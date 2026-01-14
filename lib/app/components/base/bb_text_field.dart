import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Theme-adaptive text field component that automatically uses the correct
/// text field implementation for the current skin (iOS, Material, Samsung).
/// 
/// Example usage:
/// ```dart
/// BBTextField(
///   controller: controller,
///   placeholder: 'Enter text',
///   onChanged: (value) => print(value),
/// )
/// ```
class BBTextField extends StatelessWidget {
  const BBTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.helperText,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.style,
    this.decoration,
  });

  /// Controller for the text field
  final TextEditingController? controller;
  
  /// Focus node for the text field
  final FocusNode? focusNode;
  
  /// Placeholder text (shown when field is empty)
  final String? placeholder;
  
  /// Label text (shown above field in Material)
  final String? label;
  
  /// Callback when text changes
  final ValueChanged<String>? onChanged;
  
  /// Callback when user submits (presses enter/done)
  final ValueChanged<String>? onSubmitted;
  
  /// Callback when field is tapped
  final VoidCallback? onTap;
  
  /// Whether the field is enabled
  final bool enabled;
  
  /// Whether the field is read-only
  final bool readOnly;
  
  /// Whether to obscure text (for passwords)
  final bool obscureText;
  
  /// Whether to enable autocorrect
  final bool autocorrect;
  
  /// Whether to enable suggestions
  final bool enableSuggestions;
  
  /// Maximum number of lines (null = unlimited)
  final int? maxLines;
  
  /// Minimum number of lines
  final int? minLines;
  
  /// Maximum character length
  final int? maxLength;
  
  /// Keyboard type
  final TextInputType? keyboardType;
  
  /// Text input action (done, next, etc.)
  final TextInputAction? textInputAction;
  
  /// Text capitalization behavior
  final TextCapitalization textCapitalization;
  
  /// Input formatters
  final List<TextInputFormatter>? inputFormatters;
  
  /// Widget to show at start of field
  final Widget? prefix;
  
  /// Widget to show at end of field
  final Widget? suffix;
  
  /// Icon to show at start of field
  final IconData? prefixIcon;
  
  /// Icon to show at end of field
  final IconData? suffixIcon;
  
  /// Error message to display
  final String? errorText;
  
  /// Helper text to display
  final String? helperText;
  
  /// Whether to autofocus this field
  final bool autofocus;
  
  /// Text alignment
  final TextAlign textAlign;
  
  /// Custom text style
  final TextStyle? style;
  
  /// Custom input decoration (overrides default theme decoration)
  /// For iOS: This parameter is ignored as CupertinoTextField doesn't use InputDecoration
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    return ThemeSwitcher(
      iOSSkin: _IOSTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTap: onTap,
        enabled: enabled,
        readOnly: readOnly,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        maxLines: maxLines,
        minLines: minLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        prefix: prefix,
        suffix: suffix,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        errorText: errorText,
        helperText: helperText,
        autofocus: autofocus,
        textAlign: textAlign,
        style: style,
        decoration: decoration,
      ),
      materialSkin: _MaterialTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        label: label,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTap: onTap,
        enabled: enabled,
        readOnly: readOnly,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        maxLines: maxLines,
        minLines: minLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        prefix: prefix,
        suffix: suffix,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        errorText: errorText,
        helperText: helperText,
        autofocus: autofocus,
        textAlign: textAlign,
        style: style,
        decoration: decoration,
      ),
      samsungSkin: _SamsungTextField(
        controller: controller,
        focusNode: focusNode,
        placeholder: placeholder,
        label: label,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTap: onTap,
        enabled: enabled,
        readOnly: readOnly,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        maxLines: maxLines,
        minLines: minLines,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        prefix: prefix,
        suffix: suffix,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        errorText: errorText,
        helperText: helperText,
        autofocus: autofocus,
        textAlign: textAlign,
        style: style,
        decoration: decoration,
      ),
    );
  }
}

// iOS-specific implementation
class _IOSTextField extends StatelessWidget {
  const _IOSTextField({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    required this.enabled,
    required this.readOnly,
    required this.obscureText,
    required this.autocorrect,
    required this.enableSuggestions,
    this.maxLines,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    required this.textCapitalization,
    this.inputFormatters,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.helperText,
    required this.autofocus,
    required this.textAlign,
    this.style,
    this.decoration,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefix;
  final Widget? suffix;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final String? errorText;
  final String? helperText;
  final bool autofocus;
  final TextAlign textAlign;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    // CupertinoTextField uses BoxDecoration, not InputDecoration
    final effectiveBoxDecoration = BoxDecoration(
      color: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(BBRadius.medium(context.currentSkin)),
      border: errorText != null
          ? Border.all(color: CupertinoColors.systemRed, width: 1)
          : null,
    );

    Widget textField = CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      prefix: prefix ?? (prefixIcon != null ? Padding(
        padding: const EdgeInsets.only(left: BBSpacing.sm),
        child: Icon(prefixIcon, size: 20, color: context.theme.colorScheme.onSurfaceVariant),
      ) : null),
      suffix: suffix ?? (suffixIcon != null ? Padding(
        padding: const EdgeInsets.only(right: BBSpacing.sm),
        child: Icon(suffixIcon, size: 20, color: context.theme.colorScheme.onSurfaceVariant),
      ) : null),
      autofocus: autofocus,
      textAlign: textAlign,
      style: style,
      padding: const EdgeInsets.symmetric(
        horizontal: BBSpacing.md,
        vertical: BBSpacing.sm,
      ),
      decoration: effectiveBoxDecoration,
    );

    // Wrap with column if we have error/helper text
    if (errorText != null || helperText != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          textField,
          if (errorText != null || helperText != null)
            Padding(
              padding: const EdgeInsets.only(top: BBSpacing.xs, left: BBSpacing.md),
              child: Text(
                errorText ?? helperText!,
                style: context.theme.textTheme.bodySmall?.copyWith(
                  color: errorText != null
                      ? CupertinoColors.systemRed
                      : context.theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      );
    }

    return textField;
  }
}

// Material-specific implementation
class _MaterialTextField extends StatelessWidget {
  const _MaterialTextField({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    required this.enabled,
    required this.readOnly,
    required this.obscureText,
    required this.autocorrect,
    required this.enableSuggestions,
    this.maxLines,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    required this.textCapitalization,
    this.inputFormatters,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.helperText,
    required this.autofocus,
    required this.textAlign,
    this.style,
    this.decoration,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefix;
  final Widget? suffix;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final String? errorText;
  final String? helperText;
  final bool autofocus;
  final TextAlign textAlign;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final effectiveDecoration = decoration ?? InputDecoration(
      hintText: placeholder,
      labelText: label,
      errorText: errorText,
      helperText: helperText,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      suffixIcon: suffixIcon != null ? Icon(suffixIcon) : null,
      prefix: prefix,
      suffix: suffix,
      filled: true,
      fillColor: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.medium(context.currentSkin)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.medium(context.currentSkin)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.medium(context.currentSkin)),
        borderSide: BorderSide(
          color: context.theme.colorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.medium(context.currentSkin)),
        borderSide: BorderSide(
          color: context.theme.colorScheme.error,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BBSpacing.md,
        vertical: BBSpacing.sm,
      ),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      autofocus: autofocus,
      textAlign: textAlign,
      style: style,
      decoration: effectiveDecoration,
    );
  }
}

// Samsung-specific implementation (uses Material with Samsung styling)
class _SamsungTextField extends StatelessWidget {
  const _SamsungTextField({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    required this.enabled,
    required this.readOnly,
    required this.obscureText,
    required this.autocorrect,
    required this.enableSuggestions,
    this.maxLines,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    required this.textCapitalization,
    this.inputFormatters,
    this.prefix,
    this.suffix,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.helperText,
    required this.autofocus,
    required this.textAlign,
    this.style,
    this.decoration,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? prefix;
  final Widget? suffix;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final String? errorText;
  final String? helperText;
  final bool autofocus;
  final TextAlign textAlign;
  final TextStyle? style;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final effectiveDecoration = decoration ?? InputDecoration(
      hintText: placeholder,
      labelText: label,
      errorText: errorText,
      helperText: helperText,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      suffixIcon: suffixIcon != null ? Icon(suffixIcon) : null,
      prefix: prefix,
      suffix: suffix,
      filled: true,
      fillColor: context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.large(context.currentSkin)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.large(context.currentSkin)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.large(context.currentSkin)),
        borderSide: BorderSide(
          color: context.theme.colorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(BBRadius.large(context.currentSkin)),
        borderSide: BorderSide(
          color: context.theme.colorScheme.error,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: BBSpacing.lg,
        vertical: BBSpacing.md,
      ),
    );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      autofocus: autofocus,
      textAlign: textAlign,
      style: style,
      decoration: effectiveDecoration,
    );
  }
}
