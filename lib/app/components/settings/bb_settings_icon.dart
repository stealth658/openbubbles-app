import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Theme-aware settings leading icon using BlueBubbles design system.
///
/// This replaces the legacy [SettingsLeadingIcon] with better design token integration.
/// Automatically applies theme-specific shapes (iOS: rounded, Material: flat, Samsung: squircle).
///
/// ## Example
/// ```dart
/// BBSettingsIcon(
///   iosIcon: CupertinoIcons.airplane,
///   materialIcon: Icons.airplanemode_active,
///   color: Colors.blue,
/// )
/// ```
class BBSettingsIcon extends StatelessWidget {
  const BBSettingsIcon({
    super.key,
    required this.iosIcon,
    required this.materialIcon,
    this.color,
    this.boxSize,
    this.iconSize,
    this.iconSizeMaterial,
  });

  /// Icon to use for iOS skin
  final IconData iosIcon;

  /// Icon to use for Material and Samsung skins
  final IconData materialIcon;

  /// Background color for the icon container (iOS/Samsung)
  /// For Material, this becomes the icon color
  final Color? color;

  /// Size of the container box (default: 30)
  final double? boxSize;

  /// Icon size for iOS and Samsung (default: 21)
  final double? iconSize;

  /// Icon size for Material (default: 28)
  final double? iconSizeMaterial;

  @override
  Widget build(BuildContext context) {
    final effectiveBoxSize = boxSize ?? 30.0;
    final effectiveIconSize = iconSize ?? 21.0;
    final effectiveMaterialIconSize = iconSizeMaterial ?? 28.0;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Obx(() {
          final skin = SettingsSvc.settings.skin.value;
          final iconBgColor = color ?? context.theme.colorScheme.outline;

          return Material(
            shape: skin == Skins.Samsung
                ? SquircleBorder(
                    side: BorderSide(color: iconBgColor, width: 3.0),
                  )
                : null,
            color: skin != Skins.Material ? iconBgColor : Colors.transparent,
            borderRadius: skin == Skins.iOS ? BorderRadius.circular(BBRadius.small(skin) - 2) : null,
            child: SizedBox(
              width: effectiveBoxSize,
              height: effectiveBoxSize,
              child: Center(
                child: Icon(
                  skin == Skins.iOS ? iosIcon : materialIcon,
                  color: skin != Skins.Material ? Colors.white : context.theme.colorScheme.outline,
                  size: skin != Skins.Material ? effectiveIconSize : effectiveMaterialIconSize,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Squircle border shape for Samsung icons
class SquircleBorder extends ShapeBorder {
  final BorderSide side;
  final double superRadius;

  const SquircleBorder({
    this.side = BorderSide.none,
    this.superRadius = 5.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) {
    return SquircleBorder(
      side: side.scale(t),
      superRadius: superRadius * t,
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _squirclePath(rect.deflate(side.width), superRadius);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _squirclePath(rect, superRadius);
  }

  static Path _squirclePath(Rect rect, double superRadius) {
    final c = rect.center;
    final dx = c.dx * (1.0 / superRadius);
    final dy = c.dy * (1.0 / superRadius);
    return Path()
      ..moveTo(c.dx, 0.0)
      ..relativeCubicTo(c.dx - dx, 0.0, c.dx, dy, c.dx, c.dy)
      ..relativeCubicTo(0.0, c.dy - dy, -dx, c.dy, -c.dx, c.dy)
      ..relativeCubicTo(-(c.dx - dx), 0.0, -c.dx, -dy, -c.dx, -c.dy)
      ..relativeCubicTo(0.0, -(c.dy - dy), dx, -c.dy, c.dx, -c.dy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    switch (side.style) {
      case BorderStyle.none:
        break;
      case BorderStyle.solid:
        var path = getOuterPath(rect.deflate(side.width / 2.0), textDirection: textDirection);
        canvas.drawPath(path, side.toPaint());
    }
  }
}
