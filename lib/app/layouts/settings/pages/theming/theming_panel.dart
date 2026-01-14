import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/components/settings/settings.dart';
import 'package:bluebubbles/app/components/settings/bb_settings_subtitle.dart';
import 'package:bluebubbles/core/utils/window_effects_utils.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/avatar/custom_avatar_color_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/avatar/custom_avatar_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/layouts/settings/pages/theming/advanced/advanced_theming_panel.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:get/get.dart' hide Response;
import 'package:idb_shim/idb.dart';
import 'package:universal_io/io.dart';

class ThemingPanelController extends StatefulController {
  final RxList<DisplayMode> modes = <DisplayMode>[].obs;
  final RxList<int> refreshRates = <int>[].obs;
  final RxInt currentMode = 0.obs;

  @override
  void onReady() async {
    super.onReady();
    if (!kIsWeb && !kIsDesktop) {
      updateObx(() async {
        modes.value = await FlutterDisplayMode.supported;
        refreshRates.value = modes.map((e) => e.refreshRate.round()).toSet().toList();
        currentMode.value = (await SettingsSvc.settings.getDisplayMode()).refreshRate.round();
      });
    }
  }
}

class ThemingPanel extends CustomStateful<ThemingPanelController> {
  ThemingPanel({super.key}) : super(parentController: Get.put(ThemingPanelController()));

  @override
  State<StatefulWidget> createState() => _ThemingPanelState();
}

class _ThemingPanelState extends CustomState<ThemingPanel, void, ThemingPanelController> {
  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SettingsScaffold(
        title: "Theming & Styles",
        initialHeader: "Appearance",
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        tileColor: tileColor,
        headerColor: headerColor,
        bodySlivers: [
          SliverList(
            delegate: SliverChildListDelegate(
              <Widget>[
                BBSettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    BBSettingsDropdown<AdaptiveThemeMode>(
                      value: AdaptiveTheme.of(context).mode,
                      onChanged: (val) {
                        if (val == null) return;
                        AdaptiveTheme.of(context).setThemeMode(val);
                        setState(() {});
                        EventDispatcherSvc.emit('theme-update', null);
                      },
                      options: AdaptiveThemeMode.values,
                      textProcessing: (val) => val.toString().split(".").last,
                      title: "App Theme",
                    ),
                    if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    if (!kIsWeb)
                      BBSettingsTile(
                        title: "Advanced Theming",
                        subtitle:
                            "Customize app colors and font sizes with custom themes\n${ThemeStruct.getLightTheme().name}   |   ${ThemeStruct.getDarkTheme().name}",
                        trailing: const NextButton(),
                        onTap: () async {
                          Navigator.of(context).push(
                            CupertinoPageRoute(
                              builder: (context) => const AdvancedThemingPanel(),
                            ),
                          );
                        },
                      ),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    Container(
                      padding: const EdgeInsets.only(left: 15, top: 10),
                      child: Text("Avatar Scale Factor", style: context.theme.textTheme.bodyLarge),
                    ),
                    Obx(() => SettingsSlider(
                        startingVal: SettingsSvc.settings.avatarScale.value.toDouble(),
                        update: (double val) {
                          SettingsSvc.settings.avatarScale.value = val;
                        },
                        onChangeEnd: (double val) async {
                          await SettingsSvc.settings.saveOneAsync('avatarScale');
                        },
                        formatValue: ((double val) => val.toPrecision(2).toString()),
                        backgroundColor: tileColor,
                        min: 0.8,
                        max: 1.2,
                        divisions: 4)),
                  ],
                ),
                BBSettingsHeader(
                    text: "Skin${kIsDesktop ? "" : " and Layout"}"),
                BBSettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    Obx(() => BBSettingsDropdown<Skins>(
                          value: SettingsSvc.settings.skin.value,
                          onChanged: (val) async {
                            if (val == null) return;
                            await ChatsSvc.setAllInactive();
                            SettingsSvc.settings.skin.value = val;
                            await SettingsSvc.settings.saveOneAsync('skin');
                            setState(() {});
                            EventDispatcherSvc.emit('theme-update', null);
                          },
                          options: Skins.values,
                          textProcessing: (val) => val.name,
                          capitalize: false,
                          title: "App Skin",
                        )),
                    if (!kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    if (!kIsDesktop)
                      Obx(() => BBSettingsSwitch(
                            onChanged: (bool val) async {
                              SettingsSvc.settings.tabletMode.value = val;
                              await SettingsSvc.settings.saveOneAsync('tabletMode');
                              // update the conversation view UI
                              EventDispatcherSvc.emit('split-refresh', null);
                            },
                            value: SettingsSvc.settings.tabletMode.value,
                            title: "Tablet Mode",
                            subtitle: "Enables tablet mode (split view) depending on screen width",
                            isThreeLine: true,
                          )),
                    if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    if (!kIsWeb && !kIsDesktop)
                      Obx(() => BBSettingsSwitch(
                            onChanged: (bool val) async {
                              SettingsSvc.settings.immersiveMode.value = val;
                              await SettingsSvc.settings.saveOneAsync('immersiveMode');
                              if (val) {
                                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                              } else {
                                SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
                                    overlays: [SystemUiOverlay.bottom, SystemUiOverlay.top]);
                              }
                              EventDispatcherSvc.emit('theme-update', null);
                            },
                            value: SettingsSvc.settings.immersiveMode.value,
                            title: "Immersive Mode",
                            subtitle:
                                "Makes the bottom navigation bar transparent. This option is best used with gesture navigation.",
                            isThreeLine: true,
                          )),
                    if (!kIsWeb && !kIsDesktop)
                      const BBSettingsSubtitle(
                        text:
                            "Note: This option may cause slight choppiness in some animations due to an Android limitation.",
                      ),
                  ],
                ),
                if (kIsDesktop && Platform.isWindows)
                  const BBSettingsHeader(
                    text: "Window Effect",
                  ),
                if (kIsDesktop && Platform.isWindows)
                  BBSettingsSection(backgroundColor: tileColor, children: [
                    Obx(
                      () => BBSettingsDropdown<WindowEffect>(
                        value: SettingsSvc.settings.windowEffect.value,
                        options: WindowEffects.effects,
                        textProcessing: (WindowEffect effect) => effect.toString().substring("WindowEffect.".length),
                        onChanged: (WindowEffect? effect) async {
                          bool defaultOpacityLight = SettingsSvc.settings.windowEffectCustomOpacityLight.value ==
                              WindowEffects.defaultOpacity(dark: false);
                          bool defaultOpacityDark = SettingsSvc.settings.windowEffectCustomOpacityDark.value ==
                              WindowEffects.defaultOpacity(dark: true);
                          effect ??= WindowEffect.disabled;
                          SettingsSvc.settings.windowEffect.value = effect;
                          if (defaultOpacityLight) {
                            SettingsSvc.settings.windowEffectCustomOpacityLight.value =
                                WindowEffects.defaultOpacity(dark: false);
                          }
                          if (defaultOpacityDark) {
                            SettingsSvc.settings.windowEffectCustomOpacityDark.value =
                                WindowEffects.defaultOpacity(dark: true);
                          }
                          await PrefsSvc.i.setString('window-effect', effect.toString());
                          await WindowEffects.setEffect(color: context.theme.colorScheme.background);
                          await SettingsSvc.settings.saveManyAsync(
                              ['windowEffect', 'windowEffectCustomOpacityLight', 'windowEffectCustomOpacityDark']);
                        },
                        title: "Window Effect",
                        subtitle:
                            "${WindowEffects.descriptions[SettingsSvc.settings.windowEffect.value]}\n\nOperating System Version: ${Platform.operatingSystemVersion}\nBuild number: ${parsedWindowsVersion()}${parsedWindowsVersion() < 22000 && SettingsSvc.settings.windowEffect.value == WindowEffect.acrylic ? "\n\n⚠️ This effect causes window movement lag on Windows 10" : ""}",

                        capitalize: true,
                      ),
                    ),
                    if (SettingsSvc.settings.skin.value == Skins.iOS)
                      Obx(() => BBSettingsSubtitle(
                            unlimitedSpace: true,
                            text:
                                "${WindowEffects.descriptions[SettingsSvc.settings.windowEffect.value]}\n\nOperating System Version: ${Platform.operatingSystemVersion}\nBuild number: ${parsedWindowsVersion()}${parsedWindowsVersion() < 22000 && SettingsSvc.settings.windowEffect.value == WindowEffect.acrylic ? "\n\n⚠️ This effect causes window movement lag on Windows 10" : ""}",
                          )),
                    Obx(() {
                      if (WindowEffects.dependsOnColor() &&
                          !WindowEffects.isDark(color: context.theme.colorScheme.background)) {
                        return BBSettingsTile(
                          title: "Background Opacity (Light)",
                          trailing: SettingsSvc.settings.windowEffectCustomOpacityLight.value !=
                                  WindowEffects.defaultOpacity(dark: false)
                              ? ElevatedButton(
                                  onPressed: () async {
                                    SettingsSvc.settings.windowEffectCustomOpacityLight.value =
                                        WindowEffects.defaultOpacity(dark: false);
                                    await SettingsSvc.settings.saveOneAsync('windowEffectCustomOpacityLight');
                                  },
                                  child: const Text("Reset to Default"),
                                )
                              : null,
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    Obx(() {
                      if (WindowEffects.dependsOnColor() &&
                          !WindowEffects.isDark(color: context.theme.colorScheme.background)) {
                        return SettingsSlider(
                          startingVal: SettingsSvc.settings.windowEffectCustomOpacityLight.value,
                          max: 1,
                          min: 0,
                          divisions: 100,
                          formatValue: (value) => value.toStringAsFixed(2),
                          update: (value) => SettingsSvc.settings.windowEffectCustomOpacityLight.value = value,
                          onChangeEnd: (value) async {
                            await SettingsSvc.settings.saveOneAsync('windowEffectCustomOpacityLight');
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    Obx(() {
                      if (WindowEffects.dependsOnColor() &&
                          WindowEffects.isDark(color: context.theme.colorScheme.background)) {
                        return BBSettingsTile(
                          title: "Background Opacity (Dark)",
                          trailing: SettingsSvc.settings.windowEffectCustomOpacityDark.value !=
                                  WindowEffects.defaultOpacity(dark: true)
                              ? ElevatedButton(
                                  onPressed: () async {
                                    SettingsSvc.settings.windowEffectCustomOpacityDark.value =
                                        WindowEffects.defaultOpacity(dark: true);
                                    await SettingsSvc.settings.saveOneAsync('windowEffectCustomOpacityDark');
                                  },
                                  child: const Text("Reset to Default"),
                                )
                              : null,
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                    Obx(() {
                      if (WindowEffects.dependsOnColor() &&
                          WindowEffects.isDark(color: context.theme.colorScheme.background)) {
                        return SettingsSlider(
                          startingVal: SettingsSvc.settings.windowEffectCustomOpacityDark.value,
                          max: 1,
                          min: 0,
                          divisions: 100,
                          formatValue: (value) => value.toStringAsFixed(2),
                          update: (value) => SettingsSvc.settings.windowEffectCustomOpacityDark.value = value,
                          onChangeEnd: (value) async {
                            await SettingsSvc.settings.saveOneAsync('windowEffectCustomOpacityDark');
                          },
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  ]),
                const BBSettingsHeader(text: "Colors"),
                BBSettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    if (kIsDesktop)
                      Obx(() => BBSettingsSwitch(
                            value: SettingsSvc.settings.useDesktopAccent.value,
                            title:
                                "Use ${Platform.isWindows ? "Windows" : Platform.isLinux ? "Linux" : "MacOS"} Accent Color",
                            subtitle:
                                "Apply the ${Platform.isWindows ? "Windows" : Platform.isLinux ? "Linux" : "MacOS"} accent color to your theme",
                            onChanged: (value) async {
                              SettingsSvc.settings.useDesktopAccent.value = value;
                              await SettingsSvc.settings.saveOneAsync('useDesktopAccent');
                              await ThemeSvc.refreshDesktopAccent(context);
                            },
                          )),
                    if (kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    if (!kIsWeb && !kIsDesktop && ThemeSvc.monetPalette != null)
                      Obx(() {
                        if (iOS) {
                          return BBSettingsTile(
                            title: "Material You",
                            subtitle:
                                "Use Android 12's Monet engine to provide wallpaper-based coloring to your theme. Tap for more info.",
                            onTap: () {
                              showMonetDialog(context);
                            },
                          );
                        } else {
                          return const SizedBox.shrink();
                        }
                      }),
                    if (!kIsWeb && !kIsDesktop && ThemeSvc.monetPalette != null)
                      GestureDetector(
                        onTap: () {
                          showMonetDialog(context);
                        },
                        child: BBSettingsDropdown<Monet>(
                          value: SettingsSvc.settings.monetTheming.value,
                          onChanged: (val) async {
                            // disable colors from music
                            final currentTheme = ThemeStruct.getLightTheme();
                            if (currentTheme.name == "Music Theme ☀" || currentTheme.name == "Music Theme 🌙") {
                              SettingsSvc.settings.colorsFromMedia.value = false;
                              await SettingsSvc.settings.saveOneAsync('colorsFromMedia');
                              ThemeStruct previousDark = await ThemeSvc.revertToPreviousDarkTheme();
                              ThemeStruct previousLight = await ThemeSvc.revertToPreviousLightTheme();
                              await ThemeSvc.changeTheme(context, light: previousLight, dark: previousDark);
                            }
                            SettingsSvc.settings.monetTheming.value = val ?? Monet.none;
                            await SettingsSvc.settings.saveOneAsync('monetTheming');
                            await ThemeSvc.refreshMonet(context);
                          },
                          options: Monet.values,
                          textProcessing: (val) => val.toString().split(".").last,
                          title: "Material You",
                          subtitle:
                              "Use Android 12's Monet engine to provide wallpaper-based coloring to your theme. Tap for more info.",
                        ),
                      ),
                    if (!kIsWeb && !kIsDesktop && ThemeSvc.monetPalette != null)
                      const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    if (!kIsWeb && !kIsDesktop)
                      Obx(
                        () => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            if (val) {
                              await MethodChannelSvc.invokeMethod("request-notification-listener-permission");
                              try {
                                await MethodChannelSvc.invokeMethod("start-notification-listener");
                                // disable monet theming if music theme enabled
                                SettingsSvc.settings.monetTheming.value = Monet.none;
                                await SettingsSvc.settings.saveOneAsync('monetTheming');
                                var allThemes = ThemeStruct.getThemes();
                                var currentLight = ThemeStruct.getLightTheme();
                                var currentDark = ThemeStruct.getDarkTheme();
                                await PrefsSvc.i.setString("previous-light", currentLight.name);
                                await PrefsSvc.i.setString("previous-dark", currentDark.name);
                                await ThemeSvc.changeTheme(context,
                                    light: allThemes.firstWhere((element) => element.name == "Music Theme ☀"),
                                    dark: allThemes.firstWhere((element) => element.name == "Music Theme 🌙"));
                                SettingsSvc.settings.colorsFromMedia.value = val;
                                await SettingsSvc.settings.saveOneAsync('colorsFromMedia');
                              } catch (e) {
                                showSnackbar("Error",
                                    "Something went wrong, please ensure you granted the permission correctly!");
                              }
                            } else {
                              var allThemes = ThemeStruct.getThemes();
                              final lightName = PrefsSvc.i.getString("previous-light");
                              final darkName = PrefsSvc.i.getString("previous-dark");
                              var previousLight = allThemes.firstWhere((e) => e.name == lightName);
                              var previousDark = allThemes.firstWhere((e) => e.name == darkName);
                              await PrefsSvc.i.remove("previous-light");
                              await PrefsSvc.i.remove("previous-dark");
                              await ThemeSvc.changeTheme(context, light: previousLight, dark: previousDark);
                              SettingsSvc.settings.colorsFromMedia.value = val;
                              await SettingsSvc.settings.saveOneAsync('colorsFromMedia');
                            }
                          },
                          value: SettingsSvc.settings.colorsFromMedia.value,
                          title: "Colors from Media",
                          subtitle: "Pull app colors from currently playing media",
                        ),
                      ),
                    if (!kIsWeb && !kIsDesktop)
                      const BBSettingsSubtitle(
                        unlimitedSpace: true,
                        text:
                            "Note: Requires full notification access. Enabling this option will set a custom Music Theme as the selected theme. Media art with mostly blacks or whites may not produce any change in theming.",
                      ),
                    if (!kIsWeb && !kIsDesktop) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.colorfulAvatars.value = val;
                            await SettingsSvc.settings.saveOneAsync('colorfulAvatars');
                          },
                          value: SettingsSvc.settings.colorfulAvatars.value,
                          title: "Colorful Avatars",
                          subtitle: "Gives letter avatars a splash of color",
                        )),
                    const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    Obx(() => BBSettingsSwitch(
                          onChanged: (bool val) async {
                            SettingsSvc.settings.colorfulBubbles.value = val;
                            await SettingsSvc.settings.saveOneAsync('colorfulBubbles');
                          },
                          value: SettingsSvc.settings.colorfulBubbles.value,
                          title: "Colorful Bubbles",
                          subtitle: "Gives received message bubbles a splash of color",
                        )),
                    if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    if (!kIsWeb)
                      BBSettingsTile(
                        title: "Custom Avatar Colors",
                        trailing: const NextButton(),
                        onTap: () async {
                          NavigationSvc.pushSettings(
                            context,
                            CustomAvatarColorPanel(),
                          );
                        },
                        subtitle: "Customize the color for different avatars",
                      ),
                    if (!kIsWeb) const SettingsDivider(padding: EdgeInsets.only(left: 16.0)),
                    if (!kIsWeb)
                      BBSettingsTile(
                        title: "Custom Avatars",
                        trailing: const NextButton(),
                        onTap: () async {
                          NavigationSvc.pushSettings(
                            context,
                            const CustomAvatarPanel(),
                          );
                        },
                        subtitle: "Customize the avatar for different chats",
                      ),
                  ],
                ),
                if (!kIsWeb && !kIsDesktop)
                  Obx(() {
                    if (controller.refreshRates.length > 2) {
                      return const BBSettingsHeader(
                          text: "Refresh Rate");
                    } else {
                      return const SizedBox.shrink();
                    }
                  }),
                if (!kIsWeb && !kIsDesktop)
                  Obx(() {
                    if (controller.refreshRates.length > 2) {
                      return BBSettingsSection(
                        backgroundColor: tileColor,
                        children: [
                          Obx(() => BBSettingsDropdown<int>(
                                value: controller.currentMode.value,
                                onChanged: (val) async {
                                  if (val == null) return;
                                  controller.currentMode.value = val;
                                  SettingsSvc.settings.refreshRate.value = controller.currentMode.value;
                                  await SettingsSvc.settings.saveOneAsync('refreshRate');
                                  await SettingsSvc.updateDisplayMode();
                                },
                                options: controller.refreshRates,
                                textProcessing: (val) => val == 0 ? "Auto" : "$val Hz",
                                title: "Display",
                              )),
                        ],
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  }),
                const BBSettingsHeader(text: "Text and Font"),
                BBSettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    Obx(() {
                      if (!FilesystemSvc.fontExistsOnDisk.value) {
                        return BBSettingsTile(
                          onTap: () async {
                            if (kIsWeb) {
                              try {
                                final res = await FilePicker.platform
                                    .pickFiles(withData: true, type: FileType.custom, allowedExtensions: ["ttf"]);
                                if (res == null || res.files.isEmpty || res.files.first.bytes == null) return;

                                final txn = FilesystemSvc.webDb.transaction("BBStore", idbModeReadWrite);
                                final store = txn.objectStore("BBStore");
                                await store.put(res.files.first.bytes!, "iosFont");
                                await txn.completed;

                                final fontLoader = FontLoader("Apple Color Emoji");
                                final cachedFontBytes = ByteData.view(res.files.first.bytes!.buffer);
                                fontLoader.addFont(
                                  Future<ByteData>.value(cachedFontBytes),
                                );
                                await fontLoader.load();
                                FilesystemSvc.fontExistsOnDisk.value = true;
                                return showSnackbar("Notice", "Font loaded");
                              } catch (_) {
                                return showSnackbar("Error",
                                    "Failed to load font file. Please make sure it is a valid ttf and under 50mb.");
                              }
                            }

                            BBCustomDialog.show(
                              context: context,
                              title: "Downloading font file...",
                              content: Obx(() => Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Text(
                                          '${HttpSvc.fontDownloadProgress.value != null && HttpSvc.fontDownloadTotalSize.value != null ? (HttpSvc.fontDownloadProgress.value! * HttpSvc.fontDownloadTotalSize.value! / 1000).getFriendlySize(withSuffix: false) : ""} / ${((HttpSvc.fontDownloadTotalSize.value ?? 0).toDouble() / 1000).getFriendlySize()} (${((HttpSvc.fontDownloadProgress.value ?? 0) * 100).floor()}%)',
                                          style: Theme.of(context).textTheme.bodyLarge),
                                      const SizedBox(height: 10.0),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(20),
                                        child: LinearProgressIndicator(
                                          backgroundColor: Theme.of(context).colorScheme.outline,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                                          value: HttpSvc.fontDownloadProgress.value,
                                          minHeight: 5,
                                        ),
                                      ),
                                      const SizedBox(
                                        height: 15.0,
                                      ),
                                      Text(
                                        HttpSvc.fontDownloadProgress.value == 1
                                            ? "Download Complete!"
                                            : "You can close this dialog. The font will continue to download in the background.",
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context).textTheme.bodyLarge,
                                      ),
                                      if (!HttpSvc.downloadingFont.value) ...[
                                        const SizedBox(height: 20),
                                        ElevatedButton(
                                          onPressed: () async {
                                            Get.closeAllSnackbars();
                                            Navigator.of(context, rootNavigator: true).pop();
                                            Future.delayed(const Duration(milliseconds: 400), () {
                                              HttpSvc.fontDownloadProgress.value = null;
                                              HttpSvc.fontDownloadTotalSize.value = null;
                                            });
                                          },
                                          child: const Text("Close"),
                                        ),
                                      ],
                                    ],
                                  )),
                              actions: const [],
                            );

                            HttpSvc.downloadAppleEmojiFont();
                          },
                          title: kIsWeb
                              ? "Upload Font File"
                              : "Download${HttpSvc.downloadingFont.value ? "ing" : ""} iOS Emoji Font${HttpSvc.downloadingFont.value ? " (${HttpSvc.fontDownloadProgress.value != null && HttpSvc.fontDownloadTotalSize.value != null ? (HttpSvc.fontDownloadProgress.value! * HttpSvc.fontDownloadTotalSize.value! / 1000).getFriendlySize(withSuffix: false) : ""} / ${((HttpSvc.fontDownloadTotalSize.value ?? 0).toDouble() / 1000).getFriendlySize()}) (${((HttpSvc.fontDownloadProgress.value ?? 0) * 100).floor()}%)" : ""}",
                          subtitle: kIsWeb ? "Upload your ttf emoji file into BlueBubbles" : null,
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
                    }),
                    Obx(() {
                      if (FilesystemSvc.fontExistsOnDisk.value) {
                        return BBSettingsTile(
                          onTap: () async {
                            if (kIsWeb) {
                              final txn = FilesystemSvc.webDb.transaction("BBStore", idbModeReadWrite);
                              final store = txn.objectStore("BBStore");
                              await store.delete("iosFont");
                              await txn.completed;
                            } else {
                              final file = File("${FilesystemSvc.appDocDir.path}/font/apple.ttf");
                              await file.delete();
                            }
                            FilesystemSvc.fontExistsOnDisk.value = false;
                            showSnackbar("Notice", "Font removed, restart the app for changes to take effect");
                          },
                          title: "Delete ${kIsWeb ? "" : "iOS "}Emoji Font",
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showMonetDialog(BuildContext context) {
    BBAlertDialog.alert(
        context: context,
        title: "Monet Theming Info",
        message: "Harmonize - Overwrites primary color and blends remainder of colors with the current theme colors\r\n"
            "Full - Overwrites primary, background, and accent colors, along with other minor colors.\r\n");
  }
}
