import 'package:bluebubbles/app/components/chat/bb_chat_avatar.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A theme-aware chat header component using BlueBubbles design system.
///
/// This component provides a consistent header display with proper design token usage.
/// The actual header implementations (CupertinoHeader, MaterialHeader) should use
/// this component's patterns for spacing and styling.
///
/// ## Example
/// ```dart
/// BBChatHeader(
///   chat: chat,
///   title: "Chat Name",
///   subtitle: "3 participants",
///   leading: BackButton(),
///   actions: [IconButton(...)],
/// )
/// ```
class BBChatHeader extends StatelessWidget implements PreferredSizeWidget {
  const BBChatHeader({
    super.key,
    required this.chat,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    this.showAvatar = true,
    this.onTitleTap,
    this.backgroundColor,
  });

  final Chat chat;
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final bool showAvatar;
  final VoidCallback? onTitleTap;
  final Color? backgroundColor;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final skin = SettingsSvc.settings.skin.value;
    
    return AppBar(
      backgroundColor: backgroundColor ?? context.theme.colorScheme.properSurface,
      leading: leading,
      leadingWidth: leading != null ? null : 0,
      titleSpacing: leading != null ? BBSpacing.sm : BBSpacing.lg,
      actions: actions,
      title: InkWell(
        onTap: onTitleTap,
        borderRadius: BBRadius.mediumBR(skin),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: BBSpacing.sm,
            vertical: BBSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAvatar) ...[
                BBChatAvatar(
                  chat: chat,
                  size: BBChatAvatarSize.small,
                ),
                const SizedBox(width: BBSpacing.md),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: context.theme.colorScheme.outline,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Helper class for creating header action buttons with consistent styling
class BBHeaderButton extends StatelessWidget {
  const BBHeaderButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final skin = SettingsSvc.settings.skin.value;
    
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(BBSpacing.sm),
      iconSize: 24,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BBRadius.mediumBR(skin),
        ),
      ),
    );
  }
}
