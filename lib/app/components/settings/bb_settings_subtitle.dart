import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A theme-aware settings subtitle component using BlueBubbles design system.
///
/// This replaces the legacy [SettingsSubtitle] with better design token integration
/// and consistent spacing. Displays explanatory text below a settings group.
///
/// ## Example
/// ```dart
/// BBSettingsSubtitle(
///   text: "This setting controls how videos are displayed in the app.",
/// )
/// 
/// BBSettingsSubtitle(
///   text: "Tap to edit the base color\nLong press to edit on-color",
///   unlimitedSpace: true,
///   bottomPadding: false,
/// )
/// ```
class BBSettingsSubtitle extends StatelessWidget {
  const BBSettingsSubtitle({
    super.key,
    required this.text,
    this.unlimitedSpace = false,
    this.bottomPadding = true,
  });

  /// The subtitle text to display
  final String text;

  /// Whether to allow unlimited lines (default: 2 max lines)
  final bool unlimitedSpace;

  /// Whether to include bottom padding (default: true)
  final bool bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: bottomPadding 
          ? const EdgeInsets.only(bottom: BBSpacing.md) 
          : EdgeInsets.zero,
      child: ListTile(
        title: Text(
          text,
          style: context.textTheme.bodySmall!.copyWith(
            color: context.theme.colorScheme.properOnSurface.withValues(alpha: 0.75),
          ),
          maxLines: unlimitedSpace ? 100 : 2,
          overflow: TextOverflow.ellipsis,
        ),
        minVerticalPadding: 0,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: BBSpacing.lg),
      ),
    );
  }
}
