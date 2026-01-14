import 'package:flutter/material.dart';

/// Dialog button types for styling
enum BBDialogButtonType {
  /// Primary action button (emphasized)
  primary,
  
  /// Secondary action button (normal emphasis)
  secondary,
  
  /// Destructive action button (red/warning color)
  destructive,
  
  /// Cancel/dismiss action button
  cancel,
}

/// Dialog sizes
enum BBDialogSize {
  /// Small dialog - 280pt iOS, 280dp Material
  small,
  
  /// Medium dialog - 320pt iOS, 320dp Material (default)
  medium,
  
  /// Large dialog - 400pt iOS, 400dp Material
  large,
  
  /// Auto-size to content
  auto,
}

/// Common dialog configuration base class
class BBDialogConfig {
  const BBDialogConfig({
    this.title,
    this.barrierDismissible = true,
    this.size = BBDialogSize.medium,
    this.contentPadding,
    this.barrierColor,
    this.barrierLabel,
    this.useRootNavigator = true,
    this.enableAnimations = true,
    this.fullscreen = false,
    this.semanticLabel,
  });

  /// Dialog title (optional)
  final String? title;
  
  /// Whether the dialog can be dismissed by tapping outside
  final bool barrierDismissible;
  
  /// Size of the dialog
  final BBDialogSize size;
  
  /// Custom content padding
  final EdgeInsets? contentPadding;
  
  /// Custom barrier color
  final Color? barrierColor;
  
  /// Barrier semantic label for accessibility
  final String? barrierLabel;
  
  /// Whether to use root navigator
  final bool useRootNavigator;
  
  /// Enable entry/exit animations (iOS: scale+fade, Material: fade+slide)
  final bool enableAnimations;
  
  /// Show dialog in fullscreen mode (mobile only)
  final bool fullscreen;
  
  /// Semantic label for screen readers
  final String? semanticLabel;

  /// Get the appropriate max width for the dialog size
  double getMaxWidth(bool isTablet) {
    switch (size) {
      case BBDialogSize.small:
        return 280;
      case BBDialogSize.medium:
        return isTablet ? 320 : 280;
      case BBDialogSize.large:
        return isTablet ? 560 : 400;
      case BBDialogSize.auto:
        return double.infinity;
    }
  }
}
