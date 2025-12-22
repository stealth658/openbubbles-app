import 'dart:async';

import 'package:bluebubbles/services/backend/interfaces/contact_interface.dart';
import 'package:bluebubbles/services/backend/interfaces/sync_interface.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
SyncService get SyncSvc => GetIt.I<SyncService>();

class SyncService {
  int numberOfMessagesPerPage = 25;
  bool skipEmptyChats = true;
  bool saveToDownloads = false;
  int? syncTimeFilter;
  final RxBool isIncrementalSyncing = false.obs;

  FullSyncManager? _manager;
  FullSyncManager? get fullSyncManager => _manager;

  void initFullSync() {
    _manager = FullSyncManager(
        messageCount: numberOfMessagesPerPage.toInt(),
        skipEmptyChats: skipEmptyChats,
        saveLogs: saveToDownloads,
        syncTimeFilter: syncTimeFilter
    );
  }
  
  Future<void> startFullSync() async {
    if (_manager == null) {
      initFullSync();
    }

    // Set the last sync date (for incremental, even though this isn't incremental)
    // We won't try an incremental sync until the last (full) sync date is set
    SettingsSvc.settings.lastIncrementalSync.value = DateTime.now().millisecondsSinceEpoch;
    await SettingsSvc.saveSettings();
    await _manager!.start();
  }

  Future<void> startIncrementalSync() async {
    isIncrementalSyncing.value = true;

    List<List<int>> result = [];
    Logger.info('[Incremental Sync] Starting incremental sync...');
    
    try {
      // Use the GlobalIsolate to perform the sync
      result = await SyncInterface.performIncrementalSync();
      
      if (result.isNotEmpty && (result.first.isNotEmpty || result.last.isNotEmpty)) {
        // Auto upload contacts if requested
        if (SettingsSvc.settings.syncContactsAutomatically.value) {
          Logger.debug("Contact changes detected, uploading to server...");
          
          // Get all contacts from ContactServiceV2
          final contactsV2 = await ContactsSvcV2.getAllContacts();
          final _contacts = <Map<String, dynamic>>[];
          for (final c in contactsV2) {
            _contacts.add(c.toMap());
          }
          
          try {
            await ContactInterface.uploadContacts(_contacts);
          } catch (err, stack) {
            Logger.error("Failed to upload contacts!", error: err, trace: stack);
          }
        }
        
        // Notify UI about contact changes via handle IDs
        if (result.last.isNotEmpty) {
          ContactsSvcV2.notifyHandlesUpdated(result.last);
        }
      }
    } catch (e, stack) {
      Logger.error('Incremental sync failed!', error: e, trace: stack);
    }

    isIncrementalSyncing.value = false;
  }
}