import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Centralized responsive breakpoints and helpers
class Responsive {
  static const double mobileBreakpoint = 768;
  static const double tabletBreakpoint = 1024;
  static const double largeBreakpoint = 1440;

  /// Tablet lớn / màn ngang ≥10" (~1024 dp) — POS F&B: sơ đồ bàn → chọn món → thanh toán
  /// theo từng bước riêng (phủ 10.1" landscape, không chờ ≥1200).
  static const double tabletLandscapeFlowBreakpoint = 1024;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  /// Màn hẹp / thấp (cửa sổ web nhỏ, tablet dọc, laptop 1366×768).
  static bool isCompactViewport(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return s.width < mobileBreakpoint || s.height < 720;
  }

  /// Một cột cuộn dọc (header + danh sách) — app mobile hoặc web viewport hẹp.
  static bool useUnifiedPageScroll(BuildContext context) =>
      isCompactViewport(context) || (!kIsWeb && isMobile(context));

  /// Bảng DataTable chỉ khi đủ rộng; viewport hẹp dùng thẻ + cuộn dọc.
  static bool preferTableListLayout(BuildContext context) =>
      !isCompactViewport(context) && (kIsWeb || !isMobile(context));

  static double dialogMaxHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height * 0.72;

  static double dialogContentWidth(BuildContext context, {double max = 560}) {
    final w = MediaQuery.sizeOf(context).width - 64;
    return max.clamp(280.0, w > 0 ? w : max);
  }

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= mobileBreakpoint && w < tabletBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  static bool isMobileOrTablet(BuildContext context) =>
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static double screenWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double screenHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  /// Returns value based on breakpoint
  static T value<T>(BuildContext context,
      {required T mobile, T? tablet, required T desktop}) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet ?? desktop;
    return desktop;
  }

  /// Padding for content areas
  static EdgeInsets contentPadding(BuildContext context) => isMobile(context)
      ? const EdgeInsets.all(12)
      : isTablet(context)
          ? const EdgeInsets.all(16)
          : const EdgeInsets.all(24);

  /// Max width for cards/content
  static double? maxContentWidth(BuildContext context) =>
      isMobile(context) ? null : null;

  /// Dialog width - full screen on mobile, constrained on desktop
  static double dialogWidth(BuildContext context) {
    final w = screenWidth(context);
    if (isMobile(context)) return w - 32;
    if (isTablet(context)) return w * 0.7;
    return w * 0.5 > 600 ? 600 : w * 0.5;
  }

  /// Number of columns for a grid
  static int gridColumns(BuildContext context, {int mobile = 1, int tablet = 2, int desktop = 3}) {
    if (isMobile(context)) return mobile;
    if (isTablet(context)) return tablet;
    return desktop;
  }

  /// Font size scaling
  static double fontSize(BuildContext context, {required double base}) {
    if (isMobile(context)) return base * 0.9;
    return base;
  }

  /// FAB góc phải — tránh che menu ⋮ / action cuối danh sách (mobile).
  static const double fabHorizontalInset = 72;

  static double fabBottomClearance(BuildContext context,
      {bool extendedFab = false}) {
    final safe = MediaQuery.paddingOf(context).bottom;
    final fabHeight = extendedFab ? 48.0 : 56.0;
    return fabHeight + 16 + safe + 8;
  }

  /// Chỉ khoảng trống dưới FAB — không lệch ngang cả trang.
  static EdgeInsets fabBodyInsets(
    BuildContext context, {
    bool extendedFab = false,
    bool enabled = true,
  }) {
    if (!enabled || !useUnifiedPageScroll(context)) return EdgeInsets.zero;
    return EdgeInsets.only(
      bottom: fabBottomClearance(context, extendedFab: extendedFab),
    );
  }

  /// Padding list (cuối danh sách): chỉ thêm khoảng trống dưới FAB.
  /// Không padding phải — tránh lệch trái cả danh sách trên mobile.
  static EdgeInsets fabListInsets(
    BuildContext context, {
    EdgeInsets base = EdgeInsets.zero,
    bool enabled = true,
    bool extendedFab = false,
    @Deprecated('Use bottom-only clearance; right inset shifts list left')
    bool trailingClearance = false,
  }) {
    if (!enabled || !useUnifiedPageScroll(context)) return base;
    return base.copyWith(
      right: trailingClearance
          ? base.right + fabHorizontalInset
          : base.right,
      bottom: base.bottom +
          fabBottomClearance(context, extendedFab: extendedFab),
    );
  }

  /// Chỉ padding dưới cho vùng cuộn có FAB — dùng thay fabListInsets khi không cần base.
  static EdgeInsets fabScrollBottomInset(
    BuildContext context, {
    bool enabled = true,
    bool extendedFab = false,
  }) {
    if (!enabled || !useUnifiedPageScroll(context)) return EdgeInsets.zero;
    return EdgeInsets.only(
      bottom: fabBottomClearance(context, extendedFab: extendedFab),
    );
  }

  /// Padding hai bên cho hàng cuộn ngang (stat cards, tab chips).
  static const EdgeInsets horizontalScrollPadding =
      EdgeInsets.symmetric(horizontal: 16);
}

/// Widget that rebuilds when orientation or size changes
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext ctx, bool isMobile, bool isTablet, bool isDesktop) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth;
        final isMobile = w < Responsive.mobileBreakpoint;
        final isTablet = w >= Responsive.mobileBreakpoint && w < Responsive.tabletBreakpoint;
        final isDesktop = w >= Responsive.tabletBreakpoint;
        return builder(ctx, isMobile, isTablet, isDesktop);
      },
    );
  }
}
