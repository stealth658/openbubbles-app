import 'dart:typed_data';
import 'dart:ui';

import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/core/constants/app_constants.dart';
import 'package:bluebubbles/helpers/ui/ui_helpers.dart';
import 'package:bluebubbles/services/platform/android/intents_service.dart';
import 'package:bluebubbles/services/storage/settings_service.dart';
import 'package:faker/faker.dart' hide Image;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:bluebubbles/services/backend/notifications/notifications_service.dart';

Map<String, Route> faceTimeOverlays = {}; // Map from call uuid to overlay route

/// Hides the FaceTime overlay with the given [callUuid]
/// Also calls [NotificationsService.clearFaceTimeNotification] to clear the notification
void hideFaceTimeOverlay(String callUuid) {
  NotificationsSvc.clearFaceTimeNotification(callUuid);
  if (faceTimeOverlays.containsKey(callUuid)) {
    Get.removeRoute(faceTimeOverlays[callUuid]!);
    faceTimeOverlays.remove(callUuid);
  }
}

/// Shows a FaceTime overlay with the given [callUuid], [caller], [chatIcon], and [isAudio]
/// Saves the overlay route in [faceTimeOverlays]
Future<void> showFaceTimeOverlay(String callUuid, String caller, Uint8List? chatIcon, bool isAudio) async {
  if (SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value) {
    if (chatIcon != null) chatIcon = null;
    caller = faker.person.name();
  }
  chatIcon ??= (await rootBundle.load("assets/images/person64.png")).buffer.asUint8List();
  chatIcon = await clip(chatIcon, size: 256, circle: true);

  // If we are somehow already showing an overlay for this call, close it
  hideFaceTimeOverlay(callUuid);

  BBCustomDialog.show(
    context: Get.context!,
    config: const BBCustomDialogConfig(
      barrierDismissible: false,
    ),
    title: caller,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.memory(chatIcon!, width: 48, height: 48),
        const SizedBox(height: 16),
        Text(
          "Incoming FaceTime ${isAudio ? "Audio" : "Video"} Call",
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MaterialButton(
              elevation: 0,
              hoverElevation: 0,
              color: Colors.green.withValues(alpha: 0.2),
              splashColor: Colors.green,
              highlightColor: Colors.green.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 36.0),
              child: Column(
                children: [
                  Icon(
                    SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.phone : Icons.call_outlined,
                    color: Colors.green,
                  ),
                  const Text(
                    "Accept",
                  ),
                ],
              ),
              onPressed: () async {
                await IntentsSvc.answerFaceTime(callUuid);
              },
            ),
            const SizedBox(width: 16.0),
            MaterialButton(
              elevation: 0,
              hoverElevation: 0,
              color: Colors.red.withValues(alpha: 0.2),
              splashColor: Colors.red,
              highlightColor: Colors.red.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 36.0),
              child: Column(
                children: [
                  Icon(
                    SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.phone_down : Icons.call_end_outlined,
                    color: Colors.red,
                  ),
                  const Text(
                    "Ignore",
                  ),
                ],
              ),
              onPressed: () {
                hideFaceTimeOverlay(callUuid);
              },
            ),
          ],
        ),
      ],
    ),
    actions: const [],
  ).then((_) => faceTimeOverlays.remove(
          callUuid) /* Not explicitly necessary since all ways of closing the dialog do this, but just in case */
      );

  // Save dialog as overlay route
  faceTimeOverlays[callUuid] = Get.rawRoute!;
}
