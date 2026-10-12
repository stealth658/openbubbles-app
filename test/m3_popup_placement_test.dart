import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/m3_popup_placement.dart';
import 'package:flutter_test/flutter_test.dart';

// A 900dp-tall screen: status bar ends at 40 (+8), bottom margin 24.
const double top = 48;
const double bottom = 876;
const double bar = 56;
const double menu = 256; // five 48dp rows + 16

M3PopupPlacement place(double bubbleTop, double bubbleHeight, {double menuHeight = menu}) => M3PopupPlacement.compute(
    bubbleTop: bubbleTop,
    bubbleHeight: bubbleHeight,
    menuHeight: menuHeight,
    barHeight: bar,
    topLimit: top,
    bottomLimit: bottom);

void main() {
  test('mid-screen bubble: bar above, menu below, 8dp from the bubble', () {
    final p = place(400, 44);
    expect(p.barTop, 400 - 8 - bar);
    expect(p.menuTop, 444 + 8);
    expect(p.menuBelow, isTrue);
  });

  test('bubble at the very top: bar and menu both below it', () {
    final p = place(60, 44);
    expect(p.barTop, 104 + 8);
    expect(p.menuTop, 112 + bar + 8);
    expect(p.menuBelow, isTrue);
  });

  test('bubble near the bottom: menu above, bar below when it fits', () {
    final p = place(760, 44); // 72 below: room for the bar, not the menu
    expect(p.menuTop, 760 - 8 - menu);
    expect(p.barTop, 804 + 8);
    expect(p.menuBelow, isFalse);
  });

  test('bubble at the bottom edge: bar above the bubble, menu above the bar', () {
    final p = place(820, 44); // 12 below
    expect(p.barTop, 820 - 8 - bar);
    expect(p.menuTop, p.barTop - 8 - menu);
    expect(p.menuBelow, isFalse);
  });

  test('a bubble as tall as the screen: menu pinned to the bottom, bar to the top', () {
    final p = place(100, 700);
    expect(p.menuTop, bottom - menu);
    expect(p.barTop, top);
  });

  test('nothing is ever placed outside the limits', () {
    for (double t = -200; t <= 1000; t += 13) {
      for (final h in <double>[30, 120, 400, 800]) {
        for (final m in <double>[112, 256, 500]) {
          final p = place(t, h, menuHeight: m);
          expect(p.menuTop, greaterThanOrEqualTo(top), reason: 'menu top t=$t h=$h m=$m');
          expect(p.barTop, greaterThanOrEqualTo(top), reason: 'bar top t=$t h=$h m=$m');
          expect(p.barTop + bar, lessThanOrEqualTo(bottom), reason: 'bar bottom t=$t h=$h m=$m');
          if (m <= bottom - top) {
            expect(p.menuTop + m, lessThanOrEqualTo(bottom), reason: 'menu bottom t=$t h=$h m=$m');
          }
        }
      }
    }
  });

  test('the menu and the bar never overlap each other when the bubble is on screen', () {
    for (double t = top; t <= bottom - 44; t += 7) {
      final p = place(t, 44);
      final overlap = p.barTop < p.menuTop + menu && p.menuTop < p.barTop + bar;
      expect(overlap, isFalse, reason: 't=$t bar=${p.barTop} menu=${p.menuTop}');
    }
  });

  test('rows that fit follow the roomier side', () {
    int rows(double t, double h, {bool? below}) => M3PopupPlacement.rowsThatFit(
        bubbleTop: t, bubbleHeight: h, topLimit: top, bottomLimit: bottom, rowHeight: 48, extra: 16, below: below);
    expect(rows(400, 44), ((876 - 444 - 8 - 16) / 48).floor()); // below is roomier
    expect(rows(700, 44), ((700 - 48 - 8 - 16) / 48).floor()); // above is roomier
    expect(rows(700, 44, below: true), ((876 - 744 - 8 - 16) / 48).floor());
    expect(rows(100, 760), 0);
  });
}
