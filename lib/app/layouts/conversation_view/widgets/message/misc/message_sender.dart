import 'dart:ui';

import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MessageSender extends StatelessWidget {
  const MessageSender({super.key, required this.olderMessage, this.googleStyle = false, this.showAvatar = false});

  final Message? olderMessage;

  /// Google Messages layout: a small avatar beside the name, the name in the
  /// contact's colour, above the bubble (no avatar beside the bubble).
  final bool googleStyle;
  final bool showAvatar;

  @override
  Widget build(BuildContext context) {
    final state = MessageStateScope.maybeOf(context);
    if (state == null) return const SizedBox.shrink();
    final chatState = ChatStateScope.maybeOf(context);
    if (googleStyle) {
      return Padding(
        padding: const EdgeInsets.only(left: 5, right: 25, bottom: 4, top: 2),
        child: Obx(() {
          final hex = state.sender?.color.value;
          final address = state.sender?.handle.address ?? state.message.handleRelation.target?.address;
          final nameColor = hex != null ? HexColor(hex) : toColorGradient(address).first;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAvatar) ...[
                ContactAvatarWidget(
                  handle: state.message.handleRelation.target,
                  size: 28,
                  fontSize: 12,
                  borderThickness: 0.1,
                  editable: false,
                  scaleSize: false,
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  state.senderDisplayName,
                  style: context.theme.textTheme.labelLarge!.copyWith(color: nameColor, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25).add(const EdgeInsets.only(bottom: 3)),
      // Obx makes the sender name reactive: updates when contact data syncs.
      child: Obx(() {
        final hasCustomBackground = chatState?.hasCustomWallpaper ?? false;
        final text = Text(
          state.senderDisplayName,
          style: context.theme.textTheme.labelMedium!.copyWith(
            color: hasCustomBackground ? context.theme.colorScheme.onSurface : context.theme.colorScheme.outline,
            fontWeight: FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        if (!hasCustomBackground) return text;
        return Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1.0,
          child: IntrinsicWidth(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: context.theme.colorScheme.surface.withValues(alpha: 0.5),
                  child: text,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
