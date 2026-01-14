import 'package:bluebubbles/data/database/models.dart';
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

  // ========== Internal State Update Methods ==========
  // These are called by ChatsService after DB operations complete
  // Do NOT call these directly - use ChatsService methods instead

  void updateIsPinnedInternal(bool value) {
    if (isPinned.value != value) {
      isPinned.value = value;
    }
  }

  void updatePinIndexInternal(int? value) {
    if (pinIndex.value != value) {
      pinIndex.value = value;
    }
  }

  void updateHasUnreadInternal(bool value) {
    if (hasUnreadMessage.value != value) {
      hasUnreadMessage.value = value;
    }
  }

  void updateMutedInternal(String? muteType, String? muteArgs) {
    if (this.muteType.value != muteType) {
      this.muteType.value = muteType;
    }
    if (this.muteArgs.value != muteArgs) {
      this.muteArgs.value = muteArgs;
    }
  }

  void updateArchivedInternal(bool value) {
    if (isArchived.value != value) {
      isArchived.value = value;
    }
  }

  void updateDisplayNameInternal(String? value) {
    if (displayName.value != value) {
      displayName.value = value;
    }
  }

  void updateCustomAvatarPathInternal(String? value) {
    if (customAvatarPath.value != value) {
      customAvatarPath.value = value;
    }
  }

  void updateTitleInternal(String? value) {
    if (title.value != value) {
      title.value = value;
    }
  }

  void updateLatestMessageInternal(Message? value) {
    if (latestMessage.value?.guid != value?.guid) {
      latestMessage.value = value;
    }
  }

  void updateTextFieldTextInternal(String? value) {
    if (textFieldText.value != value) {
      textFieldText.value = value;
    }
  }

  void updateTextFieldAttachmentsInternal(List<String> value) {
    if (!listEquals(textFieldAttachments, value)) {
      textFieldAttachments.value = value;
    }
  }

  /// Update the state from a chat object (useful when chat is updated from DB)
  void updateFromChat(Chat updatedChat) {
    // Update observables using internal methods
    updateIsPinnedInternal(updatedChat.isPinned ?? false);
    updatePinIndexInternal(updatedChat.pinIndex);
    updateHasUnreadInternal(updatedChat.hasUnreadMessage ?? false);
    updateMutedInternal(updatedChat.muteType, updatedChat.muteArgs);
    updateArchivedInternal(updatedChat.isArchived ?? false);
    updateDisplayNameInternal(updatedChat.displayName);
    updateCustomAvatarPathInternal(updatedChat.customAvatarPath);
    updateTitleInternal(updatedChat.title);
    updateLatestMessageInternal(updatedChat.latestMessage);
    updateTextFieldTextInternal(updatedChat.textFieldText);
    updateTextFieldAttachmentsInternal(updatedChat.textFieldAttachments);

    // Update other properties directly
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

  // ========== Internal Lifecycle State Update Methods ==========
  // These are called by ChatsService - do NOT call directly

  /// Check if this chat is currently active and alive
  bool get isChatActive => isActive.value && isAlive.value;

  void updateActiveInternal(bool value) {
    if (isActive.value != value) {
      isActive.value = value;
    }
  }

  void updateAliveInternal(bool value) {
    if (isAlive.value != value) {
      isAlive.value = value;
    }
  }

  void updateActiveAndAliveInternal(bool value) {
    if (isActive.value != value) {
      isActive.value = value;
    }
    if (isAlive.value != value) {
      isAlive.value = value;
    }
  }
}
