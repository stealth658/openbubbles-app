import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/handle_actions.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class HandleInterface {
  static Future<Map<String, dynamic>> saveHandleAsync({
    required Map<String, dynamic> handleData,
    required bool updateColor,
    required bool matchOnOriginalROWID,
  }) async {
    final data = {
      'handleData': handleData,
      'updateColor': updateColor,
      'matchOnOriginalROWID': matchOnOriginalROWID,
    };

    if (isIsolate()) {
      return await HandleActions.saveHandleAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.saveHandleAsync, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> bulkSaveHandlesAsync({
    required List<Map<String, dynamic>> handlesData,
    required bool matchOnOriginalROWID,
  }) async {
    final data = {
      'handlesData': handlesData,
      'matchOnOriginalROWID': matchOnOriginalROWID,
    };

    if (isIsolate()) {
      return await HandleActions.bulkSaveHandlesAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.bulkSaveHandlesAsync, input: data);
    }
  }

  static Future<Map<String, dynamic>?> findOneHandleAsync({
    int? id,
    int? originalROWID,
    String? address,
    String? service,
  }) async {
    final data = {
      'id': id,
      'originalROWID': originalROWID,
      'address': address,
      'service': service,
    };

    if (isIsolate()) {
      return await HandleActions.findOneHandleAsync(data);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.findOneHandleAsync, input: data);
    }
  }

  static Future<List<Map<String, dynamic>>> findHandlesAsync() async {
    if (isIsolate()) {
      return await HandleActions.findHandlesAsync({});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.findHandlesAsync, input: {});
    }
  }
}
