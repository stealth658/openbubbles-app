import 'dart:math';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/typing/typing_indicator.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/conversation_list/dialogs/conversation_peek_view.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/pinned_tile_text_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class PinnedConversationTile extends CustomStateful<ConversationTileController> {
  PinnedConversationTile({
    super.key,
    required Chat chat,
    required ConversationListController controller,
  }) : super(
            parentController: Get.isRegistered<ConversationTileController>(tag: chat.guid)
                ? Get.find<ConversationTileController>(tag: chat.guid)
                : Get.put(
                    ConversationTileController(
                      chat: chat,
                      listController: controller,
                    ),
                    tag: "${chat.guid}-pinned"));

  @override
  State<PinnedConversationTile> createState() => _PinnedConversationTileState();
}

class _PinnedConversationTileState extends CustomState<PinnedConversationTile, void, ConversationTileController> {
  ConversationListController get listController => controller.listController;
  Offset? longPressPosition;

  @override
  void initState() {
    super.initState();

    tag = "${controller.chat.guid}-pinned";
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;

    if (kIsDesktop || kIsWeb) {
      controller.shouldHighlight.value = ChatsSvc.activeChat?.chat.guid == controller.chat.guid;
    }

    EventDispatcherSvc.stream.listen((event) {
      if (event.item1 == 'update-highlight' && mounted) {
        if ((kIsDesktop || kIsWeb) && event.item2 == controller.chat.guid) {
          controller.shouldHighlight.value = true;
        } else if (controller.shouldHighlight.value) {
          controller.shouldHighlight.value = false;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4, right: 4, top: 1, bottom: 3),
      child: MouseRegion(
        onEnter: (event) => controller.hoverHighlight.value = true,
        onExit: (event) => controller.hoverHighlight.value = false,
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (details) {
            longPressPosition = details.globalPosition;
          },
          onTap: () => controller.onTap(context),
          onLongPress: kIsDesktop || kIsWeb
              ? null
              : () async {
                  await peekChat(context, controller.chat, longPressPosition ?? Offset.zero);
                },
          onSecondaryTapUp: (details) => controller.onSecondaryTap(context, details),
          child: Obx(() {
            NavigationSvc.listener.value;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(
                top: 4,
                left: 11,
                right: 11,
                bottom: 2,
              ),
              decoration: BoxDecoration(
                color: controller.shouldPartialHighlight.value
                    ? context.theme.colorScheme.properSurface.lightenOrDarken(10)
                    : controller.shouldHighlight.value
                        ? context.theme.colorScheme.bubble(context, controller.chat.isIMessage)
                        : controller.hoverHighlight.value
                            ? context.theme.colorScheme.properSurface
                            : null,
                borderRadius: BorderRadius.circular(controller.shouldHighlight.value ||
                        controller.shouldPartialHighlight.value ||
                        controller.hoverHighlight.value
                    ? 8
                    : 0),
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // Great math right here
                  final availableWidth = constraints.maxWidth;
                  final colCount = kIsDesktop
                      ? SettingsSvc.settings.pinColumnsLandscape.value
                      : SettingsSvc.settings.pinColumnsPortrait.value;
                  final spaceBetween = (colCount - 1) * 30;
                  final maxWidth = max(((availableWidth - spaceBetween) / colCount).floorToDouble(), 0).toDouble();

                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: <Widget>[
                        Column(
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                ContactAvatarGroupWidget(
                                  chat: controller.chat,
                                  size: maxWidth,
                                  editable: false,
                                ),
                                UnreadIcon(width: maxWidth, parentController: controller),
                                MuteIcon(width: maxWidth, parentController: controller),
                                PinnedIndicators(width: maxWidth, controller: controller),
                              ],
                            ),
                            ChatTitle(width: maxWidth, parentController: controller),
                          ],
                        ),
                        ReactionIcon(width: maxWidth, parentController: controller),
                        Positioned(
                          bottom: context.textTheme.bodyMedium!.fontSize! * 3,
                          width: maxWidth,
                          child: PinnedTileTextBubble(
                            chat: controller.chat,
                            size: maxWidth,
                            parentController: controller,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}

class UnreadIcon extends CustomStateful<ConversationTileController> {
  const UnreadIcon({super.key, required this.width, required super.parentController});

  final double width;

  @override
  State<StatefulWidget> createState() => _UnreadIconState();
}

class _UnreadIconState extends CustomState<UnreadIcon, void, ConversationTileController> {
  @override
  void initState() {
    super.initState();
    tag = "${controller.chat.guid}-pinned";
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = ChatsSvc.getChatState(controller.chat.guid)?.hasUnreadMessage.value ?? false;
      return unread
          ? Positioned(
              left: sqrt(widget.width) - widget.width * 0.05 * sqrt(2),
              top: sqrt(widget.width) - widget.width * 0.05 * sqrt(2),
              child: Container(
                width: widget.width * 0.2,
                height: widget.width * 0.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.theme.colorScheme.primary,
                ),
                margin: const EdgeInsets.only(right: 3),
              ),
            )
          : const SizedBox.shrink();
    });
  }
}

class MuteIcon extends CustomStateful<ConversationTileController> {
  const MuteIcon({super.key, required this.width, required super.parentController});

  final double width;

  @override
  State<StatefulWidget> createState() => _MuteIconState();
}

class _MuteIconState extends CustomState<MuteIcon, void, ConversationTileController> {
  @override
  void initState() {
    super.initState();
    tag = "${controller.chat.guid}-pinned";
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final muteType = controller.chat.muteType;
      final unread = ChatsSvc.getChatState(controller.chat.guid)?.hasUnreadMessage.value ?? false;

      return muteType == "mute"
          ? Positioned(
              left: sqrt(widget.width) - widget.width * 0.05 * sqrt(2),
              top: sqrt(widget.width) - widget.width * 0.05 * sqrt(2),
              child: Container(
                width: widget.width * 0.2,
                height: widget.width * 0.2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      unread ? context.theme.colorScheme.primaryContainer : context.theme.colorScheme.tertiaryContainer,
                ),
                child: Icon(
                  CupertinoIcons.bell_slash_fill,
                  size: widget.width * 0.14,
                  color: unread
                      ? context.theme.colorScheme.onPrimaryContainer
                      : context.theme.colorScheme.onTertiaryContainer,
                ),
              ),
            )
          : const SizedBox.shrink();
    });
  }
}

class ChatTitle extends CustomStateful<ConversationTileController> {
  final double width;

  const ChatTitle({super.key, required this.width, required super.parentController});

  @override
  State<StatefulWidget> createState() => _ChatTitleState();
}

class _ChatTitleState extends CustomState<ChatTitle, void, ConversationTileController> {
  @override
  void initState() {
    super.initState();
    tag = "${controller.chat.guid}-pinned";
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: widget.width * 0.075,
      ),
      child: Obx(() {
        final isPinned = controller.chatState?.isPinned.value ?? controller.chat.isPinned ?? false;
        final style = context.theme.textTheme.bodyMedium!.apply(
          color: controller.shouldHighlight.value
              ? context.theme.colorScheme.onBubble(context, controller.chat.isIMessage)
              : context.theme.colorScheme.outline,
          fontSizeFactor: isPinned ? 0.95 : 1,
        );

        // Get title from ChatState - it handles all title logic including redacted mode
        final chatState = ChatsSvc.getChatState(controller.chat.guid);
        final _title = chatState?.title.value ?? controller.chat.getTitle();

        return SizedBox(
          height: style.height! * style.fontSize! * 2,
          child: OverflowBox(
            maxWidth: widget.width + 16,
            child: Align(
              alignment: Alignment.center,
              child: RichText(
                text: TextSpan(
                  children: MessageHelper.buildEmojiText(
                    _title,
                    style,
                  ),
                  style: style,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class PinnedIndicators extends StatelessWidget {
  final ConversationTileController controller;
  final double width;

  const PinnedIndicators({super.key, required this.width, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final showTypingIndicator = cvc(controller.chat).showTypingIndicator.value;
      if (showTypingIndicator) {
        return Positioned(
          top: -sqrt(width / 2) + width * 0.05,
          right: -sqrt(width / 2) + width * 0.025,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: width / 3),
            child: const FittedBox(
              child: TypingIndicator(visible: true),
            ),
          ),
        );
      }

      final showMarker = controller.chat.latestMessage.indicatorToShow;
      if (SettingsSvc.settings.statusIndicatorsOnChats.value &&
          !controller.chat.isGroup &&
          showMarker != Indicator.NONE) {
        return Positioned(
          left: sqrt(width) - width * 0.05 * sqrt(2),
          top: width - width * 0.13 * 2,
          child: Container(
            width: width * 0.27,
            height: width * 0.27,
            decoration: BoxDecoration(
              border: Border.all(color: context.theme.colorScheme.background, width: 1),
              borderRadius: BorderRadius.circular(30),
              color: context.theme.colorScheme.tertiaryContainer,
            ),
            child: Transform.rotate(
              angle: showMarker != Indicator.SENT ? pi / 2 : 0,
              child: Icon(
                showMarker == Indicator.DELIVERED
                    ? CupertinoIcons.location_north_fill
                    : showMarker == Indicator.READ
                        ? CupertinoIcons.location_north
                        : CupertinoIcons.location_fill,
                color: context.theme.colorScheme.onTertiaryContainer,
                size: width * 0.14,
              ),
            ),
          ),
        );
      }

      return const SizedBox.shrink();
    });
  }
}

class ReactionIcon extends CustomStateful<ConversationTileController> {
  const ReactionIcon({super.key, required this.width, required super.parentController});

  final double width;

  @override
  State<StatefulWidget> createState() => _ReactionIconState();
}

class _ReactionIconState extends CustomState<ReactionIcon, void, ConversationTileController> {
  @override
  void initState() {
    super.initState();
    tag = "${controller.chat.guid}-pinned";
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final unread = ChatsSvc.getChatState(controller.chat.guid)?.hasUnreadMessage.value ?? false;
      final latestMsg = controller.chat.latestMessage;
      final isReaction = !isNullOrEmpty(latestMsg.associatedMessageGuid);
      // Null-safe isFromMe: treat null as "from me" so we don't show the icon
      // for messages with unknown sender, mirroring the text-bubble behaviour.
      final isNotFromMe = latestMsg.isFromMe == false;

      return unread && isReaction && isNotFromMe
          ? Positioned(
              top: -sqrt(widget.width / 2) + widget.width * 0.05,
              right: -sqrt(widget.width / 2) + widget.width * 0.025,
              child: ReactionWidget(
                reaction: latestMsg,
                message: null,
                // Pass the chat GUID explicitly so ReactionWidget can locate the
                // correct MessagesService instead of falling back to activeChat.
                chatGuid: controller.chat.guid,
              ),
            )
          : const SizedBox.shrink();
    });
  }
}
