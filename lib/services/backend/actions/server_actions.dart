import 'package:bluebubbles/services/storage/settings_service.dart';

class ServerActions {
  static Future<Map<String, dynamic>> checkForServerUpdate() async {
    return await SettingsSvc.getServerUpdateDict();
  }

  static Future<Map<String, dynamic>> getServerDetails() async {
    return await SettingsSvc.getServerDetailsDict();
  }
}
