import 'package:flutter/material.dart';
import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';

/// Giao diện POS — lấy từ bộ quy chuẩn SBOX (xanh thương hiệu #158DC0 + xanh lá thanh toán).
/// Tên cũ giữ lại để không phải sửa hàng trăm màn; giá trị trỏ về [SboxColors].
abstract final class PosTheme {
  /// Thanh top / tab active / nút chính.
  static const Color kiotBlue = SboxColors.brand600;
  static const Color kiotBlueLight = SboxColors.brand50;
  /// Bàn đang dùng trên sơ đồ.
  static const Color edgeBlue = SboxColors.brand500;
  static const Color edgeBlueLight = SboxColors.brand50;
  /// Nút Thanh toán.
  static const Color payGreen = SboxColors.pay;
  static const Color payGreenDark = SboxColors.payHover;
  static const Color primary = SboxColors.pay;
  static const Color primaryDark = SboxColors.payHover;
  static const Color primaryLight = SboxColors.successSoft;
  static const Color background = SboxColors.page;
  static const Color border = SboxColors.border;
  static const Color textPrimary = SboxColors.text;
  static const Color textSecondary = SboxColors.textMuted;

  static const Color goodsColor = SboxColors.brand600;
  static const Color serviceColor = SboxColors.violet;
  static const Color comboColor = Color(0xFFEA580C);
  static const Color materialColor = Color(0xFF0F766E);
  static const Color toppingColor = Color(0xFFDB2777);

  static ButtonStyle filledButtonStyle = FilledButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SboxRadius.md)),
  );

  /// Nút chính mobile/tablet POS — xanh dương chrome.
  static ButtonStyle mobilePrimaryButton = FilledButton.styleFrom(
    backgroundColor: kiotBlue,
    foregroundColor: Colors.white,
    minimumSize: const Size(0, 56),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  /// Nút thanh toán — xanh lá KiotViet.
  static ButtonStyle payButtonStyle({double height = 50, double radius = 10}) =>
      FilledButton.styleFrom(
        backgroundColor: payGreen,
        foregroundColor: Colors.white,
        disabledBackgroundColor: SboxColors.slate300,
        disabledForegroundColor: SboxColors.slate600,
        minimumSize: Size(0, height),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
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
        border: const OutlineInputBorder(
          borderRadius: SboxRadius.mdAll,
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: SboxRadius.mdAll,
          borderSide: BorderSide(color: border),
        ),
        // Viền đang nhập = màu thương hiệu (trước đây xanh lá, lệch với phần còn lại).
        focusedBorder: const OutlineInputBorder(
          borderRadius: SboxRadius.mdAll,
          borderSide: BorderSide(color: SboxColors.primary, width: 1.5),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      );

  // --- Mobile POS ---
  static const double mobileTopBarHeight = 52.0;
  static const double mobileBottomNavHeight = 56.0;
  static const double mobileCartBarHeight = 48.0;
  static const double mobileRadius = SboxRadius.lg;
  static const EdgeInsets mobilePadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  static BoxDecoration mobileCardDecoration({Color? borderColor}) =>
      BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(mobileRadius),
        border: Border.all(color: borderColor ?? border),
        boxShadow: SboxShadow.card,
      );
}
