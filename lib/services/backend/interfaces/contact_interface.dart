import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/contact_actions.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';
import 'package:get_it/get_it.dart';

class ContactInterface {
  static Future<Map<String, dynamic>> saveContactAsync({
    required Map<String, dynamic> contactData,
  }) async {
    final data = {
      'contactData': contactData,
    };

    if (isIsolate) {
      return await ContactActions.saveContactAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.saveContactAsync, input: data);
    }
  }

  static Future<Map<String, dynamic>?> findOneContactAsync({
    String? id,
    String? address,
  }) async {
    final data = {
      'id': id,
      'address': address,
    };

    if (isIsolate) {
      return await ContactActions.findOneContactAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.findOneContactAsync, input: data);
    }
  }

  /// Gets all contacts ordered by display name
  static Future<List<Map<String, dynamic>>> getAllContactsAsync() async {
    if (isIsolate) {
      return await ContactActions.getAllContactsAsync();
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.getAllContactsAsync, input: {});
    }
  }

  /// Uploads contacts to the server
  static Future<void> uploadContacts(List<Map<String, dynamic>> contacts) async {
    final data = {
      'contacts': contacts,
    };

    if (isIsolate) {
      return await ContactActions.uploadContacts(data);
    } else {
      return await GetIt.I<GlobalIsolate>().send<void>(IsolateRequestType.uploadContacts, input: data);
    }
  }
}
