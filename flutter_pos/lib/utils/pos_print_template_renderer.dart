import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import 'pos_area_dims.dart';
import 'pos_print_template_defaults.dart';
import 'pos_print_template_loader.dart';
import 'pos_receipt_layout.dart';
import 'pos_topping_format.dart';
import 'pos_vietnamese_money_words.dart';

const _itemBegin = '<!--BEGIN_ITEMS-->';
const _itemEnd = '<!--END_ITEMS-->';

const _beginMarker = '<span data-pos="begin-items" hidden></span>';
const _endMarker = '<span data-pos="end-items" hidden></span>';

final _tableRe = RegExp(r'<table\b[^>]*>[\s\S]*?</table>', caseSensitive: false);
final _tbodyRe = RegExp(r'(<tbody\b[^>]*>)([\s\S]*?)(</tbody>)', caseSensitive: false);
final _trRe = RegExp(r'<tr\b[^>]*>[\s\S]*?</tr>', caseSensitive: false);
final _tdRe = RegExp(r'(<td\b[^>]*>)([\s\S]*?)(</td>)', caseSensitive: false);

/// contenteditable thường nuốt HTML comment — giữ vòng hàng bằng span ẩn.
String posPrintProtectItemMarkers(String html) => html
    .replaceAll(_itemBegin, _beginMarker)
    .replaceAll(_itemEnd, _endMarker);

String posPrintRestoreItemMarkers(String html) {
  var out = html.replaceAll(
    RegExp(r'<span[^>]*data-pos="begin-items"[^>]*>\s*</span>',
        caseSensitive: false),
    _itemBegin,
  );
  return out.replaceAll(
    RegExp(r'<span[^>]*data-pos="end-items"[^>]*>\s*</span>',
        caseSensitive: false),
    _itemEnd,
  );
}

const _defaultItemTable =
    '<table style="width:100%;border-collapse:collapse;margin:8px 0;font-size:12px">'
    '<thead><tr style="background:#f3f4f6">'
    '<th style="border:1px solid #111;padding:4px 2px;text-align:center">STT</th>'
    '<th style="border:1px solid #111;padding:4px 4px;text-align:left">Tên hàng</th>'
    '<th style="border:1px solid #111;padding:4px 2px;text-align:center">ĐVT</th>'
    '<th style="border:1px solid #111;padding:4px 2px;text-align:center">SL</th>'
    '<th style="border:1px solid #111;padding:4px 3px;text-align:right">Đơn giá</th>'
    '<th style="border:1px solid #111;padding:4px 3px;text-align:right">Thành tiền</th>'
    '<th style="border:1px solid #111;padding:4px 2px;text-align:center">BH</th>'
    '</tr></thead><tbody><!--BEGIN_ITEMS-->'
    '<tr>'
    '<td style="border:1px solid #111;padding:4px 2px;text-align:center">{STT}</td>'
    '<td style="border:1px solid #111;padding:4px 4px">{Ten_Hang_Hoa}</td>'
    '<td style="border:1px solid #111;padding:4px 2px;text-align:center">{Don_Vi_Tinh}</td>'
    '<td style="border:1px solid #111;padding:4px 2px;text-align:center">{So_Luong}</td>'
    '<td style="border:1px solid #111;padding:4px 3px;text-align:right">{Don_Gia}</td>'
    '<td style="border:1px solid #111;padding:4px 3px;text-align:right">{Thanh_Tien}</td>'
    '<td style="border:1px solid #111;padding:4px 2px;text-align:center">{Bao_Hanh}</td>'
    '</tr><!--END_ITEMS--></tbody></table>';

/// Mẫu Word / soạn thảo hay mất comment hoặc để sẵn 1 dòng mẫu (Aquafina).
String ensurePosPrintItemLoop(String html) {
  // Mẫu chứng từ không có bảng hàng (vd. đề nghị thanh toán) — không tự chèn bảng.
  if (html.contains('<!--NO_ITEMS-->')) return html;
  if (_itemLoopIsUsable(html)) return html;
  // Comment nằm ở chú thích import — không phải vòng bảng thật.
  html = html.replaceAll(_itemBegin, '').replaceAll(_itemEnd, '');
  final tokenAt = html.indexOf('{Ten_Hang_Hoa}');
  if (tokenAt >= 0) {
    final head = html.substring(0, tokenAt).toLowerCase();
    final trStart = head.lastIndexOf('<tr');
    final trEnd = html.toLowerCase().indexOf('</tr>', tokenAt);
    if (trStart >= 0 && trEnd > trStart) {
      final after = trEnd + 5;
      return '${html.substring(0, trStart)}$_itemBegin'
          '${html.substring(trStart, after)}$_itemEnd${html.substring(after)}';
    }
  }
  for (final table in _tableRe.allMatches(html)) {
    final tableHtml = table.group(0)!;
    if (!_looksLikeProductTable(tableHtml)) continue;
    final tbody = _tbodyRe.firstMatch(tableHtml);
    if (tbody == null) continue;
    final inner = tbody.group(2) ?? '';
    if (inner.contains('{Tong_Cong}')) continue;
    String? dataRow;
    for (final m in _trRe.allMatches(inner)) {
      final row = m.group(0)!;
      if (row.toLowerCase().contains('<th')) continue;
      dataRow = row;
      break;
    }
    if (dataRow == null) continue;
    final tokenRow = _tokenizeProductRow(dataRow);
    final newTable = tableHtml.replaceFirst(
      tbody.group(0)!,
      '${tbody.group(1)}$_itemBegin$tokenRow$_itemEnd${tbody.group(3)}',
    );
    return html.replaceRange(table.start, table.end, newTable);
  }
  final close = html.toLowerCase().lastIndexOf('</div>');
  if (close >= 0) {
    return '${html.substring(0, close)}$_defaultItemTable${html.substring(close)}';
  }
  return '$html$_defaultItemTable';
}

bool _itemLoopIsUsable(String html) {
  final begin = html.indexOf(_itemBegin);
  final end = html.indexOf(_itemEnd);
  if (begin < 0 || end <= begin) return false;
  final block = html.substring(begin + _itemBegin.length, end);
  // Hint nhập Word/PDF hay có comment + {Ten_Hang_Hoa} nhưng không phải hàng bảng.
  // Dòng Aquafina cứng có <tr> nhưng không có token — cũng không dùng được.
  return block.contains('{Ten_Hang_Hoa}') &&
      (block.contains('<tr') ||
          block.contains('<TR') ||
          block.contains('<td') ||
          block.contains('<TD'));
}

bool _looksLikeProductTable(String tableHtml) {
  final t = tableHtml.toLowerCase();
  if (t.contains('{ten_hang_hoa}') || t.contains('begin_items')) return true;
  if (t.contains('tên hàng') ||
      t.contains('ten hang') ||
      t.contains('hàng hóa') ||
      t.contains('thành tiền') ||
      t.contains('thanh tien') ||
      t.contains('đơn giá') ||
      t.contains('don gia')) {
    return true;
  }
  if (RegExp(r'>\s*stt\s*<').hasMatch(t)) return true;
  final firstTr = _trRe.firstMatch(tableHtml);
  if (firstTr == null) return false;
  return _tdRe.allMatches(firstTr.group(0)!).length >= 4;
}

String _tokenizeProductRow(String tr) {
  final tds = _tdRe.allMatches(tr).toList();
  if (tds.isEmpty) return tr;
  const byCount = <int, List<String>>{
    4: ['Ten_Hang_Hoa', 'So_Luong', 'Don_Gia', 'Thanh_Tien'],
    5: ['STT', 'Ten_Hang_Hoa', 'So_Luong', 'Don_Gia', 'Thanh_Tien'],
    6: ['STT', 'Ten_Hang_Hoa', 'Don_Vi_Tinh', 'So_Luong', 'Don_Gia', 'Thanh_Tien'],
  };
  final tokens = byCount[tds.length] ??
      ['STT', 'Ten_Hang_Hoa', 'Don_Vi_Tinh', 'So_Luong', 'Don_Gia', 'Thanh_Tien', 'Bao_Hanh'];
  var i = 0;
  return tr.replaceAllMapped(_tdRe, (m) {
    final tok = i < tokens.length ? tokens[i] : 'Ghi_Chu';
    i++;
    return '${m.group(1)}{$tok}${m.group(3)}';
  });
}

/// Token giữ lại khi in chứng từ thật ([fillSamples] = false) — còn lại là số liệu mẫu, xóa trắng.
const _realDocKeys = <String>{
  'Ten_Cua_Hang',
  'Ten_Cong_Ty',
  'Dia_Chi_Chi_Nhanh',
  'Dia_Chi_Cong_Ty',
  'Dien_Thoai_Chi_Nhanh',
  'Dien_Thoai_Cong_Ty',
  'Con_Dau',
  'Logo',
  'Dong_Email',
  'Tieu_De_In',
  'Chuc_Vu_Cua_Hang',
  'Chu_Tai_Khoan_Cua_Hang',
};

/// Dữ liệu mẫu để xem trước mẫu in.
///
/// [fillSamples] = false: dùng làm nền cho chứng từ thật — chỉ giữ thông tin cửa hàng
/// thật (hồ sơ thương mại), mọi số liệu mẫu (MST/TK khách, người đại diện, cọc…) để trống
/// để không lọt dữ liệu giả lên báo giá / hợp đồng.
Map<String, String> posPrintSampleData({
  String documentType = PosPrintDocumentTypes.saleInvoice,
  String? storeName,
  String? storeAddress,
  String? storePhone,
  Map<String, dynamic>? commercialProfile,
  bool fillSamples = true,
}) {
  if (!fillSamples) {
    final sample = posPrintSampleData(
      documentType: documentType,
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      commercialProfile: commercialProfile,
    );
    final profileData = posPrintCommercialProfileData(commercialProfile);
    const placeholders = {'Địa chỉ cửa hàng', '0900000000'};
    return {
      for (final e in sample.entries)
        e.key: profileData.containsKey(e.key)
            ? profileData[e.key]!
            : (_realDocKeys.contains(e.key) && !placeholders.contains(e.value)
                ? e.value
                : ''),
    };
  }
  final money = NumberFormat('#,##0', 'vi_VN');
  final profileData = posPrintCommercialProfileData(commercialProfile);
  final shop = (storeName ?? '').trim();
  final addr = (storeAddress ?? '').trim();
  final phone = (storePhone ?? '').trim();
  final company = (profileData['Ten_Cong_Ty'] ?? '').trim();
  final companyAddr = (profileData['Dia_Chi_Cong_Ty'] ?? '').trim();
  final companyPhone = (profileData['Dien_Thoai_Cong_Ty'] ?? '').trim();
  final commercial = PosPrintDocumentTypes.isCommercial(documentType);
  final legalName = company.isNotEmpty
      ? company
      : (shop.isNotEmpty ? shop : 'Cửa hàng');
  final legalAddr = companyAddr.isNotEmpty
      ? companyAddr
      : (addr.isNotEmpty ? addr : 'Địa chỉ cửa hàng');
  final legalPhone = companyPhone.isNotEmpty
      ? companyPhone
      : (phone.isNotEmpty ? phone : '0900000000');
  final printedName = commercial ? legalName : (shop.isNotEmpty ? shop : 'Cửa hàng');
  final printedAddr =
      commercial ? legalAddr : (addr.isNotEmpty ? addr : 'Địa chỉ cửa hàng');
  final printedPhone =
      commercial ? legalPhone : (phone.isNotEmpty ? phone : '0900000000');
  final base = <String, String>{
    ...profileData,
    'Ten_Cua_Hang': printedName,
    'Ten_Cong_Ty': legalName,
    'Dia_Chi_Chi_Nhanh': printedAddr,
    'Dia_Chi_Cong_Ty': legalAddr,
    'Dien_Thoai_Chi_Nhanh': printedPhone,
    'Dien_Thoai_Cong_Ty': legalPhone,
    'Con_Dau': profileData['Con_Dau'] ?? '<div style="height:64px"></div>',
    'Dong_Email': profileData['Dong_Email'] ?? '',
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
    'Dieu_Khoan': 'Báo giá có hiệu lực 15 ngày.',
    'Bao_Hanh': '12 tháng',
    'So_Hop_Dong': 'HD0926/2026/NT-TLP',
    'Ngay_Hop_Dong': '16/09/2026',
    'Dia_Diem_Thi_Cong': 'Showroom Nghĩa Tín, Tuy Phước Tây',
    'MST_Cua_Hang': profileData['MST_Cua_Hang'] ??
        profileData['MST_Cong_Ty'] ??
        '0402207773',
    'MST_Cong_Ty': profileData['MST_Cong_Ty'] ??
        profileData['MST_Cua_Hang'] ??
        '0402207773',
    'Email_Cua_Hang': profileData['Email_Cua_Hang'] ?? '',
    'Tai_Khoan_Cua_Hang':
        profileData['Tai_Khoan_Cua_Hang'] ?? '512222255555',
    'Ngan_Hang_Cua_Hang': profileData['Ngan_Hang_Cua_Hang'] ??
        'Ngân hàng TMCP Quân đội (MB) — CN Đà Nẵng',
    'Chu_Tai_Khoan_Cua_Hang':
        profileData['Chu_Tai_Khoan_Cua_Hang'] ?? legalName,
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
    'Ky_Han_Thi_Cong': 'hoàn thành trước ngày 25/10/2026',
    'Ky_Han_Thanh_Toan': 'theo tiến độ các đợt tại Điều 2',
    'Ngay_So': '28',
    'Thang': '06',
    'Nam': '2026',
    'Ngay_HD_So': '16',
    'Thang_HD': '09',
    'Nam_HD': '2026',
    'Ben_A_Ten': 'Công ty TNHH Đồ gỗ Nghĩa Tín',
    'Email_Khach_Hang': '',
    'Thue_Suat': '8%',
    'Cach_Tinh_VAT': 'Giá đã cộng thuế GTGT 8%.',
    'Gia_Tri_Truoc_VAT': money.format(28245370),
    'Tien_Coc': money.format(9151500),
    'Phan_Tram_Coc': '30',
    'Coc_Tinh_Tren': 'tổng giá trị',
    'Tien_Coc_Bang_Chu': vietnameseMoneyInWords(9151500),
    'Con_Lai_Bang_Chu': vietnameseMoneyInWords(21353500),
    'Da_Thanh_Toan': money.format(9151500),
    'Da_Thanh_Toan_Hien': money.format(9151500),
    'Con_Phai_Thu': money.format(21353500),
    'Con_Phai_Thu_Bang_Chu': vietnameseMoneyInWords(21353500),
    'De_Nghi_Dot': 'Giao hàng',
    'De_Nghi_So_Tien': money.format(15252500),
    'De_Nghi_Bang_Chu': vietnameseMoneyInWords(15252500),
    'Co_Dot_Thanh_Toan': '1',
    posPrintStagesKey: jsonEncode([
      {
        'Dot_STT': '1', 'Dot_Ten': 'Đặt cọc ký hợp đồng', 'Dot_Phan_Tram': '30%',
        'Dot_So_Tien': money.format(9151500), 'Dot_Han': '16/09/2026',
        'Dot_Da_Thu': money.format(9151500), 'Dot_Con_Lai': '0', 'Dot_Ghi_Chu': '',
      },
      {
        'Dot_STT': '2', 'Dot_Ten': 'Giao hàng', 'Dot_Phan_Tram': '50%',
        'Dot_So_Tien': money.format(15252500), 'Dot_Han': '',
        'Dot_Da_Thu': '0', 'Dot_Con_Lai': money.format(15252500), 'Dot_Ghi_Chu': '',
      },
      {
        'Dot_STT': '3', 'Dot_Ten': 'Nghiệm thu bàn giao', 'Dot_Phan_Tram': '20%',
        'Dot_So_Tien': money.format(6101000), 'Dot_Han': '',
        'Dot_Da_Thu': '0', 'Dot_Con_Lai': money.format(6101000), 'Dot_Ghi_Chu': '',
      },
    ]),
    'Ngay_San_Xuat': '',
    'Ngay_Lap_Dat': '',
    'Ngay_Ban_Giao': '25/10/2026',
    'Ton_Tai': 'Không có.',
    'Dia_Diem_Ky': '',
    'Co_Bao_Hanh_Dong': '1',
    'Co_Anh': '',
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
  final addr = t('address', 'Address');
  final phone = t('phone', 'Phone');
  final tax = t('taxCode', 'TaxCode');
  return {
    if (company.isNotEmpty) 'Ten_Cong_Ty': company,
    if (addr.isNotEmpty) 'Dia_Chi_Cong_Ty': addr,
    if (phone.isNotEmpty) 'Dien_Thoai_Cong_Ty': phone,
    if (t('email', 'Email').isNotEmpty) 'Email_Cua_Hang': t('email', 'Email'),
    if (tax.isNotEmpty) 'MST_Cua_Hang': tax,
    if (tax.isNotEmpty) 'MST_Cong_Ty': tax,
    if (t('bankAccountNumber', 'BankAccountNumber').isNotEmpty)
      'Tai_Khoan_Cua_Hang': t('bankAccountNumber', 'BankAccountNumber'),
    if (t('bankName', 'BankName').isNotEmpty)
      'Ngan_Hang_Cua_Hang': t('bankName', 'BankName'),
    if (t('bankAccountHolder', 'BankAccountHolder').isNotEmpty)
      'Chu_Tai_Khoan_Cua_Hang': t('bankAccountHolder', 'BankAccountHolder'),
    if (rep.isNotEmpty) 'Nguoi_Dai_Dien_Cua_Hang': rep,
    'Chuc_Vu_Cua_Hang': title.trim().isEmpty ? 'Giám đốc' : title.trim(),
    'Logo': posCommercialLogoHtml(t('logoPngBase64', 'LogoPngBase64')),
    'Con_Dau': posCommercialStampHtml(t('stampPngBase64', 'StampPngBase64')),
    'Dong_Email': t('email', 'Email').trim().isEmpty
        ? ''
        : 'Email: ${t('email', 'Email').trim()}',
  };
}

List<Map<String, String>> posPrintSampleLines({int count = 2}) {
  final money = NumberFormat('#,##0', 'vi_VN');
  const names = <(String, String, String)>[
    ('MONTRASUA01', 'Trà sữa', 'Ly'),
    ('IP15PM', 'iPhone 15 Pro Max', 'Cái'),
    ('LAPTOP01', 'Laptop văn phòng', 'Cái'),
    ('BANLV01', 'Bàn làm việc 1m2', 'Cái'),
    ('GHXG01', 'Ghế xoay lưới', 'Cái'),
    ('TULH01', 'Tủ hồ sơ 3 tầng', 'Cái'),
    ('DENLED01', 'Đèn LED bàn', 'Cái'),
    ('MAYIN01', 'Máy in laser A4', 'Cái'),
  ];
  final n = count.clamp(1, names.length);
  return [
    for (var i = 0; i < n; i++)
      {
        'STT': '${i + 1}',
        'Ma_Hang': names[i].$1,
        'Ten_Hang_Hoa': names[i].$2,
        'Don_Gia': money.format(i == 1 ? 28000000 : 25000 + i * 150000),
        'So_Luong': '${1 + (i % 3)}',
        'Don_Vi_Tinh': names[i].$3,
        'Chiet_Khau': i == 1 ? money.format(500000) : '0',
        'Thanh_Tien': money.format(i == 1 ? 27500000 : (25000 + i * 150000) * (1 + (i % 3))),
        'Bao_Hanh': i % 2 == 1 ? '12 tháng' : '',
        'Chieu_Dai': i == 0 ? '2,4' : '',
        'Chieu_Rong': i == 0 ? '1,2' : '0,8',
        'Chieu_Cao': i == 0 ? '' : '2,1',
        'Ghi_Chu': i == 0 ? '+ TranChau x2\n+ Thach' : '',
        'Hinh_Anh': '',
      },
  ];
}

bool _isRawHtmlPrintToken(String key) =>
    key == 'Hinh_Anh' || key == 'Con_Dau';

/// PNG con dấu (base64 hoặc data-url) — HTML img treo lên chữ ký. Rỗng nếu chưa có.
String posCommercialLogoHtml(String? raw) {
  final img = posCommercialStampHtml(raw);
  if (img.isEmpty || !img.contains('<img')) return '';
  return img
      .replaceAll('width="112"', 'width="72"')
      .replaceAll('height="112"', 'height="72"')
      .replaceAll('width:112px;height:112px', 'width:72px;height:72px');
}

String posCommercialStampHtml(String? raw) {
  var s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  final comma = s.indexOf(',');
  if (s.startsWith('data:') && comma > 0) s = s.substring(comma + 1).trim();
  s = s.replaceAll(RegExp(r'\s'), '');
  if (s.length < 32) return '<div style="height:64px"></div>';
  return '<img src="data:image/png;base64,$s" alt="" width="96" height="96" '
      'style="width:96px;height:96px;object-fit:contain;display:block;margin:8px auto 0"/>';
}

bool _printMoneyIsZero(String? raw) {
  if (raw == null || raw.trim().isEmpty) return true;
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return true;
  return int.tryParse(digits) == 0;
}

String _escPrint(String raw) => raw
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Mẫu không có ô ghi chú / chiết khấu dòng thì gắn dưới tên hàng.
String _withLineNoteAndDiscount(String block) {
  if (!block.contains('{Ten_Hang_Hoa}')) return block;
  final extra = StringBuffer();
  if (!block.contains('{Hinh_Anh}')) extra.write('{Sbox_Hinh_Anh}');
  if (!block.contains('{Ghi_Chu}')) extra.write('{Sbox_Ghi_Chu}');
  if (!block.contains('{Chiet_Khau}')) extra.write('{Sbox_Chiet_Khau}');
  if (extra.isEmpty) return block;
  return block.replaceFirst('{Ten_Hang_Hoa}', '{Ten_Hang_Hoa}$extra');
}

String _lineNoteHtml(String? note) {
  final text = (note ?? '').trim();
  if (text.isEmpty) return '';
  return '<div style="margin-top:2px;font-size:11px;font-style:italic;white-space:pre-wrap">${_escPrint(text)}</div>';
}

String _lineDiscountHtml(String? amount) {
  if (_printMoneyIsZero(amount)) return '';
  return '<div style="margin-top:2px;font-size:11px">Giảm giá: ${_escPrint(amount!.trim())}</div>';
}

/// Hàng «Chiết khấu» ở chân bảng chỉ giữ khi đơn có chiết khấu.
String _dropZeroInvoiceDiscountRow(String html, String? amount) {
  if (!_printMoneyIsZero(amount)) return html;
  return html.replaceAllMapped(
    RegExp(r'<tr\b[^>]*>[\s\S]*?</tr>', caseSensitive: false),
    (m) {
      final row = m.group(0)!;
      final text = row
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();
      final label = text.contains('chiết khấu') ||
          text.contains('chiet khau') ||
          text.contains('giảm giá');
      if (!label || text.length > 80 || !_printMoneyIsZero(text)) return row;
      return '';
    },
  );
}

String _replacePrintToken(String row, String key, String value) {
  if (_isRawHtmlPrintToken(key)) {
    return row.replaceAll('{$key}', value);
  }
  return row.replaceAll('{$key}', value);
}

/// Danh sách đợt thanh toán (JSON mảng object chuỗi) trong dữ liệu chứng từ — trùng API.
const posPrintStagesKey = '_Dot_Thanh_Toan';
const _stageBegin = '<!--BEGIN_STAGES-->';
const _stageEnd = '<!--END_STAGES-->';
final _ifRe = RegExp(r'<!--IF:([A-Za-z0-9_]+)-->([\s\S]*?)<!--ENDIF:\1-->');
final _ifNotRe = RegExp(r'<!--IFNOT:([A-Za-z0-9_]+)-->([\s\S]*?)<!--ENDIFNOT:\1-->');
final _zeroNumberRe = RegExp(r'^[\s0.,]*(đ|VNĐ|VND|%)?\s*$', caseSensitive: false);

/// Trường «có dữ liệu»: khác rỗng và không phải số 0 (0 / 0 đ / 0%).
bool posPrintHasValue(String? v) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return false;
  return !(RegExp(r'\d').hasMatch(t) && _zeroNumberRe.hasMatch(t));
}

/// `<!--IF:Truong-->…<!--ENDIF:Truong-->` chỉ in khi trường có dữ liệu;
/// `<!--IFNOT:Truong-->…<!--ENDIFNOT:Truong-->` chỉ in khi trường trống.
String applyPosPrintConditionals(String html, Map<String, String> data) {
  for (var pass = 0; pass < 12; pass++) {
    final before = html;
    html = html.replaceAllMapped(
      _ifRe,
      (m) => posPrintHasValue(data[m.group(1)]) ? m.group(2)! : '',
    );
    html = html.replaceAllMapped(
      _ifNotRe,
      (m) => posPrintHasValue(data[m.group(1)]) ? '' : m.group(2)!,
    );
    if (before == html) break;
  }
  return html;
}

String _escapeHtml(String v) => v
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _expandStages(String html, Map<String, String> data) {
  final begin = html.indexOf(_stageBegin);
  final end = html.indexOf(_stageEnd);
  if (begin < 0 || end <= begin) return html;
  final block = html.substring(begin + _stageBegin.length, end);
  final sb = StringBuffer();
  final raw = data[posPrintStagesKey];
  if (raw != null && raw.trim().isNotEmpty) {
    try {
      final rows = jsonDecode(raw);
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          var line = block;
          row.forEach((k, v) {
            line = line.replaceAll('{$k}', _escapeHtml('${v ?? ''}'));
          });
          sb.write(line);
        }
      }
    } on FormatException {
      // JSON hỏng — bỏ bảng đợt.
    }
  }
  return html.replaceRange(begin, end + _stageEnd.length, sb.toString());
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
  var html = ensurePosPrintItemLoop(templateHtml);
  html = _expandStages(html, data);
  final begin = html.indexOf(_itemBegin);
  final end = html.indexOf(_itemEnd);
  if (begin >= 0 && end > begin) {
    final block = _withLineNoteAndDiscount(
      html.substring(begin + _itemBegin.length, end),
    );
    final rendered = StringBuffer();
    for (final line in lineItems) {
      final filled = Map<String, String>.from(line);
      filled['Sbox_Ghi_Chu'] = _lineNoteHtml(line['Ghi_Chu']);
      filled['Sbox_Chiet_Khau'] = _lineDiscountHtml(line['Chiet_Khau']);
      filled['Sbox_Hinh_Anh'] = line['Hinh_Anh'] ?? '';
      var row = block;
      for (final e in filled.entries) {
        row = _replacePrintToken(row, e.key, e.value);
      }
      for (final e in data.entries) {
        row = _replacePrintToken(row, e.key, e.value);
      }
      rendered.write(row);
    }
    html = html.replaceRange(begin, end + _itemEnd.length, rendered.toString());
  }

  html = applyPosPrintConditionals(html, data);
  for (final e in data.entries) {
    if (e.key == posPrintStagesKey) continue;
    html = html.replaceAll('{${e.key}}', e.value);
  }
  html = _dropZeroInvoiceDiscountRow(html, data['Chiet_Khau_Hoa_Don']);
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

String wrapPosPrintHtmlDocument(
  String bodyHtml, {
  required String paperSize,
  PosCommercialPageSetup? pageSetup,
}) {
  if (!PosPrintPaperSizes.isThermal(paperSize)) {
    final setup = pageSetup ??
        PosCommercialPageSetup.parse(
          bodyHtml,
          fallbackPaper: paperSize,
        );
    return wrapPosCommercialPrintHtml(bodyHtml, setup);
  }
  final width = PosPrintPaperSizes.widthMm(paperSize);
  return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
  @page { size: ${width}mm auto; margin: 2mm; }
  * { box-sizing: border-box; }
  body { width: ${width}mm; margin: 0 auto; font-family: Arial, sans-serif; color: #111; }
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
    ...posEInvoicePrintTokens(order),
  };
}

/// Biến in HĐĐT: {HDDT_Ky_Hieu} {HDDT_So} {HDDT_Ma_CQT} {HDDT_Ma_Tra_Cuu}
/// {HDDT_Link_Tra_Cuu} {HDDT_MST_Ban} {HDDT_QR}. Rỗng khi đơn chưa phát hành HĐĐT
/// hoặc cửa hàng tắt «In mã QR HĐĐT trên hóa đơn».
Map<String, String> posEInvoicePrintTokens(PosSaleOrder order) {
  final no = (order.eInvoiceNo ?? '').trim();
  final issued = (order.eInvoiceStatus ?? '').trim() == 'Issued';
  if (!issued || no.isEmpty || !order.eInvoicePrintOnReceipt) return const {};
  final lookup = (order.eInvoiceLookupUrl ?? '').trim();
  return {
    'HDDT_Ky_Hieu': (order.eInvoiceSeries ?? '').trim(),
    'HDDT_So': no,
    'HDDT_Ma_CQT': (order.eInvoiceCode ?? '').trim(),
    'HDDT_Ma_Tra_Cuu': (order.eInvoiceReservationCode ?? '').trim(),
    'HDDT_Link_Tra_Cuu': lookup,
    'HDDT_MST_Ban': (order.eInvoiceSellerTaxCode ?? '').trim(),
    'HDDT_QR': lookup.isNotEmpty ? lookup : 'https://hoadondientu.gdt.gov.vn',
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
    final dims = parsePosAreaDims(l.lineNote);
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
      'Chieu_Dai': formatPosDim(dims.length),
      'Chieu_Rong': formatPosDim(dims.width),
      'Chieu_Cao': formatPosDim(dims.height),
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
