import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import '../search/searchable_setting_item.dart';

class SettingsSection extends StatelessWidget {
  final List<Widget>? children;
  // group searchable settings into a rounded rectangle
  final List<SearchableSettingItem>? searchableSettingsItems;
  final Color backgroundColor;
  final String? searchQuery;

  SettingsSection({
    this.children,
    required this.backgroundColor,
    this.searchableSettingsItems,
    this.searchQuery,
  });

  @override
  Widget build(BuildContext context) {
    List<Widget> displayedChildren = [];

    final isSearching = searchQuery != null && searchQuery!.isNotEmpty;

    if (searchableSettingsItems != null) {
      if (isSearching) {
        final lowerQuery = searchQuery!.toLowerCase();

        final matchingItems = searchableSettingsItems!.where((item) {
          final titleMatches = item.title.toLowerCase().contains(lowerQuery);
          final tagMatches = item.searchTags.any(
                (tag) => tag.toLowerCase().contains(lowerQuery),
          );
          return titleMatches || tagMatches;
        }).toList();

        displayedChildren = matchingItems.map((item) => item.child).toList();
      } else {
        // No search → show all searchable items
        displayedChildren = searchableSettingsItems!.map((item) => item.child).toList();
      }
    } else if (children != null) {
      displayedChildren = children!;
    }

    // If searching and nothing matches → hide section
    if (displayedChildren.isEmpty && isSearching) {
      return const SizedBox.shrink();
    }

    // Always return section container
    return Padding(
      padding: ss.settings.skin.value == Skins.iOS
          ? const EdgeInsets.symmetric(horizontal: 20)
          : ss.settings.skin.value == Skins.Samsung
          ? const EdgeInsets.symmetric(vertical: 5)
          : EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: ss.settings.skin.value == Skins.Samsung
            ? BorderRadius.circular(25)
            : ss.settings.skin.value == Skins.iOS
            ? BorderRadius.circular(10)
            : BorderRadius.circular(0),
        clipBehavior: ss.settings.skin.value != Skins.Material ? Clip.antiAlias : Clip.none,
        child: Container(
          color: ss.settings.skin.value == Skins.iOS ? null : backgroundColor,
          decoration: ss.settings.skin.value == Skins.iOS
              ? BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: backgroundColor.darkenAmount(0.1).withValues(alpha: 0.25),
                spreadRadius: 5,
                blurRadius: 7,
                offset: const Offset(0, 3),
              ),
            ],
          )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: displayedChildren,
          ),
        ),
      ),
    );
  }
}
