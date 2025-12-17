import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/contact_v2_actions.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';
import 'package:get_it/get_it.dart';

/// ContactV2Interface provides the bridge between the main isolate and the GlobalIsolate
/// for all ContactV2 operations. This follows the architecture outlined in FR-1.md
class ContactV2Interface {
  /// Fetch all contacts from the device and match them to existing handles
  /// This operation is executed in the GlobalIsolate to prevent UI jank
  /// 
  /// Returns a list of handle IDs that were affected by the matching
  static Future<List<int>> fetchAndMatchContactsAsync() async {
    if (isIsolate()) {
      return await ContactV2Actions.fetchAndMatchContacts(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<int>>(IsolateRequestType.fetchAndMatchContactsV2, input: <String, dynamic>{});
    }
  }

  /// Check for contact database changes and re-sync if needed
  /// This is designed to be called periodically by workmanager
  /// 
  /// Returns true if changes were detected and a re-sync was performed
  static Future<bool> checkContactChangesAsync() async {
    if (isIsolate()) {
      return await ContactV2Actions.checkContactChanges(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<bool>(IsolateRequestType.checkContactChangesV2, input: <String, dynamic>{});
    }
  }

  /// Get all stored ContactV2 IDs (nativeContactId) for comparison
  /// Used by the periodic checker to detect changes
  static Future<List<String>> getStoredContactIdsAsync() async {
    if (isIsolate()) {
      return await ContactV2Actions.getStoredContactIds(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<String>>(IsolateRequestType.getStoredContactIdsV2, input: <String, dynamic>{});
    }
  }

  /// Find a single ContactV2 by native contact ID
  static Future<Map<String, dynamic>?> findOneContactV2Async({
    required String nativeContactId,
  }) async {
    final data = {
      'nativeContactId': nativeContactId,
    };

    if (isIsolate()) {
      return await ContactV2Actions.findOneContactV2(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.findOneContactV2, input: data);
    }
  }

  /// Get ContactV2 entities for a list of Handle IDs
  static Future<List<Map<String, dynamic>>> getContactsForHandlesAsync({
    required List<int> handleIds,
  }) async {
    final data = {
      'handleIds': handleIds,
    };

    if (isIsolate()) {
      return await ContactV2Actions.getContactsForHandles(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getContactsForHandlesV2, input: data);
    }
  }

  /// Manually trigger a contact refresh
  /// This will fetch all contacts and match them to handles
  static Future<List<int>> refreshContactsAsync() async {
    if (isIsolate()) {
      return await ContactV2Actions.refreshContacts(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<int>>(IsolateRequestType.refreshContactsV2, input: <String, dynamic>{});
    }
  }
}
