import 'dart:io';

import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Helper class for getting error display information
class ErrorHelper {
  static String getErrorText(int errorCode, String? guid) {
    if (errorCode == 22) {
      return "The recipient is not registered with iMessage!";
    } else if (guid != null && guid.startsWith("error-")) {
      return guid.split('-')[1];
    }
    return "An unknown internal error occurred.";
  }
}

/// Shared widget for displaying message/reaction error dialogs
class MessageErrorDialog extends StatelessWidget {
  const MessageErrorDialog({
    super.key,
    required this.errorCode,
    required this.errorText,
    required this.onRetry,
    required this.onRemove,
    required this.chatId,
  });

  final int errorCode;
  final String errorText;
  final VoidCallback onRetry;
  final VoidCallback onRemove;
  final int chatId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.theme.colorScheme.properSurface,
      title: Text("Message failed to send", style: context.theme.textTheme.titleLarge),
      content: Text("Error ($errorCode): $errorText", style: context.theme.textTheme.bodyLarge),
      actions: <Widget>[
        TextButton(
          child: Text("Retry",
              style: context.theme.textTheme.bodyLarge!.copyWith(color: Get.context!.theme.colorScheme.primary)),
          onPressed: () async {
            Navigator.of(context).pop();
            onRetry();
          },
        ),
        TextButton(
          child: Text("Remove",
              style: context.theme.textTheme.bodyLarge!.copyWith(color: Get.context!.theme.colorScheme.primary)),
          onPressed: () async {
            Navigator.of(context).pop();
            onRemove();
            await NotificationsSvc.clearFailedToSend(chatId);
          },
        ),
        TextButton(
          child: Text("Cancel",
              style: context.theme.textTheme.bodyLarge!.copyWith(color: Get.context!.theme.colorScheme.primary)),
          onPressed: () async {
            Navigator.of(context).pop();
            await NotificationsSvc.clearFailedToSend(chatId);
          },
        )
      ],
    );
  }
}

/// Shared retry logic for reactions
Future<void> retryReaction({
  required Message reaction,
  required Chat chat,
  required Message selected,
}) async {
  // Remove the original message and notification
  await MessagesSvc(chat.guid).deleteMessage(reaction);
  await NotificationsSvc.clearFailedToSend(chat.id!);

  // Remove from parent MessageState
  final parentState = MessagesSvc(chat.guid).getMessageStateIfExists(reaction.associatedMessageGuid!);
  if (parentState != null) {
    parentState.removeAssociatedMessageInternal(reaction);
  }

  // Re-send
  OutgoingMsgHandler.queue(OutgoingItem(
    type: QueueType.sendMessage,
    chat: chat,
    message: Message(
      associatedMessageGuid: selected.guid,
      associatedMessageType: reaction.associatedMessageType,
      associatedMessagePart: reaction.associatedMessagePart,
      dateCreated: DateTime.now(),
      hasAttachments: false,
      isFromMe: true,
      handleId: 0,
    ),
    selected: selected,
    reaction: reaction.associatedMessageType!,
  ));
}

/// Shared remove logic for reactions
Future<void> removeReaction({
  required Message reaction,
  required Chat chat,
}) async {
  // Delete the message from DB and service
  await MessagesSvc(chat.guid).deleteMessage(reaction);

  // Remove from parent MessageState
  final parentState = MessagesSvc(chat.guid).getMessageStateIfExists(reaction.associatedMessageGuid!);
  if (parentState != null) {
    parentState.removeAssociatedMessageInternal(reaction);
  }

  await NotificationsSvc.clearFailedToSend(chat.id!);
  // Get the "new" latest info
  List<Message> latest = await Chat.getMessagesAsync(chat, limit: 1);
  chat.latestMessage = latest.first;
  await chat.saveAsync();
}

/// Shared retry logic for regular messages
Future<void> retryMessage({
  required Message message,
  required Chat chat,
  required MessagesService service,
  required MessageState controller,
}) async {
  // Save old GUID for cleanup
  final oldGuid = message.guid!;

  // Retry message through service (updates DB and MessageState)
  await service.retryFailedMessage(message, oldGuid: oldGuid);

  // Clear notification
  await NotificationsSvc.clearFailedToSend(chat.id!);

  // Force UI rebuild to show unsent color
  controller.update();

  // Reload attachment bytes if needed
  for (Attachment? a in message.attachments) {
    if (a == null) continue;
    await Attachment.deleteAsync(a.guid!);
    a.bytes = await File(a.path).readAsBytes();
  }

  // Queue for sending (message already in UI, just updated)
  if (message.attachments.isNotEmpty) {
    OutgoingMsgHandler.queue(OutgoingItem(
      type: QueueType.sendAttachment,
      chat: chat,
      message: message,
    ));
  } else {
    OutgoingMsgHandler.queue(OutgoingItem(
      type: QueueType.sendMessage,
      chat: chat,
      message: message,
    ));
  }
}
