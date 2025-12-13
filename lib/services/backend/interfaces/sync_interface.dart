import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/sync_actions.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class SyncInterface {
  /// Performs an incremental sync in the isolate
  /// Returns contact refresh data [changedContacts, removedContacts]
  static Future<List<List<int>>> performIncrementalSync() async {
    if (isIsolate()) {
      return await SyncActions.performIncrementalSync({});
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<List<List<int>>>(IsolateRequestType.performIncrementalSync, input: {});
    }
  }
}
