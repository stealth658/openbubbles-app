import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_line_painter.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Extracted widget for reply bubble section
/// Displays the message being replied to, with appropriate styling based on platform
class ReplyBubbleSection extends StatelessWidget {
  const ReplyBubbleSection({
    super.key,
    required this.replyTo,
    required this.cvController,
    required this.showAvatar,
    required this.alwaysShowAvatars,
    required this.avatarScale,
    required this.isIOS,
    required this.isFirstPart,
  });

  final Message replyTo;
  final ConversationViewController cvController;
  final bool showAvatar;
  final bool alwaysShowAvatars;
  final double avatarScale;
  final bool isIOS;
  final bool isFirstPart;

  @override
  Widget build(BuildContext context) {
    final chat = ChatStateScope.chatOf(context);
    final message = MessageStateScope.messageOf(context);
    final part = replyTo.guid == message.threadOriginatorGuid ? message.normalizedThreadPart : 0;
    final showReplyAvatar = (chat.isGroup || alwaysShowAvatars || !isIOS) && !replyTo.isFromMe!;

    // Provide the replyTo message's state so ReplyBubble displays the original
    // message content rather than the current (reply) message's content.
    final replyToState = MessagesSvc(cvController.chat.guid).getOrCreateState(replyTo);

    Widget replyBubble = MessageStateScope(
      messageState: replyToState,
      child: ReplyBubble(
        part: part,
        showAvatar: showReplyAvatar,
        cvController: cvController,
        // The reply already has its sender's name above it; repeating the same
        // name inside the quote read as two messages from that person.
        showSenderName: !message.sameSender(replyTo),
      ),
    );

    if (isIOS) {
      // iOS style - integrated with message bubble
      // Note: Padding is handled by the parent MessageHolder, not here
      return DecoratedBox(
        decoration: ReplyLineDecoration(
          isFromMe: message.isFromMe!,
          color: context.theme.colorScheme.surfaceContainerHighest,
          connectUpper: false,
          connectLower: false,
          context: context,
        ),
        child: Container(
          width: double.infinity,
          alignment: replyTo.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
          child: replyBubble,
        ),
      );
    } else {
      // Android/Material style: a small, faded quote of the original above the
      // reply (lighter than a message, so it does not read as one), aligned to
      // the side the original was sent from.
      final hasBackground = ChatStateScope.maybeOf(context)?.hasCustomWallpaper ?? false;
      final lineColor = context.theme.colorScheme.outlineVariant;
      final quote = ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: hasBackground ? 0.85 : 0.45),
          ),
          child: replyBubble,
        ),
      );
      // A thin line beside the quote that runs down into the reply, the way
      // iMessage ties the two together.
      final line = Container(
        width: 2,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(1)),
      );
      return Padding(
        padding: showAvatar || alwaysShowAvatars
            ? const EdgeInsets.only(left: 45.0, right: 10)
            : const EdgeInsets.only(left: 10, right: 10),
        child: Align(
          alignment: message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: message.isFromMe!
                  ? [Flexible(child: quote), const SizedBox(width: 6), line]
                  : [line, const SizedBox(width: 6), Flexible(child: quote)],
            ),
          ),
        ),
      );
    }
  }
}
