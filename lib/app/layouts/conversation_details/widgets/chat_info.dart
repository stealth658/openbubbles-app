import 'dart:ui' show ImageFilter;

import 'package:bluebubbles/app/layouts/conversation_details/dialogs/address_picker.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/change_name.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/avatar/avatar_crop.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ChatInfo extends StatefulWidget {
  const ChatInfo({super.key, required this.chat, this.ftSupportedParticipants = const []});

  final Chat chat;

  /// OpenBubbles: rust handles in this chat that can receive a FaceTime call.
  final List<String> ftSupportedParticipants;

  @override
  State<StatefulWidget> createState() => _ChatInfoState();
}

class _ChatInfoState extends State<ChatInfo> with ThemeHelpers {
  Chat get chat => widget.chat;

  /// OpenBubbles: everyone in the chat (plus us) has to be FaceTime-capable.
  bool get facetimeSupported =>
      widget.ftSupportedParticipants.length == (chat.handles.length + 1 /* my handle */);

  /// OpenBubbles: same idea as upstream's chat_photo_actions.showMethodDialog,
  /// but with the fork's wording (there is no "Private API" when talking to Apple directly).
  Future<bool?> _showMethodDialog(String title) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
        title: Text(title, style: context.theme.textTheme.titleLarge),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Local - Changes only apply to this device.\nEveryone - Changes will apply to everyone's devices.",
              style: context.theme.textTheme.bodyLarge,
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text("Local",
                style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text("Everyone",
                style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }

  /// OpenBubbles: group photo updates go through [backend], never a direct HttpSvc
  /// call, and the capability gate is [BackendService.canUploadGroupPhotos].
  Future<void> _updatePhoto() async {
    bool? papi = false;
    if (SettingsSvc.settings.enablePrivateAPI.value && chat.isIMessage) {
      papi = await _showMethodDialog("Group Icon Update Method");
    }
    if (papi == null || !mounted) return;
    final String? result = await Navigator.of(context).push(
      ThemeSwitcher.buildPageRoute(
        builder: (context) => AvatarCrop(chat: chat),
      ),
    );
    if (result == null) return;
    await ChatsSvc.setChatCustomAvatarPath(chat, result);

    if (!papi || !SettingsSvc.settings.enablePrivateAPI.value) return;
    if (!await backend.canUploadGroupPhotos()) return;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
          title: Text(
            "Updating group photo...",
            style: context.theme.textTheme.titleLarge,
          ),
          content: SizedBox(
            height: 70,
            child: Center(
              child: CircularProgressIndicator(
                backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
              ),
            ),
          ),
        );
      },
    );
    final response = await backend.setChatIcon(chat, result);
    Get.back();
    if (response) {
      showSnackbar("Notice", "Updated group photo successfully!");
    } else {
      showSnackbar("Error", "Failed to update group photo!");
    }
  }

  /// OpenBubbles: see [_updatePhoto].
  Future<void> _deletePhoto() async {
    bool? papi = false;
    if (SettingsSvc.settings.enablePrivateAPI.value && chat.isIMessage) {
      papi = await _showMethodDialog("Group Icon Deletion Method");
    }
    if (papi == null) return;
    await ChatsSvc.setChatCustomAvatarPath(chat, null);
    if (!papi || !SettingsSvc.settings.enablePrivateAPI.value) return;
    if (!await backend.canUploadGroupPhotos()) return;

    final response = await backend.deleteChatIcon(chat);
    if (response) {
      showSnackbar("Notice", "Deleted group photo successfully!");
    } else {
      showSnackbar("Error", "Failed to delete group photo!");
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ChatsSvc.getChatState(chat.guid);

    bool canCall = !kIsWeb &&
        !kIsDesktop &&
        !(chat.chatIdentifier?.startsWith("urn:biz") ?? false) &&
        (chat.handles.isNotEmpty &&
            ((chat.handles.first.contactsV2.firstOrNull?.phoneNumbers.isNotEmpty ?? false) ||
                !chat.handles.first.address.contains("@")));

    return DeferredPointerHandler(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // OpenBubbles: 1:1 chats render their header via ProfileScaffold (Apple
        // profile poster), so the avatar/title block is group-only here.
        if (chat.isGroup) const SizedBox(height: 10),
        if (iOS && chat.isGroup)
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: chat.isGroup
                      ? () async {
                          _updatePhoto();
                        }
                      : null,
                  child: ContactAvatarGroupWidget(
                    size: 100,
                    editable: !chat.isGroup,
                  ),
                ),
                Obx(() => chat.customAvatarPath != null
                    ? Positioned(
                        right: -5,
                        top: -5,
                        child: DeferPointer(
                          child: InkWell(
                            onTap: () async {
                              _deletePhoto();
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                border: Border.all(color: context.theme.colorScheme.surface, width: 1),
                                shape: BoxShape.circle,
                                color: context.theme.colorScheme.tertiaryContainer,
                              ),
                              child: Icon(
                                Icons.close,
                                color: context.theme.colorScheme.onTertiaryContainer,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink()),
              ],
            ),
          ),
        if (iOS && chat.isGroup)
          Padding(
            padding: const EdgeInsets.only(top: 12.0, left: 20.0, right: 20.0),
            child: Center(
              child: Obx(() => RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: context.theme.textTheme.headlineMedium!.copyWith(
                        fontWeight: FontWeight.bold,
                        color: context.theme.colorScheme.onSurface,
                      ),
                      children: MessageHelper.buildEmojiText(
                        chatState?.title.value ?? chat.getTitle(),
                        context.theme.textTheme.headlineMedium!.copyWith(
                          fontWeight: FontWeight.bold,
                          color: context.theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  )),
            ),
          ),
        if (!chat.isGroup && iOS && chatState != null && chatState.participants.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, left: 20.0, right: 20.0),
            child: Center(
              child: Obx(() {
                final address = chatState.participants.first.formattedAddress.value;
                if (address == null) return const SizedBox.shrink();
                return Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: context.theme.textTheme.bodyMedium!.copyWith(
                    color: context.theme.colorScheme.outline,
                  ),
                );
              }),
            ),
          ),
        if (chat.isGroup)
          Center(
            child: TextButton(
              child: Text(
                "${(chat.displayName?.isNotEmpty ?? false) ? "Change" : "Add"} Name",
                style: context.theme.textTheme.bodyMedium!.apply(color: context.theme.primaryColor),
                textScaler: const TextScaler.linear(1.15),
              ),
              onPressed: () async {
                bool? papi = false;
                if (SettingsSvc.settings.enablePrivateAPI.value && chat.isIMessage) {
                  papi = await _showMethodDialog("Group Name Update Method");
                }
                if (papi == null) return;
                if (!papi) {
                  showChangeName(chat, "local", context);
                } else {
                  showChangeName(chat, "private-api", context);
                }
              },
            ),
          ),
        // OpenBubbles: the action row is shown for every skin (1:1 details are hosted
        // by ProfileScaffold, which has no button row of its own).
        if (!chat.isGroup)
          Padding(
            padding: const EdgeInsets.only(left: 18.0, right: 18, top: 10),
            child: Row(
              mainAxisAlignment: kIsWeb || kIsDesktop ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: intersperse(const SizedBox(width: 5), [
                if (canCall) CallButton(tileColor: tileColor, chat: chat, iOS: iOS),
                // OpenBubbles: only offer FaceTime when rustpush validated the targets.
                if (facetimeSupported) VideoCallButton(tileColor: tileColor, chat: chat, iOS: iOS),
                if (chat.handles.isNotEmpty &&
                    ((chat.handles.first.contactsV2.firstOrNull?.emailAddresses.isNotEmpty ?? false) ||
                        chat.handles.first.address.contains("@")))
                  MailButton(tileColor: tileColor, chat: chat, iOS: iOS),
                if (!kIsWeb && !kIsDesktop) InfoButton(tileColor: tileColor, chat: chat, iOS: iOS),
                // OpenBubbles-only: invite an SMS contact to OpenBubbles relaying.
                if (SettingsSvc.settings.macIsMine.value && chat.isRpSms)
                  ShareButton(tileColor: tileColor, chat: chat, iOS: iOS),
              ]).toList(),
            ),
          ),
        if (chat.isGroup)
          Padding(
            padding: const EdgeInsets.only(left: 20.0, top: 20.0, bottom: 5.0),
            child: Text("${chat.handles.length} ${iOS ? "OTHER MEMBERS" : "OTHER PEOPLE"}",
                style: context.theme.textTheme.bodyMedium!.copyWith(color: context.theme.colorScheme.outline)),
          ),
      ]),
    );
  }
}

const List<double> darkMatrix = <double>[
  1.385, -0.56, -0.112, 0.0, 0.3, //
  -0.315, 1.14, -0.112, 0.0, 0.3, //
  -0.315, -0.56, 1.588, 0.0, 0.3, //
  0.0, 0.0, 0.0, 1.0, 0.0
];

const List<double> lightMatrix = <double>[
  1.74, -0.4, -0.17, 0.0, 0.0, //
  -0.26, 1.6, -0.17, 0.0, 0.0, //
  -0.26, -0.4, 1.83, 0.0, 0.0, //
  0.0, 0.0, 0.0, 1.0, 0.0
];

/// OpenBubbles: the 1:1 detail buttons sit on top of the Apple profile poster, so
/// they use a translucent blurred card instead of a solid Material tile.
Widget blurredCard({required Widget child, required BuildContext context}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(15),
    child: BackdropFilter(
      filter: ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        inner: ColorFilter.matrix(
          CupertinoTheme.maybeBrightnessOf(context) == Brightness.dark ? darkMatrix : lightMatrix,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        clipBehavior: Clip.hardEdge,
        child: child,
      ),
    ),
  );
}

/// OpenBubbles-only: shares an invite link so an SMS contact can be relayed
/// through this device's Apple account.
class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    required this.tileColor,
    required this.chat,
    required this.iOS,
  });

  final Color tileColor;
  final Chat chat;
  final bool iOS;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: blurredCard(
        context: context,
        child: InkWell(
          onTap: () async {
            final ctx = context;
            showDialog(
              context: Get.context!,
              builder: (context) => AlertDialog(
                backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                title: const Text('Choose your friends wisely'),
                content: Text(
                  "Apple may block devices due to spam or exceeding 20 users.",
                  style: context.theme.textTheme.bodyLarge,
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Get.back(),
                    child: Text("Cancel",
                        style:
                            context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                  ),
                  TextButton(
                    onPressed: () async {
                      Get.back();
                      final code =
                          await pushService.uploadCode(false, await api.getDeviceInfo(config: pushService.state!.osConfig));
                      cvc(chat).textController.text = "$rpApiRoot/$code";
                      if (ctx.mounted) Navigator.of(ctx).pop();
                    },
                    child: Text("Invite",
                        style:
                            context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                  ),
                ],
              ),
            );
          },
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.arrow_up_right_diamond, color: context.theme.colorScheme.onSurface, size: 20),
                const SizedBox(height: 7.5),
                Text("Invite",
                    style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InfoButton extends StatelessWidget {
  const InfoButton({
    super.key,
    required this.tileColor,
    required this.chat,
    required this.iOS,
  });

  final Color tileColor;
  final Chat chat;
  final bool iOS;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: blurredCard(
        context: context,
        child: InkWell(
          onTap: () async {
            final contact = chat.handles.first.contactsV2.firstOrNull;
            final handle = chat.handles.first;
            if (contact == null || !contact.isNative) {
              await MethodChannelSvc.actions.openContactForm(
                address: handle.address,
                isEmail: handle.address.isEmail,
              );
            } else {
              try {
                await MethodChannelSvc.actions.viewContactForm(nativeContactId: contact.nativeContactId);
              } catch (_) {
                showSnackbar("Error", "Failed to find contact on device!");
              }
            }
          },
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  chat.handles.isNotEmpty &&
                          chat.handles.first.contactsV2.isNotEmpty &&
                          chat.handles.first.contactsV2.first.isNative
                      ? (iOS ? CupertinoIcons.info : Icons.info)
                      : (iOS ? CupertinoIcons.plus_circle : Icons.add_circle_outline),
                  color: context.theme.colorScheme.onSurface,
                  size: 20,
                ),
                const SizedBox(height: 7.5),
                Text(
                    chat.handles.isNotEmpty &&
                            chat.handles.first.contactsV2.isNotEmpty &&
                            chat.handles.first.contactsV2.first.isNative
                        ? "Info"
                        : "Add Contact",
                    style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MailButton extends StatelessWidget {
  const MailButton({
    super.key,
    required this.tileColor,
    required this.chat,
    required this.iOS,
  });

  final Color tileColor;
  final Chat chat;
  final bool iOS;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: blurredCard(
        context: context,
        child: InkWell(
          onTap: () {
            final contact = chat.handles.first.contactsV2.firstOrNull;
            showAddressPicker(contact, chat.handles.first, context, isEmail: true);
          },
          onLongPress: () {
            final contact = chat.handles.first.contactsV2.firstOrNull;
            showAddressPicker(contact, chat.handles.first, context, isEmail: true, isLongPressed: true);
          },
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iOS ? CupertinoIcons.mail : Icons.email, color: context.theme.colorScheme.onSurface, size: 20),
                const SizedBox(height: 7.5),
                Text("Mail",
                    style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VideoCallButton extends StatelessWidget {
  const VideoCallButton({
    super.key,
    required this.tileColor,
    required this.chat,
    required this.iOS,
  });

  final Color tileColor;
  final Chat chat;
  final bool iOS;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: blurredCard(
        context: context,
        child: InkWell(
          // OpenBubbles: this is a real (rustpush) FaceTime call, not a video intent.
          onTap: () async {
            final data = await chat.getConversationData();
            final handle = await chat.ensureHandle();
            final handles = data.participants;
            handles.remove(handle);
            await pushService.placeOutgoingCall(handle, handles);
          },
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iOS ? CupertinoIcons.video_camera : Icons.video_call_outlined,
                    color: context.theme.colorScheme.onSurface, size: 25),
                const SizedBox(height: 2.5),
                Text("Video",
                    style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.tileColor,
    required this.chat,
    required this.iOS,
  });

  final Color tileColor;
  final Chat chat;
  final bool iOS;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: blurredCard(
        context: context,
        child: InkWell(
          onTap: () {
            final contact = chat.handles.first.contactsV2.firstOrNull;
            showAddressPicker(contact, chat.handles.first, context);
          },
          onLongPress: () {
            final contact = chat.handles.first.contactsV2.firstOrNull;
            showAddressPicker(contact, chat.handles.first, context, isLongPressed: true);
          },
          borderRadius: BorderRadius.circular(15),
          child: SizedBox(
            height: 60,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iOS ? CupertinoIcons.phone : Icons.call, color: context.theme.colorScheme.onSurface, size: 20),
                const SizedBox(height: 7.5),
                Text("Call",
                    style: context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
