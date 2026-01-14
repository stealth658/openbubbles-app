import 'package:bluebubbles/app/components/dialogs/base/dialog_types.dart';

/// Configuration for BBProgressDialog
class BBProgressDialogConfig extends BBDialogConfig {
  const BBProgressDialogConfig({
    super.enableAnimations,
    super.fullscreen,
    super.semanticLabel,
    super.title,
    super.barrierDismissible = false, // Progress dialogs typically can't be dismissed
    super.size,
    super.contentPadding,
    super.barrierColor,
    super.barrierLabel,
    super.useRootNavigator,
  });
}
