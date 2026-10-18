import 'dart:math';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Several pictures or videos in one message on the Material skin, tiled the
/// way Google Messages does it: two side by side, three as one tall tile with
/// two stacked beside it, four or more as a 2x2 grid with "+N" over the last
/// tile. Each tile is the ordinary [AttachmentHolder] for that attachment
/// (download state, upload progress, tap to open), scaled to fill its tile;
/// the viewer gets the whole set so it swipes between them. The bubble
/// clipper around this gives the outer corners.
class MessageMediaCollage extends StatelessWidget {
  const MessageMediaCollage({super.key, required this.part});

  final MessagePart part;

  static const double gap = 2;
  static const int maxTiles = 4;

  @override
  Widget build(BuildContext context) {
    final attachments = part.attachments;
    final n = attachments.length;
    final width = min(NavigationSvc.width(context) * 0.62, 340.0);
    final cell = (width - gap) / 2;

    Widget tile(int index, double w, double h) {
      final att = attachments[index];
      final extra = index == maxTiles - 1 ? n - maxTiles : 0;
      return SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: AttachmentHolder(
                message: MessagePart(
                  part: part.partIndexForAttachment(index),
                  attachments: [att],
                  shouldRedact: part.shouldRedact,
                  text: null,
                  subject: null,
                  annotations: const [],
                  edits: const [],
                ),
                transparentBackground: true,
                galleryAttachments: attachments,
              ),
            ),
            if (extra > 0)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Text("+$extra",
                      style: context.theme.textTheme.headlineSmall!.copyWith(color: Colors.white)),
                ),
              ),
          ],
        ),
      );
    }

    final Widget body;
    if (n == 2) {
      body = Row(mainAxisSize: MainAxisSize.min, children: [
        tile(0, cell, cell),
        const SizedBox(width: gap),
        tile(1, cell, cell),
      ]);
    } else if (n == 3) {
      final tall = cell * 2 + gap;
      body = Row(mainAxisSize: MainAxisSize.min, children: [
        tile(0, cell, tall),
        const SizedBox(width: gap),
        Column(mainAxisSize: MainAxisSize.min, children: [
          tile(1, cell, cell),
          const SizedBox(height: gap),
          tile(2, cell, cell),
        ]),
      ]);
    } else {
      body = Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          tile(0, cell, cell),
          const SizedBox(width: gap),
          tile(1, cell, cell),
        ]),
        const SizedBox(height: gap),
        Row(mainAxisSize: MainAxisSize.min, children: [
          tile(2, cell, cell),
          const SizedBox(width: gap),
          tile(3, cell, cell),
        ]),
      ]);
    }
    return SizedBox(width: width, child: body);
  }
}
