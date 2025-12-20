import 'package:bluebubbles/helpers/backend/startup_tasks.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/network/network_tasks.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:get/get.dart';

SetupService setup = Get.isRegistered<SetupService>() ? Get.find<SetupService>() : Get.put(SetupService());

class SetupService extends GetxService {
  Future<void> startSetup(int numberOfMessagesPerPage, bool skipEmptyChats, bool saveToDownloads, int? syncTimeFilter) async {
    SyncSvc.numberOfMessagesPerPage = numberOfMessagesPerPage;
    SyncSvc.skipEmptyChats = skipEmptyChats;
    SyncSvc.saveToDownloads = saveToDownloads;
    SyncSvc.syncTimeFilter = syncTimeFilter;
    SyncSvc.initFullSync();
    await SyncSvc.startFullSync();
    await _finishSetup();
  }

  Future<void> _finishSetup() async {
    SettingsSvc.settings.finishedSetup.value = true;
    await SettingsSvc.saveSettings();
    await StartupTasks.onStartup();
    await NetworkTasks.onConnect();
    
    // Trigger a full UI update for the chat list
    ChatsSvc.chats.refresh();
  }
}