import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/io/chat.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/sync_actions.dart';
import 'package:bluebubbles/services/isolates/incremental_sync_isolate.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class SyncInterface {
  /// Performs an incremental sync in the isolate
  static Future<List<Chat>> performIncrementalSync() async {
    late List<int>chatIds = [];
    if (isIsolate) {
      chatIds = await SyncActions.performIncrementalSync({});
    } else {
      chatIds = await GetIt.I<IncrementalSyncIsolate>()
          .send<List<int>>(IsolateRequestType.performIncrementalSync, input: {});
    }

    return Database.chats.getMany(chatIds).whereType<Chat>().toList();
  }
}
