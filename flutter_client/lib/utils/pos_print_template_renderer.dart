import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import 'pos_print_template_loader.dart';
import 'pos_vietnamese_money_words.dart';

const _itemBegin = '<!--BEGIN_ITEMS-->';
const _itemEnd = '<!--END_ITEMS-->';

/// Dữ liệu mẫu để xem trước mẫu in.
Map<String, String> posPrintSampleData({String documentType = PosPrintDocumentTypes.saleInvoice}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final base = <String, String>{
    'Ten_Cua_Hang': 'SBOX POS Demo',
    'Dia_Chi_Chi_Nhanh': '123 Nguyễn Huệ, Q.1, TP.HCM',
    'Dien_Thoai_Chi_Nhanh': '0901 234 567',
    'Tieu_De_In': PosPrintDocumentTypes.all[documentType] ?? 'Hóa đơn',
    'Ma_Don_Hang': 'HD000050',
    'Ngay': '28/06/2026',
    'Gio': '14:30',
    'Khach_Hang': 'Anh Hòa Q.1',
    'SDT': '0909123456',
    'Dia_Chi_Khach_Hang': 'Q.1, TP.HCM',
    'Tong_Tien_Hang': money.format(16000000),
    'Chiet_Khau_Hoa_Don': money.format(0),
    'Tong_Cong': money.format(16000000),
    'Khach_Can_Tra': money.format(16000000),
    'Khach_Thanh_Toan': money.format(16000000),
    'Tien_Thua': money.format(0),
    'Con_Lai': money.format(0),
    'Tong_Cong_Bang_Chu': 'Mười sáu triệu đồng chẵn',
    'Hinh_Thuc_Thanh_Toan': 'Tiền mặt',
    'Nguoi_Ban': 'NV Bán hàng',
    'Ghi_Chu': '',
    'Ten_Ban': 'Bàn 05',
    'Ma_Hang': 'TS-TRA-DAO',
    'Ma_Vach': '8934567890123',
    'Ten_Hang_Hoa': 'Trà đào cam sả size L',
    'Don_Gia': money.format(45000),
    'So_Luong': '1',
    'Don_Vi_Tinh': 'ly',
  };
  if (documentType == PosPrintDocumentTypes.barcodeLabel) {
    return {
      ...base,
      'Tieu_De_In': 'TEM SẢN PHẨM',
      'Ten_Hang_Hoa': 'Giày thể thao Nam Adidas Blue',
      'Ma_Hang': 'GNA10001',
      'Ma_Vach': '8934567890123',
      'Don_Gia': money.format(350000),
      'Don_Vi_Tinh': 'Đôi',
    };
  }
  if (documentType == PosPrintDocumentTypes.kitchenLabel) {
    return {
      ...base,
      'Tieu_De_In': 'TEM BÁO BẾP',
      'Ghi_Chu': '+ Ít đá, + 50% đường',
      'So_Luong': '1',
    };
  }
  return base;
}

List<Map<String, String>> posPrintSampleLines() {
  final money = NumberFormat('#,##0', 'vi_VN');
  return [
    {
      'STT': '1',
      'Ma_Hang': 'GNA10001',
      'Ten_Hang_Hoa': 'Giày thể thao Nam Adidas Blue',
      'Don_Gia': money.format(350000),
      'So_Luong': '2',
      'Don_Vi_Tinh': 'Đôi',
      'Chiet_Khau': '0',
      'Thanh_Tien': money.format(700000),
    },
    {
      'STT': '2',
      'Ma_Hang': 'IP15PM',
      'Ten_Hang_Hoa': 'iPhone 15 Pro Max',
      'Don_Gia': money.format(28000000),
      'So_Luong': '1',
      'Don_Vi_Tinh': 'Cái',
      'Chiet_Khau': money.format(500000),
      'Thanh_Tien': money.format(27500000),
    },
  ];
}

/// Render HTML mẫu in — thay token + lặp khối dòng hàng.
String renderPosPrintTemplateHtml(
  String templateHtml, {
  required Map<String, String> data,
  required List<Map<String, String>> lineItems,
}) {
  var html = templateHtml;
  final begin = html.indexOf(_itemBegin);
  final end = html.indexOf(_itemEnd);
  if (begin >= 0 && end > begin) {
    final block = html.substring(begin + _itemBegin.length, end);
    final rendered = StringBuffer();
    for (final line in lineItems) {
      var row = block;
      for (final e in line.entries) {
        row = row.replaceAll('{${e.key}}', e.value);
      }
      for (final e in data.entries) {
        row = row.replaceAll('{${e.key}}', e.value);
      }
      rendered.write(row);
    }
    html = html.replaceRange(begin, end + _itemEnd.length, rendered.toString());
  }

  for (final e in data.entries) {
    html = html.replaceAll('{${e.key}}', e.value);
  }
  return wrapPosPrintHtmlDocument(html, paperSize: data['PaperSize'] ?? 'K80');
}

String wrapPosPrintHtmlDocument(String bodyHtml, {required String paperSize}) {
  final width = PosPrintPaperSizes.widthMm(paperSize);
  final pageCss = PosPrintPaperSizes.isThermal(paperSize)
      ? '@page { size: ${width}mm auto; margin: 2mm; } body { width: ${width}mm; margin: 0 auto; }'
      : '@page { size: $paperSize portrait; margin: 10mm; } body { max-width: ${width}mm; margin: 0 auto; }';

  return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
  $pageCss
  * { box-sizing: border-box; }
  body { font-family: Arial, sans-serif; color: #111; }
  table { border-collapse: collapse; }
  @media print { body { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
</style></head><body>$bodyHtml</body></html>
''';
}

Map<String, String> buildSaleOrderPrintData(
  PosSaleOrder order, {
  String? storeName,
  String? storeAddress,
  String? storePhone,
  String paperSize = PosPrintPaperSizes.k80,
  String? titleOverride,
}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final saleDate = order.saleDate?.toLocal() ?? order.createdAt?.toLocal() ?? DateTime.now();
  final change = (order.paidAmount - order.total).clamp(0, double.infinity);
  final due = (order.total - order.paidAmount).clamp(0, double.infinity);

  return {
    'PaperSize': paperSize,
    'Ten_Cua_Hang': storeName ?? 'Cửa hàng',
    'Dia_Chi_Chi_Nhanh': storeAddress ?? '',
    'Dien_Thoai_Chi_Nhanh': storePhone ?? '',
    'Tieu_De_In': titleOverride ??
        (order.printCount > 1
            ? 'HÓA ĐƠN BÁN HÀNG — IN LẠI'
            : 'HÓA ĐƠN BÁN HÀNG'),
    'Ma_Don_Hang': order.orderNo.isEmpty ? '—' : order.orderNo,
    'Ngay': DateFormat('dd/MM/yyyy').format(saleDate),
    'Gio': DateFormat('HH:mm').format(saleDate),
    'Khach_Hang': order.customerName ?? 'Bán cho người tiêu dùng',
    'SDT': order.deliveryPhone ?? '',
    'Dia_Chi_Khach_Hang': order.deliveryAddress ?? '',
    'Tong_Tien_Hang': money.format(order.subTotal),
    'Chiet_Khau_Hoa_Don': money.format(order.discount),
    'Tong_Cong': money.format(order.total),
    'Khach_Can_Tra': money.format(order.total),
    'Khach_Thanh_Toan': money.format(order.paidAmount),
    'Tien_Thua': money.format(change),
    'Con_Lai': money.format(due),
    'Tong_Cong_Bang_Chu': _amountInWords(order.total),
    'Hinh_Thuc_Thanh_Toan': order.paymentMethod,
    'Nguoi_Ban': order.soldBy ?? order.createdBy ?? '',
    'Ghi_Chu': order.note ?? '',
    'In_Lai': order.printCount > 1
        ? 'Bản in lại — Lần in thứ ${order.printCount} — thông báo chủ cửa hàng'
        : (order.printCount == 1 ? 'Lần in: 1' : ''),
    'Lan_In': order.printCount > 0 ? '${order.printCount}' : '',
    'Thu_Tu_Hoa_Don_Ngay': '',
    'Tong_Hoa_Don_Trong_Ngay': '',
  };
}

List<Map<String, String>> buildSaleOrderPrintLines(
  List<PosSaleOrderLine> lines, {
  bool mergeSameItems = false,
}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final src = mergeSameItems ? _mergeLines(lines) : lines;
  return List.generate(src.length, (i) {
    final l = src[i];
    var name = l.productName;
    if (l.unitName != null && l.unitName!.isNotEmpty) {
      name = '$name (${l.unitName})';
    }
    if (l.lineNote != null && l.lineNote!.isNotEmpty) {
      name = '$name — ${l.lineNote}';
    }
    return {
      'STT': '${i + 1}',
      'Ma_Hang': l.productId.length > 8 ? l.productId.substring(0, 8) : l.productId,
      'Ten_Hang_Hoa': name,
      'Don_Gia': money.format(l.unitPrice),
      'So_Luong': qtyFmt.format(l.qty),
      'Don_Vi_Tinh': l.unitName ?? '',
      'Chiet_Khau': l.discountAmount > 0 ? money.format(l.discountAmount) : '0',
      'Thanh_Tien': money.format(l.lineTotal),
    };
  });
}

List<PosSaleOrderLine> _mergeLines(List<PosSaleOrderLine> lines) {
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

String _amountInWords(double amount) => vietnameseMoneyInWords(amount.round());

String renderSaleOrderTemplate(
  String templateHtml,
  PosSaleOrder order, {
  String? storeName,
  String? storeAddress,
  String? storePhone,
  String paperSize = PosPrintPaperSizes.k80,
  bool mergeSameItems = false,
}) {
  final data = buildSaleOrderPrintData(
    order,
    storeName: storeName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    paperSize: paperSize,
  );
  final lines = buildSaleOrderPrintLines(order.lines, mergeSameItems: mergeSameItems);
  return renderPosPrintTemplateHtml(templateHtml, data: data, lineItems: lines);
}

/// Tiêu đề mặc định phiếu báo xuất kho.
String warehouseSlipDefaultTitle() =>
    PosPrintDocumentTypes.all[PosPrintDocumentTypes.stockIssue] ??
    'PHIẾU BÁO XUẤT KHO';

String renderWarehouseSlipTemplate(
  String templateHtml,
  PosSaleOrder order, {
  String? storeName,
  String? storeAddress,
  String? storePhone,
  String paperSize = PosPrintPaperSizes.k80,
  String? titleOverride,
}) {
  final title = titleOverride ?? warehouseSlipDefaultTitle();
  final data = buildSaleOrderPrintData(
    order,
    storeName: storeName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    paperSize: paperSize,
    titleOverride: title,
  );
  final lines = buildSaleOrderPrintLines(order.lines, mergeSameItems: false);
  return renderPosPrintTemplateHtml(templateHtml, data: data, lineItems: lines);
}

/// Tải mẫu in the ưu tiên [templateId] rồi mẫu mặc định theo [documentType].
Future<PosPrintTemplate?> resolvePosPrintTemplate({
  required String documentType,
  String? templateId,
}) async {
  final api = ApiService();
  if (templateId != null && templateId.isNotEmpty) {
    final res = await api.getPosPrintTemplate(templateId);
    if (res['isSuccess'] == true && res['data'] is Map) {
      return PosPrintTemplate.fromJson(res['data'] as Map<String, dynamic>);
    }
  }
  var listRes = await api.getPosPrintTemplates(documentType: documentType);
  var list = parsePosPrintTemplatesResponse(listRes);
  if (list.isEmpty) {
    list = await loadPosPrintTemplates(api, documentType);
  }
  if (list.isNotEmpty) {
    return list.where((t) => t.isDefault).firstOrNull ?? list.firstOrNull;
  }
  return null;
}

String renderSampleTemplatePreview(
  String templateHtml, {
  String documentType = PosPrintDocumentTypes.saleInvoice,
  String paperSize = PosPrintPaperSizes.k80,
}) {
  final data = posPrintSampleData(documentType: documentType);
  data['PaperSize'] = paperSize;
  return renderPosPrintTemplateHtml(
    templateHtml,
    data: data,
    lineItems: posPrintSampleLines(),
  );
}
