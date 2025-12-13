import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/services/backend/actions/image_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:bluebubbles/services/isolates/global_isolate.dart';

class ImageInterface {
  static Future<Uint8List?> convertToPng(PlatformFile file) async {
    final fileData = {
      'name': file.name,
      'path': file.path,
      'bytes': file.bytes,
      'size': file.size,
    };

    if (isIsolate()) {
      return ImageActions.convertToPng(fileData);
    } else {
      return await GetIt.I<GlobalIsolate>()
          .send<Uint8List?>(IsolateRequestType.convertImageToPng, input: fileData);
    }
  }
}
