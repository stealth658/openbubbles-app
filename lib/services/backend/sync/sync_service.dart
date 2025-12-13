import 'dart:async';

import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/interfaces/contact_interface.dart';
import 'package:bluebubbles/services/backend/interfaces/prefs_interface.dart';
import 'package:bluebubbles/services/backend/interfaces/sync_interface.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart' hide Response;
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
SyncService get SyncSvc => GetIt.I<SyncService>();

class SyncService {
  int numberOfMessagesPerPage = 25;
  bool skipEmptyChats = true;
  bool saveToDownloads = false;
  final RxBool isIncrementalSyncing = false.obs;

  FullSyncManager? _manager;
  FullSyncManager? get fullSyncManager => _manager;

  void initFullSync() {
    _manager = FullSyncManager(
        messageCount: numberOfMessagesPerPage.toInt(),
        skipEmptyChats: skipEmptyChats,
        saveLogs: saveToDownloads
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
    await PrefsInterface.syncSettings();
    await _manager!.start();
  }

  Future<void> startIncrementalSync() async {
    isIncrementalSyncing.value = true;

    final contacts = <Contact>[];
    List<List<int>> result = [];
    
    try {
      // Use the GlobalIsolate to perform the sync
      result = await SyncInterface.performIncrementalSync();
      
      if (result.isNotEmpty && (result.first.isNotEmpty || result.last.isNotEmpty)) {
        contacts.addAll(kIsWeb || kIsDesktop ? ContactsSvc.contacts : Contact.getContacts());
        
        // Auto upload contacts if requested
        if (SettingsSvc.settings.syncContactsAutomatically.value) {
          Logger.debug("Contact changes detected, uploading to server...");
          final _contacts = <Map<String, dynamic>>[];
          for (Contact c in contacts) {
            var map = c.toMap();
            _contacts.add(map);
          }
          
          try {
            await ContactInterface.uploadContacts(_contacts);
          } catch (err, stack) {
            Logger.error("Failed to upload contacts!", error: err, trace: stack);
          }
        }
      }
    } catch (e, stack) {
      Logger.error('Incremental sync failed!', error: e, trace: stack);
    }
    
    ContactsSvc.completeContactsRefresh(contacts, reloadUI: result);

    isIncrementalSyncing.value = false;
  }
}