import 'package:flutter/material.dart';
import 'package:bluebubbles/core/constants/app_constants.dart';

/// Central design tokens for spacing, sizing, radius, and other constants
/// following the BlueBubbles widget refactor action plan.
class BBSpacing {
  // Spacing scale (following 8px grid for consistency)
  static const double xxs = 2.0;  // For very tight spacing
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 24.0;

  // Common padding presets
  static const EdgeInsets paddingXS = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD = EdgeInsets.all(md);
  static const EdgeInsets paddingLG = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL = EdgeInsets.all(xl);
  static const EdgeInsets paddingXXL = EdgeInsets.all(xxl);

  // Horizontal padding
  static const EdgeInsets horizontalXS = EdgeInsets.symmetric(horizontal: xs);
  static const EdgeInsets horizontalSM = EdgeInsets.symmetric(horizontal: sm);
  static const EdgeInsets horizontalMD = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets horizontalLG = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalXL = EdgeInsets.symmetric(horizontal: xl);
  static const EdgeInsets horizontalXXL = EdgeInsets.symmetric(horizontal: xxl);

  // Vertical padding
  static const EdgeInsets verticalXS = EdgeInsets.symmetric(vertical: xs);
  static const EdgeInsets verticalSM = EdgeInsets.symmetric(vertical: sm);
  static const EdgeInsets verticalMD = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets verticalLG = EdgeInsets.symmetric(vertical: lg);
  static const EdgeInsets verticalXL = EdgeInsets.symmetric(vertical: xl);
  static const EdgeInsets verticalXXL = EdgeInsets.symmetric(vertical: xxl);
}

/// Border radius values that adapt to the current theme/skin
class BBRadius {
  // Get theme-specific radius values
  static double small(Skins skin) {
    switch (skin) {
      case Skins.iOS:
        return 6.0;
      case Skins.Material:
        return 4.0;
      case Skins.Samsung:
        return 10.0;
    }
  }

  static double medium(Skins skin) {
    switch (skin) {
      case Skins.iOS:
        return 10.0;
      case Skins.Material:
        return 8.0;
      case Skins.Samsung:
        return 18.0;
    }
  }

  static double large(Skins skin) {
    switch (skin) {
      case Skins.iOS:
        return 15.0;
      case Skins.Material:
        return 12.0;
      case Skins.Samsung:
        return 25.0;
    }
  }

  static double extraLarge(Skins skin) {
    switch (skin) {
      case Skins.iOS:
        return 20.0;
      case Skins.Material:
        return 16.0;
      case Skins.Samsung:
        return 30.0;
    }
  }

  // BorderRadius helpers
  static BorderRadius smallBR(Skins skin) => BorderRadius.circular(small(skin));
  static BorderRadius mediumBR(Skins skin) => BorderRadius.circular(medium(skin));
  static BorderRadius largeBR(Skins skin) => BorderRadius.circular(large(skin));
  static BorderRadius extraLargeBR(Skins skin) => BorderRadius.circular(extraLarge(skin));
}

/// Common component sizes
class BBSizing {
  // Icon sizes
  static const double iconXS = 16.0;
  static const double iconSM = 20.0;
  static const double iconMD = 24.0;
  static const double iconLG = 32.0;
  static const double iconXL = 48.0;

  // Avatar sizes
  static const double avatarSM = 32.0;
  static const double avatarMD = 40.0;
  static const double avatarLG = 56.0;
  static const double avatarXL = 72.0;

  // Button heights
  static const double buttonSM = 32.0;
  static const double buttonMD = 44.0;
  static const double buttonLG = 56.0;

  // Standard dimensions
  static const double fabSize = 56.0;
  static const double toolbarHeight = 56.0;
  static const double minTouchTarget = 44.0;
}

/// Animation duration constants
class BBDuration {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
}

/// Opacity levels for window effects and overlays
enum OpacityLevel {
  none(0.0),
  subtle(0.2),
  medium(0.5),
  strong(0.8),
  full(1.0);

  const OpacityLevel(this.value);
  final double value;
}

/// Blur intensity levels for image effects and backgrounds
class BBBlur {
  /// No blur
  static const double none = 0.0;
  
  /// Subtle blur for slight background softening
  static const double subtle = 5.0;
  
  /// Medium blur for backgrounds behind content
  static const double medium = 15.0;
  
  /// Strong blur for media gallery backgrounds
  static const double strong = 20.0;
  
  /// Extra strong blur for heavily obscured backgrounds
  static const double extraStrong = 30.0;
}
