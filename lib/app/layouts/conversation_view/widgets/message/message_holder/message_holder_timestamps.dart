import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/tail_clipper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/text/text_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/message_timestamp.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Isolated widget for Samsung timestamp with reaction-aware padding
class SamsungTimestampObserver extends StatelessWidget {
  const SamsungTimestampObserver({
    super.key,
    required this.controller,
    required this.message,
    required this.messageParts,
    required this.part,
    required this.cvController,
    required this.getReactions,
    required this.reactionsForPart,
  });

  final MessageWidgetController controller;
  final Message message;
  final List<MessagePart> messageParts;
  final MessagePart part;
  final ConversationViewController cvController;
  final List<Message> Function() getReactions;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Observe MessageState associatedMessages for reaction changes
      controller.messageState?.associatedMessages.length;
      final reactions = getReactions();
      return Padding(
        padding: (messageParts.length == 1 && reactions.isNotEmpty) || reactionsForPart(part.part, reactions).isNotEmpty
            ? EdgeInsets.only(left: message.isFromMe! ? 0 : 10, right: message.isFromMe! ? 20 : 0)
            : const EdgeInsets.only(right: 10),
        child: MessageTimestamp(controller: controller, cvController: cvController),
      );
    });
  }
}

/// Isolated widget for edit history display
/// Only rebuilds when showEdits flag changes
class EditHistoryObserver extends StatelessWidget {
  const EditHistoryObserver({
    super.key,
    required this.controller,
    required this.message,
    required this.part,
    required this.newerMessage,
    required this.showAvatar,
    required this.alwaysShowAvatars,
    required this.avatarScale,
  });

  final MessageWidgetController controller;
  final Message message;
  final MessagePart part;
  final Message? newerMessage;
  final bool showAvatar;
  final bool alwaysShowAvatars;
  final double avatarScale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: showAvatar || alwaysShowAvatars ? EdgeInsets.only(left: 35.0 * avatarScale) : EdgeInsets.zero,
      child: Obx(() => AnimatedSize(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.bottomCenter,
            curve: controller.showEdits.value ? Curves.easeOutBack : Curves.easeOut,
            child: controller.showEdits.value
                ? Opacity(
                    opacity: 0.75,
                    child: Column(
                      crossAxisAlignment: message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: part.edits
                          .map((edit) => ClipPath(
                                clipper: TailClipper(
                                  isFromMe: message.isFromMe!,
                                  showTail: message.showTail(newerMessage) && part.part == controller.parts.length - 1,
                                  connectLower: SettingsSvc.settings.skin.value == Skins.iOS
                                      ? false
                                      : (part.part != 0 && part.part != controller.parts.length - 1) ||
                                          (part.part == 0 && controller.parts.length > 1),
                                  connectUpper: SettingsSvc.settings.skin.value == Skins.iOS ? false : part.part != 0,
                                ),
                                child: TextBubble(
                                  parentController: controller,
                                  message: edit,
                                ),
                              ))
                          .toList(),
                    ),
                  )
                : Container(
                    height: 0,
                    constraints: BoxConstraints(
                        maxWidth: NavigationSvc.width(context) * MessageWidgetController.maxBubbleSizeFactor - 30)),
          )),
    );
  }
}
