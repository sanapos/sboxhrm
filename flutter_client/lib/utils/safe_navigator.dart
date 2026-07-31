import 'package:flutter/material.dart';

import '../widgets/hrm_page_chrome.dart';

/// Tránh màn hình đen do pop nhầm route (Settings Hub) hoặc loading dialog kẹt.
class SafeNavigator {
  SafeNavigator._();

  /// Chỉ pop khi màn hình được [Navigator.push].
  /// Trong Settings Hub ([HrmPageChrome.isEmbedded]) — không pop (sẽ gỡ MainLayout).
  static void popPageIfPushed(BuildContext context, [Object? result]) {
    if (HrmPageChrome.isEmbedded) return;
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop(result);
    }
  }

  /// Hiện spinner chặn tương tác, chạy [action], luôn đóng spinner (kể cả lỗi / unmount).
  static Future<T?> runWithLoadingDialog<T>({
    required BuildContext context,
    required Future<T> Function() action,
    Widget? loading,
    bool useRootNavigator = true,
  }) async {
    final nav = Navigator.of(context, rootNavigator: useRootNavigator);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: useRootNavigator,
      builder: (_) =>
          loading ?? const Center(child: CircularProgressIndicator()),
    );
    try {
      return await action();
    } finally {
      if (nav.mounted && nav.canPop()) {
        nav.pop();
      }
    }
  }

  /// Đóng dialog/loading trên cùng stack nếu còn.
  static void dismissDialog(
    BuildContext context, {
    bool rootNavigator = true,
  }) {
    final nav = Navigator.of(context, rootNavigator: rootNavigator);
    if (nav.canPop()) nav.pop();
  }

  /// Giữ [NavigatorState] trước await — dùng trong finally thay vì context đã dispose.
  static NavigatorState capture(
    BuildContext context, {
    bool rootNavigator = true,
  }) =>
      Navigator.of(context, rootNavigator: rootNavigator);

  static void dismissCaptured(NavigatorState nav) {
    if (nav.mounted && nav.canPop()) {
      nav.pop();
    }
  }
}
