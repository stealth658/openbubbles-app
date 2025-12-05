import 'package:bluebubbles/app/layouts/settings/pages/server/server_management_panel.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/search/searchable_setting_item.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/search/settings_search_breadcrumb_tile.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/search/settings_items_list.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/search/settings_search_bar.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/search/settings_search_empty_result.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/settings_widgets.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/app/wrappers/tablet_mode_wrapper.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide Response;

class SettingsPage extends StatefulWidget {
  SettingsPage({
    super.key,
    this.initialPage,
  });

  final Widget? initialPage;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends OptimizedState<SettingsPage> {
  final RxBool uploadingContacts = false.obs;
  final RxnDouble progress = RxnDouble();
  final RxnInt totalSize = RxnInt();

  String searchQuery = "";

  @override
  void initState() {
    super.initState();

    if (showAltLayoutContextless) {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        ns.pushAndRemoveSettingsUntil(
          context,
          widget.initialPage ?? ServerManagementPanel(),
          (route) => route.isFirst,
        );
      });
    } else if (widget.initialPage != null) {
      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        ns.pushSettings(
          context,
          widget.initialPage!,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsItemList = buildSettingItemList(
        context: context,
        searchQuery: searchQuery,
        tileColor: tileColor,
        samsung: samsung,
        iOS: iOS,
        material: material,
        iosSubtitle: iosSubtitle,
        materialSubtitle: materialSubtitle,
        ss: ss,
        ns: ns,
        progress: progress,
        totalSize: totalSize,
        uploadingContacts: uploadingContacts);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: ss.settings.immersiveMode.value
              ? Colors.transparent
              : context.theme.colorScheme.background, // navigation bar color
          systemNavigationBarIconBrightness:
              context.theme.colorScheme.brightness.opposite,
          statusBarColor: Colors.transparent, // status bar color
          statusBarIconBrightness:
              context.theme.colorScheme.brightness.opposite,
        ),
        child: Actions(
            actions: {
              GoBackIntent: GoBackAction(context),
            },
            child: Obx(() => Container(
                  color: context.theme.colorScheme.background
                      .themeOpacity(context),
                  child: TabletModeWrapper(
                    initialRatio: 0.4,
                    minRatio: kIsDesktop || kIsWeb ? 0.2 : 0.33,
                    maxRatio: 0.5,
                    allowResize: true,
                    left: SettingsScaffold(
                      title: "Settings",
                      initialHeader: kIsWeb
                          ? "Server & Message Management"
                          : (!iOS || kIsDesktop)
                              ? "Profile"
                              : null,
                      iosSubtitle: iosSubtitle,
                      materialSubtitle: materialSubtitle,
                      tileColor: tileColor,
                      headerColor: headerColor,
                      bodySlivers: [
                        SliverList(
                          delegate: SliverChildListDelegate([
                            SettingsSearchBar(
                              iOS: iOS,
                              onChanged: (value) {
                                setState(() {
                                  searchQuery = value.trim();
                                });
                              },
                            ),
                            ...(() {
                              final lowerQuery = searchQuery.toLowerCase();

                              // Build widgets list dynamically
                              final List<Widget> widgets = [];

                              for (final item in settingsItemList) {
                                if (item is SearchableSettingItem) {
                                  // Flat item (SearchableSettingItem)
                                  final titleMatches = item.title
                                      .toLowerCase()
                                      .contains(lowerQuery);
                                  final tagMatches = item.searchTags.any(
                                    (tag) =>
                                        tag.toLowerCase().contains(lowerQuery),
                                  );

                                  if (searchQuery.isEmpty ||
                                      titleMatches ||
                                      tagMatches) {
                                    widgets.add(item);

                                    if (searchQuery.isNotEmpty) {
                                      final matchingTags =
                                          item.searchTags.where(
                                        (tag) => tag
                                            .toLowerCase()
                                            .contains(lowerQuery),
                                      );

                                      for (final tag in matchingTags) {
                                        widgets.add(SearchBreadcrumbTile(
                                          origin: item.title,
                                          destination: tag,
                                          onTap: item.onTap,
                                        ));
                                      }
                                    }
                                  }
                                } else if (item is SettingsSection) {
                                  // Section → recurse into children
                                  final sectionWidgets = <Widget>[];

                                  if (item.searchableSettingsItems != null) {
                                    final matchingItems = item
                                        .searchableSettingsItems!
                                        .where((childItem) {
                                      final titleMatches = childItem.title
                                          .toLowerCase()
                                          .contains(lowerQuery);
                                      final tagMatches =
                                          childItem.searchTags.any(
                                        (tag) => tag
                                            .toLowerCase()
                                            .contains(lowerQuery),
                                      );
                                      return titleMatches || tagMatches;
                                    }).toList();

                                    if (searchQuery.isEmpty) {
                                      // No search → show whole section
                                      sectionWidgets.add(item);
                                    } else if (matchingItems.isNotEmpty) {
                                      // If any children match → rebuild section with only matching children
                                      sectionWidgets.add(SettingsSection(
                                        backgroundColor: item.backgroundColor,
                                        searchQuery: searchQuery,
                                        searchableSettingsItems: matchingItems,
                                        children:
                                            null, // Only show matching searchable children
                                      ));

                                      // Add breadcrumbs for matching child tags
                                      for (final matchingItem
                                          in matchingItems) {
                                        final matchingTags =
                                            matchingItem.searchTags.where(
                                          (tag) => tag
                                              .toLowerCase()
                                              .contains(lowerQuery),
                                        );

                                        for (final tag in matchingTags) {
                                          sectionWidgets
                                              .add(SearchBreadcrumbTile(
                                            origin: matchingItem.title,
                                            destination: tag,
                                            onTap: matchingItem.onTap,
                                          ));
                                        }
                                      }
                                    }
                                  } else if (item.children != null &&
                                      searchQuery.isEmpty) {
                                    // Section with non-searchable children → show if no search
                                    sectionWidgets.add(item);
                                  }

                                  // Add section content to main list
                                  widgets.addAll(sectionWidgets);
                                } else {
                                  // Other Widget → show only if no search
                                  if (searchQuery.isEmpty) {
                                    widgets.add(item);
                                  }
                                }
                              }

                              // If searching and no results → show EmptySearchResult
                              final visibleWidgetsCount = widgets.length;
                              if (searchQuery.isNotEmpty &&
                                  visibleWidgetsCount <= 1) {
                                return [EmptySearchResult(searchQuery: searchQuery)];
                              }

                              return widgets;
                            })(),
                          ]),
                        ),
                      ],
                    ),
                    right: LayoutBuilder(builder: (context, constraints) {
                      ns.maxWidthSettings = constraints.maxWidth;
                      return PopScope(
                        canPop: false,
                        onPopInvoked: (_) async {
                          Get.until((route) {
                            if (route.settings.name == "initial") {
                              Get.back();
                            } else {
                              Get.back(id: 3);
                            }
                            return true;
                          }, id: 3);
                        },
                        child: Navigator(
                          key: Get.nestedKey(3),
                          onPopPage: (route, _) {
                            route.didPop(false);
                            return false;
                          },
                          pages: [
                            CupertinoPage(
                                name: "initial",
                                child: Scaffold(
                                    backgroundColor:
                                        ss.settings.skin.value != Skins.iOS
                                            ? tileColor
                                            : headerColor,
                                    body: Center(
                                      child: Text(
                                          "Select a settings page from the list",
                                          style: context
                                              .theme.textTheme.bodyLarge),
                                    ))),
                          ],
                        ),
                      );
                    }),
                  ),
                ))),
      ),
    );
  }
}
