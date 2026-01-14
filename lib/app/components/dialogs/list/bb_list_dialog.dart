import 'package:bluebubbles/app/components/base/bb_text_field.dart';
import 'package:bluebubbles/app/components/dialogs/base/bb_base_dialog.dart';
import 'package:bluebubbles/app/components/dialogs/list/list_dialog_config.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Theme-adaptive list selection dialog component.
/// 
/// Shows dialogs for selecting one or more items from a list.
/// Supports search/filtering, single and multi-selection modes.
/// Automatically adapts to iOS, Material, and Samsung skins.
/// 
/// Example usage:
/// ```dart
/// // Single selection
/// final selected = await BBListDialog.showSingle<String>(
///   context: context,
///   title: 'Choose Color',
///   items: [
///     BBListItem(value: 'red', label: 'Red'),
///     BBListItem(value: 'blue', label: 'Blue'),
///     BBListItem(value: 'green', label: 'Green'),
///   ],
/// );
/// 
/// if (selected != null) {
///   print('Selected: $selected');
/// }
/// 
/// // Multi-selection with search
/// final selected = await BBListDialog.showMulti<String>(
///   context: context,
///   title: 'Choose Tags',
///   items: [
///     BBListItem(value: 'work', label: 'Work', subtitle: 'Work-related'),
///     BBListItem(value: 'personal', label: 'Personal', subtitle: 'Personal stuff'),
///     BBListItem(value: 'urgent', label: 'Urgent', subtitle: 'Time-sensitive'),
///   ],
///   initialSelection: ['work'],
///   config: BBListDialogConfig(enableSearch: true),
/// );
/// 
/// if (selected != null) {
///   print('Selected tags: ${selected.join(', ')}');
/// }
/// ```
class BBListDialog {
  /// Show a single-selection list dialog
  /// 
  /// Returns the selected item value, or `null` if cancelled.
  static Future<T?> showSingle<T>({
    required BuildContext context,
    required String title,
    required List<BBListItem<T>> items,
    T? initialSelection,
    String? Function(BBListItem<T>)? searchFilter,
    BBListDialogConfig? config,
  }) async {
    if (!BBBaseDialog.canShowDialog(context)) {
      return Future.value(null);
    }

    config ??= const BBListDialogConfig();

    return BBBaseDialog.show<T>(
      context: context,
      barrierDismissible: config.barrierDismissible,
      barrierColor: config.barrierColor,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      useCupertinoDialog: context.iOS,
      builder: (context) {
        return _SingleSelectionDialog<T>(
          title: title,
          items: items,
          initialSelection: initialSelection,
          searchFilter: searchFilter,
          config: config!,
        );
      },
    );
  }

  /// Show a multi-selection list dialog
  /// 
  /// Returns a list of selected item values, or `null` if cancelled.
  static Future<List<T>?> showMulti<T>({
    required BuildContext context,
    required String title,
    required List<BBListItem<T>> items,
    List<T>? initialSelection,
    String? Function(BBListItem<T>)? searchFilter,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    BBListDialogConfig? config,
  }) async {
    if (!BBBaseDialog.canShowDialog(context)) {
      return Future.value(null);
    }

    config ??= const BBListDialogConfig();

    return BBBaseDialog.show<List<T>>(
      context: context,
      barrierDismissible: config.barrierDismissible,
      barrierColor: config.barrierColor,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      useCupertinoDialog: false, // Multi-select works better with Material dialog
      builder: (context) {
        return _MultiSelectionDialog<T>(
          title: title,
          items: items,
          initialSelection: initialSelection ?? [],
          searchFilter: searchFilter,
          confirmLabel: confirmLabel,
          cancelLabel: cancelLabel,
          config: config!,
        );
      },
    );
  }
}

/// Single selection dialog widget
class _SingleSelectionDialog<T> extends StatefulWidget {
  const _SingleSelectionDialog({
    required this.title,
    required this.items,
    this.initialSelection,
    this.searchFilter,
    required this.config,
  });

  final String title;
  final List<BBListItem<T>> items;
  final T? initialSelection;
  final String? Function(BBListItem<T>)? searchFilter;
  final BBListDialogConfig config;

  @override
  State<_SingleSelectionDialog<T>> createState() => _SingleSelectionDialogState<T>();
}

class _SingleSelectionDialogState<T> extends State<_SingleSelectionDialog<T>> {
  late List<BBListItem<T>> _filteredItems;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((item) {
          final searchText = widget.searchFilter?.call(item) ??
              '${item.label} ${item.subtitle ?? ''}'.toLowerCase();
          return searchText.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.config.enableSearch) ...[
          BBTextField(
            controller: _searchController,
            placeholder: widget.config.searchPlaceholder,
            prefixIcon: Icons.search,
          ),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: _filteredItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.config.emptyText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    final isSelected = item.value == widget.initialSelection;

                    if (context.iOS) {
                      return CupertinoActionSheetAction(
                        onPressed: item.enabled
                            ? () => Navigator.pop(context, item.value)
                            : () {}, // Empty callback for disabled items
                        child: Row(
                          children: [
                            if (item.leading != null) ...[
                              item.leading!,
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.label),
                                  if (item.subtitle != null)
                                    Text(
                                      item.subtitle!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              const Icon(CupertinoIcons.check_mark),
                          ],
                        ),
                      );
                    } else {
                      return RadioListTile<T>(
                        value: item.value,
                        groupValue: widget.initialSelection,
                        onChanged: item.enabled
                            ? (value) => Navigator.pop(context, value)
                            : null,
                        title: Text(item.label),
                        subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
                        secondary: item.leading,
                      );
                    }
                  },
                ),
        ),
      ],
    );

    if (context.iOS) {
      return CupertinoActionSheet(
        title: Text(widget.title),
        message: widget.config.enableSearch ? content : null,
        actions: widget.config.enableSearch
            ? []
            : _filteredItems.map((item) {
                return CupertinoActionSheetAction(
                  onPressed: item.enabled
                      ? () => Navigator.pop(context, item.value)
                      : () {}, // Empty callback for disabled items
                  child: Text(item.label),
                );
              }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      );
    } else {
      return AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: double.maxFinite,
          child: content,
        ),
        contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      );
    }
  }
}

/// Multi selection dialog widget
class _MultiSelectionDialog<T> extends StatefulWidget {
  const _MultiSelectionDialog({
    required this.title,
    required this.items,
    required this.initialSelection,
    this.searchFilter,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.config,
  });

  final String title;
  final List<BBListItem<T>> items;
  final List<T> initialSelection;
  final String? Function(BBListItem<T>)? searchFilter;
  final String confirmLabel;
  final String cancelLabel;
  final BBListDialogConfig config;

  @override
  State<_MultiSelectionDialog<T>> createState() => _MultiSelectionDialogState<T>();
}

class _MultiSelectionDialogState<T> extends State<_MultiSelectionDialog<T>> {
  late List<BBListItem<T>> _filteredItems;
  late Set<T> _selectedValues;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _selectedValues = Set.from(widget.initialSelection);
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((item) {
          final searchText = widget.searchFilter?.call(item) ??
              '${item.label} ${item.subtitle ?? ''}'.toLowerCase();
          return searchText.contains(query);
        }).toList();
      }
    });
  }

  void _toggleSelection(T value) {
    setState(() {
      if (_selectedValues.contains(value)) {
        _selectedValues.remove(value);
      } else {
        _selectedValues.add(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.config.enableSearch) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: BBTextField(
              controller: _searchController,
              placeholder: widget.config.searchPlaceholder,
              prefixIcon: Icons.search,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Flexible(
          child: _filteredItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.config.emptyText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    final isSelected = _selectedValues.contains(item.value);

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: item.enabled
                          ? (checked) => _toggleSelection(item.value)
                          : null,
                      title: Text(item.label),
                      subtitle: item.subtitle != null ? Text(item.subtitle!) : null,
                      secondary: item.leading,
                    );
                  },
                ),
        ),
      ],
    );

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: content,
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 0),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            widget.cancelLabel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _selectedValues.toList()),
          child: Text(
            widget.confirmLabel,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
