import 'package:bluebubbles/app/components/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A theme-aware chat avatar component using BlueBubbles design system.
///
/// This component provides a consistent avatar display across different chat contexts
/// (conversation list, headers, etc.) with automatic theme adaptation.
///
/// ## Example
/// ```dart
/// BBChatAvatar(
///   chat: chat,
///   size: BBChatAvatarSize.medium,
///   showUnreadIndicator: true,
/// )
/// ```
class BBChatAvatar extends StatelessWidget {
  const BBChatAvatar({
    super.key,
    required this.chat,
    this.size = BBChatAvatarSize.medium,
    this.showUnreadIndicator = false,
    this.showReadReceipt = false,
    this.onTap,
  });

  final Chat chat;
  final BBChatAvatarSize size;
  final bool showUnreadIndicator;
  final bool showReadReceipt;
  final VoidCallback? onTap;

  double get _avatarSize {
    switch (size) {
      case BBChatAvatarSize.small:
        return 35.0;
      case BBChatAvatarSize.medium:
        return 40.0;
      case BBChatAvatarSize.large:
        return 60.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _avatarSize,
        height: _avatarSize,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main avatar
            ContactAvatarGroupWidget(
              chat: chat,
              size: _avatarSize,
              editable: false,
            ),
            // Unread indicator
            if (showUnreadIndicator && (chat.hasUnreadMessage ?? false))
              Positioned(
                top: -BBSpacing.xs,
                right: -BBSpacing.xs,
                child: Container(
                  width: BBSpacing.md,
                  height: BBSpacing.md,
                  decoration: BoxDecoration(
                    color: context.theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.theme.colorScheme.properSurface,
                      width: 2.0,
                    ),
                  ),
                ),
              ),
            // Read receipt indicator
            if (showReadReceipt && !chat.isGroup && chat.latestMessage.dateRead != null)
              Positioned(
                bottom: -BBSpacing.xs / 2,
                right: -BBSpacing.xs / 2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: context.theme.colorScheme.properSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.done_all,
                    size: 12,
                    color: context.theme.colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum BBChatAvatarSize {
  small,
  medium,
  large,
}
