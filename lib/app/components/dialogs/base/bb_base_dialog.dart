import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Base dialog class with common functionality for all BB dialog types.
/// 
/// This class provides shared methods for displaying dialogs across different
/// skins (iOS, Material, Samsung) and handling common dialog operations.
/// 
/// Phase 3 Features:
/// - Animated transitions (iOS: scale+fade, Material: fade+slide)
/// - Accessibility support (semantic labels, focus management)
/// - Advanced options (custom barrier, fullscreen mode)
abstract class BBBaseDialog {
  /// Show a dialog and return result
  /// 
  /// This is a generic method for showing any type of dialog. Most dialog
  /// components will use this internally.
  /// 
  /// Phase 3 enhancements:
  /// - Animated transitions (iOS: scale+fade, Material: fade+slide)
  /// - Accessibility support via semanticLabel
  /// - Fullscreen mode support
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget Function(BuildContext) builder,
    bool barrierDismissible = true,
    Color? barrierColor,
    String? barrierLabel,
    bool useRootNavigator = true,
    bool useCupertinoDialog = false,
    bool enableAnimations = true,
    bool fullscreen = false,
    String? semanticLabel,
  }) {
    // Wrap builder with semantic labels if provided
    final wrappedBuilder = semanticLabel != null
        ? (BuildContext ctx) => wrapWithSemantics(
              child: builder(ctx),
              label: semanticLabel,
            )
        : builder;

    if (context.iOS && useCupertinoDialog) {
      // iOS dialogs with custom animations
      if (enableAnimations) {
        return showCupertinoDialog<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          barrierLabel: barrierLabel,
          useRootNavigator: useRootNavigator,
          builder: (ctx) => buildIOSAnimatedDialog(
            context: ctx,
            animation: ModalRoute.of(ctx)?.animation ?? kAlwaysCompleteAnimation,
            child: wrappedBuilder(ctx),
          ),
        );
      } else {
        return showCupertinoDialog<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          barrierLabel: barrierLabel,
          useRootNavigator: useRootNavigator,
          builder: wrappedBuilder,
        );
      }
    } else {
      // Material dialogs with custom animations
      if (enableAnimations) {
        return showGeneralDialog<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          barrierColor: barrierColor ?? Colors.black54,
          barrierLabel: barrierLabel ?? MaterialLocalizations.of(context).modalBarrierDismissLabel,
          useRootNavigator: useRootNavigator,
          pageBuilder: (ctx, animation, secondaryAnimation) {
            return fullscreen
                ? wrappedBuilder(ctx)
                : SafeArea(child: wrappedBuilder(ctx));
          },
          transitionBuilder: (ctx, animation, secondaryAnimation, child) {
            return buildMaterialAnimatedDialog(
              context: ctx,
              animation: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 250),
        );
      } else {
        return showDialog<T>(
          context: context,
          barrierDismissible: barrierDismissible,
          barrierColor: barrierColor,
          barrierLabel: barrierLabel,
          useRootNavigator: useRootNavigator,
          builder: wrappedBuilder,
        );
      }
    }
  }

  /// Get the appropriate dialog theme for the current context
  /// 
  /// This ensures dialogs have proper theming for Material and Samsung skins
  static ThemeData getDialogTheme(BuildContext context) {
    final theme = Theme.of(context);
    
    if (context.samsung) {
      // Samsung skin uses more rounded corners and different spacing
      return theme.copyWith(
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          elevation: 24,
          backgroundColor: theme.colorScheme.surface,
        ),
      );
    } else if (context.isMaterial) {
      // Material skin uses standard Material 3 styling
      return theme.copyWith(
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 24,
          backgroundColor: theme.colorScheme.surface,
        ),
      );
    }
    
    return theme;
  }

  /// Wrap dialog content for the appropriate skin
  /// 
  /// This handles skin-specific dialog chrome and styling
  static Widget wrapForSkin({
    required BuildContext context,
    required Widget child,
    String? title,
    List<Widget>? actions,
    EdgeInsets? contentPadding,
  }) {
    if (context.iOS) {
      return CupertinoAlertDialog(
        title: title != null ? Text(title) : null,
        content: child,
        actions: actions ?? [],
      );
    } else {
      return AlertDialog(
        title: title != null ? Text(title) : null,
        content: child,
        contentPadding: contentPadding ?? const EdgeInsets.fromLTRB(24, 20, 24, 24),
        actions: actions,
        backgroundColor: Theme.of(context).colorScheme.surface,
      );
    }
  }

  /// Standard dismiss logic for dialogs
  /// 
  /// Pops the current dialog with an optional result
  static void dismiss<T>(BuildContext context, [T? result]) {
    Navigator.of(context).pop(result);
  }

  /// Check if the context is still mounted before showing dialog
  /// 
  /// This helps prevent errors when trying to show dialogs on unmounted widgets
  static bool canShowDialog(BuildContext context) {
    try {
      // Try to access the navigator to check if context is mounted
      Navigator.of(context);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Build animated dialog for iOS
  /// 
  /// Provides scale + fade animation for iOS dialogs
  static Widget buildIOSAnimatedDialog({
    required BuildContext context,
    required Widget child,
    required Animation<double> animation,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
      child: ScaleTransition(
        scale: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ).drive(Tween<double>(begin: 1.15, end: 1.0)),
        child: child,
      ),
    );
  }

  /// Build animated dialog for Material
  /// 
  /// Provides fade + slide up animation for Material dialogs
  static Widget buildMaterialAnimatedDialog({
    required BuildContext context,
    required Widget child,
    required Animation<double> animation,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      ),
    );
  }

  /// Wrap dialog with semantic labels for accessibility
  /// 
  /// Ensures screen readers announce dialog content properly
  static Widget wrapWithSemantics({
    required Widget child,
    String? label,
    String? hint,
    bool isDialog = true,
  }) {
    return Semantics(
      label: label,
      hint: hint,
      namesRoute: isDialog,
      scopesRoute: isDialog,
      explicitChildNodes: true,
      child: child,
    );
  }
}
