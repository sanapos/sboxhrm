import 'package:flutter/material.dart';

/// Giao diện POS kiểu KiotViet (xanh lá chủ đạo).
abstract final class PosTheme {
  static const Color kiotBlue = Color(0xFF0070F4);
  static const Color kiotBlueLight = Color(0xFFE8F4FD);
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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );

  static InputDecoration inputDecoration({
    required String label,
    String? hint,
    Widget? suffix,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffix: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );
}
