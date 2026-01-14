import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';
import 'package:flutter/material.dart';

/// Configuration for BBListDialog
class BBListDialogConfig extends BBDialogConfig {
  const BBListDialogConfig({
    super.enableAnimations,
    super.fullscreen,
    super.semanticLabel,
    super.title,
    super.barrierDismissible,
    super.size,
    super.contentPadding,
    super.barrierColor,
    super.barrierLabel,
    super.useRootNavigator,
    this.enableSearch = false,
    this.searchPlaceholder = 'Search...',
    this.emptyText = 'No items',
    this.showDividers = true,
  });

  /// Whether to show a search field
  final bool enableSearch;
  
  /// Placeholder text for search field
  final String searchPlaceholder;
  
  /// Text to show when list is empty
  final String emptyText;
  
  /// Whether to show dividers between items
  final bool showDividers;
}

/// List item definition for selection dialogs
class BBListItem<T> {
  const BBListItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.leading,
    this.trailing,
    this.enabled = true,
  });

  /// Value associated with this item
  final T value;
  
  /// Label text
  final String label;
  
  /// Optional subtitle text
  final String? subtitle;
  
  /// Optional leading widget (icon, avatar, etc.)
  final Widget? leading;
  
  /// Optional trailing widget
  final Widget? trailing;
  
  /// Whether the item can be selected
  final bool enabled;
}
