import 'dart:io';
import 'dart:math';

import 'package:bluebubbles/app/app.dart' hide BBDialogAction;
import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/next_button.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutPanel extends StatefulWidget {
  const AboutPanel({super.key});

  @override
  State<StatefulWidget> createState() => _AboutPanelState();
}

class _AboutPanelState extends OptimizedState<AboutPanel> {
  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
        title: "About & Links",
        initialHeader: "Links",
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
                    BBSettingsTile(
                        title: "BlueBubbles Website",
                        subtitle: "Visit the BlueBubbles Homepage",
                        onTap: () async {
                          await launchUrl(Uri(scheme: "https", host: "bluebubbles.app"),
                              mode: LaunchMode.externalApplication);
                        },
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.globe,
                          materialIcon: Icons.language,
                          color: Colors.green,
                        ),
                        trailing: const NextButton()),
                    const SettingsDivider(),
                    BBSettingsTile(
                        title: "Documentation",
                        subtitle: "RTFM: Read the [Fine] Manual and learn how to use BlueBubbles or fix common issues",
                        onTap: () async {
                          await launchUrl(Uri(scheme: "https", host: "docs.bluebubbles.app"),
                              mode: LaunchMode.externalApplication);
                        },
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.doc_append,
                          materialIcon: Icons.document_scanner,
                          color: Colors.blueAccent,
                        ),
                        trailing: const NextButton()),
                    const SettingsDivider(),
                    BBSettingsTile(
                        title: "Source Code",
                        subtitle: "View the source code for BlueBubbles, and contribute!",
                        onTap: () async {
                          await launchUrl(Uri(scheme: "https", host: "github.com", path: "BlueBubblesApp"),
                              mode: LaunchMode.externalApplication);
                        },
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.chevron_left_slash_chevron_right,
                          materialIcon: Icons.code,
                          color: Colors.orange,
                        ),
                        trailing: const NextButton()),
                    const SettingsDivider(),
                    BBSettingsTile(
                        title: "Report a Bug",
                        subtitle: "Found a bug? Report it here!",
                        onTap: () async {
                          await launchUrl(
                              Uri(scheme: "https", host: "github.com", path: "BlueBubblesApp/bluebubbles-app/issues"),
                              mode: LaunchMode.externalApplication);
                        },
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.triangle_righthalf_fill,
                          materialIcon: Icons.bug_report,
                          color: Colors.redAccent,
                        ),
                        trailing: const NextButton()),
                  ],
                ),
                const BBSettingsHeader(text: "Info"),
                BBSettingsSection(
                  backgroundColor: tileColor,
                  children: [
                    BBSettingsTile(
                      title: "Changelog",
                      onTap: () async {
                        String changelog =
                            await DefaultAssetBundle.of(context).loadString('assets/changelog/changelog.md');
                        Navigator.of(context).push(
                          ThemeSwitcher.buildPageRoute(
                            builder: (context) => Scaffold(
                              body: Markdown(
                                data: changelog,
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                styleSheet: MarkdownStyleSheet.fromTheme(
                                  context.theme
                                    ..textTheme.copyWith(
                                      headlineMedium: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                ).copyWith(
                                  h1: context.theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold),
                                  h2: context.theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
                                  h3: context.theme.textTheme.titleSmall!.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              backgroundColor: context.theme.colorScheme.background,
                              appBar: AppBar(
                                toolbarHeight: 50,
                                elevation: 0,
                                scrolledUnderElevation: 3,
                                surfaceTintColor: context.theme.colorScheme.primary,
                                leading: buildBackButton(context),
                                backgroundColor: headerColor,
                                iconTheme: IconThemeData(color: context.theme.colorScheme.primary),
                                centerTitle: iOS,
                                title: Padding(
                                  padding: EdgeInsets.only(top: kIsDesktop ? 20 : 0),
                                  child: Text(
                                    "Changelog",
                                    style: context.theme.textTheme.titleLarge,
                                  ),
                                ),
                                systemOverlayStyle: context.theme.colorScheme.brightness == Brightness.dark
                                    ? SystemUiOverlayStyle.light
                                    : SystemUiOverlayStyle.dark,
                              ),
                            ),
                          ),
                        );
                      },
                      subtitle: "See what's new in the latest version",
                      leading: const BBSettingsIcon(
                        iosIcon: CupertinoIcons.doc_plaintext,
                        materialIcon: Icons.article,
                        color: Colors.blueAccent,
                      ),
                    ),
                    const SettingsDivider(),
                    BBSettingsTile(
                      title: "Developers",
                      onTap: () {
                        final devs = {
                          "Zach": "zlshames",
                          "Tanay": "tneotia",
                          "Joel": "jjoelj",
                        };
                        BBCustomDialog.show(
                          context: context,
                          title: "GitHub Profiles",
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: devs.entries
                                .map((e) => Container(
                                      alignment: Alignment.center,
                                      padding: const EdgeInsets.all(8),
                                      child: RichText(
                                        text: TextSpan(
                                            text: e.key,
                                            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                                                decoration: TextDecoration.underline,
                                                color: Theme.of(context).colorScheme.primary),
                                            recognizer: TapGestureRecognizer()
                                              ..onTap = () async {
                                                await launchUrl(
                                                    Uri(scheme: "https", host: "github.com", path: e.value),
                                                    mode: LaunchMode.externalApplication);
                                              }),
                                      ),
                                    ))
                                .toList(),
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
                      subtitle: "Meet the developers behind BlueBubbles",
                      leading: const BBSettingsIcon(
                        iosIcon: CupertinoIcons.person_alt,
                        materialIcon: Icons.person,
                        color: Colors.green,
                      ),
                    ),
                    if (kIsWeb || kIsDesktop) const SettingsDivider(),
                    if (kIsWeb || kIsDesktop)
                      BBSettingsTile(
                        title: "Keyboard Shortcuts",
                        onTap: () {
                          BBCustomDialog.show(
                              context: context,
                              title: 'Keyboard Shortcuts',
                              config: const BBCustomDialogConfig(
                                scrollable: true,
                              ),
                              content: SizedBox(
                                height: MediaQuery.of(context).size.height / 2,
                                child: SingleChildScrollView(
                                  child: DataTable(
                                    columnSpacing: 5,
                                    dataRowMinHeight: 75,
                                    dataRowMaxHeight: 75,
                                    dataTextStyle: Theme.of(context).textTheme.bodyLarge,
                                    headingTextStyle:
                                        Theme.of(context).textTheme.bodyLarge!.copyWith(fontStyle: FontStyle.italic),
                                    columns: const <DataColumn>[
                                      DataColumn(
                                        label: Text(
                                          'Key Combination',
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          'Action',
                                        ),
                                      ),
                                    ],
                                    rows: const <DataRow>[
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + COMMA')),
                                          DataCell(Text('Open settings')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + N')),
                                          DataCell(Text('Start new chat (Desktop only)')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('ALT + N')),
                                          DataCell(Text('Start new chat')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + F')),
                                          DataCell(Text('Open search page')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('ALT + R')),
                                          DataCell(
                                              Text('Reply to most recent message in the currently selected chat')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + R')),
                                          DataCell(Text(
                                              'Reply to most recent message in the currently selected chat (Desktop only)')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('ALT + G')),
                                          DataCell(Text('Sync from server')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + SHIFT + R')),
                                          DataCell(Text('Sync from server (Desktop only)')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + G')),
                                          DataCell(Text('Sync from server (Desktop only)')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + SHIFT + 1-6')),
                                          DataCell(Text(
                                              'Apply reaction to most recent message in the currently selected chat')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + ARROW DOWN')),
                                          DataCell(Text('Switch to the chat below the currently selected one')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + TAB')),
                                          DataCell(Text(
                                              'Switch to the chat below the currently selected one (Desktop only)')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + ARROW UP')),
                                          DataCell(Text('Switch to the chat above the currently selected one')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + SHIFT + TAB')),
                                          DataCell(Text(
                                              'Switch to the chat above the currently selected one (Desktop only)')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('CTRL + I')),
                                          DataCell(Text('Open chat details page')),
                                        ],
                                      ),
                                      DataRow(
                                        cells: <DataCell>[
                                          DataCell(Text('ESC')),
                                          DataCell(Text('Close pages')),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              actions: [
                                BBDialogAction(
                                  label: 'Close',
                                  type: BBDialogButtonType.cancel,
                                  onPressed: () => Navigator.of(context).pop(),
                                )
                              ]);
                        },
                        leading: const BBSettingsIcon(
                          iosIcon: CupertinoIcons.keyboard,
                          materialIcon: Icons.keyboard,
                        ),
                      ),
                    const SettingsDivider(),
                    BBSettingsTile(
                      title: "About",
                      subtitle: "Version and other information",
                      onTap: () {
                        BBCustomDialog.show<void>(
                          context: context,
                          title: "",
                          config: const BBCustomDialogConfig(
                            scrollable: true,
                          ),
                          content: FutureBuilder<PackageInfo>(
                              future: PackageInfo.fromPlatform(),
                              builder: (BuildContext context, AsyncSnapshot<PackageInfo> snapshot) {
                                return ListBody(
                                  children: <Widget>[
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        IconTheme(
                                          data: Theme.of(context).iconTheme,
                                          child: Image.asset(
                                            "assets/icon/icon.png",
                                            width: 30,
                                            height: 30,
                                          ),
                                        ),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                                            child: ListBody(
                                              children: <Widget>[
                                                Text(
                                                  "BlueBubbles",
                                                  style: Theme.of(context).textTheme.titleLarge,
                                                ),
                                                if (!kIsDesktop)
                                                  Text(
                                                      "Version Number: ${snapshot.hasData ? snapshot.data!.version : "N/A"}",
                                                      style: Theme.of(context).textTheme.bodyLarge),
                                                if (!kIsDesktop)
                                                  Text(
                                                      "Version Code: ${snapshot.hasData ? snapshot.data!.buildNumber.toString().lastChars(min(4, snapshot.data!.buildNumber.length)) : "N/A"}",
                                                      style: Theme.of(context).textTheme.bodyLarge),
                                                if (kIsDesktop)
                                                  Text(
                                                    "${FilesystemSvc.packageInfo.version}_${Platform.operatingSystem.capitalizeFirst!}${isSnap ? "_Snap" : isFlatpak ? "_Flatpak" : isMsix ? "_Msix" : ""}",
                                                    style: Theme.of(context).textTheme.bodyLarge,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              }),
                          actions: [
                            BBDialogAction(
                              label: "View Licenses",
                              type: BBDialogButtonType.secondary,
                              onPressed: () {
                                PackageInfo.fromPlatform().then((snapshot) {
                                  Navigator.of(context).push(MaterialPageRoute<void>(
                                    builder: (BuildContext context) => Theme(
                                      data: Theme.of(context),
                                      child: LicensePage(
                                        applicationName: "BlueBubbles",
                                        applicationVersion: snapshot.version,
                                        applicationIcon: Image.asset(
                                          "assets/icon/icon.png",
                                          width: 30,
                                          height: 30,
                                        ),
                                      ),
                                    ),
                                  ));
                                });
                              },
                            ),
                            BBDialogAction(
                              label: "Close",
                              type: BBDialogButtonType.cancel,
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        );
                      },
                      leading: const BBSettingsIcon(
                        iosIcon: CupertinoIcons.info_circle,
                        materialIcon: Icons.info,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ]);
  }
}
