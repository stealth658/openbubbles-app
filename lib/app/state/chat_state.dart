import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
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
  final RxnString customBackgroundPath;
  final RxnString title;
  final RxnString chatCreatorSubtitle;
  final RxnString subtitle;
  final Rxn<Message> latestMessage;
  final RxnString textFieldText;
  final RxList<String> textFieldAttachments;
  final RxnBool autoSendReadReceipts;
  final RxnBool autoSendTypingIndicators;
  final RxBool lockChatName;
  final RxBool lockChatIcon;
  final RxnString lastReadMessageGuid;

  /// The delivery/read status of the latest outgoing message.  Updated any
  /// time [updateLatestMessageInternal] is called, even when the GUID has not
  /// changed (e.g. a delivery or read receipt arrives for the current latest
  /// message).  Drives the status indicator on conversation-list tiles.
  final Rx<MessageStatusIndicator> latestMessageStatus;

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
        customBackgroundPath = RxnString(chat.customBackgroundPath),
        title = RxnString(chat.getTitle()),
        chatCreatorSubtitle = RxnString(chat.isGroup
            ? chat.getChatCreatorSubtitle()
            : (chat.handles.isNotEmpty ? (chat.handles.first.formattedAddress ?? chat.handles.first.address) : null)),
        subtitle = RxnString(MessageHelper.getNotificationText(chat.latestMessage)),
        latestMessage = Rxn<Message>(chat.latestMessage),
        latestMessageStatus = Rx<MessageStatusIndicator>(
          chat.latestMessage.isFromMe != true ? MessageStatusIndicator.NONE : chat.latestMessage.indicatorToShow,
        ),
        textFieldText = RxnString(chat.textFieldText),
        textFieldAttachments = chat.textFieldAttachments.obs,
        autoSendReadReceipts = RxnBool(chat.autoSendReadReceipts),
        autoSendTypingIndicators = RxnBool(chat.autoSendTypingIndicators),
        lockChatName = chat.lockChatName.obs,
        lockChatIcon = chat.lockChatIcon.obs,
        lastReadMessageGuid = RxnString(chat.lastReadMessageGuid),
        isActive = false.obs,
        isAlive = false.obs {
    // Apply redaction if redacted mode is enabled on initialization
    if (SettingsSvc.settings.redactedMode.value) {
      redactFields();
    }
  }

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

  void updateAutoSendReadReceiptsInternal(bool? value) {
    if (autoSendReadReceipts.value != value) {
      autoSendReadReceipts.value = value;
    }
  }

  void updateAutoSendTypingIndicatorsInternal(bool? value) {
    if (autoSendTypingIndicators.value != value) {
      autoSendTypingIndicators.value = value;
    }
  }

  void updateLockChatNameInternal(bool value) {
    if (lockChatName.value != value) {
      lockChatName.value = value;
    }
  }

  void updateLockChatIconInternal(bool value) {
    if (lockChatIcon.value != value) {
      lockChatIcon.value = value;
    }
  }

  void updateDisplayNameInternal(String? value) {
    if (displayName.value != value) {
      displayName.value = value;
      updateTitleInternal(_computeTitle());
    }
  }

  void updateCustomAvatarPathInternal(String? value) {
    if (customAvatarPath.value != value) {
      customAvatarPath.value = value;
    }
  }

  void updateCustomBackgroundPathInternal(String? value) {
    if (customBackgroundPath.value != value) {
      customBackgroundPath.value = value;
    }
  }

  void updateTitleInternal(String? value) {
    if (title.value != value) {
      title.value = value;
    }
  }

  String? _computeTitle() => isNullOrEmpty(displayName.value) ? chatCreatorSubtitle.value : displayName.value;

  void updateChatCreatorSubtitleInternal(String? value) {
    if (chatCreatorSubtitle.value != value) {
      chatCreatorSubtitle.value = value;
      updateTitleInternal(_computeTitle());
    }
  }

  void updateSubtitleInternal(String? value) {
    if (subtitle.value != value) {
      subtitle.value = value;
    }
  }

  void updateLatestMessageInternal(Message? value) {
    if (latestMessage.value?.guid != value?.guid) {
      latestMessage.value = value;
    }
    // Always update status even when the GUID is unchanged — a delivery or
    // read receipt arrives for the same message object, and the indicator
    // must reflect the new state without a full GUID change.
    updateLatestMessageStatusInternal(value?.indicatorToShow ?? MessageStatusIndicator.NONE);
  }

  void updateLatestMessageStatusInternal(MessageStatusIndicator value) {
    if (latestMessageStatus.value != value) latestMessageStatus.value = value;
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
    updateCustomBackgroundPathInternal(updatedChat.customBackgroundPath);
    updateChatCreatorSubtitleInternal(updatedChat.isGroup
        ? updatedChat.getChatCreatorSubtitle()
        : (updatedChat.handles.isNotEmpty
            ? (updatedChat.handles.first.formattedAddress ?? updatedChat.handles.first.address)
            : null));
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

  // ========== Redaction Methods ==========
  // These are called when redacted mode is toggled on/off

  /// Redact contact information (title, displayName, subtitle)
  void redactContactInfo() {
    if (!SettingsSvc.settings.redactedMode.value) return;
    if (!SettingsSvc.settings.hideContactInfo.value && !SettingsSvc.settings.generateFakeContactNames.value) return;

    // Apply fake name as title and displayName, clear subtitle
    final fakeName = chat.isGroup ? chat.fakeName : (chat.handles.isNotEmpty ? chat.handles[0].fakeName : 'Unknown');
    updateDisplayNameInternal(fakeName);
    updateChatCreatorSubtitleInternal('');
  }

  /// Restore contact information to original values
  void unredactContactInfo() {
    updateDisplayNameInternal(chat.displayName);
    // TODO: cache this value if needed to avoid over-processing
    final computedSubtitle = chat.isGroup
        ? chat.getChatCreatorSubtitle()
        : (chat.handles.isNotEmpty ? (chat.handles.first.formattedAddress ?? chat.handles.first.address) : null);
    updateChatCreatorSubtitleInternal(computedSubtitle);
  }

  /// Redact/hide avatars by clearing custom avatar path
  void redactAvatars() {
    if (!SettingsSvc.settings.redactedMode.value) return;
    if (!SettingsSvc.settings.generateFakeAvatars.value) return;

    // Clear the custom avatar path so fake avatars are generated
    updateCustomAvatarPathInternal(null);
  }

  /// Restore avatars to original values
  void unredactAvatars() {
    updateCustomAvatarPathInternal(chat.customAvatarPath);
  }

  /// Apply all redactions based on current settings (used on initialization)
  void redactFields() {
    if (!SettingsSvc.settings.redactedMode.value) return;

    redactContactInfo();
    redactAvatars();
  }

  /// Remove all redactions (used when redacted mode is disabled)
  void unredactFields() {
    unredactContactInfo();
    unredactAvatars();
  }
}
