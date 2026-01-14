import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Theme-adaptive loading indicator that uses the correct spinner for each skin.
/// 
/// Replaces the buildProgressIndicator() helper and scattered loading indicators
/// with a unified component.
/// 
/// Example usage:
/// ```dart
/// BBLoadingIndicator()
/// 
/// // With custom size and color
/// BBLoadingIndicator(
///   size: 30,
///   color: Colors.blue,
/// )
/// ```
class BBLoadingIndicator extends StatelessWidget {
  const BBLoadingIndicator({
    super.key,
    this.size,
    this.color,
    this.strokeWidth,
  });

  /// Size of the indicator (diameter)
  final double? size;
  
  /// Color of the indicator
  final Color? color;
  
  /// Stroke width for circular indicators (Material/Samsung)
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    return ThemeSwitcher(
      iOSSkin: _buildIOSIndicator(),
      materialSkin: _buildMaterialIndicator(),
      samsungSkin: _buildMaterialIndicator(), // Samsung uses same as Material
    );
  }

  Widget _buildIOSIndicator() {
    Widget indicator = CupertinoActivityIndicator(
      color: color,
      radius: size != null ? size! / 2 : 10,
    );

    if (size != null) {
      indicator = SizedBox(
        width: size,
        height: size,
        child: indicator,
      );
    }

    return indicator;
  }

  Widget _buildMaterialIndicator() {
    Widget indicator = CircularProgressIndicator(
      valueColor: color != null ? AlwaysStoppedAnimation(color) : null,
      strokeWidth: strokeWidth ?? 4.0,
    );

    if (size != null) {
      indicator = SizedBox(
        width: size,
        height: size,
        child: indicator,
      );
    }

    return indicator;
  }
}
