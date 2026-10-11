import 'dart:math';

import 'package:bluebubbles/database/models.dart';
import 'package:flutter/material.dart';

/// Google Messages bubble geometry, measured from screenshots at 3x:
///
/// * No tails. A bubble is a rounded rectangle whose free corners are 20dp
///   (half of a 40dp one-line bubble, which is what makes short messages
///   pills).
/// * Where two bubbles from the same sender meet, the corner on the
///   sender's side (left for received, right for sent) tightens to 4dp; the
///   far side always stays 20dp. Bubbles in a run sit 2dp apart.
/// * A reply's quote box sits in an 8dp frame. Its top corners follow the
///   outer bubble's (outer radius minus the frame: 20 -> 12, 4 -> ~2); its
///   bottom corners are always 4dp. Reply bubbles are at least 162dp wide.
class GoogleBubbleShape {
  GoogleBubbleShape._();

  static const double free = 20;
  static const double joined = 4;
  static const double frame = 8;
  static const double quoteBottom = 4;
  static const double replyMinWidth = 162;

  /// Whether [a] and [b] are bubbles of one run: same sender, neither a
  /// group event, sent within a minute of each other. Symmetric.
  static bool groups(Message a, Message? b) {
    if (b == null || a.isGroupEvent || b.isGroupEvent || !a.sameSender(b)) return false;
    final da = a.dateCreated, db = b.dateCreated;
    if (da == null || db == null) return false;
    return da.difference(db).inMinutes.abs() <= 1;
  }

  /// Corner radii of the outer bubble.
  static BorderRadius outer({
    required bool isFromMe,
    required bool joinTop,
    required bool joinBottom,
    required double height,
  }) {
    final r = Radius.circular(min(free, height / 2));
    const j = Radius.circular(joined);
    return BorderRadius.only(
      topLeft: !isFromMe && joinTop ? j : r,
      bottomLeft: !isFromMe && joinBottom ? j : r,
      topRight: isFromMe && joinTop ? j : r,
      bottomRight: isFromMe && joinBottom ? j : r,
    );
  }

  /// Corner radii of the quote box inside a reply bubble whose outer corners
  /// are [outer]: the top corners run parallel to the outer ones, the bottom
  /// corners face the message text and stay small.
  static BorderRadius quote(BorderRadius outer) {
    Radius inner(Radius o) => Radius.circular(max(o.x - frame, 2));
    return BorderRadius.only(
      topLeft: inner(outer.topLeft),
      topRight: inner(outer.topRight),
      bottomLeft: const Radius.circular(quoteBottom),
      bottomRight: const Radius.circular(quoteBottom),
    );
  }
}

/// Clips a message part to the Google Messages shape. The part's content
/// keeps the 10px tail gutter on the sender's side that the iOS layout
/// needs (see [TailClipper]); like TailClipper, this clips that strip away,
/// so the visible bubble is tailless and the layout around it is unchanged.
class GoogleBubbleClipper extends CustomClipper<Path> {
  const GoogleBubbleClipper({required this.isFromMe, required this.joinTop, required this.joinBottom});

  final bool isFromMe;
  final bool joinTop;
  final bool joinBottom;

  @override
  Path getClip(Size size) {
    final rect = Rect.fromLTRB(isFromMe ? 0 : 10, 0, isFromMe ? size.width - 10 : size.width, size.height);
    final radii = GoogleBubbleShape.outer(isFromMe: isFromMe, joinTop: joinTop, joinBottom: joinBottom, height: size.height);
    return Path()..addRRect(radii.toRRect(rect));
  }

  @override
  bool shouldReclip(covariant GoogleBubbleClipper old) =>
      old.isFromMe != isFromMe || old.joinTop != joinTop || old.joinBottom != joinBottom;
}
