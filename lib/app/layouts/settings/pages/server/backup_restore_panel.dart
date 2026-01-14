import 'dart:convert';

import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/app/components/settings/settings.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/core/logger/logger.dart';
import 'package:bluebubbles/core/utils/share_utils.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response;
import 'package:intl/intl.dart';
import 'package:path/path.dart' hide context;
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bluebubbles/app/components/base/base.dart' hide BBDialogAction;

class BackupRestorePanel extends StatefulWidget {
  const BackupRestorePanel({super.key});

  @override
  State<BackupRestorePanel> createState() => _BackupRestorePanelState();
}

class _BackupRestorePanelState extends OptimizedState<BackupRestorePanel> {
  List<Map<String, dynamic>> settings = [];
  List<Map<String, dynamic>> themes = [];
  bool? fetching = true;

  @override
  void initState() {
    super.initState();
    getBackups();
  }

  void getBackups() async {
    final response1 = await HttpSvc.getSettings().catchError((_) {
      setState(() {
        fetching = null;
      });
      return Response(requestOptions: RequestOptions(path: ''));
    });
    if (response1.statusCode == 200 && response1.data['data'] != null) {
      settings = response1.data['data'].cast<Map<String, dynamic>>();
      settings.sort((a, b) => DateTime.fromMillisecondsSinceEpoch(b['timestamp'] ?? 0)
          .compareTo(DateTime.fromMillisecondsSinceEpoch(a['timestamp'] ?? 0)));
      final response2 = await HttpSvc.getTheme().catchError((_) {
        setState(() {
          fetching = null;
        });
        return Response(requestOptions: RequestOptions(path: ''));
      });
      if (response2.statusCode == 200 && response2.data['data'] != null) {
        themes = response2.data['data'].cast<Map<String, dynamic>>();
        setState(() {
          fetching = false;
        });
      }
    }
  }

  void deleteSettings(String name) {
    setState(() {
      settings.removeWhere((element) => element["name"] == name);
    });
    HttpSvc.deleteSettings(name);
  }

  void deleteTheme(String name) {
    setState(() {
      themes.removeWhere((element) => element["name"] == name);
    });
    HttpSvc.deleteTheme(name);
  }

  Future<String> defaultName() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      return "Android (${androidInfo.model})";
    } else if (kIsWeb) {
      WebBrowserInfo webInfo = await deviceInfo.webBrowserInfo;
      return "Web (${webInfo.browserName.name})";
    } else if (Platform.isWindows) {
      WindowsDeviceInfo windowsInfo = await deviceInfo.windowsInfo;
      return "Windows (${windowsInfo.computerName})";
    } else if (Platform.isLinux) {
      LinuxDeviceInfo linuxInfo = await deviceInfo.linuxInfo;
      return "Linux (${linuxInfo.name})";
    }

    return "Unknown Device";
  }

  Future<bool?> showMethodDialog() async {
    return await BBAlertDialog.show<bool>(
      context: context,
      title: "Choose Backup Location",
      message: "Local - Save a backup to this device.\nCloud - Save a backup to the server for use across all your devices.",
      actions: [
        BBDialogAction(
          label: "Local",
          type: BBDialogButtonType.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        BBDialogAction(
          label: "Cloud",
          type: BBDialogButtonType.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => SettingsScaffold(
            title: "Backup and Restore",
            initialHeader: fetching == false ? "Settings Backups" : null,
            iosSubtitle: iosSubtitle,
            materialSubtitle: materialSubtitle,
            tileColor: tileColor,
            headerColor: headerColor,
            actions: [
              IconButton(
                icon: Icon(iOS ? CupertinoIcons.arrow_counterclockwise : Icons.refresh,
                    color: context.theme.colorScheme.onBackground),
                onPressed: () {
                  setState(() {
                    fetching = true;
                    settings.clear();
                    themes.clear();
                  });
                  getBackups();
                },
              ),
            ],
            bodySlivers: [
              SliverList(
                delegate: SliverChildListDelegate([
                  if (fetching == null || fetching == true)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 100),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                fetching == null ? "Something went wrong!" : "Getting backups...",
                                style: context.theme.textTheme.labelLarge,
                              ),
                            ),
                            if (fetching == true) const BBLoadingIndicator(size: 15),
                          ],
                        ),
                      ),
                    ),
                  if (fetching == false)
                    SettingsSection(
                      backgroundColor: tileColor,
                      children: [
                        if (settings.isNotEmpty)
                          Material(
                            color: Colors.transparent,
                            child: ListView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              findChildIndexCallback: (key) =>
                                  findChildIndexByKey(settings, key, (item) => item["name"]),
                              itemBuilder: (context, index) {
                                final item = settings[index];
                                return ListTile(
                                  key: ValueKey(item["name"]),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                                  mouseCursor: SystemMouseCursors.click,
                                  title: RichText(
                                    text: TextSpan(
                                      style: context.textTheme.titleMedium,
                                      children: [
                                        TextSpan(text: item["name"]),
                                        const TextSpan(text: "\n"),
                                        TextSpan(
                                          text: (item["timestamp"] is int)
                                              ? DateFormat("MMMM d, yyyy h:mm:ss a")
                                                  .format(DateTime.fromMillisecondsSinceEpoch(item["timestamp"]))
                                              : null,
                                          style: context.textTheme.titleSmall!
                                              .copyWith(color: context.theme.colorScheme.outline),
                                        ),
                                      ],
                                    ),
                                  ),
                                  subtitle: !isNullOrEmpty(item["description"]) ? Text(item["description"]) : null,
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    IconButton(
                                        icon: Icon(iOS ? CupertinoIcons.arrow_2_circlepath : Icons.sync),
                                        onPressed: () async {
                                          final confirmed = await BBAlertDialog.confirm(
                                            context: context,
                                            title: "Overwrite Backup?",
                                            message: "Are you sure you want to replace this backup with your current Settings?",
                                            isDestructive: true,
                                          );
                                          
                                          if (confirmed) {
                                            Map<String, dynamic> json =
                                                SettingsSvc.settings.toMap(includeAll: false);
                                            json["description"] = item["description"];
                                            json["timestamp"] = DateTime.now().millisecondsSinceEpoch;
                                            Response response = await HttpSvc.setSettings(item["name"], json);
                                            if (response.statusCode != 200) {
                                              showSnackbar(
                                                "Error",
                                                "Somthing went wrong",
                                              );
                                            } else {
                                              showSnackbar(
                                                "Success",
                                                "Settings exported successfully to server",
                                              );
                                            }
                                            setState(() {
                                              fetching = true;
                                              settings.clear();
                                              themes.clear();
                                            });
                                            getBackups();
                                          }
                                        }),
                                    IconButton(
                                        icon: Icon(iOS ? CupertinoIcons.trash : Icons.delete_outlined),
                                        onPressed: () async {
                                          final confirmed = await BBAlertDialog.confirm(
                                            context: context,
                                            title: "Delete Backup?",
                                            message: "Are you sure you want to delete this settings backup?",
                                            isDestructive: true,
                                          );
                                          
                                          if (confirmed) {
                                            deleteSettings(item["name"]);
                                            Navigator.of(context).pop();
                                          }
                                        })
                                  ]),
                                  onTap: () async {
                                    final confirmed = await BBAlertDialog.confirm(
                                      context: context,
                                      title: "Restore Backup?",
                                      message: "Are you sure you want to restore this backup, overwriting your current Settings?",
                                      isDestructive: true,
                                    );
                                    
                                    if (confirmed) {
                                      try {
                                        Settings.updateFromMap(item);
                                        showSnackbar("Success", "Settings restored successfully");
                                      } catch (e, s) {
                                        Logger.error("Failed to restore settings backup!", error: e, trace: s);
                                        showSnackbar(
                                            "Error", "Failed to restore settings backup! Error: ${e.toString()}");
                                      }
                                    }
                                  },
                                  onLongPress: () async {
                                    const encoder = JsonEncoder.withIndent("     ");
                                    final str = encoder.convert(item);
                                    BBCustomDialog.show(
                                      context: context,
                                      title: "Settings Data",
                                      content: SizedBox(
                                        width: NavigationSvc.width(context) * 3 / 5,
                                        height: context.height * 1 / 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(10.0),
                                          decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surface,
                                              borderRadius: const BorderRadius.all(Radius.circular(10))),
                                          child: SingleChildScrollView(
                                            child: SelectableText(
                                              str,
                                              style: Theme.of(context).textTheme.bodyLarge,
                                            ),
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        BBDialogAction(
                                          label: "Close",
                                          type: BBDialogButtonType.cancel,
                                          onPressed: () => Navigator.of(context).pop(),
                                        ),
                                      ],
                                    );
                                  },
                                  isThreeLine: !isNullOrEmpty(item["description"]),
                                );
                              },
                              itemCount: settings.length,
                            ),
                          ),
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            mouseCursor: SystemMouseCursors.click,
                            title: Text("Create New",
                                style: context.theme.textTheme.bodyLarge!
                                    .copyWith(color: context.theme.colorScheme.primary)),
                            leading: Container(
                              width: 40 * SettingsSvc.settings.avatarScale.value,
                              height: 40 * SettingsSvc.settings.avatarScale.value,
                              decoration: BoxDecoration(
                                  color:
                                      !iOS ? null : context.theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                  border: iOS ? null : Border.all(color: context.theme.colorScheme.primary, width: 3)),
                              child: Icon(
                                Icons.add,
                                color: context.theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            onTap: () async {
                              final method = await showMethodDialog();
                              if (method == null) return;
                              final deviceName = await defaultName();
                              final TextEditingController nameController = TextEditingController(text: deviceName);
                              final TextEditingController descController = TextEditingController();

                              void onDone(_context) async {
                                String name = nameController.text;
                                final desc = descController.text;
                                if (name.isEmpty) {
                                  return showSnackbar("Error", "Provide a name!");
                                } else if (settings.firstWhereOrNull((s) => s["name"] == name) != null) {
                                  final confirmed = await BBAlertDialog.confirm(
                                    context: _context,
                                    title: "Overwrite Backup?",
                                    message: "Are you sure you want to replace this backup with your current Settings?",
                                    isDestructive: true,
                                  );
                                  if (!confirmed) return;
                                  Navigator.of(_context).pop();
                                } else {
                                  Navigator.of(_context).pop();
                                }
                                Map<String, dynamic> json = SettingsSvc.settings.toMap(includeAll: false);
                                if (desc.isNotEmpty) {
                                  json["description"] = desc;
                                }
                                final timestamp = DateTime.now().millisecondsSinceEpoch;
                                json["timestamp"] = timestamp;
                                if (method) {
                                  var response = await HttpSvc.setSettings(name, json);
                                  if (response.statusCode != 200) {
                                    showSnackbar(
                                      "Error",
                                      "Somthing went wrong",
                                    );
                                  } else {
                                    showSnackbar(
                                      "Success",
                                      "Settings exported successfully to server",
                                    );
                                  }
                                } else {
                                  String directoryPath = "/storage/emulated/0/Download/BB-Settings-";
                                  String filePath = "$directoryPath$name.json";
                                  if (kIsWeb) {
                                    final bytes = utf8.encode(jsonEncode(json));
                                    final content = base64.encode(bytes);
                                    html.AnchorElement(
                                        href: "data:application/octet-stream;charset=utf-16le;base64,$content")
                                      ..setAttribute("download", basename(filePath))
                                      ..click();
                                    return;
                                  }
                                  if (kIsDesktop) {
                                    String? _filePath = await FilePicker.platform.saveFile(
                                      initialDirectory: (await getDownloadsDirectory())?.path,
                                      dialogTitle: 'Choose a location to save this file',
                                      fileName: "BB-Settings-$name.json",
                                      type: FileType.custom,
                                      allowedExtensions: ["json"],
                                    );
                                    if (_filePath == null) {
                                      return showSnackbar('Failed', 'You didn\'t select a file path!');
                                    }
                                    filePath = _filePath;
                                  }
                                  File file = File(filePath);
                                  await file.create(recursive: true);
                                  String jsonString = jsonEncode(json);
                                  await file.writeAsString(jsonString);
                                  showSnackbar(
                                    "Success",
                                    "Settings exported successfully to ${kIsDesktop ? filePath : "downloads folder"}",
                                    durationMs: kIsDesktop ? 4000 : 2000,
                                    button: TextButton(
                                      style: TextButton.styleFrom(
                                        backgroundColor: Get.theme.colorScheme.secondary,
                                      ),
                                      onPressed: () {
                                        if (kIsDesktop) {
                                          launchUrl(Uri.file(dirname(filePath)));
                                        }
                                        Share.files([filePath]);
                                      },
                                      child: Text(kIsDesktop ? "OPEN FOLDER" : "SHARE",
                                          style: TextStyle(color: context.theme.colorScheme.onSecondary)),
                                    ),
                                  );
                                }
                                setState(() {
                                  fetching = true;
                                  settings.clear();
                                  themes.clear();
                                });
                                getBackups();
                              }

                              BBCustomDialog.show(
                                context: context,
                                title: "Settings Backup Creation",
                                content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Focus(
                                            onKeyEvent: (node, event) {
                                              if (event is KeyDownEvent &&
                                                  !HardwareKeyboard.instance.isShiftPressed &&
                                                  event.logicalKey == LogicalKeyboardKey.tab) {
                                                node.nextFocus();
                                                return KeyEventResult.handled;
                                              }
                                              return KeyEventResult.ignored;
                                            },
                                            child: TextField(
                                              cursorColor: Theme.of(context).colorScheme.primary,
                                              autocorrect: true,
                                              autofocus: true,
                                              controller: nameController,
                                              textInputAction: TextInputAction.next,
                                              decoration: InputDecoration(
                                                enabledBorder: OutlineInputBorder(
                                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                                                    borderRadius: BorderRadius.circular(20)),
                                                focusedBorder: OutlineInputBorder(
                                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                                    borderRadius: BorderRadius.circular(20)),
                                                labelText: "Name",
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Focus(
                                            onKeyEvent: (node, event) {
                                              if (event is KeyDownEvent &&
                                                  HardwareKeyboard.instance.isShiftPressed &&
                                                  event.logicalKey == LogicalKeyboardKey.tab) {
                                                node.previousFocus();
                                                node.previousFocus(); // This is intentional. Should probably figure out why it's needed
                                                return KeyEventResult.handled;
                                              }
                                              return KeyEventResult.ignored;
                                            },
                                            child: TextField(
                                              cursorColor: Theme.of(context).colorScheme.primary,
                                              autocorrect: true,
                                              autofocus: false,
                                              controller: descController,
                                              textInputAction: TextInputAction.next,
                                              onSubmitted: (_) {
                                                onDone.call(context);
                                              },
                                              decoration: InputDecoration(
                                                enabledBorder: OutlineInputBorder(
                                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                                                    borderRadius: BorderRadius.circular(20)),
                                                focusedBorder: OutlineInputBorder(
                                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
                                                    borderRadius: BorderRadius.circular(20)),
                                                labelText: "Description (Optional)",
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                actions: [
                                  BBDialogAction(
                                    label: "Cancel",
                                    type: BBDialogButtonType.cancel,
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  BBDialogAction(
                                    label: "OK",
                                    type: BBDialogButtonType.primary,
                                    onPressed: () => onDone.call(context),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            mouseCursor: SystemMouseCursors.click,
                            title: Text("Restore Local",
                                style: context.theme.textTheme.bodyLarge!
                                    .copyWith(color: context.theme.colorScheme.primary)),
                            leading: Container(
                              width: 40 * SettingsSvc.settings.avatarScale.value,
                              height: 40 * SettingsSvc.settings.avatarScale.value,
                              decoration: BoxDecoration(
                                  color:
                                      !iOS ? null : context.theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                  border: iOS ? null : Border.all(color: context.theme.colorScheme.primary, width: 3)),
                              child: Icon(
                                Icons.upload,
                                color: context.theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            onTap: () async {
                              final res = await FilePicker.platform
                                  .pickFiles(withData: true, type: FileType.custom, allowedExtensions: ["json"]);
                              if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;
                              final confirmed = await BBAlertDialog.confirm(
                                context: context,
                                title: "Restore Settings?",
                                message: "Are you sure you want to restore this backup, overwriting your current Settings?",
                                isDestructive: true,
                              );
                              
                              if (confirmed) {
                                try {
                                  String jsonString = const Utf8Decoder().convert(res.files.first.bytes!);
                                  Map<String, dynamic> json = jsonDecode(jsonString);
                                  Settings.updateFromMap(json);
                                  showSnackbar("Success", "Settings restored successfully");
                                } catch (e, s) {
                                  Logger.error("Failed to restore settings backup!", error: e, trace: s);
                                  showSnackbar(
                                      "Error", "Failed to restore settings backup! Error: ${e.toString()}");
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  if (fetching == false)
                    const BBSettingsHeader(
                      text: "Theme Backups",
                    ),
                  if (fetching == false)
                    SettingsSection(
                      backgroundColor: tileColor,
                      children: [
                        if (themes.isNotEmpty)
                          Material(
                            color: Colors.transparent,
                            child: ListView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              shrinkWrap: true,
                              findChildIndexCallback: (key) => findChildIndexByKey(themes, key, (item) => item['name']),
                              itemBuilder: (context, index) {
                                final item = themes[index];
                                final data = item["data"];
                                return ListTile(
                                  key: ValueKey(item["name"]),
                                  mouseCursor: SystemMouseCursors.click,
                                  title: Text(item["name"]),
                                  subtitle: !item.containsKey('data')
                                      ? Text("Incompatible backup!",
                                          style: context.theme.textTheme.bodyMedium!
                                              .copyWith(color: context.theme.colorScheme.error))
                                      : Text(
                                          "${Brightness.values[data["colorScheme"]["brightness"]].name.capitalizeFirst!} theme"),
                                  leading: !item.containsKey('data')
                                      ? null
                                      : Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: <Widget>[
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                Padding(
                                                  padding: const EdgeInsets.all(3),
                                                  child: Container(
                                                    height: 12,
                                                    width: 12,
                                                    decoration: BoxDecoration(
                                                      color: Color(data["colorScheme"]["primary"]),
                                                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.all(3),
                                                  child: Container(
                                                    height: 12,
                                                    width: 12,
                                                    decoration: BoxDecoration(
                                                      color: Color(data["colorScheme"]["secondary"]),
                                                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: <Widget>[
                                                Padding(
                                                  padding: const EdgeInsets.all(3),
                                                  child: Container(
                                                    height: 12,
                                                    width: 12,
                                                    decoration: BoxDecoration(
                                                      color: Color(data["colorScheme"]["primaryContainer"]),
                                                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                                                    ),
                                                  ),
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.all(3),
                                                  child: Container(
                                                    height: 12,
                                                    width: 12,
                                                    decoration: BoxDecoration(
                                                      color: Color(data["colorScheme"]["tertiary"]),
                                                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                  trailing: IconButton(
                                    icon: Icon(iOS ? CupertinoIcons.trash : Icons.delete_outlined),
                                    onPressed: () async {
                                      final confirmed = await BBAlertDialog.confirm(
                                        context: context,
                                        title: "Delete Backup?",
                                        message: "Are you sure you want to delete this theme backup?",
                                        isDestructive: true,
                                      );
                                      
                                      if (confirmed) {
                                        deleteTheme(item["name"]);
                                      }
                                    },
                                  ),
                                  onTap: () async {
                                    if (!item.containsKey('data')) {
                                      return showSnackbar("Error",
                                          "This theme was created on the old theming engine and cannot be restored");
                                    }
                                    final confirmed = await BBAlertDialog.confirm(
                                      context: context,
                                      title: "Restore Backup?",
                                      message: "Are you sure you want to restore this backup, overwriting your current theme?",
                                      isDestructive: true,
                                    );
                                    
                                    if (confirmed) {
                                      try {
                                        ThemeStruct object = ThemeStruct.fromMap(item);
                                        object.id = null;
                                        object.save();
                                        showSnackbar("Success", "Theme restored successfully");
                                      } catch (e, s) {
                                        Logger.error("Failed to restore theme backup!", error: e, trace: s);
                                        showSnackbar(
                                            "Error", "Failed to restore theme backup! Error: ${e.toString()}");
                                      }
                                    }
                                  },
                                  onLongPress: () async {
                                    const encoder = JsonEncoder.withIndent("     ");
                                    final str = encoder.convert(item);
                                    BBCustomDialog.show(
                                      context: context,
                                      title: "Theme Data",
                                      content: SizedBox(
                                        width: NavigationSvc.width(context) * 3 / 5,
                                        height: context.height * 1 / 4,
                                        child: Container(
                                          padding: const EdgeInsets.all(10.0),
                                          decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surface,
                                              borderRadius: const BorderRadius.all(Radius.circular(10))),
                                          child: SingleChildScrollView(
                                            child: SelectableText(
                                              str,
                                              style: Theme.of(context).textTheme.bodyLarge,
                                            ),
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        BBDialogAction(
                                          label: "Close",
                                          type: BBDialogButtonType.cancel,
                                          onPressed: () => Navigator.of(context).pop(),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                              itemCount: themes.length,
                            ),
                          ),
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            mouseCursor: SystemMouseCursors.click,
                            title: Text("Create New",
                                style: context.theme.textTheme.bodyLarge!
                                    .copyWith(color: context.theme.colorScheme.primary)),
                            leading: Container(
                              width: 40 * SettingsSvc.settings.avatarScale.value,
                              height: 40 * SettingsSvc.settings.avatarScale.value,
                              decoration: BoxDecoration(
                                  color:
                                      !iOS ? null : context.theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                  border: iOS ? null : Border.all(color: context.theme.colorScheme.primary, width: 3)),
                              child: Icon(
                                Icons.add,
                                color: context.theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            onTap: () async {
                              final method = await showMethodDialog();
                              if (method == null) return;
                              List<ThemeStruct> allThemes =
                                  ThemeStruct.getThemes().where((element) => !element.isPreset).toList();
                              if (allThemes.isEmpty) {
                                return showSnackbar(
                                  "Notice",
                                  "No custom themes found!",
                                );
                              }
                              if (method) {
                                bool errored = false;
                                for (ThemeStruct e in allThemes) {
                                  var response = await HttpSvc.setTheme(e.name.characters.take(50).string, e.toMap());
                                  if (response.statusCode != 200) {
                                    errored = true;
                                  }
                                }
                                if (errored) {
                                  showSnackbar(
                                    "Error",
                                    "Somthing went wrong",
                                  );
                                } else {
                                  showSnackbar(
                                    "Success",
                                    "Themes exported successfully to server",
                                  );
                                }
                              } else {
                                final List<Map<String, dynamic>> themeData = [];
                                for (ThemeStruct e in allThemes) {
                                  themeData.add(e.toMap());
                                }
                                String jsonStr = jsonEncode(themeData);
                                String directoryPath = "/storage/emulated/0/Download/BlueBubbles-theming-";
                                DateTime now = DateTime.now().toLocal();
                                String filePath =
                                    "$directoryPath${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}.json";
                                if (kIsWeb) {
                                  final bytes = utf8.encode(jsonStr);
                                  final content = base64.encode(bytes);
                                  html.AnchorElement(
                                      href: "data:application/octet-stream;charset=utf-16le;base64,$content")
                                    ..setAttribute("download", basename(filePath))
                                    ..click();
                                  return;
                                }
                                if (kIsDesktop) {
                                  String? _filePath = await FilePicker.platform.saveFile(
                                    initialDirectory: (await getDownloadsDirectory())?.path,
                                    dialogTitle: 'Choose a location to save this file',
                                    fileName:
                                        "BlueBubbles-theming-${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}.json",
                                    type: FileType.custom,
                                    allowedExtensions: ["json"],
                                  );
                                  if (_filePath == null) {
                                    return showSnackbar('Failed', 'You didn\'t select a file path!');
                                  }
                                  filePath = _filePath;
                                }
                                File file = File(filePath);
                                await file.create(recursive: true);
                                await file.writeAsString(jsonStr);
                                showSnackbar(
                                  "Success",
                                  "Theming exported successfully to ${kIsDesktop ? filePath : "downloads folder"}",
                                  durationMs: kIsDesktop ? 4000 : 2000,
                                  button: TextButton(
                                    style: TextButton.styleFrom(
                                      backgroundColor: Get.theme.colorScheme.secondary,
                                    ),
                                    onPressed: () {
                                      if (kIsDesktop) {
                                        launchUrl(Uri.file(dirname(filePath)));
                                        return;
                                      }
                                      Share.files([filePath]);
                                    },
                                    child: Text(kIsDesktop ? "OPEN FOLDER" : "SHARE",
                                        style: TextStyle(color: context.theme.colorScheme.onSecondary)),
                                  ),
                                );
                              }
                              setState(() {
                                fetching = true;
                                settings.clear();
                                themes.clear();
                              });
                              getBackups();
                            },
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: ListTile(
                            mouseCursor: SystemMouseCursors.click,
                            title: Text("Restore Local",
                                style: context.theme.textTheme.bodyLarge!
                                    .copyWith(color: context.theme.colorScheme.primary)),
                            leading: Container(
                              width: 40 * SettingsSvc.settings.avatarScale.value,
                              height: 40 * SettingsSvc.settings.avatarScale.value,
                              decoration: BoxDecoration(
                                  color:
                                      !iOS ? null : context.theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  shape: BoxShape.circle,
                                  border: iOS ? null : Border.all(color: context.theme.colorScheme.primary, width: 3)),
                              child: Icon(
                                Icons.upload,
                                color: context.theme.colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            onTap: () async {
                              final res = await FilePicker.platform
                                  .pickFiles(withData: true, type: FileType.custom, allowedExtensions: ["json"]);
                              if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;

                              final confirmed = await BBAlertDialog.confirm(
                                context: context,
                                title: "Restore Backup?",
                                message: "Are you sure you want to restore this backup, overwriting your current theme?",
                                isDestructive: true,
                              );
                              
                              if (confirmed) {
                                try {
                                  String jsonString = const Utf8Decoder().convert(res.files.first.bytes!);
                                  List<dynamic> json = jsonDecode(jsonString);
                                  for (var e in json) {
                                    ThemeStruct object = ThemeStruct.fromMap(e);
                                    if (object.isPreset) continue;
                                    object.id = null;
                                    object.save();
                                  }
                                  showSnackbar("Success", "Theming restored successfully");
                                } catch (e, s) {
                                  Logger.error("Failed to restore theme backup!", error: e, trace: s);
                                  showSnackbar("Error", "Failed to restore theme backup! Error: ${e.toString()}");
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                ]),
              ),
            ]));
  }
}
