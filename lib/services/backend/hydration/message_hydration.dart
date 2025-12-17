import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';

/// Utility class for hydrating Message objects with their relationships from the database.
/// This is necessary because ObjectBox ToMany relationships cannot be serialized across isolates.
class MessageHydration {
  /// Hydrates a single message with its attachments from the database.
  /// 
  /// This populates the `attachments` field from the `dbAttachments` ToMany relationship.
  /// 
  /// Parameters:
  /// - [message]: The message to hydrate
  /// - [loadAttachments]: Whether to load attachments (default: true)
  /// 
  /// Returns the hydrated message
  static Message hydrate(Message message, {bool loadAttachments = true}) {
    if (loadAttachments && message.hasAttachments) {
      // Access dbAttachments to trigger lazy-load
      final _ = message.dbAttachments.length;
      
      // Populate the attachments field from dbAttachments
      if (message.dbAttachments.isNotEmpty) {
        message.attachments = List<Attachment>.from(message.dbAttachments);
      }
    }
    
    return message;
  }

  /// Hydrates multiple messages with their attachments from the database.
  /// 
  /// This is more efficient than calling [hydrate] individually for each message
  /// as it can batch operations if needed in the future.
  /// 
  /// Parameters:
  /// - [messages]: The list of messages to hydrate
  /// - [loadAttachments]: Whether to load attachments (default: true)
  /// 
  /// Returns the list of hydrated messages
  static List<Message> hydrateAll(List<Message> messages, {bool loadAttachments = true}) {
    if (!loadAttachments) return messages;
    
    for (final message in messages) {
      if (message.hasAttachments) {
        // Access dbAttachments to trigger lazy-load
        final _ = message.dbAttachments.length;
        
        // Populate the attachments field from dbAttachments
        if (message.dbAttachments.isNotEmpty) {
          message.attachments = List<Attachment>.from(message.dbAttachments);
        }
      }
    }
    
    return messages;
  }

  /// Hydrates messages by querying attachments separately (alternative approach).
  /// 
  /// This approach explicitly queries the attachment table instead of relying
  /// on ToMany lazy-loading. May be more efficient for large batches.
  /// 
  /// Parameters:
  /// - [messages]: The list of messages to hydrate
  /// 
  /// Returns the list of hydrated messages
  static List<Message> hydrateWithQuery(List<Message> messages) {
    if (messages.isEmpty) return messages;
    
    final attachmentBox = Database.attachments;
    final messageIds = messages.map((e) => e.id!).toList();
    
    // Query all attachments for these messages
    final attachmentQuery = (attachmentBox.query(Attachment_.id.notNull())
          ..link(Attachment_.message, Message_.id.oneOf(messageIds)))
        .build();
    final attachments = attachmentQuery.find();
    attachmentQuery.close();

    // Build attachment map by message ID
    final attachmentMap = <int, List<Attachment>>{};
    for (final attachment in attachments) {
      final messageId = attachment.message.target?.id;
      if (messageId != null) {
        attachmentMap.putIfAbsent(messageId, () => []).add(attachment);
      }
    }

    // Populate attachments field for each message
    for (final message in messages) {
      final messageAttachments = attachmentMap[message.id];
      if (messageAttachments != null && messageAttachments.isNotEmpty) {
        message.attachments = messageAttachments;
      }
    }
    
    return messages;
  }
}
