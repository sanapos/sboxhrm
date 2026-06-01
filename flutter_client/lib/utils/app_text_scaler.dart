import 'package:flutter/material.dart';
import 'responsive_helper.dart';

/// Resolves app-wide [TextScaler]: desktop/tablet keep design sizes;
/// only narrow phones get a slight downscale. Always respects OS accessibility.
class AppTextScaler {
  AppTextScaler._();

  static TextScaler resolve(BuildContext context) {
    final mq = MediaQuery.of(context);
    final userScale = mq.textScaler.scale(1.0).clamp(0.85, 1.4);

    // Desktop & tablet: do not blow up typography (fixes overflow in tables/chips).
    if (!Responsive.isMobile(context)) {
      return TextScaler.linear(userScale);
    }

    // Very small phones: tiny downscale only.
    final w = mq.size.width;
    final narrowFactor = w < 360 ? 0.94 : 1.0;
    return TextScaler.linear((narrowFactor * userScale).clamp(0.85, 1.2));
  }
}
