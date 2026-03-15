import 'dart:async';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:bluebubbles/helpers/ui/facetime_helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/interfaces/chat_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/file_utils.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;
import 'package:tuple/tuple.dart';
import 'package:universal_io/io.dart';

// ignore: non_constant_identifier_names
ActionHandler MessageHandlerSvc =
    Get.isRegistered<ActionHandler>() ? Get.find<ActionHandler>() : Get.put(ActionHandler());

class ActionHandler extends GetxService {
  final RxList<Tuple2<String, RxDouble>> attachmentProgress = <Tuple2<String, RxDouble>>[].obs;
  final List<String> outOfOrderTempGuids = [];
  final List<String> handledNewMessages = [];
  CancelToken? latestCancelToken;

  /// Tracks tempGUID -> (Chat, Completer) for completing send progress when events arrive before HTTP responses
  final Map<String, Tuple2<Chat, Completer<void>>> _sendProgressTrackers = {};

  /// Checks if a GUID has been handled.
  /// After each check, before returning, trim the list of GUIDs to the last 100.
  bool shouldNotifyForNewMessageGuid(String guid) {
    if (handledNewMessages.contains(guid)) return false;
    handledNewMessages.add(guid);

    if (handledNewMessages.length > 100) {
      handledNewMessages.removeRange(0, handledNewMessages.length - 100);
    }

    return true;
  }

  /// Register a send progress tracker for a tempGUID
  void registerSendProgressTracker(String tempGuid, Chat chat, Completer<void> completer) {
    _sendProgressTrackers[tempGuid] = Tuple2(chat, completer);
    Logger.debug("Registered send progress tracker for $tempGuid", tag: "SendProgress");
  }

  /// Complete send progress if a tracker exists for this tempGUID
  void completeSendProgressIfExists(String tempGuid) {
    final tracker = _sendProgressTrackers.remove(tempGuid);
    if (tracker != null) {
      Logger.debug("Event arrived before HTTP response for $tempGuid, completing send progress early",
          tag: "SendProgress");
      final chat = tracker.item1;
      final completer = tracker.item2;

      if (chat.sendProgress.value != 0) {
        chat.sendProgress.value = 1;
        Timer(const Duration(milliseconds: 500), () {
          chat.sendProgress.value = 0;
        });
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<List<Message>> prepMessage(Chat c, Message m, Message? selected, String? r,
      {bool clearNotificationsIfFromMe = true}) async {
    if ((m.text?.isEmpty ?? true) && (m.subject?.isEmpty ?? true) && r == null) return [];

    final List<Message> messages = <Message>[];

    if (!(await SettingsSvc.isMinBigSur) && r == null) {
      // Split URL messages on OS X to prevent message matching glitches
      String mainText = m.text!;
      String? secondaryText;
      final match = parseLinks(m.text!.replaceAll("\n", " ")).firstOrNull;
      if (match != null) {
        if (match.start == 0) {
          mainText = m.text!.substring(0, match.end).trimRight();
          secondaryText = m.text!.substring(match.end).trimLeft();
        } else if (match.end == m.text!.length) {
          mainText = m.text!.substring(0, match.start).trimRight();
          secondaryText = m.text!.substring(match.start).trimLeft();
        }
      }

      messages.add(m..text = mainText);
      if (!isNullOrEmpty(secondaryText)) {
        messages.add(Message(
          text: secondaryText,
          threadOriginatorGuid: m.threadOriginatorGuid,
          threadOriginatorPart: "${m.threadOriginatorPart ?? 0}:0:0",
          expressiveSendStyleId: m.expressiveSendStyleId,
          dateCreated: DateTime.now(),
          hasAttachments: false,
          isFromMe: true,
          handleId: 0,
        ));
      }

      for (Message message in messages) {
        message.generateTempGuid();
        await c.addMessage(message, clearNotificationsIfFromMe: clearNotificationsIfFromMe);
      }
    } else {
      m.generateTempGuid();
      await c.addMessage(m, clearNotificationsIfFromMe: clearNotificationsIfFromMe);
      messages.add(m);
    }
    return messages;
  }

  Future<void> matchMessageWithExisting(Chat chat, String existingGuid, Message replacement,
      {Message? existing}) async {
    // First, try to find a matching message with the replacement's GUID.
    // We check this first because if an event came in for that GUID, we should be able to ignore
    // the API response.
    final existingReplacementMessage = Message.findOne(guid: replacement.guid);
    if (existingReplacementMessage != null) {
      Logger.debug("Found existing message with GUID ${replacement.guid}...", tag: "MessageStatus");

      if (replacement.isNewerThan(existingReplacementMessage)) {
        Logger.debug("Replacing existing message with newer message (GUID: ${replacement.guid})...",
            tag: "MessageStatus");
        await Message.replaceMessage(replacement.guid, replacement);
      } else {
        Logger.debug("Existing message with GUID ${replacement.guid} is newer than the replacement...",
            tag: "MessageStatus");
      }

      // Delete the temp message if it exists and update the controller
      if (existingGuid != replacement.guid) {
        Logger.debug("Deleting temp message with GUID $existingGuid...", tag: "MessageStatus");
        final existingTempMessage = Message.findOne(guid: existingGuid);
        if (existingTempMessage != null) {
          Message.delete(existingTempMessage.guid!);
          // Update the controller to use the new GUID instead of removing it
          // This keeps the UI reactive and prevents the "Instance already removed" error
          MessagesSvc(chat.guid).updateMessage(replacement, oldGuid: existingGuid);
        }
      }
    } else {
      try {
        // If we didn't find a matching message with the replacement's GUID, replace the existing message.
        Logger.debug("Replacing message with GUID $existingGuid with ${replacement.guid}...", tag: "MessageStatus");
        await Message.replaceMessage(existingGuid, replacement);
      } catch (ex) {
        Logger.warn("Unable to find & replace message with GUID $existingGuid...", tag: "MessageStatus", error: ex);
      }
    }
  }

  Future<void> matchAttachmentWithExisting(Chat chat, String existingGuid, Attachment replacement,
      {Attachment? existing}) async {
    Logger.test("matchAttachmentWithExisting: existingGuid=$existingGuid, replacement.guid=${replacement.guid}", tag: "AttachmentStatus");
    // First, try to find a matching message with the replacement's GUID.
    // We check this first because if an event came in for that GUID, we should be able to ignore
    // the API response.
    final existingReplacementMessage = await Attachment.findOneAsync(replacement.guid!);
    Logger.test("matchAttachmentWithExisting: existingReplacement (${replacement.guid}) found=${existingReplacementMessage != null}", tag: "AttachmentStatus");
    if (existingReplacementMessage != null) {
      Logger.debug("Replacing existing attachment with GUID ${replacement.guid}...", tag: "AttachmentStatus");
      await Attachment.replaceAttachmentAsync(replacement.guid, replacement);

      // Delete the temp message if it exists
      if (existingGuid != replacement.guid) {
        Logger.debug("Deleting temp attachment with GUID $existingGuid...", tag: "AttachmentStatus");
        final existingTempMessage = await Attachment.findOneAsync(existingGuid);
        if (existingTempMessage != null) {
          await Attachment.deleteAsync(existingTempMessage.guid!);
        }
      }
    } else {
      // Temp attachment not yet replaced by a socket event — look it up directly
      final existingTemp = await Attachment.findOneAsync(existingGuid);
      Logger.test("matchAttachmentWithExisting: existingTemp ($existingGuid) found=${existingTemp != null}", tag: "AttachmentStatus");
      try {
        Logger.debug("Replacing original attachment with GUID $existingGuid with ${replacement.guid}...",
            tag: "AttachmentStatus");
        await Attachment.replaceAttachmentAsync(existingGuid, replacement);
      } catch (ex) {
        Logger.warn("Unable to find & replace attachment with GUID $existingGuid...",
            error: ex, tag: "AttachmentStatus");
      }
    }
  }

  Future<void> sendMessage(Chat c, Message m, Message? selected, String? r) async {
    final completer = Completer<void>();

    // Register send progress tracker for this message
    registerSendProgressTracker(m.guid!, c, completer);

    // Update the position of the chat in the chat list
    ChatsSvc.updateChat(c);

    // For reactions, add to UI immediately before sending to server
    if (r != null && m.associatedMessageGuid != null) {
      // Update parent message's MessageState with temp reaction
      final parentState = MessagesSvc(c.guid).getMessageStateIfExists(m.associatedMessageGuid!);
      if (parentState != null) {
        parentState.addAssociatedMessageInternal(m);
      }
    }

    if (r == null) {
      HttpSvc.sendMessage(
        c.guid,
        m.guid!,
        m.text!,
        subject: m.subject,
        method: (SettingsSvc.settings.enablePrivateAPI.value && SettingsSvc.settings.privateAPISend.value) ||
                (m.subject?.isNotEmpty ?? false) ||
                m.threadOriginatorGuid != null ||
                m.expressiveSendStyleId != null
            ? "private-api"
            : "apple-script",
        selectedMessageGuid: m.threadOriginatorGuid,
        effectId: m.expressiveSendStyleId,
        partIndex: int.tryParse(m.threadOriginatorPart?.split(":").firstOrNull ?? ""),
        ddScan: !SettingsSvc.isMinSonomaSync && m.text!.hasUrl,
      ).then((response) async {
        completeSendProgressIfExists(m.guid!);

        final newMessage = Message.fromMap(response.data['data']);
        try {
          await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);
        } catch (ex) {
          Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!",
              error: ex, tag: "MessageStatus");
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      }).catchError((error, stack) async {
        completeSendProgressIfExists(m.guid!);

        Logger.error('Failed to send message!', error: error, trace: stack);

        final tempGuid = m.guid;
        m = handleSendError(error, m);

        if (!LifecycleSvc.isAlive || !(ChatsSvc.getChatController(c.guid)?.isAlive.value ?? false)) {
          await NotificationsSvc.createFailedToSend(c);
        }
        await Message.replaceMessage(tempGuid, m);
        completer.completeError(error);
      });
    } else {
      HttpSvc.sendTapback(c.guid, selected!.text ?? "", selected.guid!, r, partIndex: m.associatedMessagePart)
          .then((response) async {
        completeSendProgressIfExists(m.guid!);

        final newMessage = Message.fromMap(response.data['data']);
        Logger.debug(
            "[ActionHandler] Reaction sent successfully: temp=${m.guid}, real=${newMessage.guid}, parent=${selected.guid}",
            tag: "MessageReactivity");

        try {
          await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);

          // Trigger UI update for the parent message when reaction is replaced
          if (newMessage.associatedMessageGuid != null) {
            Logger.debug(
                "[ActionHandler] Triggering UI update for parent ${newMessage.associatedMessageGuid} after reaction replaced",
                tag: "MessageReactivity");

            // Update the parent message's MessageState with the real reaction
            final parentState = MessagesSvc(c.guid).getMessageStateIfExists(newMessage.associatedMessageGuid!);
            if (parentState != null) {
              parentState.updateAssociatedMessageInternal(newMessage, tempGuid: m.guid);
              Logger.debug(
                  "[ActionHandler] Updated parent MessageState for ${newMessage.associatedMessageGuid} with real reaction ${newMessage.guid}",
                  tag: "MessageReactivity");
            } else {
              Logger.warn(
                  "[ActionHandler] Parent MessageState not found for ${newMessage.associatedMessageGuid} when updating reaction",
                  tag: "MessageReactivity");
            }
          }
        } catch (ex) {
          Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!",
              error: ex, tag: "MessageStatus");
        }

        if (!completer.isCompleted) {
          completer.complete();
        }
      }).catchError((error, stack) async {
        completeSendProgressIfExists(m.guid!);

        Logger.error('Failed to send message!', error: error, trace: stack);

        m = handleSendError(error, m);

        if (!LifecycleSvc.isAlive || !(ChatsSvc.getChatController(c.guid)?.isAlive.value ?? false)) {
          await NotificationsSvc.createFailedToSend(c);
        }
        await Message.replaceMessage(m.guid, m);

        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      });
    }

    return completer.future;
  }

  Future<void> sendMultipart(Chat c, Message m, Message? selected, String? r) async {
    final completer = Completer<void>();

    // Register send progress tracker for this message
    registerSendProgressTracker(m.guid!, c, completer);

    List<Map<String, dynamic>> parts = m.attributedBody.first.runs
        .map((e) => {
              "text": m.attributedBody.first.string.substring(e.range.first, e.range.first + e.range.last),
              "mention": e.attributes!.mention,
              "partIndex": e.attributes!.messagePart,
            })
        .toList();

    HttpSvc.sendMultipart(c.guid, m.guid!, parts,
            subject: m.subject,
            selectedMessageGuid: m.threadOriginatorGuid,
            effectId: m.expressiveSendStyleId,
            partIndex: int.tryParse(m.threadOriginatorPart?.split(":").firstOrNull ?? ""),
            ddScan: !SettingsSvc.isMinSonomaSync && parts.any((e) => e["text"].toString().hasUrl))
        .then((response) async {
      completeSendProgressIfExists(m.guid!);

      final newMessage = Message.fromMap(response.data['data']);
      try {
        await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);
      } catch (ex) {
        Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!",
            error: ex, tag: "MessageStatus");
      }

      if (!completer.isCompleted) {
        completer.complete();
      }
    }).catchError((error, stack) async {
      completeSendProgressIfExists(m.guid!);
      Logger.error('Failed to send message!', error: error, trace: stack);

      m = handleSendError(error, m);

      if (!LifecycleSvc.isAlive || !(ChatsSvc.getChatController(c.guid)?.isAlive.value ?? false)) {
        await NotificationsSvc.createFailedToSend(c);
      }
      await Message.replaceMessage(m.guid!, m);

      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    return completer.future;
  }

  Future<void> prepAttachment(Chat c, Message m) async {
    final attachment = m.attachments.first!;
    final progress = Tuple2(attachment.guid!, 0.0.obs);
    attachmentProgress.add(progress);
    // Save the attachment to storage and DB
    if (!kIsWeb) {
      // Get source path from metadata
      final sourcePath = attachment.metadata?['source_path'] as String?;
      Logger.debug("prepAttachment: sourcePath=$sourcePath, hasBytes=${attachment.bytes != null}", tag: "Attachment");
      if (sourcePath == null && attachment.bytes == null) {
        throw Exception("Attachment has no source_path in metadata or bytes");
      }

      // Use attachment.path getter for destination
      final destinationPath = attachment.path;
      final destinationFile = await File(destinationPath).create(recursive: true);

      if (sourcePath != null) {
        // Copy file from source to destination (avoid loading into memory)
        if (attachment.mimeType == "image/gif") {
          // GIFs need processing, so we load bytes only for this case
          final bytes = await File(sourcePath).readAsBytes();
          final optimizedBytes = await fixSpeedyGifs(bytes);
          await destinationFile.writeAsBytes(optimizedBytes);
        } else {
          // For all other files, just copy without loading into memory
          await File(sourcePath).copy(destinationPath);
        }
      } else {
        // Bytes-only attachment (clipboard paste / GIF keyboard) — write directly to disk
        Uint8List bytesToWrite = attachment.bytes!;
        if (attachment.mimeType == "image/gif") {
          bytesToWrite = await fixSpeedyGifs(bytesToWrite);
        }
        await destinationFile.writeAsBytes(bytesToWrite);
        attachment.bytes = null; // free memory now that the file is on disk
      }

      // Load image properties for outgoing attachments to ensure proper display in UI
      if (attachment.mimeStart == "image") {
        try {
          await AttachmentsSvc.loadImageProperties(attachment, actualPath: destinationPath);
        } catch (ex) {
          Logger.warn("Failed to load image properties for outgoing attachment", error: ex);
        }
      }

      // Mark attachment as downloaded since it's now on disk
      attachment.isDownloaded = true;
    }
    Logger.test("prepAttachment: calling addMessage with attachment.guid=${attachment.guid}, m.attachments.length=${m.attachments.length}", tag: "Attachment");
    await c.addMessage(m);
    // Verify attachment was saved to DB
    final savedAttachment = await Attachment.findOneAsync(attachment.guid!);
    Logger.test("prepAttachment: after addMessage, attachment ${attachment.guid} found in DB = ${savedAttachment != null}", tag: "Attachment");
  }

  Future<void> sendAttachment(Chat c, Message m, bool isAudioMessage) async {
    if (m.attachments.isEmpty) return;
    final attachment = m.attachments.first!;

    // Read bytes from attachment.path (where prepAttachment copied it)
    Uint8List? bytes;
    if (!kIsWeb) {
      try {
        bytes = await File(attachment.path).readAsBytes();
      } catch (ex) {
        Logger.error("Failed to read attachment bytes from path for sending", error: ex);
        return;
      }
    }

    if (bytes == null) return;

    final progress = attachmentProgress.firstWhere((e) => e.item1 == attachment.guid);
    final completer = Completer<void>();

    // Register send progress tracker for this message
    registerSendProgressTracker(m.guid!, c, completer);

    latestCancelToken = CancelToken();
    HttpSvc.sendAttachment(
      c.guid,
      attachment.guid!,
      PlatformFile(
          name: attachment.transferName!,
          bytes: bytes,
          path: kIsWeb ? null : attachment.path,
          size: attachment.totalBytes ?? 0),
      onSendProgress: (count, total) => progress.item2.value = count / bytes!.length,
      method: (SettingsSvc.settings.enablePrivateAPI.value && SettingsSvc.settings.privateAPIAttachmentSend.value) ||
              (m.subject?.isNotEmpty ?? false) ||
              m.threadOriginatorGuid != null ||
              m.expressiveSendStyleId != null
          ? "private-api"
          : "apple-script",
      selectedMessageGuid: m.threadOriginatorGuid,
      effectId: m.expressiveSendStyleId,
      partIndex: int.tryParse(m.threadOriginatorPart?.split(":").firstOrNull ?? ""),
      isAudioMessage: isAudioMessage,
      cancelToken: latestCancelToken,
    ).then((response) async {
      completeSendProgressIfExists(m.guid!);

      latestCancelToken = null;
      final newMessage = Message.fromMap(response.data['data']);

      for (Attachment? a in newMessage.attachments) {
        if (a == null) continue;

        matchAttachmentWithExisting(c, m.guid!, a, existing: attachment).then((_) {
          MessagesSvc(c.guid).updateMessage(newMessage);
        }).catchError((e, stack) {
          Logger.warn("Failed to replace attachment ${a.guid}!", error: e, tag: "AttachmentStatus");
        });
      }

      try {
        await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);
      } catch (e) {
        Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!",
            error: e, tag: "MessageStatus");
      }
      attachmentProgress.removeWhere((e) => e.item1 == m.guid || e.item2 >= 1);

      if (!completer.isCompleted) {
        completer.complete();
      }
    }).catchError((error, stack) async {
      completeSendProgressIfExists(m.guid!);

      latestCancelToken = null;
      Logger.error('Failed to send message!', error: error, trace: stack);

      m = handleSendError(error, m);

      if (!LifecycleSvc.isAlive || !(ChatsSvc.getChatController(c.guid)?.isAlive.value ?? false)) {
        await NotificationsSvc.createFailedToSend(c);
      }
      await Message.replaceMessage(m.guid!, m);
      attachmentProgress.removeWhere((e) => e.item1 == m.guid || e.item2 >= 1);

      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    return completer.future;
  }

  Future<void> handleNewMessage(Chat c, Message m, String? tempGuid, {bool checkExisting = true}) async {
    if (tempGuid != null) {
      completeSendProgressIfExists(tempGuid);
    }

    // sanity check - try tempGuid first, then fallback to m.guid
    if (checkExisting) {
      Message? existing;
      if (tempGuid != null) {
        existing = Message.findOne(guid: tempGuid);
      }
      if (existing == null) {
        existing = Message.findOne(guid: m.guid);
      }
      if (existing != null) {
        return await handleUpdatedMessage(c, m, tempGuid, checkExisting: false);
      }
    }

    // Gets the chat from the db or server (if new).
    // If the participant list is empty, we should fetch the chat from the server to populate it.
    // If we have an ID, we can assume it's already in the database, with the proper participants.
    c = m.isParticipantEvent
        ? await handleNewOrUpdatedChat(c)
        : kIsWeb
            ? c
            : (Chat.findOne(guid: c.guid) ?? await handleNewOrUpdatedChat(c));

    if (c.id != null && c.participants.isEmpty && c.handles.isEmpty) {
      Logger.info("Chat ${c.guid} has no participants, fetching updated chat data from server...",
          tag: "ActionHandler");
      c = await handleNewOrUpdatedChat(c);
    }

    // New chat incoming, we should sync the data to the database.
    // We should get a valid object back. If we don't, log it.
    if (c.id == null) {
      c = (await ChatInterface.bulkSyncChats(chatsData: [c.toMap()])).firstOrNull ?? c;
      if (c.id == null) {
        Logger.warn("Failed to sync new chat for incoming message ${m.guid}!", tag: "ActionHandler");
      }
    }

    // Save message to DB first to get the complete DB object.
    // Only clear the notification from me if it's not a reaction.
    // If it's a reaction, we want to keep the notification. Especially in
    // cases where the reaction was sent from a notification.
    final clearNotificationFromMe = (m.isFromMe ?? false) && m.associatedMessageGuid == null;
    final result = await c.addMessage(m, clearNotificationsIfFromMe: clearNotificationFromMe);
    m = result.item1;

    // Display notification if needed
    bool shouldNotify = shouldNotifyForNewMessageGuid(m.guid!);
    if (!shouldNotify) {
      Logger.info("Not notifying for already handled new message with GUID ${m.guid}...", tag: "ActionHandler");
    } else if (SettingsSvc.settings.receiveSoundPath.value != null && SettingsSvc.settings.soundVolume.value != 0) {
      if (kIsDesktop && LifecycleSvc.isAlive) {
        Player player = Player();
        player.stream.completed
            .firstWhere((completed) => completed)
            .then((_) async => Future.delayed(const Duration(milliseconds: 500), () async => await player.dispose()));
        await player.setVolume(SettingsSvc.settings.soundVolume.value.toDouble());
        await player.open(Media(SettingsSvc.settings.receiveSoundPath.value!));
      } else if (!kIsDesktop && !kIsWeb) {
        PlayerController controller = PlayerController();
        await controller
            .preparePlayer(
                path: SettingsSvc.settings.receiveSoundPath.value!,
                volume: SettingsSvc.settings.soundVolume.value / 100)
            .then((_) => controller.startPlayer());
      }
    }

    // Create notification
    // This will no-op if notifications aren't allowed, the message is from me, or other conditions aren't met
    NotificationsSvc.tryCreateNewMessageNotification(m, c);

    // Reload the latest message from the database to ensure we have the most up-to-date data
    c.dbLatestMessage;

    // Reposition the chat in the chat list (more efficient than sorting the entire list)
    ChatsSvc.updateChat(c, override: true);
  }

  Future<void> handleUpdatedMessage(Chat c, Message m, String? tempGuid, {bool checkExisting = true}) async {
    if (tempGuid != null) {
      completeSendProgressIfExists(tempGuid);
    }

    // sanity check - try tempGuid first, then fallback to m.guid
    if (checkExisting) {
      Message? existing;
      if (tempGuid != null) {
        existing = Message.findOne(guid: tempGuid);
      }
      if (existing == null) {
        existing = Message.findOne(guid: m.guid);
      }
      if (existing == null) {
        return await handleNewMessage(c, m, tempGuid, checkExisting: false);
      }
    }

    Logger.info("Updated message: [${m.text}] ${m.getLastUpdate().toLowerCase()} - for chat [${c.guid}]",
        tag: "ActionHandler");

    // update any attachments
    for (Attachment? a in m.attachments) {
      if (a == null) continue;

      matchAttachmentWithExisting(c, tempGuid ?? m.guid!, a).then((_) {
        MessagesSvc(c.guid).updateMessage(m);
      }).catchError((e, stack) {
        Logger.warn("Failed to replace attachment ${a.guid}!", error: e, trace: stack, tag: "AttachmentStatus");
      });
    }

    // update the message in the DB
    await matchMessageWithExisting(c, tempGuid ?? m.guid!, m);

    // Update MessagesService which will update MessageState
    // This ensures UI gets updated without needing DB watches on each message
    MessagesSvc(c.guid).updateMessage(m, oldGuid: tempGuid);
  }

  Future<Chat> handleNewOrUpdatedChat(Chat partialData) async {
    // Contact fetching is now handled automatically by ContactServiceV2 on startup
    // get and return the chat from server
    return await ChatsSvc.fetchChat(partialData.guid) ?? partialData;
  }

  Future<void> handleFaceTimeStatusChange(Map<String, dynamic> data) async {
    if (data["status_id"] == null) return;
    final int statusId = data["status_id"] as int;
    if (statusId == 4) {
      await ActionHandler().handleIncomingFaceTimeCall(data);
    } else if (statusId == 6 && data["uuid"] != null) {
      hideFaceTimeOverlay(data["uuid"]!);
    }
  }

  Future<void> handleIncomingFaceTimeCall(Map<String, dynamic> data) async {
    Logger.info("Handling incoming FaceTime call");
    final callUuid = data["uuid"];
    String? address = data["handle"]?["address"];
    String caller = data["address"] ?? "Unknown Number";
    bool isAudio = data["is_audio"];
    Uint8List? chatIcon;

    // Find the contact info for the caller
    // Load the contact's avatar & name
    if (address != null) {
      ContactV2? contact = await ContactsSvcV2.getContact(address);
      if (contact?.avatarPath != null) {
        chatIcon = await ContactsSvcV2.getContactAvatar(contact!.nativeContactId);
      }
      caller = contact?.displayName ?? caller;
    }

    if (!LifecycleSvc.isAlive) {
      if (kIsDesktop) {
        await showFaceTimeOverlay(callUuid, caller, chatIcon, isAudio);
      }
      await NotificationsSvc.createIncomingFaceTimeNotification(callUuid, caller, chatIcon, isAudio);
    } else {
      await showFaceTimeOverlay(callUuid, caller, chatIcon, isAudio);
    }
  }

  Future<void> handleIncomingFaceTimeCallLegacy(Map<String, dynamic> data) async {
    Logger.info("Handling incoming FaceTime call (legacy)");
    String? address = data["caller"];
    String? caller = address;
    Uint8List? chatIcon;

    // Find the contact info for the caller
    // Load the contact's avatar & name
    if (address != null) {
      ContactV2? contact = await ContactsSvcV2.getContact(address);
      if (contact?.avatarPath != null) {
        chatIcon = await ContactsSvcV2.getContactAvatar(contact!.nativeContactId);
      }
      caller = contact?.displayName ?? caller;
      await NotificationsSvc.createIncomingFaceTimeNotification(null, caller!, chatIcon, false);
    }
  }

  Future<void> handleEvent(String event, Map<String, dynamic> data, String source, {bool useQueue = true}) async {
    Logger.info("Received $event from $source");
    switch (event) {
      case "new-message":
        if (!isNullOrEmpty(data)) {
          final payload = ServerPayload.fromJson(data);
          final message = Message.fromMap(payload.data);
          if (message.isFromMe!) {
            if (payload.data['tempGuid'] == null) {
              MessageHandlerSvc.outOfOrderTempGuids.add(message.guid!);
              await Future.delayed(const Duration(milliseconds: 500));
              if (!MessageHandlerSvc.outOfOrderTempGuids.contains(message.guid!)) return;
            } else {
              MessageHandlerSvc.outOfOrderTempGuids.remove(message.guid!);
            }
          }

          await IncomingMsgHandler.handle(IncomingPayload(
            type: MessageEventType.newMessage,
            source: MessageSource.socket,
            chat: Chat.fromMap(payload.data['chats'].first.cast<String, Object>()),
            message: message,
            tempGuid: payload.data['tempGuid'],
          ), front: !useQueue);
        }
        return;
      case "updated-message":
        if (!isNullOrEmpty(data)) {
          final payload = ServerPayload.fromJson(data);
          await IncomingMsgHandler.handle(IncomingPayload(
            type: MessageEventType.updatedMessage,
            source: MessageSource.socket,
            chat: Chat.fromMap(payload.data['chats'].first.cast<String, Object>()),
            message: Message.fromMap(payload.data),
            tempGuid: payload.data['tempGuid'],
          ), front: !useQueue);
        }
        return;
      case "group-name-change":
      case "participant-removed":
      case "participant-added":
      case "participant-left":
        try {
          MessageHandlerSvc.handleNewOrUpdatedChat(Chat.fromMap(data['chats'].first.cast<String, Object>()));
        } catch (_) {}
        return;
      case "chat-read-status-changed":
        Chat? chat = Chat.findOne(guid: data["chatGuid"]);
        if (chat != null && (data["read"] == true || data["read"] == false)) {
          chat.toggleHasUnreadAsync(!data["read"]!, privateMark: false);
        }
        return;
      case "typing-indicator":
        final chat = ChatsSvc.findChatByGuid(data["guid"]);
        if (chat != null) {
          final controller = cvc(chat);
          controller.showTypingIndicator.value = data["display"];
        }
        return;
      case "incoming-facetime":
        Logger.info("Received legacy incoming FaceTime call");
        await handleIncomingFaceTimeCallLegacy(data);
        return;
      case "ft-call-status-changed":
        Logger.info("Received FaceTime call status change");
        await handleFaceTimeStatusChange(data);
        return;
      case "imessage-aliases-removed":
        Logger.info("Alias(es) removed ${data["aliases"]}");
        await NotificationsSvc.createAliasesRemovedNotification((data["aliases"] as List).cast<String>());
        return;
      default:
        return;
    }
  }
}
