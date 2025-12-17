import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// Shared service to manage chat title updates across all headers
/// Prevents duplicate database queries and improves performance
class ChatTitleController extends GetxController {
  static ChatTitleController get to => Get.find<ChatTitleController>();
  
  final Map<String, RxString> _titleCache = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  final Map<String, String?> _displayNameCache = {};
  final Map<String, int> _participantCountCache = {};

  /// Get or create a reactive title for a chat
  RxString getTitleObservable(Chat chat) {
    if (_titleCache.containsKey(chat.guid)) {
      return _titleCache[chat.guid]!;
    }

    final title = chat.getTitle().obs;
    _titleCache[chat.guid] = title;
    _displayNameCache[chat.guid] = chat.displayName;
    _participantCountCache[chat.guid] = chat.handles.length;

    _startWatchingChat(chat);
    return title;
  }

  void _startWatchingChat(Chat chat) {
    if (_subscriptions.containsKey(chat.guid)) return;

    if (!kIsWeb) {
      final titleQuery = Database.chats.query(Chat_.guid.equals(chat.guid)).watch();
      _subscriptions[chat.guid] = titleQuery.listen((Query<Chat> query) async {
        final updatedChat = await runAsync(() {
          final cquery = Database.chats.query(Chat_.guid.equals(chat.guid)).build();
          return cquery.findFirst();
        });

        if (updatedChat == null) return;

        // Only update if display name or participant count actually changed
        final cachedDisplayName = _displayNameCache[chat.guid];
        final cachedParticipantCount = _participantCountCache[chat.guid];

        if (updatedChat.displayName != cachedDisplayName ||
            updatedChat.handles.length != cachedParticipantCount) {
          final newTitle = updatedChat.getTitle();
          if (_titleCache[chat.guid]?.value != newTitle) {
            _titleCache[chat.guid]?.value = newTitle;
          }
          _displayNameCache[chat.guid] = updatedChat.displayName;
          _participantCountCache[chat.guid] = updatedChat.handles.length;
        }
      });
    } else {
      _subscriptions[chat.guid] = WebListeners.chatUpdate.listen((updatedChat) {
        if (updatedChat.guid != chat.guid) return;

        final cachedDisplayName = _displayNameCache[chat.guid];
        final cachedParticipantCount = _participantCountCache[chat.guid];

        if (updatedChat.displayName != cachedDisplayName ||
            updatedChat.participants.length != cachedParticipantCount) {
          final newTitle = updatedChat.getTitle();
          if (_titleCache[chat.guid]?.value != newTitle) {
            _titleCache[chat.guid]?.value = newTitle;
          }
          _displayNameCache[chat.guid] = updatedChat.displayName;
          _participantCountCache[chat.guid] = updatedChat.participants.length;
        }
      });
    }
  }

  /// Clean up resources for a specific chat
  void disposeChat(String chatGuid) {
    _subscriptions[chatGuid]?.cancel();
    _subscriptions.remove(chatGuid);
    _titleCache.remove(chatGuid);
    _displayNameCache.remove(chatGuid);
    _participantCountCache.remove(chatGuid);
  }

  @override
  void onClose() {
    for (var sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    _titleCache.clear();
    _displayNameCache.clear();
    _participantCountCache.clear();
    super.onClose();
  }
}

/// Initialize the title controller
void initChatTitleController() {
  if (!Get.isRegistered<ChatTitleController>()) {
    Get.put(ChatTitleController());
  }
}
