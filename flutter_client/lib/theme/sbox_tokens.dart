import 'package:flutter/material.dart';

import '../utils/vietnamese_font.dart';

/// SBOX Design — bộ quy chuẩn giao diện dùng chung toàn app.
///
/// Quy tắc: màn hình KHÔNG tự đặt mã màu / cỡ chữ / bo góc. Luôn lấy từ đây
/// (hoặc từ Theme) để cả phần mềm đồng nhất và đổi thương hiệu một chỗ.
abstract final class SboxColors {
  // ── Thương hiệu: xanh biển #158DC0 ──────────────────────────────
  static const brand50 = Color(0xFFE8F5FB);
  static const brand100 = Color(0xFFBFE3F3);
  static const brand200 = Color(0xFF94D0EA);
  static const brand300 = Color(0xFF6FC0E3);
  static const brand400 = Color(0xFF3FA6D2);
  /// Màu thương hiệu (logo, thanh tiêu đề, biểu đồ, điểm nhấn).
  static const brand500 = Color(0xFF158DC0);
  /// Nút chính, chữ liên kết, tab đang chọn — đủ tương phản chữ trắng (≈4.8:1).
  static const brand600 = Color(0xFF0F7BA8);
  /// Di chuột / nhấn.
  static const brand700 = Color(0xFF0B6A91);
  static const brand800 = Color(0xFF095A7B);
  /// Chữ trên nền xanh nhạt.
  static const brand900 = Color(0xFF084B67);

  static const primary = brand600;
  static const primaryHover = brand700;
  static const primarySoft = brand50;

  // ── Trung tính: một họ Slate duy nhất ───────────────────────────
  static const white = Color(0xFFFFFFFF);
  static const slate25 = Color(0xFFFBFCFE);
  static const slate50 = Color(0xFFF8FAFC);
  static const slate100 = Color(0xFFF1F5F9);
  static const slate200 = Color(0xFFE2E8F0);
  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);

  /// Nền trang (xám rất nhạt, hơi lạnh cho hợp tông xanh).
  static const page = Color(0xFFF4F7FA);
  static const surface = white;
  static const surfaceMuted = slate50;
  static const border = slate200;
  static const borderStrong = slate300;
  static const divider = Color(0xFFEDF1F5);

  static const text = slate900;
  static const textSecondary = slate600;
  static const textMuted = slate500;
  static const textDisabled = slate400;
  static const onPrimary = white;

  // ── Trạng thái ───────────────────────────────────────────────────
  static const success = Color(0xFF16A34A);
  static const successSoft = Color(0xFFDCFCE7);
  static const successText = Color(0xFF166534);

  static const warning = Color(0xFFD97706);
  static const warningSoft = Color(0xFFFEF3C7);
  static const warningText = Color(0xFF92400E);

  static const danger = Color(0xFFDC2626);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const dangerText = Color(0xFF991B1B);

  static const info = brand600;
  static const infoSoft = brand50;
  static const infoText = brand900;

  /// Dịch vụ / chốt giờ / gói.
  static const violet = Color(0xFF7C3AED);
  static const violetSoft = Color(0xFFEDE9FE);
  static const violetText = Color(0xFF5B21B6);

  /// Nút Thanh toán POS (xanh lá — hành động thu tiền).
  static const pay = Color(0xFF16A34A);
  static const payHover = Color(0xFF15803D);

  // ── Chế độ tối ───────────────────────────────────────────────────
  static const darkPage = Color(0xFF0B1220);
  static const darkSurface = Color(0xFF111A2B);
  static const darkSurfaceRaised = Color(0xFF17233A);
  static const darkBorder = Color(0xFF26344D);
  static const darkText = Color(0xFFE5EAF1);
  static const darkTextSecondary = Color(0xFF9AA8BD);
}

/// Cỡ chữ: chỉ 7 cỡ. Đậm nhạt: chỉ 4 mức.
abstract final class SboxType {
  static const caption = 12.0; // chú thích, nhãn nhỏ, chip
  static const small = 13.0; // chữ phụ, ô bảng
  static const body = 14.0; // nội dung
  static const titleSm = 16.0; // tiêu đề thẻ, mục
  static const title = 18.0; // tiêu đề hộp thoại, AppBar
  static const headline = 22.0; // tiêu đề trang
  static const display = 28.0; // số liệu lớn

  static const regular = FontWeight.w400;
  static const medium = FontWeight.w500; // nhãn, ô bảng nhấn
  static const semibold = FontWeight.w600; // tiêu đề, nút
  static const bold = FontWeight.w700; // số tiền, số liệu

  static TextStyle _t(double size, FontWeight w, Color c, {double h = 1.45, double ls = 0}) => TextStyle(
        fontFamily: kVietnameseFontFamily,
        fontFamilyFallback: kVietnameseFontFallback,
        fontSize: size,
        fontWeight: w,
        height: h,
        color: c,
        letterSpacing: ls,
      );

  static TextStyle displayStyle([Color c = SboxColors.text]) => _t(display, bold, c, h: 1.25, ls: -0.4);
  static TextStyle headlineStyle([Color c = SboxColors.text]) => _t(headline, bold, c, h: 1.3, ls: -0.2);
  static TextStyle titleStyle([Color c = SboxColors.text]) => _t(title, semibold, c, h: 1.35);
  static TextStyle titleSmStyle([Color c = SboxColors.text]) => _t(titleSm, semibold, c, h: 1.4);
  static TextStyle bodyStyle([Color c = SboxColors.text]) => _t(body, regular, c, h: 1.5);
  static TextStyle bodyStrong([Color c = SboxColors.text]) => _t(body, semibold, c, h: 1.5);
  static TextStyle smallStyle([Color c = SboxColors.textSecondary]) => _t(small, regular, c, h: 1.45);
  static TextStyle captionStyle([Color c = SboxColors.textMuted]) => _t(caption, medium, c, h: 1.4);
  static TextStyle moneyStyle({double size = body, Color c = SboxColors.text}) =>
      _t(size, bold, c, h: 1.3).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// TextTheme chuẩn cho ThemeData.
  static TextTheme textTheme(Color text, Color secondary, Color muted) => TextTheme(
        displayLarge: _t(display, bold, text, h: 1.25, ls: -0.4),
        displayMedium: _t(headline, bold, text, h: 1.3, ls: -0.2),
        displaySmall: _t(headline, semibold, text, h: 1.3),
        headlineLarge: _t(title, bold, text, h: 1.35),
        headlineMedium: _t(title, semibold, text, h: 1.35),
        headlineSmall: _t(titleSm, semibold, text, h: 1.4),
        titleLarge: _t(title, semibold, text, h: 1.35),
        titleMedium: _t(titleSm, semibold, text, h: 1.4),
        titleSmall: _t(body, semibold, text, h: 1.4),
        bodyLarge: _t(titleSm, regular, text, h: 1.5),
        bodyMedium: _t(body, regular, text, h: 1.5),
        bodySmall: _t(small, regular, secondary, h: 1.45),
        labelLarge: _t(body, medium, text, h: 1.4),
        labelMedium: _t(small, medium, secondary, h: 1.4),
        labelSmall: _t(caption, medium, muted, h: 1.4),
      );
}

/// Khoảng cách theo lưới 4.
abstract final class SboxSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// Lề trang theo bề rộng màn hình.
  static double pagePadding(double width) => width < SboxBreakpoints.mobile ? 12 : (width < SboxBreakpoints.tablet ? 16 : 24);
}

/// Bo góc: chỉ 4 mức.
abstract final class SboxRadius {
  static const sm = 6.0; // chip, ô nhỏ, checkbox
  static const md = 10.0; // nút, ô nhập, thẻ nhỏ
  static const lg = 14.0; // thẻ, hộp thoại, bảng
  static const pill = 999.0;

  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Mốc màn hình: chỉ 3.
abstract final class SboxBreakpoints {
  static const mobile = 600.0;
  static const tablet = 1024.0;
  static const wide = 1440.0;

  static bool isMobile(BuildContext c) => MediaQuery.sizeOf(c).width < mobile;
  static bool isTablet(BuildContext c) {
    final w = MediaQuery.sizeOf(c).width;
    return w >= mobile && w < tablet;
  }

  static bool isDesktop(BuildContext c) => MediaQuery.sizeOf(c).width >= tablet;
}

/// Bóng đổ: chỉ 2 mức.
abstract final class SboxShadow {
  static const card = [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D0F172A), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const overlay = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1F0F172A), blurRadius: 32, offset: Offset(0, 12)),
  ];
}

/// Chiều cao điều khiển.
abstract final class SboxSize {
  static const controlSm = 32.0;
  static const control = 40.0;
  static const controlLg = 48.0;
  /// Nút trên máy POS cảm ứng.
  static const touch = 56.0;
  static const tableHeader = 40.0;
  static const tableRow = 44.0;
  static const tableRowDense = 36.0;
}
