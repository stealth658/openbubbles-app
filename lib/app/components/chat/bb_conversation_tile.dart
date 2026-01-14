// ignore_for_file: unused_import
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/cupertino_conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/material_conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/samsung_conversation_tile.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:flutter/widgets.dart';

/// A theme-aware conversation tile component using BlueBubbles design system.
///
/// This component automatically routes to the correct theme-specific implementation
/// (Cupertino, Material, or Samsung) based on the current skin setting.
///
/// ## Features
/// - Automatic theme routing via ThemeSwitcher
/// - Consistent API across all skins
/// - Uses design tokens for spacing and borders
/// - Preserves existing functionality from theme-specific tiles
///
/// ## Design Token Migration
/// All theme-specific tiles (CupertinoConversationTile, MaterialConversationTile,
/// SamsungConversationTile) have been updated to use:
/// - `BBRadius` for border radius values
/// - `BBSpacing` for EdgeInsets and padding
/// - Consistent spacing scale across all themes
///
/// ## Example
/// ```dart
/// BBConversationTile(
///   controller: controller,
/// )
/// ```
///
/// ## Migration Note
/// This is a drop-in replacement for the existing ConversationTile.build() pattern.
/// The controller remains unchanged and contains all the tile logic.
class BBConversationTile extends StatelessWidget {
  const BBConversationTile({
    super.key,
    required this.controller,
  });

  final ConversationTileController controller;

  @override
  Widget build(BuildContext context) {
    return ThemeSwitcher(
      iOSSkin: CupertinoConversationTile(parentController: controller),
      materialSkin: MaterialConversationTile(parentController: controller),
      samsungSkin: SamsungConversationTile(parentController: controller),
    );
  }
}
