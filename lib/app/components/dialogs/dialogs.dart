/// BlueBubbles Dialog Components
/// 
/// This library provides a comprehensive set of theme-adaptive dialog components
/// that automatically adapt to iOS, Material, and Samsung skins.
/// 
/// ## Available Dialog Types:
/// 
/// - **BBAlertDialog**: Alert and confirmation dialogs
/// - **BBInputDialog**: Text input and form dialogs
/// - **BBProgressDialog**: Loading and progress dialogs
/// - **BBListDialog**: Single and multi-selection list dialogs
/// - **BBCustomDialog**: Custom content dialogs
/// 
/// ## Quick Start:
/// 
/// ```dart
/// import 'package:bluebubbles/app/components/dialogs/dialogs.dart';
/// 
/// // Simple alert
/// await BBAlertDialog.alert(
///   context: context,
///   title: 'Success',
///   message: 'Operation completed',
/// );
/// 
/// // Confirmation
/// final confirmed = await BBAlertDialog.confirm(
///   context: context,
///   title: 'Delete?',
///   message: 'This cannot be undone',
///   isDestructive: true,
/// );
/// 
/// // Text input
/// final name = await BBInputDialog.text(
///   context: context,
///   title: 'Enter Name',
///   placeholder: 'Your name',
/// );
/// 
/// // Progress
/// final controller = BBProgressController();
/// BBProgressDialog.showWithProgress(
///   context: context,
///   title: 'Uploading',
///   controller: controller,
/// );
/// controller.update(progress: 0.5, message: 'Half done');
/// 
/// // List selection
/// final selected = await BBListDialog.showSingle<String>(
///   context: context,
///   title: 'Choose',
///   items: [
///     BBListItem(value: 'a', label: 'Option A'),
///     BBListItem(value: 'b', label: 'Option B'),
///   ],
/// );
/// ```
library;

// Base types and infrastructure
export 'base/bb_base_dialog.dart';
export 'base/dialog_types.dart';

// Alert dialogs
export 'alert/bb_alert_dialog.dart';
export 'alert/alert_dialog_config.dart';

// Input dialogs
export 'input/bb_input_dialog.dart';
export 'input/input_dialog_config.dart';

// Progress dialogs
export 'progress/bb_progress_dialog.dart';
export 'progress/progress_dialog_config.dart';

// List dialogs
export 'list/bb_list_dialog.dart';
export 'list/list_dialog_config.dart';

// Custom dialogs
export 'custom/bb_custom_dialog.dart';
export 'custom/custom_dialog_config.dart';
