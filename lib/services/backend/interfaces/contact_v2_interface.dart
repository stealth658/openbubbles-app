import 'dart:typed_data';

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
  static Future<List<int>> syncContactsToHandles() async {
    if (isIsolate) {
      return await ContactV2Actions.syncContactsToHandles(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<int>>(IsolateRequestType.syncContactsToHandles, input: <String, dynamic>{});
    }
  }

  /// Get all stored ContactV2 IDs (nativeContactId) for comparison
  /// Used by the periodic checker to detect changes
  static Future<List<String>> getStoredContactIds() async {
    if (isIsolate) {
      return await ContactV2Actions.getStoredContactIds(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<String>>(IsolateRequestType.getStoredContactIds, input: <String, dynamic>{});
    }
  }

  /// Find a single ContactV2 by native contact ID
  static Future<Map<String, dynamic>?> findOneContact({
    required String nativeContactId,
  }) async {
    final data = {
      'nativeContactId': nativeContactId,
    };

    if (isIsolate) {
      return await ContactV2Actions.findOneContact(data);
    } else {
      return await GetIt.I<GlobalIsolate>().send<Map<String, dynamic>?>(IsolateRequestType.findOneContact, input: data);
    }
  }

  /// Get ContactV2 entities for a list of Handle IDs
  static Future<List<Map<String, dynamic>>> getContactsForHandles({
    required List<int> handleIds,
  }) async {
    final data = {
      'handleIds': handleIds,
    };

    if (isIsolate) {
      return await ContactV2Actions.getContactsForHandles(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getContactsForHandles, input: data);
    }
  }

  /// Get a contact by address (email or phone number)
  static Future<Map<String, dynamic>?> getContactByAddress({
    required String address,
  }) async {
    final data = {
      'address': address,
    };

    if (isIsolate) {
      return await ContactV2Actions.getContactByAddress(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.getContactByAddress, input: data);
    }
  }

  /// Get all contacts from the database
  static Future<List<Map<String, dynamic>>> getAllContacts() async {
    if (isIsolate) {
      return await ContactV2Actions.getAllContacts(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getAllContacts, input: <String, dynamic>{});
    }
  }

  /// Fetch network contacts for web/desktop (from server)
  static Future<List<Map<String, dynamic>>> fetchNetworkContacts() async {
    if (isIsolate) {
      return await ContactV2Actions.fetchNetworkContacts(<String, dynamic>{});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.fetchNetworkContacts, input: <String, dynamic>{});
    }
  }

  /// Get avatar data for a contact
  static Future<Uint8List?> getContactAvatar({
    required String nativeContactId,
  }) async {
    final data = {
      'nativeContactId': nativeContactId,
    };

    if (isIsolate) {
      return await ContactV2Actions.getContactAvatar(data);
    } else {
      return await GetIt.I<GlobalIsolate>().send<Uint8List?>(IsolateRequestType.getContactAvatar, input: data);
    }
  }
}
