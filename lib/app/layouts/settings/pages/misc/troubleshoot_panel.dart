import 'package:bluebubbles/app/layouts/chat_selector_view/chat_selector_view.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/sync_time_range_dialog.dart';
import 'package:bluebubbles/app/layouts/settings/dialogs/sync_dialog.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/handle_audit_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/soft_deleted_chats_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/logging_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/log_level_selector.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/backend/settings_helpers.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/services/backend/sync/chat_sync_manager.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/share.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;




class TroubleshootPanel extends StatefulWidget {
  const TroubleshootPanel({super.key});

  @override
  State<StatefulWidget> createState() => _TroubleshootPanelState();
}

class _TroubleshootPanelState extends State<TroubleshootPanel> with ThemeHelpers, WidgetsBindingObserver {
  final RxnBool resyncingHandles = RxnBool();
  final RxnBool resyncingChats = RxnBool();
  final RxInt logFileCount = 0.obs;
  final RxInt logFileSize = 0.obs;
  final RxBool optimizationsDisabled = false.obs;
  final TextEditingController participantController = TextEditingController();

  bool isExportingLogs = false;
  final RxnBool reregisteringIds = RxnBool();

  @override
  void initState() {
    super.initState();
    _refreshLogStats();
    WidgetsBinding.instance.addObserver(this);
    _refreshBatteryOptimizationStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Toggling the exemption happens in the system settings app, so the only signal we
    // get that it changed is coming back to the foreground.
    if (state == AppLifecycleState.resumed) _refreshBatteryOptimizationStatus();
  }

  Future<void> _refreshBatteryOptimizationStatus() async {
    if (!Platform.isAndroid) return;
    final isDisabled = await isBatteryOptimizationDisabled();
    if (!mounted) return;
    optimizationsDisabled.value = isDisabled;
  }

  void _refreshLogStats() {
    int count = 0;
    int sizeKb = 0;

    final Directory logDir = Directory(Logger.logDir);
    if (logDir.existsSync()) {
      final List<FileSystemEntity> files = logDir.listSync();
      final List<FileSystemEntity> logFiles = files.where((file) => file.path.endsWith(".log")).toList();
      count = logFiles.length;

      for (final file in logFiles) {
        sizeKb += file.statSync().size ~/ 1024;
      }
    }

    logFileCount.value = count;
    logFileSize.value = sizeKb;
  }

  @override
  Widget build(BuildContext context) {
    bool isWebOrDesktop = kIsWeb || kIsDesktop;
    return SettingsScaffold(
        title: "Developer Tools",
        initialHeader: (isWebOrDesktop) ? "Contacts" : "Logging",
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        tileColor: tileColor,
        headerColor: headerColor,
        bodySlivers: [
          SliverList(
            delegate: SliverChildListDelegate(
              <Widget>[
                if (isWebOrDesktop)
                  SettingsSection(
                    backgroundColor: tileColor,
                    children: [
                      SettingsTile(
                        onTap: () async {
                          final RxList<String> log = <String>[].obs;
                          showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                    backgroundColor: context.theme.colorScheme.surface,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                                    titlePadding: const EdgeInsets.only(top: 15),
                                    title: Text("Fetching contacts...", style: context.theme.textTheme.titleLarge),
                                    content: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: SizedBox(
                                        width: NavigationSvc.width(context) * 4 / 5,
                                        height: context.height * 1 / 3,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(25),
                                            color: context.theme.colorScheme.surface,
                                          ),
                                          padding: const EdgeInsets.all(10),
                                          child: Obx(() => ListView.builder(
                                                physics: const AlwaysScrollableScrollPhysics(
                                                    parent: BouncingScrollPhysics()),
                                                itemBuilder: (context, index) {
                                                  return Text(
                                                    log[index],
                                                    style: TextStyle(
                                                      color: context.theme.colorScheme.onSurface,
                                                      fontSize: 10,
                                                    ),
                                                  );
                                                },
                                                itemCount: log.length,
                                              )),
                                        ),
                                      ),
                                    ),
                                  ));
                          await ContactsSvcV2.fetchNetworkContacts(logger: (newLog) {
                            log.add(newLog);
                          });
                        },
                        leading: const SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.group,
                          materialIcon: Icons.contacts,
                          containerColor: Colors.green,
                        ),
                        title: "Fetch Contacts With Verbose Logging",
                        subtitle:
                            "This will fetch contacts from the server with extra info to help devs debug contacts issues",
                      ),
                    ],
                  ),
                if (isWebOrDesktop)
                  SettingsHeader(iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Logging"),
                SettingsSection(backgroundColor: tileColor, children: [
                  const LogLevelSelector(),
                  SettingsTile(
                    title: "View Latest Log",
                    subtitle: "View the latest log file. Useful for debugging issues, in app.",
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.doc_append,
                      materialIcon: Icons.document_scanner_rounded,
                      containerColor: Colors.blueAccent,
                    ),
                    onTap: () {
                      NavigationSvc.pushSettings(
                        context,
                        const LoggingPanel(),
                      );
                    },
                    trailing: const NextButton(),
                  ),
                  if (Platform.isAndroid) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (Platform.isAndroid)
                    Obx(
                      () => SettingsTile(
                          leading: const SettingsLeadingIcon(
                            iosIcon: CupertinoIcons.share_up,
                            materialIcon: Icons.share,
                            containerColor: Colors.green,
                          ),
                          title: "Download / Share Logs",
                          subtitle: "${logFileCount.value} log file(s) | ${logFileSize.value} KB",
                          onTap: () async {
                            _refreshLogStats();
                            if (logFileCount.value == 0) {
                              showSnackbar("No Logs", "There are no logs to download!");
                              return;
                            }

                            if (isExportingLogs) return;
                            isExportingLogs = true;

                            try {
                              showSnackbar("Please Wait", "Compressing ${logFileCount.value} log file(s)...");
                              String filePath = await Logger.compressLogs();
                              final String fileName = File(filePath).uri.pathSegments.last;

                              try {
                                final String savedPath = await FilesystemSvc.saveToDownloads(
                                  File(filePath),
                                  mimeType: 'application/zip',
                                );
                                showSnackbar("Logs Saved", "Saved $fileName to your Downloads folder.");
                                if (kIsDesktop) await launchUrl(Uri.file(savedPath));
                              } catch (_) {
                                // saveToDownloads failed on Android — fall back to share sheet.
                                Share.files([filePath], mimeType: 'application/zip');
                              }
                            } catch (ex, stacktrace) {
                              Logger.error("Failed to export logs!", error: ex, trace: stacktrace);
                              showSnackbar("Failed to export logs!", "Error: ${ex.toString()}");
                            } finally {
                              isExportingLogs = false;
                              _refreshLogStats();
                            }
                          }),
                    ),
                  if (kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (kIsDesktop)
                    SettingsTile(
                        leading: const SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.doc,
                          materialIcon: Icons.file_open,
                          containerColor: Colors.blueGrey,
                        ),
                        title: "Open Logs",
                        subtitle: Logger.logDir,
                        onTap: () async {
                          final File logFile = File(Logger.logDir);
                          if (logFile.existsSync()) {
                            logFile.createSync(recursive: true);
                          }
                          await launchUrl(Uri.file(logFile.path));
                        }),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  SettingsTile(
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.trash,
                        materialIcon: Icons.delete,
                        containerColor: Colors.redAccent,
                      ),
                      title: "Clear Logs",
                      subtitle: "Deletes all stored log files.",
                      onTap: () async {
                        Logger.clearLogs();
                        showSnackbar("Logs Cleared", "All logs have been deleted.");
                        _refreshLogStats();
                      }),
                  if (kIsDesktop) const SettingsDivider(),
                  if (kIsDesktop)
                    SettingsTile(
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.folder,
                        materialIcon: Icons.folder,
                        containerColor: Colors.purple,
                      ),
                      title: "Open App Data Location",
                      subtitle: FilesystemSvc.appDocDir.path,
                      onTap: () async => await launchUrl(Uri.file(FilesystemSvc.appDocDir.path)),
                    ),
                ]),
                if (Platform.isAndroid)
                  SettingsHeader(iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Optimizations"),
                if (Platform.isAndroid)
                  SettingsSection(backgroundColor: tileColor, children: [
                    Obx(() => SettingsTile(
                        onTap: () async {
                          // Android exposes no API to revoke the exemption — the system
                          // prompt only ever grants it. To turn optimizations back on the
                          // user has to do it themselves, so send them to app settings and
                          // pick the status back up on resume.
                          if (optimizationsDisabled.value) {
                            await openAppSettings();
                            return;
                          }

                          final optsDisabled = await disableBatteryOptimizations();
                          await _refreshBatteryOptimizationStatus();
                          if (!optsDisabled) {
                            showSnackbar("Error", "Battery optimizations were not disabled. Please try again.");
                          }
                        },
                        leading: SettingsLeadingIcon(
                          iosIcon: CupertinoIcons.battery_25,
                          materialIcon: Icons.battery_5_bar,
                          containerColor: optimizationsDisabled.value ? Colors.green : Colors.redAccent,
                        ),
                        title: "Battery Optimizations",
                        isThreeLine: true,
                        subtitle: optimizationsDisabled.value
                            ? "Disabled — the OS lets BlueBubbles run in the background. Tap to open system settings if you want to turn optimizations back on."
                            : "Enabled — the OS may stop BlueBubbles in the background. Tap to allow it to keep running. This may not do anything on some devices.",
                        trailing: !optimizationsDisabled.value
                            ? const NextButton()
                            : Icon(Icons.check, color: context.theme.colorScheme.outline))),
                  ]),
                SettingsHeader(iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Troubleshooting"),
                SettingsSection(backgroundColor: tileColor, children: [
                  SettingsTile(
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.share,
                      materialIcon: Icons.share,
                    ),
                    title: "Export OB logs",
                    subtitle:
                        "Last 24-48 hours saved. Contains sensitive information (such as messages and identifiers); do not share publicly.",
                    onTap: () async {
                      // The rustpush layer writes its own rolling logs next to the app documents
                      // directory; they are not the Dart Logger's files.
                      var dir = Directory(Platform.isAndroid
                          ? "${FilesystemSvc.appDocDir.path}/../files/logs"
                          : "${FilesystemSvc.appDocDir.path}/logs");
                      final List<FileSystemEntity> entities = await dir.list().toList();
                      var current = entities.indexWhere((element) => element.path.endsWith("CURRENT.log"));
                      if (current == -1) {
                        return showSnackbar("Error", "No logs were found to export!");
                      }
                      var item = entities.removeAt(current);
                      var end = await File(item.path).readAsBytes();
                      var b = BytesBuilder();
                      if (entities.isNotEmpty) {
                        var next = await File(entities.first.path).readAsBytes();
                        b.add(next);
                      }
                      b.add(end);
                      var total = b.toBytes();

                      final date = DateTime.now().toIso8601String().split('T').first;
                      final File logFile = File("${FilesystemSvc.appDocDir.path}/openbubbles-logs-$date.log");
                      if (logFile.existsSync()) logFile.deleteSync();

                      await logFile.writeAsBytes(total);

                      String newPath = await FilesystemSvc.saveToDownloads(logFile);

                      // Delete the original file
                      logFile.deleteSync();

                      showSnackbar(
                        "Logs Exported",
                        "Logs have been exported to your downloads folder. Tap here to share it.",
                        durationMs: 5000,
                        onTap: (snackbar) async {
                          Share.files([newPath]);
                        },
                      );
                    },
                  ),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  SettingsTile(
                      onTap: () async {
                        await PrefsSvc.messaging.clearLastOpenedChat();
                        showSnackbar("Success", "Successfully cleared the last opened chat!");
                      },
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.rectangle_badge_xmark,
                        materialIcon: Icons.folder_delete_outlined,
                        containerColor: Colors.orange,
                      ),
                      title: "Clear Last Opened Chat",
                      subtitle: "Use this if you are experiencing the app opening an incorrect chat"),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  SettingsTile(
                    onTap: () => NavigationSvc.pushSettings(context, const SoftDeletedChatsPanel()),
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.trash_slash,
                      materialIcon: Icons.restore_from_trash,
                      containerColor: Colors.orangeAccent,
                    ),
                    title: "View Soft-Deleted Chats",
                    subtitle: "Shows only soft-deleted chats. Allows restoring them back to the main chat list.",
                    trailing: const NextButton(),
                  ),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  SettingsTile(
                      onTap: () async {
                        NavigationSvc.pushSettings(
                          context,
                          ChatSelectorView(
                            onSelect: (Chat chat) async {
                              final bool? confirmed = await showBBDialog<bool>(
                                context: context,
                                title: "Delete Chat?",
                                body:
                                    "This will permanently delete the chat, all of its messages, and all of its participants (handles). This cannot be undone.",
                                actions: [
                                  BBDialogAction(
                                    text: "Cancel",
                                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
                                  ),
                                  BBDialogAction(
                                    text: "Delete",
                                    isDestructive: true,
                                    color: Colors.redAccent,
                                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
                                  ),
                                ],
                              );

                              if (confirmed != true) return;

                              try {
                                await ChatsSvc.deleteChat(chat, deleteHandles: true);
                                showSnackbar(
                                  "Chat Deleted",
                                  "Successfully deleted chat and all associated data.",
                                );
                              } catch (ex, stacktrace) {
                                Logger.error("Failed to delete chat!", error: ex, trace: stacktrace);
                                showSnackbar("Failed to Delete Chat", "Error: ${ex.toString()}");
                              }
                            },
                          ),
                        );
                      },
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.chat_bubble_2,
                        materialIcon: Icons.delete_forever,
                        containerColor: Colors.redAccent,
                      ),
                      title: "Delete a Chat",
                      subtitle:
                          "Permanently deletes a selected chat, all its messages, and all its participants. Use this to simulate a brand-new chat arrival."),
                  const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  SettingsTile(
                      onTap: () async {
                        final bool? confirmed = await showBBDialog<bool>(
                          context: context,
                          title: "Delete All Messaging Data?",
                          body: "This will permanently delete ALL messages, attachments, chats, "
                              "participants (handles), and contacts from this device. This includes "
                              "attachment files, custom chat avatars/backgrounds, contact avatars, "
                              "and message caches. Your settings and themes will not be affected. "
                              "This cannot be undone.",
                          bodyTextAlign: TextAlign.center,
                          actions: [
                            BBDialogAction(
                              text: "Cancel",
                              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
                            ),
                            BBDialogAction(
                              text: "Delete All",
                              isDestructive: true,
                              color: Colors.redAccent,
                              onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
                            ),
                          ],
                        );

                        if (confirmed != true) return;

                        try {
                          await ChatsSvc.deleteAllMessagingData();
                          showSnackbar(
                            "Messaging Data Deleted",
                            "Successfully deleted all messages, chats, attachments, participants, and contacts.",
                          );
                        } catch (ex, stacktrace) {
                          Logger.error("Failed to delete all messaging data!", error: ex, trace: stacktrace);
                          showSnackbar("Failed to Delete Messaging Data", "Error: ${ex.toString()}");
                          return;
                        }

                        if (!context.mounted) return;
                        await showAreYouSure(
                          context,
                          title: "Sync Messages Now?",
                          content: const Text(
                              "Would you like to sync messages from the server now? You can also do this later."),
                          noText: "Not Now",
                          yesText: "Sync Now",
                          onNo: () => Navigator.of(context, rootNavigator: true).pop(),
                          onYes: () async {
                            Navigator.of(context, rootNavigator: true).pop();
                            if (!context.mounted) return;
                            final range = await showSyncTimeRangeDialog(context);
                            if (range == null) return;

                            // Same mechanism as "Manually Sync Messages" on the Server
                            // Management page: a single global message query bounded by
                            // start/end, which discovers and creates any chats referenced
                            // by the synced messages.
                            final mgr = IncrementalSyncManager(
                              startTimestamp: range.start.millisecondsSinceEpoch,
                              endTimestamp: range.end.millisecondsSinceEpoch,
                            );
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              builder: (context) => SyncDialog(manager: mgr),
                            );
                            await mgr.start();
                          },
                        );
                      },
                      leading: const SettingsLeadingIcon(
                        iosIcon: CupertinoIcons.trash,
                        materialIcon: Icons.delete_forever,
                        containerColor: Colors.redAccent,
                      ),
                      title: "Delete All Messaging Data",
                      subtitle:
                          "Permanently deletes ALL messages, chats, attachments, participants, and contacts on this device."),
                ]),
                SettingsHeader(iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Audit"),
                SettingsSection(backgroundColor: tileColor, children: [
                  SettingsTile(
                    onTap: () => NavigationSvc.pushSettings(context, const HandleAuditPanel()),
                    leading: const SettingsLeadingIcon(
                      iosIcon: CupertinoIcons.person_crop_circle_badge_exclam,
                      materialIcon: Icons.person_search,
                      containerColor: Colors.deepPurpleAccent,
                    ),
                    title: "Audit Handles",
                    subtitle: "Scans local handles for a missing originalROWID (the server-side ID used to link "
                        "messages to their sender) and lets you try to repair the affected ones.",
                    trailing: const NextButton(),
                  ),
                ]),
                if (!kIsWeb && backend.getRemoteService() != null)
                  SettingsHeader(
                      iosSubtitle: iosSubtitle,
                      materialSubtitle: materialSubtitle,
                      text: "Database Re-syncing"),
                if (!kIsWeb && backend.getRemoteService() != null)
                  SettingsSection(backgroundColor: tileColor, children: [
                    SettingsTile(
                        title: "Sync Handles & Contacts",
                        subtitle:
                            "Run this troubleshooter if you are experiencing issues with missing or incorrect contact names and photos",
                        onTap: () async {
                          resyncingHandles.value = true;
                          try {
                            final handleSyncer = HandleSyncManager();
                            await handleSyncer.start();
                            EventDispatcherSvc.emit("refresh-all", null);
                            showSnackbar("Success",
                                "Successfully re-synced handles! You may need to close and re-open the app for changes to take effect.");
                          } catch (ex, stacktrace) {
                            Logger.error("Failed to sync handles!", error: ex, trace: stacktrace);
                            showSnackbar("Failed to sync handles!", "Error: ${ex.toString()}");
                          } finally {
                            resyncingHandles.value = false;
                          }
                        },
                        trailing: Obx(() => resyncingHandles.value == null
                            ? const SizedBox.shrink()
                            : resyncingHandles.value == true
                                ? Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 20,
                                      maxWidth: 20,
                                    ),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                                    ))
                                : Icon(Icons.check, color: context.theme.colorScheme.outline))),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    SettingsTile(
                        title: "Sync Chat Info",
                        subtitle:
                            "This will re-sync all chat data & icons from the server to ensure that you have the most up-to-date information.\n\nNote: This will overwrite any group chat icons that are not locked!",
                        onTap: () async {
                          resyncingChats.value = true;
                          try {
                            final chatSyncer = ChatSyncManager();
                            await chatSyncer.start();
                            EventDispatcherSvc.emit("refresh-all", null);
                            showSnackbar("Success",
                                "Successfully synced your chat info! You may need to close and re-open the app for changes to take effect.");
                          } catch (ex, stacktrace) {
                            Logger.error("Failed to sync chat info!", error: ex, trace: stacktrace);
                            showSnackbar("Failed to sync chat info!", "Error: ${ex.toString()}");
                          } finally {
                            resyncingChats.value = false;
                          }
                        },
                        trailing: Obx(() => resyncingChats.value == null
                            ? const SizedBox.shrink()
                            : resyncingChats.value == true
                                ? Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 20,
                                      maxWidth: 20,
                                    ),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                                    ))
                                : Icon(Icons.check, color: context.theme.colorScheme.outline)))
                  ]),
                if (usingRustPush)
                  SettingsHeader(
                      iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "iMessage"),
                if (usingRustPush)
                  SettingsSection(backgroundColor: tileColor, children: [
                    SettingsTile(
                        title: "Clear identity cache",
                        subtitle: "Run this troubleshooter if you're having trouble sending messages.",
                        onTap: () async {
                          await api.invalidateIdCache(client: pushService.state!.client);
                          showSnackbar("Success", "Identity cache cleared! Try re-sending any messages.");
                        }),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    SettingsTile(
                        title: "Clear peer caches",
                        subtitle: "Run this troubleshooter if you are told to do so.",
                        onTap: () async {
                          if (reregisteringIds.value ?? false) return;
                          try {
                            reregisteringIds.value = true;
                            await pushService.invalidatePeerCaches();
                            showSnackbar("Success", "Cleared peer caches");
                          } catch (e, s) {
                            Logger.error("Failed to clear peer caches", error: e, trace: s);
                            showSnackbar("Failure", e.toString());
                          } finally {
                            reregisteringIds.value = false;
                          }
                        },
                        trailing: Obx(() => reregisteringIds.value == null
                            ? const SizedBox.shrink()
                            : reregisteringIds.value == true
                                ? Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 20,
                                      maxWidth: 20,
                                    ),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                                    ))
                                : Icon(Icons.check, color: context.theme.colorScheme.outline))),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    SettingsTile(
                        title: "Reregister",
                        subtitle: "Run this troubleshooter if you are told to do so.",
                        onTap: () async {
                          if (reregisteringIds.value ?? false) return;
                          try {
                            reregisteringIds.value = true;
                            await api.doReregister(state: pushService.state!.client);
                            showSnackbar("Success", "Registered");
                          } catch (e, s) {
                            Logger.error("Failed to reregister", error: e, trace: s);
                            showSnackbar("Failure", e.toString());
                          } finally {
                            reregisteringIds.value = false;
                          }
                        },
                        trailing: Obx(() => reregisteringIds.value == null
                            ? const SizedBox.shrink()
                            : reregisteringIds.value == true
                                ? Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 20,
                                      maxWidth: 20,
                                    ),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                                    ))
                                : Icon(Icons.check, color: context.theme.colorScheme.outline))),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    SettingsTile(
                        title: "Clear FaceTime Handles",
                        subtitle:
                            "Run this troubleshooter if you cannot use FaceTime. This will delete all links asscoiated with your account.",
                        onTap: () async {
                          if (reregisteringIds.value ?? false) return;
                          try {
                            reregisteringIds.value = true;
                            await api.clearLinks(facetime: pushService.state!.ftClient);
                            showSnackbar("Success", "Cleared Links!");
                          } catch (e, s) {
                            Logger.error("Failed to clear FaceTime links", error: e, trace: s);
                            showSnackbar("Failure", e.toString());
                          } finally {
                            reregisteringIds.value = false;
                          }
                        },
                        trailing: Obx(() => reregisteringIds.value == null
                            ? const SizedBox.shrink()
                            : reregisteringIds.value == true
                                ? Container(
                                    constraints: const BoxConstraints(
                                      maxHeight: 20,
                                      maxWidth: 20,
                                    ),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                                    ))
                                : Icon(Icons.check, color: context.theme.colorScheme.outline)))
                  ]),
                if (!kIsDesktop)
                  SettingsHeader(
                      iosSubtitle: iosSubtitle, materialSubtitle: materialSubtitle, text: "Extensions"),
                if (!kIsDesktop)
                  SettingsSection(
                    backgroundColor: tileColor,
                    children: [
                      Obx(() => SettingsSwitch(
                            onChanged: (bool val) async {
                              if (val) {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                        backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                                        title:
                                            Text("Enable development mode?", style: context.theme.textTheme.titleLarge),
                                        content: Text(
                                          'This mode is intended for developer use only. Extensions added through this mode have not been reviewed or approved by neither OpenBubbles or Google. You are responsible for ensuring the safety of your data and any extensions you add.',
                                          style: context.theme.textTheme.bodyLarge,
                                        ),
                                        actions: <Widget>[
                                          TextButton(
                                            child: Text("Cancel",
                                                style: context.theme.textTheme.bodyLarge!
                                                    .copyWith(color: context.theme.colorScheme.primary)),
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                          TextButton(
                                            child: Text("Enable",
                                                style: context.theme.textTheme.bodyLarge!
                                                    .copyWith(color: context.theme.colorScheme.primary)),
                                            onPressed: () async {
                                              Navigator.of(context).pop();
                                              SettingsSvc.settings.developerEnabled.value = true;
                                              await SettingsSvc.settings.saveOneAsync("developerEnabled");
                                            },
                                          ),
                                        ]);
                                  },
                                );
                                return;
                              }
                              SettingsSvc.settings.developerEnabled.value = val;
                              await SettingsSvc.settings.saveOneAsync("developerEnabled");
                              showSnackbar("Success", "Restart device or force quit OpenBubbles to unload extensions");
                            },
                            initialVal: SettingsSvc.settings.developerEnabled.value,
                            title: "Enable Developer Mode",
                            backgroundColor: tileColor,
                          )),
                    ],
                  ),
                if (kIsDesktop) const SizedBox(height: 100),
              ],
            ),
          ),
          if(!kIsDesktop)
          Obx(() => SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final addMember = ListTile(
                mouseCursor: MouseCursor.defer,
                title: Text("Add Service Name", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                leading: Container(
                  width: 40 * SettingsSvc.settings.avatarScale.value,
                  height: 40 * SettingsSvc.settings.avatarScale.value,
                  decoration: BoxDecoration(
                    color: !iOS ? null : context.theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: iOS ? null : Border.all(color: context.theme.colorScheme.primary, width: 3)
                  ),
                  child: Icon(
                    Icons.add,
                    color: context.theme.colorScheme.primary,
                    size: 20
                  ),
                ),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) {
                      return AlertDialog(
                        actions: [
                          TextButton(
                            child: Text("Cancel", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                            onPressed: () => Get.back(),
                          ),
                          TextButton(
                            child: Text("OK", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                            onPressed: () async {
                              SettingsSvc.settings.developerMode.add(participantController.text);
                              await SettingsSvc.settings.saveOneAsync("developerMode");
                              await es.refreshCache();
                              Get.back();
                            },
                          ),
                        ],
                        content: TextField(
                          controller: participantController,
                          decoration: const InputDecoration(
                            labelText: "Service Name",
                            border: OutlineInputBorder(),
                          ),
                          autofillHints: [AutofillHints.telephoneNumber, AutofillHints.email],
                        ),
                        title: Text("Add", style: context.theme.textTheme.titleLarge),
                        backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                      );
                    }
                  );
                },
              );

              final refreshCache = ListTile(
                mouseCursor: MouseCursor.defer,
                title: Text("Reload extensions", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                leading: Container(
                  width: 40 * SettingsSvc.settings.avatarScale.value,
                  height: 40 * SettingsSvc.settings.avatarScale.value,
                  decoration: BoxDecoration(
                    color: !iOS ? null : context.theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: iOS ? null : Border.all(color: context.theme.colorScheme.primary, width: 3)
                  ),
                  child: Icon(
                    Icons.refresh,
                    color: context.theme.colorScheme.primary,
                    size: 20
                  ),
                ),
                onTap: () async {
                  await es.refreshCache();
                  showSnackbar("Success", "Extensions reloaded!");
                },
              );

              final clear = ListTile(
                mouseCursor: MouseCursor.defer,
                title: Text("Clear services", style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.error)),
                leading: Container(
                  width: 40 * SettingsSvc.settings.avatarScale.value,
                  height: 40 * SettingsSvc.settings.avatarScale.value,
                  decoration: BoxDecoration(
                    color: !iOS ? null : context.theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: iOS ? null : Border.all(color: context.theme.colorScheme.primary, width: 3)
                  ),
                  child: Icon(
                    Icons.clear_all,
                    color: context.theme.colorScheme.error,
                    size: 20
                  ),
                ),
                onTap: () async {
                  SettingsSvc.settings.developerMode.clear();
                  await SettingsSvc.settings.saveOneAsync("developerMode");
                  showSnackbar("Success", "Restart device or force quit OpenBubbles to unload extensions");
                },
              );

              if (index == SettingsSvc.settings.developerMode.length) {
                return addMember;
              }
              if (index == SettingsSvc.settings.developerMode.length + 1) {
                return refreshCache;
              }
              if (index == SettingsSvc.settings.developerMode.length + 2) {
                return clear;
              }

              return ListTile(
                mouseCursor: MouseCursor.defer,
                title: Text(SettingsSvc.settings.developerMode[index]),
              );
            }, childCount: SettingsSvc.settings.developerEnabled.value ? SettingsSvc.settings.developerMode.length + 3 : 0),
          ),)
        ]);
  }
}
