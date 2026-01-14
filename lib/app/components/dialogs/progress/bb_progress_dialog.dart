import 'package:bluebubbles/app/components/base/bb_loading_indicator.dart';
import 'package:bluebubbles/app/components/dialogs/base/bb_base_dialog.dart';
import 'package:bluebubbles/app/components/dialogs/progress/progress_dialog_config.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Controller for managing progress dialog state
/// 
/// Use this to update progress and message dynamically while the dialog is shown.
class BBProgressController extends ChangeNotifier {
  BBProgressController({
    double? progress,
    String? message,
  })  : _progress = progress,
        _message = message;

  double? _progress; // null = indeterminate
  String? _message;
  bool _isComplete = false;

  /// Current progress value (0.0 to 1.0), or null for indeterminate
  double? get progress => _progress;

  /// Current message text
  String? get message => _message;

  /// Whether the operation is complete
  bool get isComplete => _isComplete;

  /// Update progress and/or message
  /// 
  /// Set [progress] to a value between 0.0 and 1.0, or null for indeterminate.
  /// Set [message] to update the displayed text.
  void update({double? progress, String? message}) {
    if (progress != null) {
      _progress = progress.clamp(0.0, 1.0);
    }
    if (message != null) {
      _message = message;
    }
    notifyListeners();
  }

  /// Mark the operation as complete
  /// 
  /// This sets progress to 1.0 and can optionally update the message.
  void complete([String? message]) {
    _progress = 1.0;
    if (message != null) {
      _message = message;
    }
    _isComplete = true;
    notifyListeners();
  }
}

/// Theme-adaptive progress dialog component.
/// 
/// Shows dialogs for displaying progress of long-running operations.
/// Supports both determinate (with progress bar) and indeterminate (spinner only) modes.
/// Automatically adapts to iOS, Material, and Samsung skins.
/// 
/// Example usage:
/// ```dart
/// // Indeterminate progress (simple spinner)
/// showDialog(
///   context: context,
///   barrierDismissible: false,
///   builder: (_) => BBProgressDialog.indeterminate(
///     title: 'Loading',
///     message: 'Please wait...',
///   ),
/// );
/// 
/// // Later: dismiss
/// Navigator.pop(context);
/// 
/// // Determinate progress with controller
/// final controller = BBProgressController(
///   progress: 0.0,
///   message: 'Starting...',
/// );
/// 
/// final result = await BBProgressDialog.showWithProgress(
///   context: context,
///   title: 'Uploading',
///   controller: controller,
/// );
/// 
/// // Update progress
/// controller.update(progress: 0.5, message: 'Halfway there...');
/// 
/// // Complete and close
/// controller.complete('Done!');
/// await Future.delayed(Duration(milliseconds: 500));
/// Navigator.pop(context, true);
/// 
/// controller.dispose();
/// ```
class BBProgressDialog {
  /// Show an indeterminate progress dialog
  /// 
  /// Returns a Future that completes when the dialog is dismissed.
  /// Use this for operations where you can't track progress precisely.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? message,
    bool barrierDismissible = false,
    BBProgressDialogConfig? config,
  }) {
    if (!BBBaseDialog.canShowDialog(context)) {
      return Future.value(null);
    }

    config ??= const BBProgressDialogConfig();

    return BBBaseDialog.show<T>(
      context: context,
      barrierDismissible: config.barrierDismissible || barrierDismissible,
      barrierColor: config.barrierColor,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      useCupertinoDialog: context.iOS,
      builder: (context) {
        if (context.iOS) {
          return CupertinoAlertDialog(
            title: Text(title),
            content: _IndeterminateProgressContent(message: message),
          );
        } else {
          return AlertDialog(
            title: Text(title),
            content: _IndeterminateProgressContent(message: message),
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
            ),
          );
        }
      },
    );
  }

  /// Show a determinate progress dialog with a controller
  /// 
  /// Use the [controller] to update progress and message while the dialog is shown.
  /// Returns a Future that completes when the dialog is dismissed.
  static Future<T?> showWithProgress<T>({
    required BuildContext context,
    required String title,
    required BBProgressController controller,
    bool barrierDismissible = false,
    BBProgressDialogConfig? config,
  }) {
    if (!BBBaseDialog.canShowDialog(context)) {
      return Future.value(null);
    }

    config ??= const BBProgressDialogConfig();

    return BBBaseDialog.show<T>(
      context: context,
      barrierDismissible: config.barrierDismissible || barrierDismissible,
      barrierColor: config.barrierColor,
      barrierLabel: config.barrierLabel,
      useRootNavigator: config.useRootNavigator,
      useCupertinoDialog: context.iOS,
      builder: (context) {
        if (context.iOS) {
          return CupertinoAlertDialog(
            title: Text(title),
            content: _DeterminateProgressContent(controller: controller),
          );
        } else {
          return AlertDialog(
            title: Text(title),
            content: _DeterminateProgressContent(controller: controller),
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
            ),
          );
        }
      },
    );
  }

  /// Create an indeterminate progress dialog widget
  /// 
  /// Use this when you want to manually control showing/dismissing via showDialog.
  static Widget indeterminate({
    required String title,
    String? message,
  }) {
    return Builder(
      builder: (context) {
        if (context.iOS) {
          return CupertinoAlertDialog(
            title: Text(title),
            content: _IndeterminateProgressContent(message: message),
          );
        } else {
          return AlertDialog(
            title: Text(title),
            content: _IndeterminateProgressContent(message: message),
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
            ),
          );
        }
      },
    );
  }

  /// Create a determinate progress dialog widget
  /// 
  /// Use this when you want to manually control showing/dismissing via showDialog.
  static Widget determinate({
    required String title,
    required BBProgressController controller,
  }) {
    return Builder(
      builder: (context) {
        if (context.iOS) {
          return CupertinoAlertDialog(
            title: Text(title),
            content: _DeterminateProgressContent(controller: controller),
          );
        } else {
          return AlertDialog(
            title: Text(title),
            content: _DeterminateProgressContent(controller: controller),
            backgroundColor: Theme.of(context).colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.samsung ? 32 : 28),
            ),
          );
        }
      },
    );
  }
}

/// Content widget for indeterminate progress
class _IndeterminateProgressContent extends StatelessWidget {
  const _IndeterminateProgressContent({
    this.message,
  });

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),
        const BBLoadingIndicator(size: 40),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Content widget for determinate progress with controller
class _DeterminateProgressContent extends StatelessWidget {
  const _DeterminateProgressContent({
    required this.controller,
  });

  final BBProgressController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = controller.progress;
        final message = controller.message;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            if (progress != null) ...[
              // Determinate progress bar
              if (context.iOS)
                CupertinoActivityIndicator.partiallyRevealed(
                  progress: progress,
                  radius: 20,
                )
              else
                SizedBox(
                  height: 40,
                  width: 40,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                '${(progress * 100).toInt()}%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else ...[
              // Indeterminate fallback
              const BBLoadingIndicator(size: 40),
            ],
            if (message != null) ...[
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
