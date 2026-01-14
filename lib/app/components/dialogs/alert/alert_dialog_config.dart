import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';
import 'package:flutter/material.dart';

/// Configuration for BBAlertDialog
class BBAlertDialogConfig extends BBDialogConfig {
  const BBAlertDialogConfig({
    super.title,
    super.barrierDismissible,
    super.size,
    super.contentPadding,
    super.barrierColor,
    super.barrierLabel,
    super.useRootNavigator,
    super.enableAnimations,
    super.fullscreen,
    super.semanticLabel,
    this.icon,
    this.messageAlignment,
  });

  /// Optional icon to display above the message
  final Widget? icon;
  
  /// Text alignment for the message content
  final TextAlign? messageAlignment;
}