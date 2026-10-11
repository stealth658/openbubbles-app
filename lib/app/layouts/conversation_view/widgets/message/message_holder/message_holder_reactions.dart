import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/sticker_holder.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction_holder.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/helpers/ui/reaction_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/ui/chat/conversation_view_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

/// Isolated widget for reaction display
/// Only rebuilds when MessageState.associatedMessages changes
///
/// Not used for media-gallery parts on iOS skin — those attach a reaction
/// per attachment inside [MessageImageGallery] instead, since a gallery can
/// bundle several originally-separate message parts (see
/// MessageHolder._collapseImageGalleryParts) and a tapback is only ever
/// associated with one of them.
class ReactionObserver extends StatelessWidget {
  const ReactionObserver({
    super.key,
    required this.messageParts,
    required this.part,
    required this.chatGuid,
    required this.reactionsForPart,
  });

  final List<MessagePart> messageParts;
  final MessagePart part;
  final String chatGuid;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;

  @override
  Widget build(BuildContext context) {
    final state = MessageStateScope.of(context);
    return Obx(() {
      // Directly observe MessageState for all reactive data
      final isFromMe = state.isFromMe.value;
      final associatedMessages = state.associatedMessages;
      final reactions = associatedMessages
          .where((e) => ReactionTypes.toList().contains(e.associatedMessageType?.replaceAll("-", "")))
          .toList();
      final reactionList = messageParts.length == 1 ? reactions : reactionsForPart(part.part, reactions).toList();

      if (SettingsSvc.settings.skin.value == Skins.Material) {
        // Google Messages: a small pill of the reaction emoji (with a count
        // when there is more than one) overlapping the bubble's bottom edge,
        // on the sender's side. 10px clears TailClipper's hidden gutter.
        if (reactionList.isEmpty) return const SizedBox.shrink();
        return Positioned(
          bottom: -16,
          left: isFromMe ? null : 18,
          right: isFromMe ? 18 : null,
          child: _GoogleReactionPill(
            reactions: reactionList,
            // With the iOS-style tapback menu the reactions were picked as
            // iMessage tapbacks, so draw them with the same tapback icons.
            iosIcons: SettingsSvc.settings.materialIosMessageMenu.value,
          ),
        );
      }
      return Positioned(
        top: -14,
        left: isFromMe ? -20 : null,
        right: isFromMe ? null : -20,
        child: ReactionHolder(
          reactions: reactionList,
        ),
      );
    });
  }
}

class _GoogleReactionPill extends StatelessWidget {
  const _GoogleReactionPill({required this.reactions, required this.iosIcons});

  final List<Message> reactions;
  final bool iosIcons;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final unique = getUniqueReactionMessages(reactions);
    final seen = <String>{};
    final glyphs = <Widget>[];
    for (final r in unique) {
      final type = r.associatedMessageType?.replaceAll("-", "");
      final isTapback = type != null && type != ReactionTypes.EMOJI && ReactionTypes.reactionToEmoji.containsKey(type);
      final emoji = ReactionTypes.reactionToEmoji[type] ?? r.associatedMessageEmoji;
      if (emoji == null) continue;
      if (!seen.add(isTapback ? type : emoji)) continue;
      if (glyphs.length == 3) break;
      if (iosIcons && isTapback) {
        glyphs.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 2.5),
          child: SvgPicture.asset(
            'assets/reactions/$type-black.svg',
            width: 14,
            height: 14,
            colorFilter: ColorFilter.mode(type == "love" ? Colors.pink : scheme.onSurfaceVariant, BlendMode.srcIn),
          ),
        ));
      } else {
        glyphs.add(Text(emoji, style: const TextStyle(fontSize: 15, height: 1.3)));
      }
    }
    if (glyphs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...glyphs,
          if (unique.length > 1) ...[
            const SizedBox(width: 3),
            Text("${unique.length}",
                style: context.theme.textTheme.labelSmall!.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// Isolated widget for sticker display.
/// Uses its own [Obx] so sticker rebuilds are decoupled from the outer
/// message-holder [Obx] (which tracks isSending, isFromMe, parts, etc.).
class StickerObserver extends StatelessWidget {
  const StickerObserver({
    super.key,
    required this.messageParts,
    required this.part,
    required this.cvController,
  });

  final List<MessagePart> messageParts;
  final MessagePart part;
  final ConversationViewController cvController;

  @override
  Widget build(BuildContext context) {
    final state = MessageStateScope.of(context);
    return Obx(() {
      final allStickers = state.associatedMessages.where((e) => e.associatedMessageType == "sticker").toList();
      final stickersForPart = messageParts.length == 1
          ? allStickers
          : allStickers.where((s) => (s.associatedMessagePart ?? 0) == part.part).toList();

      if (stickersForPart.isEmpty) return const SizedBox.shrink();

      return StickerHolder(
        stickerMessages: stickersForPart,
        controller: cvController,
      );
    });
  }
}

/// Isolated widget for reaction spacing calculation
/// Only rebuilds when reactions change, not the entire message part
class ReactionSpacing extends StatelessWidget {
  const ReactionSpacing({
    super.key,
    required this.messageParts,
    required this.part,
    required this.reactionsForPart,
    this.minHeightWhenNoReactions = 0,
  });

  final List<MessagePart> messageParts;
  final MessagePart part;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;
  final double minHeightWhenNoReactions;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state = MessageStateScope.of(context);
      // Directly observe MessageState associatedMessages for reactivity
      final associatedMessages = state.associatedMessages;
      final reactions = associatedMessages
          .where((e) => ReactionTypes.toList().contains(e.associatedMessageType?.replaceAll("-", "")))
          .cast<Message>()
          .toList();
      // A gallery part can bundle several originally-separate message parts
      // (see MessageHolder._collapseImageGalleryParts), so check every one
      // of them rather than just part.part.
      final relevantParts = part.attachmentPartIndices?.toSet() ?? {part.part};
      final hasReaction = relevantParts.any((p) => reactionsForPart(p, reactions).isNotEmpty);
      if ((messageParts.length == 1 && reactions.isNotEmpty) || hasReaction) {
        return const SizedBox(height: 12.5);
      }

      if (minHeightWhenNoReactions > 0) {
        return SizedBox(height: minHeightWhenNoReactions);
      }

      return const SizedBox.shrink();
    });
  }
}
