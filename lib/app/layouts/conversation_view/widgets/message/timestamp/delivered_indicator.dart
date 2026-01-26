import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DeliveredIndicator extends CustomStateful<MessageWidgetController> {
  const DeliveredIndicator({
    super.key,
    required super.parentController,
    required this.forceShow,
  });

  final bool forceShow;

  @override
  CustomState createState() => _DeliveredIndicatorState();
}

class _DeliveredIndicatorState extends CustomState<DeliveredIndicator, void, MessageWidgetController> {
  Message get message => controller.message;
  bool get showAvatar => (controller.cvController?.chat ?? ChatsSvc.activeChat!.chat).isGroup;

  bool get shouldShow {
    if (controller.audioWasKept.value != null) return true;
    final isTempMessage = controller.messageState?.isSending.value ?? message.guid!.contains("temp");
    if (widget.forceShow || isTempMessage) return true;
    if ((!message.isFromMe! && iOS) || (controller.parts.lastOrNull?.isUnsent ?? false)) return false;
    final messages = MessagesSvc(controller.cvController?.chat.guid ?? ChatsSvc.activeChat!.chat.guid)
        .struct
        .messages
        .where((e) => (!iOS ? !e.isFromMe! : false) || (e.isFromMe! && (e.dateDelivered != null || e.dateRead != null)))
        .toList()
      ..sort(Message.sort);
    final index = messages.indexWhere((e) => e.guid == message.guid);
    if (index == 0) return true;
    if (index == 1 && message.isFromMe!) {
      final newer = messages.first;
      if (message.dateRead != null) {
        return newer.dateRead == null;
      }
      if (message.dateDelivered != null) {
        return newer.dateDelivered == null;
      }
    }
    if (index > 1 && message.isFromMe!) {
      return messages.firstWhereOrNull((e) => e.dateRead != null)?.guid == message.guid;
    }
    return false;
  }

  List<InlineSpan> buildTwoPiece(String action, String? date) {
    return [
      TextSpan(
        text: "$action ",
        style: context.theme.textTheme.labelSmall!
            .copyWith(fontWeight: FontWeight.w600, color: context.theme.colorScheme.outline),
      ),
      if (date != null)
        TextSpan(
            text: date,
            style: context.theme.textTheme.labelSmall!
                .copyWith(color: context.theme.colorScheme.outline, fontWeight: FontWeight.normal))
    ];
  }

  List<InlineSpan> getText() {
    if (controller.audioWasKept.value != null) {
      return buildTwoPiece("Kept", buildDate(controller.audioWasKept.value!));
    } else if (!(message.isFromMe ?? false)) {
      return buildTwoPiece("Received", buildDate(message.dateCreated));
    } else if (message.dateRead != null) {
      return buildTwoPiece("Read", buildDate(message.dateRead));
    } else if (message.dateDelivered != null) {
      return buildTwoPiece(
          "Delivered${message.wasDeliveredQuietly && !message.didNotifyRecipient ? " Quietly" : ""}",
          SettingsSvc.settings.showDeliveryTimestamps.value || !iOS || widget.forceShow
              ? buildDate(message.dateDelivered)
              : null);
    } else if (message.isDelivered) {
      return buildTwoPiece("Delivered", null);
    } else if ((controller.messageState?.isSending.value ?? message.guid!.contains("temp")) &&
        !(controller.cvController?.chat ?? ChatsSvc.activeChat!.chat).isGroup &&
        !iOS) {
      return buildTwoPiece("Sending...", "");
    } else if (widget.forceShow) {
      return buildTwoPiece("Sent", buildDate(message.dateCreated));
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      curve: Curves.easeInOut,
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 250),
      child: Obx(() {
        // Observe granular MessageState fields instead of boolean toggles
        // This provides direct observation of actual data changes
        controller.messageState?.guid.value;
        controller.messageState?.dateDelivered.value;
        controller.messageState?.dateRead.value;
        return shouldShow && getText().isNotEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15).add(
                    EdgeInsets.only(top: 3, left: showAvatar || SettingsSvc.settings.alwaysShowAvatars.value ? 35 : 0)),
                child: Text.rich(TextSpan(
                  children: getText(),
                )),
              )
            : const SizedBox.shrink();
      }),
    );
  }
}
