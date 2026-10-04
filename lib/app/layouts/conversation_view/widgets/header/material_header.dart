import 'package:bluebubbles/app/layouts/conversation_details/conversation_details.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/header/header_widgets.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_thread_popup.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart' hide BackButton;
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

class MaterialHeader extends StatelessWidget implements PreferredSizeWidget {
  const MaterialHeader({super.key, required this.controller});

  final ConversationViewController controller;

  @override
  Widget build(BuildContext context) {
    final Rx<Color> _backgroundColor = context.theme.colorScheme.surfaceContainerHighest
        .withValues(alpha: (kIsDesktop && SettingsSvc.settings.windowEffect.value != WindowEffect.disabled) ? 0.4 : 1)
        .obs;
    final Color _foregroundColor = context.theme.colorScheme.onSurfaceVariant;

    return Column(children: [
      Expanded(
          child: Stack(children: [
      Obx(() => AppBar(
            backgroundColor: _backgroundColor.value,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            systemOverlayStyle: context.systemUiOverlayStyle(
              statusBarColor: _backgroundColor.value,
              backgroundBrightness: ThemeData.estimateBrightnessForColor(_backgroundColor.value),
            ),
            automaticallyImplyLeading: false,
            toolbarHeight: (kIsDesktop ? 25 : 0) + kToolbarHeight,
            leadingWidth: 30,
            leading: Padding(
              padding: EdgeInsets.only(left: 5.0, top: kIsDesktop ? 20 : 0),
              child: BackButton(
                color: _foregroundColor,
                focusNode: controller.headerBackFocusNode,
                onPressed: () {
                  if (controller.inSelectMode.value) {
                    controller.inSelectMode.value = false;
                    controller.selected.clear();
                    return true;
                  }
                  if (LifecycleSvc.isBubble) {
                    SystemNavigator.pop();
                    return true;
                  }
                  controller.close();
                  return false;
                },
              ),
            ),
            title: Padding(
              padding: EdgeInsets.only(top: kIsDesktop ? 20 : 0),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                // Tapping the name opens the conversation details for every chat.
                // The native contact card is one tap further (the Info button in
                // the details header), the way iOS does it.
                onTap: () {
                  Navigator.of(context).push(
                    ThemeSwitcher.buildPageRoute(
                      builder: (context) => ConversationDetails(
                        chat: controller.chat,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(5.0),
                  child: _ChatIconAndTitle(parentController: controller),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(top: kIsDesktop ? 20 : 0),
                child: ManualMark(controller: controller),
              ),
              if (Platform.isAndroid && !controller.chat.isGroup && controller.chat.handles.first.address.isPhoneNumber)
                IconButton(
                  icon: Icon(Icons.call_outlined, color: _foregroundColor),
                  onPressed: () {
                    launchUrl(Uri(scheme: "tel", path: controller.chat.handles.first.address));
                  },
                ),
              if (Platform.isAndroid && !controller.chat.isGroup && controller.chat.handles.first.address.isEmail)
                IconButton(
                  icon: Icon(Icons.mail_outlined, color: _foregroundColor),
                  onPressed: () {
                    launchUrl(Uri(scheme: "mailto", path: controller.chat.handles.first.address));
                  },
                ),
              FaceTimeBtn(controller: controller),
              Padding(
                padding: EdgeInsets.only(top: kIsDesktop ? 20 : 0),
                child: PopupMenuButton<int>(
                  color: context.theme.colorScheme.surfaceContainerHighest,
                  shape: SettingsSvc.settings.skin.value != Skins.Material
                      ? const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(20.0),
                          ),
                        )
                      : null,
                  onSelected: (int value) {
                    if (value == 0) {
                      Navigator.of(context).push(
                        ThemeSwitcher.buildPageRoute(
                          builder: (context) => ConversationDetails(
                            chat: controller.chat,
                          ),
                        ),
                      );
                    } else if (value == 1) {
                      ChatsSvc.setChatArchived(controller.chat, !controller.chat.isArchived!);
                      if (Get.isSnackbarOpen) {
                        Get.closeAllSnackbars();
                      }
                      Navigator.of(context).pop();
                    } else if (value == 2) {
                      showBBDialog(
                        barrierDismissible: false,
                        context: context,
                        title: "Are you sure?",
                        body: "This chat will be moved to trash on all synced devices",
                        actions: <BBDialogAction>[
                          BBDialogAction(
                            text: "No",
                            onPressed: () {
                              if (Get.isSnackbarOpen) {
                                Get.closeAllSnackbars();
                              }
                              Navigator.of(context, rootNavigator: true).pop();
                            },
                          ),
                          BBDialogAction(
                            text: "Yes",
                            isDestructive: true,
                            onPressed: () async {
                              ChatsSvc.removeChat(controller.chat);
                              ChatsSvc.softDeleteChat(controller.chat);
                              if (Get.isSnackbarOpen) {
                                Get.closeAllSnackbars();
                              }
                              Navigator.of(context, rootNavigator: true).pop();
                            },
                          ),
                        ],
                      );
                    } else if (value == 3) {
                      showBookmarksThread(controller, context);
                    }
                  },
                  itemBuilder: (context) {
                    return <PopupMenuItem<int>>[
                      PopupMenuItem(
                        value: 0,
                        child: Text(
                          'Details',
                          style: context.textTheme.bodyLarge!.apply(color: context.theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      if (!LifecycleSvc.isBubble)
                        PopupMenuItem(
                          value: 1,
                          child: Text(
                            controller.chat.isArchived! ? 'Unarchive' : 'Archive',
                            style:
                                context.textTheme.bodyLarge!.apply(color: context.theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      if (!LifecycleSvc.isBubble)
                        PopupMenuItem(
                          value: 2,
                          child: Text(
                            'Delete',
                            style:
                                context.textTheme.bodyLarge!.apply(color: context.theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      PopupMenuItem(
                        value: 3,
                        child: Text(
                          'Bookmarks',
                          style: context.textTheme.bodyLarge!.apply(color: context.theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ];
                  },
                  icon: Icon(
                    Icons.more_vert,
                    color: _foregroundColor,
                  ),
                ),
              )
            ],
          )),
      const Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: HeaderProgressIndicator(),
      ),
    ])),
      // OpenBubbles: Apple name-and-photo sharing prompt.
      ShareProfileBanner(controller: controller, material: true),
    ]);
  }

  @override
  Size get preferredSize => Size.fromHeight(kIsDesktop ? 90 : kToolbarHeight);
}

class _ChatIconAndTitle extends CustomStateful<ConversationViewController> {
  const _ChatIconAndTitle({required super.parentController});

  @override
  State<StatefulWidget> createState() => _ChatIconAndTitleState();
}

class _ChatIconAndTitleState extends CustomState<_ChatIconAndTitle, void, ConversationViewController> {
  @override
  void initState() {
    super.initState();
    tag = controller.chat.guid;
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ChatStateScope.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12.5),
          child: IgnorePointer(
            ignoring: true,
            child: ContactAvatarGroupWidget(
              size: !controller.chat.isGroup ? 35 : 40,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Obx(() {
                // Get title from ChatState - it handles all title logic including redacted mode
                final _title = controller.inSelectMode.value
                    ? "${controller.selected.length} selected"
                    : chatState.title.value ?? controller.chat.getTitle();
                return Text(
                  _title,
                  style: context.theme.textTheme.titleLarge!
                      .apply(color: context.theme.colorScheme.onSurfaceVariant, fontSizeFactor: 0.85),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                );
              }),
              // Find My: a quiet city line under the name for people who share
              // their location with you (1:1 chats only). Falls back to the
              // Samsung address line where that applied before.
              if (!controller.chat.isGroup && !controller.inSelectMode.value)
                _FriendPlaceLine(chat: controller.chat, fallbackAddress: samsung &&
                        !controller.chat.getTitle().isPhoneNumber &&
                        !controller.chat.getTitle().isEmail
                    ? controller.chat.handles[0].address
                    : null)
              else if (samsung && controller.chat.isGroup)
                Text(
                  "${controller.chat.handles.length} recipients",
                  style: context.theme.textTheme.labelLarge!.apply(color: context.theme.colorScheme.outline),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                ),
            ],
          ),
        ),
      ],
    );
  }
}


/// "Old Westbury, NY" under the contact's name when they share their location.
/// Reads the shared Find My cache and asks it for a refresh on first build;
/// shows nothing (or the Samsung address line) until there is something to show.
class _FriendPlaceLine extends StatefulWidget {
  const _FriendPlaceLine({required this.chat, this.fallbackAddress});

  final Chat chat;
  final String? fallbackAddress;

  @override
  State<_FriendPlaceLine> createState() => _FriendPlaceLineState();
}

class _FriendPlaceLineState extends State<_FriendPlaceLine> {
  @override
  void initState() {
    super.initState();
    if (FindMyFriendsCache.available) {
      // Fire and forget; the Obx below repaints when the cache fills.
      FindMyFriendsCache.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = context.theme.textTheme.labelLarge!.apply(color: context.theme.colorScheme.outline);
    return Obx(() {
      final friend = FindMyFriendsCache.forChat(widget.chat);
      final place = SettingsSvc.settings.redactedMode.value ? null : friend?.placeName;
      if (place == null || !(friend?.hasLocation ?? false)) {
        if (widget.fallbackAddress == null) return const SizedBox.shrink();
        return Text(widget.fallbackAddress!, style: style, maxLines: 1, overflow: TextOverflow.fade);
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_outlined, size: 12, color: context.theme.colorScheme.outline),
          const SizedBox(width: 2),
          Flexible(child: Text(place, style: style, maxLines: 1, overflow: TextOverflow.fade)),
        ],
      );
    });
  }
}
