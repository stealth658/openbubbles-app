import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class DeliveredIndicator extends StatefulWidget {
  const DeliveredIndicator({
    super.key,
    required this.forceShow,
  });

  final bool forceShow;

  @override
  State<StatefulWidget> createState() => _DeliveredIndicatorState();
}

class _DeliveredIndicatorState extends State<DeliveredIndicator> with ThemeHelpers {
  late MessageState _ms;
  MessageState get controller => _ms;
  late final String _chatGuid;
  late final bool _isGroup;
  Message get message => controller.message;
  bool get showAvatar => _isGroup;

  @override
  void initState() {
    super.initState();
    _ms = MessageStateScope.readStateOnce(context);
    final fallbackChat = ChatStateScope.maybeReadChatOnce(context);
    _chatGuid = controller.cvController?.chat.guid ?? fallbackChat?.guid ?? '';
    _isGroup = controller.cvController?.chat.isGroup ?? fallbackChat?.isGroup ?? false;
  }

  bool get shouldShow {
    if (controller.audioWasKept.value != null) return true;
    final isTempMessage = controller.isSending.value;
    if (widget.forceShow || isTempMessage) return true;
    if ((!message.isFromMe! && iOS) || (controller.parts.lastOrNull?.isUnsent ?? false)) return false;

    // Prefer reactive messageState values to avoid stale reads on delivery/read receipts.
    final dateRead = controller.dateRead.value;
    final dateDelivered = controller.dateDelivered.value;

    final chatGuid = _chatGuid;
    final allMessages = MessagesSvc(chatGuid).struct.messages;

    // Non-iOS: show "Received" only on the most recent incoming message.
    if (!message.isFromMe!) {
      final lastIncoming = allMessages.where((e) => !e.isFromMe!).toList()..sort(Message.sort);
      return lastIncoming.firstOrNull?.guid == message.guid;
    }

    // Show "Read" on the most recently read outgoing message.
    // This takes priority over "Delivered" even when a newer message is only delivered.
    if (dateRead != null) {
      final lastRead = allMessages
          .where((e) => e.isFromMe! && e.dateRead != null)
          .toList()..sort(Message.sort);
      return lastRead.firstOrNull?.guid == message.guid;
    }

    // Show "Delivered" only on the newest outgoing message that has any receipt.
    if (dateDelivered != null) {
      final lastDelivered = allMessages
          .where((e) => e.isFromMe! && (e.dateDelivered != null || e.dateRead != null))
          .toList()..sort(Message.sort);
      return lastDelivered.firstOrNull?.guid == message.guid;
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
    // Use reactive MessageState fields for Obx subscription
    final dateRead = controller.dateRead.value ?? message.dateRead;
    final dateDelivered = controller.dateDelivered.value ?? message.dateDelivered;
    final wasDeliveredQuietly = controller.wasDeliveredQuietly.value;
    final didNotifyRecipient = controller.didNotifyRecipient.value;

    if (controller.audioWasKept.value != null) {
      return buildTwoPiece("Kept", buildDate(controller.audioWasKept.value!));
    } else if (!(message.isFromMe ?? false)) {
      return buildTwoPiece("Received", buildDate(message.dateCreated));
    } else if (dateRead != null) {
      return buildTwoPiece("Read", buildDate(dateRead));
    } else if (dateDelivered != null) {
      return buildTwoPiece(
          "Delivered${wasDeliveredQuietly && !didNotifyRecipient ? " Quietly" : ""}",
          SettingsSvc.settings.showDeliveryTimestamps.value || !iOS || widget.forceShow
              ? buildDate(dateDelivered)
              : null);
    } else if (message.isDelivered) {
      return buildTwoPiece("Delivered", null);
    } else if (controller.isSending.value &&
        !(controller.cvController?.chat.isGroup ?? _isGroup) &&
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
        // Observe granular MessageState fields directly
        controller.guid.value;
        controller.dateDelivered.value;
        controller.dateRead.value;
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
