import 'package:bluebubbles/app/layouts/conversation_details/material/chat_detail_theme.dart';
import 'package:bluebubbles/app/layouts/conversation_details/material/material_chat_options.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/chat_options.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// The chat's settings, moved out of the details page and behind its gear.
///
/// Same groups as before (Appearance, Conversation, Content & data, Danger
/// zone), rendered by the skin's own options widget, so nothing changed in
/// what each row does. Details itself now shows only what the chat *is*:
/// people, location, media, links and files.
class ConversationSettings extends StatefulWidget {
  const ConversationSettings({super.key, required this.chat});

  final Chat chat;

  @override
  State<ConversationSettings> createState() => _ConversationSettingsState();
}

class _ConversationSettingsState extends State<ConversationSettings> with ThemeHelpers {
  @override
  Widget build(BuildContext context) {
    final chatState = ChatsSvc.getOrCreateChatState(widget.chat);
    return ChatStateScope(
      chatState: chatState,
      child: Obx(() {
        final chatDetailTheme = ChatDetailTheme.resolve(context, widget.chat);
        final iosSkin = SettingsSvc.settings.skin.value == Skins.iOS;
        return Theme(
          data: chatDetailTheme.theme,
          child: SettingsScaffold(
            headerColor: chatDetailTheme.headerColor,
            title: "Conversation Settings",
            tileColor: chatDetailTheme.tileColor,
            initialHeader: null,
            iosSubtitle: iosSubtitle,
            materialSubtitle: materialSubtitle,
            bodySlivers: [
              SliverPadding(padding: EdgeInsets.symmetric(vertical: iosSkin ? 0 : 5)),
              iosSkin ? ChatOptions(chat: widget.chat) : ExpressiveChatOptions(chat: widget.chat),
              const SliverPadding(padding: EdgeInsets.only(top: 50)),
            ],
          ),
        );
      }),
    );
  }
}

/// The gear that opens [ConversationSettings]; used by every skin's details page.
class ConversationSettingsButton extends StatelessWidget {
  const ConversationSettingsButton({super.key, required this.chat});

  final Chat chat;

  @override
  Widget build(BuildContext context) {
    final iosSkin = SettingsSvc.settings.skin.value == Skins.iOS;
    return IconButton(
      tooltip: "Conversation settings",
      // No explicit colour: inherits onSurface normally, white when the iOS
      // profile poster paints its overlay buttons.
      icon: Icon(iosSkin ? CupertinoIcons.gear : Icons.settings_outlined),
      padding: EdgeInsets.zero,
      onPressed: () => NavigationSvc.pushLeft(context, ConversationSettings(chat: chat)),
    );
  }
}
