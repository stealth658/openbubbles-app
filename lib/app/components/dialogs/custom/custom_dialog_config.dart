import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';
import 'package:flutter/material.dart';

/// Configuration for BBCustomDialog
class BBCustomDialogConfig extends BBDialogConfig {
  const BBCustomDialogConfig({
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
    this.scrollable = false,
    this.insetPadding = const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
    this.mainAxisSize = MainAxisSize.min,
  });

  /// Whether the content should be scrollable
  final bool scrollable;
  
  /// Padding around the dialog (outside the dialog)
  final EdgeInsets insetPadding;
  
  /// How to size the dialog along the main axis
  final MainAxisSize mainAxisSize;
}
