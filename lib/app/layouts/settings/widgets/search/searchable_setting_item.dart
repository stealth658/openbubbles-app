import 'package:flutter/cupertino.dart';

/**
 * A delegate wrapper to use for searching settings tiles
 */
class SearchableSettingItem {
  final Widget widget;
  final String title;
  final List<String>
      searchTags; // list of keywords which can be found on each page to build a breadcrumb
  final VoidCallback? onTap; // navigation to each page from breadcrumb tile

  SearchableSettingItem(
      {required this.widget,
      required this.title,
      this.searchTags = const [],
      this.onTap});
}
