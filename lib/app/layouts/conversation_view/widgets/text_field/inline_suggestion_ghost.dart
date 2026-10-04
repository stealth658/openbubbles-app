import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Decides whether the ghost-text suggestion should be shown in the text field.
/// Called from inside the composer's reactive builders, so reading the Rx values
/// here is what registers them.
bool inlineSuggestionShouldShow(ConversationViewController? controller, TextEditingValue draft, bool isRecording) {
  if (controller == null) return false;
  if (!SettingsSvc.settings.smartReply.value || !SettingsSvc.settings.inlineReplySuggestions.value) return false;
  if (isRecording) return false;
  if (draft.text.isNotEmpty) return false;
  if (controller.subjectTextController.text.isNotEmpty) return false;
  if (controller.pickedAttachments.isNotEmpty) return false;
  return controller.suggestedReplies.isNotEmpty;
}

/// One reply suggestion drawn where the placeholder would be, in the placeholder
/// colour, with a sparkle in front so it reads as a suggestion and not as text
/// already typed. Tap puts it into the field for editing (it never sends on its
/// own); a horizontal swipe moves to the next suggestion. A small service tag at
/// the right keeps the information the placeholder used to carry.
class InlineSuggestionGhost extends StatefulWidget {
  const InlineSuggestionGhost({
    super.key,
    required this.controller,
    required this.textController,
    required this.serviceLabel,
    required this.style,
  });

  final ConversationViewController controller;
  final TextEditingController textController;
  final String serviceLabel;
  final TextStyle style;

  @override
  State<InlineSuggestionGhost> createState() => _InlineSuggestionGhostState();
}

class _InlineSuggestionGhostState extends State<InlineSuggestionGhost> {
  int _index = 0;

  void _accept(String s) {
    widget.textController.value = TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
    widget.controller.focusNode.requestFocus();
  }

  void _cycle(int delta, int count) {
    if (count < 2) return;
    HapticFeedback.selectionClick();
    setState(() => _index = (_index + delta) % count);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return Obx(() {
      final replies = widget.controller.suggestedReplies;
      if (replies.isEmpty) return const SizedBox.shrink();
      final count = replies.length;
      final i = _index % count;
      final suggestion = replies[i];
      final ghostStyle = widget.style.copyWith(color: scheme.outline);
      final tagStyle = context.theme.textTheme.labelSmall!.copyWith(color: scheme.outline.withValues(alpha: 0.8));

      // Only the sparkle and the text are tappable; a tap on the empty space to
      // their right falls through to the text field, so starting a fresh message
      // still works the way it always did.
      return Row(
        children: [
          Flexible(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _accept(suggestion),
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 50) return;
                _cycle(v < 0 ? 1 : count - 1, count);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, size: 14, color: scheme.outline),
                  const SizedBox(width: 6),
                  Flexible(
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(children: MessageHelper.buildEmojiText(suggestion, ghostStyle)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (count > 1) Text("${i + 1}/$count", style: tagStyle),
                if (count > 1) const SizedBox(width: 6),
                if (widget.serviceLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      border: Border.all(color: scheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.serviceLabel, style: tagStyle),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }
}
