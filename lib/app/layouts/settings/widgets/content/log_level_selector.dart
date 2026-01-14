import 'package:bluebubbles/app/components/settings/settings.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/core/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart' show Level;

final levelWhitelist = [Level.all, Level.info, Level.warning, Level.error];

class LogLevelSelector extends StatefulWidget {
  const LogLevelSelector({super.key});

  @override
  LogLevelSelectorState createState() => LogLevelSelectorState();
}

class LogLevelSelectorState extends State<LogLevelSelector> {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return BBSettingsDropdown<Level>(
        value: SettingsSvc.settings.logLevel.value,
        onChanged: (val) async {
          if (val == null) return;

          // Change the log level
          Logger.currentLevel = val;

          SettingsSvc.settings.logLevel.value = val;
          SettingsSvc.settings.saveOneAsync("logLevel");
        },
        options: Level.values.where((testLevel) => levelWhitelist.contains(testLevel)).toList(),
        textProcessing: (val) => val.name,
        capitalize: true,
        title: "Log Level",
      );
    });
  }
}
