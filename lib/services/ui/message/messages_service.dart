import 'dart:async';

import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/helpers/types/helpers/message_helper.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
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
  bool messagesLoaded = false;
  String? method;

  /// Map of message states for granular reactivity
  /// Key is message GUID, value is MessageState
  /// Provides O(1) lookups and granular observable fields
  final Map<String, MessageState> messageStates = {};

  /// Map of message widget controllers
  /// Key is message GUID, value is MessageWidgetController
  /// Managed locally per conversation for better lifecycle control
  final Map<String, MessageWidgetController> _controllers = {};

  /// Listeners for redacted mode settings to update all MessageStates
  StreamSubscription? _redactedModeListener;
  StreamSubscription? _hideMessageContentListener;

  /// Granular reactivity map to track individual message updates
  /// Key: message guid, Value: timestamp of last update
  final RxMap<String, int> messageUpdateTrigger = <String, int>{}.obs;

  Message? get mostRecentSent => (struct.messages.where((e) => e.isFromMe!).toList()..sort(Message.sort)).firstOrNull;

  Message? get mostRecent => (struct.messages.toList()..sort(Message.sort)).firstOrNull;

  Message? get mostRecentReceived =>
      (struct.messages.where((e) => !e.isFromMe!).toList()..sort(Message.sort)).firstOrNull;

  // ========== MessageState Management ==========

  /// Get or create a MessageState for a specific message GUID
  /// Creates the state if it doesn't exist
  /// Throws if message doesn't exist in struct
  MessageState getOrCreateMessageState(String guid) {
    if (!messageStates.containsKey(guid)) {
      final message = struct.getMessage(guid);
      if (message == null) {
        throw Exception('Cannot create MessageState: Message $guid not found in struct');
      }
      messageStates[guid] = MessageState(message);
      Logger.debug("Created MessageState for message $guid", tag: "MessageState");
    }
    return messageStates[guid]!;
  }

  /// Get MessageState if it exists, null otherwise
  /// Use this when you're not sure if the message exists
  MessageState? getMessageStateIfExists(String guid) {
    return messageStates[guid];
  }

  /// Sync a MessageState from the database
  /// Call this after any external DB update that doesn't go through MessagesService
  /// This ensures MessageState stays in sync with DB changes
  void syncMessageStateFromDB(String guid) {
    final message = Message.findOne(guid: guid);
    if (message != null) {
      final state = messageStates[guid];
      if (state != null) {
        state.updateFromMessage(message);
        Logger.debug("Synced MessageState from DB for message $guid", tag: "MessageState");
      } else {
        // State doesn't exist, create it
        messageStates[guid] = MessageState(message);
        Logger.debug("Created MessageState from DB sync for message $guid", tag: "MessageState");
      }
    }
  }

  /// Ensure MessageStates exist for a list of messages
  /// Creates states for messages that don't have them yet
  void _ensureMessageStates(List<Message> messages) {
    for (final message in messages) {
      if (message.guid != null && !messageStates.containsKey(message.guid)) {
        messageStates[message.guid!] = MessageState(message);
      }
    }
  }

  // ========== End MessageState Management ==========

  // ========== MessageWidgetController Management ==========

  /// Get or create a MessageWidgetController for a specific message
  /// Controllers are scoped to this MessagesService instance (one per conversation)
  MessageWidgetController getOrCreateController(Message message) {
    final guid = message.guid!;
    if (!_controllers.containsKey(guid)) {
      final controller = MessageWidgetController(message);
      controller.onInit(); // Initialize the controller
      controller.onReady(); // Ensure full GetX lifecycle initialization
      _controllers[guid] = controller;
      Logger.debug("Created MessageWidgetController for message $guid", tag: "MWC");
    }
    return _controllers[guid]!;
  }

  /// Get an existing controller if it exists, null otherwise
  MessageWidgetController? getControllerIfExists(String guid) {
    return _controllers[guid];
  }

  /// Dispose a specific controller by GUID
  void disposeController(String guid) {
    final controller = _controllers.remove(guid);
    if (controller != null) {
      controller.onClose(); // Properly clean up GetX lifecycle
      controller.dispose();
      Logger.debug("Disposed MessageWidgetController for message $guid", tag: "MWC");
    }
  }

  /// Dispose all controllers (called when conversation is closed)
  void disposeAllControllers() {
    for (final controller in _controllers.values) {
      controller.onClose(); // Properly clean up GetX lifecycle
      controller.dispose();
    }
    _controllers.clear();
    Logger.debug("Disposed all ${_controllers.length} MessageWidgetControllers", tag: "MWC");
  }

  // ========== End MessageWidgetController Management ==========

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
    _setupRedactedModeListeners();
  }

  /// Set up global listeners for redacted mode settings that update all message states
  void _setupRedactedModeListeners() {
    // Cancel existing listeners if any
    _redactedModeListener?.cancel();
    _hideMessageContentListener?.cancel();

    // Listen to redacted mode master toggle - when enabled, redact all messages; when disabled, unredact all
    _redactedModeListener = SettingsSvc.settings.redactedMode.listen((enabled) {
      for (final messageState in messageStates.values) {
        if (enabled) {
          messageState.redactFields();
        } else {
          messageState.unredactFields();
        }
      }
    });

    // Listen to hideMessageContent toggle - only affects message text/subject
    _hideMessageContentListener = SettingsSvc.settings.hideMessageContent.listen((enabled) {
      for (final messageState in messageStates.values) {
        if (enabled) {
          messageState.redactMessageContent();
        } else {
          messageState.unredactMessageContent();
        }
      }
    });
  }

  @override
  void onClose() {
    if (_init) {
      countSub.cancel();
      _redactedModeListener?.cancel();
      _hideMessageContentListener?.cancel();
    }
    _init = false;
    disposeAllControllers(); // Clean up all controllers
    messageStates.clear(); // Clean up message states
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
    messagesLoaded = false;
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

    // Create MessageState for this message
    if (message.guid != null) {
      messageStates[message.guid!] = MessageState(message);
      Logger.debug("Created MessageState for new message ${message.guid}", tag: "MessageState");
    }

    // Handle reactions with improved reactivity
    if (message.associatedMessageGuid != null) {
      final parentMessage = struct.getMessage(message.associatedMessageGuid!);
      if (parentMessage != null) {
        // Add to parent's associated messages list
        parentMessage.associatedMessages.add(message);

        // Update parent MessageState with the new reaction
        final parentState = messageStates[message.associatedMessageGuid!];
        if (parentState != null) {
          parentState.addAssociatedMessageInternal(message);
          Logger.debug("Added reaction ${message.guid} to MessageState of parent ${message.associatedMessageGuid}",
              tag: "MessageState");
        }

        // Notify UI of update (no longer need to call controller methods)
        triggerMessageUpdate(message.associatedMessageGuid!);
      } else {
        Logger.warn("Parent message not found for reaction ${message.guid} (parent: ${message.associatedMessageGuid})",
            tag: "MessageReactivity");
      }
    }

    // Handle thread originators with improved reactivity
    if (message.threadOriginatorGuid != null) {
      // Update thread originator MessageState
      final originatorState = messageStates[message.threadOriginatorGuid!];
      if (originatorState != null) {
        final currentCount = originatorState.threadReplyCount.value;
        originatorState.updateThreadReplyCountInternal(currentCount + 1);
        Logger.debug("Incremented thread reply count for ${message.threadOriginatorGuid} to ${currentCount + 1}",
            tag: "MessageState");
      }

      // Notify UI of update
      triggerMessageUpdate(message.threadOriginatorGuid!);
    }

    // Only call newFunc for non-reactions (regular messages)
    if (message.associatedMessageGuid == null) {
      newFunc.call(message);
    }
  }

  void updateMessage(Message updated, {String? oldGuid}) {
    // Try to find the message - check oldGuid first, then fallback to updated.guid
    // This handles race conditions where the GUID was already replaced
    Message? toUpdate;
    if (oldGuid != null) {
      toUpdate = struct.getMessage(oldGuid);
    }
    toUpdate ??= struct.getMessage(updated.guid!);
    if (toUpdate == null) return;
    
    updated = updated.mergeWith(toUpdate);
    struct.removeMessage(oldGuid ?? updated.guid!);
    struct.removeAttachments(toUpdate.attachments.map((e) => e!.guid!));
    struct.addMessages([updated]);

    // Update MessageState - try oldGuid first, then fallback to updated.guid
    MessageState? messageState;
    if (oldGuid != null) {
      messageState = messageStates[oldGuid];
    }
    messageState ??= messageStates[updated.guid!];
    
    if (messageState != null) {
      messageState.updateFromMessage(updated);
      Logger.debug("Updated MessageState for message ${updated.guid}", tag: "MessageState");

      // If guid changed (temp -> real), update the map
      if (oldGuid != null && oldGuid != updated.guid) {
        messageStates.remove(oldGuid);
        if (updated.guid != null) {
          messageStates[updated.guid!] = messageState;
          Logger.debug("Moved MessageState from $oldGuid to ${updated.guid}", tag: "MessageState");
        }
      }
    } else if (updated.guid != null) {
      // State doesn't exist, create it
      messageStates[updated.guid!] = MessageState(updated);
      Logger.debug("Created MessageState for updated message ${updated.guid}", tag: "MessageState");
    }

    // Trigger granular update for this specific message
    messageUpdateTrigger[updated.guid!] = DateTime.now().millisecondsSinceEpoch;

    updateFunc.call(updated, oldGuid: oldGuid);
  }

  void removeMessage(Message toRemove) {
    struct.removeMessage(toRemove.guid!);
    struct.removeAttachments(toRemove.attachments.map((e) => e!.guid!));
    messageUpdateTrigger.remove(toRemove.guid!);

    // Remove MessageState
    messageStates.remove(toRemove.guid!);
    Logger.debug("Removed MessageState for message ${toRemove.guid}", tag: "MessageState");

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

  /// Retry sending a failed message
  /// Generates new temp GUID, clears error state, and updates both DB and MessageState
  Future<void> retryFailedMessage(Message message, {String? oldGuid}) async {
    final guidToDelete = oldGuid ?? message.guid!;

    // Generate new temp GUID for retry
    message.generateTempGuid();

    // Clear error and delivery status
    message.error = 0;
    message.dateCreated = DateTime.now();
    message.dateDelivered = null;
    message.dateRead = null;

    // Delete old errored message from DB and save with new temp GUID
    await Message.delete(guidToDelete);
    message.id = null;
    message.save(chat: chat);

    // Update struct and MessageState
    final messageState = getOrCreateMessageState(message.guid!);
    messageState.updateErrorInternal(0);
    messageState.updateDateCreatedInternal(message.dateCreated);
    messageState.updateDateDeliveredInternal(null);
    messageState.updateDateReadInternal(null);

    // Update in struct
    final index = struct.messages.indexWhere((m) => m.guid == guidToDelete);
    if (index >= 0) {
      struct.messages[index] = message;
    }

    // Clean up old MessageState and create new one
    messageStates.remove(guidToDelete);
    getOrCreateMessageState(message.guid!);
  }

  /// Delete a message from DB, struct, and MessageState
  Future<void> deleteMessage(Message message) async {
    await Message.delete(message.guid!);
    removeMessage(message);
  }

  /// Toggle bookmark status on a message
  /// Updates DB and MessageState
  void toggleBookmark(Message message) {
    message.isBookmarked = !message.isBookmarked;
    message.save(updateIsBookmarked: true);

    // Update MessageState if it exists
    final messageState = getMessageStateIfExists(message.guid!);
    messageState?.updateIsBookmarkedInternal(message.isBookmarked);
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
          // Phase 2 complete - reactions have been loaded into message.associatedMessages
          Logger.info("[loadChunk] Supplemental data loaded, syncing MessageStates for ${_messages.length} messages",
              tag: "MessageReactivity");

          // Ensure MessageStates exist first (in case they weren't created yet)
          _ensureMessageStates(_messages);

          // Sync associatedMessages into MessageState observables
          for (final message in _messages) {
            if (message.guid != null && message.associatedMessages.isNotEmpty) {
              final messageState = messageStates[message.guid];
              if (messageState != null) {
                // Clear and repopulate the observable list to trigger reactivity
                messageState.associatedMessages.clear();
                messageState.associatedMessages.addAll(message.associatedMessages);
                messageState.hasReactions.value = message.associatedMessages.isNotEmpty;
                
                Logger.debug(
                  "[loadChunk] Synced ${message.associatedMessages.length} reactions into MessageState for ${message.guid}",
                  tag: "MessageReactivity");
              }
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

    // Create MessageStates for all loaded messages
    _ensureMessageStates(_messages);
    Logger.debug("[loadChunk] Created MessageStates for ${_messages.length} messages", tag: "MessageState");

    // get thread originators
    for (Message m in _messages.where((e) => e.threadOriginatorGuid != null)) {
      // see if the originator is already loaded
      final guid = m.threadOriginatorGuid!;
      if (struct.getMessage(guid) != null) continue;
      // if not, fetch local and add to data
      final threadOriginator = Message.findOne(guid: guid);
      if (threadOriginator != null) {
        // create the controller so it can be rendered in a reply bubble
        final c = getOrCreateController(threadOriginator);
        c.cvController = controller;
        struct.addThreadOriginator(threadOriginator);
      }
    }

    // this indicates an audio message was kept by the recipient
    // run this every time more messages are loaded just in case
    for (Message m in struct.messages.where((e) => e.itemType == 5 && e.subject != null)) {
      final otherMessage = struct.getMessage(m.subject!);
      if (otherMessage != null) {
        final otherMwc = getControllerIfExists(m.subject!) ?? getOrCreateController(otherMessage);
        otherMwc.audioWasKept.value = m.dateCreated;
      }
    }

    isFetching = false;
    messagesLoaded = true;
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
      // Create MessageStates for loaded messages
      _ensureMessageStates(_messages);
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
      // Create MessageStates for loaded messages
      _ensureMessageStates(_messages);
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
