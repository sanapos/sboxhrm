import 'package:flutter/foundation.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import '../models/pos_sale_order.dart';
import 'pos_thermal_printer_settings.dart';

/// Lệnh ngoại vi máy in nhiệt: bip + mở két (ESC/POS / Sunmi).
abstract final class PosPrinterPeripheral {
  /// ESC B n t — bip (Epson / nhiều máy ESC/POS Trung Quốc).
  static List<int> beepEscPos({int count = 1, int durationUnits = 3}) => [
        0x1B,
        0x42,
        count.clamp(1, 9),
        durationUnits.clamp(1, 9),
      ];

  /// ESC p m t1 t2 — xung mở két (pin 2).
  static List<int> openDrawerEscPos() => [0x1B, 0x70, 0x00, 0x19, 0xFA];

  static bool isCashPaymentMethod(String? method) {
    final m = (method ?? '').trim().toLowerCase();
    if (m.isEmpty) return true;
    return m.contains('tiền mặt') ||
        m.contains('tien mat') ||
        m == 'cash' ||
        m.contains('cash');
  }

  /// Có kick két cho job in này không (theo setting + tiền mặt).
  static bool shouldOpenDrawer(
    PosThermalPrinterSettings settings, {
    String? paymentMethod,
    bool isSaleInvoice = true,
  }) {
    if (!settings.openCashDrawer) return false;
    if (!isSaleInvoice) return false;
    if (!settings.openDrawerCashOnly) return true;
    return isCashPaymentMethod(paymentMethod);
  }

  static bool shouldOpenDrawerForOrder(
    PosThermalPrinterSettings settings,
    PosSaleOrder order,
  ) =>
      shouldOpenDrawer(
        settings,
        paymentMethod: order.paymentMethod,
        isSaleInvoice: true,
      );

  /// Gắn bip / mở két vào cuối payload ESC/POS (sau feed+cut).
  static void appendEscPosTrailing(
    List<int> bytes,
    PosThermalPrinterSettings settings, {
    required bool openDrawer,
  }) {
    if (settings.beepOnPrint) {
      bytes.addAll(beepEscPos());
    }
    if (openDrawer) {
      bytes.addAll(openDrawerEscPos());
    }
  }

  /// Sau in native Sunmi: bip (ESC) + mở két API.
  static Future<void> afterSunmiNativePrint(
    PosThermalPrinterSettings settings, {
    required bool openDrawer,
  }) async {
    if (kIsWeb) return;
    if (settings.beepOnPrint) {
      try {
        await SunmiPrinter.printEscPos(beepEscPos());
      } catch (e) {
        debugPrint('Sunmi beep: $e');
      }
    }
    if (openDrawer) {
      try {
        await SunmiDrawer.openDrawer();
      } catch (e) {
        debugPrint('SunmiDrawer.openDrawer: $e');
        try {
          await SunmiPrinter.printEscPos(openDrawerEscPos());
        } catch (e2) {
          debugPrint('Sunmi ESC p drawer fallback: $e2');
        }
      }
    }
  }
}
