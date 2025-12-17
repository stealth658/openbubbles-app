import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/handle_actions.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class HandleInterface {
  static Future<Handle> saveHandleAsync({
    required Map<String, dynamic> handleData,
    required bool updateColor,
    required bool matchOnOriginalROWID,
  }) async {
    final data = {
      'handleData': handleData,
      'updateColor': updateColor,
      'matchOnOriginalROWID': matchOnOriginalROWID,
    };

    late Map<String, dynamic> handleMap;
    if (isIsolate()) {
      handleMap = await HandleActions.saveHandleAsync(data);
    } else {
      handleMap = await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>>(IsolateRequestType.saveHandleAsync, input: data);
    }
    
    return Handle.fromMap(handleMap);
  }

  static Future<List<Handle>> bulkSaveHandlesAsync({
    required List<Map<String, dynamic>> handlesData,
    required bool matchOnOriginalROWID,
  }) async {
    final data = {
      'handlesData': handlesData,
      'matchOnOriginalROWID': matchOnOriginalROWID,
    };

    late List<Map<String, dynamic>> handlesDataResult;
    if (isIsolate()) {
      handlesDataResult = await HandleActions.bulkSaveHandlesAsync(data);
    } else {
      handlesDataResult = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.bulkSaveHandlesAsync, input: data);
    }
    
    return handlesDataResult.map((e) => Handle.fromMap(e)).toList();
  }

  static Future<Handle?> findOneHandleAsync({
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

    late Map<String, dynamic>? handleMap;
    if (isIsolate()) {
      handleMap = await HandleActions.findOneHandleAsync(data);
    } else {
      handleMap = await GetIt.I<GlobalIsolate>()
          .send<Map<String, dynamic>?>(IsolateRequestType.findOneHandleAsync, input: data);
    }
    
    if (handleMap == null) return null;
    
    return Handle.fromMap(handleMap);
  }

  static Future<List<Handle>> findHandlesAsync() async {
    late List<Map<String, dynamic>> handlesData;
    if (isIsolate()) {
      handlesData = await HandleActions.findHandlesAsync({});
    } else {
      handlesData = await GetIt.I<GlobalIsolate>()
          .send<List<Map<String, dynamic>>>(IsolateRequestType.findHandlesAsync, input: {});
    }
    
    return handlesData.map((e) => Handle.fromMap(e)).toList();
  }
}
