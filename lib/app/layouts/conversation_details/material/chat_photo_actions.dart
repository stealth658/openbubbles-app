import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/avatar/avatar_crop.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Photo business logic for a chat's avatar, shared by the iOS (`ChatInfo`) and
/// Material/Samsung (`ExpressiveChatHeader`) hero rows. Pure extraction — behavior is
/// identical to what `ChatInfo` used to do inline.
Future<bool?> showMethodDialog(BuildContext context, Chat chat, String title) async {
  return await showBBDialog<bool>(
    context: context,
    title: title,
    content: SettingsSvc.settings.enablePrivateAPI.value && chat.isIMessage
        ? Text(
            "Local - Changes only apply to this device.\nPrivate API - Changes will apply to everyone's devices.",
            style: context.theme.textTheme.bodyLarge,
          )
        : null,
    actions: [
      BBDialogAction(
        text: "Local",
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
      ),
      BBDialogAction(
        text: "Private API",
        isDefault: true,
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
      ),
    ],
  );
}

Future<void> updatePhoto(BuildContext context, Chat chat) async {
  bool? papi = false;
  if (SettingsSvc.settings.enablePrivateAPI.value && chat.isIMessage && chat.isGroup) {
    papi = await showMethodDialog(context, chat, "Group Icon Update Method");
  }
  if (papi == null) return;
  final usePrivateApi = papi;
  if (!context.mounted) return;
  final String? result = await Navigator.of(context).push(
    ThemeSwitcher.buildPageRoute(
      builder: (context) => AvatarCrop(chat: chat),
    ),
  );
  if (result == null) return;

  // OpenBubbles: apply the avatar locally first, then (optionally) push it to
  // everyone through [backend] — never a direct HttpSvc call. This mirrors
  // `conversation_details/widgets/chat_info.dart` so the two skins agree.
  await ChatsSvc.setChatCustomAvatarPath(chat, result);
  if (!usePrivateApi || !SettingsSvc.settings.enablePrivateAPI.value) return;

  // The capability gate lives on the backend: HttpBackend still requires
  // isMinBigSur + supportsGroupChatManagement, rustpush always allows it.
  if (!await backend.canUploadGroupPhotos()) {
    showSnackbar("Error", "Failed to update group photo!");
    return;
  }
  if (!context.mounted) return;

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
      });
  final success = await backend.setChatIcon(chat, result);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (success) {
    showSnackbar("Notice", "Updated group photo successfully!");
  } else {
    showSnackbar("Error", "Failed to update group photo!");
  }
}

Future<void> deletePhoto(BuildContext context, Chat chat) async {
  bool? papi = false;
  if (SettingsSvc.settings.enablePrivateAPI.value && chat.isIMessage && chat.isGroup) {
    papi = await showMethodDialog(context, chat, "Group Icon Deletion Method");
  }
  if (papi == null) return;
  final usePrivateApi = papi;

  // OpenBubbles: see [updatePhoto] — clear locally, then push through [backend].
  await ChatsSvc.setChatCustomAvatarPath(chat, null);
  if (!usePrivateApi || !SettingsSvc.settings.enablePrivateAPI.value) return;
  if (!await backend.canUploadGroupPhotos()) return;

  final success = await backend.deleteChatIcon(chat);
  if (success) {
    showSnackbar("Notice", "Deleted group photo successfully!");
  } else {
    showSnackbar("Error", "Failed to delete group photo!");
  }
}
