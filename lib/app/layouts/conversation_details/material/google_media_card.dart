import 'package:bluebubbles/app/layouts/conversation_details/attachment_section_type.dart';
import 'package:bluebubbles/app/layouts/conversation_details/conversation_attachments.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/media_gallery_card.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Google Messages-style attachment cards on the Material chat details
/// page: one rounded card each for photos and videos (with a strip of
/// thumbnails), links, files and locations. A card appears only when the
/// chat has that kind of content; tapping it opens the full list on
/// [ConversationAttachments].
class GoogleAttachmentCards extends StatefulWidget {
  const GoogleAttachmentCards({
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

  @override
  State<GoogleAttachmentCards> createState() => _GoogleAttachmentCardsState();
}

class _GoogleAttachmentCardsState extends State<GoogleAttachmentCards> {
  int _linkCount = 0;

  @override
  void initState() {
    super.initState();
    _countLinks();
  }

  /// Same query LinksSection uses for its list, counted here so the card
  /// can stay hidden when there are none.
  Future<void> _countLinks() async {
    if (kIsWeb || widget.chat.id == null) return;
    try {
      final query = (Database.messages.query(Message_.dateDeleted.isNull() &
              Message_.dbPayloadData.notNull() &
              Message_.balloonBundleId.contains("URLBalloonProvider"))
            ..link(Message_.chat, Chat_.id.equals(widget.chat.id!)))
          .build();
      final count = query.count();
      query.close();
      if (mounted) setState(() => _linkCount = count);
    } catch (_) {}
  }

  void _open(AttachmentSectionType section) => ConversationAttachments.open(
        context,
        chat: widget.chat,
        section: section,
        media: widget.media,
        docs: widget.docs,
        locations: widget.locations,
      );

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final cards = <Widget>[
      if (widget.media.isNotEmpty)
        _Card(
          icon: Icons.image_outlined,
          label: "Photos & videos",
          count: widget.media.length,
          onTap: () => _open(AttachmentSectionType.media),
          child: SizedBox(
            height: 120,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              itemCount: widget.media.length.clamp(0, 12),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 120,
                  child: MediaGalleryCard(attachment: widget.media[i], showSenderAvatar: false),
                ),
              ),
            ),
          ),
        ),
      if (_linkCount > 0)
        _Card(
          icon: Icons.link,
          label: "Links",
          count: _linkCount,
          onTap: () => _open(AttachmentSectionType.links),
        ),
      if (widget.docs.isNotEmpty)
        _Card(
          icon: Icons.attach_file,
          label: "Files",
          count: widget.docs.length,
          onTap: () => _open(AttachmentSectionType.documents),
        ),
      if (widget.locations.isNotEmpty)
        _Card(
          icon: Icons.location_on_outlined,
          label: "Locations",
          count: widget.locations.length,
          onTap: () => _open(AttachmentSectionType.locations),
        ),
    ];
    return SliverList.list(children: cards);
  }
}

/// One rounded card: a row with an icon, label, count and chevron, and an
/// optional strip of content under it.
class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.label, required this.count, required this.onTap, this.child});

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: context.tileColor,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Row(
                  children: [
                    Icon(icon, color: scheme.onSurfaceVariant, size: 24),
                    const SizedBox(width: 20),
                    Expanded(child: Text(label, style: context.theme.textTheme.bodyLarge)),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text("$count",
                          style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)),
                    ),
                    Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            if (child != null) ...[child!, const SizedBox(height: 8)],
          ],
        ),
      ),
    );
  }
}
