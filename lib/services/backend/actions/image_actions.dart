import 'package:flutter/foundation.dart';
import 'package:image/image.dart';
import 'package:universal_io/io.dart';

class ImageActions {
  static Uint8List? convertToPng(Map<String, dynamic> fileData) {
    try {
      final path = fileData['path'] as String?;
      final bytes = fileData['bytes'] as Uint8List?;
      
      // Get image bytes from either bytes or file path
      final Uint8List? imageBytes = bytes ?? (path != null && !kIsWeb ? File(path).readAsBytesSync() : null);
      
      if (imageBytes == null) {
        return null;
      }
      
      final image = decodeImage(imageBytes);
      if (image == null) {
        return null;
      }
      
      return Uint8List.fromList(encodePng(image));
    } catch (e) {
      print('Error converting image to PNG: $e');
      return null;
    }
  }
}
