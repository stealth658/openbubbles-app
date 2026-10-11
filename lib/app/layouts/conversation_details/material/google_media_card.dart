import 'package:bluebubbles/app/layouts/conversation_details/attachment_section_type.dart';
import 'package:bluebubbles/app/layouts/conversation_details/conversation_attachments.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/media_gallery_card.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Google Messages' media card on the chat details page: an "Images" row
/// with the count, a strip of rounded thumbnails, and a "Videos, links, &
/// more" row, all in one rounded card. Shown only when the chat has
/// attachments; the full lists live on [ConversationAttachments].
class GoogleMediaCard extends StatelessWidget {
  const GoogleMediaCard({
    super.key,
    required this.chat,
    required this.media,
    required this.docs,
    required this.locations,
    required this.isLoading,
  });

  final Chat chat;
  final List<Attachment> media;
  final List<Attachment> docs;
  final List<Attachment> locations;
  final bool isLoading;

  void _open(BuildContext context, AttachmentSectionType section) => ConversationAttachments.open(
        context,
        chat: chat,
        section: section,
        media: media,
        docs: docs,
        locations: locations,
      );

  @override
  Widget build(BuildContext context) {
    if (isLoading || (media.isEmpty && docs.isEmpty && locations.isEmpty)) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final images = media.where((a) => a.mimeStart == "image").toList();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Material(
          color: context.tileColor,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (images.isNotEmpty) ...[
                _Row(
                  icon: Icons.image_outlined,
                  label: "Images",
                  count: images.length,
                  onTap: () => _open(context, AttachmentSectionType.media),
                ),
                SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    itemCount: images.length.clamp(0, 12),
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        width: 120,
                        child: MediaGalleryCard(attachment: images[i], showSenderAvatar: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _Row(
                icon: Icons.link,
                label: "Videos, links, & more",
                onTap: () => _open(
                    context,
                    media.any((a) => a.mimeStart == "video")
                        ? AttachmentSectionType.media
                        : AttachmentSectionType.links),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap, this.count});

  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: scheme.onSurfaceVariant, size: 24),
            const SizedBox(width: 20),
            Expanded(child: Text(label, style: context.theme.textTheme.bodyLarge)),
            if (count != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text("$count",
                    style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)),
              ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
