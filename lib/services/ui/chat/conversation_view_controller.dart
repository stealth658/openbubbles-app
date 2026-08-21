import 'dart:async';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/app/layouts/settings/pages/profile/posterkit.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:universal_io/io.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/interfaces/prefs_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:bluebubbles/services/ui/chat/send_data.dart';
import 'package:bluebubbles/models/models.dart' show MessageReplyContext;
import 'package:unicode_emojis/unicode_emojis.dart';

class MessageEditEntry {
  final Message message;
  final MessagePart part;
  final SpellCheckTextEditingController controller;
  const MessageEditEntry({required this.message, required this.part, required this.controller});
}

ConversationViewController cvc(Chat chat, {String? tag}) =>
    Get.isRegistered<ConversationViewController>(tag: tag ?? chat.guid)
        ? Get.find<ConversationViewController>(tag: tag ?? chat.guid)
        : Get.put(ConversationViewController(chat, tag_: tag), tag: tag ?? chat.guid);

class ConversationViewController extends StatefulController with GetSingleTickerProviderStateMixin {
  final Chat chat;
  late final String tag;
  bool fromChatCreator = false;
  bool fromSearchResult = false;
  bool addedRecentPhotoReply = false;
  final AutoScrollController scrollController = AutoScrollController();

  ConversationViewController(this.chat, {String? tag_}) {
    tag = tag_ ?? chat.guid;
    // OpenBubbles: seed the per-chat state rustpush keeps on the controller.
    recipientNotifsSilenced.value = chat.notifsSilenced;
    reportJunkAvailable.value = !(chat.senderIsKnown ?? true);
  }

  // caching items
  /// OpenBubbles: decoded attachment bytes keyed by attachment GUID.
  final Map<String, Uint8List> imageData = {};

  /// OpenBubbles: decoded sticker bytes (+ their placement data) per message part.
  final Map<String, Map<String, (Uint8List, StickerData?)>> stickerData = {};
  final Map<String, VideoController> videoPlayers = {};
  final Map<String, PlayerController> audioPlayers = {};
  final Map<String, Player> audioPlayersDesktop = {};
  final Map<String, List<EntityAnnotation>> mlKitParsedText = {};

  // message view items
  final RxBool showTypingIndicator = false.obs;

  /// OpenBubbles: rustpush reports typing per participant (with an optional app
  /// icon), so the indicator row needs the handles rather than a single bool.
  final RxList<Handle> showTypingIndicatorFor = <Handle>[].obs;
  final Map<String, (StreamSubscription<dynamic>, Uint8List?)> typingIndicatorData = {};
  final RxBool showScrollDown = false.obs;
  final RxDouble timestampOffset = 0.0.obs;
  final RxBool inSelectMode = false.obs;
  final RxList<Message> selected = <Message>[].obs;
  final RxList<MessageEditEntry> editing = <MessageEditEntry>[].obs;
  final GlobalKey focusInfoKey = GlobalKey();
  final GlobalKey typingInfoKey = GlobalKey();
  final RxBool recipientNotifsSilenced = false.obs;

  /// OpenBubbles: whether the "Report Junk" affordance applies to this chat
  /// (i.e. the sender is not a known contact).
  final RxBool reportJunkAvailable = false.obs;
  final RxBool showSmartReplyRow = false.obs;
  final RxDouble smartReplyRowHeight = 0.0.obs;
  bool showingOverlays = false;

  /// True while a pointer is actively dragging a [MessageImageGallery] fan of
  /// cards, so the list-wide timestamp-reveal swipe in [MessagesView] can
  /// ignore that drag instead of fighting the gallery for the same gesture.
  bool isGalleryDragging = false;

  /// True while any route is pushed on top of the conversation view route (e.g.
  /// ConversationDetails). Used by onAppResume to skip keyboard auto-focus on mobile.
  bool showingSubRoute = false;
  bool _subjectWasLastFocused = false; // If this is false, then message field was last focused (default)

  FocusNode get lastFocusedNode => _subjectWasLastFocused ? subjectFocusNode : focusNode;
  SpellCheckTextEditingController get lastFocusedTextController =>
      _subjectWasLastFocused ? subjectTextController : textController;

  // text field items
  final RxBool showAttachmentPicker = false.obs;
  RxBool showEmojiPicker = false.obs;
  final GlobalKey textFieldKey = GlobalKey();
  final RxList<PlatformFile> pickedAttachments = <PlatformFile>[].obs;
  final focusNode = FocusNode();
  final subjectFocusNode = FocusNode();
  // OpenBubbles: focus targets used by the keyboard-navigation shortcuts.
  final headerBackFocusNode = FocusNode();
  FocusNode? bottomMessageFocusNode;
  // OpenBubbles: only iMessage chats support rich text, SMS/RCS do not.
  late final textController = MentionTextEditingController(focusNode: focusNode, supportsFormatting: chat.isIMessage);
  late final subjectTextController = SpellCheckTextEditingController(focusNode: subjectFocusNode);

  /// OpenBubbles: the iMessage app payload staged for the next send
  /// (poll, handwriting, digital touch, ...) along with its preview file.
  final Rx<(PlatformFile?, PayloadData)?> pickedApp = Rx<(PlatformFile?, PayloadData)?>(null);
  final RxBool showRecording = false.obs;
  final RxList<Emoji> emojiMatches = <Emoji>[].obs;
  final RxInt emojiSelectedIndex = 0.obs;
  final RxList<Mentionable> mentionMatches = <Mentionable>[].obs;
  final RxInt mentionSelectedIndex = 0.obs;
  final ScrollController emojiScrollController = ScrollController();
  final Rxn<DateTime> scheduledDate = Rxn<DateTime>(null);
  final Rxn<MessageReplyContext> _replyToMessage = Rxn<MessageReplyContext>(null);
  MessageReplyContext? get replyToMessage => _replyToMessage.value;
  set replyToMessage(MessageReplyContext? m) {
    _replyToMessage.value = m;
    if (m != null) {
      lastFocusedNode.requestFocus();
    }
  }

  late final mentionables = chat.handles
      .map((e) => Mentionable(
            handle: e,
          ))
      .toList();

  // OpenBubbles: Apple name-and-photo sharing prompts shown in the chat header.
  final Rxn<ContactV2> suggestedContact = Rxn<ContactV2>(null);
  final RxBool suggestShare = false.obs;
  StreamSubscription<int>? shareSubscription;

  /// OpenBubbles: the contact poster rendered behind the transcript, if any.
  final Rxn<api.SimplifiedTranscriptPoster> backgroundPoster = Rxn<api.SimplifiedTranscriptPoster>(null);
  Map<String, ui.Image> images = {};

  Timer? _debounceTyping;

  bool keyboardOpen = false;
  double _keyboardOffset = 0;
  Timer? _scrollDownDebounce;
  Future<void> Function(SendData)? sendFunc;

  /// When set, [_SendAnimationState] will auto-fire this send as soon as it
  /// registers [sendFunc] (i.e. immediately after the widget is built).
  /// Used by ChatCreator to pre-queue a send before navigating to ConversationView.
  SendData? pendingSend;

  /// Completer that resolves once [MessagesView] has finished setting up its
  /// handlers AND its list key (both sync and async loadChunk paths).
  ///
  /// [SendAnimation] waits on this before firing a [pendingSend] so that
  /// [handleNewMessage] → [_listKey.currentState?.insertItem] is guaranteed
  /// to find a mounted [SliverAnimatedList], preventing the silent no-op race.
  Completer<void> _messagesViewReady = Completer<void>();

  /// Called by [MessagesView] once its handlers and list key are fully set up.
  void markMessagesViewReady() {
    if (!_messagesViewReady.isCompleted) {
      _messagesViewReady.complete();
    }
  }

  /// Called by [MessagesView.dispose] so that the next visit starts fresh.
  void resetMessagesViewReady() {
    if (_messagesViewReady.isCompleted) {
      _messagesViewReady = Completer<void>();
    }
  }

  /// Future that resolves once [MessagesView] has fully initialized.
  Future<void> get messagesViewReady => _messagesViewReady.future;

  /// Coordinates message list mutations against the in-flight send animation.
  ///
  /// [SendAnimation] holds this for the duration of its flight so that a
  /// message arriving at the same moment can't insert into the list (or toggle
  /// the smart reply / typing indicator rows) and move the animation's landing
  /// target out from under it. Held work replays as soon as the gate opens.
  /// The send itself is never gated — see [MessageListGate].
  final MessageListGate messageListGate = MessageListGate();

  @override
  void onInit() {
    super.onInit();

    // OpenBubbles: keep the header's contact-sharing prompts in sync.
    shareSubscription = SettingsSvc.settings.shareVersion.listen((_) => updateContactInfo());
    updateContactInfo();

    textController.mentionables = mentionables;
    KeyboardVisibilityController().onChange.listen((bool visible) async {
      keyboardOpen = visible;
      if (scrollController.hasClients && scrollController.positions.length == 1) {
        _keyboardOffset = scrollController.offset;
      }
    });

    scrollController.addListener(() {
      if (!scrollController.hasClients || scrollController.positions.length != 1) return;
      if (keyboardOpen &&
          SettingsSvc.settings.hideKeyboardOnScroll.value &&
          scrollController.offset > _keyboardOffset + 100) {
        focusNode.unfocus();
        subjectFocusNode.unfocus();
      }

      if (showScrollDown.value && scrollController.offset >= 500) return;
      if (!showScrollDown.value && scrollController.offset < 500) return;

      if (scrollController.offset >= 500 && !showScrollDown.value) {
        showScrollDown.value = true;
        if (_scrollDownDebounce?.isActive ?? false) _scrollDownDebounce?.cancel();
        _scrollDownDebounce = Timer(const Duration(seconds: 3), () {
          showScrollDown.value = false;
        });
      } else if (showScrollDown.value) {
        showScrollDown.value = false;
      }
    });

    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        _subjectWasLastFocused = false;
      }
    });

    subjectFocusNode.addListener(() {
      if (subjectFocusNode.hasFocus) {
        _subjectWasLastFocused = true;
      }
    });

    updatePoster();
  }

  /// OpenBubbles: (re)loads the contact poster used as the transcript background.
  Future<void> updatePoster() async {
    final posterPath = chat.transcriptPosterPath;
    if (posterPath == null) {
      backgroundPoster.value = null;
      return;
    }
    try {
      final data = await File("$posterPath.jpg").readAsBytes();
      final poster = await api.fromTranscriptPosterSave(poster: data);
      images = await loadPosterImages(posterPath, poster.poster);
      backgroundPoster.value = poster;
    } catch (e, stack) {
      Logger.warn("Failed to load transcript poster", error: e, trace: stack, tag: "ConversationViewController");
      backgroundPoster.value = null;
    }
  }

  /// OpenBubbles: recomputes the "share your name and photo" prompt for 1:1 chats.
  ///
  /// NOTE: the incoming half of this (Apple's "Maybe: <name>" shared-contact
  /// suggestion) relied on `Contact.isShared` / `Contact.isDismissed`, which the
  /// upstream ContactV2 model does not carry. [suggestedContact] therefore stays
  /// null until those flags exist on ContactV2 again.
  void updateContactInfo() {
    if (chat.participants.length != 1) return;
    final address = chat.participants.first.address;
    suggestShare.value = SettingsSvc.settings.nameAndPhotoSharing.value &&
        chat.isIMessage &&
        !SettingsSvc.settings.sharedContacts.contains(address) &&
        !SettingsSvc.settings.dismissedContacts.contains(address);
  }

  /// OpenBubbles: clears the typing debounce without emitting a "stopped" event
  /// (used right after a send, which implicitly ends typing).
  void clearTypingState() {
    _debounceTyping?.cancel();
    _debounceTyping = null;
  }

  /// OpenBubbles: routes typing indicators through the active backend, throttled
  /// so a burst of keystrokes doesn't produce a burst of events.
  void triggerTypingIndicator() {
    if (!SettingsSvc.settings.enablePrivateAPI.value ||
        !(chat.autoSendTypingIndicators ?? SettingsSvc.settings.privateSendTypingIndicators.value)) {
      return;
    }
    _debounceTyping?.cancel();
    if (_debounceTyping == null) {
      final appData = pickedApp.value?.$2.appData?.firstOrNull;
      // Polls is the only non-builtin app right now. Built-in apps have a circle
      // icon, which does not work with typing indicators.
      backend.startedTyping(chat, appData?.appId != null ? appData : null);
    }
    _debounceTyping = Timer(const Duration(seconds: 5), () {
      backend.stoppedTyping(chat);
      _debounceTyping = null;
    });
  }

  @override
  void onClose() {
    messageListGate.dispose();
    updateSmartReplyLayout(visible: false, height: 0);
    for (PlayerController a in audioPlayers.values) {
      a.pausePlayer();
      a.dispose();
    }
    for (Player a in audioPlayersDesktop.values) {
      a.dispose();
    }
    for (VideoController a in videoPlayers.values) {
      a.player.pause();
      a.player.dispose();
    }
    scrollController.dispose();
    // OpenBubbles
    headerBackFocusNode.dispose();
    shareSubscription?.cancel();
    _debounceTyping?.cancel();
    for (final entry in typingIndicatorData.values) {
      entry.$1.cancel();
    }
    typingIndicatorData.clear();
    super.onClose();
  }

  /// Disposes and evicts the cached [VideoController] for [attachmentGuid] -- call before a
  /// redownload replaces the underlying file, since the cached controller/aspect ratio is from
  /// the old decode and would otherwise get reused as-is.
  void invalidateVideoPlayer(String attachmentGuid) {
    final controller = videoPlayers.remove(attachmentGuid);
    if (controller == null) return;
    controller.player.pause();
    controller.player.dispose();
  }

  Future<void> scrollToBottom() async {
    if (scrollController.positions.isNotEmpty && scrollController.positions.first.extentBefore > 0) {
      await scrollController.animateTo(
        0.0,
        curve: Curves.easeOut,
        duration: const Duration(milliseconds: 300),
      );
    }

    if (SettingsSvc.settings.openKeyboardOnSTB.value) {
      focusNode.requestFocus();
    }
  }

  /// OpenBubbles: jumps the transcript to the first message at or before [time].
  /// Used after scheduling a send so the user sees where it landed.
  Future<void> scrollToTime(DateTime time) async {
    final service = maybeFindMessagesSvc(chat.guid);
    if (service != null && scrollController.positions.isNotEmpty) {
      final messages = service.struct.messages.toList()..sort(Message.sort);
      final index = messages.indexWhere((element) => element.chatViewDate?.isBefore(time) ?? false);
      if (index >= 0) {
        await scrollController.scrollToIndex(index, preferPosition: AutoScrollPosition.begin);
      }
    }

    if (SettingsSvc.settings.openKeyboardOnSTB.value) {
      focusNode.requestFocus();
    }
  }

  Future<void> send(SendData data) async {
    await sendFunc?.call(data);
  }

  bool isSelected(String guid) {
    return selected.firstWhereOrNull((e) => e.guid == guid) != null;
  }

  bool isEditing(String guid, int part) {
    return editing.firstWhereOrNull((e) => e.message.guid == guid && e.part.part == part) != null;
  }

  void updateSmartReplyLayout({required bool visible, required double height}) {
    if (showSmartReplyRow.value != visible) {
      showSmartReplyRow.value = visible;
    }

    final nextHeight = visible ? height : 0.0;
    if (smartReplyRowHeight.value != nextHeight) {
      smartReplyRowHeight.value = nextHeight;
    }
  }

  void close() {
    updateSmartReplyLayout(visible: false, height: 0);
    ChatsSvc.setAllInactiveSync();
    Get.delete<ConversationViewController>(tag: tag);
  }

  Future<void> saveReplyToMessageState() async {
    await PrefsInterface.saveReplyToMessageState(
      chat.guid,
      replyToMessage?.message.guid,
      replyToMessage?.partIndex,
    );
  }

  Future<void> loadReplyToMessageState() async {
    final data = await PrefsInterface.loadReplyToMessageState(chat.guid);
    if (data != null) {
      final messageGuid = data['messageGuid'] as String;
      final messagePart = data['messagePart'] as int;
      final message = Message.findOne(guid: messageGuid);
      if (message != null) {
        replyToMessage = MessageReplyContext(message, messagePart);
      }
    }
  }
}
