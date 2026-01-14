import 'package:bluebubbles/app/components/dialogs/alert/alert_dialog_config.dart';
import 'package:bluebubbles/app/components/dialogs/base/bb_base_dialog.dart';
import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Action button for dialog
class BBDialogAction {
  const BBDialogAction({
    required this.label,
    this.onPressed,
    this.type = BBDialogButtonType.primary,
    this.isDefault = false,
  });

  /// Button label text
  final String label;
  
  /// Callback when button is pressed (null = close dialog)
  final VoidCallback? onPressed;
  
  /// Button type for styling
  final BBDialogButtonType type;
  
  /// Whether this is the default action (iOS: bold text)
  final bool isDefault;
  
  /// Helper getter for destructive actions
  bool get isDestructive => type == BBDialogButtonType.destructive;
}

/// Theme-adaptive alert dialog component.
/// 
/// Automatically shows the correct alert dialog for each skin:
/// - iOS: CupertinoAlertDialog with blur effect
/// - Material: Material AlertDialog with elevation
/// - Samsung: Material AlertDialog with larger corner radius
/// 
/// Example usage:
/// ```dart
/// // Simple alert
/// await BBAlertDialog.alert(
///   context: context,
///   title: 'Success',
///   message: 'Operation completed successfully',
/// );
/// 
/// // Confirmation dialog
/// final confirmed = await BBAlertDialog.confirm(
///   context: context,
///   title: 'Delete Chat?',
///   message: 'This action cannot be undone',
///   isDestructive: true,
/// );
/// 
/// if (confirmed) {
///   // Delete chat
/// }
/// 
/// // Custom actions
/// final result = await BBAlertDialog.show<String>(
///   context: context,
///   title: 'Choose Action',
///   message: 'What would you like to do?',
///   actions: [
///     BBDialogAction(
///       label: 'Cancel',
///       type: BBDialogButtonType.cancel,
///       onPressed: () => Navigator.pop(context, 'cancel'),
///     ),
///     BBDialogAction(
///       label: 'Save',
///       type: BBDialogButtonType.primary,
///       onPressed: () => Navigator.pop(context, 'save'),
///     ),
///     BBDialogAction(
///       label: 'Delete',
///       type: BBDialogButtonType.destructive,
///       onPressed: () => Navigator.pop(context, 'delete'),
///     ),
///   ],
/// );
/// ```
class BBAlertDialog {
  /// Show a simple alert dialog with an OK button
  /// 
  /// Returns when the user taps OK or dismisses the dialog.
  static Future<void> alert({
    required BuildContext context,
    required String title,
    String? message,
    String buttonLabel = 'OK',
    Widget? icon,
  }) {
    return show(
      context: context,
      title: title,
      message: message,
      actions: [
        BBDialogAction(
          label: buttonLabel,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      config: icon != null
          ? BBAlertDialogConfig(icon: icon)
          : null,
    );
  }

  /// Show a confirmation dialog with OK/Cancel buttons
  /// 
  /// Returns `true` if the user confirms, `false` if they cancel.
  /// Returns `false` if the dialog is dismissed without a selection.
  static Future<bool> confirm({
    required BuildContext context,
    required String title,
    String? message,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await show<bool>(
      context: context,
      title: title,
      message: message,
      actions: [
        BBDialogAction(
          label: cancelLabel,
          type: BBDialogButtonType.cancel,
          onPressed: () => Navigator.pop(context, false),
        ),
        BBDialogAction(
          label: confirmLabel,
          type: isDestructive ? BBDialogButtonType.destructive : BBDialogButtonType.primary,
          isDefault: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    );
    return result ?? false;
  }

  /// Show a custom alert dialog with specified actions
  /// 
  /// This is the most flexible method, allowing you to specify:
  /// - Custom title and message
  /// - Custom widget content (instead of message)
  /// - Multiple actions with different types
  /// - Custom configuration (icon, alignment, etc.)
  /// 
  /// Returns the result of type [T] when an action is triggered,
  /// or `null` if the dialog is dismissed.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? message,
    Widget? content,
    required List<BBDialogAction> actions,
    BBAlertDialogConfig? config,
  }) {
    if (!BBBaseDialog.canShowDialog(context)) {
      return Future.value(null);
    }

    config ??= const BBAlertDialogConfig();

    if (context.iOS) {
      return _showCupertinoAlert<T>(
        context: context,
        title: title,
        message: message,
        content: content,
        actions: actions,
        config: config,
      );
    } else {
      return _showMaterialAlert<T>(
        context: context,
        title: title,
        message: message,
        content: content,
        actions: actions,
        config: config,
      );
    }
  }

  /// Show iOS-style Cupertino alert dialog
  static Future<T?> _showCupertinoAlert<T>({
    required BuildContext context,
    required String title,
    String? message,
    Widget? content,
    required List<BBDialogAction> actions,
    required BBAlertDialogConfig config,
  }) {
    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: config.barrierDismissible,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      builder: (context) {
        Widget? dialogContent;
        
        if (content != null) {
          dialogContent = content;
        } else if (message != null) {
          dialogContent = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (config.icon != null) ...[
                config.icon!,
                const SizedBox(height: 8),
              ],
              Text(
                message,
                textAlign: config.messageAlignment ?? TextAlign.center,
              ),
            ],
          );
        } else if (config.icon != null) {
          dialogContent = config.icon;
        }

        return CupertinoAlertDialog(
          title: Text(title),
          content: dialogContent,
          actions: actions.map((action) {
            return CupertinoDialogAction(
              onPressed: action.onPressed ?? () => Navigator.pop(context),
              isDestructiveAction: action.isDestructive,
              isDefaultAction: action.isDefault,
              child: Text(action.label),
            );
          }).toList(),
        );
      },
    );
  }

  /// Show Material-style alert dialog (Material & Samsung)
  static Future<T?> _showMaterialAlert<T>({
    required BuildContext context,
    required String title,
    String? message,
    Widget? content,
    required List<BBDialogAction> actions,
    required BBAlertDialogConfig config,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: config.barrierDismissible,
      barrierColor: config.barrierColor,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        
        Widget? dialogContent;
        
        if (content != null) {
          dialogContent = content;
        } else if (message != null) {
          dialogContent = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (config.icon != null) ...[
                Center(child: config.icon!),
                const SizedBox(height: 16),
              ],
              Text(
                message,
                textAlign: config.messageAlignment ?? TextAlign.start,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          );
        } else if (config.icon != null) {
          dialogContent = Center(child: config.icon!);
        }

        return AlertDialog(
          title: Text(title),
          content: dialogContent,
          contentPadding: config.contentPadding ?? const EdgeInsets.fromLTRB(24, 20, 24, 24),
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
          ),
          actions: actions.map((action) {
            Color? textColor;
            FontWeight? fontWeight;
            
            switch (action.type) {
              case BBDialogButtonType.destructive:
                textColor = colorScheme.error;
                break;
              case BBDialogButtonType.primary:
                textColor = colorScheme.primary;
                fontWeight = FontWeight.w600;
                break;
              case BBDialogButtonType.secondary:
                textColor = context.samsung ? colorScheme.secondary : colorScheme.primary;
                break;
              case BBDialogButtonType.cancel:
                textColor = colorScheme.onSurface.withValues(alpha: 0.6);
                break;
            }

            return TextButton(
              onPressed: action.onPressed ?? () => Navigator.pop(context),
              child: Text(
                action.label,
                style: TextStyle(
                  color: textColor,
                  fontWeight: fontWeight,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
