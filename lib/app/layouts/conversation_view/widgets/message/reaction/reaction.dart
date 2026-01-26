import 'dart:math';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction_clipper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/shared/message_error_helper.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';

class ReactionWidget extends StatefulWidget {
  const ReactionWidget({
    super.key,
    required this.message,
    required this.reaction,
    this.reactions,
  });

  final Message? message;
  final Message reaction;
  final List<Message>? reactions;

  @override
  ReactionWidgetState createState() => ReactionWidgetState();
}

class ReactionWidgetState extends OptimizedState<ReactionWidget> {
  List<Message>? get reactions => widget.reactions;

  // Observe the reaction from parent message's associatedMessages list
  // This is already an RxList in MessageState, so changes propagate automatically
  Message get reaction {
    // First check if parent has MessageState with associatedMessages
    final chatGuid = widget.message?.chat.target?.guid ?? ChatsSvc.activeChat?.chat.guid;
    final parentController =
        chatGuid != null ? MessagesSvc(chatGuid).getControllerIfExists(widget.message?.guid ?? '') : null;
    if (parentController?.messageState != null) {
      // Find our reaction in the observable associatedMessages list
      final found = parentController!.messageState!.associatedMessages.firstWhereOrNull((m) =>
          m.guid == widget.reaction.guid ||
          (m.associatedMessageType == widget.reaction.associatedMessageType &&
              m.associatedMessagePart == widget.reaction.associatedMessagePart &&
              m.isFromMe == widget.reaction.isFromMe));
      if (found != null) return found;
    }
    // Fallback to widget.reaction if not found in MessageState
    return widget.reaction;
  }

  bool get reactionIsFromMe => reaction.isFromMe!;
  bool get messageIsFromMe => widget.message?.isFromMe ?? true;
  String get reactionType => reaction.associatedMessageType!;

  MessageWidgetController? get reactionController {
    final chatGuid = widget.message?.chat.target?.guid ?? ChatsSvc.activeChat?.chat.guid;
    if (chatGuid == null || reaction.guid == null) return null;
    return MessagesSvc(chatGuid).getControllerIfExists(reaction.guid!);
  }

  static const double iosSize = 35;

  @override
  Widget build(BuildContext context) {
    // Wrap in Obx to observe changes to the reaction from parent's associatedMessages RxList
    return Obx(() {
      // Access the reaction getter which reads from MessageState.associatedMessages
      // This triggers rebuild when the reaction changes (temp->real GUID, error state, etc.)
      final _ = reaction; // Force observation of the getter

      if (SettingsSvc.settings.skin.value != Skins.iOS) {
        return Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: reactionIsFromMe ? context.theme.colorScheme.primary : context.theme.colorScheme.properSurface,
              border: Border.all(color: context.theme.colorScheme.background),
              shape: BoxShape.circle,
            ),
            child: GestureDetector(
              onTap: () {
                if (reactions == null) return;
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 500),
                    pageBuilder: (context, animation, secondaryAnimation) {
                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 1.0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
                        child: Theme(
                          data: context.theme.copyWith(
                            // in case some components still use legacy theming
                            primaryColor: context.theme.colorScheme.bubble(context, true),
                            colorScheme: context.theme.colorScheme.copyWith(
                              primary: context.theme.colorScheme.bubble(context, true),
                              onPrimary: context.theme.colorScheme.onBubble(context, true),
                              surface: SettingsSvc.settings.monetTheming.value == Monet.full
                                  ? null
                                  : (context.theme.extensions[BubbleColors] as BubbleColors?)?.receivedBubbleColor,
                              onSurface: SettingsSvc.settings.monetTheming.value == Monet.full
                                  ? null
                                  : (context.theme.extensions[BubbleColors] as BubbleColors?)?.onReceivedBubbleColor,
                            ),
                          ),
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.of(context).pop();
                                },
                              ),
                              Positioned(
                                  bottom: 10, left: 15, right: 15, child: ReactionDetails(reactions: reactions!)),
                            ],
                          ),
                        ),
                      );
                    },
                    fullscreenDialog: true,
                    opaque: false,
                    barrierDismissible: true,
                  ),
                );
              },
              child: Center(
                child: Builder(builder: (context) {
                  final text = Text(
                    ReactionTypes.reactionToEmoji[reactionType] ?? "X",
                    style: const TextStyle(fontSize: 15, fontFamily: 'Apple Color Emoji'),
                    textAlign: TextAlign.center,
                  );
                  // rotate thumbs down to match iOS
                  if (reactionType == "dislike") {
                    return Transform(
                      transform: Matrix4.identity()..rotateY(pi),
                      alignment: FractionalOffset.center,
                      child: text,
                    );
                  }
                  return text;
                }),
              ),
            ));
      }
      return Stack(
        alignment: messageIsFromMe ? Alignment.centerRight : Alignment.centerLeft,
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -1,
            left: messageIsFromMe ? 0 : -1,
            right: !messageIsFromMe ? 0 : -1,
            child: ClipPath(
              clipper: ReactionBorderClipper(isFromMe: messageIsFromMe),
              child: Container(
                width: iosSize + 2,
                height: iosSize + 2,
                color: context.theme.colorScheme.background,
              ),
            ),
          ),
          ClipPath(
              clipper: ReactionClipper(isFromMe: messageIsFromMe),
              child: Obx(() {
                final isSending = reactionController?.messageState?.isSending.value ?? false;
                return Container(
                    width: iosSize,
                    height: iosSize,
                    color: reactionIsFromMe
                        ? context.theme.colorScheme.primary.darkenAmount(isSending ? 0.2 : 0)
                        : context.theme.colorScheme.properSurface,
                    alignment: messageIsFromMe ? Alignment.topRight : Alignment.topLeft,
                    child: SizedBox(
                      width: iosSize * 0.8,
                      height: iosSize * 0.8,
                      child: Center(
                          child: Padding(
                        padding:
                            const EdgeInsets.all(6.5).add(EdgeInsets.only(right: reactionType == "emphasize" ? 1 : 0)),
                        child: SvgPicture.asset(
                          'assets/reactions/$reactionType-black.svg',
                          colorFilter: ColorFilter.mode(
                              reactionType == "love"
                                  ? Colors.pink
                                  : (reactionIsFromMe
                                      ? context.theme.colorScheme.onPrimary
                                      : context.theme.colorScheme.properOnSurface),
                              BlendMode.srcIn),
                        ),
                      )),
                    ));
              })),
          Positioned(
            left: !messageIsFromMe ? 0 : -75,
            right: messageIsFromMe ? 0 : -75,
            child: Obx(() {
              final hasError = reactionController?.messageState?.hasError.value ?? false;
              if (reaction.error > 0 || hasError) {
                final errorCode = reaction.error;
                final errorText = ErrorHelper.getErrorText(errorCode, reaction.guid);

                return DeferPointer(
                  child: GestureDetector(
                    child: Icon(
                      SettingsSvc.settings.skin.value == Skins.iOS
                          ? CupertinoIcons.exclamationmark_circle
                          : Icons.error_outline,
                      color: context.theme.colorScheme.error,
                    ),
                    onTap: () {
                      final chat = ChatsSvc.activeChat!.chat;
                      final selected =
                          MessagesSvc(chat.guid).getControllerIfExists(reaction.associatedMessageGuid!)!.message;

                      showDialog(
                        context: context,
                        builder: (BuildContext context) => MessageErrorDialog(
                          errorCode: errorCode,
                          errorText: errorText,
                          chatId: chat.id!,
                          onRetry: () => retryReaction(
                            reaction: reaction,
                            chat: chat,
                            selected: selected,
                          ),
                          onRemove: () => removeReaction(
                            reaction: reaction,
                            chat: chat,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }
              return const SizedBox.shrink();
            }),
          )
        ],
      );
    }); // Close outer Obx
  }
}
