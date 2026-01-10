import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:dio/dio.dart';

class ContactActions {
  static Future<Map<String, dynamic>> saveContactAsync(Map<String, dynamic> data) async {
    final contactData = data['contactData'] as Map<String, dynamic>;

    return Database.runInTransaction(TxMode.write, () {
      final contact = Contact.fromMap(contactData);

      Contact? existing = Contact.findOne(id: contact.id);
      if (existing != null) {
        contact.dbId = existing.dbId;
      }

      try {
        contact.dbId = Database.contacts.put(contact);
      } on UniqueViolationException catch (_) {}

      return contact.toMap();
    });
  }

  static Future<Map<String, dynamic>?> findOneContactAsync(Map<String, dynamic> data) async {
    final id = data['id'] as String?;
    final address = data['address'] as String?;

    return Database.runInTransaction(TxMode.read, () {
      final contactBox = Database.contacts;

      Contact? result;

      if (id != null) {
        final query = contactBox.query(Contact_.id.equals(id)).build();
        query.limit = 1;
        result = query.findFirst();
        query.close();
      } else if (address != null) {
        final query = contactBox
            .query(Contact_.phones.containsElement(address) | Contact_.emails.containsElement(address))
            .build();
        query.limit = 1;
        result = query.findFirst();
        query.close();
      }

      return result?.toMap();
    });
  }

  /// Gets all contacts ordered by display name
  static Future<List<Map<String, dynamic>>> getAllContactsAsync() async {
    return Database.runInTransaction(TxMode.read, () {
      final query = (Database.contacts.query()..order(Contact_.displayName)).build();
      final contacts = query.find();
      query.close();
      // Convert to unique set and back to list, then map to Map
      return contacts.toSet().toList().map((e) => e.toMap()).toList();
    });
  }

  /// Uploads contacts to the server
  static Future<void> uploadContacts(Map<String, dynamic> data) async {
    final contacts = data['contacts'] as List<Map<String, dynamic>>;

    try {
      await HttpSvc.createContact(contacts);
      Logger.info('Successfully uploaded ${contacts.length} contacts to server');
    } catch (err, stack) {
      if (err is Response) {
        Logger.error(err.data["error"]["message"].toString(), error: err, trace: stack);
      } else {
        Logger.error("Failed to create contacts!", error: err, trace: stack);
      }
    }
  }
}
