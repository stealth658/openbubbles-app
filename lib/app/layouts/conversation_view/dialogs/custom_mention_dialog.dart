import 'package:bluebubbles/app/components/custom/custom_bouncing_scroll_physics.dart';
import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

/// [mention] may either be a [Mentionable] (the upstream callers) or a plain
/// [String] display name (OpenBubbles' attributed-body mention cache, which
/// only has the cached address text in hand).
Future<String?> showCustomMentionDialog(BuildContext context, Object? mention) async {
  final String? currentName = mention is Mentionable ? mention.displayName : mention as String?;
  final String defaultName =
      mention is Mentionable ? mention.handle.displayName : (mention as String? ?? "");
  final TextEditingController mentionController = TextEditingController(text: currentName);
  String? changed;
  await showBBDialog(
    context: context,
    title: "Custom Mention",
    content: TextField(
      controller: mentionController,
      textCapitalization: TextCapitalization.sentences,
      autocorrect: true,
      scrollPhysics: const CustomBouncingScrollPhysics(),
      autofocus: true,
      enableIMEPersonalizedLearning: !SettingsSvc.settings.incognitoKeyboard.value,
      decoration: InputDecoration(
        labelText: "Custom Mention",
        hintText: defaultName,
        border: const OutlineInputBorder(),
      ),
      onSubmitted: (val) {
        if (isNullOrEmptyString(val)) {
          val = defaultName;
        }
        changed = val;
        Navigator.of(context, rootNavigator: true).pop();
      },
    ),
    actions: [
      BBDialogAction(
        text: "Cancel",
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
      BBDialogAction(
        text: "OK",
        isDefault: true,
        onPressed: () {
          if (isNullOrEmptyString(mentionController.text)) {
            changed = defaultName;
          } else {
            changed = mentionController.text;
          }
          Navigator.of(context, rootNavigator: true).pop();
        },
      ),
    ],
  );
  return changed;
}
