import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

/// Theme-aware settings section container using BlueBubbles design system.
///
/// This replaces the legacy [SettingsSection] with better design token integration.
/// Automatically applies theme-specific border radius, padding, and shadows.
///
/// ## Features
/// - Uses design tokens for consistent border radius
/// - Theme-specific padding (iOS: horizontal, Samsung: vertical, Material: none)
/// - iOS-specific shadow effects
/// - Automatic clipping for rounded corners
///
/// ## Example
/// ```dart
/// BBSettingsSection(
///   backgroundColor: context.properSurface,
///   children: [
///     BBSettingsTile(title: "Setting 1"),
///     BBSettingsTile(title: "Setting 2"),
///   ],
/// )
/// ```
class BBSettingsSection extends StatelessWidget {
  const BBSettingsSection({
    super.key,
    required this.backgroundColor,
    this.children,
  });

  /// Background color for the section
  final Color backgroundColor;

  /// List of child widgets (typically BBSettingsTile widgets)
  final List<Widget>? children;

  @override
  Widget build(BuildContext context) {
    if (children == null || children!.isEmpty) {
      return const SizedBox.shrink();
    }

    final skin = SettingsSvc.settings.skin.value;

    return Padding(
      padding: context.skinPadding,
      child: ClipRRect(
        borderRadius: context.radius.largeBR,
        clipBehavior: skin != Skins.Material ? Clip.antiAlias : Clip.none,
        child: Container(
          color: skin == Skins.iOS ? null : backgroundColor,
          decoration: skin == Skins.iOS
              ? BoxDecoration(
                  color: backgroundColor,
                  borderRadius: context.radius.mediumBR,
                  boxShadow: [
                    BoxShadow(
                      color: backgroundColor.darkenAmount(0.1).withValues(alpha: 0.25),
                      spreadRadius: 5,
                      blurRadius: 7,
                      offset: const Offset(0, 3),
                    ),
                  ],
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: children!,
          ),
        ),
      ),
    );
  }
}

/// Extension to provide skin-specific padding for settings sections
extension _SettingsSectionPadding on BuildContext {
  EdgeInsets get skinPadding {
    final skin = SettingsSvc.settings.skin.value;
    switch (skin) {
      case Skins.iOS:
        return const EdgeInsets.symmetric(horizontal: BBSpacing.xl);
      case Skins.Samsung:
        return const EdgeInsets.symmetric(vertical: BBSpacing.xs);
      case Skins.Material:
        return EdgeInsets.zero;
    }
  }
}
