import '../models/pos_print_template.dart';
import 'pos_commercial_templates.g.dart';

/// Phiên bản mẫu chuẩn A4 (báo giá, hợp đồng, bàn giao, nghiệm thu, đề nghị TT) — tăng mỗi khi sửa
/// `src/ZKTecoADMS.Api/PrintTemplates/A4/*.html`. Mẫu cửa hàng lưu từ bản cũ hơn → màn Mẫu in mời cập nhật.
/// 2: 10/10/2026 — bảng tổng khớp cột Thành tiền, ký tên thẳng hàng, bỏ dòng trống.
const kPosCommercialBaseRev = 2;

/// Phiên bản mẫu chuẩn mà mẫu [html] được tạo từ (thiếu = 1: trước khi có đánh số).
int posCommercialBaseRev(String html) => PosCommercialPageSetup.parse(html).baseRev;

/// Khổ + lề (mm) mẫu báo giá / hợp đồng — lưu trong `<!--POS_A4_V6 …-->`.
class PosCommercialPageSetup {
  const PosCommercialPageSetup({
    this.paperSize = PosPrintPaperSizes.a4,
    this.topMm = defaultMm,
    this.rightMm = defaultMm,
    this.bottomMm = defaultMm,
    this.leftMm = defaultMm,
    this.baseRev = 1,
  });

  static const defaultMm = 12.0;
  static const minMm = 5.0;
  static const maxMm = 30.0;

  final String paperSize;
  final double topMm;
  final double rightMm;
  final double bottomMm;
  final double leftMm;

  /// Mẫu chuẩn gốc — xem [kPosCommercialBaseRev].
  final int baseRev;

  bool get isA5 => paperSize == PosPrintPaperSizes.a5;

  /// CSS @ 96dpi — A4 210×297, A5 148×210.
  double get cssWidth => isA5 ? 559.0 : 794.0;
  double get cssHeight => isA5 ? 794.0 : 1123.0;

  String get paddingCss =>
      '${_fmt(topMm)}mm ${_fmt(rightMm)}mm ${_fmt(bottomMm)}mm ${_fmt(leftMm)}mm';

  PosCommercialPageSetup copyWith({
    String? paperSize,
    double? topMm,
    double? rightMm,
    double? bottomMm,
    double? leftMm,
    int? baseRev,
  }) {
    return PosCommercialPageSetup(
      paperSize: paperSize ?? this.paperSize,
      topMm: topMm ?? this.topMm,
      rightMm: rightMm ?? this.rightMm,
      bottomMm: bottomMm ?? this.bottomMm,
      leftMm: leftMm ?? this.leftMm,
      baseRev: baseRev ?? this.baseRev,
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(1);
  }

  static double _clampMm(double? v, [double fallback = defaultMm]) {
    final n = v ?? fallback;
    if (n.isNaN) return fallback;
    return n.clamp(minMm, maxMm);
  }

  static PosCommercialPageSetup parse(
    String html, {
    String? fallbackPaper,
  }) {
    final paper = PosPrintPaperSizes.normalizeCommercialPaper(
      _attr(html, 'paper') ?? fallbackPaper,
    );
    final margin = _attr(html, 'margin');
    if (margin != null) {
      final parts = margin.split(RegExp(r'[,\s]+')).where((s) => s.isNotEmpty);
      final nums = parts.map((s) => double.tryParse(s)).toList();
      if (nums.length >= 4 && nums.every((n) => n != null)) {
        return PosCommercialPageSetup(
          paperSize: paper,
          topMm: _clampMm(nums[0]),
          rightMm: _clampMm(nums[1]),
          bottomMm: _clampMm(nums[2]),
          leftMm: _clampMm(nums[3]),
        );
      }
    }
    return PosCommercialPageSetup(
      paperSize: paper,
      topMm: _clampMm(double.tryParse(_attr(html, 'mt') ?? '')),
      rightMm: _clampMm(double.tryParse(_attr(html, 'mr') ?? '')),
      bottomMm: _clampMm(double.tryParse(_attr(html, 'mb') ?? '')),
      leftMm: _clampMm(double.tryParse(_attr(html, 'ml') ?? '')),
      baseRev: int.tryParse(_attr(html, 'rev') ?? '') ?? 1,
    );
  }

  static String? _attr(String html, String name) {
    final m = RegExp(
      '''<!--POS_A4_V\\d+[^>]*\\b$name=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    return m?.group(1);
  }

  /// Gắn / ghi đè comment khổ + lề ở đầu HTML (không đụng nội dung).
  String applyToHtml(String html) {
    final body = html
        .replaceFirst(RegExp(r'<!--POS_A4_V\d+[^>]*-->'), '')
        .replaceFirst(RegExp(r'<!--POS_PAGE[^>]*-->'), '');
    return '<!--POS_A4_V9 paper="$paperSize" mt="${_fmt(topMm)}" '
        'mr="${_fmt(rightMm)}" mb="${_fmt(bottomMm)}" '
        'ml="${_fmt(leftMm)}" rev="$baseRev"-->$body';
  }
}

/// HTML in A4/A5 — Times + lề (trùng Soạn / Xem / In thử).
/// CSS NỘI DUNG dùng chung cho khung soạn A4, xem trước và bản in — soạn thấy sao in ra vậy.
/// Bảng không bao giờ tràn khổ giấy: bỏ bố cục cột cố định (tổng cột px > trang sẽ tràn),
/// giới hạn tối đa bằng vùng chữ; cột vẫn theo tỉ lệ đã đặt.
const posCommercialContentCss = r'''
  body{font-family:"Times New Roman",Times,serif;font-size:13px;line-height:1.15;color:#111;
    word-wrap:break-word;overflow-wrap:break-word;}
  h1,h2,h3{text-align:center;margin:8px 0;}
  h2{font-size:16px;font-weight:700;text-transform:uppercase;letter-spacing:0.2px;margin:4px 0;}
  h3{font-size:13px;font-weight:700;text-align:left;margin:6px 0 1px;text-transform:none;}
  p{margin:2px 0;text-indent:0;}
  b,strong{font-weight:700;}
  table{border-collapse:collapse;width:100%;max-width:100% !important;table-layout:auto !important;margin:8px 0;}
  col{max-width:100%;}
  th,td{padding:4px 5px;vertical-align:top;word-wrap:break-word;overflow-wrap:anywhere;min-width:0;}
  img{max-width:100%;height:auto;}
''';

String wrapPosCommercialPrintHtml(
  String bodyHtml,
  PosCommercialPageSetup setup,
) {
  final inner = bodyHtml
      .replaceAll(RegExp(r'</script', caseSensitive: false), '<\\/script')
      .replaceAll(RegExp(r'</body', caseSensitive: false), '<\\/body');
  final page = setup.isA5 ? 'A5' : 'A4';
  final maxW = setup.isA5 ? '148mm' : '210mm';
  return '''
<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  @page { size: $page portrait; margin: 0; }
  html,body{margin:0;background:#fff;}
$posCommercialContentCss
  body{
    padding:${setup.paddingCss};
    box-sizing:border-box;
    max-width:$maxW;
    margin:0 auto;
    overflow-x:hidden;
  }
  @media print { body { -webkit-print-color-adjust: exact; print-color-adjust: exact; } }
</style>
</head><body>$inner</body></html>
''';
}

/// HTML mẫu in mặc định (fallback khi API chưa có dữ liệu).
String posPrintDefaultHtml({
  String documentType = PosPrintDocumentTypes.saleInvoice,
  String paperSize = PosPrintPaperSizes.k80,
}) {
  if (PosPrintDocumentTypes.isCommercial(documentType)) {
    final setup = PosCommercialPageSetup(
      paperSize: PosPrintPaperSizes.normalizeCommercialPaper(paperSize),
      baseRev: kPosCommercialBaseRev,
    );
    return setup.applyToHtml(_commercialA4(documentType));
  }
  final title = _docTitle(documentType);
  if (PosPrintPaperSizes.isThermal(paperSize)) {
    return _thermalHtml(title, paperSize);
  }
  return _sheetHtml(title, paperSize);
}

String _docTitle(String documentType) {
  switch (documentType) {
    case PosPrintDocumentTypes.saleOrder:
      return 'HÓA ĐƠN ĐẶT HÀNG';
    case PosPrintDocumentTypes.delivery:
      return 'PHIẾU GIAO HÀNG';
    case PosPrintDocumentTypes.purchaseReceipt:
      return 'PHIẾU NHẬP HÀNG';
    case PosPrintDocumentTypes.stockIssue:
      return 'PHIẾU BÁO XUẤT KHO';
    case PosPrintDocumentTypes.quote:
      return 'BÁO GIÁ';
    case PosPrintDocumentTypes.contract:
      return 'HỢP ĐỒNG';
    case PosPrintDocumentTypes.handover:
      return 'BIÊN BẢN BÀN GIAO';
    case PosPrintDocumentTypes.acceptance:
      return 'BIÊN BẢN NGHIỆM THU';
    case PosPrintDocumentTypes.paymentRequest:
      return 'ĐỀ NGHỊ THANH TOÁN';
    default:
      return 'HÓA ĐƠN BÁN HÀNG';
  }
}

String _thermalHtml(String title, String paperSize) {
  final width = paperSize == PosPrintPaperSizes.k58 ? '58mm' : '80mm';
  final fs = paperSize == PosPrintPaperSizes.k58 ? '13px' : '14px';
  final titleFs = paperSize == PosPrintPaperSizes.k58 ? '18px' : '20px';
  final storeFs = paperSize == PosPrintPaperSizes.k58 ? '16px' : '18px';
  return '''
<div style="width:$width;max-width:100%;box-sizing:border-box;margin:0 auto;padding:0 1mm;font-family:Arial,sans-serif;font-size:$fs;color:#000">
  <div style="text-align:center">
    <div style="font-weight:bold;font-size:$storeFs">{Ten_Cua_Hang}</div>
    <div>{Dia_Chi_Chi_Nhanh}</div>
    <div>ĐT: {Dien_Thoai_Chi_Nhanh}</div>
    <div style="font-weight:bold;font-size:$titleFs;margin-top:6px">$title</div>
  </div>
  <div style="margin:6px 0;border-top:2px solid #000"></div>
  <div><b>Bàn:</b> {Ten_Ban}</div>
  <div><b>Số HĐ:</b> {Ma_Don_Hang}</div>
  <div><b>Ngày:</b> {Ngay}</div>
  <div>KH: {Khach_Hang}</div>
  <div style="margin:6px 0;border-top:2px solid #000"></div>
  <table style="width:100%;border-collapse:collapse;font-size:$fs">
    <thead><tr style="border-bottom:2px solid #000">
      <th style="text-align:left;padding:3px 2px">Tên hàng</th>
      <th style="text-align:center;width:12%;padding:3px 2px">SL</th>
      <th style="text-align:right;width:24%;padding:3px 2px">Đ.giá</th>
      <th style="text-align:right;width:26%;padding:3px 2px">TT</th>
    </tr></thead>
    <tbody><!--BEGIN_ITEMS-->
      <tr style="border-bottom:1px dotted #555">
        <td style="padding:5px 2px 3px;font-weight:bold;vertical-align:top">{Ten_Hang_Hoa}</td>
        <td style="text-align:center;vertical-align:top;padding:5px 2px">{So_Luong}</td>
        <td style="text-align:right;vertical-align:top;padding:5px 2px">{Don_Gia}</td>
        <td style="text-align:right;vertical-align:top;padding:5px 2px;font-weight:bold">{Thanh_Tien}</td>
      </tr><!--END_ITEMS-->
    </tbody>
  </table>
  <div style="margin:6px 0;border-top:2px solid #000"></div>
  <div style="display:flex;justify-content:space-between"><span>Tổng tiền hàng</span><b>{Tong_Tien_Hang}</b></div>
  <div style="display:flex;justify-content:space-between;font-weight:bold;font-size:${paperSize == PosPrintPaperSizes.k58 ? '16px' : '18px'}"><span>TỔNG CỘNG</span><span>{Tong_Cong}</span></div>
  <div style="margin-top:8px;text-align:center;font-weight:bold">Cảm ơn quý khách!</div>
</div>''';
}

String _sheetHtml(String title, String paperSize) {
  final pad = paperSize == PosPrintPaperSizes.a5 ? '12px' : '20px';
  return '''
<div style="font-family:Arial,sans-serif;font-size:11px;color:#000;padding:$pad">
  <table style="width:100%;border-collapse:collapse"><tr>
    <td style="width:60%;vertical-align:top">
      <div style="font-weight:bold;font-size:16px">{Ten_Cua_Hang}</div>
      <div>{Dia_Chi_Chi_Nhanh}</div><div>ĐT: {Dien_Thoai_Chi_Nhanh}</div></td>
    <td style="text-align:right;vertical-align:top">
      <div style="font-weight:bold;font-size:18px">$title</div>
      <div>Số: <b>{Ma_Don_Hang}</b> / {Ma_Bao_Gia}</div><div>Ngày: {Ngay} {Gio}</div></td></tr></table>
  <div style="margin:12px 0;padding:8px;border:1px solid #ddd">
    <div><b>Khách hàng:</b> {Khach_Hang} &nbsp; <b>SĐT:</b> {SDT}</div>
    <div><b>Địa chỉ:</b> {Dia_Chi_Khach_Hang}</div>
    <div><b>Thanh toán:</b> {Hinh_Thuc_Thanh_Toan} &nbsp; <b>Hạn BG:</b> {Han_Bao_Gia}</div>
  </div>
  <table style="width:100%;border-collapse:collapse;border:1px solid #ccc;margin-top:12px">
    <thead><tr style="background:#f3f4f6">
      <th style="border:1px solid #ccc;padding:6px">STT</th>
      <th style="border:1px solid #ccc;padding:6px">Mã hàng</th>
      <th style="border:1px solid #ccc;padding:6px">Tên hàng</th>
      <th style="border:1px solid #ccc;padding:6px">BH</th>
      <th style="border:1px solid #ccc;padding:6px;text-align:right">Đơn giá</th>
      <th style="border:1px solid #ccc;padding:6px;text-align:center">SL</th>
      <th style="border:1px solid #ccc;padding:6px;text-align:right">Thành tiền</th>
    </tr></thead>
    <tbody><!--BEGIN_ITEMS-->
      <tr>
        <td style="border:1px solid #ccc;padding:5px;text-align:center">{STT}</td>
        <td style="border:1px solid #ccc;padding:5px">{Ma_Hang}</td>
        <td style="border:1px solid #ccc;padding:5px">{Ten_Hang_Hoa}</td>
        <td style="border:1px solid #ccc;padding:5px">{Bao_Hanh}</td>
        <td style="border:1px solid #ccc;padding:5px;text-align:right">{Don_Gia}</td>
        <td style="border:1px solid #ccc;padding:5px;text-align:center">{So_Luong}</td>
        <td style="border:1px solid #ccc;padding:5px;text-align:right">{Thanh_Tien}</td>
      </tr><!--END_ITEMS-->
    </tbody>
  </table>
  <div style="text-align:right;margin-top:12px">
    <div>Tổng tiền hàng: <b>{Tong_Tien_Hang}</b></div>
    <div>Chiết khấu: <b>{Chiet_Khau_Hoa_Don}</b></div>
    <div>Thuế: <b>{Tien_Thue}</b></div>
    <div>Tổng cộng: <b>{Tong_Cong}</b></div>
    <div style="font-style:italic">{Tong_Cong_Bang_Chu}</div>
  </div>
  <div style="margin-top:10px"><b>Điều khoản:</b> {Dieu_Khoan}</div>
</div>''';
}

/// Mẫu A4 chứng từ — sinh từ src/ZKTecoADMS.Api/PrintTemplates/A4 (một nguồn với API).
String _commercialA4(String documentType) {
  switch (documentType) {
    case PosPrintDocumentTypes.contract:
      return posA4ContractHtml;
    case PosPrintDocumentTypes.acceptance:
      return posA4AcceptanceHtml;
    case PosPrintDocumentTypes.handover:
      return posA4HandoverHtml;
    case PosPrintDocumentTypes.paymentRequest:
      return posA4PaymentRequestHtml;
    default:
      return posA4QuoteHtml;
  }
}

/// Mẫu A4 cũ / quốc hiệu nhân đôi / báo giá còn gắn quốc hiệu — thay mẫu chuẩn.
bool posCommercialHtmlLooksStale(String html) {
  if (!html.contains('{Ten_Hang_Hoa}') && !html.contains('BEGIN_ITEMS')) {
    return false;
  }
  const motto = 'CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM';
  if (motto.allMatches(html).length >= 2) return true;
  // BBG mẫu thật không có quốc hiệu — mẫu V5 2 cột còn gắn.
  if (html.contains('BẢNG BÁO GIÁ') && html.contains(motto)) return true;
  if (html.contains('BẢNG BÁO GIÁ') && !html.contains('{Hinh_Anh}')) return true;
  return !RegExp(r'<!--POS_A4_V(?:9|\d{2,})', caseSensitive: false)
      .hasMatch(html);
}

String posPrintDefaultTemplateName(String paperSize, {String? documentType}) {
  final doc = PosPrintDocumentTypes.all[documentType ?? ''] ?? 'Mẫu in';
  final short = switch (paperSize) {
    PosPrintPaperSizes.k58 => 'K58',
    PosPrintPaperSizes.k80 => 'K80',
    PosPrintPaperSizes.a5 => 'A5',
    PosPrintPaperSizes.a4 => 'A4',
    PosPrintPaperSizes.label50x30 || 'roll_1_50x30' => '50×30',
    PosPrintPaperSizes.label40x30 || 'roll_1_40x30' => '40×30',
    _ => paperSize,
  };
  return '$doc 1 ($short)';
}
