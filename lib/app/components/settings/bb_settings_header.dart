import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

/// Theme-aware settings header using BlueBubbles design system.
///
/// This replaces the legacy [SettingsHeader] with better design token integration.
/// Automatically adapts height, padding, and text style based on the current skin.
///
/// ## Features
/// - Uses design tokens for consistent spacing
/// - Theme-specific heights (iOS: 60px, Material: 40px, Samsung: hidden)
/// - Proper text capitalization
/// - Semantic text styling via BBTextStyles
///
/// ## Example
/// ```dart
/// BBSettingsHeader(
///   text: "General Settings",
/// )
/// ```
class BBSettingsHeader extends StatelessWidget {
  const BBSettingsHeader({
    super.key,
    required this.text,
    this.height,
  });

  /// Header text to display
  final String text;

  /// Custom height (overrides default theme-specific height)
  final double? height;

  @override
  Widget build(BuildContext context) {
    final skin = SettingsSvc.settings.skin.value;
    
    // Samsung hides headers
    if (skin == Skins.Samsung) {
      return const SizedBox(height: BBSpacing.lg);
    }

    return Container(
      height: height ?? (skin == Skins.iOS ? 60 : 40),
      alignment: Alignment.bottomLeft,
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: BBSpacing.sm,
          left: skin == Skins.iOS ? 30 : BBSpacing.lg,
        ),
        child: Text(
          text.psCapitalize,
          style: skin == Skins.iOS ? context.iosHeaderStyle : context.materialHeaderStyle,
        ),
      ),
    );
  }
}

/// Extension for header text styles
extension _HeaderStyles on BuildContext {
  TextStyle get iosHeaderStyle {
    return labelLarge.copyWith(
      color: isDark
          ? (samsung ? onBackground : properOnSurface)
          : (samsung ? properOnSurface : onBackground),
      fontWeight: FontWeight.w300,
    );
  }

  TextStyle get materialHeaderStyle {
    return labelLarge.copyWith(
      color: primary,
      fontWeight: FontWeight.bold,
    );
  }
}
