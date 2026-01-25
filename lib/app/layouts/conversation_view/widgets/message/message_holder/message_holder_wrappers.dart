import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Isolated wrapper for select mode to minimize Obx scope
class SelectModeWrapper extends StatelessWidget {
  const SelectModeWrapper({
    super.key,
    required this.cvController,
    required this.message,
    required this.tapped,
    required this.child,
  });

  final ConversationViewController cvController;
  final Message message;
  final RxBool tapped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Obx(() => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: cvController.inSelectMode.value
              ? () {
                  if (cvController.isSelected(message.guid!)) {
                    cvController.selected.remove(message);
                  } else {
                    cvController.selected.add(message);
                  }
                }
              : kIsDesktop ||
                      kIsWeb ||
                      SettingsSvc.settings.skin.value == Skins.iOS ||
                      SettingsSvc.settings.skin.value == Skins.Material
                  ? () => tapped.value = !tapped.value
                  : null,
          child: IgnorePointer(
            ignoring: cvController.inSelectMode.value,
            child: child,
          ),
        ));
  }
}
