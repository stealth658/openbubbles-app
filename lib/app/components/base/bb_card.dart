import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/material.dart';

/// Theme-aware card component with consistent styling across all skins.
/// 
/// Replaces the common pattern of Material + BoxDecoration + InkWell
/// with a single, unified component.
/// 
/// Example usage:
/// ```dart
/// BBCard(
///   child: Text('Card content'),
///   onTap: () => print('Tapped'),
/// )
/// ```
class BBCard extends StatelessWidget {
  const BBCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderRadius,
    this.elevation = 0,
    this.border,
    this.clipBehavior = Clip.antiAlias,
    this.constraints,
  });

  /// The widget below this widget in the tree
  final Widget child;
  
  /// Callback when the card is tapped
  final VoidCallback? onTap;
  
  /// Callback when the card is long-pressed
  final VoidCallback? onLongPress;
  
  /// Internal padding of the card
  final EdgeInsetsGeometry? padding;
  
  /// External margin of the card
  final EdgeInsetsGeometry? margin;
  
  /// Background color. If null, uses theme's surface color
  final Color? backgroundColor;
  
  /// Border radius. If null, uses theme-specific medium radius
  final BorderRadius? borderRadius;
  
  /// Elevation of the card (Material only, ignored on iOS/Samsung)
  final double elevation;
  
  /// Border around the card
  final Border? border;
  
  /// How to clip the card's contents
  final Clip clipBehavior;
  
  /// Additional constraints for the card
  final BoxConstraints? constraints;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? context.radius.mediumBR;
    final effectiveBackgroundColor = backgroundColor ?? context.properSurface;
    final effectivePadding = padding ?? BBSpacing.paddingMD;
    
    // Build the card content
    Widget card = Container(
      padding: effectivePadding,
      constraints: constraints,
      decoration: BoxDecoration(
        color: effectiveBackgroundColor,
        borderRadius: effectiveBorderRadius,
        border: border,
      ),
      child: child,
    );

    // Wrap with Material for elevation and ink effects
    card = Material(
      color: Colors.transparent,
      elevation: elevation,
      borderRadius: effectiveBorderRadius,
      clipBehavior: clipBehavior,
      child: card,
    );

    // Add interactivity if callbacks are provided
    if (onTap != null || onLongPress != null) {
      card = InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: effectiveBorderRadius,
        child: card,
      );
    }

    // Add margin if provided
    if (margin != null) {
      card = Padding(
        padding: margin!,
        child: card,
      );
    }

    return card;
  }
}
