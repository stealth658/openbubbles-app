import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';

class SyncActions {
  /// Performs an incremental sync and returns contact refresh data
  static Future<List<List<int>>> performIncrementalSync(dynamic data) async {
    try {
      int syncStart = SettingsSvc.settings.lastIncrementalSync.value;
      int startRowId = SettingsSvc.settings.lastIncrementalSyncRowId.value;
      
      final incrementalSyncManager = IncrementalSyncManager(
        startTimestamp: syncStart, 
        startRowId: startRowId, 
        saveMarker: true
      );
      
      await incrementalSyncManager.start();
      ChatsSvc.sort();
    } catch (ex, s) {
      Logger.error('Incremental sync failed!', error: ex, trace: s);
    }
    
    Logger.info('Starting contact refresh');
    try {
      final refreshedItems = await ContactsSvc.refreshContacts();
      Logger.info('Finished contact refresh, shouldRefresh $refreshedItems');
      return refreshedItems;
    } catch (ex, stack) {
      Logger.error('Contacts refresh failed!', error: ex, trace: stack);
      return [];
    }
  }
}
