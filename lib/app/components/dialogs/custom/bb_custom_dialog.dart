import 'package:bluebubbles/app/components/dialogs/alert/bb_alert_dialog.dart';
import 'package:bluebubbles/app/components/dialogs/base/bb_base_dialog.dart';
import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';
import 'package:bluebubbles/app/components/dialogs/custom/custom_dialog_config.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Theme-adaptive custom content dialog component.
/// 
/// Use this when you need a dialog with custom widget content that doesn't
/// fit the standard alert, input, progress, or list patterns.
/// Automatically adapts to iOS, Material, and Samsung skins.
/// 
/// Example usage:
/// ```dart
/// final result = await BBCustomDialog.show<bool>(
///   context: context,
///   title: 'Custom Dialog',
///   content: Column(
///     mainAxisSize: MainAxisSize.min,
///     children: [
///       Image.asset('assets/icon.png', height: 100),
///       SizedBox(height: 16),
///       Text('This is custom content'),
///       SizedBox(height: 16),
///       CustomWidget(),
///     ],
///   ),
///   actions: [
///     BBDialogAction(
///       label: 'Cancel',
///       type: BBDialogButtonType.cancel,
///       onPressed: () => Navigator.pop(context, false),
///     ),
///     BBDialogAction(
///       label: 'Confirm',
///       type: BBDialogButtonType.primary,
///       onPressed: () => Navigator.pop(context, true),
///     ),
///   ],
/// );
/// 
/// // Scrollable content
/// await BBCustomDialog.show(
///   context: context,
///   title: 'Terms of Service',
///   content: Text(longTermsText),
///   config: BBCustomDialogConfig(
///     scrollable: true,
///     size: BBDialogSize.large,
///   ),
///   actions: [
///     BBDialogAction(
///       label: 'Accept',
///       onPressed: () => Navigator.pop(context),
///     ),
///   ],
/// );
/// ```
class BBCustomDialog {
  /// Show a dialog with custom content
  /// 
  /// The [content] widget will be wrapped in the appropriate dialog chrome
  /// for the current skin, with optional title and actions.
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    required Widget content,
    List<BBDialogAction>? actions,
    BBCustomDialogConfig? config,
  }) {
    if (!BBBaseDialog.canShowDialog(context)) {
      return Future.value(null);
    }

    config ??= const BBCustomDialogConfig();

    if (context.iOS) {
      return _showCupertinoCustom<T>(
        context: context,
        title: title,
        content: content,
        actions: actions,
        config: config,
      );
    } else {
      return _showMaterialCustom<T>(
        context: context,
        title: title,
        content: content,
        actions: actions,
        config: config,
      );
    }
  }

  /// Show iOS-style Cupertino custom dialog
  static Future<T?> _showCupertinoCustom<T>({
    required BuildContext context,
    String? title,
    required Widget content,
    List<BBDialogAction>? actions,
    required BBCustomDialogConfig config,
  }) {
    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: config.barrierDismissible,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      builder: (context) {
        Widget dialogContent = content;

        // Handle scrollable content
        if (config.scrollable) {
          dialogContent = SingleChildScrollView(
            child: content,
          );
        }

        return CupertinoAlertDialog(
          title: title != null ? Text(title) : null,
          content: dialogContent,
          actions: actions?.map((action) {
                return CupertinoDialogAction(
                  onPressed: action.onPressed ?? () => Navigator.pop(context),
                  isDestructiveAction: action.isDestructive,
                  isDefaultAction: action.isDefault,
                  child: Text(action.label),
                );
              }).toList() ??
              [],
        );
      },
    );
  }

  /// Show Material-style custom dialog
  static Future<T?> _showMaterialCustom<T>({
    required BuildContext context,
    String? title,
    required Widget content,
    List<BBDialogAction>? actions,
    required BBCustomDialogConfig config,
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

        Widget dialogContent = content;

        // Handle scrollable content
        if (config.scrollable) {
          dialogContent = SingleChildScrollView(
            child: content,
          );
        }

        return AlertDialog(
          title: title != null ? Text(title) : null,
          content: dialogContent,
          contentPadding: config.contentPadding ?? const EdgeInsets.fromLTRB(24, 20, 24, 24),
          insetPadding: config.insetPadding,
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
          ),
          actions: actions?.map((action) {
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
