import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Wraps [child] with an [Opacity] that reacts only to [isSending] changes,
/// keeping send-progress updates isolated from the rest of the card.
class SendingOpacityWrapper extends StatelessWidget {
  const SendingOpacityWrapper({super.key, required this.controller, required this.child});

  final MessageWidgetController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Obx(() => Opacity(
          opacity: (controller.messageState?.isSending.value ?? false) ? 0.5 : 1.0,
          child: child,
        ));
  }
}
