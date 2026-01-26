import 'package:bluebubbles/app/components/custom/custom_bouncing_scroll_physics.dart';
import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Inline message editing field with keyboard shortcuts
/// Extracted from MessageHolder to improve maintainability
class MessageEditField extends StatelessWidget {
  const MessageEditField({
    super.key,
    required this.message,
    required this.part,
    required this.editController,
    required this.cvController,
    required this.onComplete,
  });

  final Message message;
  final int part;
  final SpellCheckTextEditingController editController;
  final ConversationViewController cvController;
  final void Function(String text, int part) onComplete;

  MessageWidgetController get controller => MessagesSvc(cvController.chat.guid).getOrCreateController(message);

  void _cancelEdit() {
    cvController.editing.removeWhere((e2) => e2.item1.guid == message.guid! && e2.item2.part == part);
    if (cvController.editing.isEmpty) {
      cvController.lastFocusedNode.requestFocus();
    } else {
      cvController.editing.last.item3.focusNode?.requestFocus();
    }
  }

  KeyEventResult _handleKeyEvent(KeyEvent ev) {
    if (ev is! KeyDownEvent) {
      if (ev.logicalKey == LogicalKeyboardKey.tab) {
        return KeyEventResult.skipRemainingHandlers;
      }
      return KeyEventResult.ignored;
    }

    // Enter without shift = submit
    if (ev.logicalKey == LogicalKeyboardKey.enter && !HardwareKeyboard.instance.isShiftPressed) {
      onComplete(editController.text, part);
      return KeyEventResult.handled;
    }

    // Escape = cancel
    if (ev.logicalKey == LogicalKeyboardKey.escape) {
      _cancelEdit();
      return KeyEventResult.handled;
    }

    // Absorb tab
    if (ev.logicalKey == LogicalKeyboardKey.tab) {
      return KeyEventResult.skipRemainingHandlers;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final iOS = SettingsSvc.settings.skin.value == Skins.iOS;

    return Obx(() {
      final isTempMessage = controller.messageState?.isSending.value ?? false;
      return Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: !message.isBigEmoji
                ? context.theme.colorScheme.primary.darkenAmount(isTempMessage ? 0.2 : 0)
                : context.theme.colorScheme.background,
          ),
          constraints: BoxConstraints(
            maxWidth: NavigationSvc.width(context) * 0.75 - 40,
            minHeight: 40,
          ),
          padding: const EdgeInsets.only(right: 10).add(const EdgeInsets.all(5)),
        child: Focus(
          focusNode: FocusNode(),
          onKeyEvent: (_, ev) => _handleKeyEvent(ev),
          child: TextField(
            textCapitalization: TextCapitalization.sentences,
            autocorrect: true,
            controller: editController,
            focusNode: editController.focusNode,
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
                borderSide: BorderSide(color: context.theme.colorScheme.inversePrimary, width: 1.5),
                borderRadius: BorderRadius.circular(20),
              ),
              fillColor: Colors.transparent,
              hintStyle: context.theme.extension<BubbleText>()!.bubbleText.copyWith(
                    color: context.theme.colorScheme.inversePrimary,
                  ),
              prefixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 40),
              prefixIcon: IconButton(
                constraints: const BoxConstraints(maxWidth: 27),
                padding: const EdgeInsets.only(left: 5),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  color: context.theme.colorScheme.inversePrimary,
                  size: 20,
                ),
                onPressed: _cancelEdit,
              ),
              suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 40),
              suffixIcon: IconButton(
                constraints: const BoxConstraints(maxWidth: 27),
                padding: const EdgeInsets.only(right: 5),
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  iOS ? CupertinoIcons.checkmark_alt_circle_fill : Icons.check_circle,
                  color: context.theme.colorScheme.inversePrimary,
                  size: 20,
                ),
                onPressed: () => onComplete(editController.text, part),
              ),
            ),
            onSubmitted: (value) {
              if (!SettingsSvc.settings.sendWithReturn.value || kIsWeb || kIsDesktop) return;
              onComplete(value, part);
            },
          ),
        ), // Container closes
      )); // Material closes
    }); // Obx closes
  }
}
