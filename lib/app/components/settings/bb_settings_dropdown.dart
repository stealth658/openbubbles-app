import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A theme-aware dropdown/picker component for settings using BlueBubbles design system.
///
/// This replaces the legacy [SettingsOptions] with better design token integration
/// and a simplified API. Automatically adapts to the current skin:
/// - iOS: CupertinoSlidingSegmentedControl
/// - Material/Samsung: DropdownButton
///
/// ## Example
/// ```dart
/// BBSettingsDropdown<String>(
///   title: "Theme",
///   options: ['Light', 'Dark', 'Auto'],
///   value: currentTheme,
///   onChanged: (newTheme) => updateTheme(newTheme),
/// )
/// ```
class BBSettingsDropdown<T extends Object> extends StatelessWidget {
  const BBSettingsDropdown({
    super.key,
    required this.title,
    required this.options,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.textProcessing,
    this.cupertinoCustomWidgets,
    this.materialCustomWidgets,
    this.capitalize = true,
    this.useCupertino = true,
    this.backgroundColor,
  });

  /// Title text for the dropdown
  final String title;

  /// List of available options
  final List<T> options;

  /// Currently selected value
  final T value;

  /// Callback when value changes
  final ValueChanged<T?> onChanged;

  /// Optional subtitle text
  final String? subtitle;

  /// Function to convert option to display string
  final String Function(T)? textProcessing;

  /// Custom widgets for iOS segmented control
  final Iterable<Widget>? cupertinoCustomWidgets;

  /// Custom widget builder for Material dropdown items
  final Widget? Function(T)? materialCustomWidgets;

  /// Whether to capitalize option text
  final bool capitalize;

  /// Whether to use Cupertino control on iOS (default: true)
  final bool useCupertino;

  /// Background color for Material dropdown (optional)
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final skin = SettingsSvc.settings.skin.value;

    // iOS uses segmented control
    if (skin == Skins.iOS && useCupertino) {
      return _buildCupertinoControl(context);
    }

    // Material/Samsung use dropdown
    return _buildMaterialDropdown(context);
  }

  Widget _buildCupertinoControl(BuildContext context) {
    final texts = options.map((e) {
      final text = textProcessing != null ? textProcessing!(e) : e.toString();
      return Text(
        capitalize ? text.capitalize! : text,
        style: context.bodyLarge.copyWith(
          color: e == value ? context.onPrimary : null,
        ),
      );
    });

    final map = Map<T, Widget>.fromIterables(
      options,
      cupertinoCustomWidgets ?? texts,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: BBSpacing.md),
      height: 50,
      width: context.width,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: CupertinoSlidingSegmentedControl<T>(
          children: map,
          groupValue: value,
          thumbColor: context.primary,
          backgroundColor: Colors.transparent,
          onValueChanged: onChanged,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildMaterialDropdown(BuildContext context) {
    Color surfaceColor = backgroundColor ?? context.properSurface;
    
    // Ensure sufficient contrast for Material skin
    if (SettingsSvc.settings.skin.value == Skins.Material &&
        surfaceColor.computeDifference(context.background) < 15) {
      surfaceColor = context.surfaceVariant;
    }

    return Container(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(BBSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Title and subtitle
            Flexible(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.bodyLarge,
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3.0),
                      child: Text(
                        subtitle!,
                        style: context.bodySmall.copyWith(
                          color: context.properOnSurface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BBSpacing.lg),
            
            // Dropdown
            Flexible(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(BBRadius.small(SettingsSvc.settings.skin.value)),
                  color: surfaceColor,
                ),
                child: Center(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<T>(
                      padding: const EdgeInsets.symmetric(horizontal: BBSpacing.sm),
                      borderRadius: BorderRadius.circular(BBRadius.small(SettingsSvc.settings.skin.value)),
                      dropdownColor: surfaceColor.withValues(alpha: 1),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: context.bodyLarge.color,
                      ),
                      isExpanded: true,
                      value: value,
                      items: options.map<DropdownMenuItem<T>>((e) {
                        final text = textProcessing != null ? textProcessing!(e) : e.toString();
                        return DropdownMenuItem(
                          value: e,
                          child: materialCustomWidgets?.call(e) ??
                              Text(
                                capitalize ? text.capitalize! : text,
                                style: context.bodyLarge,
                              ),
                        );
                      }).toList(),
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
