import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:flutter/material.dart';

/// Unified tappable widget that handles gesture detection with proper feedback.
/// 
/// Replaces the common pattern of wrapping widgets with GestureDetector or InkWell
/// with a single, consistent component that provides proper touch feedback.
/// 
/// Example usage:
/// ```dart
/// BBTappable(
///   onTap: () => print('Tapped'),
///   child: Text('Tap me'),
/// )
/// 
/// // With custom border radius
/// BBTappable(
///   onTap: () => print('Tapped'),
///   borderRadius: BorderRadius.circular(20),
///   child: Container(...),
/// )
/// ```
class BBTappable extends StatelessWidget {
  const BBTappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.borderRadius,
    this.useMaterialInk = false,
    this.backgroundColor,
  });

  /// The widget below this widget in the tree
  final Widget child;
  
  /// Callback when tapped
  final VoidCallback? onTap;
  
  /// Callback when long-pressed
  final VoidCallback? onLongPress;
  
  /// Callback when double-tapped
  final VoidCallback? onDoubleTap;
  
  /// Border radius for ink splash (if useMaterialInk is true)
  final BorderRadius? borderRadius;
  
  /// Whether to use Material ink effect (InkWell) vs simple GestureDetector
  final bool useMaterialInk;
  
  /// Background color (only used with useMaterialInk)
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (useMaterialInk && (onTap != null || onLongPress != null)) {
      return Material(
        color: backgroundColor ?? Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onDoubleTap: onDoubleTap,
          borderRadius: borderRadius,
          child: child,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onDoubleTap: onDoubleTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}

/// Tappable with animated opacity feedback (common pattern in iOS)
class BBTappableOpacity extends StatefulWidget {
  const BBTappableOpacity({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.activeOpacity = 0.6,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double activeOpacity;

  @override
  State<BBTappableOpacity> createState() => _BBTappableOpacityState();
}

class _BBTappableOpacityState extends State<BBTappableOpacity> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        opacity: _isPressed ? widget.activeOpacity : 1.0,
        duration: BBDuration.fast,
        child: widget.child,
      ),
    );
  }
}
