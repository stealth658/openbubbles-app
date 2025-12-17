import 'package:bluebubbles/database/models.dart';

/// Utility class for hydrating Attachment objects with their relationships
/// after they've been deserialized from isolate communication.
/// 
/// ObjectBox ToMany/ToOne relationships cannot be serialized across isolates,
/// so after deserializing an Attachment from a Map, we need to "hydrate" it
/// by accessing the relationship to trigger ObjectBox's lazy loading.
class AttachmentHydration {
  /// Hydrate a single attachment with its relationships
  /// 
  /// [loadMessage] - Whether to load the linked message (default: true)
  static void hydrate(Attachment attachment, {bool loadMessage = true}) {
    if (loadMessage) {
      // Access the message relationship to trigger lazy-load
      // This ensures the relationship is populated after crossing isolate boundary
      final _ = attachment.message.target;
    }
  }

  /// Hydrate multiple attachments with their relationships
  /// 
  /// [loadMessage] - Whether to load the linked message (default: true)
  static void hydrateAll(List<Attachment> attachments, {bool loadMessage = true}) {
    for (final attachment in attachments) {
      hydrate(attachment, loadMessage: loadMessage);
    }
  }
}
