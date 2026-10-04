import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// One tappable suggestion. Tap sends it as a message; long-press drops it into
/// the text field instead so it can be edited first.
///
/// Styled as a small outlined pill in the composer's own palette so it reads as
/// part of the input area rather than as a message bubble.
class SuggestionChip extends StatelessWidget {
  const SuggestionChip({
    super.key,
    required this.controller,
    required this.text,
    this.onTap,
    this.label,
  });

  final ConversationViewController controller;
  final String text;
  final VoidCallback? onTap;

  /// Optional reactive label override (used by "Jump to oldest unread" while it
  /// is working). Falls back to [text].
  final String Function()? label;

  void _send() {
    OutgoingMsgHandler.queue(OutgoingMessage(
      chat: controller.chat,
      message: Message(
        text: text,
        dateCreated: DateTime.now(),
        hasAttachments: false,
        isFromMe: true,
        handleId: 0,
      ),
    ));
  }

  void _insert() {
    controller.textController.text = text;
    controller.textController.selection = TextSelection.collapsed(offset: text.length);
    controller.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final style = context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: StadiumBorder(side: BorderSide(color: scheme.outlineVariant, width: 1)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap ?? _send,
          onLongPress: onTap == null ? _insert : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Center(
              widthFactor: 1,
              child: label == null
                  ? RichText(text: TextSpan(children: MessageHelper.buildEmojiText(text, style)))
                  : Obx(() => RichText(text: TextSpan(children: MessageHelper.buildEmojiText(label!(), style)))),
            ),
          ),
        ),
      ),
    );
  }
}

/// The suggestion strip that sits inside the composer, above the text row.
///
/// Shows while there is something to suggest and the draft is empty. The moment
/// the user types (or attaches something) it collapses, and it comes back when
/// the field is cleared. A small sparkle marks the row as suggestions rather
/// than content.
class ComposerSuggestions extends StatelessWidget {
  const ComposerSuggestions({super.key, required this.controller});

  final ConversationViewController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller.textController,
      builder: (context, draft, _) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller.subjectTextController,
        builder: (context, subject, _) => Obx(() {
          // In inline mode the replies are drawn inside the text field; only the
          // quick actions stay in the strip.
          final bool inline = SettingsSvc.settings.inlineReplySuggestions.value;
          final List<String> replies = inline ? const [] : controller.suggestedReplies;
          final actions = controller.suggestedActions;
          final bool typing = draft.text.trim().isNotEmpty || subject.text.trim().isNotEmpty;
          final bool visible = !typing &&
              controller.pickedAttachments.isEmpty &&
              (replies.isNotEmpty || actions.isNotEmpty);

          return AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.bottomCenter,
            child: !visible
                ? const SizedBox(width: double.infinity, height: 0)
                : Padding(
                    padding: const EdgeInsets.only(left: 14, right: 10, bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome, size: 15, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 34,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: ThemeSwitcher.getScrollPhysics(),
                              children: [
                                ...replies.map((s) => SuggestionChip(controller: controller, text: s)),
                                ...actions.values,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        }),
      ),
    );
  }
}
