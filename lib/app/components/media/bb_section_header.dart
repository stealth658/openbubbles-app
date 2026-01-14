import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Section header component for media sections
/// 
/// Provides consistent styling for section headers with design token spacing.
/// 
/// Example:
/// ```dart
/// BBSectionHeader(text: "IMAGES & VIDEOS")
/// ```
class BBSectionHeader extends StatelessWidget {
  const BBSectionHeader({
    super.key,
    required this.text,
    this.padding,
  });

  /// The header text to display
  final String text;

  /// Optional padding override
  /// 
  /// Defaults to EdgeInsets.only(top: 20, bottom: 5, left: 20)
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.only(
        top: BBSpacing.lg,
        bottom: BBSpacing.xs,
        left: BBSpacing.lg,
      ),
      child: Text(
        text,
        style: context.theme.textTheme.bodyMedium!.copyWith(
          color: context.theme.colorScheme.outline,
        ),
      ),
    );
  }
}
