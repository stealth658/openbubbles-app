import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/google_bubble_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('outer corners: only the sender side tightens', () {
    final r = GoogleBubbleShape.outer(isFromMe: true, joinTop: true, joinBottom: false, height: 40);
    expect(r.topRight.x, 4);
    expect(r.bottomRight.x, 20);
    expect(r.topLeft.x, 20);
    expect(r.bottomLeft.x, 20);
    final l = GoogleBubbleShape.outer(isFromMe: false, joinTop: false, joinBottom: true, height: 40);
    expect(l.bottomLeft.x, 4);
    expect(l.topLeft.x, 20);
    expect(l.topRight.x, 20);
  });
  test('short bubbles become pills, tall ones keep 20', () {
    expect(GoogleBubbleShape.outer(isFromMe: true, joinTop: false, joinBottom: false, height: 30).topLeft.x, 15);
    expect(GoogleBubbleShape.outer(isFromMe: true, joinTop: false, joinBottom: false, height: 120).topLeft.x, 20);
  });
  test('quote box follows the outer corners minus the frame', () {
    final o = GoogleBubbleShape.outer(isFromMe: false, joinTop: true, joinBottom: false, height: 120);
    final q = GoogleBubbleShape.quote(o);
    expect(q.topLeft.x, 2);
    expect(q.topRight.x, 12);
    expect(q.bottomLeft.x, 4);
    expect(q.bottomRight.x, 4);
  });
  test('clipper drops the 10px gutter on the sender side', () {
    const sent = GoogleBubbleClipper(isFromMe: true, joinTop: false, joinBottom: false);
    expect(sent.getClip(const Size(100, 40)).getBounds(), const Rect.fromLTRB(0, 0, 90, 40));
    const recv = GoogleBubbleClipper(isFromMe: false, joinTop: false, joinBottom: false);
    expect(recv.getClip(const Size(100, 40)).getBounds(), const Rect.fromLTRB(10, 0, 100, 40));
  });
}
