import 'package:flutter/material.dart';
import '../../l10n/app_tr.dart';
import '../../design_system/tokens/app_radius.dart';
import '../../design_system/tokens/app_space.dart';

/// Giao diện POS kiểu KiotViet (xanh lá chủ đạo).
/// Radius / spacing kế thừa App DS; màu domain giữ độc lập.
abstract final class PosTheme {
  static const Color kiotBlue = Color(0xFF0070F4);
  static const Color kiotBlueLight = Color(0xFFE8F4FD);
  /// Microsoft Edge logo blue — bàn đang dùng trên sơ đồ.
  static const Color edgeBlue = Color(0xFF0078D4);
  static const Color edgeBlueLight = Color(0xFFDEECF9);
  static const Color primary = Color(0xFF00B63E);
  static const Color primaryDark = Color(0xFF009632);
  static const Color primaryLight = Color(0xFFE8F8ED);
  static const Color background = Color(0xFFF4F6F8);
  static const Color border = Color(0xFFE0E4E8);
  static const Color textPrimary = Color(0xFF1A1D21);
  static const Color textSecondary = Color(0xFF6B7280);

  static const Color goodsColor = Color(0xFF2563EB);
  static const Color serviceColor = Color(0xFF7C3AED);
  static const Color comboColor = Color(0xFFEA580C);

  static ButtonStyle filledButtonStyle = FilledButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
  );

  /// Nút chính mobile/tablet POS — xanh KiotViet, đủ lớn cho cảm ứng.
  static ButtonStyle mobilePrimaryButton = FilledButton.styleFrom(
    backgroundColor: kiotBlue,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 56),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
  );

  /// Hit-target tối thiểu trên tablet cảm ứng (≥10").
  static const double touchMin = 56.0;
  static const double touchIconMin = 48.0;

  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    Widget? suffix,
  }) =>
      InputDecoration(
        labelText: tr(label),
        hintText: trN(hint),
        suffix: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  // --- Mobile POS ---
  static const double mobileTopBarHeight = 52.0;
  static const double mobileBottomNavHeight = 56.0;
  static const double mobileCartBarHeight = 48.0;
  static const double mobileRadius = AppRadius.lg;
  static const EdgeInsets mobilePadding =
      EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: AppSpace.xs);

  static BoxDecoration mobileCardDecoration({Color? borderColor}) =>
      BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(mobileRadius),
        border: Border.all(color: borderColor ?? border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      );
}
