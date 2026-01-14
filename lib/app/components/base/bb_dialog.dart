import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Theme-adaptive dialog component.
/// 
/// Automatically shows the correct dialog type for each skin:
/// - iOS: CupertinoAlertDialog
/// - Material/Samsung: Material AlertDialog
/// 
/// Example usage:
/// ```dart
/// BBDialog.show(
///   context: context,
///   title: 'Delete Chat?',
///   content: 'This action cannot be undone.',
///   actions: [
///     BBDialogAction(
///       label: 'Cancel',
///       onPressed: () => Navigator.pop(context),
///     ),
///     BBDialogAction(
///       label: 'Delete',
///       isDestructive: true,
///       onPressed: () {
///         // Delete logic
///         Navigator.pop(context);
///       },
///     ),
///   ],
/// )
/// ```
class BBDialog {
  /// Show a theme-appropriate dialog
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? content,
    required List<BBDialogAction> actions,
    bool barrierDismissible = true,
  }) {
    final iOS = context.iOS;
    
    if (iOS) {
      return showCupertinoDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (context) => CupertinoAlertDialog(
          title: Text(title),
          content: content != null ? Text(content) : null,
          actions: actions.map((action) => CupertinoDialogAction(
            onPressed: action.onPressed,
            isDestructiveAction: action.isDestructive,
            isDefaultAction: action.isDefault,
            child: Text(action.label),
          )).toList(),
        ),
      );
    } else {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: content != null ? Text(content) : null,
          actions: actions.map((action) => TextButton(
            onPressed: action.onPressed,
            child: Text(
              action.label,
              style: action.isDestructive 
                  ? TextStyle(color: context.error)
                  : null,
            ),
          )).toList(),
        ),
      );
    }
  }

  /// Show a confirmation dialog with OK/Cancel buttons
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    String? content,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      content: content,
      actions: [
        BBDialogAction(
          label: cancelLabel,
          onPressed: () => Navigator.pop(context, false),
        ),
        BBDialogAction(
          label: confirmLabel,
          isDestructive: isDestructive,
          isDefault: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    return result ?? false;
  }
}

/// Dialog action configuration
class BBDialogAction {
  const BBDialogAction({
    required this.label,
    required this.onPressed,
    this.isDestructive = false,
    this.isDefault = false,
  });

  /// Action button label
  final String label;
  
  /// Action callback
  final VoidCallback onPressed;
  
  /// Whether this is a destructive action (red text)
  final bool isDestructive;
  
  /// Whether this is the default action (bold on iOS)
  final bool isDefault;
}
