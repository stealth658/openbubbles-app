import 'dart:math';

/// Where the Material 3 long-press menu and tapback bar go around a bubble that
/// stays where it is.
///
/// All values are logical pixels from the top of the screen. [topLimit] and
/// [bottomLimit] are the edges nothing may cross (status bar and the bottom
/// margin).
///
/// Order of preference:
/// 1. menu below the bubble, bar above it;
/// 2. bubble too close to the top for the bar: bar below the bubble, menu below the bar;
/// 3. no room below for the menu: menu above the bubble, bar below it;
/// 4. no room below for the bar either: bar above the bubble, menu above the bar;
/// 5. a bubble so tall that neither side holds the menu: menu pinned to the
///    bottom edge and bar to the top edge, over the bubble.
class M3PopupPlacement {
  const M3PopupPlacement({required this.menuTop, required this.barTop, required this.menuBelow});

  final double menuTop;
  final double barTop;

  /// Whether the menu sits below the bubble (cases 1, 2 and 5).
  final bool menuBelow;

  /// Space between the bubble, the bar and the menu.
  static const double gap = 8;

  static M3PopupPlacement compute({
    required double bubbleTop,
    required double bubbleHeight,
    required double menuHeight,
    required double barHeight,
    required double topLimit,
    required double bottomLimit,
  }) {
    final bubbleBottom = bubbleTop + bubbleHeight;
    final above = bubbleTop - topLimit;
    final below = bottomLimit - bubbleBottom;

    double clampTop(double top, double height) => top.clamp(topLimit, max(topLimit, bottomLimit - height)).toDouble();

    // Every result is clamped to the limits: a bubble that is partly scrolled
    // off the screen must not drag the menu or the bar off with it.
    M3PopupPlacement at(double menuTop, double barTop, bool menuBelow) => M3PopupPlacement(
        menuTop: clampTop(menuTop, menuHeight), barTop: clampTop(barTop, barHeight), menuBelow: menuBelow);

    if (below >= menuHeight + gap) {
      if (above >= barHeight + gap) {
        return at(bubbleBottom + gap, bubbleTop - gap - barHeight, true);
      }
      if (below >= barHeight + menuHeight + 2 * gap) {
        final barTop = max(bubbleBottom + gap, topLimit);
        return at(barTop + barHeight + gap, barTop, true);
      }
      // No room for the bar on either side: lay it over the top of the bubble.
      return at(bubbleBottom + gap, bubbleTop + gap, true);
    }
    if (above >= menuHeight + gap) {
      if (below >= barHeight + gap) {
        return at(bubbleTop - gap - menuHeight, bubbleBottom + gap, false);
      }
      if (above >= menuHeight + barHeight + 2 * gap) {
        final barTop = min(bubbleTop - gap - barHeight, bottomLimit - barHeight);
        return at(barTop - gap - menuHeight, barTop, false);
      }
      // No room for the bar on either side: lay it over the bottom of the bubble.
      return at(bubbleTop - gap - menuHeight, bubbleBottom - gap - barHeight, false);
    }
    return at(bottomLimit - menuHeight, topLimit, true);
  }

  /// How many menu rows of [rowHeight] fit beside the bubble, on the roomier
  /// side or on the given one. [extra] is what the menu adds to its rows
  /// (padding, the who-reacted header).
  static int rowsThatFit({
    required double bubbleTop,
    required double bubbleHeight,
    required double topLimit,
    required double bottomLimit,
    required double rowHeight,
    required double extra,
    bool? below,
  }) {
    final spaceAbove = bubbleTop - topLimit;
    final spaceBelow = bottomLimit - (bubbleTop + bubbleHeight);
    final space = below == null ? max(spaceAbove, spaceBelow) : (below ? spaceBelow : spaceAbove);
    return max(((space - gap - extra) / rowHeight).floor(), 0);
  }
}
