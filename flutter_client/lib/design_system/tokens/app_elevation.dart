import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';

abstract final class AppElevation {
  static const double none = 0;
  static const double low = 1;
  static const double mid = 2;

  static List<BoxShadow> soft({Color? color}) => [
        BoxShadow(
          color: (color ?? Colors.black).withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static BoxDecoration cardSurface({
    Color? color,
    Color? borderColor,
    bool elevated = false,
  }) =>
      BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: AppRadius.card,
        border: Border.all(color: borderColor ?? AppColors.borderSubtle),
        boxShadow: elevated ? soft() : null,
      );
}
