import 'package:bluebubbles/app/components/m3e/m3e_list_tile.dart' show GoogleTileStyle;
import 'package:bluebubbles/app/components/m3e/m3e_shapes.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

enum M3ESectionTone { neutral, error }

/// The expressive replacement for `SettingsSection`.
///
/// The group fill is always derived from [backgroundColor] (the `tileColor` callers already
/// compute, which carries window-effect alpha and any per-chat surface override) — never from
/// `colorScheme.surfaceContainer*` directly, since that would break Mica/acrylic and per-chat
/// themes. Any tonal step within the group is a lighten/darken of that same colour.
/// Draws a 1px line along the top edge of [child], only when the child has height.
class _HairlineAbove extends StatelessWidget {
  final bool enabled;
  final Color color;
  final Widget child;
  const _HairlineAbove({required this.enabled, required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return CustomPaint(foregroundPainter: _HairlinePainter(color), child: child);
  }
}

class _HairlinePainter extends CustomPainter {
  final Color color;
  _HairlinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HairlinePainter old) => old.color != color;
}

class M3ESection extends StatelessWidget {
  final List<Widget> children;
  final Color backgroundColor;
  final M3ESectionTone tone;
  final EdgeInsets margin;
  final double gap;

  const M3ESection({
    super.key,
    required this.children,
    required this.backgroundColor,
    this.tone = M3ESectionTone.neutral,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    this.gap = 2,
  });

  @override
  Widget build(BuildContext context) {
    // Conditionally-hidden rows still show up as SizedBox.shrink() — strip them before
    // indexing or they corrupt the grouped-corner sequence.
    final visibleChildren = children.where((child) => child is! SizedBox || child.width != 0 || child.height != 0);
    final displayedChildren = visibleChildren.toList(growable: false);

    if (displayedChildren.isEmpty) {
      return const SizedBox.shrink();
    }

    final google = GoogleTileStyle.of(context);
    final fill = tone == M3ESectionTone.error
        ? Color.lerp(backgroundColor, context.theme.colorScheme.errorContainer, 0.35)!
        : backgroundColor;

    if (google) {
      // Google Messages: one rounded card per group, hairline dividers between rows.
      return Padding(
        padding: margin,
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(28)),
          child: Container(
            color: fill,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < displayedChildren.length; i++)
                  // Hairline above every row but the first, painted by the row itself so a
                  // conditional row that collapses to nothing leaves no stray line behind.
                  _HairlineAbove(
                    enabled: i > 0,
                    color: context.theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                    child: displayedChildren[i],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < displayedChildren.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            ClipRRect(
              borderRadius: M3EShapes.grouped(i, displayedChildren.length),
              child: Container(
                color: fill,
                child: displayedChildren[i],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
