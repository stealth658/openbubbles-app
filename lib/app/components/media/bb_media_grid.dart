import 'dart:math';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

/// Grid helper for media sections with consistent spacing and responsive columns
/// 
/// Automatically calculates the number of columns based on screen width
/// and applies consistent design token spacing.
class BBMediaGrid {
  /// Calculate the number of columns for grid based on screen width
  /// 
  /// Returns minimum 2 columns, or width divided by 200 pixels
  static int calculateCrossAxisCount(BuildContext context) {
    return max(2, NavigationSvc.width(context) ~/ 200);
  }

  /// Get standard grid padding based on current skin
  /// 
  /// iOS uses 20px horizontal padding
  /// Material/Samsung use 10px horizontal padding
  static EdgeInsets getGridPadding(Skins skin) {
    return EdgeInsets.only(
      left: skin == Skins.iOS ? BBSpacing.lg : BBSpacing.sm,
      right: skin == Skins.iOS ? BBSpacing.lg : BBSpacing.sm,
      top: BBSpacing.sm,
      bottom: BBSpacing.sm,
    );
  }

  /// Standard spacing for grids
  static const double mainAxisSpacing = BBSpacing.sm;
  static const double crossAxisSpacing = BBSpacing.sm;
}
