import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/chat_event/chat_event.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_indicators.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_reactions.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_timestamps.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_holder_wrappers.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/message_reactions.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder/reply_bubble_section.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
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
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/text/text_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/message_timestamp.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/timestamp_separator.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/backend/incoming_message_handler.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:collection/collection.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

class MessageHolder extends StatefulWidget {
  MessageHolder({
    super.key,
    required this.cvController,
    this.oldMessage,
    this.newMessage,
    required this.message,
    this.isReplyThread = false,
    this.replyPart,
  }) : ms = MessagesSvc(cvController.chat.guid).getOrCreateState(message);

  final MessageState ms;
  final Message message;
  final Message? oldMessage;
  final Message? newMessage;
  final ConversationViewController cvController;
  final bool isReplyThread;
  final int? replyPart;

  @override
  State<StatefulWidget> createState() => _MessageHolderState();
}

class _MessageHolderState extends State<MessageHolder> with AutomaticKeepAliveClientMixin, ThemeHelpers {
  @override
  bool get wantKeepAlive => true;

  MessageState get controller => widget.ms;

  Message get message => controller.message;

  // In the reply-thread view the neighbours are the thread's, passed in by the
  // popup; the message state still holds its main-list neighbours, which made
  // time headers, sender names and spacing in the thread follow the wrong
  // messages (no "Today 9:31 PM" header above an original from hours earlier).
  Message? get olderMessage => widget.isReplyThread ? widget.oldMessage : controller.oldMessage;

  Message? get newerMessage => widget.isReplyThread ? widget.newMessage : controller.newMessage;

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
      SettingsSvc.serverDetails.isMinBigSur &&
      chat.isIMessage &&
      !widget.isReplyThread &&
      !controller.isSending.value &&
      !controller.hasError.value;

  bool get showAvatar => chat.isGroup;

  bool isEditing(int part) =>
      message.isFromMe! &&
      widget.cvController.editing.firstWhereOrNull((e2) => e2.message.guid == message.guid! && e2.part.part == part) !=
          null;

  List<RxDouble> replyOffsets = [];
  List<GlobalKey> keys = [];
  final RxBool tapped = false.obs;
  final Map<int, ValueNotifier<int>> _galleryIndices = {};

  @override
  void dispose() {
    for (final notifier in _galleryIndices.values) {
      notifier.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.isReplyThread) {
      replyOffsets = List.generate(widget.replyPart != null ? 1 : controller.parts.length, (_) => 0.0.obs);
      keys = List.generate(widget.replyPart != null ? 1 : controller.parts.length, (_) => GlobalKey());
    } else {
      controller.cvController = widget.cvController;
      controller.oldMessage = widget.oldMessage;
      controller.newMessage = widget.newMessage;
      replyOffsets = List.generate(controller.parts.length, (_) => 0.0.obs);
      keys = List.generate(controller.parts.length, (_) => GlobalKey());
    }
  }

  @override
  void didUpdateWidget(MessageHolder old) {
    super.didUpdateWidget(old);
    if (!widget.isReplyThread) {
      controller.oldMessage = widget.oldMessage;
      controller.newMessage = widget.newMessage;
    }
  }

  void completeEdit(String newEdit, int part) async {
    // Grab the entry before removing it - OpenBubbles needs its controller to
    // rebuild the full attributed body (so mentions survive an edit).
    final entry =
        widget.cvController.editing.firstWhereOrNull((e2) => e2.message.guid == message.guid! && e2.part.part == part);
    widget.cvController.editing.removeWhere((e2) => e2.message.guid == message.guid! && e2.part.part == part);
    if (newEdit.isNotEmpty && newEdit != controller.parts.firstWhere((element) => element.part == part).text) {
      // Edits must go through the backend abstraction so rustpush handles them
      // natively rather than hitting the BlueBubbles server.
      final editController = entry?.controller;
      final body = editController is MentionTextEditingController
          ? editController.getFinalAnnotations()
          : AttributedBody.raw(newEdit);
      final updated = await backend.edit(message, body, part);
      if (updated != null) {
        IncomingMsgHandler.handle(IncomingPayload(
          type: MessageEventType.updatedMessage,
          source: MessageSource.apiResponse,
          chat: chat,
          message: updated,
        ));
      }
    }
    widget.cvController.lastFocusedNode.requestFocus();
  }

  List<MessagePart> _collapseImageGalleryParts(List<MessagePart> parts) {
    if (!iOS) return parts;
    final collapsed = <MessagePart>[];
    int i = 0;
    while (i < parts.length) {
      final current = parts[i];
      if (!current.isMediaOnlyPart) {
        collapsed.add(current);
        i++;
        continue;
      }

      final groupedAttachments = <Attachment>[...current.attachments];
      final groupedPartIndices = <int>[...List.filled(current.attachments.length, current.part)];
      int lastPart = current.part;
      int j = i + 1;
      while (j < parts.length) {
        final next = parts[j];
        if (!next.isMediaOnlyPart) break;
        groupedAttachments.addAll(next.attachments);
        groupedPartIndices.addAll(List.filled(next.attachments.length, next.part));
        lastPart = next.part;
        j++;
      }

      if (groupedAttachments.length > 1) {
        collapsed.add(MessagePart(
          attachments: groupedAttachments,
          // Use the last grouped raw part index (not the first) so downstream
          // "is this the last part of the message" checks (e.g. avatar, tail)
          // still resolve correctly against controller.parts.length.
          part: lastPart,
          shouldRedact: current.shouldRedact,
          annotations: const [],
          edits: const [],
          isUnsent: current.isUnsent,
          attachmentPartIndices: groupedPartIndices,
        ));
      } else {
        collapsed.add(current);
      }
      i = j;
    }
    return collapsed;
  }


  /// Google Messages style: the replied-to message as a lighter card at the
  /// top of this bubble, author and one-line excerpt, tap to jump to it.
  Widget _withReplyCard(BuildContext context, Widget inner, MessagePart part) {
    final original = replyTo!;
    final scheme = context.theme.colorScheme;
    final bubbleExt = context.theme.extensions[BubbleColors] as BubbleColors?;
    final bubbleColor = message.isFromMe!
        ? scheme.bubble(context, chat.isIMessage)
        : (bubbleExt?.receivedBubbleColor ?? scheme.surfaceContainerHighest);
    final author = original.isFromMe == true
        ? "You"
        : (original.handleRelation.target?.displayName ?? original.handle?.displayName ?? "");
    final excerpt = original.getNotificationText(hideMessageContent: false);
    // An image original gets a small thumbnail beside the text, as in
    // Google Messages.
    final imageAtt = original.dbAttachments.firstWhereOrNull((a) => a.mimeStart == "image" && a.existsOnDisk);
    final Widget? thumb = imageAtt == null
        ? null
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image(
              image: ResizeImage(FileImage(File(imageAtt.path)), width: 240),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          );
    final card = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Material(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => service.jumpToMessage.call(original.guid!),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (thumb != null) ...[thumb, const SizedBox(width: 14)],
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (author.isNotEmpty)
                        Text(author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurface)),
                      Text(excerpt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // IntrinsicWidth: the bubble is as wide as the wider of the card and the
    // reply text, and the card stretches to that; the text sits at the left
    // like Google's, instead of floating right in a max-width bubble.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: NavigationSvc.width(context) * MessageState.maxBubbleSizeFactor),
      child: IntrinsicWidth(
        child: Container(
          color: bubbleColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [card, Align(alignment: Alignment.centerLeft, child: inner)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    controller.built = true;

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
    // OpenBubbles: only the newest item of an iMessage-app session renders;
    // superseded updates in the same session are hidden entirely.
    if ((message.hasApplePayloadData || message.isLegacyUrlPreview || message.isInteractive) &&
        message.amkSessionId != null &&
        !es.getLatest(message.amkSessionId!).contains(message.stagingGuid ?? message.guid)) {
      return const SizedBox.shrink();
    }
    final messageState = controller;
    return MessageStateScope(
      messageState: messageState,
      child: Obx(() {
        // Ensure this Obx always has direct reactive dependencies from MessageState.
        // Some render paths can avoid touching other Rx fields.
        // ignore: unused_local_variable
        final _rxGuard = (controller.isSending.value, controller.hasError.value, controller.parts.length);

        // Read controller.parts reactively so Obx rebuilds when parts change
        final rawMessageParts = widget.isReplyThread && widget.replyPart != null
            ? [controller.parts[widget.replyPart!]]
            : controller.parts.toList();
        final messageParts = _collapseImageGalleryParts(rawMessageParts);

        // Grow per-part arrays so replyOffsets[index] and keys[index] are
        // always safe to access, even when parts are added after initState.
        while (replyOffsets.length < messageParts.length) {
          replyOffsets.add(0.0.obs);
          keys.add(GlobalKey());
        }

        // Use MessageState observables for proper reactivity
        final isFromMe = controller.message.isFromMe!;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 100),
          padding: EdgeInsets.only(
            top: olderMessage != null && !message.sameSender(olderMessage!) ? 5.0 : 0,
            bottom: newerMessage != null && !message.sameSender(newerMessage!) ? 5.0 : 0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // large timestamp between messages
              TimestampSeparator(olderMessage: olderMessage),
              // use stack so avatar can be placed at bottom
              Row(
                children: [
                  if (!isFromMe && !message.isGroupEvent) SelectCheckbox(controller: widget.cvController),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        // message column
                        ...messageParts.mapIndexed((index, e) {
                          // Reply threading, drawn the same way on every skin
                          // (iMessage's layout): when the original is not right
                          // above, a quote of it with a small avatar of its
                          // author sits in the avatar column; a thin line runs
                          // down that column to this message's own avatar.
                          final isReply = index == 0 &&
                              !widget.isReplyThread &&
                              olderMessage != null &&
                              message.threadOriginatorGuid != null &&
                              replyTo != null &&
                              service.getMessageStateIfExists(replyTo!.guid!) != null;
                          // Material follows Google Messages: the reply is a card nested
                          // inside the bubble (see _replyCard), no quote or thread line;
                          // avatars sit beside the sender's name, not the bubble.
                          final googleStyle = material;
                          final showQuote = !googleStyle && isReply && message.showUpperMessage(olderMessage!);
                          final avatarsOn = showAvatar || alwaysShowAvatars;
                          final lineInColumn =
                              !googleStyle && isReply && !message.isFromMe! && !message.isGroupEvent && avatarsOn;
                          final avatarHere = message.showTail(newerMessage) && e.part == controller.parts.length - 1;
                          final bodyAvatarSize = (iOS ? 30.0 : 35.0) * avatarScale;
                          return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  // add previous edits if needed
                                  if (e.isEdited)
                                    EditHistoryObserver(
                                      part: e,
                                      newerMessage: newerMessage,
                                      showAvatar: showAvatar,
                                      alwaysShowAvatars: alwaysShowAvatars,
                                      avatarScale: avatarScale,
                                    ),
                                  if (showQuote)
                                    ReplyBubbleSection(
                                      replyTo: replyTo!,
                                      cvController: widget.cvController,
                                      showAvatar: showAvatar,
                                      alwaysShowAvatars: alwaysShowAvatars,
                                      avatarScale: avatarScale,
                                      isIOS: iOS,
                                      isFirstPart: true,
                                    ),
                                  CustomPaint(
                                    painter: lineInColumn
                                        ? _AvatarColumnLinePainter(
                                            color: replyLineColor(context),
                                            x: 5.0 + bodyAvatarSize / 2,
                                            stopAbove: avatarHere ? bodyAvatarSize + 3.0 : 0.0,
                                          )
                                        : null,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                      children: [
                                  // show sender, if needed
                                  if (chat.isGroup &&
                                      !message.isFromMe! &&
                                      showSender &&
                                      e.part == (messageParts.firstWhereOrNull((e) => !e.isUnsent)?.part))
                                    Padding(
                                      padding: !googleStyle && (showAvatar || alwaysShowAvatars)
                                          ? EdgeInsets.only(left: 35.0 * avatarScale)
                                          : EdgeInsets.zero,
                                      child: MessageSender(
                                        olderMessage: olderMessage,
                                        googleStyle: googleStyle,
                                        showAvatar: googleStyle && (showAvatar || alwaysShowAvatars),
                                      ),
                                    ),
                                  // add a box to account for height of reactions
                                  ReactionSpacing(
                                    messageParts: messageParts,
                                    part: e,
                                    reactionsForPart: reactionsForPart,
                                    minHeightWhenNoReactions: 0,
                                  ),
                                  Stack(
                                    alignment: Alignment.bottomLeft,
                                    children: [
                                      // avatar, if needed
                                      if (!googleStyle &&
                                          message.showTail(newerMessage) &&
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
                                        padding:
                                            (showAvatar || alwaysShowAvatars) && !(message.isGroupEvent || e.isUnsent)
                                                ? EdgeInsets.only(
                                                    left: 35.0 * avatarScale + (e.isMediaGallery ? 12.0 : 0.0))
                                                : EdgeInsets.zero,
                                        child: DecoratedBox(
                                          decoration: const BoxDecoration(),
                                          child: SelectModeWrapper(
                                            cvController: widget.cvController,
                                            tapped: tapped,
                                            child: Align(
                                              alignment:
                                                  message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // show group event
                                                  if (message.isGroupEvent || e.isUnsent)
                                                    ChatEvent(
                                                      part: e,
                                                    ),
                                                  if (samsung)
                                                    SamsungTimestampObserver(
                                                      messageParts: messageParts,
                                                      part: e,
                                                      cvController: widget.cvController,
                                                      reactionsForPart: reactionsForPart,
                                                    ),
                                                  // otherwise show content
                                                  if (!message.isGroupEvent && !e.isUnsent)
                                                    Column(
                                                      crossAxisAlignment:
                                                          isFromMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                                                                isFromMe: isFromMe,
                                                                showTail: false,
                                                                connectLower: iOS
                                                                    ? false
                                                                    : (e.part != 0 &&
                                                                            e.part != controller.parts.length - 1) ||
                                                                        (e.part == 0 && controller.parts.length > 1),
                                                                connectUpper: iOS ? false : e.part != 0,
                                                              ),
                                                              child: TextBubble(
                                                                message: MessagePart(
                                                                  subject: e.subject,
                                                                  part: e.part,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        Stack(
                                                          alignment:
                                                              isFromMe ? Alignment.centerRight : Alignment.centerLeft,
                                                          fit: StackFit.loose,
                                                          clipBehavior: Clip.none,
                                                          children: [
                                                            // Inner Stack: bubble + reactions, sized by the bubble alone
                                                            // so reactions are always anchored to the bubble edge
                                                            Stack(
                                                              alignment: isFromMe
                                                                  ? Alignment.centerRight
                                                                  : Alignment.centerLeft,
                                                              fit: StackFit.loose,
                                                              clipBehavior: Clip.none,
                                                              children: [
                                                                // actual message content
                                                                BubbleEffects(
                                                                  part: index,
                                                                  globalKey: keys.length > index ? keys[index] : null,
                                                                  showTail: message.showTail(newerMessage) &&
                                                                      e.part == controller.parts.length - 1,
                                                                  messageState: controller,
                                                                  child: MessagePopupHolder(
                                                                    key: keys.length > index ? keys[index] : null,
                                                                    controller: controller,
                                                                    cvController: widget.cvController,
                                                                    part: e,
                                                                    isEditing: isEditing(e.part),
                                                                    galleryCurrentIndex: e.isMediaGallery
                                                                        ? _galleryIndices.putIfAbsent(
                                                                            e.part, () => ValueNotifier(0))
                                                                        : null,
                                                                    child: SwipeToReplyWrapper(
                                                                      enabled: canSwipeToReply &&
                                                                          !isEditing(e.part) &&
                                                                          !(iOS && e.isMediaGallery),
                                                                      partIndex: index,
                                                                      replyOffset: replyOffsets[index],
                                                                      cvController: widget.cvController,
                                                                      child: Builder(
                                                                        builder: (_) {
                                                                          final isGallery = iOS && e.isMediaGallery;
                                                                          final inner = Stack(
                                                                            alignment: Alignment.centerRight,
                                                                            children: [
                                                                              MessagePartContent(
                                                                                messagePart: e,
                                                                                galleryCurrentIndexNotifier: e
                                                                                        .isMediaGallery
                                                                                    ? _galleryIndices.putIfAbsent(
                                                                                        e.part, () => ValueNotifier(0))
                                                                                    : null,
                                                                              ),
                                                                              if (message.isFromMe!)
                                                                                Obx(() {
                                                                                  final editStuff = widget
                                                                                      .cvController.editing
                                                                                      .firstWhereOrNull((e2) =>
                                                                                          e2.message.guid ==
                                                                                              message.guid! &&
                                                                                          e2.part.part == e.part);
                                                                                  return AnimatedSize(
                                                                                      duration: const Duration(
                                                                                          milliseconds: 250),
                                                                                      alignment: Alignment.centerRight,
                                                                                      curve: Curves.easeOutBack,
                                                                                      child: editStuff == null
                                                                                          ? const SizedBox.shrink()
                                                                                          : MessageEditField(
                                                                                              part: e.part,
                                                                                              editController:
                                                                                                  editStuff.controller,
                                                                                              cvController:
                                                                                                  widget.cvController,
                                                                                              onComplete: completeEdit,
                                                                                            ));
                                                                                }),
                                                                            ],
                                                                          );
                                                                          // Google Messages style reply: the
                                                                          // original as a card at the top of
                                                                          // this bubble.
                                                                          final body = googleStyle &&
                                                                                  isReply &&
                                                                                  !e.isUnsent &&
                                                                                  !message.isGroupEvent
                                                                              ? _withReplyCard(context, inner, e)
                                                                              : inner;
                                                                          if (isGallery) return body;
                                                                          final tailClipper = TailClipper(
                                                                            isFromMe: message.isFromMe!,
                                                                            showTail: !e.isPkPass &&
                                                                                message.showTail(newerMessage) &&
                                                                                e.part == controller.parts.length - 1,
                                                                            connectLower: iOS
                                                                                ? false
                                                                                : (e.part != 0 &&
                                                                                        e.part !=
                                                                                            controller.parts.length -
                                                                                                1) ||
                                                                                    (e.part == 0 &&
                                                                                        controller.parts.length > 1),
                                                                            connectUpper: iOS ? false : e.part != 0,
                                                                          );
                                                                          final clipped = ClipPath(
                                                                            clipper: tailClipper,
                                                                            child: body,
                                                                          );
                                                                          // OpenBubbles: scheduled ("Send Later")
                                                                          // messages get a dashed outline.
                                                                          if (message.dateScheduled == null) {
                                                                            return clipped;
                                                                          }
                                                                          return DottedBorder(
                                                                            customPath: (size) =>
                                                                                tailClipper.getClip(size),
                                                                            color:
                                                                                context.theme.colorScheme.primaryContainer,
                                                                            strokeWidth: 2,
                                                                            dashPattern: const [7, 4],
                                                                            child: clipped,
                                                                          );
                                                                        },
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                                // Reactions are in the inner Stack so they are always
                                                                // positioned relative to the bubble, not the sticker.
                                                                // Gallery parts show a reaction per attachment instead
                                                                // (inside MessageImageGallery), since a tapback can be
                                                                // associated with just one image/video in the gallery.
                                                                if (!(iOS && e.isMediaGallery))
                                                                  MessageReactions(
                                                                    messageParts: messageParts,
                                                                    part: e,
                                                                    chatGuid: chat.guid,
                                                                    reactionsForPart: reactionsForPart,
                                                                  ),
                                                              ],
                                                            ),
                                                            // Stickers are in the outer Stack so they contribute to
                                                            // the message holder's size but don't affect bubble alignment
                                                            StickerObserver(
                                                              messageParts: messageParts,
                                                              part: e,
                                                              cvController: widget.cvController,
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
                                      ],
                                    ),
                                  ),
                                  // message properties (replies, edits, effect)
                                  Padding(
                                    padding: showAvatar || alwaysShowAvatars
                                        ? EdgeInsets.only(left: 35.0 * avatarScale)
                                        : EdgeInsets.zero,
                                    child:
                                        MessageProperties(globalKey: keys.length > index ? keys[index] : null, part: e),
                                  ),
                                ],
                              ),
                            );
                        }),
                        // delivered / read receipt
                        DeliveredIndicatorObserver(tapped: tapped),
                      ],
                    ),
                  ),
                  if (isFromMe && !message.isGroupEvent) SelectCheckbox(controller: widget.cvController),
                  ErrorIndicatorObserver(chat: chat, service: service),
                  // slide to view timestamp
                  if (iOS) MessageTimestamp(controller: controller, cvController: widget.cvController),
                ],
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Material reply quote: the 2px line in the avatar column, continued down
/// the message body from the quote above to the reply's avatar (stopping
/// [stopAbove] px short of the bottom when the avatar sits in this part).
class _AvatarColumnLinePainter extends CustomPainter {
  final Color color;
  final double x;
  final double stopAbove;

  _AvatarColumnLinePainter({required this.color, required this.x, required this.stopAbove});

  @override
  void paint(Canvas canvas, Size size) {
    final bottom = size.height - stopAbove;
    if (bottom <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x, 0), Offset(x, bottom), paint);
  }

  @override
  bool shouldRepaint(_AvatarColumnLinePainter old) => old.color != color || old.x != x || old.stopAbove != stopAbove;
}

