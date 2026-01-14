import 'package:bluebubbles/app/design_system/tokens.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:flutter/material.dart';

/// Standardized empty state component for when there's no data to display.
/// 
/// Replaces scattered "No items" messages with a consistent, reusable component.
/// 
/// Example usage:
/// ```dart
/// BBEmptyState(
///   icon: Icons.message,
///   message: 'No messages yet',
/// )
/// 
/// // With action button
/// BBEmptyState(
///   icon: Icons.photo,
///   message: 'No photos',
///   description: 'Photos you share will appear here',
///   actionLabel: 'Share Photo',
///   onAction: () => print('Share'),
/// )
/// ```
class BBEmptyState extends StatelessWidget {
  const BBEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  /// Icon to display
  final IconData icon;
  
  /// Primary message
  final String message;
  
  /// Optional secondary description
  final String? description;
  
  /// Optional action button label
  final String? actionLabel;
  
  /// Action button callback
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: BBSpacing.paddingXXL,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 64,
              color: context.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: BBSpacing.lg),
            Text(
              message,
              style: context.titleMedium.copyWith(
                color: context.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: BBSpacing.sm),
              Text(
                description!,
                style: context.bodyMedium.copyWith(
                  color: context.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: BBSpacing.xl),
              TextButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
