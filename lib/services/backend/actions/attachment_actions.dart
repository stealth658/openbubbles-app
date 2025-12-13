import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:collection/collection.dart';
import 'package:objectbox/objectbox.dart';

class AttachmentActions {
  static Future<Map<String, dynamic>> saveAttachmentAsync(Map<String, dynamic> data) async {
    final attachmentData = data['attachmentData'] as Map<String, dynamic>;
    final messageData = data['messageData'] as Map<String, dynamic>?;

    return Database.runInTransaction(TxMode.write, () {
      final attachment = Attachment.fromMap(attachmentData);

      /// Find an existing attachment and update the attachment ID if applicable
      Attachment? existing = Attachment.findOne(attachment.guid!);
      if (existing != null) {
        attachment.id = existing.id;
      }

      try {
        /// store the attachment and add the link between the message and
        /// attachment
        if (messageData != null) {
          final message = Message.fromMap(messageData);
          if (message.id != null) {
            attachment.message.target = message;
          }
        }

        attachment.id = Database.attachments.put(attachment);
      } on UniqueViolationException catch (_) {}

      return attachment.toMap();
    });
  }

  static Future<void> bulkSaveAttachmentsAsync(Map<String, dynamic> data) async {
    final mapData = data['mapData'] as Map<Map<String, dynamic>, List<Map<String, dynamic>>>;

    return Database.runInTransaction(TxMode.write, () {
      // Convert the map from serialized data back to Message/Attachment objects
      Map<Message, List<Attachment>> map = {};
      for (var entry in mapData.entries) {
        final message = Message.fromMap(entry.key);
        final attachments = entry.value.map((e) => Attachment.fromMap(e)).toList();
        map[message] = attachments;
      }

      /// convert List<List<Attachment>> into just List<Attachment> (flatten it)
      final attachments = map.values.flattened.toList();
      
      /// find existing attachments
      List<Attachment> existingAttachments =
          Attachment.find(cond: Attachment_.guid.oneOf(attachments.map((e) => e.guid!).toList()));
      
      /// map existing attachment IDs to the attachments to save, if applicable
      for (Attachment a in attachments) {
        final existing = existingAttachments.firstWhereOrNull((e) => e.guid == a.guid);
        if (existing != null) {
          a.id = existing.id;
        }
      }
      
      try {
        /// store the attachments and update their ids
        final ids = Database.attachments.putMany(attachments);
        for (int i = 0; i < attachments.length; i++) {
          attachments[i].id = ids[i];
        }
      } on UniqueViolationException catch (_) {}
    });
  }

  static Future<Map<String, dynamic>> replaceAttachmentAsync(Map<String, dynamic> data) async {
    final oldGuid = data['oldGuid'] as String;
    final newAttachmentData = data['newAttachmentData'] as Map<String, dynamic>;

    return Database.runInTransaction(TxMode.write, () {
      final newAttachment = Attachment.fromMap(newAttachmentData);
      
      Attachment? existing = Attachment.findOne(oldGuid);
      if (existing == null) {
        throw Exception("Old GUID ($oldGuid) does not exist!");
      }

      // Note: cm and cvc services are NOT called here since they're only available on UI thread
      // This should be handled by the caller on the main thread before/after calling this

      // update values and save
      existing.guid = newAttachment.guid;
      existing.originalROWID = newAttachment.originalROWID;
      existing.uti = newAttachment.uti;
      existing.mimeType = newAttachment.mimeType ?? existing.mimeType;
      existing.isOutgoing = newAttachment.isOutgoing;
      existing.transferName = newAttachment.transferName;
      existing.totalBytes = newAttachment.totalBytes;
      existing.bytes = newAttachment.bytes;
      existing.webUrl = newAttachment.webUrl;
      existing.hasLivePhoto = newAttachment.hasLivePhoto;
      existing.save(null);

      // grab values from existing
      newAttachment.id = existing.id;
      newAttachment.width = existing.width;
      newAttachment.height = existing.height;
      newAttachment.metadata = existing.metadata;
      
      return newAttachment.toMap();
    });
  }

  static Future<Map<String, dynamic>?> findOneAttachmentAsync(Map<String, dynamic> data) async {
    final guid = data['guid'] as String;

    return Database.runInTransaction(TxMode.read, () {
      final attachmentBox = Database.attachments;

      final query = attachmentBox.query(Attachment_.guid.equals(guid)).build();
      query.limit = 1;
      final result = query.findFirst();
      query.close();

      return result?.toMap();
    });
  }

  static Future<List<Map<String, dynamic>>> findAttachmentsAsync(Map<String, dynamic> data) async {
    return Database.runInTransaction(TxMode.read, () {
      final attachmentBox = Database.attachments;

      // Note: For now, we don't serialize conditions for cross-isolate communication
      // This will return all attachments. Future enhancement can add condition serialization.
      final query = attachmentBox.query().build();
      final results = query.find();
      query.close();

      return results.map((e) => e.toMap()).toList();
    });
  }

  static Future<void> deleteAttachmentAsync(Map<String, dynamic> data) async {
    final guid = data['guid'] as String;

    return Database.runInTransaction(TxMode.write, () {
      final query = Database.attachments.query(Attachment_.guid.equals(guid)).build();
      final result = query.findFirst();
      query.close();
      
      if (result?.id != null) {
        Database.attachments.remove(result!.id!);
      }
    });
  }
}
