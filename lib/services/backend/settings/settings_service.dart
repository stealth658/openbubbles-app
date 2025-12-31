import 'dart:async';
import 'dart:math';

import 'package:bluebubbles/app/layouts/settings/pages/advanced/private_api_panel.dart';
import 'package:bluebubbles/app/layouts/settings/settings_page.dart';
import 'package:bluebubbles/app/wrappers/scrollbar_wrapper.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/settings/shared_preferences_service.dart';
import 'package:bluebubbles/services/backend/interfaces/app_interface.dart';
import 'package:bluebubbles/services/backend/interfaces/server_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:get/get.dart';
import 'package:github/github.dart' hide Source;
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:store_checker/store_checker.dart';
import 'package:tuple/tuple.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:version/version.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
SettingsService get SettingsSvc => GetIt.I<SettingsService>();

class AppUpdateInfo {
  final bool available;
  final Release latestRelease;
  final bool isDesktopRelease;
  final String version;
  final String code;
  final String buildNumber;

  AppUpdateInfo({
    required this.available,
    required this.latestRelease,
    required this.isDesktopRelease,
    required this.version,
    required this.code,
    required this.buildNumber,
  });
}

class ServerUpdateInfo {
  final bool available;
  final String? version;
  final String? releaseDate;
  final String? releaseName;

  ServerUpdateInfo({
    required this.available,
    this.version,
    this.releaseDate,
    this.releaseName,
  });
}

class ServerDetailsInfo {
  final int macOSVersion;
  final int macOSMinorVersion;
  final String serverVersion;
  final int serverVersionCode;

  ServerDetailsInfo({
    required this.macOSVersion,
    required this.macOSMinorVersion,
    required this.serverVersion,
    required this.serverVersionCode,
  });

  Tuple4<int, int, String, int> toTuple() {
    return Tuple4(macOSVersion, macOSMinorVersion, serverVersion, serverVersionCode);
  }
}

class FCMDataInfo {
  final String? projectID;
  final String? storageBucket;
  final String? apiKey;
  final String? firebaseURL;
  final String? clientID;
  final String? applicationID;

  FCMDataInfo({
    this.projectID,
    this.storageBucket,
    this.apiKey,
    this.firebaseURL,
    this.clientID,
    this.applicationID,
  });
}

class SettingsService {
  late Settings settings;
  late FCMData fcmData;
  bool _canAuthenticate = false;
  bool _showingPapiPopup = false;
  Completer<void> initCompleted = Completer<void>();

  bool get canAuthenticate => _canAuthenticate && (Platform.isWindows || (FilesystemSvc.androidInfo?.version.sdkInt ?? 0) > 28);

  Future<void> init({bool headless = false}) async {
    settings = Settings.getSettings();
    if (!headless && !kIsWeb && !kIsDesktop) {
      // Parallelize independent operations
      try {
        await Future.wait([
          LocalAuthentication().isDeviceSupported().then((value) => _canAuthenticate = value),
          settings.getDisplayMode().then((mode) {
            if (mode != DisplayMode.auto) {
              FlutterDisplayMode.setPreferredMode(mode);
            }
          }),
        ]);
      } catch (_) {}
      // system appearance
      if (settings.immersiveMode.value) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.portraitUp,
        if (settings.allowUpsideDownRotation.value) DeviceOrientation.portraitDown,
      ]);
    }
    // launch at startup - defer this so it doesn't block startup
    if (kIsDesktop) {
      Future.microtask(() async {
        if (Platform.isWindows) {
          try {
            _canAuthenticate = await LocalAuthentication().isDeviceSupported();
          } catch (_) {}
        }
        SettingsSvc.settings.launchAtStartup.value =
            await setupLaunchAtStartup(SettingsSvc.settings.launchAtStartup.value, SettingsSvc.settings.launchAtStartupMinimized.value);
      });
    }

    initCompleted.complete();
  }

  /// Returns true if LaunchAtStartup is enabled and false if it is disabled
  Future<bool> setupLaunchAtStartup(bool launchAtStartup, bool minimized) async {
    // Can't use fs here because it hasn't been initialized yet
    if (!isMsix) {
      LaunchAtStartup.setup((await PackageInfo.fromPlatform()).appName, minimized);
      if (launchAtStartup) {
        await LaunchAtStartup.enable();
        return true;
      }
      await LaunchAtStartup.disable();
      return false;
    } else if (launchAtStartup) {
      /// Copied from https://github.com/Merrit/nyrna/pull/172/files
      /// Custom because LaunchAtStartup's implementation doesn't support args yet.
      String script = '''
        \$TargetPath = "shell:AppsFolder\\$windowsAppPackageName"
        \$ShortcutFile = "\$env:USERPROFILE\\Start Menu\\Programs\\Startup\\$appName.lnk"
        \$WScriptShell = New-Object -ComObject WScript.Shell
        \$Shortcut = \$WScriptShell.CreateShortcut(\$ShortcutFile)
        \$Shortcut.TargetPath = \$TargetPath
        \$Shortcut.Arguments = "${minimized ? 'minimized' : ''}"
        \$Shortcut.Save()
        ''';
      await Process.run(
        'powershell',
        ['-Command', script],
      );
    } else {
      const String script = '''
        Remove-Item -Path "\$env:USERPROFILE\\Start Menu\\Programs\\Startup\\$appName.lnk"
      ''';
      await Process.run(
        'powershell',
        ['-Command', script],
      );
    }
    final createdShortcut = File(
      '${Platform.environment['USERPROFILE']}\\Start Menu\\Programs\\Startup\\$appName.lnk',
    );
    if (!createdShortcut.existsSync()) {
      return false;
    }
    return true;
  }

  // this is a separate method because objectbox needs to be initialized
  Future<void> getFcmData() async {
    if (Platform.isAndroid) {
      final fcmInfo = await AppInterface.getFcmData();
      fcmData = FCMData(
        projectID: fcmInfo.projectID,
        storageBucket: fcmInfo.storageBucket,
        apiKey: fcmInfo.apiKey,
        firebaseURL: fcmInfo.firebaseURL,
        clientID: fcmInfo.clientID,
        applicationID: fcmInfo.applicationID,
      );
    } else {
      fcmData = FCMData.getFCM();
    }
  }

  Map<String, dynamic> getFcmDataDict() {
    final data = FCMData.getFCM();
    return {
      'projectID': data.projectID,
      'storageBucket': data.storageBucket,
      'apiKey': data.apiKey,
      'firebaseURL': data.firebaseURL,
      'clientID': data.clientID,
      'applicationID': data.applicationID,
    };
  }

  FCMDataInfo fetchFcmData() {
    final dataDict = getFcmDataDict();
    return FCMDataInfo(
      projectID: dataDict['projectID'] as String?,
      storageBucket: dataDict['storageBucket'] as String?,
      apiKey: dataDict['apiKey'] as String?,
      firebaseURL: dataDict['firebaseURL'] as String?,
      clientID: dataDict['clientID'] as String?,
      applicationID: dataDict['applicationID'] as String?,
    );
  }

  Future<void> updateDisplayMode() async {
    if (!kIsWeb && !kIsDesktop) {
      try {
        final mode = await settings.getDisplayMode();
        FlutterDisplayMode.setPreferredMode(mode);
      } catch (_) {}
    }
  }

  Future<void> saveFCMData(FCMData data) async {
    fcmData = data;
    await fcmData.save(wait: true);
  }

  Future<Map<String, dynamic>> getServerDetailsDict() async {
    final response = await HttpSvc.serverInfo();
    if (response.statusCode == 200) {
      final List<String> toSave = [];
      if (settings.iCloudAccount.isEmpty && response.data['data']['detected_icloud'] is String) {
        settings.iCloudAccount.value = response.data['data']['detected_icloud'];
        toSave.add('iCloudAccount');
      }

      if (response.data['data']['private_api'] is bool) {
        settings.serverPrivateAPI.value = response.data['data']['private_api'];
        toSave.add('serverPrivateAPI');
      }

      final version = int.tryParse(response.data['data']['os_version'].split(".")[0]);
      final minorVersion = int.tryParse(response.data['data']['os_version'].split(".")[1]);
      final serverVersion = response.data['data']['server_version'];
      final code = Version.parse(serverVersion ?? "0.0.0");
      final versionCode = code.major * 100 + code.minor * 21 + code.patch;
      if (version != null) await PrefsSvc.i.setInt("macos-version", version);
      if (minorVersion != null) await PrefsSvc.i.setInt("macos-minor-version", minorVersion);
      if (serverVersion != null) await PrefsSvc.i.setString("server-version", serverVersion);
      await PrefsSvc.i.setInt("server-version-code", versionCode);
      
      if (toSave.isNotEmpty) {
        await settings.saveManyAsync(toSave);
      }

      return {
        'macOSVersion': version ?? 11,
        'macOSMinorVersion': minorVersion ?? 0,
        'serverVersion': serverVersion ?? "0.0.0",
        'serverVersionCode': versionCode,
        'recommendPrivateApi': settings.finishedSetup.value && 
                               settings.reachedConversationList.value && 
                               !settings.enablePrivateAPI.value && 
                               settings.serverPrivateAPI.value == true && 
                               PrefsSvc.i.getBool('private-api-enable-tip') != true,
      };
    }

    return {
      'macOSVersion': 11,
      'macOSMinorVersion': 0,
      'serverVersion': "0.0.0",
      'serverVersionCode': 0,
      'recommendPrivateApi': false,
    };
  }

  Future<ServerDetailsInfo> fetchServerDetails() async {
    final detailsDict = await getServerDetailsDict();
    return ServerDetailsInfo(
      macOSVersion: detailsDict['macOSVersion'] as int,
      macOSMinorVersion: detailsDict['macOSMinorVersion'] as int,
      serverVersion: detailsDict['serverVersion'] as String,
      serverVersionCode: detailsDict['serverVersionCode'] as int,
    );
  }

  Future<Tuple4<int, int, String, int>> getServerDetails({bool refresh = false, String? origin}) async {
    if (refresh) {
      late ServerDetailsInfo detailsInfo;
      if (Platform.isAndroid) {
        detailsInfo = await ServerInterface.getServerDetails();
      } else {
        detailsInfo = await fetchServerDetails();
      }
      
      // Handle PAPI popup (only if not in isolate since it needs UI context)
      if (!Platform.isAndroid) {
        final detailsDict = await getServerDetailsDict();
        if (detailsDict['recommendPrivateApi'] as bool) {
          await _showPapiPopup();
        }
      }

      return detailsInfo.toTuple();
    } else {
      return serverDetailsSync();
    }
  }

  Future<void> _showPapiPopup() async {
    final ScrollController controller = ScrollController();
    if (_showingPapiPopup) Navigator.of(Get.context!).pop();
    _showingPapiPopup = true;
    await showDialog(
      context: Get.context!,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Private API Features"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: min(context.height / 3, Get.context!.height - 300)),
                child: ScrollbarWrapper(
                  controller: controller,
                  showScrollbar: true,
                  child: SingleChildScrollView(
                    controller: controller,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("You've enabled Private API Features on your server!"),
                        const SizedBox(height: 10),
                        const Text("Private API features give you the ability to:"),
                        const Text(" - Send & Receive typing indicators"),
                        const Text(" - Send tapbacks, effects, and mentions"),
                        const Text(" - Send messages with subject lines"),
                        if (isMinBigSurSync) const Text(" - Send replies"),
                        if (isMinVenturaSync) const Text(" - Edit & Unsend messages"),
                        const SizedBox(height: 10),
                        const Text(" - Mark chats read on the Mac server"),
                        if (isMinVenturaSync) const Text(" - Mark chats as unread on the Mac server"),
                        const SizedBox(height: 10),
                        const Text(" - Rename group chats"),
                        const Text(" - Add & remove people from group chats"),
                        if (isMinBigSurSync) const Text(" - Change the group chat photo"),
                        if (isMinBigSurSync) const SizedBox(height: 10),
                        if (isMinMontereySync) const Text(" - View Focus statuses"),
                        if (isMinBigSurSync) const Text(" - Use Find My Friends"),
                        if (isMinBigSurSync) const Text(" - Be notified of incoming FaceTime calls"),
                        if (isMinVenturaSync) const Text(" - Answer FaceTime calls (experimental)"),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: ElevatedButton(
                      onPressed: () async {
                        await PrefsSvc.i.setBool('private-api-enable-tip', true);
                        Navigator.of(context).pop();
                        NavigationSvc.closeSettings(context);
                        NavigationSvc.closeAllConversationView(context);
                        await ChatsSvc.setAllInactive();
                        await Navigator.of(Get.context!).push(
                          ThemeSwitcher.buildPageRoute(
                            builder: (BuildContext context) {
                              return SettingsPage(
                                initialPage: PrivateAPIPanel(
                                  enablePrivateAPIonInit: true,
                                ),
                              );
                            },
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          "Enable Private API Features",
                          textScaler: TextScaler.linear(1.2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: () async {
                        await PrefsSvc.i.setBool('private-api-enable-tip', true);
                        Navigator.of(context).pop();
                      },
                      child: const Text("Don't ask again"),
                    ),
                  )
                ],
              ),
            ],
          ),
        );
      },
    );
    _showingPapiPopup = false;
  }

  Tuple4<int, int, String, int> serverDetailsSync() => Tuple4(
      PrefsSvc.i.getInt("macos-version") ?? 11,
      PrefsSvc.i.getInt("macos-minor-version") ?? 0,
      PrefsSvc.i.getString("server-version") ?? "0.0.0",
      PrefsSvc.i.getInt("server-version-code") ?? 0);

  Future<bool> get isMinSierra async {
    final val = await getServerDetails();
    return val.item1 > 10 || (val.item1 == 10 && val.item2 > 11);
  }

  Future<bool> get isMinBigSur async {
    final val = await getServerDetails();
    return val.item1 >= 11;
  }

  Future<bool> get isMinMonterey async {
    final val = await getServerDetails();
    return val.item1 >= 12;
  }

  Future<bool> get isMinVentura async {
    final val = await getServerDetails();
    return val.item1 >= 13;
  }

  Future<bool> get isMinSonoma async {
    final val = await getServerDetails();
    return val.item1 >= 14;
  }

  Future<bool> get isMinSequioa async {
    final val = await getServerDetails();
    return val.item1 >= 15;
  }

  bool get isMinMontereySync {
    return (PrefsSvc.i.getInt("macos-version") ?? 11) >= 12;
  }

  bool get isMinBigSurSync {
    return (PrefsSvc.i.getInt("macos-version") ?? 11) >= 11;
  }

  bool get isMinVenturaSync {
    return (PrefsSvc.i.getInt("macos-version") ?? 11) >= 13;
  }

  bool get isMinCatalinaSync {
    return (PrefsSvc.i.getInt("macos-minor-version") ?? 11) >= 15 || isMinBigSurSync;
  }

  bool get isMinSonomaSync {
    return (PrefsSvc.i.getInt("macos-version") ?? 11) >= 14;
  }

  bool get isMinSequioaSync {
    return (PrefsSvc.i.getInt("macos-version") ?? 11) >= 15;
  }

  /// Group chats can be created on macOS <= Catalina or
  /// if the Private API is enabled, and the server supports it (v1.8.0).
  Future<bool> canCreateGroupChat() async {
    int serverVersion = (await SettingsSvc.getServerDetails()).item4;
    bool isMin_1_8_0 = serverVersion >= 268; // Server: v1.8.0 (1 * 100 + 8 * 21 + 0)
    bool papiEnabled = settings.enablePrivateAPI.value;
    return (isMin_1_8_0 && papiEnabled) || !isMinBigSurSync;
  }

  /// Group chats can be created on macOS <= Catalina or
  /// if the Private API is enabled, and the server supports it (v1.8.0).
  bool canCreateGroupChatSync() {
    int serverVersion = SettingsSvc.serverDetailsSync().item4;
    bool isMin_1_8_0 = serverVersion >= 268; // Server: v1.8.0 (1 * 100 + 8 * 21 + 0)
    bool papiEnabled = settings.enablePrivateAPI.value;
    return (isMin_1_8_0 && papiEnabled) || !isMinBigSurSync;
  }

  Future<Map<String, dynamic>> getServerUpdateDict() async {
    final response = await HttpSvc.checkUpdate();
    if (response.statusCode == 200) {
      bool available = response.data['data']['available'] ?? false;
      Map<String, dynamic> metadata = response.data['data']['metadata'] ?? {};
      
      return {
        'available': available,
        'metadata': metadata,
      };
    }
    
    return {
      'available': false,
      'metadata': <String, dynamic>{},
    };
  }

  Future<ServerUpdateInfo> checkForServerUpdate() async {
    final updateDict = await getServerUpdateDict();
    final metadata = updateDict['metadata'] as Map<String, dynamic>;
    
    return ServerUpdateInfo(
      available: updateDict['available'] as bool,
      version: metadata['version'] as String?,
      releaseDate: metadata['release_date'] as String?,
      releaseName: metadata['release_name'] as String?,
    );
  }

  Future<void> checkServerUpdate() async {
    late ServerUpdateInfo updateInfo;
    if (Platform.isAndroid) {
      updateInfo = await ServerInterface.checkForServerUpdate();
    } else {
      updateInfo = await checkForServerUpdate();
    }
    
    if (!updateInfo.available || 
        (updateInfo.version != null && PrefsSvc.i.getString("server-update-check") == updateInfo.version)) return;
    
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.properSurface,
        title: Text("Server Update Check", style: context.theme.textTheme.titleLarge),
        content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              height: 15.0,
            ),
            Text(updateInfo.available ? "Updates available:" : "Your server is up-to-date!",
                style: context.theme.textTheme.bodyLarge),
            const SizedBox(
              height: 15.0,
            ),
            if (updateInfo.version != null)
              Text(
                  "Version: ${updateInfo.version ?? "Unknown"}\nRelease Date: ${updateInfo.releaseDate ?? "Unknown"}\nRelease Name: ${updateInfo.releaseName ?? "Unknown"}\n\nWarning: Installing the update will briefly disconnect you.",
                  style: context.theme.textTheme.bodyLarge)
          ],
        ),
        actions: [
          TextButton(
            child: Text("OK",
                style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
            onPressed: () async {
              if (updateInfo.version != null) {
                await PrefsSvc.i.setString("server-update-check", updateInfo.version!);
              }
              Navigator.of(context).pop();
            },
          ),
          TextButton(
            child: Text("Install",
                style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
            onPressed: () async {
              if (updateInfo.version != null) {
                await PrefsSvc.i.setString("server-update-check", updateInfo.version!);
              }
              HttpSvc.installUpdate();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> getAppUpdateDict() async {
    bool available = true;
    if (!kIsDesktop && (kIsWeb || (await StoreChecker.getSource) != Source.IS_INSTALLED_FROM_LOCAL_SOURCE)) {
      available = false;
    }
    if (kIsDesktop) {
      available = false;
    }

    final github = GitHub();
    final stream = github.repositories.listReleases(RepositorySlug('bluebubblesapp', 'bluebubbles-app'));
    final release = await stream.firstWhere(
        (element) => !(element.isDraft ?? false) && !(element.isPrerelease ?? false) && element.tagName != null);
    final version = release.tagName!.split("+").first.replaceAll("v", "");
    final code = release.tagName!.split("+").last.split('-').first;
    final isDesktopRelease = release.tagName!.split('+').last.contains('desktop');
    final buildNumber = FilesystemSvc.packageInfo.buildNumber.lastChars(min(4, FilesystemSvc.packageInfo.buildNumber.length));
    if (int.parse(code) <= int.parse(buildNumber) ||
        PrefsSvc.i.getString("client-update-check") == code ||
        (Platform.isAndroid && isDesktopRelease)) {
      available = false;
    }

    return {
      'available': available,
      'latestRelease': release,
      'isDesktopRelease': isDesktopRelease,
      'parsedVersion': {
        'version': version,
        'code': code,
        'build': buildNumber,
      }
    };
  }

  Future<AppUpdateInfo> checkForUpdate() async {
    final updateDict = await getAppUpdateDict();
    return AppUpdateInfo(
      available: updateDict['available'] as bool,
      latestRelease: updateDict['latestRelease'] as Release,
      isDesktopRelease: updateDict['isDesktopRelease'] as bool,
      version: (updateDict['parsedVersion'] as Map<String, String>)['version']!,
      code: (updateDict['parsedVersion'] as Map<String, String>)['code']!,
      buildNumber: (updateDict['parsedVersion'] as Map<String, String>)['build']!,
    );
  }

  Future<void> checkClientUpdate() async {
    late AppUpdateInfo updateInfo;
    if (Platform.isAndroid) {
      updateInfo = await AppInterface.checkForUpdate();
    } else {
      updateInfo = await checkForUpdate();
    }
    if (!updateInfo.available) return;
    
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        backgroundColor: context.theme.colorScheme.properSurface,
        title: Text("App Update Check", style: context.theme.textTheme.titleLarge),
        content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              height: 15.0,
            ),
            Text("Updates available:", style: context.theme.textTheme.bodyLarge),
            const SizedBox(
              height: 15.0,
            ),
            Text("Version: ${updateInfo.version}\nRelease Date: ${buildDate(updateInfo.latestRelease.createdAt)}\nRelease Name: ${updateInfo.latestRelease.name}",
                style: context.theme.textTheme.bodyLarge)
          ],
        ),
        actions: [
          if (updateInfo.latestRelease.htmlUrl != null)
            TextButton(
              child: Text("Download",
                  style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
              onPressed: () async {
                await launchUrl(Uri.parse(updateInfo.latestRelease.htmlUrl!), mode: LaunchMode.externalApplication);
              },
            ),
          TextButton(
            child: Text("OK",
                style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
            onPressed: () async {
              await PrefsSvc.i.setString("client-update-check", updateInfo.code);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
