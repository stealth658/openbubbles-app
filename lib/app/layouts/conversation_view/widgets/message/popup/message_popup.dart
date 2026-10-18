import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/m3_popup_placement.dart';
import 'dart:math';
import 'dart:ui';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/actions/media_actions.dart'
    as popup_media_actions;
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/actions/message_actions.dart'
    as popup_message_actions;
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/actions/navigation_actions.dart'
    as popup_navigation_actions;
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/actions/text_actions.dart'
    as popup_text_actions;
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/details_menu_action.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_action_context.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/reaction_picker_clipper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/widgets/reaction_details.dart';
import 'package:bluebubbles/app/layouts/findmy/findmy_pin_clipper.dart';
import 'package:bluebubbles/app/wrappers/bb_app_bar.dart';
import 'package:bluebubbles/app/wrappers/bb_scaffold.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/shared/message_clone_scope.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' hide Emoji;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide BackButton;
import 'package:bluebubbles/database/models.dart' hide PayloadType;
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:sprung/sprung.dart';
import 'package:universal_io/io.dart';

export 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_action_context.dart'
    show MessagePopupServerDetails;

class MessagePopup extends StatefulWidget {
  final Offset childPosition;
  final Size size;
  final Widget child;
  final MessagePart part;
  final MessageState controller;
  final ConversationViewController cvController;
  final MessagePopupServerDetails serverDetails;
  /// OpenBubbles adds a third [emoji] argument for arbitrary-emoji tapbacks.
  final Function([String? type, int? part, String? emoji]) sendTapback;
  final BuildContext? Function() widthContext;

  const MessagePopup({
    super.key,
    required this.childPosition,
    required this.size,
    required this.child,
    required this.part,
    required this.controller,
    required this.cvController,
    required this.serverDetails,
    required this.sendTapback,
    required this.widthContext,
  });

  @override
  State<StatefulWidget> createState() => _MessagePopupState();
}

class _MessagePopupState extends State<MessagePopup> with SingleTickerProviderStateMixin, ThemeHelpers {
  /// Drive the whole menu's layout off the iOS-style flag, so the Material
  /// skin can opt into the iOS presentation.
  @override
  bool get iOS => iosStyleMessagePopup;

  /// Genuinely on the iOS skin. Used only where the value should track the
  /// real skin rather than the chosen menu style, such as the heavy backdrop
  /// blur, which looks wrong over Material surfaces.
  bool get _trueIOS => SettingsSvc.settings.skin.value == Skins.iOS;

  /// Material skin: same overlay layout, Material 3 surfaces. A dim scrim, a
  /// tonal tapback pill above the bubble and a menu card below it.
  bool get _m3 => SettingsSvc.settings.skin.value == Skins.Material;

  /// What the Material 3 menu adds to its rows' height: 8dp padding above and
  /// below them, plus the who-reacted header when the message has tapbacks.
  double get _menuPad => _m3 ? 16 + MenuReactors.heightFor(reactions) : 0;

  /// "More" was tapped: the menu lists every action instead of the first few.

  // Material keeps the bubble where it is and places the bar and the menu
  // around it (see M3PopupPlacement). Everything is in logical pixels from the
  // top of the screen.

  /// Where the bubble rests once the keyboard has gone. The position was
  /// measured with the keyboard still up, and the list slides down by the
  /// keyboard's height as it closes, so that height is added here.
  late final double _bubbleTop;
  late final double _topLimit;
  late final double _bottomLimit;
  double _barHeight = 56;
  M3PopupPlacement? _placement;

  double get _bubbleHeight => _measuredChildHeight ?? widget.size.height;

  double get _menuHeight => itemHeight * numberToShow + _menuPad;

  /// What the Material menu lists, as the iPhone's first menu does: the things
  /// done on the spot. Everything else is reached through "More…", which
  /// selects the message; the select-mode header carries the rest.
  static const _m3PrimaryActions = {
    DetailsMenuAction.Reply,
    DetailsMenuAction.UndoSend,
    DetailsMenuAction.Edit,
    DetailsMenuAction.CopyText,
    DetailsMenuAction.Save,
    DetailsMenuAction.Forward,
    DetailsMenuAction.Delete,
  };

  List<DetailsMenuActionWidget> get _m3Actions =>
      _allActions.where((a) => _m3PrimaryActions.contains(a.action)).toList();

  /// First layout: the rows of the menu, or as many as fit on the roomier side
  /// of the bubble.
  void _chooseRowsForM3() {
    final total = max(_m3Actions.length + 1, 1);
    final want = min(8, total);
    final fit = M3PopupPlacement.rowsThatFit(
        bubbleTop: _bubbleTop,
        bubbleHeight: _bubbleHeight,
        topLimit: _topLimit,
        bottomLimit: _bottomLimit,
        rowHeight: itemHeight,
        extra: _menuPad + _barHeight + M3PopupPlacement.gap);
    // Fewer than two rows fit only beside a bubble about as tall as the screen;
    // the menu then lies over it at full size.
    numberToShow = fit >= 2 ? min(want, fit) : want;
  }

  /// The tapback glyphs the picker can actually draw. `ReactionTypes.toList()`
  /// also carries EMOJI and STICKERBACK, which have no entry in
  /// reactionToEmoji and rendered as a literal "X" in the row.
  List<String> get _pickerReactions =>
      ReactionTypes.toList().where((i) => ReactionTypes.reactionToEmoji.containsKey(i)).toList();

  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    animationBehavior: AnimationBehavior.preserve,
  );
  final double itemHeight = kIsDesktop || kIsWeb ? 56 : 48;

  List<Message> reactions = [];
  late double messageOffset = Get.height - widget.childPosition.dy - widget.size.height;
  late double materialOffset = widget.childPosition.dy +
      EdgeInsets.fromViewPadding(
        View.of(context).viewInsets,
        View.of(context).devicePixelRatio,
      ).bottom;
  late int numberToShow = 5;
  late Chat? dmChat = ChatsSvc.allChats.firstWhereOrNull((chat) =>
      !chat.isGroup &&
      chat.handles.firstWhereOrNull((handle) => handle.address == message.handleRelation.target?.address) != null);
  String? selfReaction;
  String? currentlySelectedReaction = "init";
  final GlobalKey _childKey = GlobalKey();
  double? _measuredChildHeight;

  ConversationViewController get cvController => widget.cvController;

  MessagesService get service => MessagesSvc(chat.guid);

  Chat get chat => widget.cvController.chat;

  MessagePart get part => widget.part;

  Message get message => widget.controller.message;

  bool get isSent {
    final isSending = widget.controller.isSending.value;
    final hasError = widget.controller.hasError.value;
    return !isSending && !hasError;
  }

  bool get showDownload =>
      (isSent &&
          part.attachments.isNotEmpty &&
          part.attachments.where((element) => AttachmentsSvc.hasLocalFile(element)).isNotEmpty) ||
      isEmbeddedMedia;

  bool get showRefreshPreview =>
      message.isLegacyUrlPreview || message.payloadData?.type == PayloadType.url || message.isPhotoSlideshow;

  bool get canOpenInImageViewer =>
      part.attachments.length == 1 && part.attachments.first.mimeStart == "image";

  late bool isEmbeddedMedia = (message.balloonBundleId == "com.apple.Handwriting.HandwritingProvider" ||
          message.balloonBundleId == "com.apple.DigitalTouchBalloonProvider") &&
      File(message.interactiveMediaPath!).existsSync();

  bool get minSierra => widget.serverDetails.minSierra;

  bool get minBigSur => widget.serverDetails.minBigSur;

  bool get supportsOriginalDownload => widget.serverDetails.supportsOriginalDownload;

  BuildContext get widthContext => widget.widthContext.call() ?? context;

  @override
  void initState() {
    super.initState();
    controller.forward();
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final dpr = view.devicePixelRatio;
    _bubbleTop = widget.childPosition.dy + view.viewInsets.bottom / dpr;
    _topLimit = view.viewPadding.top / dpr + 8;
    _bottomLimit = view.physicalSize.height / dpr - max(view.viewPadding.bottom / dpr, 16) - 8;
    if (iOS) {
      final remainingHeight = max(Get.height - Get.statusBarHeight - 135 - widget.size.height, itemHeight);
      numberToShow = min(remainingHeight ~/ itemHeight, 5);
    } else {
      // Potentially make this dynamic in the future
      numberToShow = 5;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final measuredHeight = _childKey.currentContext?.size?.height;
      currentlySelectedReaction = null;
      reactions = getUniqueReactionMessages(message.associatedMessages
          .where((e) =>
              ReactionTypes.toList().contains(e.associatedMessageType?.replaceAll("-", "")) &&
              (e.associatedMessagePart ?? 0) == part.part)
          .toList());
      final selfMessage = reactions.firstWhereOrNull((e) => e.isFromMe!);
      final self = selfMessage?.associatedMessageType;
      if (!(self?.contains("-") ?? true)) {
        // OpenBubbles: an "emoji" tapback carries the actual emoji separately.
        selfReaction = self == ReactionTypes.EMOJI ? selfMessage!.associatedMessageEmoji : self;
        currentlySelectedReaction = selfReaction;
      }
      setState(() {
        if (_m3) {
          if (measuredHeight != null) _measuredChildHeight = measuredHeight;
          _chooseRowsForM3();
        } else if (iOS) {
          if (measuredHeight != null) {
            _measuredChildHeight = measuredHeight;
            final remainingHeight = max(Get.height - Get.statusBarHeight - 135 - measuredHeight, itemHeight);
            numberToShow = min(remainingHeight ~/ itemHeight, 5);
          }
          messageOffset = itemHeight * numberToShow + 40;
        }
      });
    });
  }

  void _remeasureChild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _childKey.currentContext?.size?.height;
      if (h != null && h != _measuredChildHeight) {
        setState(() => _measuredChildHeight = h);
      }
    });
  }

  /// OpenBubbles: send an arbitrary-emoji tapback (iOS 17+).
  void reactEmoji(String emoji) {
    HapticFeedback.lightImpact();
    widget.sendTapback(selfReaction == emoji ? "-${ReactionTypes.EMOJI}" : ReactionTypes.EMOJI, part.part, emoji);
    popDetails();
  }

  /// OpenBubbles: opens the full emoji picker so any emoji can be used as a
  /// tapback.
  void showEmojiReactionPicker() {
    final content = SizedBox(
      width: 512,
      child: Theme(
        data: context.theme.copyWith(canvasColor: Colors.transparent),
        child: EmojiPicker(
          scrollController: ScrollController(),
          config: Config(
            height: 512,
            checkPlatformCompatibility: true,
            emojiViewConfig: EmojiViewConfig(
              emojiSizeMax: 28,
              backgroundColor: Colors.transparent,
              columns: min(NavigationSvc.width(context), 512) ~/ 56,
              noRecents: Text("No Recents",
                  style: context.textTheme.headlineMedium!.copyWith(color: context.theme.colorScheme.outline)),
            ),
            skinToneConfig: const SkinToneConfig(enabled: false),
            categoryViewConfig: const CategoryViewConfig(
              backgroundColor: Colors.transparent,
              dividerColor: Colors.transparent,
            ),
            searchViewConfig: SearchViewConfig(
              backgroundColor: Colors.transparent,
              buttonIconColor: context.theme.colorScheme.outline,
            ),
          ),
          onEmojiSelected: (cat, emoji) {
            Navigator.of(context, rootNavigator: true).pop();
            reactEmoji(emoji.emoji);
          },
        ),
      ),
    );
    Get.dialog(
      AlertDialog(
        backgroundColor: context.theme.colorScheme.surfaceContainerHigh,
        content: content,
      ),
      name: 'Popup Menu',
    );
  }

  void popDetails({bool returnVal = true}) {
    Navigator.popUntil(context, (route) => route is! DialogRoute);
    Navigator.of(context).pop(returnVal);
  }

  @override
  Widget build(BuildContext context) {
    // Decide whether the tapback row needs to wrap to a second line by comparing its actual
    // content width (derived from the fixed per-item padding/icon sizes used below) against the
    // real horizontal space available at the picker's anchor position, rather than guessing from
    // overall screen width. widget.childPosition.dx already reflects any avatar space the bubble
    // was pushed past, so no avatar/group special-casing is needed here.
    final double screenWidth = NavigationSvc.width(widthContext);
    const double reactionPickerEdgeMargin = 15;
    final double reactionPickerAvailableWidth = message.isFromMe!
        ? screenWidth - reactionPickerEdgeMargin - reactionPickerEdgeMargin
        : screenWidth - (widget.childPosition.dx + 10) - reactionPickerEdgeMargin;
    // icon/emoji + its fixed padding, see item build below (Material 3: 48dp targets)
    final double reactionItemWidth = _m3 ? 48.0 : (iOS ? 47.0 : 44.0);
    // Count what is actually rendered: the drawable glyphs plus the trailing
    // "more" smiley. Counting ReactionTypes.toList() (8) instead of the 6 + 1
    // on screen over-estimated the row and wrapped it to two lines for no
    // reason.
    final int reactionItemCount = _pickerReactions.length + 1;
    // + container padding
    final double reactionRowContentWidth = reactionItemWidth * reactionItemCount + 10;
    // The picker is anchored at the bubble's left edge, which in a group chat
    // sits past the avatar and can push the row off screen. Allow it to slide
    // left to the screen margin before deciding it has to wrap.
    final double reactionPickerLeft = !message.isFromMe!
        ? min(widget.childPosition.dx + 10, screenWidth - reactionPickerEdgeMargin - reactionRowContentWidth)
            .clamp(reactionPickerEdgeMargin, double.infinity)
        : reactionPickerEdgeMargin;
    final double shiftedAvailableWidth = screenWidth - reactionPickerLeft - reactionPickerEdgeMargin;
    bool narrowScreen = reactionRowContentWidth > max(reactionPickerAvailableWidth, shiftedAvailableWidth);

    // Material: the bubble stays put; the bar and the menu go above or below it.
    _barHeight = narrowScreen ? 104 : 56;
    final placement = M3PopupPlacement.compute(
        bubbleTop: _bubbleTop,
        bubbleHeight: _bubbleHeight,
        menuHeight: _menuHeight,
        barHeight: _barHeight,
        topLimit: _topLimit,
        bottomLimit: _bottomLimit);
    _placement = placement;

    return Theme(
      data: context.theme.copyWith(
        // in case some components still use legacy theming
        primaryColor: context.theme.colorScheme.bubble(context, chat.isIMessage),
        colorScheme: context.theme.colorScheme.copyWith(
          primary: context.theme.colorScheme.bubble(context, chat.isIMessage),
          onPrimary: context.theme.colorScheme.onBubble(context, chat.isIMessage),
          surface: ThemeSvc.isMaterialYouActive(context)
              ? null
              : (context.theme.extensions[BubbleColors] as BubbleColors?)?.receivedBubbleColor,
          onSurface: ThemeSvc.isMaterialYouActive(context)
              ? null
              : (context.theme.extensions[BubbleColors] as BubbleColors?)?.onReceivedBubbleColor,
        ),
      ),
      child: TitleBarWrapper(
          child: BBScaffold(
              extendBodyBehindAppBar: true,
              safeAreaLeft: false,
              safeAreaRight: false,
              // The popup opens over a still-collapsing keyboard. Keep the body
              // full-screen and its bottom edge fixed so Positioned offsets are
              // screen-anchored and don't ride the inset animation down.
              resizeToAvoidBottomInset: false,
              safeAreaMaintainBottomViewPadding: true,
              backgroundColor: kIsDesktop && iOS && SettingsSvc.settings.windowEffect.value != WindowEffect.disabled
                  ? context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
                  : Colors.transparent,
              appBar: iOS
                  ? null
                  : BBAppBar(
                      backgroundColor: context.theme.colorScheme.surface.oppositeLightenOrDarken(5),
                      automaticallyImplyLeading: false,
                      leadingWidth: 40,
                      toolbarHeight: kIsDesktop ? 80 : 50,
                      leading: Padding(
                        padding: EdgeInsets.only(top: kIsDesktop ? 20 : 0, left: 10.0),
                        child: BackButton(
                          color: context.theme.colorScheme.onSurface,
                          onPressed: () {
                            popDetails();
                            return true;
                          },
                        ),
                      ),
                      actions: buildMaterialDetailsMenu(context),
                    ),
              body: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: popDetails,
                    child: _m3
                        // Material 3: a plain scrim, no blur.
                        ? Container(color: context.theme.colorScheme.scrim.withValues(alpha: 0.4))
                        : iOS
                        ? (SettingsSvc.settings.highPerfMode.value
                            ? Container(color: context.theme.colorScheme.surface.withValues(alpha: 0.5))
                            : BackdropFilter(
                                // The iOS skin's heavy 30px blur washes out
                                // Material surfaces, so the opt-in Material
                                // menu gets a light blur plus a scrim instead,
                                // which keeps the message readable behind it.
                                filter: ImageFilter.blur(
                                    sigmaX:
                                        kIsDesktop && SettingsSvc.settings.windowEffect.value != WindowEffect.disabled
                                            ? 10
                                            : (_trueIOS ? 30 : 6),
                                    sigmaY:
                                        kIsDesktop && SettingsSvc.settings.windowEffect.value != WindowEffect.disabled
                                            ? 10
                                            : (_trueIOS ? 30 : 6)),
                                child: Container(
                                  color: _trueIOS
                                      ? Colors.transparent.withValues(alpha: 0.1)
                                      : context.theme.colorScheme.scrim.withValues(alpha: 0.35),
                                ),
                              ))
                        : null,
                  ),
                  if (iOS)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutBack,
                      left: widget.childPosition.dx,
                      top: _m3 ? _bubbleTop : null,
                      bottom: _m3 ? null : messageOffset,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.8, end: 1),
                        curve: Curves.easeOutBack,
                        duration: const Duration(milliseconds: 500),
                        child: NotificationListener<SizeChangedLayoutNotification>(
                          onNotification: (_) {
                            _remeasureChild();
                            return false;
                          },
                          child: SizeChangedLayoutNotifier(
                            child: ConstrainedBox(
                              key: _childKey,
                              constraints: BoxConstraints(maxWidth: widget.size.width),
                              // Marked as a clone so anything inside that
                              // reacts to shared state by doing work (URL
                              // preview refreshes, say) knows not to — this
                              // copy and the real bubble both see every signal.
                              child: MessageCloneScope(
                                child: MessageStateScope(
                                  messageState: widget.controller,
                                  child: widget.child,
                                ),
                              ),
                            ),
                          ),
                        ),
                        builder: (context, size, child) {
                          return Transform.scale(
                            scale: size.clamp(1, double.infinity),
                            alignment: message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
                            child: child,
                          );
                        },
                      ),
                    ),
                  // Material lists who reacted at the top of the menu card instead.
                  if (iOS && !_m3)
                    Positioned(
                      top: 40,
                      left: 15,
                      right: 15,
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 500),
                        curve: Sprung.underDamped,
                        alignment: Alignment.center,
                        child: reactions.isNotEmpty ? ReactionDetails(reactions: reactions) : const SizedBox.shrink(),
                      ),
                    ),
                  if (SettingsSvc.settings.enablePrivateAPI.value &&
                          isSent &&
                          minSierra &&
                          chat.isIMessage &&
                          message.dateScheduled == null)
                    Positioned(
                      top: _m3 ? placement.barTop : null,
                      bottom: _m3
                          ? null
                          : (iOS
                                  ? itemHeight * numberToShow + 35 + (_measuredChildHeight ?? widget.size.height)
                                  : context.height - materialOffset)
                              .clamp(0, context.height - (narrowScreen ? 200 : 125)),
                      right: message.isFromMe! ? 15 : null,
                      left: !message.isFromMe! ? reactionPickerLeft : null,
                      child: AnimatedSize(
                        curve: Curves.easeInOut,
                        alignment: message.isFromMe! ? Alignment.centerRight : Alignment.centerLeft,
                        duration: const Duration(milliseconds: 250),
                        child: currentlySelectedReaction == "init"
                            ? SizedBox(height: _m3 ? 56 : 80)
                            : _m3
                            ? _m3TapbackBar(context, narrowScreen)
                            : ClipShadowPath(
                                shadow: iOS
                                    ? BoxShadow(
                                        color: context.theme.colorScheme.surfaceContainerHighest
                                            .withAlpha(iOS ? 150 : 255)
                                            .lightenOrDarken(iOS ? 0 : 10))
                                    : BoxShadow(
                                        color: context.theme.colorScheme.shadow,
                                        blurRadius: 2,
                                      ),
                                clipper: ReactionPickerClipper(
                                  messageSize: widget.size,
                                  isFromMe: message.isFromMe!,
                                ),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                  child: Container(
                                    padding: const EdgeInsets.all(5).add(const EdgeInsets.only(bottom: 15)),
                                    color: context.theme.colorScheme.surfaceContainerHighest
                                        .withAlpha(iOS ? 150 : 255)
                                        .lightenOrDarken(iOS ? 0 : 10),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(narrowScreen ? 2 : 1, (index) {
                                          return Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment: MainAxisAlignment.start,
                                            children: _pickerReactions
                                                .slice(narrowScreen && index == 1 ? 3 : 0,
                                                    narrowScreen && index == 0 ? 3 : null)
                                                .map<Widget>((e) {
                                              return Padding(
                                                padding: iOS
                                                    ? const EdgeInsets.all(5.0)
                                                    : const EdgeInsets.symmetric(horizontal: 5),
                                                child: Material(
                                                  color: currentlySelectedReaction == e
                                                      ? context.theme.colorScheme.primary
                                                      : Colors.transparent,
                                                  borderRadius: BorderRadius.circular(20),
                                                  child: SizedBox(
                                                    width: iOS ? 35 : null,
                                                    height: iOS ? 35 : null,
                                                    child: InkWell(
                                                      borderRadius: BorderRadius.circular(20),
                                                      onTap: () {
                                                        if (currentlySelectedReaction == e) {
                                                          currentlySelectedReaction = null;
                                                        } else {
                                                          currentlySelectedReaction = e;
                                                        }
                                                        setState(() {});
                                                        HapticFeedback.lightImpact();
                                                        widget.sendTapback(selfReaction == e ? "-$e" : e, part.part);
                                                        popDetails();
                                                      },
                                                      child: Padding(
                                                        padding: const EdgeInsets.all(6.5)
                                                            .add(EdgeInsets.only(right: e == "emphasize" ? 2.5 : 0)),
                                                        child: iOS
                                                            ? SvgPicture.asset(
                                                                'assets/reactions/$e-black.svg',
                                                                colorFilter: ColorFilter.mode(
                                                                    e == "love" && currentlySelectedReaction == e
                                                                        ? Colors.pink
                                                                        : (currentlySelectedReaction == e
                                                                            ? context.theme.colorScheme.onPrimary
                                                                            : context.theme.colorScheme.outline),
                                                                    BlendMode.srcIn),
                                                              )
                                                            : Center(
                                                                child: Builder(builder: (context) {
                                                                  final text = Text(
                                                                    ReactionTypes.reactionToEmoji[e] ?? "X",
                                                                    style: const TextStyle(
                                                                        fontSize: 18, fontFamily: 'Apple Color Emoji'),
                                                                    textAlign: TextAlign.center,
                                                                  );
                                                                  // rotate thumbs down to match iOS
                                                                  if (e == "dislike") {
                                                                    return Transform(
                                                                      transform: Matrix4.identity()..rotateY(pi),
                                                                      alignment: FractionalOffset.center,
                                                                      child: text,
                                                                    );
                                                                  }
                                                                  return text;
                                                                }),
                                                              ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }).toList()
                                              // OpenBubbles: arbitrary-emoji tapbacks.
                                              ..addAll((narrowScreen && index == 0)
                                                  ? const <Widget>[]
                                                  : [
                                                      Padding(
                                                        padding: iOS
                                                            ? const EdgeInsets.all(5.0)
                                                            : const EdgeInsets.symmetric(horizontal: 5),
                                                        child: Material(
                                                          color: Colors.transparent,
                                                          borderRadius: BorderRadius.circular(20),
                                                          child: SizedBox(
                                                            width: iOS ? 35 : null,
                                                            height: iOS ? 35 : null,
                                                            child: InkWell(
                                                              borderRadius: BorderRadius.circular(20),
                                                              onTap: showEmojiReactionPicker,
                                                              child: Padding(
                                                                padding: const EdgeInsets.all(6.5),
                                                                child: Icon(
                                                                  cupertino.CupertinoIcons.smiley,
                                                                  size: 18,
                                                                  color: context.theme.colorScheme.outline,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ]),
                                          );
                                        })),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  if (iOS)
                    Positioned(
                      right: message.isFromMe! ? 15 : null,
                      left: !message.isFromMe! ? widget.childPosition.dx + 10 : null,
                      top: _m3 ? placement.menuTop : null,
                      bottom: _m3 ? null : 30,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.8, end: 1),
                        curve: Curves.easeOutBack,
                        duration: const Duration(milliseconds: 400),
                        child: FadeTransition(
                          opacity: CurvedAnimation(
                            parent: controller,
                            curve: const Interval(0.0, .9, curve: Curves.ease),
                            reverseCurve: Curves.easeInCubic,
                          ),
                          child: Column(
                            crossAxisAlignment:
                                _m3 && message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!_m3) const SizedBox(height: 5),
                              buildDetailsMenu(context),
                            ],
                          ),
                        ),
                        builder: (context, size, child) {
                          return Transform.scale(
                            scale: size,
                            child: child,
                          );
                        },
                      ),
                    ),
                  if (!iOS && SettingsSvc.settings.enablePrivateAPI.value && minBigSur && chat.isIMessage && isSent)
                    Positioned(
                      left: !message.isFromMe!
                          ? widget.childPosition.dx + widget.size.width + (reactions.isNotEmpty ? 20 : 5)
                          : widget.childPosition.dx - 55,
                      top: materialOffset,
                      child: Material(
                        color: context.theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          width: 35,
                          height: 35,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => popup_navigation_actions.reply(_buildActionContext(DetailsMenuAction.Reply)),
                            child: const Center(child: Icon(Icons.reply, size: 20)),
                          ),
                        ),
                      ),
                    ),
                ],
              ))),
    );
  }

  MessagePopupActionContext _buildActionContext(DetailsMenuAction action) {
    return MessagePopupActionContext(
      context: context,
      widthContext: widthContext,
      cvController: cvController,
      messageState: widget.controller,
      message: message,
      part: part,
      chat: chat,
      service: service,
      serverDetails: widget.serverDetails,
      action: action,
      popDetails: ({bool returnVal = true}) => popDetails(returnVal: returnVal),
      showSnack: showSnackbar,
      dmChat: dmChat,
      isEmbeddedMedia: isEmbeddedMedia,
    );
  }

  List<DetailsMenuActionWidget> get _allActionsInUserOrder {
    final canEdit = (message.dateCreated?.toUtc().isWithin(DateTime.now().toUtc(), minutes: 15) ?? false);
    final canUnsend = (message.dateCreated?.toUtc().isWithin(DateTime.now().toUtc(), minutes: 2) ?? false);
    return [
      if (SettingsSvc.settings.enablePrivateAPI.value && minBigSur && chat.isIMessage && isSent)
        DetailsMenuActionWidget(
          onTap: () => popup_navigation_actions.reply(_buildActionContext(DetailsMenuAction.Reply)),
          action: DetailsMenuAction.Reply,
        ),
      if (showDownload)
        DetailsMenuActionWidget(
          onTap: () => popup_media_actions.downloadAttachment(_buildActionContext(DetailsMenuAction.Save)),
          action: DetailsMenuAction.Save,
        ),
      if (canOpenInImageViewer)
        DetailsMenuActionWidget(
          onTap: () => popup_media_actions.openInImageViewer(_buildActionContext(DetailsMenuAction.OpenInImageViewer)),
          action: DetailsMenuAction.OpenInImageViewer,
        ),
      if ((part.text?.hasUrl ?? false) && !LifecycleSvc.isBubble)
        DetailsMenuActionWidget(
          onTap: () => popup_text_actions.openLink(_buildActionContext(DetailsMenuAction.OpenInBrowser)),
          action: DetailsMenuAction.OpenInBrowser,
        ),
      if (showDownload && part.attachments.firstOrNull?.webUrl != null)
        DetailsMenuActionWidget(
          onTap: () => popup_media_actions.openAttachmentWeb(_buildActionContext(DetailsMenuAction.OpenInNewTab)),
          action: DetailsMenuAction.OpenInNewTab,
        ),
      if (!isNullOrEmptyString(part.fullText))
        DetailsMenuActionWidget(
          onTap: () => popup_text_actions.copyText(_buildActionContext(DetailsMenuAction.CopyText)),
          action: DetailsMenuAction.CopyText,
        ),
      if (showDownload)
        DetailsMenuActionWidget(
          onTap: () => popup_media_actions.copyAttachment(_buildActionContext(DetailsMenuAction.CopyAttachment)),
          action: DetailsMenuAction.CopyAttachment,
        ),
      if (showDownload &&
          supportsOriginalDownload &&
          part.attachments
              .where((element) =>
                  (element.uti?.contains("heic") ?? false) ||
                  (element.uti?.contains("heif") ?? false) ||
                  (element.uti?.contains("quicktime") ?? false) ||
                  (element.uti?.contains("coreaudio") ?? false) ||
                  (element.uti?.contains("tiff") ?? false))
              .isNotEmpty)
        DetailsMenuActionWidget(
          onTap: () =>
              popup_media_actions.downloadOriginalAttachments(_buildActionContext(DetailsMenuAction.SaveOriginal)),
          action: DetailsMenuAction.SaveOriginal,
        ),
      if (showDownload && part.attachments.where((e) => e.hasLivePhoto).isNotEmpty)
        DetailsMenuActionWidget(
          onTap: () => popup_media_actions.downloadLivePhoto(_buildActionContext(DetailsMenuAction.SaveLivePhoto)),
          action: DetailsMenuAction.SaveLivePhoto,
        ),
      if (chat.isGroup && !message.isFromMe! && dmChat != null && !LifecycleSvc.isBubble)
        DetailsMenuActionWidget(
          onTap: () => popup_navigation_actions.openDm(_buildActionContext(DetailsMenuAction.OpenDirectMessage)),
          action: DetailsMenuAction.OpenDirectMessage,
        ),
      if (message.threadOriginatorGuid != null ||
          service.struct.threads(message.guid!, part.part, returnOriginator: false).isNotEmpty)
        DetailsMenuActionWidget(
          onTap: () => popup_navigation_actions.showThread(_buildActionContext(DetailsMenuAction.ViewThread)),
          action: DetailsMenuAction.ViewThread,
        ),
      if (part.attachments.isNotEmpty || !isNullOrEmpty(part.text))
        DetailsMenuActionWidget(
          onTap: () => popup_media_actions.sharePart(_buildActionContext(DetailsMenuAction.Share)),
          action: DetailsMenuAction.Share,
        ),
      DetailsMenuActionWidget(
        onTap: () => popup_message_actions.remindLater(_buildActionContext(DetailsMenuAction.RemindLater)),
        action: DetailsMenuAction.RemindLater,
      ),
      if (!message.isFromMe! &&
          message.handleRelation.target != null &&
          message.handleRelation.target!.contactsV2.isEmpty)
        DetailsMenuActionWidget(
          onTap: () => popup_message_actions.createContact(_buildActionContext(DetailsMenuAction.CreateContact)),
          action: DetailsMenuAction.CreateContact,
        ),
      // Undo Send is only offered while Apple still allows it (two minutes);
      // a greyed "too old" entry was noise.
      if (backend.canEditUnsend() &&
          message.isFromMe! &&
          !widget.controller.isSending.value &&
          message.dateScheduled == null &&
          canUnsend)
        DetailsMenuActionWidget(
          onTap: () => popup_message_actions.unsend(_buildActionContext(DetailsMenuAction.UndoSend)),
          customTitle: 'Undo Send',
          action: DetailsMenuAction.UndoSend,
        ),
      if (message.isFromMe! && widget.controller.isSending.value && OutgoingMsgHandler.hasPendingMessage(message.guid!))
        DetailsMenuActionWidget(
          onTap: () => popup_message_actions.cancelSend(_buildActionContext(DetailsMenuAction.CancelSend)),
          action: DetailsMenuAction.CancelSend,
        ),
      if (backend.canEditUnsend() &&
          message.isFromMe! &&
          !widget.controller.isSending.value &&
          message.dateScheduled == null &&
          (part.text?.isNotEmpty ?? false))
        DetailsMenuActionWidget(
          onTap: () => popup_message_actions.edit(_buildActionContext(DetailsMenuAction.Edit)),
          customTitle: canEdit ? 'Edit' : 'Edit (too old)',
          shouldDisableBtn: !canEdit,
          action: DetailsMenuAction.Edit,
        ),
      if (!LifecycleSvc.isBubble && !message.isInteractive)
        DetailsMenuActionWidget(
          onTap: () => popup_navigation_actions.forward(_buildActionContext(DetailsMenuAction.Forward)),
          action: DetailsMenuAction.Forward,
        ),
      if (chat.isGroup && !message.isFromMe! && dmChat == null && !LifecycleSvc.isBubble)
        DetailsMenuActionWidget(
          onTap: () => popup_navigation_actions.newConvo(_buildActionContext(DetailsMenuAction.StartConversation)),
          action: DetailsMenuAction.StartConversation,
        ),
      if (!isNullOrEmptyString(part.fullText))
        DetailsMenuActionWidget(
          onTap: () => popup_text_actions.copySelection(_buildActionContext(DetailsMenuAction.CopySelection)),
          action: DetailsMenuAction.CopySelection,
        ),
      DetailsMenuActionWidget(
        onTap: () => popup_message_actions.delete(_buildActionContext(DetailsMenuAction.Delete)),
        action: DetailsMenuAction.Delete,
      ),
      DetailsMenuActionWidget(
        onTap: () => popup_message_actions.toggleBookmark(_buildActionContext(DetailsMenuAction.Bookmark)),
        action: DetailsMenuAction.Bookmark,
        customTitle: message.isBookmarked ? "Remove Bookmark" : "Add Bookmark",
      ),
      DetailsMenuActionWidget(
        onTap: () => popup_message_actions.selectMultiple(_buildActionContext(DetailsMenuAction.SelectMultiple)),
        action: DetailsMenuAction.SelectMultiple,
      ),
      DetailsMenuActionWidget(
        onTap: () => popup_message_actions.messageInfo(_buildActionContext(DetailsMenuAction.MessageInfo)),
        action: DetailsMenuAction.MessageInfo,
      ),
    ].where((a) => a.action.isPlatformSupported).sorted((a, b) => SettingsSvc.settings.detailsMenuActions
        .indexOf(a.action)
        .compareTo(SettingsSvc.settings.detailsMenuActions.indexOf(b.action)));
  }

  /// The user's order, with iMessage's priorities applied on top: Reply,
  /// then Undo Send and Edit while they are still possible, lead the menu;
  /// Remind Later and anything disabled go to the end, under "More".
  List<DetailsMenuActionWidget> get _allActions {
    final actions = _allActionsInUserOrder;
    bool leads(DetailsMenuActionWidget a) =>
        (a.action == DetailsMenuAction.Reply || a.action == DetailsMenuAction.UndoSend || a.action == DetailsMenuAction.Edit) &&
        !(a.shouldDisableBtn ?? false);
    bool trails(DetailsMenuActionWidget a) => a.action == DetailsMenuAction.RemindLater || (a.shouldDisableBtn ?? false);
    const leadOrder = [DetailsMenuAction.Reply, DetailsMenuAction.UndoSend, DetailsMenuAction.Edit];
    final lead = actions.where(leads).toList()
      ..sort((a, b) => leadOrder.indexOf(a.action).compareTo(leadOrder.indexOf(b.action)));
    final middle = actions.where((a) => !leads(a) && !trails(a)).toList();
    final trail = actions.where(trails).toList();
    return [...lead, ...middle, ...trail];
  }

  // ---- Material 3 presentation ---------------------------------------------

  /// Tapback bar: a tonal pill with 48dp targets. The current choice sits on a
  /// secondary-container circle; the last target opens the emoji picker. Icons
  /// are iMessage glyphs or emoji according to "iOS-Style Tapback Icons".
  Widget _m3TapbackBar(BuildContext context, bool wrap) {
    final scheme = context.theme.colorScheme;

    Widget target({required Widget child, required VoidCallback onTap, bool selected = false}) => SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Material(
              color: selected ? scheme.secondaryContainer : Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(width: 40, height: 40, child: Center(child: child)),
              ),
            ),
          ),
        );

    Widget glyph(String e, bool selected) {
      if (useIosTapbacks) {
        return Padding(
          padding: EdgeInsets.only(right: e == "emphasize" ? 2 : 0),
          child: SvgPicture.asset(
            'assets/reactions/$e-black.svg',
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(
                e == "love" && selected
                    ? Colors.pink
                    : (selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                BlendMode.srcIn),
          ),
        );
      }
      final text = Text(
        ReactionTypes.reactionToEmoji[e] ?? "",
        style: const TextStyle(fontSize: 22, fontFamily: 'Apple Color Emoji'),
        textAlign: TextAlign.center,
      );
      // rotate thumbs down to match iOS
      return e == "dislike"
          ? Transform(transform: Matrix4.identity()..rotateY(pi), alignment: FractionalOffset.center, child: text)
          : text;
    }

    final items = <Widget>[
      for (final e in _pickerReactions)
        target(
          selected: currentlySelectedReaction == e,
          onTap: () {
            setState(() => currentlySelectedReaction = currentlySelectedReaction == e ? null : e);
            HapticFeedback.lightImpact();
            widget.sendTapback(selfReaction == e ? "-$e" : e, part.part);
            popDetails();
          },
          child: glyph(e, currentlySelectedReaction == e),
        ),
      // OpenBubbles: arbitrary-emoji tapbacks.
      target(
        onTap: showEmojiReactionPicker,
        child: Icon(Icons.add_reaction_outlined, size: 22, color: scheme.onSurfaceVariant),
      ),
    ];
    final split = (items.length / 2).ceil();
    final rows = wrap ? [items.sublist(0, split), items.sublist(split)] : [items];

    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shadowColor: scheme.shadow,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: message.isFromMe! ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [for (final r in rows) Row(mainAxisSize: MainAxisSize.min, children: r)],
        ),
      ),
    );
  }

  /// Options as a Material 3 menu: container tone, level-2 elevation, leading
  /// icon then label, one row per action.
  /// "More…": select this message, as on the iPhone. Delete and Forward sit in
  /// the select-mode header, with the rarer actions under its overflow.
  void _selectThisMessage() {
    HapticFeedback.selectionClick();
    widget.cvController.inSelectMode.value = true;
    if (!widget.cvController.selected.any((m) => m.guid == message.guid)) {
      widget.cvController.selected.add(message);
    }
    popDetails(returnVal: false);
  }

  Widget _m3Menu(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final all = _m3Actions;
    final visible = all.length + 1 > numberToShow ? all.sublist(0, max(numberToShow - 1, 0)) : all;

    Widget row(IconData icon, String label, VoidCallback? onTap, {bool disabled = false}) => InkWell(
          onTap: disabled ? null : onTap,
          child: SizedBox(
            height: itemHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(icon,
                      size: 24, color: disabled ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.theme.textTheme.bodyLarge?.copyWith(
                          color: disabled ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    final double maxWidth = min(280.0, NavigationSvc.width(widthContext) * 4 / 5);
    return Material(
      color: scheme.surfaceContainer,
      elevation: 3,
      shadowColor: scheme.shadow,
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            minWidth: min(200.0, maxWidth), maxWidth: maxWidth, maxHeight: itemHeight * numberToShow + _menuPad),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Who reacted, above the actions.
              MenuReactors(reactions: reactions),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final a in visible)
                        row(a.nonIosIcon, a.title, a.onTap,
                            disabled: a.action == DetailsMenuAction.Edit &&
                                !(message.dateCreated?.toUtc().isWithin(DateTime.now().toUtc(), minutes: 15) ?? false)),
                      row(Icons.more_horiz, "More…", _selectThisMessage),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildDetailsMenu(BuildContext context) {
    if (_m3) return _m3Menu(context);
    double maxMenuWidth =
        min(max(NavigationSvc.width(widthContext) * 3 / 5, 200), NavigationSvc.width(widthContext) * 4 / 5);

    List<DetailsMenuActionWidget> allActions = _allActions;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          color: context.theme.colorScheme.surfaceContainerHighest.withAlpha(150),
          width: maxMenuWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: allActions.cast<CustomDetailsMenuActionWidget>().sublist(0, numberToShow - 1)
              ..add(
                CustomDetailsMenuActionWidget(
                  onTap: () async {
                    Widget content = Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: allActions.sublist(numberToShow - 1),
                    );
                    showBBDialog(
                      useRootNavigator: false,
                      context: context,
                      content: content,
                    );
                  },
                  title: 'More...',
                  iosIcon: cupertino.CupertinoIcons.ellipsis,
                  nonIosIcon: Icons.more_vert,
                ),
              ),
          ),
        ),
      ),
    );
  }

  List<Widget> buildMaterialDetailsMenu(BuildContext context) {
    List<DetailsMenuActionWidget> allActions = _allActions;

    return [
      ...allActions.slice(0, numberToShow - 1).map((action) {
        bool isDisabled = false;
        if (action.action == DetailsMenuAction.Edit) {
          isDisabled = !((message.dateCreated?.toUtc().isWithin(DateTime.now().toUtc(), minutes: 15) ?? false));
        }

        Color color = isDisabled
            ? context.theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
            : context.theme.colorScheme.onSurfaceVariant;
        return Padding(
            padding: EdgeInsets.only(top: kIsDesktop ? 20 : 0),
            child: IconButton(
              icon: Icon(action.nonIosIcon, color: color),
              onPressed: isDisabled ? null : action.onTap,
              tooltip: action.title,
            ));
      }),
      Padding(
          padding: EdgeInsets.only(top: kIsDesktop ? 20 : 0),
          child: PopupMenuButton<int>(
              color: context.theme.colorScheme.surfaceContainerHighest,
              shape: SettingsSvc.settings.skin.value != Skins.Material
                  ? const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20.0)),
                    )
                  : null,
              onSelected: (int value) {
                allActions[value + numberToShow - 1].onTap?.call();
              },
              itemBuilder: (context) {
                return allActions.slice(numberToShow - 1).mapIndexed((index, action) {
                  return PopupMenuItem(
                    value: index,
                    child: Text(
                      action.title,
                      style: context.textTheme.bodyLarge!.apply(color: context.theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }).toList();
              }))
    ];
  }
}
