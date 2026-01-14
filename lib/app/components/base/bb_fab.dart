import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Theme-adaptive Floating Action Button.
/// 
/// Each skin has different FAB behavior:
/// - iOS: Circular FAB, top-right placement
/// - Material: Extended FAB with text, center-bottom placement
/// - Samsung: Circular FAB, bottom-right placement
/// 
/// Example usage:
/// ```dart
/// BBFAB(
///   icon: Icons.add,
///   label: 'New Chat',
///   onPressed: () => print('FAB pressed'),
/// )
/// ```
class BBFAB extends StatelessWidget {
  const BBFAB({
    super.key,
    required this.icon,
    this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.mini = false,
  });

  /// Icon to display
  final IconData icon;
  
  /// Optional label (used in Material extended FAB)
  final String? label;
  
  /// Callback when FAB is pressed
  final VoidCallback onPressed;
  
  /// Background color
  final Color? backgroundColor;
  
  /// Icon/text color
  final Color? foregroundColor;
  
  /// Whether to use mini FAB
  final bool mini;

  @override
  Widget build(BuildContext context) {
    return ThemeSwitcher(
      iOSSkin: _IOSFAB(
        icon: icon,
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        mini: mini,
      ),
      materialSkin: _MaterialFAB(
        icon: icon,
        label: label,
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        mini: mini,
      ),
      samsungSkin: _SamsungFAB(
        icon: icon,
        onPressed: onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        mini: mini,
      ),
    );
  }
}

// ============================================================================
// iOS Implementation
// ============================================================================

class _IOSFAB extends StatelessWidget {
  const _IOSFAB({
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    required this.mini,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    final size = mini ? 44.0 : BBSizing.fabSize;
    final iconSize = mini ? 20.0 : 24.0;
    
    return SizedBox(
      width: size,
      height: size,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: backgroundColor ?? context.primary,
        borderRadius: BorderRadius.circular(size / 2),
        onPressed: onPressed,
        child: Icon(
          icon,
          size: iconSize,
          color: foregroundColor ?? context.onPrimary,
        ),
      ),
    );
  }
}

// ============================================================================
// Material Implementation
// ============================================================================

class _MaterialFAB extends StatelessWidget {
  const _MaterialFAB({
    required this.icon,
    this.label,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    required this.mini,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    // Material uses extended FAB when label is provided
    if (label != null && !mini) {
      return FloatingActionButton.extended(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label!),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      );
    }

    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      mini: mini,
      child: Icon(icon),
    );
  }
}

// ============================================================================
// Samsung Implementation
// ============================================================================

class _SamsungFAB extends StatelessWidget {
  const _SamsungFAB({
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    required this.mini,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final bool mini;

  @override
  Widget build(BuildContext context) {
    // Samsung uses circular FAB similar to iOS but with Material styling
    return FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      mini: mini,
      elevation: 4.0, // Samsung has more pronounced elevation
      child: Icon(icon),
    );
  }
}
