import 'package:bluebubbles/app/components/custom/custom_bouncing_scroll_physics.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/sticker_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/chat_event/chat_event.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/interactive_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/bubble_effects.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/message_properties.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/message_sender.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/select_checkbox.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/slide_to_reply.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/tail_clipper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction_holder.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_line_painter.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/text/text_bubble.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/delivered_indicator.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/message_timestamp.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/timestamp_separator.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:tuple/tuple.dart';
import 'package:universal_io/io.dart';

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

  // Use cached value for expensive replyTo computation
  Message? get replyTo => _cachedReplyTo;

  Chat get chat => widget.cvController.chat;

  MessagesService get service => MessagesSvc(widget.cvController.chat.guid);

  // Use cached values for expensive computed properties
  bool get showSender => _cachedShowSender ?? false;
  bool get canSwipeToReply => _cachedCanSwipeToReply ?? false;
  
  bool get showAvatar => chat.isGroup;
  
  bool isEditing(int part) => message.isFromMe! && widget.cvController.editing.firstWhereOrNull((e2) => e2.item1.guid == message.guid! && e2.item2.part == part) != null;

  List<MessagePart> messageParts = [];
  List<RxDouble> replyOffsets = [];
  List<GlobalKey> keys = [];
  bool gaveHapticFeedback = false;
  final RxBool tapped = false.obs;
  
  // Cache computed values to avoid recalculating on every build
  List<Color>? _cachedBubbleColors;
  bool? _cachedShowSender;
  bool? _cachedCanSwipeToReply;
  Message? _cachedReplyTo;
  
  // Track what needs recalculation
  Set<_CacheKey> _invalidatedCaches = {};

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

    // Observe handle updates from ContactServiceV2
    if (message.handleRelation.target?.id != null) {
      ever(ContactsSvcV2.handleUpdateStatus, (_) {
        // Check if this specific handle was updated
        if (ContactsSvcV2.isHandleUpdated(message.handleRelation.target!.id!)) {
          _updateCachedValues();
          if (mounted) setState(() {});
        }
      });
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache computed values after context is available
    _updateCachedValues();
  }
  
  /// Smart cache invalidation - only recalculate what changed
  void _updateCachedValues({bool forceAll = false, Set<_CacheKey>? specific}) {
    if (forceAll) {
      // Recalculate everything
      _cachedBubbleColors = null;
      _cachedShowSender = null;
      _cachedCanSwipeToReply = null;
      _cachedReplyTo = null;
      _invalidatedCaches.clear();
    } else if (specific != null) {
      // Only invalidate specific caches
      _invalidatedCaches.addAll(specific);
    }
    
    // Recalculate only what's needed
    if (forceAll || _invalidatedCaches.contains(_CacheKey.bubbleColors) || _cachedBubbleColors == null) {
      _cachedBubbleColors = _calculateBubbleColors();
      _invalidatedCaches.remove(_CacheKey.bubbleColors);
    }
    if (forceAll || _invalidatedCaches.contains(_CacheKey.showSender) || _cachedShowSender == null) {
      _cachedShowSender = !message.isGroupEvent &&
          (!message.sameSender(olderMessage) || (olderMessage?.isGroupEvent ?? false) || 
           (olderMessage == null || !message.dateCreated!.isWithin(olderMessage!.dateCreated!, minutes: 30)));
      _invalidatedCaches.remove(_CacheKey.showSender);
    }
    if (forceAll || _invalidatedCaches.contains(_CacheKey.canSwipeToReply) || _cachedCanSwipeToReply == null) {
      _cachedCanSwipeToReply = SettingsSvc.settings.enablePrivateAPI.value && SettingsSvc.isMinBigSurSync && 
          chat.isIMessage && !widget.isReplyThread && !message.guid!.startsWith("temp") && !message.guid!.startsWith("error");
      _invalidatedCaches.remove(_CacheKey.canSwipeToReply);
    }
    if (forceAll || _invalidatedCaches.contains(_CacheKey.replyTo) || _cachedReplyTo == null) {
      _cachedReplyTo = message.threadOriginatorGuid == null
          ? null
          : SettingsSvc.settings.repliesToPrevious.value
              ? (service.struct.getPreviousReply(message.threadOriginatorGuid!, message.normalizedThreadPart, message.guid!) ?? 
                 service.struct.getThreadOriginator(message.threadOriginatorGuid!))
              : service.struct.getThreadOriginator(message.threadOriginatorGuid!);
      _invalidatedCaches.remove(_CacheKey.replyTo);
    }
  }
  
  /// Helper to calculate bubble colors (extracted for smart caching)
  List<Color> _calculateBubbleColors() {
    List<Color> bubbleColors = [context.theme.colorScheme.properSurface, context.theme.colorScheme.properSurface];
    if (SettingsSvc.settings.colorfulBubbles.value && !message.isFromMe!) {
      if (message.handleRelation.target?.color == null) {
        bubbleColors = toColorGradient(message.handleRelation.target?.address);
      } else {
        bubbleColors = [
          HexColor(message.handleRelation.target!.color!),
          HexColor(message.handleRelation.target!.color!).lightenAmount(0.075),
        ];
      }
    }
    return bubbleColors;
  }

  @override
  void updateWidget(void _) {
    messageParts = controller.parts;
    // Only invalidate caches that depend on message parts changing
    _updateCachedValues(specific: {_CacheKey.replyTo});
    super.updateWidget(_);
  }

  List<Color> getBubbleColors() {
    // Return cached value if available
    return _cachedBubbleColors ?? _calculateBubbleColors();
  }

  void _handleHapticFeedback(RxDouble offset) {
    if (!gaveHapticFeedback && offset.value.abs() >= SlideToReply.replyThreshold) {
      HapticFeedback.lightImpact();
      gaveHapticFeedback = true;
    } else if (offset.value.abs() < SlideToReply.replyThreshold) {
      gaveHapticFeedback = false;
    }
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
            content: Container(
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
      return message.associatedMessages.where((e) => ReactionTypes.toList().contains(e.associatedMessageType?.replaceAll("-", ""))).toList();
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
              if (!message.isFromMe! && !message.isGroupEvent) SelectCheckbox(message: message, controller: widget.cvController),
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
                                _EditHistoryObserver(
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
                                  padding: EdgeInsets.only(left: (showAvatar || alwaysShowAvatars) && replyTo!.isFromMe! ? 35 : 0),
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
                                    child: Container(
                                      width: double.infinity,
                                      alignment: replyTo!.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
                                      child: ReplyBubble(
                                        parentController: getActiveMwc(replyTo!.guid!)!,
                                        part: replyTo!.guid! == message.threadOriginatorGuid ? message.normalizedThreadPart : 0,
                                        showAvatar: (chat.isGroup || alwaysShowAvatars || !iOS) && !replyTo!.isFromMe!,
                                        cvController: widget.cvController,
                                      ),
                                    ),
                                  ),
                                ),
                              // show sender, if needed
                              if (chat.isGroup && !message.isFromMe! && showSender && e.part == (messageParts.firstWhereOrNull((e) => !e.isUnsent)?.part))
                                Padding(
                                  padding: showAvatar || alwaysShowAvatars ? EdgeInsets.only(left: 35.0 * avatarScale) : EdgeInsets.zero,
                                  child: MessageSender(olderMessage: olderMessage, message: message),
                                ),
                              // add a box to account for height of reactions
                              _ReactionSpacing(
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
                                Padding(
                                  padding: showAvatar || alwaysShowAvatars ? const EdgeInsets.only(left: 45.0, right: 10) : const EdgeInsets.symmetric(horizontal: 10),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(25),
                                      border: Border.fromBorderSide(BorderSide(color: context.theme.colorScheme.properSurface)),
                                    ),
                                    child: ReplyBubble(
                                      parentController: getActiveMwc(replyTo!.guid!)!,
                                      part: replyTo!.guid! == message.threadOriginatorGuid ? message.normalizedThreadPart : 0,
                                      showAvatar: (chat.isGroup || alwaysShowAvatars || !iOS) && !replyTo!.isFromMe!,
                                      cvController: widget.cvController,
                                    ),
                                  ),
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
                                                ((index == 0 && message.threadOriginatorGuid != null && olderMessage != null) ||
                                                    (index == messageParts.length - 1 && service.struct.threads(message.guid!, index).isNotEmpty && newerMessage != null))
                                            ? ReplyLineDecoration(
                                                isFromMe: message.isFromMe!,
                                                color: context.theme.colorScheme.properSurface,
                                                connectUpper: message.connectToUpper(),
                                                connectLower: newerMessage != null && message.connectToLower(newerMessage!),
                                                context: context,
                                              )
                                            : const BoxDecoration(),
                                        child: _SelectModeWrapper(
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
                                                      _SamsungTimestampObserver(
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
                                                        crossAxisAlignment: message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                                        children: [
                                                          // interactive messages may have subjects, so render them here
                                                          // also render the subject for attachments that may have not rendered already
                                                          if ((message.hasApplePayloadData ||
                                                                  message.isLegacyUrlPreview ||
                                                                  message.isInteractive ||
                                                                  (e.part == 0 && isNullOrEmpty(e.text) && e.attachments.isNotEmpty)) &&
                                                              !isNullOrEmpty(message.subject))
                                                            Padding(
                                                              padding: const EdgeInsets.only(bottom: 2.0),
                                                              child: ClipPath(
                                                                clipper: TailClipper(
                                                                  isFromMe: message.isFromMe!,
                                                                  showTail: false,
                                                                  connectLower: iOS ? false : (e.part != 0 && e.part != controller.parts.length - 1) || (e.part == 0 && controller.parts.length > 1),
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
                                                                showTail: message.showTail(newerMessage) && e.part == controller.parts.length - 1,
                                                                child: MessagePopupHolder(
                                                                  key: keys.length > index ? keys[index] : null,
                                                                  controller: controller,
                                                                  cvController: widget.cvController,
                                                                  part: e,
                                                                  isEditing: isEditing(e.part),
                                                                  child: GestureDetector(
                                                                    behavior: HitTestBehavior.deferToChild,
                                                                    onHorizontalDragUpdate: !canSwipeToReply || isEditing(e.part)
                                                                        ? null
                                                                        : (details) {
                                                                            if (ReplyScope.maybeOf(context) != null) return;
                                                                            final offset = replyOffsets[index];
                                                                            offset.value += details.delta.dx * 0.5;
                                                                            if (message.isFromMe!) {
                                                                              offset.value = offset.value.clamp(-double.infinity, 0);
                                                                            } else {
                                                                              offset.value = offset.value.clamp(0, double.infinity);
                                                                            }
                                                                            _handleHapticFeedback(offset);
                                                                          },
                                                                    onHorizontalDragEnd: !canSwipeToReply || isEditing(e.part)
                                                                        ? null
                                                                        : (details) {
                                                                            if (ReplyScope.maybeOf(context) != null) return;
                                                                            final offset = replyOffsets[index];
                                                                            if (offset.value.abs() >= SlideToReply.replyThreshold) {
                                                                              widget.cvController.replyToMessage = Tuple2(message, index);
                                                                            }
                                                                            offset.value = 0;
                                                                          },
                                                                    onHorizontalDragCancel: !canSwipeToReply || isEditing(e.part)
                                                                        ? null
                                                                        : () {
                                                                            if (ReplyScope.maybeOf(context) != null) return;
                                                                            if (index < replyOffsets.length) {
                                                                              replyOffsets[index].value = 0;
                                                                            }
                                                                          },
                                                                    child: ClipPath(
                                                                      clipper: TailClipper(
                                                                        isFromMe: message.isFromMe!,
                                                                        showTail: message.showTail(newerMessage) && e.part == controller.parts.length - 1,
                                                                        connectLower:
                                                                            iOS ? false : (e.part != 0 && e.part != controller.parts.length - 1) || (e.part == 0 && controller.parts.length > 1),
                                                                        connectUpper: iOS ? false : e.part != 0,
                                                                      ),
                                                                      child: Stack(
                                                                        alignment: Alignment.centerRight,
                                                                        children: [
                                                                          message.hasApplePayloadData || message.isLegacyUrlPreview || message.isInteractive
                                                                              ? InteractiveHolder(
                                                                                  parentController: controller,
                                                                                  message: e,
                                                                                )
                                                                              : e.attachments.isEmpty && (e.text != null || e.subject != null)
                                                                                  ? TextBubble(
                                                                                      parentController: controller,
                                                                                      message: e,
                                                                                    )
                                                                                  : e.attachments.isNotEmpty
                                                                                      ? AttachmentHolder(
                                                                                          parentController: controller,
                                                                                          message: e,
                                                                                        )
                                                                                      : const SizedBox.shrink(),
                                                                          if (message.isFromMe!)
                                                                            Obx(() {
                                                                              final editStuff =
                                                                                  widget.cvController.editing.firstWhereOrNull((e2) => e2.item1.guid == message.guid! && e2.item2.part == e.part);
                                                                              return AnimatedSize(
                                                                                  duration: const Duration(milliseconds: 250),
                                                                                  alignment: Alignment.centerRight,
                                                                                  curve: Curves.easeOutBack,
                                                                                  child: editStuff == null
                                                                                      ? const SizedBox.shrink()
                                                                                      : Material(
                                                                                          color: Colors.transparent,
                                                                                          child: Container(
                                                                                            decoration: BoxDecoration(
                                                                                              color: !message.isBigEmoji
                                                                                                  ? context.theme.colorScheme.primary.darkenAmount(message.guid!.startsWith("temp") ? 0.2 : 0)
                                                                                                  : context.theme.colorScheme.background,
                                                                                            ),
                                                                                            constraints: BoxConstraints(
                                                                                              maxWidth: NavigationSvc.width(context) * MessageWidgetController.maxBubbleSizeFactor - 40,
                                                                                              minHeight: 40,
                                                                                            ),
                                                                                            padding: const EdgeInsets.only(right: 10).add(const EdgeInsets.all(5)),
                                                                                            child: Focus(
                                                                                              focusNode: FocusNode(),
                                                                                              onKeyEvent: (_, ev) {
                                                                                                if (ev is! KeyDownEvent) {
                                                                                                  if (ev.logicalKey == LogicalKeyboardKey.tab) {
                                                                                                    // Absorb tab
                                                                                                    return KeyEventResult.skipRemainingHandlers;
                                                                                                  }
                                                                                                  return KeyEventResult.ignored;
                                                                                                }
                                                                                                if (ev.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
                                                                                                  completeEdit(editStuff.item3.text, e.part);
                                                                                                  return KeyEventResult.handled;
                                                                                                }
                                                                                                if (ev.logicalKey == LogicalKeyboardKey.escape) {
                                                                                                  widget.cvController.editing
                                                                                                      .removeWhere((e2) => e2.item1.guid == message.guid! && e2.item2.part == e.part);
                                                                                                  if (widget.cvController.editing.isEmpty) {
                                                                                                    widget.cvController.lastFocusedNode.requestFocus();
                                                                                                  } else {
                                                                                                    widget.cvController.editing.last.item3.focusNode?.requestFocus();
                                                                                                  }
                                                                                                  return KeyEventResult.handled;
                                                                                                }
                                                                                                if (ev.logicalKey == LogicalKeyboardKey.tab) {
                                                                                                  // Absorb tab
                                                                                                  return KeyEventResult.skipRemainingHandlers;
                                                                                                }
                                                                                                return KeyEventResult.ignored;
                                                                                              },
                                                                                              child: TextField(
                                                                                                textCapitalization: TextCapitalization.sentences,
                                                                                                autocorrect: true,
                                                                                                controller: editStuff.item3,
                                                                                                focusNode: editStuff.item3.focusNode,
                                                                                                scrollPhysics: const CustomBouncingScrollPhysics(),
                                                                                                style: context.theme.extension<BubbleText>()!.bubbleText.apply(
                                                                                                      fontSizeFactor: message.isBigEmoji ? 3 : 1,
                                                                                                    ),
                                                                                                keyboardType: TextInputType.multiline,
                                                                                                maxLines: 14,
                                                                                                minLines: 1,
                                                                                                autofocus: !(kIsDesktop || kIsWeb),
                                                                                                enableIMEPersonalizedLearning: !SettingsSvc.settings.incognitoKeyboard.value,
                                                                                                textInputAction: SettingsSvc.settings.sendWithReturn.value && !kIsWeb && !kIsDesktop
                                                                                                    ? TextInputAction.send
                                                                                                    : TextInputAction.newline,
                                                                                                cursorColor: context.theme.extension<BubbleText>()!.bubbleText.color,
                                                                                                cursorHeight:
                                                                                                    context.theme.extension<BubbleText>()!.bubbleText.fontSize! * 1.25 * (message.isBigEmoji ? 3 : 1),
                                                                                                decoration: InputDecoration(
                                                                                                  contentPadding: EdgeInsets.all(iOS ? 10 : 12.5),
                                                                                                  isDense: true,
                                                                                                  isCollapsed: true,
                                                                                                  hintText: "Edited Message",
                                                                                                  enabledBorder: OutlineInputBorder(
                                                                                                    borderSide: BorderSide(color: context.theme.colorScheme.outline, width: 1.5),
                                                                                                    borderRadius: BorderRadius.circular(20),
                                                                                                  ),
                                                                                                  border: OutlineInputBorder(
                                                                                                    borderSide: BorderSide(color: context.theme.colorScheme.outline, width: 1.5),
                                                                                                    borderRadius: BorderRadius.circular(20),
                                                                                                  ),
                                                                                                  focusedBorder: OutlineInputBorder(
                                                                                                    borderSide: BorderSide(color: context.theme.colorScheme.outline, width: 1.5),
                                                                                                    borderRadius: BorderRadius.circular(20),
                                                                                                  ),
                                                                                                  fillColor: Colors.transparent,
                                                                                                  hintStyle: context.theme
                                                                                                      .extension<BubbleText>()!
                                                                                                      .bubbleText
                                                                                                      .copyWith(color: context.theme.colorScheme.outline),
                                                                                                  prefixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 40),
                                                                                                  prefixIcon: IconButton(
                                                                                                    constraints: const BoxConstraints(maxWidth: 27),
                                                                                                    padding: const EdgeInsets.only(left: 5),
                                                                                                    visualDensity: VisualDensity.compact,
                                                                                                    icon: Icon(
                                                                                                      CupertinoIcons.xmark_circle_fill,
                                                                                                      color: context.theme.colorScheme.outline,
                                                                                                      size: 22,
                                                                                                    ),
                                                                                                    onPressed: () {
                                                                                                      widget.cvController.editing
                                                                                                          .removeWhere((e2) => e2.item1.guid == message.guid! && e2.item2.part == e.part);
                                                                                                      widget.cvController.lastFocusedNode.requestFocus();
                                                                                                    },
                                                                                                    iconSize: 22,
                                                                                                    style: const ButtonStyle(
                                                                                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                                                      visualDensity: VisualDensity.compact,
                                                                                                    ),
                                                                                                  ),
                                                                                                  suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 40),
                                                                                                  suffixIcon: ValueListenableBuilder(
                                                                                                    valueListenable: editStuff.item3,
                                                                                                    builder: (context, value, _) {
                                                                                                      return Padding(
                                                                                                        padding: const EdgeInsets.all(3.0),
                                                                                                        child: TextButton(
                                                                                                          style: TextButton.styleFrom(
                                                                                                            backgroundColor: Colors.transparent,
                                                                                                            shape: const CircleBorder(),
                                                                                                            padding: const EdgeInsets.all(0),
                                                                                                            maximumSize: const Size(27, 27),
                                                                                                            minimumSize: const Size(27, 27),
                                                                                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                                                          ),
                                                                                                          child: AnimatedContainer(
                                                                                                            duration: const Duration(milliseconds: 150),
                                                                                                            constraints: const BoxConstraints(minHeight: 27, minWidth: 27),
                                                                                                            decoration: BoxDecoration(
                                                                                                              shape: iOS ? BoxShape.circle : BoxShape.rectangle,
                                                                                                              color: !iOS
                                                                                                                  ? null
                                                                                                                  : editStuff.item3.text.isNotEmpty
                                                                                                                      ? Colors.white
                                                                                                                      : context.theme.colorScheme.outline,
                                                                                                            ),
                                                                                                            alignment: Alignment.center,
                                                                                                            child: Icon(
                                                                                                              iOS ? CupertinoIcons.arrow_up : Icons.send_outlined,
                                                                                                              color: !iOS
                                                                                                                  ? context.theme.extension<BubbleText>()!.bubbleText.color
                                                                                                                  : context.theme.colorScheme.bubble(context, chat.isIMessage),
                                                                                                              size: iOS ? 18 : 26,
                                                                                                            ),
                                                                                                          ),
                                                                                                          onPressed: () {
                                                                                                            completeEdit(editStuff.item3.text, e.part);
                                                                                                          },
                                                                                                        ),
                                                                                                      );
                                                                                                    },
                                                                                                  ),
                                                                                                ),
                                                                                                onTap: () {
                                                                                                  HapticFeedback.selectionClick();
                                                                                                },
                                                                                                onSubmitted: (String value) {
                                                                                                  completeEdit(value, e.part);
                                                                                                },
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ));
                                                                            }),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                              // show stickers on top
                                                              _StickerObserver(
                                                                messageParts: messageParts,
                                                                stickers: stickers,
                                                                part: e,
                                                                cvController: widget.cvController,
                                                              ),
                                                              // show reactions on top
                                                              if (message.isFromMe!)
                                                                _ReactionObserver(
                                                                  controller: controller,
                                                                  message: message,
                                                                  messageParts: messageParts,
                                                                  part: e,
                                                                  chatGuid: chat.guid,
                                                                  isFromMe: true,
                                                                  getReactions: getReactions,
                                                                  reactionsForPart: reactionsForPart,
                                                                ),
                                                              if (!message.isFromMe!)
                                                                _ReactionObserver(
                                                                  controller: controller,
                                                                  message: message,
                                                                  messageParts: messageParts,
                                                                  part: e,
                                                                  chatGuid: chat.guid,
                                                                  isFromMe: false,
                                                                  getReactions: getReactions,
                                                                  reactionsForPart: reactionsForPart,
                                                                ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    // swipe to reply
                                                    if (canSwipeToReply && !message.isGroupEvent && !e.isUnsent && !widget.isReplyThread && index < replyOffsets.length)
                                                      Obx(() => SlideToReply(width: replyOffsets[index].value.abs(), isFromMe: message.isFromMe!)),
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
                                padding: showAvatar || alwaysShowAvatars ? EdgeInsets.only(left: 35.0 * avatarScale) : EdgeInsets.zero,
                                child: MessageProperties(globalKey: keys.length > index ? keys[index] : null, parentController: controller, part: e),
                              ),
                            ],
                          ),
                        )),
                    // delivered / read receipt
                    _DeliveredIndicatorObserver(controller: controller, tapped: tapped),
                  ],
                ),
              ),
              if (message.isFromMe! && !message.isGroupEvent) SelectCheckbox(message: message, controller: widget.cvController),
              _ErrorIndicatorObserver(controller: controller, message: message, chat: chat, service: service),
              // slide to view timestamp
              if (iOS) MessageTimestamp(controller: controller, cvController: widget.cvController),
            ],
          ),
        ],
      ),
    );
  }
}

/// Isolated widget for reaction observation to prevent unnecessary rebuilds
/// Only rebuilds when reactions actually change, not the entire message
class _ReactionObserver extends StatelessWidget {
  const _ReactionObserver({
    required this.controller,
    required this.message,
    required this.messageParts,
    required this.part,
    required this.chatGuid,
    required this.isFromMe,
    required this.getReactions,
    required this.reactionsForPart,
  });

  final MessageWidgetController controller;
  final Message message;
  final List<MessagePart> messageParts;
  final MessagePart part;
  final String chatGuid;
  final bool isFromMe;
  final List<Message> Function() getReactions;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: -14,
      left: isFromMe ? -20 : null,
      right: isFromMe ? null : -20,
      child: Obx(() {
        // Observe granular reactions flag to minimize rebuilds
        controller.reactionsChanged.value;
        // Also watch coordinator trigger for immediate updates (bypasses ObjectBox latency)
        muc.getUpdateTrigger(chatGuid, message.guid!)?.value;
        // Recalculate reactions inside Obx for reactivity
        final reactions = getReactions();
        final reactionList = messageParts.length == 1 ? reactions : reactionsForPart(part.part, reactions).toList();
        Logger.debug(
          "[MessageHolder] Rebuilding ReactionHolder for ${message.guid} (isFromMe: $isFromMe) with ${reactionList.length} reactions",
          tag: "MessageReactivity"
        );
        return ReactionHolder(
          reactions: reactionList,
          message: message,
        );
      }),
    );
  }
}

/// Isolated widget for sticker observation to prevent unnecessary rebuilds
class _StickerObserver extends StatelessWidget {
  const _StickerObserver({
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
    final stickersForPart = messageParts.length == 1 
        ? stickers 
        : stickers.where((s) => (s.associatedMessagePart ?? 0) == part.part);
    
    if (stickersForPart.isEmpty) return const SizedBox.shrink();
    
    return StickerHolder(
      stickerMessages: stickersForPart,
      controller: cvController,
    );
  }
}

/// Isolated widget for reaction spacing calculation
/// Only rebuilds when reactions change, not the entire message part
class _ReactionSpacing extends StatelessWidget {
  const _ReactionSpacing({
    required this.controller,
    required this.messageParts,
    required this.part,
    required this.getReactions,
    required this.reactionsForPart,
  });

  final MessageWidgetController controller;
  final List<MessagePart> messageParts;
  final MessagePart part;
  final List<Message> Function() getReactions;
  final Iterable<Message> Function(int, List<Message>) reactionsForPart;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      controller.reactionsChanged.value; // observe for reactivity
      final reactions = getReactions();
      if ((messageParts.length == 1 && reactions.isNotEmpty) || reactionsForPart(part.part, reactions).isNotEmpty) {
        return const SizedBox(height: 12.5);
      }
      return const SizedBox.shrink();
    });
  }
}

/// Isolated widget for delivered indicator
/// Only rebuilds when tapped state changes
class _DeliveredIndicatorObserver extends StatelessWidget {
  const _DeliveredIndicatorObserver({
    required this.controller,
    required this.tapped,
  });

  final MessageWidgetController controller;
  final RxBool tapped;

  @override
  Widget build(BuildContext context) {
    return Obx(() => DeliveredIndicator(
      parentController: controller,
      forceShow: tapped.value,
    ));
  }
}

/// Isolated widget for error indicator
/// Only rebuilds when error state changes
class _ErrorIndicatorObserver extends StatelessWidget {
  const _ErrorIndicatorObserver({
    required this.controller,
    required this.message,
    required this.chat,
    required this.service,
  });

  final MessageWidgetController controller;
  final Message message;
  final Chat chat;
  final MessagesService service;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      // Observe granular error state flag to minimize rebuilds
      controller.errorChanged.value;
      
      if (message.error > 0 || message.guid!.startsWith("error-")) {
        int errorCode = message.error;
        String errorText = "An unknown internal error occurred.";
        if (errorCode == 22) {
          errorText = "The recipient is not registered with iMessage!";
        } else if (message.guid!.startsWith("error-")) {
          errorText = message.guid!.split('-')[1];
        }

        return IconButton(
          icon: Icon(
            SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.exclamationmark_circle : Icons.error_outline,
            color: context.theme.colorScheme.error,
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: context.theme.colorScheme.properSurface,
                  title: Text("Message failed to send", style: context.theme.textTheme.titleLarge),
                  content: Text("Error ($errorCode): $errorText", style: context.theme.textTheme.bodyLarge),
                  actions: <Widget>[
                    TextButton(
                      child: Text("Retry", style: context.theme.textTheme.bodyLarge!.copyWith(color: Get.context!.theme.colorScheme.primary)),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        
                        // Save old GUID and generate new temp GUID for retry
                        final oldGuid = message.guid!;
                        message.generateTempGuid();
                        
                        // Clear error, delivery status, and update timestamp
                        message.error = 0;
                        message.dateCreated = DateTime.now();
                        message.dateDelivered = null;
                        message.dateRead = null;
                        
                        // Delete old errored message from DB and save with new temp GUID
                        await Message.delete(oldGuid);
                        message.id = null;
                        message.save(chat: chat);
                        
                        // Clear notification
                        await NotificationsSvc.clearFailedToSend(chat.id!);
                        
                        // Force UI rebuild to show unsent color
                        controller.update();
                        
                        // Reload attachment bytes if needed
                        for (Attachment? a in message.attachments) {
                          if (a == null) continue;
                          await Attachment.deleteAsync(a.guid!);
                          a.bytes = await File(a.path).readAsBytes();
                        }
                        
                        // Queue for sending (message already in UI, just updated)
                        if (message.attachments.isNotEmpty) {
                          outq.queue(OutgoingItem(
                            type: QueueType.sendAttachment,
                            chat: chat,
                            message: message,
                          ));
                        } else {
                          outq.queue(OutgoingItem(
                            type: QueueType.sendMessage,
                            chat: chat,
                            message: message,
                          ));
                        }
                      },
                    ),
                    TextButton(
                      child: Text("Remove", style: context.theme.textTheme.bodyLarge!.copyWith(color: Get.context!.theme.colorScheme.primary)),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        // Delete the message from the DB
                        Message.delete(message.guid!);
                        // Remove the message from the Bloc
                        service.removeMessage(message);
                        await NotificationsSvc.clearFailedToSend(chat.id!);
                        // Get the "new" latest info
                        List<Message> latest = await Chat.getMessagesAsync(chat, limit: 1);
                        chat.latestMessage = latest.first;
                        await chat.saveAsync();
                      },
                    ),
                    TextButton(
                      child: Text("Cancel", style: context.theme.textTheme.bodyLarge!.copyWith(color: Get.context!.theme.colorScheme.primary)),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await NotificationsSvc.clearFailedToSend(chat.id!);
                      },
                    )
                  ],
                );
              },
            );
          },
        );
      }
      return const SizedBox.shrink();
    });
  }
}

/// Isolated widget for Samsung timestamp with reaction-aware padding
/// Only rebuilds when reactions change
class _SamsungTimestampObserver extends StatelessWidget {
  const _SamsungTimestampObserver({
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
      controller.reactionsChanged.value; // observe for reactivity
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
class _EditHistoryObserver extends StatelessWidget {
  const _EditHistoryObserver({
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
                              connectLower: SettingsSvc.settings.skin.value == Skins.iOS ? false : (part.part != 0 && part.part != controller.parts.length - 1) || (part.part == 0 && controller.parts.length > 1),
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
            : Container(height: 0, constraints: BoxConstraints(maxWidth: NavigationSvc.width(context) * MessageWidgetController.maxBubbleSizeFactor - 30)),
      )),
    );
  }
}

/// Isolated wrapper for select mode to minimize Obx scope
/// Only this small widget rebuilds on select mode changes
class _SelectModeWrapper extends StatelessWidget {
  const _SelectModeWrapper({
    required this.cvController,
    required this.message,
    required this.tapped,
    required this.child,
  });

  final ConversationViewController cvController;
  final Message message;
  final RxBool tapped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Obx(() => GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: cvController.inSelectMode.value
          ? () {
              if (cvController.isSelected(message.guid!)) {
                cvController.selected.remove(message);
              } else {
                cvController.selected.add(message);
              }
            }
          : kIsDesktop || kIsWeb || SettingsSvc.settings.skin.value == Skins.iOS || SettingsSvc.settings.skin.value == Skins.Material
              ? () => tapped.value = !tapped.value
              : null,
      child: IgnorePointer(
        ignoring: cvController.inSelectMode.value,
        child: child,
      ),
    ));
  }
}

/// Cache keys for smart cache invalidation in MessageHolder
/// Only recalculates values that have actually changed
enum _CacheKey {
  bubbleColors,
  showSender,
  canSwipeToReply,
  replyTo,
}