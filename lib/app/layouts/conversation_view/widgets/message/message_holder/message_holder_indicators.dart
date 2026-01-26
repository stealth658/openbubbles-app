import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/shared/message_error_helper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/delivered_indicator.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Isolated widget for delivered indicator
/// Only rebuilds when tapped state changes
class DeliveredIndicatorObserver extends StatelessWidget {
  const DeliveredIndicatorObserver({
    super.key,
    required this.controller,
    required this.tapped,
  });

  final MessageWidgetController controller;
  final RxBool tapped;

  @override
  Widget build(BuildContext context) {
    return Obx(() => DeliveredIndicator(
          parentController: controller,
          forceShow: tapped.value,
        ));
  }
}

/// Isolated widget for error indicator
/// Only rebuilds when error state changes
class ErrorIndicatorObserver extends StatelessWidget {
  const ErrorIndicatorObserver({
    super.key,
    required this.controller,
    required this.message,
    required this.chat,
    required this.service,
  });

  final MessageWidgetController controller;
  final Message message;
  final Chat chat;
  final MessagesService service;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Observe MessageState error field directly instead of boolean toggle
      final hasError = controller.messageState?.hasError.value ?? (message.error > 0);

      if (hasError) {
        final errorCode = message.error;
        final errorText = ErrorHelper.getErrorText(errorCode, message.guid);

        return IconButton(
          icon: Icon(
            SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.exclamationmark_circle : Icons.error_outline,
            color: context.theme.colorScheme.error,
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (BuildContext context) => MessageErrorDialog(
                errorCode: errorCode,
                errorText: errorText,
                chatId: chat.id!,
                onRetry: () => retryMessage(
                  message: message,
                  chat: chat,
                  service: service,
                  controller: controller,
                ),
                onRemove: () async {
                  // Delete the message from DB and remove from service
                  await service.deleteMessage(message);
                  // Get the "new" latest info
                  List<Message> latest = await Chat.getMessagesAsync(chat, limit: 1);
                  chat.latestMessage = latest.first;
                  await chat.saveAsync();
                },
              ),
            );
          },
        );
      }
      return const SizedBox.shrink();
    });
  }
}
