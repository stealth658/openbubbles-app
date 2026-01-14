import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';
import 'package:flutter/material.dart';

/// Configuration for BBInputDialog
class BBInputDialogConfig extends BBDialogConfig {
  const BBInputDialogConfig({
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
    this.autofocus = true,
  });

  /// Whether to auto-focus the first input field
  final bool autofocus;
}

/// Input field definition for form dialogs
class BBInputField {
  const BBInputField({
    required this.key,
    this.label,
    this.placeholder,
    this.initialValue,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.obscureText = false,
    this.enabled = true,
    this.autocorrect = true,
    this.textCapitalization = TextCapitalization.none,
  });

  /// Unique key for this field (used to retrieve value)
  final String key;
  
  /// Label text (shown above field in Material)
  final String? label;
  
  /// Placeholder text
  final String? placeholder;
  
  /// Initial value for the field
  final String? initialValue;
  
  /// Keyboard type
  final TextInputType? keyboardType;
  
  /// Validation function (returns error message or null)
  final String? Function(String?)? validator;
  
  /// Maximum number of lines
  final int maxLines;
  
  /// Whether to obscure text (passwords)
  final bool obscureText;
  
  /// Whether the field is enabled
  final bool enabled;
  
  /// Whether to enable autocorrect
  final bool autocorrect;
  
  /// Text capitalization behavior
  final TextCapitalization textCapitalization;
}
