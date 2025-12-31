import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

/// State wrapper for Chat that provides granular reactivity for UI components.
/// Each field that may affect the UI is tracked separately, allowing widgets
/// to observe only the specific properties they care about.
class ChatState {
  /// Reference to the underlying chat object
  final Chat chat;

  /// Observable fields for granular UI updates
  final RxBool isPinned;
  final RxnInt pinIndex;
  final RxBool hasUnreadMessage;
  final RxnString muteType;
  final RxnString muteArgs;
  final RxBool isArchived;
  final RxnString displayName;
  final RxnString customAvatarPath;
  final RxnString title;
  final Rxn<Message> latestMessage;
  final RxnString textFieldText;
  final RxList<String> textFieldAttachments;
  final RxnBool autoSendReadReceipts;
  final RxnBool autoSendTypingIndicators;
  final RxBool lockChatName;
  final RxBool lockChatIcon;
  final RxnString lastReadMessageGuid;

  final RxBool isActive;
  final RxBool isAlive;
  ConversationViewController? controller;

  ChatState(this.chat)
      : isPinned = (chat.isPinned ?? false).obs,
        pinIndex = RxnInt(chat.pinIndex),
        hasUnreadMessage = (chat.hasUnreadMessage ?? false).obs,
        muteType = RxnString(chat.muteType),
        muteArgs = RxnString(chat.muteArgs),
        isArchived = (chat.isArchived ?? false).obs,
        displayName = RxnString(chat.displayName),
        customAvatarPath = RxnString(chat.customAvatarPath),
        title = RxnString(chat.title),
        latestMessage = Rxn<Message>(chat.latestMessage),
        textFieldText = RxnString(chat.textFieldText),
        textFieldAttachments = chat.textFieldAttachments.obs,
        autoSendReadReceipts = RxnBool(chat.autoSendReadReceipts),
        autoSendTypingIndicators = RxnBool(chat.autoSendTypingIndicators),
        lockChatName = chat.lockChatName.obs,
        lockChatIcon = chat.lockChatIcon.obs,
        lastReadMessageGuid = RxnString(chat.lastReadMessageGuid),
        isActive = false.obs,
        isAlive = false.obs;

  /// Update the state from a chat object (useful when chat is updated from DB)
  void updateFromChat(Chat updatedChat) {
    if (isPinned.value != (updatedChat.isPinned ?? false)) {
      isPinned.value = updatedChat.isPinned ?? false;
    }
    if (pinIndex.value != updatedChat.pinIndex) {
      pinIndex.value = updatedChat.pinIndex;
    }
    if (hasUnreadMessage.value != (updatedChat.hasUnreadMessage ?? false)) {
      hasUnreadMessage.value = updatedChat.hasUnreadMessage ?? false;
    }
    if (muteType.value != updatedChat.muteType) {
      muteType.value = updatedChat.muteType;
    }
    if (muteArgs.value != updatedChat.muteArgs) {
      muteArgs.value = updatedChat.muteArgs;
    }
    if (isArchived.value != (updatedChat.isArchived ?? false)) {
      isArchived.value = updatedChat.isArchived ?? false;
    }
    if (displayName.value != updatedChat.displayName) {
      displayName.value = updatedChat.displayName;
    }
    if (customAvatarPath.value != updatedChat.customAvatarPath) {
      customAvatarPath.value = updatedChat.customAvatarPath;
    }
    if (title.value != updatedChat.title) {
      title.value = updatedChat.title;
    }
    if (latestMessage.value?.guid != updatedChat.latestMessage.guid) {
      latestMessage.value = updatedChat.latestMessage;
    }
    if (textFieldText.value != updatedChat.textFieldText) {
      textFieldText.value = updatedChat.textFieldText;
    }
    if (!listEquals(textFieldAttachments, updatedChat.textFieldAttachments)) {
      textFieldAttachments.value = updatedChat.textFieldAttachments;
    }
    if (autoSendReadReceipts.value != updatedChat.autoSendReadReceipts) {
      autoSendReadReceipts.value = updatedChat.autoSendReadReceipts;
    }
    if (autoSendTypingIndicators.value != updatedChat.autoSendTypingIndicators) {
      autoSendTypingIndicators.value = updatedChat.autoSendTypingIndicators;
    }
    if (lockChatName.value != updatedChat.lockChatName) {
      lockChatName.value = updatedChat.lockChatName;
    }
    if (lockChatIcon.value != updatedChat.lockChatIcon) {
      lockChatIcon.value = updatedChat.lockChatIcon;
    }
    if (lastReadMessageGuid.value != updatedChat.lastReadMessageGuid) {
      lastReadMessageGuid.value = updatedChat.lastReadMessageGuid;
    }

    // Merge the updated chat properties into the underlying chat object
    chat.isPinned = updatedChat.isPinned;
    chat.pinIndex = updatedChat.pinIndex;
    chat.hasUnreadMessage = updatedChat.hasUnreadMessage;
    chat.muteType = updatedChat.muteType;
    chat.muteArgs = updatedChat.muteArgs;
    chat.isArchived = updatedChat.isArchived;
    chat.displayName = updatedChat.displayName;
    chat.customAvatarPath = updatedChat.customAvatarPath;
    chat.title = updatedChat.title;
    chat.latestMessage = updatedChat.latestMessage;
    chat.textFieldText = updatedChat.textFieldText;
    chat.textFieldAttachments = updatedChat.textFieldAttachments;
    chat.autoSendReadReceipts = updatedChat.autoSendReadReceipts;
    chat.autoSendTypingIndicators = updatedChat.autoSendTypingIndicators;
    chat.lockChatName = updatedChat.lockChatName;
    chat.lockChatIcon = updatedChat.lockChatIcon;
    chat.lastReadMessageGuid = updatedChat.lastReadMessageGuid;
  }

  // Setters that update both the observable and save to the database

  Future<void> setIsPinned(bool value) async {
    if (isPinned.value == value) return;
    isPinned.value = value;
    pinIndex.value = null;
    await chat.togglePinAsync(value);
  }

  Future<void> setPinIndex(int? value) async {
    if (pinIndex.value == value) return;
    pinIndex.value = value;
    chat.pinIndex = value;
    await chat.saveAsync(updatePinIndex: true);
  }

  Future<void> setHasUnread(bool value, {
    bool force = false,
    bool clearLocalNotifications = true,
    bool privateMark = true,
  }) async {
    if (hasUnreadMessage.value == value && !force) return;
    hasUnreadMessage.value = value;
    await chat.toggleHasUnreadAsync(
      value,
      force: force,
      clearLocalNotifications: clearLocalNotifications,
      privateMark: privateMark,
    );
  }

  Future<void> setMuted(bool isMuted) async {
    final newMuteType = isMuted ? "mute" : null;
    if (muteType.value == newMuteType) return;
    muteType.value = newMuteType;
    muteArgs.value = null;
    await chat.toggleMuteAsync(isMuted);
  }

  Future<void> setArchived(bool value) async {
    if (isArchived.value == value) return;
    isArchived.value = value;
    isPinned.value = false;
    await chat.toggleArchivedAsync(value);
  }

  Future<void> setDisplayName(String? value) async {
    if (displayName.value == value) return;
    displayName.value = value;
    chat.displayName = value;
    await chat.saveAsync(updateDisplayName: true);
  }

  Future<void> setCustomAvatarPath(String? value) async {
    if (customAvatarPath.value == value) return;
    customAvatarPath.value = value;
    chat.customAvatarPath = value;
    await chat.saveAsync(updateCustomAvatarPath: true);
  }

  Future<void> setTitle(String? value) async {
    if (title.value == value) return;
    title.value = value;
    chat.title = value;
  }

  Future<void> setLatestMessage(Message? value) async {
    if (latestMessage.value?.guid == value?.guid) return;
    latestMessage.value = value;
    chat.latestMessage = value ?? Message(
      dateCreated: DateTime.fromMillisecondsSinceEpoch(0),
      guid: chat.guid,
    );
  }

  Future<void> setTextFieldText(String? value) async {
    if (textFieldText.value == value) return;
    textFieldText.value = value;
    chat.textFieldText = value;
    await chat.saveAsync(updateTextFieldText: true);
  }

  Future<void> setTextFieldAttachments(List<String> value) async {
    if (listEquals(textFieldAttachments, value)) return;
    textFieldAttachments.value = value;
    chat.textFieldAttachments = value;
    await chat.saveAsync(updateTextFieldAttachments: true);
  }

  Future<void> setAutoSendReadReceipts(bool? value) async {
    if (autoSendReadReceipts.value == value) return;
    autoSendReadReceipts.value = value;
    await chat.toggleAutoReadAsync(value);
  }

  Future<void> setAutoSendTypingIndicators(bool? value) async {
    if (autoSendTypingIndicators.value == value) return;
    autoSendTypingIndicators.value = value;
    await chat.toggleAutoTypeAsync(value);
  }

  Future<void> setLockChatName(bool value) async {
    if (lockChatName.value == value) return;
    lockChatName.value = value;
    chat.lockChatName = value;
    await chat.saveAsync(updateLockChatName: true);
  }

  Future<void> setLockChatIcon(bool value) async {
    if (lockChatIcon.value == value) return;
    lockChatIcon.value = value;
    chat.lockChatIcon = value;
    await chat.saveAsync(updateLockChatIcon: true);
  }

  Future<void> setLastReadMessageGuid(String? value) async {
    if (lastReadMessageGuid.value == value) return;
    lastReadMessageGuid.value = value;
    chat.lastReadMessageGuid = value;
    await chat.saveAsync(updateLastReadMessageGuid: true);
  }

  /// Refresh the title from the chat
  void refreshTitle() {
    final newTitle = chat.getTitle();
    if (title.value != newTitle) {
      title.value = newTitle;
    }
  }

  // ========== Lifecycle Management Methods ==========

  /// Check if this chat is currently active and alive
  bool get isChatActive => isActive.value && isAlive.value;

  /// Set the chat as active
  void setActive(bool value) {
    isActive.value = value;
  }

  /// Set the chat as alive
  void setAlive(bool value) {
    isAlive.value = value;
  }

  /// Set both active and alive to the same value
  void setActiveAndAlive(bool value) {
    isActive.value = value;
    isAlive.value = value;
  }
}
