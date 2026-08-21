import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';

class StickerHolder extends StatefulWidget {
  const StickerHolder({super.key, required this.stickerMessages, required this.controller});
  final Iterable<Message> stickerMessages;
  final ConversationViewController controller;

  @override
  State<StickerHolder> createState() => _StickerHolderState();
}

class _StickerHolderState extends State<StickerHolder> {
  Iterable<Message> get messages => widget.stickerMessages;
  ConversationViewController get controller => widget.controller;

  bool _visible = true;
  bool _dismissed = false;

  /// Loaded stickers, keyed by attachment path so a sticker is only handled
  /// once. The record carries OpenBubbles' placement data (rotation / scale /
  /// normalized position) when the sender's attributed body supplied it.
  final Map<String, (Attachment, StickerData?)> _stickers = {};

  @override
  void initState() {
    super.initState();
    loadStickers();
  }

  @override
  void didUpdateWidget(StickerHolder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stickerMessages.length != widget.stickerMessages.length) {
      loadStickers();
    }
  }

  /// OpenBubbles: iMessage carries a sticker's placement on the bubble in the
  /// attributed body run that references the attachment.
  StickerData? _placementFor(Message message, Attachment attachment) {
    try {
      return message.attributedBody.firstOrNull?.runs
          .firstWhereOrNull((run) => run.attributes?.attachmentGuid == attachment.guid)
          ?.attributes
          ?.stickerData;
    } catch (_) {
      return null;
    }
  }

  void _register(Message message, Attachment attachment) {
    if (!mounted) return;
    final placement = _placementFor(message, attachment);
    setState(() => _stickers[attachment.path] = (attachment, placement));
    // Keep the shared cache the reaction / popup widgets read from up to date.
    try {
      final bytes = File(attachment.path).readAsBytesSync();
      controller.stickerData[message.guid!] = {attachment.guid!: (bytes, placement)};
    } catch (_) {
      // The file may have vanished between the download completing and here;
      // the rendered Image.file below will show the error builder instead.
    }
  }

  Future<void> loadStickers() async {
    for (Message msg in messages) {
      for (Attachment attachment in msg.dbAttachments) {
        final pathName = attachment.path;
        if (_stickers.containsKey(pathName)) continue;

        if (await FileSystemEntity.type(pathName) == FileSystemEntityType.notFound) {
          AttachmentDownloader.startDownload(attachment, onComplete: (_) {
            _register(msg, attachment);
          });
        } else {
          _register(msg, attachment);
        }
      }
    }
  }

  Widget _buildSticker(Attachment attachment, StickerData? placement) {
    final image = Image.file(
      File(attachment.path),
      gaplessPlayback: true,
      filterQuality: FilterQuality.none,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
    if (placement == null) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
        child: image,
      );
    }
    // OpenBubbles: honour the placement the sender chose.
    final alignment = FractionalOffset(placement.normalizedX, placement.normalizedY);
    return Align(
      alignment: alignment,
      child: Transform.rotate(
        angle: placement.rotation,
        alignment: alignment,
        child: Transform.scale(
          scale: placement.scale,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100, maxHeight: 100),
            child: image,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_stickers.isEmpty || _dismissed) return const SizedBox.shrink();

    final placed = _stickers.values.where((e) => e.$2 != null).toList();
    final unplaced = _stickers.values.where((e) => e.$2 == null).toList();

    return GestureDetector(
      onTap: () => setState(() => _visible = !_visible),
      onLongPress: () {
        HapticFeedback.mediumImpact();
        setState(() => _dismissed = true);
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: _visible ? 1.0 : 0.25,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: NavigationSvc.width(context) * 0.6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (placed.isNotEmpty)
                Stack(
                  children: placed.map((e) => _buildSticker(e.$1, e.$2)).toList(),
                ),
              if (unplaced.isNotEmpty)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: unplaced.map((e) => _buildSticker(e.$1, null)).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
