import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import 'pos_print_template_compiler.dart';
import 'pos_print_template_loader.dart';
import 'pos_print_template_renderer.dart';
import 'pos_print_template_v2_codec.dart';
import 'pos_print_template_v2_presets.dart';
import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';

/// Runtime — tải, biên dịch và in mẫu V2.
abstract final class PosPrintTemplateRuntime {
  static PosPrintTemplateV2? parseTemplate(PosPrintTemplate? template) {
    if (template == null) return null;
    return PosPrintTemplateV2Codec.tryParse(template.htmlContent);
  }

  static PosPrintTemplateV2 resolveOrPreset({
    PosPrintTemplate? template,
    required String documentType,
    required String paperSize,
    required String printerProfile,
  }) {
    final parsed = parseTemplate(template);
    if (parsed != null) return parsed;
    return PosPrintTemplateV2Presets.build(
      documentType: documentType,
      paperSize: paperSize,
      printerProfile: printerProfile,
    );
  }

  static Future<PosPrintTemplate?> loadDefaultTemplate(
    ApiService api,
    String documentType,
  ) async {
    final list = await loadPosPrintTemplates(api, documentType);
    for (final t in list) {
      if (t.isDefault) return t;
    }
    return list.isEmpty ? null : list.first;
  }

  static PosPrintCompiledOutput compileSaleOrder({
    required PosPrintTemplateV2 template,
    required PosSaleOrder order,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? titleOverride,
    String? vietQrImageUrl,
  }) {
    final lines = mergeSameItems ? _mergeLines(order.lines) : order.lines;
    final data = buildSaleOrderPrintData(
      order,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      paperSize: template.paperSize,
      titleOverride: titleOverride,
    );
    final items = buildSaleOrderPrintLines(lines);
    return PosPrintTemplateCompiler.compile(
      template: template,
      data: data,
      lineItems: items,
      vietQrImageUrl: vietQrImageUrl,
    );
  }

  static PosPrintCompiledOutput compileKitchenSlip({
    required PosPrintTemplateV2 template,
    required String tableName,
    required bool isCancel,
    required List<({String name, String qty, String? unit, String? note})> lines,
    required String senderName,
    required String orderNo,
    required DateTime sentAt,
  }) {
    final data = {
      'Ten_Ban': tableName.trim().isEmpty ? 'Bàn' : tableName.trim(),
      'Ma_Don_Hang': orderNo.isEmpty ? '-' : orderNo,
      'Nguoi_Ban': senderName,
      'Ngay': DateFormat('dd/MM/yyyy').format(sentAt),
      'Gio': DateFormat('HH:mm').format(sentAt),
      'Tieu_De_In': isCancel ? 'PHIẾU HỦY BẾP' : 'PHIẾU CHẾ BIẾN',
    };
    final items = lines
        .map((l) => {
              'Ten_Hang_Hoa': l.name,
              'So_Luong': l.qty,
              'Don_Vi_Tinh': l.unit ?? '',
              'Ghi_Chu': l.note ?? '',
            })
        .toList();
    return PosPrintTemplateCompiler.compile(
      template: template,
      data: data,
      lineItems: items,
      kitchenLines: items,
    );
  }

  static Future<bool> printCompiledSunmi({
    required PosPrintCompiledOutput output,
    required PosThermalPrinterSettings settings,
    int copies = 1,
    bool kitchenFeed = false,
  }) =>
      PosSunmiNativePrint.printCompiled(
        output: output,
        settings: settings,
        copies: copies,
        kitchenFeed: kitchenFeed,
      );

  static Future<List<int>> buildCompiledEscPosBytes({
    required PosPrintCompiledOutput output,
    required PosThermalPrinterSettings settings,
  }) =>
      PosThermalPrinterService.buildCompiledEscPosBytes(
        output,
        settings: settings,
      );

  static List<PosSaleOrderLine> _mergeLines(List<PosSaleOrderLine> lines) {
    final map = <String, PosSaleOrderLine>{};
    for (final l in lines) {
      final key =
          '${l.productId}|${l.variantId}|${l.unitName}|${l.unitPrice}|${l.lineNote}';
      final hit = map[key];
      if (hit == null) {
        map[key] = l;
      } else {
        map[key] = PosSaleOrderLine(
          id: hit.id,
          productId: hit.productId,
          productName: hit.productName,
          variantId: hit.variantId,
          unitName: hit.unitName,
          qty: hit.qty + l.qty,
          unitPrice: hit.unitPrice,
          discountAmount: hit.discountAmount + l.discountAmount,
          lineTotal: hit.lineTotal + l.lineTotal,
          lineNote: hit.lineNote,
        );
      }
    }
    return map.values.toList();
  }
}
