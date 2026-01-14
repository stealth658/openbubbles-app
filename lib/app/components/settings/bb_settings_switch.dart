import 'package:bluebubbles/app/components/settings/bb_settings_tile.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';

/// A theme-aware switch tile for settings using BlueBubbles design system.
///
/// This is a convenience widget that combines BBSettingsTile with a Switch.
/// Replaces the legacy [SettingsSwitch] with better design token integration.
///
/// ## Features
/// - Single-tap to toggle (no need to tap the switch directly)
/// - Properly styled switch colors
/// - Uses design tokens for consistent spacing
/// - Optional leading icon and subtitle
///
/// ## Example
/// ```dart
/// BBSettingsSwitch(
///   title: "Enable Notifications",
///   subtitle: "Receive alerts for new messages",
///   value: settings.notificationsEnabled.value,
///   onChanged: (val) => settings.notificationsEnabled.value = val,
///   leading: BBSettingsIcon(
///     iosIcon: CupertinoIcons.bell,
///     materialIcon: Icons.notifications,
///   ),
/// )
/// ```
class BBSettingsSwitch extends StatelessWidget {
  const BBSettingsSwitch({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    this.isThreeLine = false,
  });

  /// The main title text of the tile
  final String title;

  /// Current switch value
  final bool value;

  /// Callback when switch is toggled
  final ValueChanged<bool> onChanged;

  /// Optional subtitle text below the title
  final String? subtitle;

  /// Leading widget (typically a BBSettingsIcon)
  final Widget? leading;

  /// Whether the tile should accommodate three lines of text
  final bool isThreeLine;

  @override
  Widget build(BuildContext context) {
    return BBSettingsTile(
      title: title,
      subtitle: subtitle,
      leading: leading,
      onTap: () => onChanged(!value),
      dense: subtitle != null,
      trailing: Switch(
        value: value,
        activeThumbColor: context.primary.lightenOrDarken(15),
        onChanged: onChanged,
      ),
    );
  }
}
