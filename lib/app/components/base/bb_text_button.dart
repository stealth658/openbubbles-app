import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Theme-adaptive text button component that automatically uses the correct
/// button implementation for the current skin (iOS, Material, Samsung).
/// 
/// Useful for secondary actions, cancel buttons, and link-style interactions.
/// 
/// Example usage:
/// ```dart
/// BBTextButton(
///   label: 'Cancel',
///   onPressed: () => Navigator.pop(context),
/// )
/// ```
class BBTextButton extends StatelessWidget {
  const BBTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.fontSize,
    this.fontWeight,
  });

  /// Button text label
  final String label;
  
  /// Callback when button is pressed
  final VoidCallback? onPressed;
  
  /// Optional icon to show before label
  final IconData? icon;
  
  /// Custom text color (uses primary color by default)
  final Color? color;
  
  /// Custom font size
  final double? fontSize;
  
  /// Custom font weight
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    return ThemeSwitcher(
      iOSSkin: _IOSTextButton(
        label: label,
        onPressed: onPressed,
        icon: icon,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
      materialSkin: _MaterialTextButton(
        label: label,
        onPressed: onPressed,
        icon: icon,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
      samsungSkin: _SamsungTextButton(
        label: label,
        onPressed: onPressed,
        icon: icon,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
  }
}

// iOS-specific implementation
class _IOSTextButton extends StatelessWidget {
  const _IOSTextButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.fontSize,
    this.fontWeight,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.theme.colorScheme.primary;

    Widget child = Text(
      label,
      style: TextStyle(
        color: effectiveColor,
        fontSize: fontSize ?? 17,
        fontWeight: fontWeight ?? FontWeight.w400,
      ),
    );

    if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: effectiveColor),
          const SizedBox(width: BBSpacing.xs),
          child,
        ],
      );
    }

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(
        horizontal: BBSpacing.md,
        vertical: BBSpacing.xs,
      ),
      onPressed: onPressed,
      child: child,
    );
  }
}

// Material-specific implementation
class _MaterialTextButton extends StatelessWidget {
  const _MaterialTextButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.fontSize,
    this.fontWeight,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          textStyle: TextStyle(
            fontSize: fontSize ?? 14,
            fontWeight: fontWeight ?? FontWeight.w500,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: BBSpacing.md,
            vertical: BBSpacing.sm,
          ),
        ),
      );
    }

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        textStyle: TextStyle(
          fontSize: fontSize ?? 14,
          fontWeight: fontWeight ?? FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BBSpacing.md,
          vertical: BBSpacing.sm,
        ),
      ),
      child: Text(label),
    );
  }
}

// Samsung-specific implementation
class _SamsungTextButton extends StatelessWidget {
  const _SamsungTextButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.color,
    this.fontSize,
    this.fontWeight,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? color;
  final double? fontSize;
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: color,
          textStyle: TextStyle(
            fontSize: fontSize ?? 14,
            fontWeight: fontWeight ?? FontWeight.w600,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: BBSpacing.lg,
            vertical: BBSpacing.sm,
          ),
        ),
      );
    }

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        textStyle: TextStyle(
          fontSize: fontSize ?? 14,
          fontWeight: fontWeight ?? FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BBSpacing.lg,
          vertical: BBSpacing.sm,
        ),
      ),
      child: Text(label),
    );
  }
}
