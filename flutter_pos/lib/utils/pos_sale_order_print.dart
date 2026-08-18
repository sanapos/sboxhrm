import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_html_print.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_role.dart';
import 'pos_print_template_loader.dart';
import 'pos_pdf_fonts.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_renderer.dart';
import 'pos_topping_format.dart';
import 'pos_printer_transport.dart';
import 'pos_print_store_info.dart';
import 'pos_purchase_receipt_print.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_print_template_runtime.dart';
import 'pos_printer_peripheral.dart';
import 'pos_vietqr_helper.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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
              final toppingNote = posToppingNoteFromSaleLine(
                l,
                withPrice: true,
                money: money,
              );
              if (toppingNote.isNotEmpty) {
                name = '$name\n$toppingNote';
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
    final topKey = l.toppings.map((t) => '${t.id}x${t.qty}').join(',');
    final key =
        '${l.productId}|${l.variantId ?? ''}|${l.unitPrice}|${l.unitName ?? ''}|${l.lineNote ?? ''}|$topKey';
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
        lineNote: existing.lineNote,
        toppings: existing.toppings,
      );
    }
  }
  return map.values.toList();
}

/// In hóa đơn bán hàng — mở dialog xem trước.
Future<PosPrintTemplate?> _resolveSalePrintTemplate(
  String? templateId, {
  String documentType = PosPrintDocumentTypes.saleInvoice,
}) async {
  // Chính sách cửa hàng: ưu tiên mẫu IsDefault của store (không lệch theo máy).
  var list = await loadPosPrintTemplates(ApiService(), documentType);
  // Phiếu trả: nếu chưa seed/gán mẫu riêng → dùng mẫu hóa đơn gọn.
  if (list.isEmpty && documentType == PosPrintDocumentTypes.saleReturn) {
    list = await loadPosPrintTemplates(
      ApiService(),
      PosPrintDocumentTypes.saleInvoice,
    );
  }
  if (list.isEmpty) return null;
  final storeDefault = list.where((t) => t.isDefault).firstOrNull ?? list.first;
  if (templateId != null && templateId.isNotEmpty) {
    final hit = list.where((t) => t.id == templateId).firstOrNull;
    if (hit != null && hit.id == storeDefault.id) return hit;
  }
  return storeDefault;
}

PosThermalPrinterSettings _thermalSettingsForTemplate(
  PosThermalPrinterSettings settings,
  PosPrintTemplate? template,
) {
  if (template == null) return settings;
  final ps = template.paperSize;
  // Luôn theo khổ mẫu: K80 không bị in hẹp kiểu K58.
  if (ps == PosPrintPaperSizes.k80) {
    return settings.copyWith(paperSize: 'K80');
  }
  if (ps == PosPrintPaperSizes.k58 && settings.paperWidthMm > 58) {
    // Giữ khổ máy thật (80mm) — không thu hẹp.
    return settings;
  }
  if (PosPrintPaperSizes.isThermal(ps)) {
    return settings.copyWith(paperSize: ps);
  }
  return settings;
}

/// Cloud / Agent: cùng mẫu V2 như in nội bộ A6 (tạm tính + thanh toán).
Future<List<int>> _buildSaleEscPosMatchingLocal({
  required PosSaleOrder printOrder,
  required PosThermalPrinterSettings settings,
  PosPrintTemplate? template,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  required bool mergeSameItems,
  String? vietQrImageUrl,
  String? documentTitle,
  String documentType = PosPrintDocumentTypes.saleInvoice,
  double vatAmount = 0,
}) async {
  // Xprinter/Zywell qua Agent: luôn in ảnh — khớp A6 + tránh Agent vẽ layout thô.
  var s = settings;
  if (s.printerBrand != PosThermalPrinterBrand.sunmi &&
      s.printerBrand != PosThermalPrinterBrand.epson &&
      s.resolvedTextMode != PosThermalTextMode.image) {
    s = s.copyWith(textMode: PosThermalTextMode.image);
  }

  // Cùng preset profile như A6 local EscPos (attempt) — không zywell riêng.
  final paper = template?.paperSize ??
      (s.paperWidthMm <= 58 ? PosPrintPaperSizes.k58 : PosPrintPaperSizes.k80);
  final v2 = PosPrintTemplateRuntime.resolveOrPreset(
    template: template,
    documentType: documentType,
    paperSize: paper,
    printerProfile: s.paperWidthMm <= 58
        ? PosPrintPrinterProfiles.sunmiK58
        : PosPrintPrinterProfiles.sunmiK80,
  );
  if (v2.blocks.isNotEmpty) {
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
    return PosPrintTemplateRuntime.buildCompiledEscPosBytes(
      output: output,
      settings: s,
    );
  }
  return PosThermalPrinterService.buildSaleOrderEscPosBytes(
    printOrder,
    settings: s,
    storeName: branchName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    mergeSameItems: mergeSameItems,
    vietQrImageUrl: vietQrImageUrl,
    slipTitle: documentTitle,
    vatAmount: vatAmount,
  );
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
  /// Mặc định: chỉ mở két khi in lần đầu (không phải in lại).
  bool? openCashDrawer,
  /// VD: «HÓA ĐƠN TẠM TÍNH» / «PHIẾU TRẢ HÀNG» — ghi đè tiêu đề in.
  String? documentTitle,
  /// Loại mẫu: SaleInvoice (mặc định) hoặc SaleReturn.
  String documentType = PosPrintDocumentTypes.saleInvoice,
  /// Thuế VAT in trên bill (trước Tổng cộng). Null → lấy từ [order.vatAmount].
  double? vatAmount,
  bool? vatIncludedInPrice,
  double vatRate = 0,
  /// In lại chọn máy cửa hàng / Agent.
  String? overridePrinterId,
  PosStorePrinter? overridePrinter,
  PosPrintHangCallback? onCloudHang,
}) async {
  final printOrder = await _resolvePrintOrder(order);
  // Tự gắn VietQR khi bật «In mã VietQR» — kể cả in từ danh sách đơn (caller quên truyền URL).
  var effectiveVietQr = vietQrImageUrl;
  if (effectiveVietQr == null || effectiveVietQr.isEmpty) {
    if (documentType != PosPrintDocumentTypes.saleReturn) {
      effectiveVietQr =
          await PosVietQrHelper.resolvePrintImageUrlForOrder(printOrder);
    }
  }
  final template = await _resolveSalePrintTemplate(
    templateId,
    documentType: documentType,
  );
  final effectiveVat = vatAmount ?? printOrder.vatAmount;
  // VAT > 0 = chế độ cộng thêm; = 0 giữ flag caller (giá đã gồm / không thuế).
  final effectiveIncluded =
      vatIncludedInPrice ?? (effectiveVat <= 0);

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

  final hasOverride = overridePrinter != null ||
      (overridePrinterId ?? '').trim().isNotEmpty;

  // In lại chọn máy: bỏ máy nội bộ mặc định — gửi đúng máy đã chọn (cloud/Agent).
  if (hasOverride) {
    await PosPrintOrchestrator.instance.refreshConfig(force: true);
    PosStorePrinter? target = overridePrinter;
    if (target == null) {
      final want = overridePrinterId!.trim().toLowerCase();
      target = PosPrintOrchestrator.instance.printers
          .where((p) => p.id.toLowerCase() == want)
          .firstOrNull;
    }
    if (target == null) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không tìm thấy máy in',
          message: tr('Chọn lại máy in cửa hàng'),
        );
      }
      return false;
    }
    return PosPrintOrchestrator.instance.dispatchSaleOrder(
      order: printOrder,
      copies: copies,
      referenceNo: printOrder.orderNo.isEmpty ? null : printOrder.orderNo,
      referenceId: printOrder.id,
      showFeedback: showFeedback,
      successTitle: 'In lại hóa đơn',
      skipDedup: true,
      storeName: branchName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      mergeSameItems: mergeSameItems,
      documentTitle: documentTitle,
      overridePrinter: target,
      buildEscPos: (printer) async {
        var settings = toThermalSettings(printer);
        settings = _thermalSettingsForTemplate(settings, template);
        final isProvisional =
            (documentTitle ?? '').toUpperCase().contains('TẠM');
        final allowKick = openCashDrawer ?? !printOrder.isReprint;
        final kick = !isProvisional &&
            allowKick &&
            PosPrinterPeripheral.shouldOpenDrawerForOrder(
              settings,
              printOrder,
            );
        settings = settings.copyWith(openCashDrawer: kick);
        return _buildSaleEscPosMatchingLocal(
          printOrder: printOrder,
          settings: settings,
          template: template,
          branchName: branchName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          mergeSameItems: mergeSameItems,
          vietQrImageUrl: effectiveVietQr,
          documentTitle: documentTitle,
          documentType: documentType,
          vatAmount: effectiveVat,
        );
      },
    );
  }

  final thermal = await PosThermalPrinterSettings.load();
  await PosPrintOrchestrator.instance.refreshConfig();
  final cloudPrinters = PosPrintOrchestrator.instance
      .resolvePrinters(PosCloudDocumentTypes.saleInvoice);

  // App: chỉ in local khi ĐANG là Print Agent (A6). A7/Oppo có profile LAN/USB
  // «ảo» khớp tên → thử local fail/treo → phiếu chờ, không gửi Agent.
  final isAgentDevice =
      !kIsWeb && await PosPrintRole.isPrintAgentDevice();
  if (!kIsWeb && isAgentDevice) {
    final saleLocals = await PosLocalPrintersStore.instance
        .forRoleOnDevice(PosLocalPrinterRoles.saleInvoice);
    final thermalCandidates = <PosThermalPrinterSettings>[
      for (final p in saleLocals.where((p) => !p.isLabel)) p.toThermalSettings(),
    ];
    if (thermalCandidates.isEmpty &&
        thermal.enabled &&
        PosLocalPrintersStore.isOnDeviceDirectPort(thermal.connectionType)) {
      thermalCandidates.add(thermal);
    }

    if (thermalCandidates.isNotEmpty) {
      // A6 Sunmi: ưu tiên in native trước USB/LAN — tránh USB «OK» giả rồi bỏ Sunmi.
      if (await PosPrinterTransport.isSunmiDevice()) {
        thermalCandidates.sort((a, b) {
          final aS =
              a.connectionType == PosThermalConnectionType.sunmi ? 0 : 1;
          final bS =
              b.connectionType == PosThermalConnectionType.sunmi ? 0 : 1;
          return aS.compareTo(bS);
        });
      }
      final isProvisional =
          (documentTitle ?? '').toUpperCase().contains('TẠM');
      var anyOk = false;
      for (var i = 0; i < thermalCandidates.length; i++) {
        final settings = await _prepareLocalThermalSettings(
          thermalCandidates[i],
          template,
          order: isProvisional ? null : printOrder,
          allowOpenCashDrawer: openCashDrawer ?? !printOrder.isReprint,
        );
        final printed = await _tryLocalSalePrint(
          printOrder: printOrder,
          settings: settings,
          template: template,
          branchName: branchName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          mergeSameItems: mergeSameItems,
          vietQrImageUrl: effectiveVietQr,
          copies: copies,
          // Chỉ báo lỗi/thành công ở máy cuối hoặc khi đã có kết quả gộp.
          showFeedback: false,
          skipDedup: skipDedup || i > 0,
          documentTitle: documentTitle,
          documentType: documentType,
        );
        if (printed) {
          // Chỉ 1 máy nội bộ — tránh 2 bill khi Sunmi + USB cùng role Hóa đơn.
          anyOk = true;
          break;
        }
      }
      if (anyOk) {
        if (showFeedback) {
          NotificationOverlayManager().showSuccess(
            title: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
            message: tr('Máy in cục bộ'),
          );
        }
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
  }

  // Cloud → Print Agent (app + web). Web bán hàng dùng đường này để giống app.
  if (cloudPrinters.isNotEmpty) {
    // Không toast «Đang gửi…» — orchestrator đã báo 1 dòng «Đã gửi lệnh in».
    final printed = await PosPrintOrchestrator.instance.dispatchSaleOrder(
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
      overridePrinterId: overridePrinterId,
      overridePrinter: overridePrinter,
      onHang: onCloudHang,
      buildEscPos: (printer) async {
        var settings = toThermalSettings(printer);
        settings = _thermalSettingsForTemplate(settings, template);
        final isProvisional =
            (documentTitle ?? '').toUpperCase().contains('TẠM');
        final allowKick = openCashDrawer ?? !printOrder.isReprint;
        final kick = !isProvisional &&
            allowKick &&
            PosPrinterPeripheral.shouldOpenDrawerForOrder(
              settings,
              printOrder,
            );
        settings = settings.copyWith(openCashDrawer: kick);
        return _buildSaleEscPosMatchingLocal(
          printOrder: printOrder,
          settings: settings,
          template: template,
          branchName: branchName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          mergeSameItems: mergeSameItems,
          vietQrImageUrl: effectiveVietQr,
          documentTitle: documentTitle,
          documentType: documentType,
          vatAmount: effectiveVat,
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
          message: tr(
              'Không gửi được máy in / Print Agent offline — phiếu treo, không mở mẫu.'),
        );
      }
      return false;
    }
  }

  // Fallback HTML/PDF: chỉ khi caller cho phép VÀ không phải POS cảm ứng (Android/iOS).
  // Thanh toán không máy in → không mở hộp thoại in hệ thống.
  if (preferDevicePrintOnly || !kIsWeb) {
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'Chưa in được',
        message: tr(kIsWeb
            ? 'Chưa cấu hình máy in cửa hàng hoặc Print Agent (Android) chưa online. Không mở mẫu phiếu.'
            : 'Chưa cấu hình máy in nhiệt hoặc Print Agent. Vào Thiết lập in — không mở hộp thoại in hệ thống.'),
      );
    }
    return false;
  }

  final saleDate =
      printOrder.saleDate?.toLocal() ?? printOrder.createdAt?.toLocal() ?? DateTime.now();

  // Fallback HTML/PDF chỉ trên web khi caller cho phép.
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
  bool allowOpenCashDrawer = true,
}) async {
  var settings = _thermalSettingsForTemplate(thermal, template);
  settings = await PosPrinterTransport.prepareLocalSettings(settings);
  if (order != null && allowOpenCashDrawer && !order.isReprint) {
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
  String documentType = PosPrintDocumentTypes.saleInvoice,
  double vatAmount = 0,
  bool vatIncludedInPrice = true,
  double vatRate = 0,
}) async {
  // Sunmi: ưu tiên mẫu V2 khi không có VAT cộng thêm.
  // Có VAT > 0 → layout native (V2 hiện chưa có token VAT).
  // Chỉ native khi connectionType = sunmi — không ép máy USB/BT/LAN trên thiết bị Sunmi.
  if (settings.connectionType == PosThermalConnectionType.sunmi) {
    try {
      // HTML legacy không parse được — dùng preset V2 (4 cột), không in HTML 1 x giá.
      final v2 = PosPrintTemplateRuntime.resolveOrPreset(
        template: template,
        documentType: documentType,
        paperSize: template?.paperSize ?? PosPrintPaperSizes.k80,
        printerProfile: settings.paperWidthMm <= 58
            ? PosPrintPrinterProfiles.sunmiK58
            : PosPrintPrinterProfiles.sunmiK80,
      );
      debugPrint(
        'SALE PRINT local sunmi parsed=${PosPrintTemplateRuntime.parseTemplate(template) != null} '
        'preset=${v2.blocks.length}blks vat=$vatAmount '
        'tpl=${template?.id ?? "-"} paper=${template?.paperSize ?? "-"}',
      );
      if (vatAmount <= 0) {
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
    final v2 = PosPrintTemplateRuntime.resolveOrPreset(
      template: template,
      documentType: documentType,
      paperSize: template?.paperSize ?? PosPrintPaperSizes.k80,
      printerProfile: s.paperWidthMm <= 58
          ? PosPrintPrinterProfiles.sunmiK58
          : PosPrintPrinterProfiles.sunmiK80,
    );
    if (v2.blocks.isNotEmpty) {
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
        documentType: documentType,
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
      documentType: documentType,
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
  // Giữ VietQR nếu có; chỉ bỏ QR khi mọi mode kèm QR đều thất bại.
  if (settings.resolvedTextMode == PosThermalTextMode.image ||
      (vietQrImageUrl != null && vietQrImageUrl.isNotEmpty)) {
    const fallbackModes = [
      PosThermalTextMode.tcvn3,
      PosThermalTextMode.cp1258,
      PosThermalTextMode.utf8,
    ];
    for (final keepQr in [true, false]) {
      if (keepQr && (vietQrImageUrl == null || vietQrImageUrl.isEmpty)) {
        continue;
      }
      for (final mode in fallbackModes) {
        if (mode == settings.resolvedTextMode) continue;
        final fallback = settings.copyWith(textMode: mode);
        try {
          if (await attempt(
            fallback,
            qr: keepQr ? vietQrImageUrl : null,
          )) {
            if (showFeedback) {
              NotificationOverlayManager().showSuccess(
                title: printOrder.isReprint ? 'In lại hóa đơn' : 'In hóa đơn',
                message: tr('Máy in cục bộ (${mode.label})'),
              );
            }
            return true;
          }
        } catch (e) {
          debugPrint('Local sale print ($mode keepQr=$keepQr) fallback failed: $e');
        }
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

/// In phiếu trả hàng (mẫu SaleReturn gọn) — không ghi đếm lần in hóa đơn gốc.
Future<bool> printPosSaleReturn({
  required BuildContext context,
  required PosSaleOrder sourceOrder,
  required List<PosSaleOrderLine> returnLines,
  required double refundTotal,
  String? note,
  String? refundPaymentMethod,
}) async {
  if (returnLines.isEmpty || refundTotal <= 0) return false;
  final slip = PosSaleOrder(
    id: '',
    orderNo: sourceOrder.orderNo,
    status: 'Return',
    subTotal: refundTotal,
    discount: 0,
    total: refundTotal,
    paidAmount: refundTotal,
    paymentMethod: refundPaymentMethod ?? sourceOrder.paymentMethod,
    customerName: sourceOrder.customerName,
    customerPhone: sourceOrder.customerPhone ?? sourceOrder.deliveryPhone,
    note: note,
    saleDate: DateTime.now(),
    soldBy: sourceOrder.soldBy,
    createdBy: sourceOrder.createdBy,
    lines: returnLines,
    serviceResourceName: sourceOrder.serviceResourceName,
    serviceAreaName: sourceOrder.serviceAreaName,
  );
  return printPosSaleOrder(
    context: context,
    order: slip,
    documentTitle: 'PHIẾU TRẢ HÀNG',
    documentType: PosPrintDocumentTypes.saleReturn,
    preferDevicePrintOnly: true,
    openCashDrawer: false,
    mergeSameItems: false,
    showFeedback: true,
    skipDedup: true,
  );
}
