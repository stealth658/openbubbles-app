import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/widgets/reaction_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A message without tapbacks has no header. This used to return from inside
  // an Obx before reading any observable, which makes Obx throw, so the
  // long-press menu of every message without tapbacks drew an error box.
  testWidgets('MenuReactors with no reactions builds nothing and does not throw', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Material(child: MenuReactors(reactions: []))));
    expect(tester.takeException(), isNull);
    expect(MenuReactors.heightFor(const []), 0);
  });
}
