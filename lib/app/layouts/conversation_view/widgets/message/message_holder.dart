import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/chat_event/chat_event.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_indicators.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_reactions.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_timestamps.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_wrappers.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_reactions.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/reply_bubble_section.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/bubble_effects.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/message_edit_field.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/message_part_content.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/message_properties.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/message_sender.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/select_checkbox.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/slide_to_reply.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/swipe_to_reply_wrapper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/tail_clipper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_line_painter.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/text/text_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/message_timestamp.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/timestamp_separator.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MessageHolder extends CustomStateful<MessageWidgetController> {
  MessageHolder({
    super.key,
    required this.cvController,
    this.oldMessageGuid,
    this.newMessageGuid,
    required this.message,
    this.isReplyThread = false,
    this.replyPart,
  }) : super(parentController: getActiveMwc(message.guid!) ?? mwc(message));

  final Message message;
  final String? oldMessageGuid;
  final String? newMessageGuid;
  final ConversationViewController cvController;
  final bool isReplyThread;
  final int? replyPart;

  @override
  CustomState createState() => _MessageHolderState();
}

class _MessageHolderState extends CustomState<MessageHolder, void, MessageWidgetController> {
  Message get message => controller.message;

  Message? get olderMessage => controller.oldMessage;

  Message? get newerMessage => controller.newMessage;

  // Computed reactive replyTo getter
  Message? get replyTo => message.threadOriginatorGuid == null
      ? null
      : SettingsSvc.settings.repliesToPrevious.value
          ? (service.struct
                  .getPreviousReply(message.threadOriginatorGuid!, message.normalizedThreadPart, message.guid!) ??
              service.struct.getThreadOriginator(message.threadOriginatorGuid!))
          : service.struct.getThreadOriginator(message.threadOriginatorGuid!);

  Chat get chat => widget.cvController.chat;

  MessagesService get service => MessagesSvc(widget.cvController.chat.guid);

  // Computed reactive properties
  bool get showSender =>
      !message.isGroupEvent &&
      (!message.sameSender(olderMessage) ||
          (olderMessage?.isGroupEvent ?? false) ||
          (olderMessage == null || !message.dateCreated!.isWithin(olderMessage!.dateCreated!, minutes: 30)));

  bool get canSwipeToReply =>
      SettingsSvc.settings.enablePrivateAPI.value &&
      SettingsSvc.isMinBigSurSync &&
      chat.isIMessage &&
      !widget.isReplyThread &&
      !(controller.messageState?.guid.value?.startsWith("temp") ?? message.guid!.startsWith("temp")) &&
      !(controller.messageState?.guid.value?.startsWith("error") ?? message.guid!.startsWith("error"));

  bool get showAvatar => chat.isGroup;

  bool isEditing(int part) =>
      message.isFromMe! &&
      widget.cvController.editing.firstWhereOrNull((e2) => e2.item1.guid == message.guid! && e2.item2.part == part) !=
          null;

  List<MessagePart> messageParts = [];
  List<RxDouble> replyOffsets = [];
  List<GlobalKey> keys = [];
  final RxBool tapped = false.obs;

  @override
  void initState() {
    forceDelete = false;
    super.initState();
    if (widget.isReplyThread) {
      if (widget.replyPart != null) {
        messageParts = [controller.parts[widget.replyPart!]];
      } else {
        messageParts = controller.parts;
      }
    } else {
      controller.cvController = widget.cvController;
      controller.oldMessageGuid = widget.oldMessageGuid;
      controller.newMessageGuid = widget.newMessageGuid;
      messageParts = controller.parts;
      replyOffsets = List.generate(messageParts.length, (_) => 0.0.obs);
      keys = List.generate(messageParts.length, (_) => GlobalKey());
    }
  }

  @override
  void updateWidget(void _) {
    messageParts = controller.parts;
    super.updateWidget(_);
  }

  void completeEdit(String newEdit, int part) async {
    widget.cvController.editing.removeWhere((e2) => e2.item1.guid == message.guid! && e2.item2.part == part);
    if (newEdit.isNotEmpty && newEdit != messageParts.firstWhere((element) => element.part == part).text) {
      bool dismissed = false;
      showDialog(
        context: context,
        builder: (BuildContext context) => PopScope(
          onPopInvokedWithResult: (_, __) => dismissed = true,
          child: AlertDialog(
            backgroundColor: context.theme.colorScheme.properSurface,
            title: Text(
              "Editing message...",
              style: context.theme.textTheme.titleLarge,
            ),
            content: SizedBox(
              height: 70,
              child: Center(
                child: CircularProgressIndicator(
                  backgroundColor: context.theme.colorScheme.properSurface,
                  valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                ),
              ),
            ),
          ),
        ),
      );
      final response = await HttpSvc.edit(message.guid!, newEdit, "Edited to: “$newEdit”", partIndex: part);
      if (response.statusCode == 200) {
        final updatedMessage = Message.fromMap(response.data['data']);
        MessageHandlerSvc.handleUpdatedMessage(chat, updatedMessage, null);
      }
      if (!dismissed) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    widget.cvController.lastFocusedNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    controller.built = true;

    // Cache associated messages filtering
    final stickers = message.associatedMessages.where((e) => e.associatedMessageType == "sticker").toList();

    // Helper to get reactions - MUST be called inside Obx() to be reactive
    List<Message> getReactions() {
      return message.associatedMessages
          .where((e) => ReactionTypes.toList().contains(e.associatedMessageType?.replaceAll("-", "")))
          .toList();
    }

    // Cache settings values to avoid repeated observable reads
    final alwaysShowAvatars = SettingsSvc.settings.alwaysShowAvatars.value;
    final avatarScale = SettingsSvc.settings.avatarScale.value;

    Iterable<Message> reactionsForPart(int part, List<Message> reactions) {
      return reactions.where((s) => (s.associatedMessagePart ?? 0) == part);
    }

    /// Layout tree
    /// - Timestamp
    /// - Stack (see code comment)
    ///    - avatar | message row
    ///                - spacing (for avatar) | message column | message timestamp
    ///                                          - message part column
    ///                                             - message sender
    ///                                             - reaction spacing box
    ///                                             - previous edits
    ///                                             - message content row
    ///                                                - text / attachment / chat event / interactive | slide to reply
    ///                                                   |-> stack: stickers & reactions
    ///                                             - message properties
    ///                                          - delivered indicator
    // Item Type 5 indicates a kept audio message, we don't need to show this
    if (message.itemType == 5 && message.subject != null) {
      return const SizedBox.shrink();
    }
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: message.guid!.contains("temp")
          ? EdgeInsets.zero
          : EdgeInsets.only(
              top: olderMessage != null && !message.sameSender(olderMessage!) ? 5.0 : 0,
              bottom: newerMessage != null && !message.sameSender(newerMessage!) ? 5.0 : 0,
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // large timestamp between messages
          TimestampSeparator(olderMessage: olderMessage, message: message),
          // use stack so avatar can be placed at bottom
          Row(
            children: [
              if (!message.isFromMe! && !message.isGroupEvent)
                SelectCheckbox(message: message, controller: widget.cvController),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // message column
                    ...messageParts.mapIndexed((index, e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              // add previous edits if needed
                              if (e.isEdited)
                                EditHistoryObserver(
                                  controller: controller,
                                  message: message,
                                  part: e,
                                  newerMessage: newerMessage,
                                  showAvatar: showAvatar,
                                  alwaysShowAvatars: alwaysShowAvatars,
                                  avatarScale: avatarScale,
                                ),
                              if (iOS &&
                                  index == 0 &&
                                  !widget.isReplyThread &&
                                  olderMessage != null &&
                                  message.threadOriginatorGuid != null &&
                                  message.showUpperMessage(olderMessage!) &&
                                  replyTo != null &&
                                  getActiveMwc(replyTo!.guid!) != null)
                                Padding(
                                  padding: EdgeInsets.only(
                                      left: (showAvatar || alwaysShowAvatars) && replyTo!.isFromMe! ? 35 : 0),
                                  child: DecoratedBox(
                                    decoration: replyTo!.isFromMe == message.isFromMe
                                        ? ReplyLineDecoration(
                                            isFromMe: message.isFromMe!,
                                            color: context.theme.colorScheme.properSurface,
                                            connectUpper: false,
                                            connectLower: true,
                                            context: context,
                                          )
                                        : const BoxDecoration(),
                                    child: ReplyBubbleSection(
                                      replyTo: replyTo!,
                                      message: message,
                                      chat: chat,
                                      cvController: widget.cvController,
                                      showAvatar: showAvatar,
                                      alwaysShowAvatars: alwaysShowAvatars,
                                      avatarScale: avatarScale,
                                      isIOS: true,
                                      isFirstPart: true,
                                    ),
                                  ),
                                ),
                              // show sender, if needed
                              if (chat.isGroup &&
                                  !message.isFromMe! &&
                                  showSender &&
                                  e.part == (messageParts.firstWhereOrNull((e) => !e.isUnsent)?.part))
                                Padding(
                                  padding: showAvatar || alwaysShowAvatars
                                      ? EdgeInsets.only(left: 35.0 * avatarScale)
                                      : EdgeInsets.zero,
                                  child: MessageSender(olderMessage: olderMessage, message: message),
                                ),
                              // add a box to account for height of reactions
                              ReactionSpacing(
                                controller: controller,
                                messageParts: messageParts,
                                part: e,
                                getReactions: getReactions,
                                reactionsForPart: reactionsForPart,
                              ),
                              if (!iOS &&
                                  index == 0 &&
                                  !widget.isReplyThread &&
                                  olderMessage != null &&
                                  message.threadOriginatorGuid != null &&
                                  replyTo != null &&
                                  getActiveMwc(replyTo!.guid!) != null)
                                ReplyBubbleSection(
                                  replyTo: replyTo!,
                                  message: message,
                                  chat: chat,
                                  cvController: widget.cvController,
                                  showAvatar: showAvatar,
                                  alwaysShowAvatars: alwaysShowAvatars,
                                  avatarScale: avatarScale,
                                  isIOS: false,
                                  isFirstPart: true,
                                ),
                              Stack(
                                alignment: Alignment.bottomLeft,
                                children: [
                                  // avatar, if needed
                                  if (message.showTail(newerMessage) &&
                                      e.part == controller.parts.length - 1 &&
                                      (showAvatar || SettingsSvc.settings.alwaysShowAvatars.value) &&
                                      !message.isFromMe! &&
                                      !message.isGroupEvent)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 5.0),
                                      child: ContactAvatarWidget(
                                        handle: message.handleRelation.target,
                                        size: iOS ? 30 : 35,
                                        fontSize: context.theme.textTheme.bodyLarge!.fontSize!,
                                        borderThickness: 0.1,
                                      ),
                                    ),
                                  Padding(
                                    padding: (showAvatar || alwaysShowAvatars) && !(message.isGroupEvent || e.isUnsent)
                                        ? EdgeInsets.only(left: 35.0 * avatarScale)
                                        : EdgeInsets.zero,
                                    child: DecoratedBox(
                                      decoration: iOS &&
                                              !widget.isReplyThread &&
                                              ((index == 0 &&
                                                      message.threadOriginatorGuid != null &&
                                                      olderMessage != null) ||
                                                  (index == messageParts.length - 1 &&
                                                      service.struct.threads(message.guid!, index).isNotEmpty &&
                                                      newerMessage != null))
                                          ? ReplyLineDecoration(
                                              isFromMe: message.isFromMe!,
                                              color: context.theme.colorScheme.properSurface,
                                              connectUpper: message.connectToUpper(),
                                              connectLower:
                                                  newerMessage != null && message.connectToLower(newerMessage!),
                                              context: context,
                                            )
                                          : const BoxDecoration(),
                                      child: SelectModeWrapper(
                                        cvController: widget.cvController,
                                        message: message,
                                        tapped: tapped,
                                        child: Align(
                                          alignment: message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // show group event
                                              if (message.isGroupEvent || e.isUnsent)
                                                ChatEvent(
                                                  part: e,
                                                  message: message,
                                                ),
                                              if (samsung)
                                                SamsungTimestampObserver(
                                                  controller: controller,
                                                  message: message,
                                                  messageParts: messageParts,
                                                  part: e,
                                                  cvController: widget.cvController,
                                                  getReactions: getReactions,
                                                  reactionsForPart: reactionsForPart,
                                                ),
                                              // otherwise show content
                                              if (!message.isGroupEvent && !e.isUnsent)
                                                Column(
                                                  crossAxisAlignment: message.isFromMe!
                                                      ? CrossAxisAlignment.end
                                                      : CrossAxisAlignment.start,
                                                  children: [
                                                    // interactive messages may have subjects, so render them here
                                                    // also render the subject for attachments that may have not rendered already
                                                    if ((message.hasApplePayloadData ||
                                                            message.isLegacyUrlPreview ||
                                                            message.isInteractive ||
                                                            (e.part == 0 &&
                                                                isNullOrEmpty(e.text) &&
                                                                e.attachments.isNotEmpty)) &&
                                                        !isNullOrEmpty(message.subject))
                                                      Padding(
                                                        padding: const EdgeInsets.only(bottom: 2.0),
                                                        child: ClipPath(
                                                          clipper: TailClipper(
                                                            isFromMe: message.isFromMe!,
                                                            showTail: false,
                                                            connectLower: iOS
                                                                ? false
                                                                : (e.part != 0 &&
                                                                        e.part != controller.parts.length - 1) ||
                                                                    (e.part == 0 && controller.parts.length > 1),
                                                            connectUpper: iOS ? false : e.part != 0,
                                                          ),
                                                          child: TextBubble(
                                                            parentController: controller,
                                                            message: MessagePart(
                                                              subject: e.subject,
                                                              part: e.part,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    Stack(
                                                      alignment: Alignment.center,
                                                      fit: StackFit.loose,
                                                      clipBehavior: Clip.none,
                                                      children: [
                                                        // actual message content
                                                        BubbleEffects(
                                                          message: message,
                                                          part: index,
                                                          globalKey: keys.length > index ? keys[index] : null,
                                                          showTail: message.showTail(newerMessage) &&
                                                              e.part == controller.parts.length - 1,
                                                          child: MessagePopupHolder(
                                                            key: keys.length > index ? keys[index] : null,
                                                            controller: controller,
                                                            cvController: widget.cvController,
                                                            part: e,
                                                            isEditing: isEditing(e.part),
                                                            child: SwipeToReplyWrapper(
                                                              enabled: canSwipeToReply && !isEditing(e.part),
                                                              message: message,
                                                              partIndex: index,
                                                              replyOffset: replyOffsets[index],
                                                              cvController: widget.cvController,
                                                              child: ClipPath(
                                                                clipper: TailClipper(
                                                                  isFromMe: message.isFromMe!,
                                                                  showTail: message.showTail(newerMessage) &&
                                                                      e.part == controller.parts.length - 1,
                                                                  connectLower: iOS
                                                                      ? false
                                                                      : (e.part != 0 &&
                                                                              e.part != controller.parts.length - 1) ||
                                                                          (e.part == 0 && controller.parts.length > 1),
                                                                  connectUpper: iOS ? false : e.part != 0,
                                                                ),
                                                                child: Stack(
                                                                  alignment: Alignment.centerRight,
                                                                  children: [
                                                                    MessagePartContent(
                                                                      parentController: controller,
                                                                      message: message,
                                                                      messagePart: e,
                                                                    ),
                                                                    if (message.isFromMe!)
                                                                      Obx(() {
                                                                        final editStuff = widget.cvController.editing
                                                                            .firstWhereOrNull((e2) =>
                                                                                e2.item1.guid == message.guid! &&
                                                                                e2.item2.part == e.part);
                                                                        return AnimatedSize(
                                                                            duration: const Duration(milliseconds: 250),
                                                                            alignment: Alignment.centerRight,
                                                                            curve: Curves.easeOutBack,
                                                                            child: editStuff == null
                                                                                ? const SizedBox.shrink()
                                                                                : MessageEditField(
                                                                                    message: message,
                                                                                    part: e.part,
                                                                                    editController: editStuff.item3,
                                                                                    cvController: widget.cvController,
                                                                                    onComplete: completeEdit,
                                                                                  ));
                                                                      }),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        // show stickers on top
                                                        StickerObserver(
                                                          messageParts: messageParts,
                                                          stickers: stickers,
                                                          part: e,
                                                          cvController: widget.cvController,
                                                        ),
                                                        // show reactions on top
                                                        MessageReactions(
                                                          controller: controller,
                                                          message: message,
                                                          messageParts: messageParts,
                                                          part: e,
                                                          chatGuid: chat.guid,
                                                          getReactions: getReactions,
                                                          reactionsForPart: reactionsForPart,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              // swipe to reply
                                              if (canSwipeToReply &&
                                                  !message.isGroupEvent &&
                                                  !e.isUnsent &&
                                                  !widget.isReplyThread &&
                                                  index < replyOffsets.length)
                                                Obx(() => SlideToReply(
                                                    width: replyOffsets[index].value.abs(),
                                                    isFromMe: message.isFromMe!)),
                                            ].conditionalReverse(message.isFromMe!),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // message properties (replies, edits, effect)
                              Padding(
                                padding: showAvatar || alwaysShowAvatars
                                    ? EdgeInsets.only(left: 35.0 * avatarScale)
                                    : EdgeInsets.zero,
                                child: MessageProperties(
                                    globalKey: keys.length > index ? keys[index] : null,
                                    parentController: controller,
                                    part: e),
                              ),
                            ],
                          ),
                        )),
                    // delivered / read receipt
                    DeliveredIndicatorObserver(controller: controller, tapped: tapped),
                  ],
                ),
              ),
              if (message.isFromMe! && !message.isGroupEvent)
                SelectCheckbox(message: message, controller: widget.cvController),
              ErrorIndicatorObserver(controller: controller, message: message, chat: chat, service: service),
              // slide to view timestamp
              if (iOS) MessageTimestamp(controller: controller, cvController: widget.cvController),
            ],
          ),
        ],
      ),
    );
  }
}
