import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Visual styles for buttons
enum BBButtonStyle {
  /// Filled button with primary color
  primary,
  
  /// Filled button with secondary color
  secondary,
  
  /// Outlined button
  outlined,
  
  /// Text-only button
  text,
}

/// Button sizes
enum BBButtonSize {
  small,
  medium,
  large,
}

/// Theme-adaptive button component that automatically uses the correct
/// button implementation for the current skin (iOS, Material, Samsung).
/// 
/// Example usage:
/// ```dart
/// BBButton(
///   label: 'Submit',
///   onPressed: () => print('Pressed'),
///   style: BBButtonStyle.primary,
/// )
/// ```
class BBButton extends StatelessWidget {
  const BBButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = BBButtonStyle.primary,
    this.size = BBButtonSize.medium,
    this.icon,
    this.loading = false,
    this.fullWidth = false,
  });

  /// Button text label
  final String label;
  
  /// Callback when button is pressed
  final VoidCallback? onPressed;
  
  /// Visual style of the button
  final BBButtonStyle style;
  
  /// Size of the button
  final BBButtonSize size;
  
  /// Optional icon to show before label
  final IconData? icon;
  
  /// Whether to show loading indicator
  final bool loading;
  
  /// Whether button should take full width
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return ThemeSwitcher(
      iOSSkin: _IOSButton(
        label: label,
        onPressed: onPressed,
        style: style,
        size: size,
        icon: icon,
        loading: loading,
        fullWidth: fullWidth,
      ),
      materialSkin: _MaterialButton(
        label: label,
        onPressed: onPressed,
        style: style,
        size: size,
        icon: icon,
        loading: loading,
        fullWidth: fullWidth,
      ),
      samsungSkin: _SamsungButton(
        label: label,
        onPressed: onPressed,
        style: style,
        size: size,
        icon: icon,
        loading: loading,
        fullWidth: fullWidth,
      ),
    );
  }
}

// ============================================================================
// iOS Implementation
// ============================================================================

class _IOSButton extends StatelessWidget {
  const _IOSButton({
    required this.label,
    required this.onPressed,
    required this.style,
    required this.size,
    this.icon,
    required this.loading,
    required this.fullWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final BBButtonStyle style;
  final BBButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final buttonHeight = _getHeight();
    final padding = _getPadding();
    final color = _getColor(context);
    final textColor = _getTextColor(context);
    
    Widget buttonChild = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CupertinoActivityIndicator(
                color: textColor,
              ),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(icon, size: 18, color: textColor),
          ),
        Text(
          label,
          style: context.labelLarge.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    if (style == BBButtonStyle.outlined || style == BBButtonStyle.text) {
      return Container(
        height: buttonHeight,
        width: fullWidth ? double.infinity : null,
        decoration: style == BBButtonStyle.outlined
            ? BoxDecoration(
                border: Border.all(color: context.primary, width: 1.5),
                borderRadius: context.radius.mediumBR,
              )
            : null,
        child: CupertinoButton(
          padding: padding,
          onPressed: loading ? null : onPressed,
          child: buttonChild,
        ),
      );
    }

    return SizedBox(
      height: buttonHeight,
      width: fullWidth ? double.infinity : null,
      child: CupertinoButton(
        color: color,
        padding: padding,
        borderRadius: context.radius.mediumBR,
        onPressed: loading ? null : onPressed,
        child: buttonChild,
      ),
    );
  }

  double _getHeight() {
    switch (size) {
      case BBButtonSize.small:
        return BBSizing.buttonSM;
      case BBButtonSize.medium:
        return BBSizing.buttonMD;
      case BBButtonSize.large:
        return BBSizing.buttonLG;
    }
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case BBButtonSize.small:
        return BBSpacing.horizontalSM;
      case BBButtonSize.medium:
        return BBSpacing.horizontalMD;
      case BBButtonSize.large:
        return BBSpacing.horizontalLG;
    }
  }

  Color _getColor(BuildContext context) {
    switch (style) {
      case BBButtonStyle.primary:
        return context.primary;
      case BBButtonStyle.secondary:
        return context.secondary;
      case BBButtonStyle.outlined:
      case BBButtonStyle.text:
        return Colors.transparent;
    }
  }

  Color _getTextColor(BuildContext context) {
    switch (style) {
      case BBButtonStyle.primary:
        return context.onPrimary;
      case BBButtonStyle.secondary:
        return context.onSecondary;
      case BBButtonStyle.outlined:
      case BBButtonStyle.text:
        return context.primary;
    }
  }
}

// ============================================================================
// Material Implementation
// ============================================================================

class _MaterialButton extends StatelessWidget {
  const _MaterialButton({
    required this.label,
    required this.onPressed,
    required this.style,
    required this.size,
    this.icon,
    required this.loading,
    required this.fullWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final BBButtonStyle style;
  final BBButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final buttonHeight = _getHeight();
    
    Widget buttonChild = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_getTextColor(context)),
              ),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(icon, size: 18),
          ),
        Text(label),
      ],
    );

    final buttonStyle = _getButtonStyle(context);

    Widget button;
    switch (style) {
      case BBButtonStyle.primary:
      case BBButtonStyle.secondary:
        button = ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: buttonStyle,
          child: buttonChild,
        );
        break;
      case BBButtonStyle.outlined:
        button = OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: buttonStyle,
          child: buttonChild,
        );
        break;
      case BBButtonStyle.text:
        button = TextButton(
          onPressed: loading ? null : onPressed,
          style: buttonStyle,
          child: buttonChild,
        );
        break;
    }

    return SizedBox(
      height: buttonHeight,
      width: fullWidth ? double.infinity : null,
      child: button,
    );
  }

  double _getHeight() {
    switch (size) {
      case BBButtonSize.small:
        return BBSizing.buttonSM;
      case BBButtonSize.medium:
        return BBSizing.buttonMD;
      case BBButtonSize.large:
        return BBSizing.buttonLG;
    }
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case BBButtonSize.small:
        return BBSpacing.horizontalSM;
      case BBButtonSize.medium:
        return BBSpacing.horizontalMD;
      case BBButtonSize.large:
        return BBSpacing.horizontalLG;
    }
  }

  ButtonStyle _getButtonStyle(BuildContext context) {
    final padding = _getPadding();
    final borderRadius = context.radius.mediumBR;
    
    Color? backgroundColor;
    Color? foregroundColor;
    
    switch (style) {
      case BBButtonStyle.primary:
        backgroundColor = context.primary;
        foregroundColor = context.onPrimary;
        break;
      case BBButtonStyle.secondary:
        backgroundColor = context.secondary;
        foregroundColor = context.onSecondary;
        break;
      case BBButtonStyle.outlined:
      case BBButtonStyle.text:
        foregroundColor = context.primary;
        break;
    }

    return ButtonStyle(
      padding: WidgetStateProperty.all(padding),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      backgroundColor: backgroundColor != null 
          ? WidgetStateProperty.all(backgroundColor)
          : null,
      foregroundColor: WidgetStateProperty.all(foregroundColor),
    );
  }

  Color _getTextColor(BuildContext context) {
    switch (style) {
      case BBButtonStyle.primary:
        return context.onPrimary;
      case BBButtonStyle.secondary:
        return context.onSecondary;
      case BBButtonStyle.outlined:
      case BBButtonStyle.text:
        return context.primary;
    }
  }
}

// ============================================================================
// Samsung Implementation
// ============================================================================

class _SamsungButton extends StatelessWidget {
  const _SamsungButton({
    required this.label,
    required this.onPressed,
    required this.style,
    required this.size,
    this.icon,
    required this.loading,
    required this.fullWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final BBButtonStyle style;
  final BBButtonSize size;
  final IconData? icon;
  final bool loading;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final buttonHeight = _getHeight();
    
    Widget buttonChild = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_getTextColor(context)),
              ),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(icon, size: 18),
          ),
        Text(label),
      ],
    );

    final buttonStyle = _getButtonStyle(context);

    Widget button;
    switch (style) {
      case BBButtonStyle.primary:
      case BBButtonStyle.secondary:
        button = ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: buttonStyle,
          child: buttonChild,
        );
        break;
      case BBButtonStyle.outlined:
        button = OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: buttonStyle,
          child: buttonChild,
        );
        break;
      case BBButtonStyle.text:
        button = TextButton(
          onPressed: loading ? null : onPressed,
          style: buttonStyle,
          child: buttonChild,
        );
        break;
    }

    return SizedBox(
      height: buttonHeight,
      width: fullWidth ? double.infinity : null,
      child: button,
    );
  }

  double _getHeight() {
    switch (size) {
      case BBButtonSize.small:
        return BBSizing.buttonSM;
      case BBButtonSize.medium:
        return BBSizing.buttonMD;
      case BBButtonSize.large:
        return BBSizing.buttonLG;
    }
  }

  EdgeInsets _getPadding() {
    switch (size) {
      case BBButtonSize.small:
        return BBSpacing.horizontalMD;
      case BBButtonSize.medium:
        return BBSpacing.horizontalLG;
      case BBButtonSize.large:
        return BBSpacing.horizontalXL;
    }
  }

  ButtonStyle _getButtonStyle(BuildContext context) {
    final padding = _getPadding();
    // Samsung uses larger, more rounded borders (squircle-like)
    final borderRadius = context.radius.largeBR;
    
    Color? backgroundColor;
    Color? foregroundColor;
    
    switch (style) {
      case BBButtonStyle.primary:
        backgroundColor = context.primary;
        foregroundColor = context.onPrimary;
        break;
      case BBButtonStyle.secondary:
        backgroundColor = context.secondary;
        foregroundColor = context.onSecondary;
        break;
      case BBButtonStyle.outlined:
      case BBButtonStyle.text:
        foregroundColor = context.primary;
        break;
    }

    return ButtonStyle(
      padding: WidgetStateProperty.all(padding),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: borderRadius),
      ),
      backgroundColor: backgroundColor != null 
          ? WidgetStateProperty.all(backgroundColor)
          : null,
      foregroundColor: WidgetStateProperty.all(foregroundColor),
      elevation: WidgetStateProperty.all(2), // Samsung style has subtle elevation
    );
  }

  Color _getTextColor(BuildContext context) {
    switch (style) {
      case BBButtonStyle.primary:
        return context.onPrimary;
      case BBButtonStyle.secondary:
        return context.onSecondary;
      case BBButtonStyle.outlined:
      case BBButtonStyle.text:
        return context.primary;
    }
  }
}
