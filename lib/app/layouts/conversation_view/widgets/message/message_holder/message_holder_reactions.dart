import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/sticker_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction_holder.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/ui/reaction_helpers.dart';
import 'package:bluebubbles/services/ui/chat/conversation_view_controller.dart';
import 'package:bluebubbles/services/ui/message/message_widget_controller.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Isolated widget for reaction display
/// Only rebuilds when MessageState.associatedMessages changes
class ReactionObserver extends StatelessWidget {
  const ReactionObserver({
    super.key,
    required this.controller,
    required this.message,
    required this.messageParts,
    required this.part,
    required this.chatGuid,
    required this.reactionsForPart,
  });

  final MessageWidgetController controller;
  final Message message;
  final List<MessagePart> messageParts;
  final MessagePart part;
  final String chatGuid;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Directly observe MessageState for all reactive data
      final isFromMe = controller.messageState?.isFromMe.value ?? message.isFromMe!;
      final associatedMessages = controller.messageState?.associatedMessages ?? message.associatedMessages;
      final reactions = associatedMessages
          .where((e) => ReactionTypes.toList().contains(e.associatedMessageType?.replaceAll("-", "")))
          .toList();
      final reactionList = messageParts.length == 1 ? reactions : reactionsForPart(part.part, reactions).toList();
    
      Logger.debug(
          "[MessageHolder] Rebuilding ReactionHolder for ${message.guid} (isFromMe: $isFromMe) with ${reactionList.length} reactions",
          tag: "MessageReactivity");
    
      return Positioned(
        top: -14,
        left: isFromMe ? -20 : null,
        right: isFromMe ? null : -20,
        child: ReactionHolder(
          reactions: reactionList,
          message: message,
        ),
      );
    });
  }
}

/// Isolated widget for sticker display
class StickerObserver extends StatelessWidget {
  const StickerObserver({
    super.key,
    required this.messageParts,
    required this.stickers,
    required this.part,
    required this.cvController,
  });

  final List<MessagePart> messageParts;
  final List<Message> stickers;
  final MessagePart part;
  final ConversationViewController cvController;

  @override
  Widget build(BuildContext context) {
    final stickersForPart =
        messageParts.length == 1 ? stickers : stickers.where((s) => (s.associatedMessagePart ?? 0) == part.part);

    if (stickersForPart.isEmpty) return const SizedBox.shrink();

    return StickerHolder(
      stickerMessages: stickersForPart,
      controller: cvController,
    );
  }
}

/// Isolated widget for reaction spacing calculation
/// Only rebuilds when reactions change, not the entire message part
class ReactionSpacing extends StatelessWidget {
  const ReactionSpacing({
    super.key,
    required this.controller,
    required this.messageParts,
    required this.part,
    required this.reactionsForPart,
  });

  final MessageWidgetController controller;
  final List<MessagePart> messageParts;
  final MessagePart part;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Directly observe MessageState associatedMessages for reactivity
      final associatedMessages = controller.messageState?.associatedMessages ?? [];
      final reactions = associatedMessages
          .where((e) => ReactionTypes.toList().contains(e.associatedMessageType?.replaceAll("-", "")))
          .cast<Message>()
          .toList();
      if ((messageParts.length == 1 && reactions.isNotEmpty) || reactionsForPart(part.part, reactions).isNotEmpty) {
        return const SizedBox(height: 12.5);
      }
      return const SizedBox.shrink();
    });
  }
}
