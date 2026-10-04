import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// OpenBubbles: the on-device compose assistant (Gemini Nano).
///
/// Opened from the sparkle button beside the text field. Offers proofreading
/// and the rewrite styles ML Kit's rewriter supports, shows the result, and
/// lets the user drop it into the field or copy it. Everything runs on the
/// phone; the draft never leaves the device.
class AiComposeSheet extends StatefulWidget {
  const AiComposeSheet({super.key, required this.controller});

  final ConversationViewController controller;

  static Future<void> show(BuildContext context, ConversationViewController controller) {
    final text = controller.textController.text.trim();
    if (text.isEmpty) {
      showSnackbar("Nothing to work with", "Type a draft first, then tap the sparkle.");
      return Future.value();
    }
    if (MentionTextEditingController.escapingRegex.hasMatch(controller.textController.text)) {
      showSnackbar("Mentions in the way", "Remove @mentions from the draft before rewriting it.");
      return Future.value();
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.theme.colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AiComposeSheet(controller: controller),
    );
  }

  @override
  State<AiComposeSheet> createState() => _AiComposeSheetState();
}

class _AiComposeSheetState extends State<AiComposeSheet> {
  static const _actions = <(String, String, IconData)>[
    ("Proofread", "proofread", Icons.spellcheck),
    ("Friendlier", "friendly", Icons.sentiment_satisfied_alt_outlined),
    ("More professional", "professional", Icons.work_outline),
    ("Shorter", "shorten", Icons.short_text),
    ("Elaborate", "elaborate", Icons.notes),
    ("Rephrase", "rephrase", Icons.autorenew),
    ("Emojify", "emojify", Icons.emoji_emotions_outlined),
  ];

  late final String original = widget.controller.textController.text;
  String? running;
  String? error;
  List<String> results = [];
  int selected = 0;

  Future<void> _run(String action) async {
    setState(() {
      running = action;
      error = null;
      results = [];
      selected = 0;
    });
    try {
      final feature = action == "proofread" ? "proofread" : "rewrite";
      if (!await GenAi.ensure(feature)) {
        throw Exception("Gemini Nano isn't available for this on your device yet. Check the On-device AI setting.");
      }
      final out = action == "proofread" ? [await GenAi.proofread(original)] : await GenAi.rewrite(original, action);
      if (!mounted) return;
      if (out.isEmpty || (out.length == 1 && out.first.trim() == original.trim())) {
        setState(() {
          running = null;
          error = action == "proofread" ? "No corrections suggested." : "No rewrite suggested.";
        });
        return;
      }
      setState(() {
        running = null;
        results = out;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        running = null;
        error = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  void _use() {
    final text = results[selected];
    widget.controller.textController.text = text;
    widget.controller.textController.selection = TextSelection.collapsed(offset: text.length);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text("Rewrite with Gemini Nano", style: theme.textTheme.titleMedium),
              const Spacer(),
              Text("On-device", style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _actions
                  .map((a) => ActionChip(
                        avatar: Icon(a.$3, size: 18),
                        label: Text(a.$1),
                        onPressed: running == null ? () => _run(a.$2) : null,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            if (running != null)
              Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text("Thinking…", style: theme.textTheme.bodyMedium),
              ]),
            if (error != null)
              Text(error!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
            if (results.isNotEmpty) ...[
              if (results.length > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: List.generate(
                      results.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text("Option ${i + 1}"),
                          selected: selected == i,
                          onSelected: (_) => setState(() => selected = i),
                        ),
                      ),
                    ),
                  ),
                ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(results[selected], style: theme.textTheme.bodyLarge),
              ),
              const SizedBox(height: 12),
              Row(children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text("Copy"),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: results[selected]));
                    showSnackbar("Copied", "Suggestion copied to clipboard");
                  },
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text("Use this"),
                  onPressed: _use,
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
