import 'package:bluebubbles/app/components/m3e/m3e_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(List<Widget> children, {double gap = 2}) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: M3EGroupedTiles(color: const Color(0xFFFFFFFF), gap: gap, outer: 28, inner: 4, children: children),
        ),
      ),
    );

void main() {
  testWidgets('rows are stacked with the gap between them', (tester) async {
    await tester.pumpWidget(_host([
      const SizedBox(key: Key('a'), height: 56),
      const SizedBox(key: Key('b'), height: 72),
      const SizedBox(key: Key('c'), height: 56),
    ]));
    expect(tester.getSize(find.byType(M3EGroupedTiles)), const Size(300, 56 + 2 + 72 + 2 + 56));
    expect(tester.getTopLeft(find.byKey(const Key('b'))).dy, 58);
    expect(tester.getTopLeft(find.byKey(const Key('c'))).dy, 132);
    expect(tester.getSize(find.byKey(const Key('b'))).width, 300);
  });

  testWidgets('a row that lays out empty takes no tile and no gap', (tester) async {
    // The shape a conditional settings row has: a wrapper that cannot be seen to be empty
    // until it is laid out.
    await tester.pumpWidget(_host([
      const SizedBox(key: Key('a'), height: 56),
      Builder(builder: (_) => const SizedBox.shrink()),
      const SizedBox(key: Key('c'), height: 56),
      Builder(builder: (_) => const SizedBox.shrink()),
    ]));
    expect(tester.getSize(find.byType(M3EGroupedTiles)).height, 56 + 2 + 56);
    expect(tester.getTopLeft(find.byKey(const Key('c'))).dy, 58);
  });

  testWidgets('a lone visible row is the whole group', (tester) async {
    await tester.pumpWidget(_host([
      const SizedBox(key: Key('a'), height: 56),
      Builder(builder: (_) => const SizedBox.shrink()),
    ]));
    expect(tester.getSize(find.byType(M3EGroupedTiles)).height, 56);
  });

  testWidgets('taps reach the row under the finger', (tester) async {
    final taps = <String>[];
    await tester.pumpWidget(_host([
      GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: () => taps.add('a'), child: const SizedBox(key: Key('a'), height: 56)),
      Builder(builder: (_) => const SizedBox.shrink()),
      GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: () => taps.add('c'), child: const SizedBox(key: Key('c'), height: 56)),
    ]));
    await tester.tapAt(const Offset(150, 28));
    await tester.tapAt(const Offset(150, 58 + 28));
    expect(taps, ['a', 'c']);
  });

  testWidgets('the group appears and disappears with its rows', (tester) async {
    await tester.pumpWidget(_host([Builder(builder: (_) => const SizedBox.shrink())]));
    expect(tester.getSize(find.byType(M3EGroupedTiles)).height, 0);
    await tester.pumpWidget(_host([const SizedBox(height: 40)]));
    expect(tester.getSize(find.byType(M3EGroupedTiles)).height, 40);
  });
}
