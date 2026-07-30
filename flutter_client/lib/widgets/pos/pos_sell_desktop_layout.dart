import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bố cục POS desktop/tablet — 2 hoặc 3 cột, tái dùng builder từ [PosSellScreen].
///
/// Breakpoint:
/// - ≥ [Responsive.largeBreakpoint] (1440): 3 cột catalog | cart | pay
/// - ≥ [Responsive.tabletBreakpoint] (1024): 3 cột (catalog hẹp hơn)
/// - 768–1023: 2 cột (trái catalog/floor, phải order+pay gộp)
class PosSellDesktopLayout extends StatelessWidget {
  const PosSellDesktopLayout({
    super.key,
    required this.topBar,
    required this.bottomBar,
    this.banner,
    required this.leftPane,
    required this.centerPane,
    this.rightPane,
    this.combineOrderAndPay = false,
  });

  final Widget topBar;
  final Widget bottomBar;
  final Widget? banner;

  /// Catalog hoặc sơ đồ bàn.
  final Widget leftPane;

  /// Giỏ hàng (hoặc panel chờ chọn bàn).
  final Widget centerPane;

  /// Thanh toán — null khi [combineOrderAndPay] (gộp vào center).
  final Widget? rightPane;

  /// Tablet hẹp: gộp cart+pay vào center, không hiện right.
  final bool combineOrderAndPay;

  static bool useThreeColumns(double width) =>
      width >= Responsive.tabletBreakpoint;

  static bool useLargeThreeColumns(double width) =>
      width >= Responsive.largeBreakpoint;

  /// Flex trái / giữa / phải theo độ rộng.
  static (int, int, int) flexFor(double width, {bool floorPrimary = false}) {
    // Ưu tiên cột đơn hàng (giữa) rộng hơn để SL / ĐVT / giá không bị chật.
    if (width >= Responsive.largeBreakpoint) {
      return floorPrimary ? (4, 5, 3) : (4, 5, 3);
    }
    if (width >= Responsive.tabletBreakpoint) {
      return floorPrimary ? (4, 5, 3) : (4, 5, 3);
    }
    return (1, 1, 0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final three = useThreeColumns(w) &&
            !combineOrderAndPay &&
            rightPane != null;
        final flex = flexFor(w);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            topBar,
            if (banner != null) banner!,
            Expanded(
              child: three
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: flex.$1, child: leftPane),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: PosTheme.border,
                        ),
                        Expanded(flex: flex.$2, child: centerPane),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: PosTheme.border,
                        ),
                        Expanded(flex: flex.$3, child: rightPane!),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: leftPane),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: PosTheme.border,
                        ),
                        Expanded(flex: 5, child: centerPane),
                      ],
                    ),
            ),
            bottomBar,
          ],
        );
      },
    );
  }
}

/// Panel chờ chọn bàn (cột phải khi đang xem sơ đồ desktop).
class PosSellDesktopFloorHint extends StatelessWidget {
  const PosSellDesktopFloorHint({super.key, this.title = 'Chọn bàn bên trái'});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.table_restaurant_outlined,
                  size: 56, color: PosTheme.kiotBlue.withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(
                tr(title),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: PosTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(tr('Sau khi chọn bàn, cột này hiện giỏ hàng và thanh toán.'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
