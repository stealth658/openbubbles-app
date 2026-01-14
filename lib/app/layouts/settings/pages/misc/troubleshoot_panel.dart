import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/app/components/settings/settings.dart';
import 'package:bluebubbles/app/layouts/settings/pages/misc/logging_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/log_level_selector.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/helpers/backend/settings_helpers.dart';
import 'package:bluebubbles/services/backend/sync/chat_sync_manager.dart';
import 'package:bluebubbles/core/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/core/utils/share_utils.dart';
import 'package:disable_battery_optimization/disable_battery_optimization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';

class TroubleshootPanel extends StatefulWidget {
  const TroubleshootPanel({super.key});

  @override
  State<StatefulWidget> createState() => _TroubleshootPanelState();
}

class _TroubleshootPanelState extends OptimizedState<TroubleshootPanel> {
  final RxnBool resyncingHandles = RxnBool();
  final RxnBool resyncingChats = RxnBool();
  final RxInt logFileCount = 1.obs;
  final RxInt logFileSize = 0.obs;
  final RxBool optimizationsDisabled = false.obs;

  bool isExportingLogs = false;

  @override
  void initState() {
    super.initState();

    // Count how many .log files are in the log directory
    final Directory logDir = Directory(Logger.logDir);
    if (logDir.existsSync()) {
      final List<FileSystemEntity> files = logDir.listSync();
      final logFiles = files.where((file) => file.path.endsWith(".log")).toList();
      logFileCount.value = logFiles.length;

      // Size in KB
      for (final file in logFiles) {
        logFileSize.value += file.statSync().size ~/ 1024;
      }
    }

    // Check if battery optimizations are disabled
    if (Platform.isAndroid) {
      DisableBatteryOptimization.isAllBatteryOptimizationDisabled.then((value) {
        optimizationsDisabled.value = value ?? false;
      });
    }
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
                  BBSettingsSection(
                    backgroundColor: tileColor,
                    children: [
                      BBSettingsTile(
                        onTap: () async {
                          final RxList<String> log = <String>[].obs;
                          BBCustomDialog.show(
                            context: context,
                            title: "Fetching contacts...",
                            content: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: SizedBox(
                                width: NavigationSvc.width(context) * 4 / 5,
                                height: Get.context!.height * 1 / 3,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(25),
                                    color: Theme.of(context).colorScheme.background,
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  child: Obx(() => ListView.builder(
                                        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                                        itemBuilder: (context, index) {
                                          return Text(
                                            log[index],
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.onBackground,
                                              fontSize: 10,
                                            ),
                                          );
                                        },
                                        itemCount: log.length,
                                      )),
                                ),
                              ),
                            ),
                            actions: const [],
                          );
                          await ContactsSvcV2.fetchNetworkContacts(logger: (newLog) {
                            log.add(newLog);
                          });
                        },
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.group,
                          materialIcon: Icons.contacts,
                        ),
                        title: "Fetch Contacts With Verbose Logging",
                        subtitle:
                            "This will fetch contacts from the server with extra info to help devs debug contacts issues",
                      ),
                    ],
                  ),
                if (isWebOrDesktop)
                  const BBSettingsHeader(text: "Logging"),
                BBSettingsSection(
                  backgroundColor: tileColor,
                  children: [
                  const LogLevelSelector(),
                  BBSettingsTile(
                    title: "View Latest Log",
                    subtitle: "View the latest log file. Useful for debugging issues, in app.",
                    leading: const BBSettingsIcon(
                      iosIcon: CupertinoIcons.doc_append,
                      materialIcon: Icons.document_scanner_rounded,
                      color: Colors.blueAccent,
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
                    BBSettingsTile(
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.share_up,
                          materialIcon: Icons.share,
                          color: Colors.green,
                        ),
                        title: "Download / Share Logs",
                        subtitle: "${logFileCount.value} log file(s) | ${logFileSize.value} KB",
                        onTap: () async {
                          if (logFileCount.value == 0) {
                            showSnackbar("No Logs", "There are no logs to download!");
                            return;
                          }

                          if (isExportingLogs) return;
                          isExportingLogs = true;

                          try {
                            showSnackbar("Please Wait", "Compressing ${logFileCount.value} log file(s)...");
                            String filePath = Logger.compressLogs();
                            final File zippedLogFile = File(filePath);

                            // Copy the file to downloads
                            String newPath = await FilesystemSvc.saveToDownloads(zippedLogFile);

                            // Delete the original file
                            zippedLogFile.deleteSync();

                            // Let the user know what happened
                            showSnackbar(
                              "Logs Exported",
                              "Logs have been exported to your downloads folder. Tap here to share it.",
                              durationMs: 5000,
                              onTap: (snackbar) async {
                                Share.files([newPath]);
                              },
                            );
                          } catch (ex, stacktrace) {
                            Logger.error("Failed to export logs!", error: ex, trace: stacktrace);
                            showSnackbar("Failed to export logs!", "Error: ${ex.toString()}");
                          } finally {
                            isExportingLogs = false;
                          }
                        }),
                  if (kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                  if (kIsDesktop)
                    BBSettingsTile(
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.doc,
                          materialIcon: Icons.file_open,
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
                  BBSettingsTile(
                      leading: const BBSettingsIcon(
                        iosIcon: CupertinoIcons.trash,
                        materialIcon: Icons.delete,
                        color: Colors.redAccent,
                      ),
                      title: "Clear Logs",
                      subtitle: "Deletes all stored log files.",
                      onTap: () async {
                        Logger.clearLogs();
                        showSnackbar("Logs Cleared", "All logs have been deleted.");
                        logFileCount.value = 0;
                        logFileSize.value = 0;
                      }),
                  if (kIsDesktop) const SettingsDivider(),
                  if (kIsDesktop)
                    BBSettingsTile(
                      leading: const BBSettingsIcon(
                        iosIcon: CupertinoIcons.folder,
                        materialIcon: Icons.folder,
                      ),
                      title: "Open App Data Location",
                      subtitle: FilesystemSvc.appDocDir.path,
                      onTap: () async => await launchUrl(Uri.file(FilesystemSvc.appDocDir.path)),
                    ),
                ]),
                if (Platform.isAndroid)
                  const BBSettingsHeader(text: "Optimizations"),
                if (Platform.isAndroid)
                  BBSettingsSection(
                    backgroundColor: tileColor,
                    children: [
                    BBSettingsTile(
                        onTap: () async {
                          if (optimizationsDisabled.value) {
                            showSnackbar(
                                "Already Disabled", "Battery optimizations are already disabled for BlueBubbles");
                            return;
                          }

                          final optsDisabled = await disableBatteryOptimizations();
                          if (!optsDisabled) {
                            showSnackbar("Error", "Battery optimizations were not disabled. Please try again.");
                          }
                        },
                        leading: Obx(() => BBSettingsIcon(
                              iosIcon: CupertinoIcons.battery_25,
                              materialIcon: Icons.battery_5_bar,
                              color: optimizationsDisabled.value ? Colors.green : Colors.redAccent,
                            )),
                        title: "Disable Battery Optimizations",
                        subtitle:
                            "Allow app to run in the background via the OS. This may not do anything on some devices.",
                        trailing: Obx(() => !optimizationsDisabled.value
                            ? const NextButton()
                            : Icon(Icons.check, color: context.theme.colorScheme.outline))),
                  ]),
                const BBSettingsHeader(text: "Troubleshooting"),
                BBSettingsSection(
                  backgroundColor: tileColor,
                  children: [
                  BBSettingsTile(
                      onTap: () async {
                        await PrefsSvc.i.remove("lastOpenedChat");
                        showSnackbar("Success", "Successfully cleared the last opened chat!");
                      },
                      leading: const BBSettingsIcon(
                        iosIcon: CupertinoIcons.rectangle_badge_xmark,
                        materialIcon: Icons.folder_delete_outlined,
                        color: Colors.orange,
                      ),
                      title: "Clear Last Opened Chat",
                      subtitle: "Use this if you are experiencing the app opening an incorrect chat")
                ]),
                if (!kIsWeb)
                  const BBSettingsHeader(text: "Database Re-syncing"),
                if (!kIsWeb)
                  BBSettingsSection(
                    backgroundColor: tileColor,
                    children: [
                    BBSettingsTile(
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
                            Logger.error("Failed to reset contacts!", error: ex, trace: stacktrace);

                            showSnackbar("Failed to re-sync handles!", "Error: ${ex.toString()}");
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
                    BBSettingsTile(
                        title: "Sync Chat Info",
                        subtitle:
                            "This will re-sync all chat data & icons from the server to ensure that you have the most up-to-date information.\n\nNote: This will overwrite any group chat icons that are not locked!",
                        onTap: () async {
                          resyncingChats.value = true;
                          try {
                            showSnackbar("Please Wait...", "This may take a few minutes.");

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
                if (kIsDesktop) const SizedBox(height: 100),
              ],
            ),
          ),
        ]);
  }
}
