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
ActionHandler MessageHandlerSvc = Get.isRegistered<ActionHandler>() ? Get.find<ActionHandler>() : Get.put(ActionHandler());

class ActionHandler extends GetxService {
  final RxList<Tuple2<String, RxDouble>> attachmentProgress = <Tuple2<String, RxDouble>>[].obs;
  final List<String> outOfOrderTempGuids = [];
  final List<String> handledNewMessages = [];
  CancelToken? latestCancelToken;

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
  
  Future<List<Message>> prepMessage(Chat c, Message m, Message? selected, String? r, {bool clearNotificationsIfFromMe = true}) async {
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

  Future<void> matchMessageWithExisting(Chat chat, String existingGuid, Message replacement, {Message? existing}) async {
    // First, try to find a matching message with the replacement's GUID.
    // We check this first because if an event came in for that GUID, we should be able to ignore
    // the API response.
    final existingReplacementMessage = Message.findOne(guid: replacement.guid);
    if (existingReplacementMessage != null) {
      Logger.debug("Found existing message with GUID ${replacement.guid}...", tag: "MessageStatus");

      if (replacement.isNewerThan(existingReplacementMessage)) {
        Logger.debug("Replacing existing message with newer message (GUID: ${replacement.guid})...", tag: "MessageStatus");
        await Message.replaceMessage(replacement.guid, replacement);
      } else {
        Logger.debug("Existing message with GUID ${replacement.guid} is newer than the replacement...", tag: "MessageStatus");
      }
      
      // Delete the temp message if it exists
      if (existingGuid != replacement.guid) {
        Logger.debug("Deleting temp message with GUID $existingGuid...", tag: "MessageStatus");
        final existingTempMessage = Message.findOne(guid: existingGuid);
        if (existingTempMessage != null) {
          Message.delete(existingTempMessage.guid!);
          if (existing != null) {
            MessagesSvc(chat.guid).removeMessage(existing);
          }
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

  Future<void> matchAttachmentWithExisting(Chat chat, String existingGuid, Attachment replacement, {Attachment? existing}) async {
    // First, try to find a matching message with the replacement's GUID.
    // We check this first because if an event came in for that GUID, we should be able to ignore
    // the API response.
    final existingReplacementMessage = await Attachment.findOneAsync(replacement.guid!);
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
      try {
        Logger.debug("Replacing original attachment with GUID $existingGuid with ${replacement.guid}...", tag: "AttachmentStatus");
        await Attachment.replaceAttachmentAsync(existingGuid, replacement);
      } catch (ex) {
        Logger.warn("Unable to find & replace attachment with GUID $existingGuid...", error: ex, tag: "AttachmentStatus");
      }
    }
  }

  Future<void> sendMessage(Chat c, Message m, Message? selected, String? r) async {
    final completer = Completer<void>();

    // Update the position of the chat in the chat list
    ChatsSvc.updateChat(c);
    
    // For reactions, add to UI immediately before sending to server
    if (r != null && m.associatedMessageGuid != null) {
      Logger.debug(
        "[ActionHandler] Adding temp reaction to UI immediately: temp=${m.guid}, parent=${m.associatedMessageGuid}, type=$r",
        tag: "MessageReactivity"
      );
      
      // Update parent message's controller with temp reaction
      final parentMwc = getActiveMwc(m.associatedMessageGuid!);
      if (parentMwc != null) {
        parentMwc.updateAssociatedMessage(m, updateHolder: true);
        Logger.debug(
          "[ActionHandler] Added temp reaction to parent controller ${m.associatedMessageGuid}",
          tag: "MessageReactivity"
        );
        
        // Emit 'added' event for the temp reaction
        parentMwc.emitUpdateEvent(MessageUpdateType.added);
      } else {
        Logger.warn(
          "[ActionHandler] Parent controller not found for temp reaction, will update when controller loads",
          tag: "MessageReactivity"
        );
      }
      
      // Trigger coordinator notification for immediate UI update
      muc.notifyMessageUpdate(c.guid, m.associatedMessageGuid!);
    } else {
      // For regular messages, emit 'added' event
      final mwc = getActiveMwc(m.guid!);
      if (mwc != null) {
        mwc.addedChanged.toggle();
        mwc.emitUpdateEvent(MessageUpdateType.added);
      }
    }
    
    if (r == null) {
      HttpSvc.sendMessage(
        c.guid,
        m.guid!,
        m.text!,
        subject: m.subject,
        method: (SettingsSvc.settings.enablePrivateAPI.value
            && SettingsSvc.settings.privateAPISend.value)
            || (m.subject?.isNotEmpty ?? false)
            || m.threadOriginatorGuid != null
            || m.expressiveSendStyleId != null
            ? "private-api" : "apple-script",
        selectedMessageGuid: m.threadOriginatorGuid,
        effectId: m.expressiveSendStyleId,
        partIndex: int.tryParse(m.threadOriginatorPart?.split(":").firstOrNull ?? ""),
        ddScan: !SettingsSvc.isMinSonomaSync && m.text!.hasUrl,
      ).then((response) async {
        final newMessage = Message.fromMap(response.data['data']);
        try {
          await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);
          
          // Emit 'sent' event when message successfully sent
          final mwc = getActiveMwc(newMessage.guid!);
          if (mwc != null) {
            mwc.sentChanged.toggle();
            mwc.emitUpdateEvent(MessageUpdateType.sent);
          }
        } catch (ex) {
          Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!", error: ex, tag: "MessageStatus");
        }

        completer.complete();
      }).catchError((error, stack) async {
        Logger.error('Failed to send message!', error: error, trace: stack);

        final tempGuid = m.guid;
        m = handleSendError(error, m);

        if (!LifecycleSvc.isAlive || !(cm.getChatController(c.guid)?.isAlive ?? false)) {
          await NotificationsSvc.createFailedToSend(c);
        }
        await Message.replaceMessage(tempGuid, m);
        completer.completeError(error);
      });
    } else {
      HttpSvc.sendTapback(c.guid, selected!.text ?? "", selected.guid!, r, partIndex: m.associatedMessagePart).then((response) async {
        final newMessage = Message.fromMap(response.data['data']);
        Logger.debug(
          "[ActionHandler] Reaction sent successfully: temp=${m.guid}, real=${newMessage.guid}, parent=${selected.guid}",
          tag: "MessageReactivity"
        );
        try {
          await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);
          
          // Trigger UI update for the parent message when reaction is replaced
          if (newMessage.associatedMessageGuid != null) {
            Logger.debug(
              "[ActionHandler] Triggering UI update for parent ${newMessage.associatedMessageGuid} after reaction replaced",
              tag: "MessageReactivity"
            );
            
            // Update the parent message's controller with the real reaction
            final parentMwc = getActiveMwc(newMessage.associatedMessageGuid!);
            if (parentMwc != null) {
              parentMwc.updateAssociatedMessage(newMessage, updateHolder: true, tempGuid: m.guid);
              Logger.debug(
                "[ActionHandler] Updated parent controller for ${newMessage.associatedMessageGuid} with real reaction ${newMessage.guid}",
                tag: "MessageReactivity"
              );
              
              // Emit 'sent' event for the reaction
              parentMwc.emitUpdateEvent(MessageUpdateType.sent);
            } else {
              Logger.warn(
                "[ActionHandler] Parent controller not found for ${newMessage.associatedMessageGuid} when updating reaction",
                tag: "MessageReactivity"
              );
            }
            
            // Trigger coordinator notification for immediate UI update
            muc.notifyMessageUpdate(c.guid, newMessage.associatedMessageGuid!);
          }
        } catch (ex) {
          Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!", error: ex, tag: "MessageStatus");
        }
        completer.complete();
      }).catchError((error, stack) async {
        Logger.error('Failed to send message!', error: error, trace: stack);

        final tempGuid = m.guid;
        m = handleSendError(error, m);

        if (!LifecycleSvc.isAlive || !(cm.getChatController(c.guid)?.isAlive ?? false)) {
          await NotificationsSvc.createFailedToSend(c);
        }
        await Message.replaceMessage(tempGuid, m);
        completer.completeError(error);
      });
    }

    return completer.future;
  }

  Future<void> sendMultipart(Chat c, Message m, Message? selected, String? r) async {
    final completer = Completer<void>();

    List<Map<String, dynamic>> parts = m.attributedBody.first.runs.map((e) => {
      "text": m.attributedBody.first.string.substring(e.range.first, e.range.first + e.range.last),
      "mention": e.attributes!.mention,
      "partIndex": e.attributes!.messagePart,
    }).toList();

    HttpSvc.sendMultipart(
      c.guid,
      m.guid!,
      parts,
      subject: m.subject,
      selectedMessageGuid: m.threadOriginatorGuid,
      effectId: m.expressiveSendStyleId,
      partIndex: int.tryParse(m.threadOriginatorPart?.split(":").firstOrNull ?? ""),
      ddScan: !SettingsSvc.isMinSonomaSync && parts.any((e) => e["text"].toString().hasUrl)
    ).then((response) async {
      final newMessage = Message.fromMap(response.data['data']);
      try {
        await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);
      } catch (ex) {
        Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!", error: ex, tag: "MessageStatus");
      }
      completer.complete();
    }).catchError((error, stack) async {
      Logger.error('Failed to send message!', error: error, trace: stack);

      final tempGuid = m.guid;
      m = handleSendError(error, m);

      if (!LifecycleSvc.isAlive || !(cm.getChatController(c.guid)?.isAlive ?? false)) {
        await NotificationsSvc.createFailedToSend(c);
      }
      await Message.replaceMessage(tempGuid, m);
      completer.completeError(error);
    });

    return completer.future;
  }
  
  Future<void> prepAttachment(Chat c, Message m) async {
    final attachment = m.attachments.first!;
    final progress = Tuple2(attachment.guid!, 0.0.obs);
    attachmentProgress.add(progress);
    // Save the attachment to storage and DB
    if (!kIsWeb) {
      String pathName = "${FilesystemSvc.appDocDir.path}/attachments/${attachment.guid}/${attachment.transferName}";
      final file = await File(pathName).create(recursive: true);
      if (attachment.mimeType == "image/gif") {
        attachment.bytes = await fixSpeedyGifs(attachment.bytes!);
      }
      await file.writeAsBytes(attachment.bytes!);
    }
    await c.addMessage(m);
  }

  Future<void> sendAttachment(Chat c, Message m, bool isAudioMessage) async {
    if (m.attachments.isEmpty || m.attachments.firstOrNull?.bytes == null) return;
    final attachment = m.attachments.first!;
    final progress = attachmentProgress.firstWhere((e) => e.item1 == attachment.guid);
    final completer = Completer<void>();
    latestCancelToken = CancelToken();
    HttpSvc.sendAttachment(
      c.guid,
      attachment.guid!,
      PlatformFile(name: attachment.transferName!, bytes: attachment.bytes, path: kIsWeb ? null : attachment.path, size: attachment.totalBytes ?? 0),
      onSendProgress: (count, total) => progress.item2.value = count / attachment.bytes!.length,
      method: (SettingsSvc.settings.enablePrivateAPI.value
          && SettingsSvc.settings.privateAPIAttachmentSend.value)
          || (m.subject?.isNotEmpty ?? false)
          || m.threadOriginatorGuid != null
          || m.expressiveSendStyleId != null
          ? "private-api" : "apple-script",
      selectedMessageGuid: m.threadOriginatorGuid,
      effectId: m.expressiveSendStyleId,
      partIndex: int.tryParse(m.threadOriginatorPart?.split(":").firstOrNull ?? ""),
      isAudioMessage: isAudioMessage,
      cancelToken: latestCancelToken,
    ).then((response) async {
      latestCancelToken = null;
      final newMessage = Message.fromMap(response.data['data']);

      for (Attachment? a in newMessage.attachments) {
        if (a == null) continue;

        matchAttachmentWithExisting(c, m.guid!, a, existing: attachment)
          .then((_) {
            MessagesSvc(c.guid).updateMessage(newMessage);
          })
          .catchError((e, stack) {
            Logger.warn("Failed to replace attachment ${a.guid}!", error: e, tag: "AttachmentStatus");
          }
        );
      }

      try {
        await matchMessageWithExisting(c, m.guid!, newMessage, existing: m);
      } catch (e) {
        Logger.warn("Failed to find message match for ${m.guid} -> ${newMessage.guid}!", error: e, tag: "MessageStatus");
      }
      attachmentProgress.removeWhere((e) => e.item1 == m.guid || e.item2 >= 1);

      completer.complete();
    }).catchError((error, stack) async {
      latestCancelToken = null;
      Logger.error('Failed to send message!', error: error, trace: stack);

      final tempGuid = m.guid;
      m = handleSendError(error, m);

      if (!LifecycleSvc.isAlive || !(cm.getChatController(c.guid)?.isAlive ?? false)) {
        await NotificationsSvc.createFailedToSend(c);
      }
      await Message.replaceMessage(tempGuid, m);
      attachmentProgress.removeWhere((e) => e.item1 == m.guid || e.item2 >= 1);
      completer.completeError(error);
    });

    return completer.future;
  }

  Future<void> handleNewMessage(Chat c, Message m, String? tempGuid, {bool checkExisting = true}) async {
    // sanity check
    if (checkExisting) {
      final existing = Message.findOne(guid: tempGuid ?? m.guid);
      if (existing != null) {
        return await handleUpdatedMessage(c, m, tempGuid, checkExisting: false);
      }
    }

    // should have been handled by the sanity check
    if (tempGuid != null) return;

    // Gets the chat from the db or server (if new).
    // If the participant list is empty, we should fetch the chat from the server to populate it.
    // If we have an ID, we can assume it's already in the database, with the proper participants.
    c = m.isParticipantEvent
      ? await handleNewOrUpdatedChat(c) 
      : kIsWeb 
        ? c 
        : (Chat.findOne(guid: c.guid) ?? await handleNewOrUpdatedChat(c));

    if (c.id != null && c.participants.isEmpty && c.handles.isEmpty) {
      Logger.info("Chat ${c.guid} has no participants, fetching updated chat data from server...", tag: "ActionHandler");
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

    // Save message to DB first to get the complete DB object
    final result = await c.addMessage(m);
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
            .preparePlayer(path: SettingsSvc.settings.receiveSoundPath.value!, volume: SettingsSvc.settings.soundVolume.value / 100)
            .then((_) => controller.startPlayer());
      }
    }

    bool isAppInactive = !LifecycleSvc.isAlive;
    bool hasUnifiedPushEndpoint = SettingsSvc.settings.endpointUnifiedPush.value != "";
    bool isNotInActiveChat = cm.activeChat == null && Get.rawRoute?.settings.name != "/";
    bool shouldSendNotification = (isAppInactive || hasUnifiedPushEndpoint || isNotInActiveChat) && shouldNotify;

    if (shouldSendNotification) {
      // We don't need to await this
      MessageHelper.handleNotification(m, c, findExisting: false);
    }
    
    // Reload the latest message from the database to ensure we have the most up-to-date data
    c.dbLatestMessage;
    
    // Reposition the chat in the chat list (more efficient than sorting the entire list)
    ChatsSvc.updateChat(c, override: true);
    
    // Trigger immediate UI update via coordinator (bypasses ObjectBox watch latency)
    muc.notifyMessageUpdate(c.guid, m.guid!);
  }

  Future<void> handleUpdatedMessage(Chat c, Message m, String? tempGuid, {bool checkExisting = true}) async {
    // sanity check
    if (checkExisting) {
      final existing = Message.findOne(guid: tempGuid ?? m.guid);
      if (existing == null) {
        return await handleNewMessage(c, m, tempGuid, checkExisting: false);
      }
    }
    Logger.info("Updated message: [${m.text}] ${m.getLastUpdate().toLowerCase()} - for chat [${c.guid}]", tag: "ActionHandler");

    // update any attachments
    for (Attachment? a in m.attachments) {
      if (a == null) continue;

      matchAttachmentWithExisting(c, tempGuid ?? m.guid!, a)
        .then((_) {
          MessagesSvc(c.guid).updateMessage(m);
        })
        .catchError((e, stack) {
          Logger.warn("Failed to replace attachment ${a.guid}!", error: e, trace: stack, tag: "AttachmentStatus");
        }
      );
    }

    // update the message in the DB
    await matchMessageWithExisting(c, tempGuid ?? m.guid!, m);
    EventDispatcherSvc.emit("message-updated-${m.guid}");
    
    // Trigger immediate UI update via coordinator (bypasses ObjectBox watch latency)
    muc.notifyMessageUpdate(c.guid, m.guid!);
  }

  Future<Chat> handleNewOrUpdatedChat(Chat partialData) async {
    // Contact fetching is now handled automatically by ContactServiceV2 on startup
    // get and return the chat from server
    return await cm.fetchChat(partialData.guid) ?? partialData;
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

          IncomingItem item = IncomingItem.fromMap(QueueType.newMessage, payload.data);
          if (useQueue) {
            inq.queue(item);
          } else {
            await MessageHandlerSvc.handleNewMessage(item.chat, item.message, item.tempGuid);
          }
        }
        return;
      case "updated-message":
        if (!isNullOrEmpty(data)) {
          final payload = ServerPayload.fromJson(data);
          IncomingItem item = IncomingItem.fromMap(QueueType.updatedMessage, payload.data);
          if (useQueue) {
            inq.queue(item);
          } else {
            await MessageHandlerSvc.handleUpdatedMessage(item.chat, item.message, item.tempGuid);
          }
        }
        return;
      case "group-name-change":
      case "participant-removed":
      case "participant-added":
      case "participant-left":
        try {
          final item = IncomingItem.fromMap(QueueType.updatedMessage, data);
          MessageHandlerSvc.handleNewOrUpdatedChat(item.chat);
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
