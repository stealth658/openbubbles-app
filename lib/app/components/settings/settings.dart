/// BlueBubbles Settings Components
/// 
/// This library provides theme-aware settings UI components using the
/// BlueBubbles design system. These components replace legacy settings
/// widgets with better design token integration and simplified APIs.
/// 
/// Example:
/// ```dart
/// import 'package:bluebubbles/app/components/settings/settings.dart';
/// 
/// BBSettingsSection(
///   backgroundColor: context.properSurface,
///   children: [
///     BBSettingsTile(
///       title: "Dark Mode",
///       value: "Enabled",
///       leading: BBSettingsIcon(
///         iosIcon: CupertinoIcons.moon,
///         materialIcon: Icons.dark_mode,
///         color: Colors.indigo,
///       ),
///       onTap: () => ...,
///     ),
///     BBSettingsSwitch(
///       title: "Notifications",
///       value: true,
///       onChanged: (val) => ...,
///     ),
///   ],
/// )
/// ```
library settings;

export 'bb_settings_dropdown.dart';
export 'bb_settings_header.dart';
export 'bb_settings_icon.dart';
export 'bb_settings_section.dart';
export 'bb_settings_switch.dart';
export 'bb_settings_tile.dart';
