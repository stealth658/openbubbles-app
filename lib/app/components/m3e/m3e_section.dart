import 'dart:math' as math;

import 'package:bluebubbles/app/components/m3e/m3e_list_tile.dart' show GoogleTileStyle;
import 'package:bluebubbles/app/components/m3e/m3e_shapes.dart';
import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';

enum M3ESectionTone { neutral, error }

/// Lays rows out as a connected group of tiles and decides each tile's corners
/// from what was actually laid out.
///
/// Settings rows are often conditional (`Obx(() => show ? Row() : SizedBox.shrink())`),
/// and such a wrapper cannot be recognised as empty before layout. Deciding the
/// corners from the widget list therefore miscounts: the row above an empty
/// wrapper was treated as a middle row (small bottom corners) with a gap and an
/// empty tile after it. Here a child that lays out to zero height gets no tile
/// and no gap, and first/last are counted over the rows that are really there.
class M3EGroupedTiles extends MultiChildRenderObjectWidget {
  const M3EGroupedTiles({
    required this.color,
    required this.gap,
    required this.outer,
    required this.inner,
    required super.children,
  });

  final Color color;
  final double gap;
  final double outer;
  final double inner;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderM3EGroupedTiles(color: color, gap: gap, outer: outer, inner: inner);

  @override
  void updateRenderObject(BuildContext context, covariant RenderM3EGroupedTiles renderObject) {
    renderObject
      ..color = color
      ..gap = gap
      ..outer = outer
      ..inner = inner;
  }
}

class _TileParentData extends ContainerBoxParentData<RenderBox> {}

class RenderM3EGroupedTiles extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _TileParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _TileParentData> {
  RenderM3EGroupedTiles({required Color color, required double gap, required double outer, required double inner})
      : _color = color,
        _gap = gap,
        _outer = outer,
        _inner = inner;

  Color _color;
  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  double _gap;
  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  double _outer;
  set outer(double v) {
    if (v == _outer) return;
    _outer = v;
    markNeedsPaint();
  }

  double _inner;
  set inner(double v) {
    if (v == _inner) return;
    _inner = v;
    markNeedsPaint();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TileParentData) child.parentData = _TileParentData();
  }

  double _intrinsicHeight(double width, double Function(RenderBox child, double width) heightOf) {
    double total = 0;
    bool any = false;
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      final h = heightOf(child, width);
      if (h <= 0) continue;
      if (any) total += _gap;
      total += h;
      any = true;
    }
    return total;
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width, (c, w) => c.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width, (c, w) => c.getMaxIntrinsicHeight(w));

  @override
  double computeMinIntrinsicWidth(double height) {
    double w = 0;
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      w = math.max(w, child.getMinIntrinsicWidth(double.infinity));
    }
    return w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    double w = 0;
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      w = math.max(w, child.getMaxIntrinsicWidth(double.infinity));
    }
    return w;
  }

  @override
  void performLayout() {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : computeMaxIntrinsicWidth(double.infinity);
    final childConstraints = BoxConstraints.tightFor(width: width);
    double y = 0;
    bool any = false;
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      child.layout(childConstraints, parentUsesSize: true);
      final data = child.parentData! as _TileParentData;
      if (child.size.height > 0) {
        if (any) y += _gap;
        data.offset = Offset(0, y);
        y += child.size.height;
        any = true;
      } else {
        data.offset = Offset(0, y);
      }
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final visible = <RenderBox>[];
    for (RenderBox? child = firstChild; child != null; child = childAfter(child)) {
      if (child.size.height > 0) visible.add(child);
    }
    final fill = Paint()..color = _color;
    for (int i = 0; i < visible.length; i++) {
      final child = visible[i];
      final origin = (child.parentData! as _TileParentData).offset;
      final rect = origin & child.size;
      final rrect = M3EShapes.grouped(i, visible.length, outer: _outer, inner: _inner).toRRect(rect);
      context.pushClipRRect(needsCompositing, offset, rect, rrect, (ctx, off) {
        ctx.canvas.drawRect(rect.shift(off), fill);
        ctx.paintChild(child, origin + off);
      });
    }
  }
}

/// The expressive replacement for `SettingsSection`.
///
/// The group fill is always derived from [backgroundColor] (the `tileColor` callers already
/// compute, which carries window-effect alpha and any per-chat surface override) — never from
/// `colorScheme.surfaceContainer*` directly, since that would break Mica/acrylic and per-chat
/// themes. Any tonal step within the group is a lighten/darken of that same colour.
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
    // Material follows Google Messages' account sheet: each row is its own tile,
    // 2dp apart, 28dp corners on the outside of the group and 4dp where rows
    // meet. No divider lines. Samsung keeps the softer 8dp seams.
    final inner = SettingsSvc.settings.skin.value == Skins.Material ? M3EShapes.xs : M3EShapes.sm;

    return Padding(
      padding: margin,
      child: M3EGroupedTiles(
        color: fill,
        gap: gap,
        // GoogleTileStyle (chat details options): every row a full card of its own.
        outer: google ? 24 : M3EShapes.xl,
        inner: google ? 24 : inner,
        children: displayedChildren,
      ),
    );
  }
}
