import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_html_print.dart';
import 'pos_print_template_loader.dart';
import 'pos_pdf_fonts.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_renderer.dart';
import 'pos_printer_transport.dart';
import 'pos_print_store_info.dart';
import 'pos_purchase_receipt_print.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_print_template_runtime.dart';
import 'pos_printer_peripheral.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Hóa đơn bán chưa in được — treo trên màn thu ngân để in lại.
class PendingSalePrintJob {
  PendingSalePrintJob({
    required this.order,
    this.errorMessage,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final PosSaleOrder order;
  final String? errorMessage;
  final DateTime createdAt;

  String get id => order.id;

  String get orderLabel =>
      order.orderNo.isEmpty ? 'Đơn vừa bán' : order.orderNo;

  String get lineSummary {
    final names = order.lines.map((l) => l.productName).take(3).join(', ');
    if (order.lines.length > 3) return '$names…';
    if (names.isEmpty) return '${order.lines.length} dòng';
    return names;
  }
}

/// Tạo PDF hóa đơn bán hàng kiểu KiotViet (khổ ngang A4, font tiếng Việt).
Future<Uint8List> buildPosSaleOrderPdfBytes({
  required String orderNo,
  required DateTime saleDate,
  String? branchName,
  String? createdBy,
  String? soldBy,
  String? customerName,
  String? salesChannel,
  String? priceListName,
  String? note,
  String paymentMethod = 'Tiền mặt',
  required double subTotal,
  required double discount,
  required double total,
  required double paidAmount,
  required double balanceDue,
  required double returnedAmount,
  required List<PosSaleOrderLine> lines,
  int copies = 1,
  bool mergeSameItems = false,
  int printCount = 0,
  int dailyOrderIndex = 0,
  double dailySalesTotal = 0,
}) async {
  final fonts = await loadPosPdfFonts();
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
  );
  final body9 = pw.TextStyle(font: fonts.regular, fontSize: 9);
  final bold9 = pw.TextStyle(font: fonts.bold, fontSize: 9);
  final bold20 = pw.TextStyle(font: fonts.bold, fontSize: 20);
  final body10 = pw.TextStyle(font: fonts.regular, fontSize: 10);
  final bold10 = pw.TextStyle(font: fonts.bold, fontSize: 10);

  final money = NumberFormat('#,##0', 'vi_VN');
  final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
  final totalQty = lines.fold<double>(0, (a, l) => a + l.qty);

  final printLines = mergeSameItems ? _mergeSaleLines(lines) : lines;
  final printQty = mergeSameItems
      ? printLines.fold<double>(0, (a, l) => a + l.qty)
      : totalQty;

  pw.Widget pageContent() => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(
              printCount > 1 ? 'HÓA ĐƠN BÁN HÀNG IN LẠI' : 'HÓA ĐƠN BÁN HÀNG',
              style: bold20,
            ),
          ),
          if (printCount > 1) ...[
            pw.SizedBox(height: 6),
            pw.Center(
              child: pw.Text(tr('*** Bản in lại — thông báo chủ cửa hàng ***'),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 11,
                  color: PdfColors.red800,
                ),
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${tr('Mã đơn: ')}${orderNo.isEmpty ? '—' : orderNo}', style: body10),
              pw.Text(tr('Ngày bán: ${dateFmt.format(saleDate.toLocal())}'), style: body10),
            ],
          ),
          pw.SizedBox(height: 6),
          if (branchName != null && branchName.isNotEmpty)
            pw.Text(tr('Chi nhánh: $branchName'), style: body10),
          if (createdBy != null && createdBy.isNotEmpty)
            pw.Text(tr('Người tạo: $createdBy'), style: body10),
          if (soldBy != null && soldBy.isNotEmpty)
            pw.Text(tr('Người bán: $soldBy'), style: body10),
          pw.Text('${tr('Khách hàng: ')}${customerName ?? 'Khách lẻ'}', style: body10),
          if (salesChannel != null && salesChannel.isNotEmpty)
            pw.Text(tr('Kênh bán: $salesChannel'), style: body10),
          if (priceListName != null && priceListName.isNotEmpty)
            pw.Text(tr('Bảng giá: $priceListName'), style: body10),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const [
              'STT',
              'Tên hàng',
              'Đơn giá',
              'SL',
              'CK',
              'Thành tiền',
            ],
            data: List.generate(printLines.length, (i) {
              final l = printLines[i];
              final unitSuffix =
                  l.unitName != null && l.unitName!.isNotEmpty ? ' (${l.unitName})' : '';
              var name = '${l.productName}$unitSuffix';
              if (l.lineNote != null && l.lineNote!.isNotEmpty) {
                name = '$name\n↳ ${l.lineNote}';
              }
              return [
                '${i + 1}',
                name,
                money.format(l.unitPrice),
                qtyFmt.format(l.qty),
                l.discountAmount > 0 ? money.format(l.discountAmount) : '—',
                money.format(l.lineTotal),
              ];
            }),
            headerStyle: bold9,
            cellStyle: body9,
            cellAlignment: pw.Alignment.centerLeft,
          ),
          pw.SizedBox(height: 10),
          pw.Text(tr('Tổng số lượng: ${qtyFmt.format(printQty)}'), style: body10),
          pw.Text(tr('Tổng tiền hàng: ${money.format(subTotal)}'), style: body10),
          pw.Text(tr('Giảm giá: ${money.format(discount)}'), style: body10),
          pw.Text(tr('Tổng cộng: ${money.format(total)}'), style: bold10),
          pw.Text(tr('Đã thanh toán: ${money.format(paidAmount)} ($paymentMethod)'), style: body10),
          pw.Text(tr('Còn lại: ${money.format(balanceDue)}'), style: body10),
          if (returnedAmount > 0)
            pw.Text(tr('Đã trả hàng: ${money.format(returnedAmount)}'), style: body10),
          if (note != null && note.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(tr('Ghi chú: $note'), style: body10),
          ],
          pw.Spacer(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              pw.Column(
                children: [
                  pw.Text(tr('Khách hàng'), style: bold10),
                  pw.SizedBox(height: 48),
                  pw.Text(tr('(Ký, họ tên)'), style: body10),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text(tr('Người bán'), style: bold10),
                  pw.SizedBox(height: 48),
                  pw.Text(tr('(Ký, họ tên)'), style: body10),
                ],
              ),
            ],
          ),
        ],
      );

  final copyCount = copies.clamp(1, 20);
  for (var c = 0; c < copyCount; c++) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (_) => pageContent(),
      ),
    );
  }

  return Uint8List.fromList(await pdf.save());
}

List<PosSaleOrderLine> _mergeSaleLines(List<PosSaleOrderLine> lines) {
  final map = <String, PosSaleOrderLine>{};
  for (final l in lines) {
    final key = '${l.productId}|${l.variantId ?? ''}|${l.unitPrice}|${l.unitName ?? ''}';
    final existing = map[key];
    if (existing == null) {
      map[key] = l;
    } else {
      map[key] = PosSaleOrderLine(
        id: existing.id,
        productId: existing.productId,
        variantId: existing.variantId,
        productName: existing.productName,
        unitName: existing.unitName,
        qty: existing.qty + l.qty,
        unitPrice: existing.unitPrice,
        discountAmount: existing.discountAmount + l.discountAmount,
        lineTotal: existing.lineTotal + l.lineTotal,
        lineNote: [existing.lineNote, l.lineNote]
            .where((n) => n != null && n.isNotEmpty)
            .join('; '),
      );
    }
  }
  return map.values.toList();
}

/// In hóa đơn bán hàng — mở dialog xem trước.
Future<PosPrintTemplate?> _resolveSalePrintTemplate(String? templateId) async {
  if (templateId != null && templateId.isNotEmpty) {
    final res = await ApiService().getPosPrintTemplate(templateId);
    if (res['isSuccess'] == true && res['data'] is Map) {
      return PosPrintTemplate.fromJson(res['data'] as Map<String, dynamic>);
    }
  }
  final list = await loadPosPrintTemplates(
    ApiService(),
    PosPrintDocumentTypes.saleInvoice,
  );
  return list.where((t) => t.isDefault).firstOrNull ?? list.firstOrNull;
}

PosThermalPrinterSettings _thermalSettingsForTemplate(
  PosThermalPrinterSettings settings,
  PosPrintTemplate? template,
) {
  if (template != null && PosPrintPaperSizes.isThermal(template.paperSize)) {
    return settings.copyWith(paperSize: template.paperSize);
  }
  return settings;
}

Future<bool> printPosSaleOrder({
  required BuildContext context,
  required PosSaleOrder order,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  bool mergeSameItems = false,
  int copies = 1,
  String? templateId,
  String? vietQrImageUrl,
  bool skipDedup = false,
  bool showFeedback = true,
  /// Sau thanh toán trên máy POS: chỉ in nhiệt/cloud, không mở dialog HTML/PDF.
  bool preferDevicePrintOnly = false,
  /// VD: «HÓA ĐƠN TẠM TÍNH» — ghi đè tiêu đề in.
  String? documentTitle,
}) async {
  final printOrder = await _resolvePrintOrder(order);
  final template = await _resolveSalePrintTemplate(templateId);

  // Luôn lấy tên/địa chỉ/SĐT cửa hàng từ thiết lập POS nếu caller không truyền.
  if (branchName == null ||
      branchName.trim().isEmpty ||
      storeAddress == null ||
      storePhone == null) {
    final store = await PosPrintStoreInfo.load();
    branchName =
        (branchName != null && branchName.trim().isNotEmpty)
            ? branchName
            : store.storeName;
    storeAddress =
        (storeAddress != null && storeAddress.trim().isNotEmpty)
            ? storeAddress
            : store.address;
    storePhone =
        (storePhone != null && storePhone.trim().isNotEmpty)
            ? storePhone
            : store.phone;
  }

  final thermal = await PosThermalPrinterSettings.load();
  if (!kIsWeb) {
    await PosPrintOrchestrator.instance.refreshConfig();
    final cloudPrinters = PosPrintOrchestrator.instance
        .resolvePrinters(PosCloudDocumentTypes.saleInvoice);

    // Ưu tiên máy in nhiệt cục bộ (Sunmi/BT/LAN) khi đã bật —
    // tránh gửi cloud "thành công" mà thiết bị POS không in ra giấy.
    if (thermal.enabled) {
      final isProvisional = (documentTitle ?? '')
          .toUpperCase()
          .contains('TẠM');
      var settings = await _prepareLocalThermalSettings(
        thermal,
        template,
        order: isProvisional ? null : printOrder,
      );
      final printed = await _tryLocalSalePrint(
        printOrder: printOrder,
        settings: settings,
        template: template,
        branchName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: mergeSameItems,
        vietQrImageUrl: vietQrImageUrl,
        copies: copies,
        showFeedback: showFeedback,
        skipDedup: skipDedup,
        documentTitle: documentTitle,
      );
      if (printed) {
        return true;
      }
      // Chỉ bỏ cloud khi không còn máy Agent — Oppo vẫn phải gửi được sang Sunmi.
      if (preferDevicePrintOnly && cloudPrinters.isEmpty) {
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Chưa in được',
            message: tr(
                'Máy in cục bộ lỗi và chưa có Print Agent. Không mở mẫu phiếu.'),
          );
        }
        return false;
      }
    }

    if (cloudPrinters.isNotEmpty) {
      if (showFeedback) {
        NotificationOverlayManager().show(
          title: 'Đang gửi lệnh in…',
          message: cloudPrinters.length == 1
              ? '→ ${cloudPrinters.first.name}'
              : '→ ${cloudPrinters.length} máy in',
          duration: const Duration(seconds: 2),
        );
      }
      final printed =
          await PosPrintOrchestrator.instance.dispatchSaleOrder(
        order: printOrder,
        copies: copies,
        referenceNo: printOrder.orderNo.isEmpty ? null : printOrder.orderNo,
        referenceId: printOrder.id,
        showFeedback: showFeedback,
        successTitle: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
        skipDedup: skipDedup,
        storeName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: mergeSameItems,
        documentTitle: documentTitle,
        buildEscPos: (printer) async {
          var settings = toThermalSettings(printer);
          settings = _thermalSettingsForTemplate(settings, template);
          final isProvisional = (documentTitle ?? '')
              .toUpperCase()
              .contains('TẠM');
          final kick = !isProvisional &&
              PosPrinterPeripheral.shouldOpenDrawerForOrder(
                settings,
                printOrder,
              );
          settings = settings.copyWith(openCashDrawer: kick);
          return PosThermalPrinterService.buildSaleOrderEscPosBytes(
            printOrder,
            settings: settings,
            storeName: branchName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            mergeSameItems: mergeSameItems,
            vietQrImageUrl: vietQrImageUrl,
            slipTitle: documentTitle,
          );
        },
      );
      if (printed) {
        return true;
      }
      if (preferDevicePrintOnly) {
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'In thất bại',
            message: tr('Không gửi được máy in — phiếu treo, không mở mẫu.'),
          );
        }
        return false;
      }
    }

    if (preferDevicePrintOnly) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Chưa in được',
          message: tr(
              'Chưa cấu hình máy in nhiệt hoặc Print Agent. Vào Thiết lập in — không mở mẫu phiếu.'),
        );
      }
      return false;
    }
  }

  final saleDate =
      printOrder.saleDate?.toLocal() ?? printOrder.createdAt?.toLocal() ?? DateTime.now();

  // Fallback HTML/PDF chỉ khi caller cho phép (không dùng trên POS cảm ứng).
  if (template != null && template.htmlContent.trim().isNotEmpty) {
    final html = renderSaleOrderTemplate(
      template.htmlContent,
      printOrder,
      storeName: branchName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      paperSize: template.paperSize,
      mergeSameItems: mergeSameItems,
    );
    await showPosHtmlPrintDialog(
      context,
      title: 'Hóa đơn ${printOrder.orderNo.isEmpty ? 'tạm' : printOrder.orderNo}'
          '${printOrder.isReprint ? ' (IN LẠI)' : ''}',
      htmlDocument: html,
      initialCopies: copies,
    );
    return true;
  }

  await showPosPurchaseReceiptPrintDialog(
    context,
    title: 'Hóa đơn ${printOrder.orderNo.isEmpty ? 'tạm' : printOrder.orderNo}'
        '${printOrder.isReprint ? ' (IN LẠI)' : ''}',
    buildPdf: (c) => buildPosSaleOrderPdfBytes(
      orderNo: printOrder.orderNo,
      saleDate: saleDate,
      branchName: branchName,
      createdBy: printOrder.createdBy,
      soldBy: printOrder.soldBy,
      customerName: printOrder.customerName,
      salesChannel: printOrder.salesChannel,
      priceListName: printOrder.priceListName,
      note: printOrder.note,
      paymentMethod: printOrder.paymentMethod,
      subTotal: printOrder.subTotal,
      discount: printOrder.discount,
      total: printOrder.total,
      paidAmount: printOrder.paidAmount,
      balanceDue: printOrder.balanceDue,
      returnedAmount: printOrder.returnedAmount,
      lines: printOrder.lines,
      copies: c,
      mergeSameItems: mergeSameItems,
      printCount: printOrder.printCount,
      dailyOrderIndex: printOrder.dailyOrderIndex,
      dailySalesTotal: printOrder.dailySalesTotal,
    ),
  );
  return true;
}

Future<PosThermalPrinterSettings> _prepareLocalThermalSettings(
  PosThermalPrinterSettings thermal,
  PosPrintTemplate? template, {
  PosSaleOrder? order,
}) async {
  var settings = _thermalSettingsForTemplate(thermal, template);
  settings = await PosPrinterTransport.prepareLocalSettings(settings);
  if (order != null) {
    final kick = PosPrinterPeripheral.shouldOpenDrawerForOrder(settings, order);
    settings = settings.copyWith(openCashDrawer: kick);
  } else {
    settings = settings.copyWith(openCashDrawer: false);
  }
  return settings;
}

Future<bool> _tryLocalSalePrint({
  required PosSaleOrder printOrder,
  required PosThermalPrinterSettings settings,
  PosPrintTemplate? template,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  required bool mergeSameItems,
  String? vietQrImageUrl,
  required int copies,
  required bool showFeedback,
  required bool skipDedup,
  String? documentTitle,
}) async {
  // Sunmi: ưu tiên mẫu V2 (preview = in thực) rồi fallback layout cứng.
  if (settings.connectionType == PosThermalConnectionType.sunmi ||
      await PosPrinterTransport.isSunmiDevice()) {
    try {
      final v2 = PosPrintTemplateRuntime.parseTemplate(template);
      if (v2 != null) {
        final output = PosPrintTemplateRuntime.compileSaleOrder(
          template: v2,
          order: printOrder,
          storeName: branchName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          mergeSameItems: mergeSameItems,
          titleOverride: documentTitle,
          vietQrImageUrl: vietQrImageUrl,
        );
        final sunmiOk = await PosPrintTemplateRuntime.printCompiledSunmi(
          output: output,
          settings: settings.copyWith(
            connectionType: PosThermalConnectionType.sunmi,
            printerBrand: PosThermalPrinterBrand.sunmi,
          ),
          copies: copies,
        );
        if (sunmiOk) {
          await PosPrinterPeripheral.afterSunmiNativePrint(
            settings,
            openDrawer: settings.openCashDrawer,
          );
          if (showFeedback) {
            NotificationOverlayManager().showSuccess(
              title: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
              message: tr('Máy in Sunmi (mẫu V2)'),
            );
          }
          return true;
        }
      }
      final sunmiOk = await PosSunmiNativePrint.printSaleOrder(
        printOrder,
        settings: settings.copyWith(
          connectionType: PosThermalConnectionType.sunmi,
          printerBrand: PosThermalPrinterBrand.sunmi,
        ),
        storeName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: mergeSameItems,
        copies: copies,
        documentTitle: documentTitle,
      );
      if (sunmiOk) {
        await PosPrinterPeripheral.afterSunmiNativePrint(
          settings,
          openDrawer: settings.openCashDrawer,
        );
        if (showFeedback) {
          NotificationOverlayManager().showSuccess(
            title: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
            message: tr('Máy in Sunmi'),
          );
        }
        return true;
      }
    } catch (e) {
      debugPrint('Sunmi native sale print failed: $e');
    }
  }

  Future<bool> attempt(PosThermalPrinterSettings s, {String? qr}) async {
    final v2 = PosPrintTemplateRuntime.parseTemplate(template);
    if (v2 != null) {
      final output = PosPrintTemplateRuntime.compileSaleOrder(
        template: v2,
        order: printOrder,
        storeName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: mergeSameItems,
        titleOverride: documentTitle,
        vietQrImageUrl: qr ?? vietQrImageUrl,
      );
      final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
        output: output,
        settings: s,
      );
      return PosPrintOrchestrator.instance.dispatchLocalEscPos(
        bytes: bytes,
        copies: copies,
        showFeedback: false,
        successTitle: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
        settingsOverride: s,
        documentType: PosPrintDocumentTypes.saleInvoice,
        skipDedup: skipDedup,
      );
    }
    final bytes = await PosThermalPrinterService.buildSaleOrderEscPosBytes(
      printOrder,
      settings: s,
      storeName: branchName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      mergeSameItems: mergeSameItems,
      vietQrImageUrl: qr,
      slipTitle: documentTitle,
    );
    return PosPrintOrchestrator.instance.dispatchLocalEscPos(
      bytes: bytes,
      copies: copies,
      showFeedback: false,
      successTitle: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
      settingsOverride: s,
      documentType: PosPrintDocumentTypes.saleInvoice,
      referenceId: printOrder.id,
      referenceNo: printOrder.orderNo.isEmpty ? null : printOrder.orderNo,
      skipDedup: skipDedup,
    );
  }

  try {
    if (await attempt(settings, qr: vietQrImageUrl)) {
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
          message: tr('Máy in cục bộ'),
        );
      }
      return true;
    }
  } catch (e) {
    debugPrint('Local sale print (primary) failed: $e');
  }

  // Fallback chuỗi chế độ chữ: image lỗi → tcvn3 → cp1258 → utf8 (giữ dấu).
  // Không nhảy thẳng ASCII/bỏ dấu.
  if (settings.resolvedTextMode == PosThermalTextMode.image ||
      (vietQrImageUrl != null && vietQrImageUrl.isNotEmpty)) {
    const fallbackModes = [
      PosThermalTextMode.tcvn3,
      PosThermalTextMode.cp1258,
      PosThermalTextMode.utf8,
    ];
    for (final mode in fallbackModes) {
      if (mode == settings.resolvedTextMode) continue;
      final fallback = settings.copyWith(textMode: mode);
      try {
        if (await attempt(fallback, qr: null)) {
          if (showFeedback) {
            NotificationOverlayManager().showSuccess(
              title: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
              message: tr('Máy in cục bộ (${mode.label})'),
            );
          }
          return true;
        }
      } catch (e) {
        debugPrint('Local sale print ($mode) fallback failed: $e');
      }
    }
  }

  if (showFeedback) {
    NotificationOverlayManager().showError(
      title: 'In thất bại',
      message: tr('Không in được hóa đơn trên máy in cục bộ'),
    );
  }
  return false;
}

Future<PosSaleOrder> _resolvePrintOrder(PosSaleOrder order) async {
  if (order.id.isEmpty || order.status != 'Completed') return order;
  try {
    final res = await ApiService().recordPosSalePrint(order.id);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final fromApi = PosSaleOrder.fromJson(data);
      final count = fromApi.printCount > 0
          ? fromApi.printCount
          : order.printCount + 1;
      if (fromApi.lines.isEmpty && order.lines.isNotEmpty) {
        return order.copyWithPrintContext(
          printCount: count,
          dailyOrderIndex: fromApi.dailyOrderIndex,
          dailySalesTotal: fromApi.dailySalesTotal,
        );
      }
      return fromApi.printCount > 0
          ? fromApi
          : fromApi.copyWithPrintContext(printCount: count);
    }
    debugPrint('recordPosSalePrint failed: ${res['message']}');
  } catch (e) {
    debugPrint('recordPosSalePrint error: $e');
  }
  return order.copyWithPrintContext(printCount: order.printCount + 1);
}
