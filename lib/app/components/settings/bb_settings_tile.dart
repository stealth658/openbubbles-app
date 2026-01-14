import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_html/html.dart' as html;

/// A theme-aware settings tile component using BlueBubbles design system.
///
/// This replaces the legacy [SettingsTile] with better design token integration
/// and simplified API. Automatically adapts to the current skin (iOS, Material, Samsung).
///
/// ## Features
/// - Uses design tokens for consistent spacing
/// - Simplified API (title as String, optional value display)
/// - Proper ink splash effects
/// - Context menu support on web
/// - Accessible and keyboard-friendly
///
/// ## Example
/// ```dart
/// BBSettingsTile(
///   title: "Redacted Mode",
///   value: "Enabled",
///   leading: BBSettingsIcon(
///     iosIcon: CupertinoIcons.wand_stars,
///     materialIcon: Icons.auto_fix_high,
///     color: Colors.green,
///   ),
///   onTap: () => Navigator.push(...),
/// )
/// ```
class BBSettingsTile extends StatelessWidget {
  const BBSettingsTile({
    super.key,
    required this.title,
    this.value,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.dense = true,
  });

  /// The main title text of the tile
  final String title;

  /// Optional value to display on the right (e.g., "Enabled", "10 minutes")
  /// If both [value] and [trailing] are provided, [trailing] takes precedence
  final String? value;

  /// Optional subtitle text below the title
  final String? subtitle;

  /// Leading widget (typically a BBSettingsIcon)
  final Widget? leading;

  /// Custom trailing widget (replaces default value display)
  final Widget? trailing;

  /// Callback when tile is tapped
  final VoidCallback? onTap;

  /// Callback when tile is long-pressed (or right-clicked on web)
  final VoidCallback? onLongPress;

  /// Whether to use dense layout
  final bool dense;

  @override
  Widget build(BuildContext context) {
    // Build the trailing widget
    Widget? trailingWidget = trailing;
    if (trailingWidget == null && value != null) {
      trailingWidget = Text(
        value!,
        style: context.textTheme.bodyMedium!.apply(
          color: context.theme.colorScheme.outline.withValues(alpha: 0.85),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: context.theme.colorScheme.surfaceVariant,
        splashFactory: context.theme.splashFactory,
        child: GestureDetector(
          onSecondaryTapUp: (details) async {
            if (kIsWeb && onLongPress != null) {
              (await html.document.onContextMenu.first).preventDefault();
              onLongPress!();
            }
          },
          child: ListTile(
            mouseCursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
            enableFeedback: true,
            minVerticalPadding: (dense) ? BBSpacing.md : BBSpacing.xl,
            horizontalTitleGap: BBSpacing.md,
            dense: context.iOS,
            leading: leading == null
                ? null
                : Padding(
                    padding: EdgeInsets.only(
                      bottom: !dense ? BBSpacing.md : 0.0,
                      right: BBSpacing.xs,
                      left: BBSpacing.xs,
                    ),
                    child: leading,
                  ),
            title: Text(
              title,
              style: context.textTheme.bodyLarge,
            ),
            trailing: trailingWidget == null
                ? null
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [trailingWidget],
                  ),
            subtitle: subtitle != null
                ? Text(
                    subtitle!,
                    style: context.textTheme.bodySmall!.copyWith(
                      color: context.theme.colorScheme.properOnSurface.withValues(alpha: 0.75),
                      height: 1.5,
                    ),
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: BBSpacing.lg),
          ),
        ),
      ),
    );
  }
}
