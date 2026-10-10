import 'dart:ui';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/message_holder.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/ui/chat/send_data.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

void showReplyThread(BuildContext context, Message message, MessagePart part, MessagesService service,
    ConversationViewController cvController) {
  final originatorPart = message.threadOriginatorGuid != null ? message.normalizedThreadPart : part.part;
  final _messages = service.struct.threads(message.threadOriginatorGuid ?? message.guid!, originatorPart);
  _messages.sort((a, b) => Message.sort(a, b, descending: false));
  _buildThreadView(_messages, originatorPart, cvController, context);
}

void showBookmarksThread(ConversationViewController cvController, BuildContext context) async {
  final _messages = (Database.messages.query(Message_.isBookmarked.equals(true))
        ..link(Message_.chat, Chat_.guid.equals(cvController.chat.guid))
        ..order(Message_.dateCreated, flags: Order.descending))
      .build()
      .find();
  if (_messages.isEmpty) {
    return showSnackbar("Error", "There are no bookmarked messages in this chat!");
  }
  for (Message m in _messages) {
    m.realAttachments;
    m.fetchAssociatedMessages();
  }
  _messages.sort((a, b) => Message.sort(a, b, descending: false));
  _buildThreadView(_messages, null, cvController, context);
}

void _buildThreadView(
    List<Message> _messages, int? originatorPart, ConversationViewController cvController, BuildContext context) {
  final controller = ScrollController();
  // Capture the conversation's theme before pushing the route — if adaptive
  // theming is active, context.theme is already the per-chat theme.
  final capturedTheme = context.theme;
  final capturedIsM3 = ThemeSvc.isMaterialYouActive(context);
  final capturedBubbleExt = capturedTheme.extensions[BubbleColors] as BubbleColors?;
  // Capture the ChatState so it can be re-provided inside the new route,
  // which has its own widget tree without a ChatStateScope.
  final capturedChatState = ChatsSvc.getOrCreateChatState(cvController.chat);
  Navigator.push(
    context,
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (routeCtx, animation, secondaryAnimation) {
        // Future.delayed(Duration.zero, () => controller.jumpTo(controller.position.maxScrollExtent));
        return FadeTransition(
            opacity: animation,
            child: ChatStateScope(
                chatState: capturedChatState,
                child: Theme(
                  data: capturedTheme.copyWith(
                    // in case some components still use legacy theming
                    primaryColor: capturedBubbleExt?.iMessageBubbleColor ?? capturedTheme.colorScheme.primary,
                    colorScheme: capturedTheme.colorScheme.copyWith(
                      primary: capturedBubbleExt?.iMessageBubbleColor ?? capturedTheme.colorScheme.primary,
                      onPrimary: capturedBubbleExt?.oniMessageBubbleColor ?? capturedTheme.colorScheme.onPrimary,
                      surface: capturedIsM3 ? null : capturedBubbleExt?.receivedBubbleColor,
                      onSurface: capturedIsM3 ? null : capturedBubbleExt?.onReceivedBubbleColor,
                    ),
                  ),
                  child: DeferredPointerHandler(
                    child: _ThreadOverlay(
                      messages: _messages,
                      originatorPart: originatorPart,
                      cvController: cvController,
                      scrollController: controller,
                      theme: capturedTheme,
                      parentContext: context,
                    ),
                  ),
                )));
      },
      fullscreenDialog: true,
      opaque: false,
    ),
  ).then((_) {
    if (kIsDesktop || kIsWeb) {
      cvController.focusNode.requestFocus();
    }
  });
}

/// The thread, drawn over the conversation the way iMessage does it: the
/// chat header stays visible and sharp above, the thread sits on a blurred
/// backdrop, an X closes it, and a "Reply" bar at the bottom starts a reply
/// to the thread's original message in the real composer.
class _ThreadOverlay extends StatefulWidget {
  const _ThreadOverlay({
    required this.messages,
    required this.originatorPart,
    required this.cvController,
    required this.scrollController,
    required this.theme,
    required this.parentContext,
  });

  final List<Message> messages;
  final int? originatorPart;
  final ConversationViewController cvController;
  final ScrollController scrollController;
  final ThemeData theme;
  final BuildContext parentContext;

  @override
  State<_ThreadOverlay> createState() => _ThreadOverlayState();
}

class _ThreadOverlayState extends State<_ThreadOverlay> {
  final TextEditingController _replyText = TextEditingController();
  final FocusNode _replyFocus = FocusNode();
  bool _sending = false;

  List<Message> get messages => widget.messages;
  int? get originatorPart => widget.originatorPart;
  ConversationViewController get cvController => widget.cvController;
  ThemeData get theme => widget.theme;
  bool get _isThread => originatorPart != null;

  @override
  void dispose() {
    _replyText.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(widget.parentContext).pop();

  /// Sends the typed text as a reply to the thread's original message, the
  /// way the iPhone's in-thread field does, then closes the thread.
  Future<void> _sendReply() async {
    final text = _replyText.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final original = messages.first;
    try {
      await cvController.send(SendData(
        attachments: const [],
        text: text,
        subject: "",
        replyGuid: original.threadOriginatorGuid ?? original.guid,
        replyPart: originatorPart,
      ));
    } finally {
      if (mounted) _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final iOS = SettingsSvc.settings.skin.value == Skins.iOS;
    final scheme = theme.colorScheme;
    final padding = MediaQuery.of(context).padding;
    // Height of the conversation header beneath, so the blur starts under it
    // (same formula as ConversationView._buildAppBar, without the banner).
    final headerHeight = padding.top +
        (kIsDesktop ? (!iOS ? 25 : 5) : 0) +
        90 * (iOS ? SettingsSvc.settings.avatarScale.value : 0) +
        (!iOS ? kToolbarHeight : 0);
    final blur = kIsDesktop && SettingsSvc.settings.windowEffect.value != WindowEffect.disabled ? 0.0 : 30.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _close,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              top: headerHeight,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: Container(color: scheme.surfaceContainerHighest.withValues(alpha: 0.3)),
                ),
              ),
            ),
            Column(
              children: [
                // Over the header: only the close control, at the right.
                SizedBox(
                  height: headerHeight,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: iOS ? 12 : 4, bottom: iOS ? 20 : 4),
                      child: iOS
                          ? Material(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.9),
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: _close,
                                child: SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(Icons.close, size: 22, color: scheme.onSurface),
                                ),
                              ),
                            )
                          // Sits where the header's overflow button is; the
                          // patch is the header's own colour so the X replaces
                          // that button instead of overlapping it.
                          : Container(
                              width: 48,
                              height: kToolbarHeight,
                              color: scheme.surfaceContainerHighest,
                              child: IconButton(
                                tooltip: "Close thread",
                                onPressed: _close,
                                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                              ),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: SingleChildScrollView(
                        controller: widget.scrollController,
                        child: Column(
                          children: messages
                              .mapIndexed((index, e) => GestureDetector(
                                    onTap: () {
                                      _close();
                                      if (originatorPart == null && iOS) {
                                        // pop twice to remove convo details page
                                        Navigator.of(widget.parentContext).pop();
                                      }
                                      MessagesSvc(cvController.chat.guid).jumpToMessage.call(e.guid!);
                                    },
                                    child: AbsorbPointer(
                                      absorbing: true,
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 5.0, right: 5.0),
                                        child: MessageHolder(
                                          cvController: cvController,
                                          message: messages[index],
                                          oldMessage: index > 0 ? messages[index - 1] : null,
                                          newMessage: index < messages.length - 1 ? messages[index + 1] : null,
                                          isReplyThread: true,
                                          replyPart: index == 0 ? originatorPart : null,
                                        ),
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isThread)
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, MediaQuery.of(context).viewInsets.bottom + padding.bottom + 10),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.only(left: 16, right: 4),
                      decoration: BoxDecoration(
                        color: iOS ? scheme.surface.withValues(alpha: 0.9) : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(22),
                        border: iOS ? Border.all(color: scheme.outlineVariant) : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyText,
                              focusNode: _replyFocus,
                              autofocus: true,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _sendReply(),
                              style: theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface),
                              cursorColor: scheme.primary,
                              decoration: InputDecoration(
                                isCollapsed: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                border: InputBorder.none,
                                hintText: "Reply",
                                hintStyle: theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _replyText,
                            builder: (_, v, __) => IconButton(
                              tooltip: "Send",
                              onPressed: v.text.trim().isEmpty || _sending ? null : _sendReply,
                              icon: Icon(iOS ? Icons.arrow_upward : Icons.send, color: scheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
