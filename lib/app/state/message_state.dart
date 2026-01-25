import 'package:bluebubbles/database/models.dart';
import 'package:get/get.dart';

/// State wrapper for Message that provides granular reactivity for UI components.
/// Each field that may affect the UI is tracked separately, allowing widgets
/// to observe only the specific properties they care about.
///
/// This pattern mirrors ChatState and provides:
/// - Single source of truth for message state
/// - Granular observables instead of boolean toggle flags
/// - Direct property updates instead of coordinator timestamps
/// - Type-safe state changes
class MessageState {
  /// Reference to the underlying message object
  final Message message;

  /// Observable fields for granular UI updates
  final RxnString guid;
  final RxnString text;
  final RxnString subject;
  final RxBool isFromMe;
  final Rxn<DateTime> dateCreated;
  final Rxn<DateTime> dateDelivered;
  final Rxn<DateTime> dateRead;
  final Rxn<DateTime> dateEdited;
  final RxInt error;
  final RxBool isDelivered;
  final RxBool hasAttachments;
  final RxBool hasReactions;
  final RxList<Message> associatedMessages; // reactions and edits
  final RxBool didNotifyRecipient;
  final RxBool wasDeliveredQuietly;
  final RxBool isBookmarked;
  final RxnString threadOriginatorGuid;
  final RxInt threadReplyCount;
  final RxnString associatedMessageGuid; // For reactions: parent message GUID
  final RxnString associatedMessageType; // For reactions: reaction type (loved, liked, etc)
  final RxnInt associatedMessagePart; // For reactions: which part of message

  // Derived/computed states for UI convenience
  final RxBool hasError;
  final RxBool isSending; // temp guid exists
  final RxBool isSent; // not temp guid
  final RxBool isReaction; // has associatedMessageGuid

  MessageState(this.message)
      : guid = RxnString(message.guid),
        text = RxnString(message.text),
        subject = RxnString(message.subject),
        isFromMe = (message.isFromMe ?? true).obs,
        dateCreated = Rxn<DateTime>(message.dateCreated),
        dateDelivered = Rxn<DateTime>(message.dateDelivered),
        dateRead = Rxn<DateTime>(message.dateRead),
        dateEdited = Rxn<DateTime>(message.dateEdited),
        error = message.error.obs,
        isDelivered = message.isDelivered.obs,
        hasAttachments = message.hasAttachments.obs,
        hasReactions = message.hasReactions.obs,
        associatedMessages = message.associatedMessages.obs,
        didNotifyRecipient = message.didNotifyRecipient.obs,
        wasDeliveredQuietly = message.wasDeliveredQuietly.obs,
        isBookmarked = message.isBookmarked.obs,
        threadOriginatorGuid = RxnString(message.threadOriginatorGuid),
        threadReplyCount = 0.obs,
        associatedMessageGuid = RxnString(message.associatedMessageGuid),
        associatedMessageType = RxnString(message.associatedMessageType),
        associatedMessagePart = RxnInt(message.associatedMessagePart),
        hasError = (message.error > 0).obs,
        isSending = (message.guid?.startsWith('temp') ?? false).obs,
        isSent = (!(message.guid?.startsWith('temp') ?? false)).obs,
        isReaction = (message.associatedMessageGuid != null).obs;

  // ========== Internal State Update Methods ==========
  // These are called by MessagesService after DB operations complete
  // Do NOT call these directly - use MessagesService methods instead

  /// Update the message GUID (typically when temp -> real GUID)
  void updateGuidInternal(String? value) {
    if (guid.value != value) {
      guid.value = value;
      message.guid = value;

      // Update derived states
      isSending.value = value?.startsWith('temp') ?? false;
      isSent.value = !(value?.startsWith('temp') ?? false);
    }
  }

  /// Update message text content
  void updateTextInternal(String? value) {
    if (text.value != value) {
      text.value = value;
      message.text = value;
    }
  }

  /// Update message subject
  void updateSubjectInternal(String? value) {
    if (subject.value != value) {
      subject.value = value;
      message.subject = value;
    }
  }

  /// Update creation timestamp
  void updateDateCreatedInternal(DateTime? value) {
    if (dateCreated.value != value) {
      dateCreated.value = value;
      message.dateCreated = value;
    }
  }

  /// Update delivery timestamp
  void updateDateDeliveredInternal(DateTime? value) {
    if (dateDelivered.value != value) {
      dateDelivered.value = value;
      message.dateDelivered = value;
      // Auto-update isDelivered flag
      isDelivered.value = value != null;
    }
  }

  /// Update read timestamp
  void updateDateReadInternal(DateTime? value) {
    if (dateRead.value != value) {
      dateRead.value = value;
      message.dateRead = value;
    }
  }

  /// Update edited timestamp
  void updateDateEditedInternal(DateTime? value) {
    if (dateEdited.value != value) {
      dateEdited.value = value;
      message.dateEdited = value;
    }
  }

  /// Update error code
  void updateErrorInternal(int value) {
    if (error.value != value) {
      error.value = value;
      message.error = value;
      // Auto-update hasError flag
      hasError.value = value > 0;
    }
  }

  /// Update isDelivered flag directly (for cases without timestamp)
  void updateIsDeliveredInternal(bool value) {
    if (isDelivered.value != value) {
      isDelivered.value = value;
      message.isDelivered = value;
    }
  }

  /// Replace all associated messages (reactions/edits)
  void updateAssociatedMessagesInternal(List<Message> value) {
    associatedMessages.value = value;
    message.associatedMessages = value;
    hasReactions.value = value.isNotEmpty;
  }

  /// Add or update a single associated message (reaction/edit)
  /// Handles both new additions and updates to existing reactions
  void addAssociatedMessageInternal(Message reaction) {
    // Try to find existing reaction by ID or GUID
    final index = associatedMessages.indexWhere((e) =>
        (e.id == reaction.id && e.id != null) || (e.guid == reaction.guid && !reaction.guid!.startsWith('temp')));

    if (index >= 0) {
      // Update existing reaction
      associatedMessages[index] = reaction;
    } else {
      // Check if this replaces a temp reaction
      final tempIndex = associatedMessages.indexWhere((e) =>
          (e.guid?.startsWith('temp') == true || e.guid?.startsWith('error') == true) &&
          e.associatedMessageType == reaction.associatedMessageType &&
          (e.associatedMessagePart ?? 0) == (reaction.associatedMessagePart ?? 0));

      if (tempIndex >= 0) {
        // Replace temp reaction
        associatedMessages[tempIndex] = reaction;
      } else {
        // Add new reaction
        associatedMessages.add(reaction);
      }
    }

    // Update underlying message and hasReactions flag
    message.associatedMessages = associatedMessages.toList();
    hasReactions.value = associatedMessages.isNotEmpty;
  }

  /// Remove an associated message (reaction/edit)
  void removeAssociatedMessageInternal(Message reaction) {
    associatedMessages.removeWhere((e) => e.id == reaction.id);
    message.associatedMessages = associatedMessages.toList();
    hasReactions.value = associatedMessages.isNotEmpty;
  }

  /// Update recipient notification flag
  void updateDidNotifyRecipientInternal(bool value) {
    if (didNotifyRecipient.value != value) {
      didNotifyRecipient.value = value;
      message.didNotifyRecipient = value;
    }
  }

  /// Update quiet delivery flag
  void updateWasDeliveredQuietlyInternal(bool value) {
    if (wasDeliveredQuietly.value != value) {
      wasDeliveredQuietly.value = value;
      message.wasDeliveredQuietly = value;
    }
  }

  /// Update bookmark status
  void updateIsBookmarkedInternal(bool value) {
    if (isBookmarked.value != value) {
      isBookmarked.value = value;
      message.isBookmarked = value;
    }
  }

  /// Update thread reply count (computed from thread messages)
  void updateThreadReplyCountInternal(int count) {
    if (threadReplyCount.value != count) {
      threadReplyCount.value = count;
    }
  }

  /// Update thread originator GUID
  void updateThreadOriginatorGuidInternal(String? value) {
    if (threadOriginatorGuid.value != value) {
      threadOriginatorGuid.value = value;
      message.threadOriginatorGuid = value;
    }
  }

  /// Update hasAttachments flag
  void updateHasAttachmentsInternal(bool value) {
    if (hasAttachments.value != value) {
      hasAttachments.value = value;
      message.hasAttachments = value;
    }
  }

  /// Update hasReactions flag directly (in addition to auto-update from associatedMessages)
  void updateHasReactionsInternal(bool value) {
    if (hasReactions.value != value) {
      hasReactions.value = value;
      message.hasReactions = value;
    }
  }

  /// Update associated message properties (for reactions)
  void updateAssociatedMessageInfoInternal({
    String? associatedMessageGuid,
    String? associatedMessageType,
    int? associatedMessagePart,
  }) {
    if (associatedMessageGuid != null && this.associatedMessageGuid.value != associatedMessageGuid) {
      this.associatedMessageGuid.value = associatedMessageGuid;
      message.associatedMessageGuid = associatedMessageGuid;
      isReaction.value = true;
    }

    if (associatedMessageType != null && this.associatedMessageType.value != associatedMessageType) {
      this.associatedMessageType.value = associatedMessageType;
      message.associatedMessageType = associatedMessageType;
    }

    if (associatedMessagePart != null && this.associatedMessagePart.value != associatedMessagePart) {
      this.associatedMessagePart.value = associatedMessagePart;
      message.associatedMessagePart = associatedMessagePart;
    }
  }

  /// Update state from database message object
  /// Used when message is refreshed from DB or merged with updates
  void updateFromMessage(Message updatedMessage) {
    // Update all observable fields
    updateGuidInternal(updatedMessage.guid);
    updateTextInternal(updatedMessage.text);
    updateSubjectInternal(updatedMessage.subject);
    updateDateDeliveredInternal(updatedMessage.dateDelivered);
    updateDateReadInternal(updatedMessage.dateRead);
    updateDateEditedInternal(updatedMessage.dateEdited);
    updateErrorInternal(updatedMessage.error);
    updateDidNotifyRecipientInternal(updatedMessage.didNotifyRecipient);
    updateWasDeliveredQuietlyInternal(updatedMessage.wasDeliveredQuietly);
    updateThreadOriginatorGuidInternal(updatedMessage.threadOriginatorGuid);
    updateHasAttachmentsInternal(updatedMessage.hasAttachments);
    updateHasReactionsInternal(updatedMessage.hasReactions);

    // Update isFromMe if changed
    if (isFromMe.value != updatedMessage.isFromMe) {
      isFromMe.value = updatedMessage.isFromMe ?? true;
      message.isFromMe = updatedMessage.isFromMe;
    }

    // Update dateCreated if changed
    if (dateCreated.value != updatedMessage.dateCreated) {
      dateCreated.value = updatedMessage.dateCreated;
      message.dateCreated = updatedMessage.dateCreated;
    }

    // Update associated message info if this is a reaction
    if (updatedMessage.associatedMessageGuid != null) {
      updateAssociatedMessageInfoInternal(
        associatedMessageGuid: updatedMessage.associatedMessageGuid,
        associatedMessageType: updatedMessage.associatedMessageType,
        associatedMessagePart: updatedMessage.associatedMessagePart,
      );
    }

    // Merge other non-observable properties
    message.handleId = updatedMessage.handleId;
    message.otherHandle = updatedMessage.otherHandle;
    message.country = updatedMessage.country;
    message.hasDdResults = updatedMessage.hasDdResults;
    message.datePlayed = updatedMessage.datePlayed;
    message.itemType = updatedMessage.itemType;
    message.groupTitle = updatedMessage.groupTitle;
    message.groupActionType = updatedMessage.groupActionType;
    message.balloonBundleId = updatedMessage.balloonBundleId;
    message.expressiveSendStyleId = updatedMessage.expressiveSendStyleId;
    message.dateDeleted = updatedMessage.dateDeleted;
    message.metadata = updatedMessage.metadata;
    message.threadOriginatorPart = updatedMessage.threadOriginatorPart;
    message.bigEmoji = updatedMessage.bigEmoji;
    message.attributedBody = updatedMessage.attributedBody;
    message.messageSummaryInfo = updatedMessage.messageSummaryInfo;
    message.payloadData = updatedMessage.payloadData;
    message.hasApplePayloadData = updatedMessage.hasApplePayloadData;
    message.isBookmarked = updatedMessage.isBookmarked;

    // Note: attachments and handle relationships are managed separately
    // They are not updated here to avoid circular dependencies
  }

  /// Convenience getter: Is this message in an error state?
  bool get isError => hasError.value;

  /// Convenience getter: Is this message currently being sent?
  bool get isCurrentlySending => isSending.value;

  /// Convenience getter: Has this message been sent successfully?
  bool get isSuccessfullySent => isSent.value && !hasError.value;

  /// Convenience getter: Is this a reaction message?
  bool get isReactionMessage => isReaction.value;

  /// Convenience getter: Count of reactions on this message
  int get reactionCount => associatedMessages.length;
}
