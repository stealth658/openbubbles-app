import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Standard icon button sizes
enum BBIconButtonSize {
  /// 32x32 button
  small,
  
  /// 40x40 button (default)
  medium,
  
  /// 48x48 button
  large,
}

/// Theme-adaptive icon button component that automatically uses the correct
/// button implementation for the current skin (iOS, Material, Samsung).
/// 
/// Provides consistent sizing and styling across themes.
/// 
/// Example usage:
/// ```dart
/// BBIconButton(
///   icon: Icons.close,
///   onPressed: () => Navigator.pop(context),
/// )
/// ```
class BBIconButton extends StatelessWidget {
  const BBIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = BBIconButtonSize.medium,
    this.color,
    this.backgroundColor,
    this.tooltip,
  });

  /// Icon to display
  final IconData icon;
  
  /// Callback when button is pressed
  final VoidCallback? onPressed;
  
  /// Size of the button
  final BBIconButtonSize size;
  
  /// Custom icon color
  final Color? color;
  
  /// Custom background color
  final Color? backgroundColor;
  
  /// Tooltip text
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return ThemeSwitcher(
      iOSSkin: _IOSIconButton(
        icon: icon,
        onPressed: onPressed,
        size: size,
        color: color,
        backgroundColor: backgroundColor,
        tooltip: tooltip,
      ),
      materialSkin: _MaterialIconButton(
        icon: icon,
        onPressed: onPressed,
        size: size,
        color: color,
        backgroundColor: backgroundColor,
        tooltip: tooltip,
      ),
      samsungSkin: _SamsungIconButton(
        icon: icon,
        onPressed: onPressed,
        size: size,
        color: color,
        backgroundColor: backgroundColor,
        tooltip: tooltip,
      ),
    );
  }
}

// iOS-specific implementation
class _IOSIconButton extends StatelessWidget {
  const _IOSIconButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    this.color,
    this.backgroundColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final BBIconButtonSize size;
  final Color? color;
  final Color? backgroundColor;
  final String? tooltip;

  double get _buttonSize {
    switch (size) {
      case BBIconButtonSize.small:
        return 32;
      case BBIconButtonSize.medium:
        return 40;
      case BBIconButtonSize.large:
        return 48;
    }
  }

  double get _iconSize {
    switch (size) {
      case BBIconButtonSize.small:
        return 18;
      case BBIconButtonSize.medium:
        return 22;
      case BBIconButtonSize.large:
        return 26;
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size(_buttonSize, _buttonSize),
      onPressed: onPressed,
      color: backgroundColor,
      borderRadius: BorderRadius.circular(_buttonSize / 2),
      child: Icon(
        icon,
        size: _iconSize,
        color: color ?? context.theme.colorScheme.onSurface,
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip!,
        child: button,
      );
    }

    return button;
  }
}

// Material-specific implementation
class _MaterialIconButton extends StatelessWidget {
  const _MaterialIconButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    this.color,
    this.backgroundColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final BBIconButtonSize size;
  final Color? color;
  final Color? backgroundColor;
  final String? tooltip;

  double get _iconSize {
    switch (size) {
      case BBIconButtonSize.small:
        return 18;
      case BBIconButtonSize.medium:
        return 22;
      case BBIconButtonSize.large:
        return 26;
    }
  }

  BoxConstraints get _constraints {
    switch (size) {
      case BBIconButtonSize.small:
        return const BoxConstraints(minWidth: 32, minHeight: 32);
      case BBIconButtonSize.medium:
        return const BoxConstraints(minWidth: 40, minHeight: 40);
      case BBIconButtonSize.large:
        return const BoxConstraints(minWidth: 48, minHeight: 48);
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = backgroundColor != null
        ? IconButton.filled(
            onPressed: onPressed,
            icon: Icon(icon),
            iconSize: _iconSize,
            color: color,
            style: IconButton.styleFrom(
              backgroundColor: backgroundColor,
            ),
            constraints: _constraints,
            tooltip: tooltip,
          )
        : IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            iconSize: _iconSize,
            color: color,
            constraints: _constraints,
            tooltip: tooltip,
          );

    return button;
  }
}

// Samsung-specific implementation
class _SamsungIconButton extends StatelessWidget {
  const _SamsungIconButton({
    required this.icon,
    required this.onPressed,
    required this.size,
    this.color,
    this.backgroundColor,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final BBIconButtonSize size;
  final Color? color;
  final Color? backgroundColor;
  final String? tooltip;

  double get _iconSize {
    switch (size) {
      case BBIconButtonSize.small:
        return 18;
      case BBIconButtonSize.medium:
        return 22;
      case BBIconButtonSize.large:
        return 26;
    }
  }

  BoxConstraints get _constraints {
    switch (size) {
      case BBIconButtonSize.small:
        return const BoxConstraints(minWidth: 32, minHeight: 32);
      case BBIconButtonSize.medium:
        return const BoxConstraints(minWidth: 40, minHeight: 40);
      case BBIconButtonSize.large:
        return const BoxConstraints(minWidth: 48, minHeight: 48);
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = backgroundColor != null
        ? IconButton.filled(
            onPressed: onPressed,
            icon: Icon(icon),
            iconSize: _iconSize,
            color: color,
            style: IconButton.styleFrom(
              backgroundColor: backgroundColor,
              padding: const EdgeInsets.all(BBSpacing.sm),
            ),
            constraints: _constraints,
            tooltip: tooltip,
          )
        : IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            iconSize: _iconSize,
            color: color,
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(BBSpacing.sm),
            ),
            constraints: _constraints,
            tooltip: tooltip,
          );

    return button;
  }
}
