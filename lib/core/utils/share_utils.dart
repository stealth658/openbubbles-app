import 'dart:convert';

import 'package:bluebubbles/app/components/base/base.dart' hide BBDialogAction;
import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:metadata_fetch/metadata_fetch.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tuple/tuple.dart';
import 'package:universal_io/io.dart';

class Share {
  /// Share a file with other apps.
  static void files(List<String> filepaths) async {
    if (kIsDesktop) {
      showSnackbar("Unsupported", "Can't share files on desktop yet!");
    } else {
      await SharePlus.instance.share(ShareParams(files: filepaths.map((String path) => XFile(path)).toList()));
    }
  }

  /// Share text with other apps.
  static void text(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }

  static Future<void> location(Chat chat) async {
    bool _serviceEnabled;
    LocationPermission _permissionGranted;
    Position _locationData;

    _serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_serviceEnabled) {
      final actions = <BBDialogAction>[
        if (!kIsDesktop || !Platform.isLinux)
          BBDialogAction(
            label: "Cancel",
            type: BBDialogButtonType.cancel,
            onPressed: () => Navigator.of(Get.context!, rootNavigator: true).pop(),
          ),
        if (!kIsDesktop || !Platform.isLinux)
          BBDialogAction(
            label: "Open Settings",
            type: BBDialogButtonType.primary,
            onPressed: () async => await Geolocator.openLocationSettings(),
          ),
        if (kIsDesktop && Platform.isLinux)
          BBDialogAction(
            label: "OK",
            type: BBDialogButtonType.primary,
            onPressed: () => Navigator.of(Get.context!, rootNavigator: true).pop(),
          ),
      ];

      await BBAlertDialog.show(
        context: Get.context!,
        title: "Location Services",
        message: "Location Services must be enabled to send Locations",
        actions: actions,
      );
      if (!_serviceEnabled) {
        return;
      }
    }

    if (!kIsDesktop || !Platform.isLinux) {
      _permissionGranted = await Geolocator.checkPermission();
      if (_permissionGranted == LocationPermission.denied) {
        _permissionGranted = await Geolocator.requestPermission();
      }
      if (_permissionGranted == LocationPermission.denied || _permissionGranted == LocationPermission.deniedForever) {
        await BBAlertDialog.show(
          context: Get.context!,
          title: "Location Permission",
          message: "BlueBubbles needs the Location permission to send Locations",
          actions: [
            BBDialogAction(
              label: "Cancel",
              type: BBDialogButtonType.cancel,
              onPressed: () => Navigator.of(Get.context!, rootNavigator: true).pop(),
            ),
            BBDialogAction(
              label: "Open Settings",
              type: BBDialogButtonType.primary,
              onPressed: () async => await Geolocator.openLocationSettings(),
            ),
          ],
        );
        if (_permissionGranted == LocationPermission.denied || _permissionGranted == LocationPermission.deniedForever) {
          return;
        }
      }
    }

    String? _attachmentGuid;
    String? fileName;
    Uint8List? bytes;
    String? url;
    String? title;

    Future<Tuple5<String, String, Uint8List, String, String?>> getLocationPreview() async {
      _locationData = await Geolocator.getCurrentPosition();
      String vcfString = AttachmentsSvc.createAppleLocation(_locationData.latitude, _locationData.longitude);

      // Build out the file we are going to send
      String _attachmentGuid = "temp-${randomString(8)}";
      String fileName = "$_attachmentGuid-CL.loc.vcf";
      Uint8List bytes = Uint8List.fromList(utf8.encode(vcfString));

      Metadata meta = await MetadataHelper.getLocationMetadata(_locationData);
      String url = meta.image!;
      String? title = meta.title;

      return Tuple5(_attachmentGuid, fileName, bytes, url, title);
    }

    bool send = false;
    if (kIsDesktop || kIsWeb) {
      cvc(chat).showingOverlays = true;
    }
    await BBCustomDialog.show(
      context: Get.context!,
      title: "Send Location?",
      content: FutureBuilder(
          future: getLocationPreview(),
          builder: (context, snapshot) {
            if (snapshot.data != null) {
              _attachmentGuid = snapshot.data!.item1;
              fileName = snapshot.data!.item2;
              bytes = snapshot.data!.item3;
              url = snapshot.data!.item4;
              title = snapshot.data!.item5;
            }
            if (url == null) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Loading Location..."),
                  SizedBox(height: 10),
                  BBLoadingIndicator(),
                ],
              );
            }
            return SizedBox(
              width: 150,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.network(
                    url!,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, __, ___) {
                      return const SizedBox.shrink();
                    },
                    frameBuilder: (_, child, frame, __) {
                      if (frame == null) {
                        return const Center(
                          heightFactor: 1,
                          child: BBLoadingIndicator(),
                        );
                      } else {
                        return child;
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  Text(
                    title ?? "No location details found",
                    style: Theme.of(context).textTheme.bodyMedium!.apply(fontWeightDelta: 2),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          }),
      actions: [
        BBDialogAction(
          label: "Cancel",
          type: BBDialogButtonType.cancel,
          onPressed: () {},
        ),
        BBDialogAction(
          label: "Send",
          type: BBDialogButtonType.primary,
          onPressed: () {
            send = true;
          },
        ),
      ],
    );
    if (kIsDesktop || kIsWeb) {
      cvc(chat).showingOverlays = false;
    }

    if (!send) return;
    if (bytes == null) return;

    final message = Message(
      guid: _attachmentGuid,
      text: "",
      dateCreated: DateTime.now(),
      hasAttachments: true,
      attachments: [
        Attachment(
          guid: _attachmentGuid,
          mimeType: "text/x-vlocation",
          isOutgoing: true,
          uti: "public.vlocation",
          bytes: bytes,
          transferName: fileName,
          totalBytes: bytes!.length,
        ),
      ],
      isFromMe: true,
      handleId: 0,
    );

    outq.queue(OutgoingItem(
      type: QueueType.sendAttachment,
      chat: chat,
      message: message,
    ));
  }
}
