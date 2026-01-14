import 'package:bluebubbles/app/components/settings/settings.dart';
import 'package:bluebubbles/app/components/dialogs/dialogs.dart';

import '../../pages/misc/misc_panel.dart';
import '../../pages/scheduling/message_reminders_panel.dart';
import '../../pages/scheduling/scheduled_messages_panel.dart';
import '../tiles/connection_server_tile.dart';
import '../tiles/contact_upload_progress.dart';
import '../tiles/private_api_tile.dart';
import '../tiles/redacted_mode_tile.dart';
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/notification_providers_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/private_api_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/redacted_mode_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/advanced/tasker_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/conversation_list/chat_list_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/desktop/desktop_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/message_view/attachment_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/message_view/conversation_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/about_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/troubleshoot_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/profile/profile_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/server/backup_restore_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/server/server_management_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/system/notification_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/theming_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/data/database/database.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/core/logger/logger.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response;
import 'package:in_app_review/in_app_review.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'searchable_setting_item.dart';

List<Widget> buildSettingItemList({
  required BuildContext context,
  required String searchQuery,
  required Color tileColor,
  required bool samsung,
  required bool iOS,
  required bool material,
  required TextStyle iosSubtitle,
  required TextStyle materialSubtitle,
  required dynamic ns,
  required RxnDouble progress,
  required RxnInt totalSize,
  required RxBool uploadingContacts,
}) {
  // return searchable items, headers, tiles, or sections
  return [
    if (!kIsWeb && (!iOS || kIsDesktop))
      const SearchableSettingItem(
        title: "Profile",
        child: BBSettingsHeader(
          height: 40,
          text: "Profile",
        ),
      ),
    if (!kIsWeb && (!iOS || kIsDesktop))
      SearchableSettingItem(
        title: SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value
            ? "User Name"
            : SettingsSvc.settings.userName.value,
        child: BBSettingsSection(
          backgroundColor: tileColor,
          children: [
            BBSettingsTile(
              title: SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideContactInfo.value
                  ? "User Name"
                  : SettingsSvc.settings.userName.value,
              subtitle: "Tap to view more details",
              onTap: () {
                ns.pushAndRemoveSettingsUntil(
                  context,
                  const ProfilePanel(),
                  (route) => route.isFirst,
                );
              },
              leading: const ContactAvatarWidget(
                handle: null,
                borderThickness: 0.1,
                editable: false,
                fontSize: 22,
                size: 50,
              ),
              trailing: const NextButton(),
            ),
          ],
        ),
      ),
    if (!kIsWeb)
      const SearchableSettingItem(
        title: "Server & Message Management",
        child: BBSettingsHeader(
          height: 40,
          text: "Server & Message Management",
        ),
      ),
    SearchableSettingItem(
      title: "Connection & Server",
      searchTags: [
        "Re-configure with BlueBubbles Server",
        "Manually Sync Messages",
        "Configure Custom Headers",
        "Auto-Sync Contacts",
        "Sign in with Google",
        "Fetch Latest URL",
        "Detect Localhost Address",
        "Fetch & Share Server Logs",
        "Restart iMessage",
        "Restart Private API & Services",
        "Restart BlueBubbles Server",
        "Check for Server Updates"
      ],
      onTap: () {
        ns.pushAndRemoveSettingsUntil(
          context,
          ServerManagementPanel(),
          (Route route) => route.isFirst,
        );
      },
      // Helps search
      child: BBSettingsSection(
        backgroundColor: tileColor,
        children: [
          // Optimized reactive tile for connection state
          ConnectionServerTile(
            tileColor: tileColor,
            samsung: samsung,
            iOS: iOS,
            material: material,
          ),

          if (SettingsSvc.serverDetailsSync().item4 >= 205) const SettingsDivider(),
          if (SettingsSvc.serverDetailsSync().item4 >= 205)
            SearchableSettingItem(
                title: "Scheduled Messages",
                searchTags: ["Scheduled Messages"],
                child: BBSettingsTile(
                  title: "Scheduled Messages",
                  onTap: () {
                    ns.pushAndRemoveSettingsUntil(
                      context,
                      const ScheduledMessagesPanel(),
                      (Route route) => route.isFirst,
                    );
                  },
                  trailing: const NextButton(),
                  leading: const BBSettingsIcon(
                    iosIcon: CupertinoIcons.calendar,
                    materialIcon: Icons.schedule_send_outlined,
                    color: Colors.redAccent,
                  ),
                )),

          if (Platform.isAndroid) const SettingsDivider(),
          if (Platform.isAndroid)
            SearchableSettingItem(
              title: "Message Reminders",
              searchTags: ["Message Reminders"],
              child: BBSettingsTile(
                title: "Message Reminders",
                onTap: () {
                  ns.pushAndRemoveSettingsUntil(
                    context,
                    const MessageRemindersPanel(),
                    (Route route) => route.isFirst,
                  );
                },
                trailing: const NextButton(),
                leading: const BBSettingsIcon(
                  iosIcon: CupertinoIcons.alarm_fill,
                  materialIcon: Icons.alarm,
                  color: Colors.blueAccent,
                ),
              ),
            ),
        ],
      ),
    ),
    const SearchableSettingItem(
        title: "Appearance",
        child: BBSettingsHeader(text: "Appearance")),
    SearchableSettingItem(
        title: "Appearance Settings",
        searchTags: [
          "Dark Mode",
          "Light Mode",
          "Advanced Theming",
          "Tablet Mode",
          "Immersive Mode",
          "Material You",
          "Colors for Media",
          "Colorful Avatars",
          "Colorful Bubbles",
          "Custom Avatar Colors",
          "Custom Avatars",
          "Download iOS Emoji font"
        ],
        onTap: () {
          ns.pushAndRemoveSettingsUntil(
            context,
            ThemingPanel(),
            (Route route) => route.isFirst,
          );
        },
        child: BBSettingsSection(
          backgroundColor: tileColor,
          children: [
            BBSettingsTile(
              title: "Appearance Settings",
              onTap: () {
                ns.pushAndRemoveSettingsUntil(
                  context,
                  ThemingPanel(),
                  (Route route) => route.isFirst,
                );
              },
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  "${SettingsSvc.settings.skin.value.toString().split(".").last}  |  ${AdaptiveTheme.of(context).mode.toString().split(".").last.capitalizeFirst!}",
                  style: context.theme.textTheme.bodyMedium!
                      .apply(color: context.theme.colorScheme.outline.withValues(alpha: 0.85)),
                ),
                const SizedBox(width: 5),
                const NextButton(),
              ]),
              leading: const BBSettingsIcon(
                  iosIcon: CupertinoIcons.paintbrush_fill,
                  materialIcon: Icons.palette,
                  color: Colors.blueGrey),
            ),
          ],
        )),
    const SearchableSettingItem(
      title: "Application Settings", // Title to search
      child: BBSettingsHeader(
        text: "Application Settings",
      ),
    ),

    SettingsSection(
      backgroundColor: tileColor,
      searchableSettingsItems: [
        // Media Settings Tile
        SearchableSettingItem(
          title: "Media Settings", // Title to search
          searchTags: [
            "Auto-download Attachments",
            "Only Auto-download Attachments on WiFi",
            "Auto-save Attachments",
            "Save Media Location",
            "Enter Relative Path",
            "Save Documents Location",
            "Ask Where to Save Attachments",
            "Mute in Attachment Preview",
            "Mute in Fullscreen Player",
            "Arrow key direction",
            "Swipe Direction"
          ],
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const AttachmentPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            title: "Media Settings",
            onTap: () {
              ns.pushAndRemoveSettingsUntil(
                context,
                const AttachmentPanel(),
                (Route route) => route.isFirst,
              );
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.photo_fill,
              materialIcon: Icons.attachment,
              iconSize: 18,
              color: Colors.deepPurpleAccent,
            ),
            trailing: const NextButton(),
          ),
        ),

        // Notification Settings Tile
        SearchableSettingItem(
          title: "Notification Settings", // Title to search
          searchTags: [
            "Send Notifications on Chat List",
            "Notify for Reactions",
            "Notification Sound",
            "Text Detection",
            "Hide Message Text",
            "Notify When Incremental Sync Complete",
            "Global options",
            "Chat options"
          ],
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const NotificationPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            title: "Notification Settings",
            onTap: () {
              ns.pushAndRemoveSettingsUntil(
                context,
                const NotificationPanel(),
                (Route route) => route.isFirst,
              );
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.bell_fill,
              materialIcon: Icons.notifications_on,
              color: Colors.redAccent,
            ),
            trailing: const NextButton(),
          ),
        ),

        // Chat List Settings Tile
        SearchableSettingItem(
          title: "Chat List Settings", // Title to search
          searchTags: [
            "Show Connection Indicator",
            "Show Sync Indicator in Chat List",
            "Message Status Indicators",
            "Filtered Chat List",
            "Filter Unknown Senders",
            "Unarchive Chats On New Message",
            "Hide Dividers",
            "Dense Conversation Tiles",
            "Pin Configuration",
            "Pin Rows",
            "Pins Per Row",
            "Pinned Order",
            "Swipe Actions for Conversation Tiles",
            "Swipe Right Action",
            "Swipe Left Action",
            "Move Chat Creator Button to Header",
            "Long Press for Camera"
          ],
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const ChatListPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            title: "Chat List Settings",
            onTap: () {
              ns.pushAndRemoveSettingsUntil(
                context,
                const ChatListPanel(),
                (Route route) => route.isFirst,
              );
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.square_list_fill,
              materialIcon: Icons.list,
              color: Colors.blueAccent,
            ),
            trailing: const NextButton(),
          ),
        ),

        // Conversation Settings Tile
        SearchableSettingItem(
          title: "Conversation Settings", // Title to search
          searchTags: [
            "Show Delivery Timestamps",
            "Show Chat Name as Placeholder",
            "Show Avatars in DM Chats",
            "Smart Suggestions",
            "Show Replies To Previous Message",
            "Message Options Order",
            "Sync Group Chat Icons",
            "Store Last Read Message",
            "Hide Names in Reaction Details",
            "Add Send/Receive Sound",
            "Send/Receive Sound Volume",
            "Auto-open Keyboard",
            "Swipe Message Box to Close Keyboard",
            "Swipe Message Box to Open Keyboard",
            "Hide Keyboard When Scrolling",
            "Open Keyboard After Tapping Scroll To Bottom",
            "Double-Tap Message",
            "Send Message with Enter",
            "Scroll to Bottom When Sending Messages"
          ],
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const ConversationPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            title: "Conversation Settings",
            onTap: () {
              ns.pushAndRemoveSettingsUntil(
                context,
                const ConversationPanel(),
                (Route route) => route.isFirst,
              );
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.chat_bubble_fill,
              materialIcon: Icons.sms,
              color: Colors.green,
            ),
            trailing: const NextButton(),
          ),
        ),

        if (kIsDesktop)
          // Desktop Settings Tile
          SearchableSettingItem(
              title: "Desktop Settings", // Title to search,
              searchTags: [
                "Desktop Settings",
                "Launch on Startup",
                "Launch on Startup Minimized",
                "Use Custom TitleBar",
                "Minimize to Tray",
                "Close to Tray",
                "Desktop Notifications",
                "Notification Sound Volume",
                "Actions",
                "Show Reply Field"
              ],
              onTap: () {
                ns.pushAndRemoveSettingsUntil(
                  context,
                  const DesktopPanel(),
                  (Route route) => route.isFirst,
                );
              },
              child: BBSettingsTile(
                title: "Desktop Settings",
                onTap: () {
                  ns.pushAndRemoveSettingsUntil(
                    context,
                    const DesktopPanel(),
                    (Route route) => route.isFirst,
                  );
                },
                leading: const BBSettingsIcon(
                  iosIcon: CupertinoIcons.desktopcomputer,
                  materialIcon: Icons.desktop_windows,
                ),
                trailing: const NextButton(),
              )),

        // More Settings Tile
        SearchableSettingItem(
          title: "More settings", // Title to search,
          searchTags: [
            "Advanced",
            "Secure App",
            "Security Level",
            "Incognito Keyboard",
            "High Performance Mode",
            "Scroll Speed Multiplier",
            "API Timeout Duration",
            "Cancel Queued Messages on Failure",
            "Replace Emoticons with Emoji",
            "Enable Spellcheck",
            "Send Delay",
            "Use 24 Hour Format for Times",
            "Allow Upside-Down Rotation",
            "Maximum Group Avatar Count"
          ],
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const MiscPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            title: "More Settings",
            onTap: () {
              ns.pushAndRemoveSettingsUntil(
                context,
                const MiscPanel(),
                (Route route) => route.isFirst,
              );
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.ellipsis_circle_fill,
              materialIcon: Icons.more_vert,
            ),
            trailing: const NextButton(),
          ),
        )
      ],
    ),

    // Desktop Settings Tile (only for desktop)
    if (kIsDesktop)
      SearchableSettingItem(
        title: "Desktop Settings", // Title to search
        searchTags: [
          "Launch on Startup",
          "Launch on Startup Minimized",
          "Use Custom TitleBar",
          "Minimize to Tray",
          "Close to Tray",
          "Desktop Notifications",
          "Notification Sound Volume",
          "Actions",
          "Show Reply Field"
        ],
        onTap: () {
          ns.pushAndRemoveSettingsUntil(
            context,
            const DesktopPanel(),
            (Route route) => route.isFirst,
          );
        },
        child: BBSettingsTile(
          title: "Desktop Settings",
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const DesktopPanel(),
              (Route route) => route.isFirst,
            );
          },
          leading: const BBSettingsIcon(
            iosIcon: CupertinoIcons.desktopcomputer,
            materialIcon: Icons.desktop_windows,
          ),
          trailing: const NextButton(),
        ),
      ),
    const SearchableSettingItem(
      title: "Advanced", // Title to search
      child: BBSettingsHeader(
        text: "Advanced",
      ),
    ),

    SettingsSection(
      backgroundColor: tileColor,
      searchableSettingsItems: [
        // Private API Features Tile
        SearchableSettingItem(
          title: "Private API Features", // Title to search
          searchTags: [
            "Set up Private API Features",
            "Enable Private API Features",
            "Send Typing Indicators",
            "Automatic Mark Read / Send Read Receipts",
            "Manual Mark Read / Send Read Receipts",
            "Double Tap/Click",
            "Quick Tapback",
            "Up Arrow for Quick Edit",
            "Send Subject Lines",
            "Private API Send",
            "Private API Attachment Send"
          ],
          onTap: () async {
            ns.pushAndRemoveSettingsUntil(
              context,
              PrivateAPIPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: PrivateAPITile(tileColor: tileColor),
        ),

        // Redacted Mode Tile
        SearchableSettingItem(
          title: "Redacted Mode", // Title to search
          searchTags: [
            "Enable Redacted Mode",
            "Hide Message Content",
            "Hide Attachments",
            "Hide Contact Info",
            "Generate Fake Avatars"
          ],
          onTap: () async {
            ns.pushAndRemoveSettingsUntil(
              context,
              const RedactedModePanel(),
              (Route route) => route.isFirst,
            );
          },
          child: RedactedModeTile(tileColor: tileColor),
        ),

        // Tasker Integration Tile (only for Android)
        if (Platform.isAndroid)
          SearchableSettingItem(
            title: "Tasker Integration", // Title to search
            searchTags: ["Tasker Integration Details", "Send Events to Tasker"],
            onTap: () async {
              ns.pushAndRemoveSettingsUntil(
                context,
                const TaskerPanel(),
                (Route route) => route.isFirst,
              );
            },
            child: BBSettingsTile(
              title: "Tasker Integration",
              trailing: const NextButton(),
              onTap: () async {
                ns.pushAndRemoveSettingsUntil(
                  context,
                  const TaskerPanel(),
                  (Route route) => route.isFirst,
                );
              },
              leading: const BBSettingsIcon(
                iosIcon: CupertinoIcons.bolt_fill,
                materialIcon: Icons.electric_bolt_outlined,
                color: Colors.orangeAccent,
              ),
            ),
          ),

        // Notification Providers Tile
        SearchableSettingItem(
          title: "Notification Providers", // Title to search
          searchTags: ["Google Firebase (FCM)", "Background Service", "Unified Push"], // Search tags
          onTap: () async {
            ns.pushAndRemoveSettingsUntil(
              context,
              const NotificationProvidersPanel(),
              (Route route) => route.isFirst,
            );
          }, // On tap to search
          child: BBSettingsTile(
            onTap: () async {
              ns.pushAndRemoveSettingsUntil(
                context,
                const NotificationProvidersPanel(),
                (Route route) => route.isFirst,
              );
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.bell,
              materialIcon: Icons.notifications,
              color: Colors.green,
            ),
            title: "Notification Providers",
            trailing: const NextButton(),
          ),
        ),

        // Developer Tools Tile
        SearchableSettingItem(
          title: "Developer Tools", // Title to search
          searchTags: [
            "Fetch Contacts With Verbose Logging",
            "View Latest Log",
            "Download / Share Logs",
            "Open Logs",
            "Clear Logs",
            "Open App Data Location",
            "Disable Battery Optimizations",
            "Clear Last Opened Chat",
            "Sync Handles & Contacts",
            "Sync Chat Info"
          ], // Tags to search
          onTap: () async {
            ns.pushAndRemoveSettingsUntil(
              context,
              const TroubleshootPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            onTap: () async {
              ns.pushAndRemoveSettingsUntil(
                context,
                const TroubleshootPanel(),
                (Route route) => route.isFirst,
              );
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.wrench_fill,
              materialIcon: Icons.adb,
              color: Colors.blueAccent,
            ),
            title: "Developer Tools",
            subtitle: "View logs, troubleshoot bugs, and more",
            trailing: const NextButton(),
          ),
        ),
      ],
    ),

    const SearchableSettingItem(
      title: "Backup and restore",
      child: BBSettingsHeader(text: "Backup and Restore"),
    ),

    SettingsSection(
      backgroundColor: tileColor,
      searchableSettingsItems: [
        SearchableSettingItem(
          title: "Backup & Restore",
          searchTags: [
            "Overwrite Backup?",
            "Delete Backup?",
            "Restore Backup?",
            "Create New",
            "Restore Local",
            "Restore Settings?",
          ],
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const BackupRestorePanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            onTap: () {
              ns.pushAndRemoveSettingsUntil(
                context,
                const BackupRestorePanel(),
                (Route route) => route.isFirst,
              );
            },
            trailing: const NextButton(),
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.cloud_upload_fill,
              materialIcon: Icons.backup,
              color: Colors.amber,
            ),
            title: "Backup & Restore",
            subtitle: "Backup and restore all app settings and custom themes",
          ),
        ),

        if (!kIsWeb && !kIsDesktop)
          SearchableSettingItem(
            title: "Export Contacts", // Title to search
            child: BBSettingsTile(
              onTap: () async {
                void closeDialog() {
                  Get.closeAllSnackbars();
                  Navigator.of(context).pop();
                  Future.delayed(const Duration(milliseconds: 400), () {
                    progress.value = null;
                    totalSize.value = null;
                  });
                }

                BBCustomDialog.show(
                  context: context,
                  content: ContactUploadProgress(
                    progress: progress,
                    totalSize: totalSize,
                    uploadingContacts: uploadingContacts,
                    onClose: closeDialog,
                  ),
                );

                final contacts = <Map<String, dynamic>>[];
                final allContacts = await ContactsSvcV2.getAllContacts();
                for (ContactV2 c in allContacts) {
                  var map = c.toMap();
                  contacts.add(map);
                }
                HttpSvc.createContact(contacts, onSendProgress: (count, total) {
                  uploadingContacts.value = true;
                  progress.value = count / total;
                  totalSize.value = total;
                  if (progress.value == 1.0) {
                    uploadingContacts.value = false;
                    showSnackbar("Notice", "Successfully exported contacts to server");
                  }
                }).catchError((err, stack) {
                  if (err is Response) {
                    Logger.error(err.data["error"]["message"].toString(), error: err, trace: stack);
                  } else {
                    Logger.error("Failed to create contact!", error: err, trace: stack);
                  }

                  closeDialog.call();
                  showSnackbar("Error", "Failed to export contacts to server");
                  return Response(requestOptions: RequestOptions(path: ''));
                });
              },
              leading: const BBSettingsIcon(
                iosIcon: CupertinoIcons.person_2_fill,
                materialIcon: Icons.contacts,
                color: Colors.green,
              ),
              title: "Export Contacts",
              subtitle: "Send contacts to server for use on the desktop app",
            ),
          ),
        // About & Links Section
        SearchableSettingItem(
          title: "Leave Us a Review", // Title to search
          child: BBSettingsTile(
            title: "Leave Us a Review",
            subtitle:
                "Enjoying the app? Leave us a review on the ${Platform.isAndroid ? 'Google Play Store' : 'Microsoft Store'}!",
            onTap: () async {
              final InAppReview inAppReview = InAppReview.instance;
              inAppReview.openStoreListing(microsoftStoreId: '9P3XF8KJ0LSM');
            },
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.star_fill,
              materialIcon: Icons.star,
              color: Colors.blue,
            ),
          ),
        ),

        if (!kIsWeb && (Platform.isAndroid || Platform.isWindows))
          SearchableSettingItem(
            title: "Make a Donation", // Title to search
            child: BBSettingsTile(
              title: "Make a Donation",
              subtitle: "Support the developers by making a one-time or recurring donation to the BlueBubbles Team!",
              onTap: () async {
                await launchUrl(Uri(scheme: "https", host: "bluebubbles.app", path: "donate"),
                    mode: LaunchMode.externalApplication);
              },
              leading: const BBSettingsIcon(
                iosIcon: CupertinoIcons.money_dollar_circle,
                materialIcon: Icons.attach_money,
                color: Colors.green,
              ),
            ),
          ),

        SearchableSettingItem(
          title: "Join Our Discord", // Title to search
          child: BBSettingsTile(
            title: "Join Our Discord",
            subtitle: "Join our Discord server to chat with other BlueBubbles users and the developers",
            onTap: () async {
              await launchUrl(Uri(scheme: "https", host: "discord.gg", path: "hbx7EhNFjp"),
                  mode: LaunchMode.externalApplication);
            },
            leading: BBSettingsIcon(
              iosIcon: Icons.discord,
              materialIcon: Icons.discord,
              color: HexColor('#7785CC'),
            ),
          ),
        ),

        SearchableSettingItem(
          title: "About & More", // Title to search
          searchTags: [
            "BlueBubbles Website",
            "Documentation",
            "Source Code",
            "Report a Bug",
            "Changelog",
            "Developers",
            "Keyboard Shortcuts",
            "About"
          ],
          onTap: () {
            ns.pushAndRemoveSettingsUntil(
              context,
              const AboutPanel(),
              (Route route) => route.isFirst,
            );
          },
          child: BBSettingsTile(
            title: "About & More",
            subtitle: "Links, Changelog, & More",
            onTap: () {
              ns.pushAndRemoveSettingsUntil(
                context,
                const AboutPanel(),
                (Route route) => route.isFirst,
              );
            },
            trailing: const NextButton(),
            leading: const BBSettingsIcon(
              iosIcon: CupertinoIcons.info_circle_fill,
              materialIcon: Icons.info,
              color: Colors.blueAccent,
            ),
          ),
        ),

// Danger Zone Section
        if (!kIsWeb)
          SearchableSettingItem(
            title: "Delete All Attachments", // Title to search
            child: BBSettingsTile(
              onTap: () async {
                final confirmed = await BBAlertDialog.confirm(
                  context: context,
                  title: "Are you sure?",
                  message: "This will remove all attachments from this app. Recent attachments will be automatically re-downloaded when you enter a chat. This will not delete attachments from your server.",
                  confirmLabel: "Yes",
                  cancelLabel: "No",
                  isDestructive: true,
                );

                if (confirmed) {
                  final dir = Directory("${FilesystemSvc.appDocDir.path}/attachments");
                  await dir.delete(recursive: true);
                  showSnackbar("Success", "Deleted cached attachments");
                }
              },
              leading: BBSettingsIcon(
                iosIcon: CupertinoIcons.trash_slash_fill,
                materialIcon: Icons.delete_forever_outlined,
                color: Colors.red[700],
              ),
              title: "Delete All Attachments",
              subtitle: "Remove all attachments from this app",
            ),
          ),

        if (!kIsWeb)
          SearchableSettingItem(
            title: "Reset App", // Title to search
            child: BBSettingsTile(
              onTap: () async {
                final confirmed = await BBAlertDialog.confirm(
                  context: context,
                  title: "Are you sure?",
                  message: "This will delete all app data, including your settings, messages, attachments, and more. This action cannot be undone. It is recommended that you take a backup of your settings before proceeding. This will also close the app once the process is complete.",
                  confirmLabel: "Yes",
                  cancelLabel: "No",
                  isDestructive: true,
                );

                if (confirmed) {
                  FilesystemSvc.deleteDB();
                  SocketSvc.forgetConnection();
                  SettingsSvc.settings = Settings();
                  await SettingsSvc.settings.saveAsync();

                  await PrefsSvc.i.clear();
                  await PrefsSvc.i.setString("selected-dark", "OLED Dark");
                  await PrefsSvc.i.setString("selected-light", "Bright White");
                  Database.themes.putMany(ThemesService.defaultThemes);

                  await FCMData.deleteFcmData();

                  try {
                    if (FirebaseSvc.token != null) {
                      await MethodChannelSvc.invokeMethod("firebase-delete-token");
                    }
                  } catch (e, s) {
                    Logger.error("Failed to delete Firebase FCM token", error: e, trace: s);
                  }

                  exit(0);
                }
              },
              leading: BBSettingsIcon(
                iosIcon: CupertinoIcons.refresh_circled_solid,
                materialIcon: Icons.refresh_rounded,
                color: Colors.red[700],
              ),
              title: kIsWeb ? "Logout" : "Reset App",
              subtitle: kIsWeb ? null : "Resets the app to default settings",
            ),
          ),
      ],
    ),
  ];
}
