import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/ui/message/message_widget_controller.dart';
import 'package:flutter/material.dart';

import 'message_holder_reactions.dart';

/// Consolidated widget for displaying reactions on a message part
/// Handles both isFromMe and !isFromMe cases
class MessageReactions extends StatelessWidget {
  const MessageReactions({
    super.key,
    required this.controller,
    required this.message,
    required this.messageParts,
    required this.part,
    required this.chatGuid,
    required this.getReactions,
    required this.reactionsForPart,
  });

  final MessageWidgetController controller;
  final Message message;
  final List<MessagePart> messageParts;
  final MessagePart part;
  final String chatGuid;
  final List<Message> Function() getReactions;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;

  @override
  Widget build(BuildContext context) {
    return ReactionObserver(
      controller: controller,
      message: message,
      messageParts: messageParts,
      part: part,
      chatGuid: chatGuid,
      isFromMe: message.isFromMe!,
      getReactions: getReactions,
      reactionsForPart: reactionsForPart,
    );
  }
}
