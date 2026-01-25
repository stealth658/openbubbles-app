import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_line_painter.dart';
import 'package:bluebubbles/helpers/helpers.dart';
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
    required this.message,
    required this.chat,
    required this.cvController,
    required this.showAvatar,
    required this.alwaysShowAvatars,
    required this.avatarScale,
    required this.isIOS,
    required this.isFirstPart,
  });

  final Message replyTo;
  final Message message;
  final Chat chat;
  final ConversationViewController cvController;
  final bool showAvatar;
  final bool alwaysShowAvatars;
  final double avatarScale;
  final bool isIOS;
  final bool isFirstPart;

  @override
  Widget build(BuildContext context) {
    final controller = MessagesSvc(chat.guid).getControllerIfExists(replyTo.guid!);
    if (controller == null) return const SizedBox.shrink();

    final part = replyTo.guid == message.threadOriginatorGuid ? message.normalizedThreadPart : 0;
    final showReplyAvatar = (chat.isGroup || alwaysShowAvatars || !isIOS) && !replyTo.isFromMe!;

    if (isIOS) {
      // iOS style - integrated with message bubble
      return Padding(
        padding: showAvatar || alwaysShowAvatars ? EdgeInsets.only(left: 35.0 * avatarScale) : EdgeInsets.zero,
        child: DecoratedBox(
          decoration: SettingsSvc.settings.skin.value == Skins.iOS
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.fromBorderSide(BorderSide(color: context.theme.colorScheme.outline, width: 2)),
                )
              : ReplyLineDecoration(
                  isFromMe: message.isFromMe!,
                  color: context.theme.colorScheme.properSurface,
                  connectUpper: false,
                  connectLower: true,
                  context: context,
                ),
          child: Container(
            width: double.infinity,
            alignment: replyTo.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
            child: ReplyBubble(
              parentController: controller,
              part: part,
              showAvatar: showReplyAvatar,
              cvController: cvController,
            ),
          ),
        ),
      );
    } else {
      // Android/Material style - separate decorative box
      return Padding(
        padding: showAvatar || alwaysShowAvatars
            ? const EdgeInsets.only(left: 45.0, right: 10)
            : const EdgeInsets.symmetric(horizontal: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            border: Border.fromBorderSide(BorderSide(color: context.theme.colorScheme.properSurface)),
          ),
          child: ReplyBubble(
            parentController: controller,
            part: part,
            showAvatar: showReplyAvatar,
            cvController: cvController,
          ),
        ),
      );
    }
  }
}
