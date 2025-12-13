import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:objectbox/objectbox.dart';
import 'package:tuple/tuple.dart';

class HandleActions {
  static Future<Map<String, dynamic>> saveHandleAsync(Map<String, dynamic> data) async {
    final handleData = data['handleData'] as Map<String, dynamic>;
    final updateColor = data['updateColor'] as bool;
    final matchOnOriginalROWID = data['matchOnOriginalROWID'] as bool;

    return Database.runInTransaction(TxMode.write, () {
      final handle = Handle.fromMap(handleData);

      Handle? existing;
      if (matchOnOriginalROWID) {
        existing = Handle.findOne(originalROWID: handle.originalROWID);
      } else {
        existing = Handle.findOne(addressAndService: Tuple2(handle.address, handle.service));
      }

      if (existing != null) {
        handle.id = existing.id;
        handle.contactRelation.target = existing.contactRelation.target;
      } else if (existing == null && handle.contactRelation.target == null) {
        handle.contactRelation.target = ContactsSvc.matchHandleToContact(handle);
      }
      if (!updateColor) {
        handle.color = existing?.color ?? handle.color;
      }
      
      try {
        handle.id = Database.handles.put(handle);
      } on UniqueViolationException catch (_) {}

      return handle.toMap();
    });
  }

  static Future<List<Map<String, dynamic>>> bulkSaveHandlesAsync(Map<String, dynamic> data) async {
    final handlesData = (data['handlesData'] as List).cast<Map<String, dynamic>>();
    final matchOnOriginalROWID = data['matchOnOriginalROWID'] as bool;

    return Database.runInTransaction(TxMode.write, () {
      final handles = handlesData.map((e) => Handle.fromMap(e)).toList();

      /// Match existing to the handles to save, where possible
      for (Handle h in handles) {
        Handle? existing;
        if (matchOnOriginalROWID) {
          existing = Handle.findOne(originalROWID: h.originalROWID);
        } else {
          existing = Handle.findOne(addressAndService: Tuple2(h.address, h.service));
        }

        if (existing != null) {
          h.id = existing.id;
        } else {
          h.contactRelation.target ??= ContactsSvc.matchHandleToContact(h);
        }
      }

      List<int> insertedIds = Database.handles.putMany(handles);
      for (int i = 0; i < insertedIds.length; i++) {
        handles[i].id = insertedIds[i];
      }

      return handles.map((e) => e.toMap()).toList();
    });
  }

  static Future<Map<String, dynamic>?> findOneHandleAsync(Map<String, dynamic> data) async {
    final id = data['id'] as int?;
    final originalROWID = data['originalROWID'] as int?;
    final address = data['address'] as String?;
    final service = data['service'] as String?;

    return Database.runInTransaction(TxMode.read, () {
      final handleBox = Database.handles;

      Handle? result;

      if (id != null && id != 0) {
        result = handleBox.get(id);
        if (result == null) {
          // Try finding by originalROWID if direct ID lookup fails
          final query = handleBox.query(Handle_.originalROWID.equals(id)).build();
          query.limit = 1;
          result = query.findFirst();
          query.close();
        }
      } else if (originalROWID != null) {
        final query = handleBox.query(Handle_.originalROWID.equals(originalROWID)).build();
        query.limit = 1;
        result = query.findFirst();
        query.close();
      } else if (address != null && service != null) {
        final query = handleBox.query(Handle_.address.equals(address) & Handle_.service.equals(service)).build();
        query.limit = 1;
        result = query.findFirst();
        query.close();
      }

      return result?.toMap();
    });
  }

  static Future<List<Map<String, dynamic>>> findHandlesAsync(Map<String, dynamic> data) async {
    return Database.runInTransaction(TxMode.read, () {
      final handleBox = Database.handles;

      final query = handleBox.query().build();
      final results = query.find();
      query.close();

      return results.map((e) => e.toMap()).toList();
    });
  }
}
