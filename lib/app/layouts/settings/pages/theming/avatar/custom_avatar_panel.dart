import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/conversation_tile.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/avatar/avatar_crop.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';
import 'package:bluebubbles/app/components/base/base.dart' hide BBDialogAction;

class CustomAvatarPanel extends StatefulWidget {
  const CustomAvatarPanel({super.key});

  @override
  State<StatefulWidget> createState() => _CustomAvatarPanelState();
}

class _CustomAvatarPanelState extends OptimizedState<CustomAvatarPanel> {
  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
        title: "Custom Avatars",
        initialHeader: null,
        iosSubtitle: null,
        materialSubtitle: null,
        tileColor: tileColor,
        headerColor: headerColor,
        bodySlivers: [
          Obx(() {
            if (!ChatsSvc.loadedFirstChatBatch.value) {
              return SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 50.0),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            "Loading chats...",
                            style: context.theme.textTheme.labelLarge,
                          ),
                        ),
                        const BBLoadingIndicator(size: 15),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (ChatsSvc.loadedFirstChatBatch.value && ChatsSvc.isEmpty) {
              return SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 50.0),
                    child: Text(
                      "You have no chats :(",
                      style: context.theme.textTheme.labelLarge,
                    ),
                  ),
                ),
              );
            }

            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final chat = ChatsSvc.allChats[index];
                  return ConversationTile(
                    key: Key(chat.guid.toString()),
                    chat: chat,
                    controller: Get.put(ConversationListController(showUnknownSenders: true, showArchivedChats: true),
                        tag: "custom-avatar-panel"),
                    inSelectMode: true,
                    onSelect: (_) {
                      if (chat.customAvatarPath != null) {
                        BBAlertDialog.show(
                          context: context,
                          title: "Custom Avatar",
                          message: "You have already set a custom avatar for this chat. What would you like to do?",
                          actions: [
                            BBDialogAction(
                              label: "Cancel",
                              type: BBDialogButtonType.cancel,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            BBDialogAction(
                              label: "Reset",
                              type: BBDialogButtonType.destructive,
                              onPressed: () async {
                                File file = File(chat.customAvatarPath!);
                                file.delete();
                                chat.customAvatarPath = null;
                                await chat.saveAsync(updateCustomAvatarPath: true);
                                Navigator.of(context, rootNavigator: true).pop();
                              },
                            ),
                            BBDialogAction(
                              label: "Set New",
                              type: BBDialogButtonType.primary,
                              onPressed: () {
                                Navigator.of(context).pop();
                                NavigationSvc.pushSettings(
                                  context,
                                  AvatarCrop(chat: chat),
                                );
                              },
                            ),
                          ],
                        );
                      } else {
                        NavigationSvc.pushSettings(
                          context,
                          AvatarCrop(chat: chat),
                        );
                      }
                    },
                  );
                },
                childCount: ChatsSvc.length,
              ),
            );
          }),
        ]);
  }
}
