import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/pos_sell_catalog_cache.dart';
import '../utils/pos_sell_stock_patch.dart';

export '../utils/navigation_notifier.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('SBOX POS')));
  }
}

/// Đồng bộ với flutter_client MainLayout.ScreenRefreshNotifier (phần POS).
class ScreenRefreshNotifier {
  static final ValueNotifier<int> attendance = ValueNotifier<int>(0);
  static final ValueNotifier<int> devices = ValueNotifier<int>(0);
  static final ValueNotifier<int> notifications = ValueNotifier<int>(0);
  static final ValueNotifier<int> mobileAttendanceSettings = ValueNotifier<int>(0);
  static final ValueNotifier<int> mobileDeviceRegistration = ValueNotifier<int>(0);
  static final ValueNotifier<int> posProducts = ValueNotifier<int>(0);
  static final ValueNotifier<int> posSellProductGrid = ValueNotifier<int>(0);
  static final ValueNotifier<List<PosSellStockLineDelta>?> posSellStockPatch =
      ValueNotifier<List<PosSellStockLineDelta>?>(null);
  static final ValueNotifier<int> posSaleOrders = ValueNotifier<int>(0);
  static final ValueNotifier<int> posPurchaseReceipts = ValueNotifier<int>(0);
  static final ValueNotifier<int> posOverview = ValueNotifier<int>(0);
  static final ValueNotifier<int> posPriceLists = ValueNotifier<int>(0);
  static final ValueNotifier<int> posSellIndustry = ValueNotifier<int>(0);
  static final ValueNotifier<int?> pendingSubIndex = ValueNotifier<int?>(null);

  static void refreshDevicesScreen() => devices.value++;
  static void scheduleAttendanceDataRefresh() => attendance.value++;
  static void scheduleNotificationCountRefresh() => notifications.value++;
  static void refreshMobileAttendanceSettings() =>
      mobileAttendanceSettings.value++;
  static void refreshMobileDeviceRegistration() =>
      mobileDeviceRegistration.value++;
  static void refreshNotificationCount() => notifications.value++;

  static void refreshPosProducts() => posProducts.value++;
  static void refreshPosSellProductGrid() => posSellProductGrid.value++;
  static void refreshPosPriceLists() => posPriceLists.value++;
  static void refreshPosSellIndustry() => posSellIndustry.value++;
  static void refreshPosSaleOrders() => posSaleOrders.value++;
  static void refreshPosPurchaseReceipts() => posPurchaseReceipts.value++;
  static void refreshPosOverview() => posOverview.value++;

  static void patchPosSellStockLines(List<PosSellStockLineDelta> lines) {
    if (lines.isEmpty) return;
    posSellStockPatch.value = List<PosSellStockLineDelta>.from(lines);
  }

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

  static void refreshPosAfterStockChange({
    List<PosSellStockLineDelta>? sellStockLines,
    bool? reloadSellCatalog,
    String? storeId,
  }) {
    refreshPosProducts();
    refreshPosSellProductGrid();
    refreshPosSaleOrders();
    refreshPosPurchaseReceipts();
    refreshPosOverview();
    final lines = sellStockLines;
    if (lines != null && lines.isNotEmpty) {
      patchPosSellStockLines(lines);
      // ignore: discarded_futures
      _applyStockLinesToSellCatalogCache(lines, storeId: storeId);
    } else if (reloadSellCatalog == true) {
      refreshPosSellProductGrid();
    }
  }
}
