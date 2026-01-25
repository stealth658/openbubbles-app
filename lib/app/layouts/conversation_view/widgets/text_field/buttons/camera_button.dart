import 'package:bluebubbles/services/ui/chat/conversation_view_controller.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

/// Widget for the camera button that opens the device camera
class CameraButton extends StatelessWidget {
  final ConversationViewController controller;
  final Future<void> Function({required String type}) openFullCamera;
  
  const CameraButton({
    super.key,
    required this.controller,
    required this.openFullCamera,
  });
  
  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !context.iOS || !Platform.isAndroid) {
      return const SizedBox.shrink();
    }
    
    return GestureDetector(
      onLongPress: () {
        openFullCamera(type: 'video');
      },
      child: IconButton(
        padding: const EdgeInsets.only(left: 10),
        icon: Icon(
          CupertinoIcons.camera_fill,
          color: context.theme.colorScheme.outline,
          size: 28,
        ),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          openFullCamera(type: 'camera');
        },
      ),
    );
  }
}

/// Utility function to handle opening the camera (extracted from main widget)
Future<void> openFullCamera(
  ConversationViewController controller, {
  required String type,
}) async {
  bool granted = (await Permission.camera.request()).isGranted;
  if (!granted) {
    showSnackbar("Error", "Camera access was denied!");
    return;
  }

  late final XFile? file;
  if (type == 'camera') {
    file = await ImagePicker().pickImage(source: ImageSource.camera);
  } else {
    file = await ImagePicker().pickVideo(source: ImageSource.camera);
  }
  
  if (file != null) {
    controller.pickedAttachments.add(PlatformFile(
      path: file.path,
      name: file.path.split('/').last,
      size: await file.length(),
      bytes: await file.readAsBytes(),
    ));
  }
}
