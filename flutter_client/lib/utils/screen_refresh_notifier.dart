import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/pos_sell_catalog_cache.dart';
import 'pos_sell_stock_patch.dart';

class _PendingPosStockRefresh {
  const _PendingPosStockRefresh({required this.reloadCatalog});
  final bool reloadCatalog;
}

/// Global notifiers for screen refresh
class ScreenRefreshNotifier {
  static final ValueNotifier<int> attendance = ValueNotifier<int>(0);
  static final ValueNotifier<int> devices = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceByShift = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceSummary = ValueNotifier<int>(0);
  static final ValueNotifier<int> payroll = ValueNotifier<int>(0);
  static final ValueNotifier<int> dashboard = ValueNotifier<int>(0);

  static void refreshDashboardScreen() {
    dashboard.value++;
    debugPrint('🔄 Triggered dashboard screen refresh: ${dashboard.value}');
  }

  static void refreshAttendanceScreen() {
    attendance.value++;
    debugPrint('🔄 Triggered attendance screen refresh: ${attendance.value}');
  }

  static void refreshDevicesScreen() {
    devices.value++;
    debugPrint('🔄 Triggered devices screen refresh: ${devices.value}');
  }

  static void refreshAttendanceByShiftScreen() {
    attendanceByShift.value++;
  }

  static void refreshAttendanceSummaryScreen() {
    attendanceSummary.value++;
  }

  static void refreshPayrollScreen() {
    payroll.value++;
  }

  static final ValueNotifier<int> notifications = ValueNotifier<int>(0);

  static void refreshNotificationCount() {
    notifications.value++;
  }

  static final ValueNotifier<int> mobileAttendanceSettings = ValueNotifier<int>(0);
  static final ValueNotifier<int> mobileDeviceRegistration = ValueNotifier<int>(0);

  static void refreshMobileAttendanceSettings() {
    mobileAttendanceSettings.value++;
  }

  static void refreshMobileDeviceRegistration() {
    mobileDeviceRegistration.value++;
  }

  static final ValueNotifier<int> posProducts = ValueNotifier<int>(0);
  static final ValueNotifier<int> posSellProductGrid = ValueNotifier<int>(0);
  static final ValueNotifier<List<PosSellStockLineDelta>?> posSellStockPatch =
      ValueNotifier<List<PosSellStockLineDelta>?>(null);
  static final ValueNotifier<int> posSaleOrders = ValueNotifier<int>(0);
  static final ValueNotifier<int> posPurchaseReceipts = ValueNotifier<int>(0);
  static final ValueNotifier<int> posOverview = ValueNotifier<int>(0);
  static final ValueNotifier<int> posPriceLists = ValueNotifier<int>(0);
  static final ValueNotifier<int> posSellIndustry = ValueNotifier<int>(0);

  static void refreshPosProducts() {
    posProducts.value++;
  }

  static void refreshPosSellProductGrid() {
    posSellProductGrid.value++;
  }

  static void refreshPosPriceLists() {
    posPriceLists.value++;
  }

  /// Đổi hồ sơ ngành / cờ bàn–ghế — màn bán hàng cần tải lại.
  static void refreshPosSellIndustry() {
    posSellIndustry.value++;
  }

  /// Cộng/trừ tồn trên lưới bán hàng (theo SP/biến thể — khớp server).
  static void patchPosSellStockLines(List<PosSellStockLineDelta> lines) {
    if (lines.isEmpty) return;
    posSellStockPatch.value = List<PosSellStockLineDelta>.from(lines);
  }

  /// Ghi patch vào cache catalog — khi lưới bán chưa mount (F&B sơ đồ / tablet TT)
  /// vẫn trừ đúng tồn khi mở lại thực đơn trong TTL 20 phút.
  static Future<void> _applyStockLinesToSellCatalogCache(
    List<PosSellStockLineDelta> lines, {
    String? storeId,
  }) async {
    final id = (storeId ?? PosSellCatalogCache.instance.lastStoreId)?.trim() ?? '';
    if (id.isEmpty || lines.isEmpty) return;
    try {
      final snap = await PosSellCatalogCache.instance.read(id);
      if (snap == null || snap.items.isEmpty) return;
      final updated = snap.items
          .map((p) => applyPosSellStockLines(p, lines))
          .toList(growable: false);
      await PosSellCatalogCache.instance.write(
        id,
        items: updated,
        catalogVersion: snap.catalogVersion,
      );
    } catch (_) {}
  }

  static void refreshPosSaleOrders() {
    posSaleOrders.value++;
  }

  static void refreshPosPurchaseReceipts() {
    posPurchaseReceipts.value++;
  }

  static void refreshPosOverview() {
    posOverview.value++;
  }

  static Timer? _posStockRefreshTimer;
  static _PendingPosStockRefresh? _pendingPosRefresh;

  static void _flushPosStockRefresh() {
    final pending = _pendingPosRefresh;
    _pendingPosRefresh = null;
    if (pending == null) return;
    refreshPosProducts();
    refreshPosSaleOrders();
    refreshPosPurchaseReceipts();
    refreshPosOverview();
    if (pending.reloadCatalog) {
      unawaited(PosSellCatalogCache.instance.invalidateLast());
      refreshPosSellProductGrid();
    }
  }

  /// [sellStockLines]: patch tồn lưới bán hàng (bán / trả / nhập / hủy).
  /// Mặc định không reload catalog khi đã có patch — tránh refresh storm.
  static void refreshPosAfterStockChange({
    List<PosSellStockLineDelta>? sellStockLines,
    bool? reloadSellCatalog,
    String? storeId,
  }) {
    final hasPatch = sellStockLines != null && sellStockLines.isNotEmpty;
    if (hasPatch) {
      final lines = List<PosSellStockLineDelta>.from(sellStockLines);
      // Listener lưới (nếu mount) áp dụng ngay + ghi cache + clear notifier.
      patchPosSellStockLines(lines);
      // F&B/tablet: lưới dispose → notifier còn lines → ghi cache rồi clear
      // để remount không trừ lần 2.
      if (posSellStockPatch.value != null) {
        unawaited(_applyStockLinesToSellCatalogCache(lines, storeId: storeId)
            .whenComplete(() {
          if (posSellStockPatch.value != null) {
            posSellStockPatch.value = null;
          }
        }));
      }
    }
    final reloadCatalog = reloadSellCatalog ?? !hasPatch;
    _pendingPosRefresh = _PendingPosStockRefresh(reloadCatalog: reloadCatalog);
    _posStockRefreshTimer?.cancel();
    _posStockRefreshTimer = Timer(const Duration(milliseconds: 300), _flushPosStockRefresh);
  }

  static Timer? _attendanceRefreshTimer;
  static Timer? _notificationCountTimer;
  static Timer? _dashboardPunchTimer;
  static DateTime? _lastDashboardPunchRefresh;

  /// Trang chủ tải lại ~25 API — giờ vào ca (máy chấm liên tục) chỉ tải lại tối đa 1 lần / 30 giây.
  static const dashboardPunchRefreshInterval = Duration(seconds: 30);

  /// Gom refresh chấm công — tối đa 1 lần / 2s thay vì mỗi punch.
  static void scheduleAttendanceDataRefresh() {
    _attendanceRefreshTimer?.cancel();
    _attendanceRefreshTimer = Timer(const Duration(seconds: 2), () {
      refreshAttendanceScreen();
      refreshAttendanceSummaryScreen();
      refreshAttendanceByShiftScreen();
      refreshPayrollScreen();
      _scheduleDashboardPunchRefresh();
    });
  }

  static void _scheduleDashboardPunchRefresh() {
    if (_dashboardPunchTimer?.isActive == true) return; // đã hẹn lần tải sau
    final last = _lastDashboardPunchRefresh;
    final wait = last == null
        ? Duration.zero
        : dashboardPunchRefreshInterval - DateTime.now().difference(last);
    void run() {
      _lastDashboardPunchRefresh = DateTime.now();
      refreshDashboardScreen();
    }

    if (wait <= Duration.zero) {
      run();
    } else {
      _dashboardPunchTimer = Timer(wait, run);
    }
  }

  static void scheduleNotificationCountRefresh() {
    _notificationCountTimer?.cancel();
    _notificationCountTimer = Timer(const Duration(milliseconds: 800), () {
      notifications.value++;
    });
  }
}
