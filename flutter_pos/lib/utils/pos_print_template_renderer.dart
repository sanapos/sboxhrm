import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import 'pos_print_template_loader.dart';
import 'pos_receipt_layout.dart';
import 'pos_topping_format.dart';
import 'pos_vietnamese_money_words.dart';

const _itemBegin = '<!--BEGIN_ITEMS-->';
const _itemEnd = '<!--END_ITEMS-->';

/// Dữ liệu mẫu để xem trước mẫu in.
Map<String, String> posPrintSampleData({
  String documentType = PosPrintDocumentTypes.saleInvoice,
  String? storeName,
  String? storeAddress,
  String? storePhone,
  Map<String, dynamic>? commercialProfile,
}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final profileData = posPrintCommercialProfileData(commercialProfile);
  final shop = (storeName ?? profileData['Ten_Cua_Hang'] ?? '').trim();
  final addr = (storeAddress ?? profileData['Dia_Chi_Chi_Nhanh'] ?? '').trim();
  final phone =
      (storePhone ?? profileData['Dien_Thoai_Chi_Nhanh'] ?? '').trim();
  final base = <String, String>{
    ...profileData,
    'Ten_Cua_Hang': shop.isNotEmpty ? shop : 'Cửa hàng',
    'Dia_Chi_Chi_Nhanh': addr.isNotEmpty ? addr : 'Địa chỉ cửa hàng',
    'Dien_Thoai_Chi_Nhanh': phone.isNotEmpty ? phone : '0900000000',
    'Tieu_De_In': PosPrintDocumentTypes.all[documentType] ?? 'Hóa đơn',
    'Ma_Don_Hang': 'HD000050',
    'Ngay': '28/06/2026',
    'Gio': '14:30',
    'Khach_Hang': 'Anh Hòa Q.1',
    'SDT': '0909123456',
    'Dia_Chi_Khach_Hang': 'Q.1, TP.HCM',
    'Tong_Tien_Hang': money.format(28200000),
    'Chiet_Khau_Hoa_Don': money.format(500000),
    'Tien_Thue': money.format(2770000),
    'Thue': money.format(2770000),
    'VAT': money.format(2770000),
    'Phu_Thu': money.format(20000),
    'Phi_Giao_Hang': money.format(15000),
    'Tong_Cong': money.format(30505000),
    'Khach_Can_Tra': money.format(30505000),
    'Khach_Thanh_Toan': money.format(30505000),
    'Tien_Thua': money.format(0),
    'Con_Lai': money.format(0),
    'Tong_Cong_Bang_Chu': vietnameseMoneyInWords(28200000),
    'Hinh_Thuc_Thanh_Toan': 'Tiền mặt',
    'Nguoi_Ban': 'NV Bán hàng',
    'Ghi_Chu': '',
    'Ma_Bao_Gia': 'BG000012',
    'So_Chung_Tu': 'BG000012',
    'Han_Bao_Gia': '05/10/2026',
    'Dieu_Khoan': 'Báo giá có hiệu lực 15 ngày. Thanh toán 50% khi đặt hàng.',
    'Bao_Hanh': '12 tháng',
    'So_Hop_Dong': 'HD0926/2026/NT-TLP',
    'Ngay_Hop_Dong': '16/09/2026',
    'Dia_Diem_Thi_Cong': 'Showroom Nghĩa Tín, Tuy Phước Tây',
    'MST_Cua_Hang': profileData['MST_Cua_Hang'] ?? '0402207773',
    'Email_Cua_Hang': profileData['Email_Cua_Hang'] ?? '',
    'Tai_Khoan_Cua_Hang':
        profileData['Tai_Khoan_Cua_Hang'] ?? '512222255555',
    'Ngan_Hang_Cua_Hang': profileData['Ngan_Hang_Cua_Hang'] ??
        'Ngân hàng TMCP Quân đội (MB) — CN Đà Nẵng',
    'Chu_Tai_Khoan_Cua_Hang': profileData['Chu_Tai_Khoan_Cua_Hang'] ?? shop,
    'Nguoi_Dai_Dien_Cua_Hang':
        profileData['Nguoi_Dai_Dien_Cua_Hang'] ?? 'Nguyễn Hoài Sang',
    'Chuc_Vu_Cua_Hang': profileData['Chuc_Vu_Cua_Hang'] ?? 'Giám đốc',
    'MST_Khach_Hang': '4100543367',
    'Ten_Cong_Ty_Khach': 'Công ty TNHH Đồ gỗ Nghĩa Tín',
    'Tai_Khoan_Khach_Hang': '5810053610',
    'Ngan_Hang_Khach_Hang': 'BIDV — CN Phú Tài',
    'Nguoi_Dai_Dien_Khach': 'Huỳnh Lê Đại Phúc',
    'Chuc_Vu_Khach': 'Giám đốc',
    'Tam_Ung': money.format(15252500),
    'Con_Lai_Hop_Dong': money.format(15252500),
    'Ky_Han_Thi_Cong': '07 – 10 ngày làm việc',
    'Ky_Han_Thanh_Toan': '10 ngày kể từ ký HĐ',
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
      'Ghi_Chu': '+ TranChau x2\n+ Thach',
      'So_Luong': '1',
    };
  }
  return base;
}

/// Map thông tin cửa hàng thương mại → token in A4.
Map<String, String> posPrintCommercialProfileData(
    Map<String, dynamic>? profile) {
  if (profile == null || profile.isEmpty) return {};
  String t(String a, String b) => (profile[a] ?? profile[b] ?? '').toString();
  final company = t('companyName', 'CompanyName');
  final rep = t('legalRepresentative', 'LegalRepresentative');
  final title = t('legalTitle', 'LegalTitle');
  return {
    if (company.isNotEmpty) 'Ten_Cua_Hang': company,
    if (t('address', 'Address').isNotEmpty)
      'Dia_Chi_Chi_Nhanh': t('address', 'Address'),
    if (t('phone', 'Phone').isNotEmpty)
      'Dien_Thoai_Chi_Nhanh': t('phone', 'Phone'),
    if (t('email', 'Email').isNotEmpty) 'Email_Cua_Hang': t('email', 'Email'),
    if (t('taxCode', 'TaxCode').isNotEmpty)
      'MST_Cua_Hang': t('taxCode', 'TaxCode'),
    if (t('bankAccountNumber', 'BankAccountNumber').isNotEmpty)
      'Tai_Khoan_Cua_Hang': t('bankAccountNumber', 'BankAccountNumber'),
    if (t('bankName', 'BankName').isNotEmpty)
      'Ngan_Hang_Cua_Hang': t('bankName', 'BankName'),
    if (t('bankAccountHolder', 'BankAccountHolder').isNotEmpty)
      'Chu_Tai_Khoan_Cua_Hang': t('bankAccountHolder', 'BankAccountHolder'),
    if (rep.isNotEmpty) 'Nguoi_Dai_Dien_Cua_Hang': rep,
    'Chuc_Vu_Cua_Hang': title.trim().isEmpty ? 'Giám đốc' : title.trim(),
  };
}

List<Map<String, String>> posPrintSampleLines() {
  final money = NumberFormat('#,##0', 'vi_VN');
  return [
    {
      'STT': '1',
      'Ma_Hang': 'MONTRASUA01',
      'Ten_Hang_Hoa': 'TraSua',
      'Don_Gia': money.format(25000),
      'So_Luong': '1',
      'Don_Vi_Tinh': 'Ly',
      'Chiet_Khau': '0',
      'Thanh_Tien': money.format(38000),
      'Bao_Hanh': '',
      'Ghi_Chu': '+ TranChau x2 (+16.000)\n+ Thach (+5.000)',
      'Hinh_Anh': '',
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
      'Bao_Hanh': '12 tháng',
      'Hinh_Anh': '',
    },
  ];
}

bool _isRawHtmlPrintToken(String key) => key == 'Hinh_Anh';

String _replacePrintToken(String row, String key, String value) {
  if (_isRawHtmlPrintToken(key)) {
    return row.replaceAll('{$key}', value);
  }
  return row.replaceAll('{$key}', value);
}

/// Render HTML mẫu in — thay token + lặp khối dòng hàng.
///
/// [wrapDocument] = false khi nhúng vào iframe soạn thảo (đã có html/body).
String renderPosPrintTemplateHtml(
  String templateHtml, {
  required Map<String, String> data,
  required List<Map<String, String>> lineItems,
  bool wrapDocument = true,
  String paperSize = 'K80',
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
        row = _replacePrintToken(row, e.key, e.value);
      }
      for (final e in data.entries) {
        row = _replacePrintToken(row, e.key, e.value);
      }
      rendered.write(row);
    }
    html = html.replaceRange(begin, end + _itemEnd.length, rendered.toString());
  }

  for (final e in data.entries) {
    html = html.replaceAll('{${e.key}}', e.value);
  }
  // HTML mẫu cũ: chữ «…đồng chẵn» hard-code từ preview — thay bằng tổng đúng.
  final bangChu = data['Tong_Cong_Bang_Chu'];
  if (bangChu != null && bangChu.isNotEmpty) {
    html = html.replaceAllMapped(
      RegExp(r'>([^<]*đồng chẵn)<'),
      (m) => '>$bangChu<',
    );
  }
  if (!wrapDocument) return html;
  return wrapPosPrintHtmlDocument(
    html,
    paperSize: data['PaperSize'] ?? paperSize,
  );
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
  double? vatAmount,
  /// Giá đã gồm thuế → không cộng Vat vào Tong_Cong / Khach_Can_Tra.
  bool vatIncludedInPrice = false,
  double? surchargeAmount,
  double? deliveryFee,
}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final saleDate = order.saleDate?.toLocal() ?? order.createdAt?.toLocal() ?? DateTime.now();
  final rawVat = vatAmount ?? order.vatAmount;
  // Inclusive: Total đã gồm thuế; VatAmount (nếu còn) chỉ là phần tách — không cộng thêm.
  final vat = vatIncludedInPrice ? 0.0 : rawVat;
  final surcharge = surchargeAmount ?? order.surchargeAmount;
  final ship = deliveryFee ?? order.deliveryFee;
  final payable = order.total + vat + surcharge + ship;
  final change = (order.paidAmount - payable).clamp(0, double.infinity);
  final due = (payable - order.paidAmount).clamp(0, double.infinity);
  final vatText = money.format(vat);
  final surchargeText = money.format(surcharge);
  final shipText = money.format(ship);

  return {
    'PaperSize': paperSize,
    'Ten_Cua_Hang': storeName ?? 'Cửa hàng',
    'Dia_Chi_Chi_Nhanh': storeAddress ?? '',
    'Dien_Thoai_Chi_Nhanh': storePhone ?? '',
    'Tieu_De_In': titleOverride ??
        (order.printCount > 1
            ? 'HÓA ĐƠN BÁN HÀNG — IN LẠI'
            : 'HÓA ĐƠN BÁN HÀNG'),
    'Ma_Don_Hang': order.orderNo.isEmpty
        ? ''
        : PosReceiptLayout.formatSaleInvoiceNo(order.orderNo),
    'Ngay': DateFormat('dd/MM/yyyy').format(saleDate),
    'Gio': DateFormat('HH:mm').format(saleDate),
    'Khach_Hang': () {
      final name = (order.customerName ?? '').trim();
      if (name.isEmpty) return '';
      final lower = name.toLowerCase();
      if (lower == 'bán cho người tiêu dùng' || lower == 'khách lẻ') {
        return '';
      }
      return name;
    }(),
    'SDT': (order.deliveryPhone ?? '').trim().isNotEmpty
        ? order.deliveryPhone!.trim()
        : (order.customerPhone ?? '').trim(),
    'Dia_Chi_Khach_Hang': (order.deliveryAddress ?? '').trim(),
    'Tong_Tien_Hang': money.format(order.subTotal),
    'Chiet_Khau_Hoa_Don': money.format(order.discount),
    'Tien_Thue': vatText,
    'Thue': vatText,
    'VAT': vatText,
    'Phu_Thu': surchargeText,
    'Phi_Giao_Hang': shipText,
    'Tong_Cong': money.format(payable),
    'Khach_Can_Tra': money.format(payable),
    'Khach_Thanh_Toan': money.format(order.paidAmount),
    'Tien_Thua': money.format(change),
    'Con_Lai': money.format(due),
    'Tong_Cong_Bang_Chu': _amountInWords(payable),
    'Hinh_Thuc_Thanh_Toan': order.paymentMethod,
    'Nguoi_Ban': order.soldBy ?? order.createdBy ?? '',
    'Ghi_Chu': order.note ?? '',
    'Ten_Ban': (order.serviceResourceName ?? '').trim(),
    'Khu_Vuc': (order.serviceAreaName ?? '').trim(),
    'In_Lai': order.printCount > 1
        ? 'Bản in lại — Lần in thứ ${order.printCount} — thông báo chủ cửa hàng'
        : '',
    'Lan_In': order.printCount > 1 ? '${order.printCount}' : '',
    'Thu_Tu_Hoa_Don_Ngay': '',
    'Tong_Hoa_Don_Trong_Ngay': '',
  };
}

List<Map<String, String>> buildSaleOrderPrintLines(
  List<PosSaleOrderLine> lines, {
  bool mergeSameItems = false,
  bool compactLineMoney = false,
}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final src = mergeSameItems ? _mergeLines(lines) : lines;
  String lineMoney(double v) => compactLineMoney
      ? PosReceiptLayout.moneyItemCompact(v)
      : money.format(v);
  return List.generate(src.length, (i) {
    final l = src[i];
    var name = l.productName;
    if (l.unitName != null && l.unitName!.isNotEmpty) {
      name = '$name (${l.unitName})';
    }
    final note = posToppingNoteFromSaleLine(
      l,
      withPrice: true,
      money: money,
    );
    return {
      'STT': '${i + 1}',
      'Ma_Hang': l.productId.length > 8 ? l.productId.substring(0, 8) : l.productId,
      'Ten_Hang_Hoa': name,
      'Don_Gia': lineMoney(l.unitPrice),
      'So_Luong': qtyFmt.format(l.qty),
      'Don_Vi_Tinh': l.unitName ?? '',
      'Chiet_Khau': l.discountAmount > 0 ? money.format(l.discountAmount) : '0',
      'Thanh_Tien': lineMoney(l.lineTotal),
      'Ghi_Chu': note,
    };
  });
}

List<PosSaleOrderLine> _mergeLines(List<PosSaleOrderLine> lines) {
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

/// Mẫu in: ưu tiên đúng khổ máy (K58/K80), rồi mặc định cửa hàng.
Future<PosPrintTemplate?> resolvePosPrintTemplate({
  required String documentType,
  String? templateId,
  String? paperSize,
}) async {
  final api = ApiService();
  var listRes = await api.getPosPrintTemplates(documentType: documentType);
  var list = parsePosPrintTemplatesResponse(listRes);
  if (list.isEmpty) {
    list = await loadPosPrintTemplates(api, documentType);
  }
  return pickPosPrintTemplateForPaper(
    list,
    paperSize: paperSize,
    templateId: templateId,
  );
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
