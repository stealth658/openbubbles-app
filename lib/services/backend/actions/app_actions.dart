import 'package:bluebubbles/services/storage/settings_service.dart';

class AppActions {
  static Future<Map<String, dynamic>> checkForUpdate() async {
    return await SettingsSvc.getAppUpdateDict();
  }
}
