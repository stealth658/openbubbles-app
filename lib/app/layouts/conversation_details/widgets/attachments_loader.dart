import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

/// Widget that handles loading attachments asynchronously with loading state
class AttachmentsLoader extends StatefulWidget {
  final Chat chat;
  final Function(List<Attachment>, List<Attachment>, List<Attachment>) onAttachmentsLoaded;

  const AttachmentsLoader({
    super.key,
    required this.chat,
    required this.onAttachmentsLoaded,
  });

  @override
  State<AttachmentsLoader> createState() => _AttachmentsLoaderState();
}

class _AttachmentsLoaderState extends OptimizedState<AttachmentsLoader> {
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _fetchAttachments();
    } else {
      isLoading = false;
    }
  }

  Future<void> _fetchAttachments() async {
    try {
      final attachments = await widget.chat.getAttachmentsAsync();
      
      if (!mounted) return;
      
      final media = attachments
          .where((e) =>
              !(e.message.target?.isGroupEvent ?? true) &&
              !(e.message.target?.isInteractive ?? true) &&
              (e.mimeStart == "image" || e.mimeStart == "video"))
          .take(24)
          .toList();
          
      final docs = attachments
          .where((e) =>
              !(e.message.target?.isGroupEvent ?? true) &&
              !(e.message.target?.isInteractive ?? true) &&
              e.mimeStart != "image" &&
              e.mimeStart != "video" &&
              !(e.mimeType ?? "").contains("location"))
          .take(24)
          .toList();
          
      final locations = attachments
          .where((e) => (e.mimeType ?? "").contains("location"))
          .take(10)
          .toList();

      // Associate handles with messages
      for (Attachment a in media) {
        a.message.target?.handle = widget.chat.participants
            .firstWhereOrNull((e) => e.originalROWID == a.message.target?.handleId);
      }
      for (Attachment a in docs) {
        a.message.target?.handle = widget.chat.participants
            .firstWhereOrNull((e) => e.originalROWID == a.message.target?.handleId);
      }
      for (Attachment a in locations) {
        a.message.target?.handle = widget.chat.participants
            .firstWhereOrNull((e) => e.originalROWID == a.message.target?.handleId);
      }

      setState(() {
        isLoading = false;
      });

      widget.onAttachmentsLoaded(media, docs, locations);
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // This widget doesn't render anything visible itself
    // It just triggers the loading and callbacks
    return const SizedBox.shrink();
  }
}
