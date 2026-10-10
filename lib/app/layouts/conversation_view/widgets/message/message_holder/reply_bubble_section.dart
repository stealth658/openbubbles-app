import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_bubble.dart';
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
    final message = MessageStateScope.messageOf(context);
    final part = replyTo.guid == message.threadOriginatorGuid ? message.normalizedThreadPart : 0;

    // Provide the replyTo message's state so ReplyBubble displays the original
    // message content rather than the current (reply) message's content.
    final replyToState = MessagesSvc(cvController.chat.guid).getOrCreateState(replyTo);

    Widget replyBubble = MessageStateScope(
      messageState: replyToState,
      child: ReplyBubble(
        part: part,
        // The small avatar in the column says who wrote it; iMessage puts no
        // name on the quote.
        showAvatar: false,
        cvController: cvController,
        showSenderName: false,
      ),
    );

    // iMessage's layout on every skin: the quoted original with a small
    // faded avatar of its author in the avatar column, and a thin line
    // running from that avatar down to the reply's own avatar. On our own
    // side the quote sits right-aligned with the line beside it.
    final lineColor = replyLineColor(context);
    final hasBackground = ChatStateScope.maybeOf(context)?.hasCustomWallpaper ?? false;
    final Widget quote;
    if (isIOS) {
      quote = replyBubble;
    } else {
      quote = ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: hasBackground ? 0.85 : 0.45),
          ),
          child: replyBubble,
        ),
      );
    }
    final line = Container(
      width: 2,
      decoration: BoxDecoration(color: lineColor, borderRadius: BorderRadius.circular(1)),
    );
    final avatarsOn = showAvatar || alwaysShowAvatars;
    if (!message.isFromMe! && avatarsOn) {
      // Same box as the reply's avatar (5px in, 35*scale wide, see
      // MessageHolder), so the small avatar and the line are centred on it.
      final column = (isIOS ? 30.0 : 35.0) * avatarScale;
      return Padding(
        padding: const EdgeInsets.only(left: 5.0, right: 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: column,
                child: Column(
                  children: [
                    if (!replyTo.isFromMe!)
                      Opacity(
                        opacity: 0.7,
                        child: ContactAvatarWidget(
                          handle: replyTo.handleRelation.target,
                          size: 22,
                          fontSize: 11,
                          borderThickness: 0.1,
                          editable: false,
                          scaleSize: false,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Expanded(child: Center(child: line)),
                  ],
                ),
              ),
              SizedBox(width: isIOS ? 0 : 10),
              Flexible(child: Align(alignment: Alignment.centerLeft, child: quote)),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Align(
        alignment: message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: message.isFromMe!
                ? [Flexible(child: quote), const SizedBox(width: 6), Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: line)]
                : [Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: line), const SizedBox(width: 6), Flexible(child: quote)],
          ),
        ),
      ),
    );
  }
}

/// The thin reply-thread line: a light grey that sits back from the bubbles
/// (iMessage uses roughly the separator colour), on every skin.
Color replyLineColor(BuildContext context) =>
    context.theme.colorScheme.outlineVariant.withValues(alpha: context.theme.brightness == Brightness.dark ? 0.8 : 0.55);
