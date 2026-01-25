import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/interactive_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/text/text_bubble.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/ui/message/message_widget_controller.dart';
import 'package:flutter/material.dart';

/// Renders the appropriate content widget based on message type
/// Extracted from MessageHolder to reduce nesting and improve readability
class MessagePartContent extends StatelessWidget {
  const MessagePartContent({
    super.key,
    required this.parentController,
    required this.message,
    required this.messagePart,
  });

  final MessageWidgetController parentController;
  final Message message;
  final MessagePart messagePart;

  @override
  Widget build(BuildContext context) {
    // Interactive messages (URL previews, GamePigeon, etc.)
    if (message.hasApplePayloadData || message.isLegacyUrlPreview || message.isInteractive) {
      return InteractiveHolder(
        parentController: parentController,
        message: messagePart,
      );
    }

    // Text-only messages
    if (messagePart.attachments.isEmpty && (messagePart.text != null || messagePart.subject != null)) {
      return TextBubble(
        parentController: parentController,
        message: messagePart,
      );
    }

    // Messages with attachments
    if (messagePart.attachments.isNotEmpty) {
      return AttachmentHolder(
        parentController: parentController,
        message: messagePart,
      );
    }

    // Empty/unsupported message
    return const SizedBox.shrink();
  }
}
