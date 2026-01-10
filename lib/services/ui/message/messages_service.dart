import 'dart:async';

import 'package:bluebubbles/helpers/types/helpers/message_helper.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/ui/message/message_update_coordinator.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:rxdart/rxdart.dart';

// ignore: non_constant_identifier_names
MessagesService MessagesSvc(String chatGuid) => Get.isRegistered<MessagesService>(tag: chatGuid)
    ? Get.find<MessagesService>(tag: chatGuid)
    : Get.put(MessagesService(chatGuid), tag: chatGuid);

String? lastReloadedChat() =>
    Get.isRegistered<String>(tag: 'lastReloadedChat') ? Get.find<String>(tag: 'lastReloadedChat') : null;

class MessagesService extends GetxController {
  static final Map<String, Size> cachedBubbleSizes = {};
  late Chat chat;
  late StreamSubscription countSub;
  final ChatMessages struct = ChatMessages();
  late Function(Message) newFunc;
  late Function(Message, {String? oldGuid}) updateFunc;
  late Function(Message) removeFunc;
  late Function(String) jumpToMessage;

  final String tag;
  MessagesService(this.tag);

  int currentCount = 0;
  bool isFetching = false;
  bool _init = false;
  String? method;

  /// Granular reactivity map to track individual message updates
  /// Key: message guid, Value: timestamp of last update
  final RxMap<String, int> messageUpdateTrigger = <String, int>{}.obs;

  Message? get mostRecentSent => (struct.messages.where((e) => e.isFromMe!).toList()..sort(Message.sort)).firstOrNull;

  Message? get mostRecent => (struct.messages.toList()..sort(Message.sort)).firstOrNull;

  Message? get mostRecentReceived =>
      (struct.messages.where((e) => !e.isFromMe!).toList()..sort(Message.sort)).firstOrNull;

  void init(Chat c, Function(Message) onNewMessage, Function(Message, {String? oldGuid}) onUpdatedMessage,
      Function(Message) onDeletedMessage, Function(String) jumpToMessageFunc) {
    chat = c;
    Get.put<String>(tag, tag: 'lastReloadedChat');

    updateFunc = onUpdatedMessage;
    removeFunc = onDeletedMessage;
    newFunc = onNewMessage;
    jumpToMessage = jumpToMessageFunc;

    // watch for new messages
    if (!_init) {
      if (chat.id != null) {
        final countQuery = (Database.messages.query(Message_.dateDeleted.isNull())
              ..link(Message_.chat, Chat_.id.equals(chat.id!))
              ..order(Message_.id, flags: Order.descending))
            .watch(triggerImmediately: true);

        // Debounce the stream to batch rapid changes (reduces processing overhead)
        countSub = countQuery.debounceTime(const Duration(milliseconds: 100)).listen((event) async {
          if (!SettingsSvc.settings.finishedSetup.value) return;
          final newCount = event.count();
          if (!isFetching && newCount > currentCount && currentCount != 0) {
            event.limit = newCount - currentCount;
            final messages = event.find();
            event.limit = 0;
            for (Message message in messages) {
              await _handleNewMessage(message);
            }
          }
          currentCount = newCount;
        });
      } else if (kIsWeb) {
        countSub = WebListeners.newMessage.listen((tuple) {
          if (tuple.item2?.guid == chat.guid) {
            _handleNewMessage(tuple.item1);
          }
        });
      }
    }
    _init = true;
  }

  @override
  void onClose() {
    if (_init) {
      countSub.cancel();
    }
    _init = false;
    super.onClose();
  }

  void close({force = false}) {
    String? lastChat = lastReloadedChat();
    if (force || lastChat != tag) {
      Get.delete<MessagesService>(tag: tag);
    }

    struct.flush();
  }

  void reload() {
    Get.put<String>(tag, tag: 'lastReloadedChat');
    Get.reload<MessagesService>(tag: tag);
  }

  Future<void> _handleNewMessage(Message message) async {
    if (message.hasAttachments && !kIsWeb) {
      message.attachments = List<Attachment>.from(message.dbAttachments);
      // we may need an artificial delay in some cases since the attachment
      // relation is initialized after message itself is saved
      if (message.attachments.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 250));
        message.attachments = List<Attachment>.from(message.dbAttachments);
      }
    }

    // Add to struct first to ensure it's available for lookups
    struct.addMessages([message]);

    // Handle reactions with improved reactivity
    if (message.associatedMessageGuid != null) {
      final parentMessage = struct.getMessage(message.associatedMessageGuid!);
      if (parentMessage != null) {
        // Add to parent's associated messages list
        parentMessage.associatedMessages.add(message);

        // Get or create the controller - this ensures it exists
        final mwcInstance = getActiveMwc(message.associatedMessageGuid!);
        if (mwcInstance != null) {
          // Controller exists, update it
          mwcInstance.updateAssociatedMessage(message);
          Logger.debug("Updated reaction ${message.guid} on parent ${message.associatedMessageGuid}",
              tag: "MessageReactivity");
        } else {
          // Controller doesn't exist yet, queue for retry
          Logger.warn("Parent controller not ready for reaction ${message.guid}, will retry", tag: "MessageReactivity");
          Future.delayed(const Duration(milliseconds: 100), () {
            final retryMwc = getActiveMwc(message.associatedMessageGuid!);
            if (retryMwc != null) {
              retryMwc.updateAssociatedMessage(message);
              Logger.debug(
                  "Retry successful: Updated reaction ${message.guid} on parent ${message.associatedMessageGuid}",
                  tag: "MessageReactivity");
              // Trigger immediate UI update via coordinator
              muc.notifyMessageUpdate(chat.guid, message.associatedMessageGuid!);
            } else {
              Logger.error("Retry failed: Parent controller still not found for reaction ${message.guid}",
                  tag: "MessageReactivity");
            }
          });
        }

        // Trigger immediate UI update via coordinator (bypasses ObjectBox watch latency)
        muc.notifyMessageUpdate(chat.guid, message.associatedMessageGuid!);
      } else {
        Logger.warn("Parent message not found for reaction ${message.guid} (parent: ${message.associatedMessageGuid})",
            tag: "MessageReactivity");
      }
    }

    // Handle thread originators with improved reactivity
    if (message.threadOriginatorGuid != null) {
      final mwcInstance = getActiveMwc(message.threadOriginatorGuid!);
      if (mwcInstance != null) {
        mwcInstance.updateThreadOriginator(message);
        // Trigger immediate UI update for thread count
        muc.notifyMessageUpdate(chat.guid, message.threadOriginatorGuid!);
      } else {
        // Queue retry for thread originator
        Future.delayed(const Duration(milliseconds: 100), () {
          getActiveMwc(message.threadOriginatorGuid!)?.updateThreadOriginator(message);
          muc.notifyMessageUpdate(chat.guid, message.threadOriginatorGuid!);
        });
      }
    }

    // Only call newFunc for non-reactions (regular messages)
    if (message.associatedMessageGuid == null) {
      newFunc.call(message);
    }
  }

  void updateMessage(Message updated, {String? oldGuid}) {
    final toUpdate = struct.getMessage(oldGuid ?? updated.guid!);
    if (toUpdate == null) return;
    updated = updated.mergeWith(toUpdate);
    struct.removeMessage(oldGuid ?? updated.guid!);
    struct.removeAttachments(toUpdate.attachments.map((e) => e!.guid!));
    struct.addMessages([updated]);

    // Trigger granular update for this specific message
    messageUpdateTrigger[updated.guid!] = DateTime.now().millisecondsSinceEpoch;

    updateFunc.call(updated, oldGuid: oldGuid);
  }

  void removeMessage(Message toRemove) {
    struct.removeMessage(toRemove.guid!);
    struct.removeAttachments(toRemove.attachments.map((e) => e!.guid!));
    messageUpdateTrigger.remove(toRemove.guid!);
    removeFunc.call(toRemove);
  }

  /// Check if a specific message has been updated (for granular Obx widgets)
  bool isMessageUpdated(String guid) {
    return messageUpdateTrigger.containsKey(guid);
  }

  /// Trigger an update for a specific message (useful for reactions, read receipts, etc.)
  void triggerMessageUpdate(String guid) {
    messageUpdateTrigger[guid] = DateTime.now().millisecondsSinceEpoch;
  }

  /// Clear the update flag for a message after it's been processed
  void clearMessageUpdate(String guid) {
    messageUpdateTrigger.remove(guid);
  }

  Future<bool> loadChunk(int offset, ConversationViewController controller, {int limit = 25}) async {
    isFetching = true;
    List<Message> _messages = [];

    // Adjust offset because reactions _are_ messages. We just separate them out in the struct.
    offset = offset + struct.reactions.length;

    try {
      Logger.debug("[loadChunk] Starting to load messages (offset: $offset, limit: $limit)", tag: "MessageReactivity");

      _messages = await Chat.getMessagesAsync(
        chat,
        offset: offset,
        limit: limit,
        onSupplementalDataLoaded: () {
          // Phase 2 complete - reactions have been loaded
          Logger.info("[loadChunk] Supplemental data loaded, triggering UI updates for ${_messages.length} messages",
              tag: "MessageReactivity");

          // Trigger UI updates for each message that has reactions
          for (final message in _messages) {
            if (message.associatedMessages.isNotEmpty) {
              Logger.debug(
                  "[loadChunk] Message ${message.guid} has ${message.associatedMessages.length} reactions, triggering update",
                  tag: "MessageReactivity");

              // Get the controller if it exists and update it
              final mwcInstance = getActiveMwc(message.guid!);
              if (mwcInstance != null) {
                // Update the controller with the new associated messages
                for (final reaction in message.associatedMessages) {
                  mwcInstance.updateAssociatedMessage(reaction, updateHolder: true);
                }
                Logger.debug("[loadChunk] Updated controller for ${message.guid} with reactions",
                    tag: "MessageReactivity");
              } else {
                Logger.warn(
                    "[loadChunk] No controller found for ${message.guid} with ${message.associatedMessages.length} reactions",
                    tag: "MessageReactivity");
              }

              // Trigger immediate UI update via coordinator
              muc.notifyMessageUpdate(chat.guid, message.guid!);
            }
          }
        },
      );

      Logger.debug("[loadChunk] Loaded ${_messages.length} messages from local DB");
      if (_messages.isEmpty) {
        // get from server and save
        final fromServer = await ChatsSvc.getMessages(chat.guid, offset: offset, limit: limit);
        final temp = await MessageHelper.bulkAddMessages(chat, fromServer, checkForLatestMessageText: false);
        if (!kIsWeb) {
          // re-fetch from the DB because it will find handles / associated messages for us
          _messages = await Chat.getMessagesAsync(chat, offset: offset, limit: limit);
        } else {
          final reactions = temp.where((e) => e.associatedMessageGuid != null);
          for (Message m in reactions) {
            final associatedMessage = temp.firstWhereOrNull((element) => element.guid == m.associatedMessageGuid);
            associatedMessage?.hasReactions = true;
            associatedMessage?.associatedMessages.add(m);
          }
          _messages = temp;
        }
      }
    } catch (e, s) {
      return Future.error(e, s);
    }

    struct.addMessages(_messages);

    // get thread originators
    for (Message m in _messages.where((e) => e.threadOriginatorGuid != null)) {
      // see if the originator is already loaded
      final guid = m.threadOriginatorGuid!;
      if (struct.getMessage(guid) != null) continue;
      // if not, fetch local and add to data
      final threadOriginator = Message.findOne(guid: guid);
      if (threadOriginator != null) {
        // create the controller so it can be rendered in a reply bubble
        final c = mwc(threadOriginator);
        c.cvController = controller;
        struct.addThreadOriginator(threadOriginator);
      }
    }

    // this indicates an audio message was kept by the recipient
    // run this every time more messages are loaded just in case
    for (Message m in struct.messages.where((e) => e.itemType == 5 && e.subject != null)) {
      final otherMessage = struct.getMessage(m.subject!);
      if (otherMessage != null) {
        final otherMwc = getActiveMwc(m.subject!) ?? mwc(otherMessage);
        otherMwc.audioWasKept.value = m.dateCreated;
      }
    }

    isFetching = false;
    return _messages.isNotEmpty;
  }

  Future<void> loadSearchChunk(Message around, SearchMethod method) async {
    isFetching = true;
    List<Message> _messages = [];
    if (method == SearchMethod.local) {
      _messages = await Chat.getMessagesAsync(chat, searchAround: around.dateCreated!.millisecondsSinceEpoch);
      _messages.add(around);
      _messages.sort(Message.sort);
      struct.addMessages(_messages);
    } else {
      final beforeResponse = await ChatsSvc.getMessages(
        chat.guid,
        limit: 25,
        before: around.dateCreated!.millisecondsSinceEpoch,
      );
      final afterResponse = await ChatsSvc.getMessages(
        chat.guid,
        limit: 25,
        sort: "ASC",
        after: around.dateCreated!.millisecondsSinceEpoch,
      );
      beforeResponse.addAll(afterResponse);
      _messages = beforeResponse.map((e) => Message.fromMap(e)).toList();
      _messages.sort(Message.sort);
      struct.addMessages(_messages);
    }
    isFetching = false;
  }

  static Future<List<dynamic>> getMessages(
      {bool withChats = false,
      bool withAttachments = false,
      bool withHandles = false,
      bool withChatParticipants = false,
      List<dynamic> where = const [],
      String sort = "DESC",
      int? before,
      int? after,
      String? chatGuid,
      int offset = 0,
      int limit = 100}) async {
    Completer<List<dynamic>> completer = Completer();
    final withQuery = <String>["attributedBody", "messageSummaryInfo", "payloadData"];
    if (withChats) withQuery.add("chat");
    if (withAttachments) withQuery.add("attachment");
    if (withHandles) withQuery.add("handle");
    if (withChatParticipants) withQuery.add("chat.participants");
    withQuery.add("attachment.metadata");

    HttpSvc.messages(
            withQuery: withQuery,
            where: where,
            sort: sort,
            before: before,
            after: after,
            chatGuid: chatGuid,
            offset: offset,
            limit: limit)
        .then((response) {
      if (!completer.isCompleted) completer.complete(response.data["data"]);
    }).catchError((err) {
      late final dynamic error;
      if (err is Response) {
        error = err.data["error"]["message"];
      } else {
        error = err?.toString();
      }
      if (!completer.isCompleted) completer.completeError(error ?? "");
    });

    return completer.future;
  }
}
