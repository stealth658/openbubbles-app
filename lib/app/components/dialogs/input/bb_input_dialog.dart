import 'package:bluebubbles/app/components/base/bb_text_field.dart';
import 'package:bluebubbles/app/components/dialogs/alert/bb_alert_dialog.dart';
import 'package:bluebubbles/app/components/dialogs/base/bb_base_dialog.dart';
import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';
import 'package:bluebubbles/app/components/dialogs/input/input_dialog_config.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Theme-adaptive input dialog component.
/// 
/// Shows dialogs for collecting user input like text, numbers, or form data.
/// Automatically adapts to iOS, Material, and Samsung skins.
/// 
/// Example usage:
/// ```dart
/// // Simple text input
/// final name = await BBInputDialog.text(
///   context: context,
///   title: 'Enter Name',
///   placeholder: 'Your name',
///   initialValue: 'John',
/// );
/// 
/// if (name != null && name.isNotEmpty) {
///   print('User entered: $name');
/// }
/// 
/// // Multi-field form
/// final result = await BBInputDialog.form(
///   context: context,
///   title: 'Create Account',
///   fields: [
///     BBInputField(
///       key: 'email',
///       label: 'Email',
///       placeholder: 'you@example.com',
///       keyboardType: TextInputType.emailAddress,
///       validator: (value) {
///         if (value?.isEmpty ?? true) return 'Email is required';
///         if (!value!.contains('@')) return 'Invalid email';
///         return null;
///       },
///     ),
///     BBInputField(
///       key: 'password',
///       label: 'Password',
///       placeholder: 'Enter password',
///       obscureText: true,
///       validator: (value) {
///         if ((value?.length ?? 0) < 6) return 'Min 6 characters';
///         return null;
///       },
///     ),
///   ],
/// );
/// 
/// if (result != null) {
///   print('Email: ${result['email']}');
///   print('Password: ${result['password']}');
/// }
/// ```
class BBInputDialog {
  /// Show a single text input dialog
  /// 
  /// Returns the entered text, or `null` if cancelled.
  static Future<String?> text({
    required BuildContext context,
    required String title,
    String? message,
    String? placeholder,
    String? initialValue,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    BBInputDialogConfig? config,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await show<String>(
      context: context,
      title: title,
      content: _SingleInputContent(
        controller: controller,
        message: message,
        placeholder: placeholder,
        keyboardType: keyboardType,
        maxLines: maxLines,
        autofocus: config?.autofocus ?? true,
      ),
      actions: [
        BBDialogAction(
          label: cancelLabel,
          type: BBDialogButtonType.cancel,
          onPressed: () => Navigator.pop(context, null),
        ),
        BBDialogAction(
          label: confirmLabel,
          type: BBDialogButtonType.primary,
          isDefault: true,
          onPressed: () {
            final value = controller.text;
            final error = validator?.call(value);
            if (error == null) {
              Navigator.pop(context, value);
            } else {
              // Show error in snackbar or similar
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(error)),
              );
            }
          },
        ),
      ],
      config: config,
    );
    controller.dispose();
    return result;
  }

  /// Show a multi-field form dialog
  /// 
  /// Returns a map of field keys to values, or `null` if cancelled.
  static Future<Map<String, dynamic>?> form({
    required BuildContext context,
    required String title,
    required List<BBInputField> fields,
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
    BBInputDialogConfig? config,
  }) async {
    final controllers = <String, TextEditingController>{};
    final focusNodes = <String, FocusNode>{};
    
    for (final field in fields) {
      controllers[field.key] = TextEditingController(text: field.initialValue);
      focusNodes[field.key] = FocusNode();
    }

    final result = await show<Map<String, dynamic>>(
      context: context,
      title: title,
      content: _FormInputContent(
        fields: fields,
        controllers: controllers,
        focusNodes: focusNodes,
        autofocus: config?.autofocus ?? true,
      ),
      actions: [
        BBDialogAction(
          label: cancelLabel,
          type: BBDialogButtonType.cancel,
          onPressed: () => Navigator.pop(context, null),
        ),
        BBDialogAction(
          label: confirmLabel,
          type: BBDialogButtonType.primary,
          isDefault: true,
          onPressed: () {
            // Validate all fields
            for (final field in fields) {
              final value = controllers[field.key]!.text;
              final error = field.validator?.call(value);
              if (error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${field.label ?? field.key}: $error')),
                );
                return;
              }
            }
            
            // Collect values
            final values = <String, dynamic>{};
            for (final field in fields) {
              values[field.key] = controllers[field.key]!.text;
            }
            Navigator.pop(context, values);
          },
        ),
      ],
      config: config,
    );

    // Clean up controllers and focus nodes
    for (final controller in controllers.values) {
      controller.dispose();
    }
    for (final focusNode in focusNodes.values) {
      focusNode.dispose();
    }

    return result;
  }

  /// Show a custom input dialog
  /// 
  /// This allows you to provide your own input widget while still
  /// getting the standard dialog chrome and theming.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    required List<BBDialogAction> actions,
    BBInputDialogConfig? config,
  }) {
    if (!BBBaseDialog.canShowDialog(context)) {
      return Future.value(null);
    }

    config ??= const BBInputDialogConfig();

    if (context.iOS) {
      return _showCupertinoInput<T>(
        context: context,
        title: title,
        content: content,
        actions: actions,
        config: config,
      );
    } else {
      return _showMaterialInput<T>(
        context: context,
        title: title,
        content: content,
        actions: actions,
        config: config,
      );
    }
  }

  /// Show iOS-style Cupertino input dialog
  static Future<T?> _showCupertinoInput<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    required List<BBDialogAction> actions,
    required BBInputDialogConfig config,
  }) {
    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: config.barrierDismissible,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      builder: (context) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: content,
          ),
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

  /// Show Material-style input dialog
  static Future<T?> _showMaterialInput<T>({
    required BuildContext context,
    required String title,
    required Widget content,
    required List<BBDialogAction> actions,
    required BBInputDialogConfig config,
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

        return AlertDialog(
          title: Text(title),
          content: content,
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

/// Widget for single text input
class _SingleInputContent extends StatelessWidget {
  const _SingleInputContent({
    required this.controller,
    this.message,
    this.placeholder,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final String? message;
  final String? placeholder;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message != null) ...[
          Text(message!),
          const SizedBox(height: 16),
        ],
        BBTextField(
          controller: controller,
          placeholder: placeholder,
          keyboardType: keyboardType,
          maxLines: maxLines,
          autofocus: autofocus,
        ),
      ],
    );
  }
}

/// Widget for multi-field form
class _FormInputContent extends StatelessWidget {
  const _FormInputContent({
    required this.fields,
    required this.controllers,
    required this.focusNodes,
    this.autofocus = true,
  });

  final List<BBInputField> fields;
  final Map<String, TextEditingController> controllers;
  final Map<String, FocusNode> focusNodes;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < fields.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          _buildField(context, fields[i], i == 0),
        ],
      ],
    );
  }

  Widget _buildField(BuildContext context, BBInputField field, bool isFirst) {
    return BBTextField(
      controller: controllers[field.key],
      focusNode: focusNodes[field.key],
      label: field.label,
      placeholder: field.placeholder,
      keyboardType: field.keyboardType,
      maxLines: field.maxLines,
      obscureText: field.obscureText,
      enabled: field.enabled,
      autocorrect: field.autocorrect,
      textCapitalization: field.textCapitalization,
      autofocus: autofocus && isFirst,
    );
  }
}
