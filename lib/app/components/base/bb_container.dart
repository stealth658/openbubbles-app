import 'package:flutter/material.dart';

/// Smart container with theme-aware decoration.
/// 
/// Automatically handles common container patterns with proper defaults
/// for border radius, padding, and colors based on the current theme.
/// 
/// Example usage:
/// ```dart
/// BBContainer(
///   child: Text('Content'),
///   backgroundColor: context.surface,
/// )
/// ```
class BBContainer extends StatelessWidget {
  const BBContainer({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.borderRadius,
    this.border,
    this.gradient,
    this.boxShadow,
    this.width,
    this.height,
    this.constraints,
    this.alignment,
  });

  /// The widget below this widget in the tree
  final Widget child;
  
  /// Internal padding
  final EdgeInsetsGeometry? padding;
  
  /// External margin
  final EdgeInsetsGeometry? margin;
  
  /// Background color (ignored if gradient is provided)
  final Color? backgroundColor;
  
  /// Border radius. Defaults to theme's medium radius if not specified
  final BorderRadius? borderRadius;
  
  /// Border around the container
  final Border? border;
  
  /// Gradient background (takes precedence over backgroundColor)
  final Gradient? gradient;
  
  /// Box shadow
  final List<BoxShadow>? boxShadow;
  
  /// Fixed width
  final double? width;
  
  /// Fixed height
  final double? height;
  
  /// Additional constraints
  final BoxConstraints? constraints;
  
  /// How to align the child within the container
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: gradient == null ? backgroundColor : null,
      gradient: gradient,
      borderRadius: borderRadius,
      border: border,
      boxShadow: boxShadow,
    );

    return Container(
      width: width,
      height: height,
      padding: padding,
      margin: margin,
      constraints: constraints,
      alignment: alignment,
      decoration: decoration,
      child: child,
    );
  }
}
