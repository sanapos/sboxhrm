import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/responsive_helper.dart';

/// Drop-in thay cho [showModalBottomSheet]: trên web/desktop rộng sẽ giới hạn
/// bề ngang + chiều cao (sheet dạng card ở giữa, có thể cuộn), tránh sheet
/// kéo full-width trên màn lớn và tránh nội dung bị cắt. Mobile giữ nguyên.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = false,
  bool? showDragHandle,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  double webMaxWidth = 640,
}) {
  final wide = !Responsive.isCompactViewport(context);
  BoxConstraints? effective = constraints;
  if (wide) {
    final h = MediaQuery.sizeOf(context).height;
    final maxH = h * 0.9;
    if (constraints == null) {
      effective = BoxConstraints(maxWidth: webMaxWidth, maxHeight: maxH);
    } else {
      effective = constraints.copyWith(
        maxWidth: math.min(constraints.maxWidth, webMaxWidth),
        maxHeight: math.min(constraints.maxHeight, maxH),
      );
    }
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: wide ? true : isScrollControlled,
    backgroundColor: backgroundColor,
    shape: shape,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    clipBehavior: clipBehavior,
    constraints: effective,
    builder: builder,
  );
}

/// Bọc nội dung để LUÔN cuộn được khi cửa sổ nhỏ (web/desktop hẹp hoặc thấp),
/// tránh trường hợp "thấy nút nhưng kích không được" do nội dung bị cắt.
///
/// - Mặc định cuộn DỌC, có [Scrollbar] hiện rõ.
/// - Bật [horizontal] để cuộn cả NGANG (cho bảng/row rộng).
/// - [enabledWhenCompactOnly]: chỉ bật cuộn khi viewport nhỏ (mặc định luôn bật).
class AppScrollSafe extends StatelessWidget {
  const AppScrollSafe({
    super.key,
    required this.child,
    this.padding,
    this.horizontal = false,
    this.primary = false,
    this.minWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool horizontal;
  final bool primary;

  /// Bề rộng tối thiểu khi cuộn ngang (giúp bảng giữ layout, không co méo).
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final vController = primary ? null : ScrollController();
    Widget content = child;

    if (horizontal) {
      final hController = ScrollController();
      content = Scrollbar(
        controller: hController,
        thumbVisibility: true,
        notificationPredicate: (n) => n.depth == 0,
        child: SingleChildScrollView(
          controller: hController,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth ?? 0),
            child: content,
          ),
        ),
      );
    }

    final vScroll = SingleChildScrollView(
      controller: vController,
      primary: primary,
      padding: padding,
      child: content,
    );

    if (primary) return vScroll;

    return Scrollbar(
      controller: vController,
      thumbVisibility: true,
      child: vScroll,
    );
  }
}

/// Bọc một [DataTable]/bảng rộng để cuộn được cả NGANG và DỌC kèm thanh cuộn.
/// Dùng thay cho `SingleChildScrollView` đơn lẻ quanh bảng (hay bị cắt cột).
class AppTableScroll extends StatelessWidget {
  const AppTableScroll({
    super.key,
    required this.child,
    this.padding,
    this.minWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final vController = ScrollController();
    final hController = ScrollController();

    return LayoutBuilder(
      builder: (context, constraints) {
        // Bề rộng khả dụng (hữu hạn) để bảng giãn hết trên màn rộng.
        final avail = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        final floor = minWidth ?? 0;
        final target = avail > floor ? avail : floor;

        return Scrollbar(
          controller: vController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: vController,
            scrollDirection: Axis.vertical,
            padding: padding,
            child: Scrollbar(
              controller: hController,
              thumbVisibility: true,
              notificationPredicate: (n) => n.depth == 0,
              child: SingleChildScrollView(
                controller: hController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: target),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tiện ích: trả về `true` nếu nên ưu tiên cuộn toàn trang (viewport nhỏ).
bool shouldUseSafeScroll(BuildContext context) =>
    Responsive.isCompactViewport(context);
