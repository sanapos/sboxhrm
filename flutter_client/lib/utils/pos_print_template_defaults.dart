import '../models/pos_print_template.dart';

/// Khổ + lề (mm) mẫu báo giá / hợp đồng — lưu trong `<!--POS_A4_V6 …-->`.
class PosCommercialPageSetup {
  const PosCommercialPageSetup({
    this.paperSize = PosPrintPaperSizes.a4,
    this.topMm = defaultMm,
    this.rightMm = defaultMm,
    this.bottomMm = defaultMm,
    this.leftMm = defaultMm,
  });

  static const defaultMm = 12.0;
  static const minMm = 5.0;
  static const maxMm = 30.0;

  final String paperSize;
  final double topMm;
  final double rightMm;
  final double bottomMm;
  final double leftMm;

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
  }) {
    return PosCommercialPageSetup(
      paperSize: paperSize ?? this.paperSize,
      topMm: topMm ?? this.topMm,
      rightMm: rightMm ?? this.rightMm,
      bottomMm: bottomMm ?? this.bottomMm,
      leftMm: leftMm ?? this.leftMm,
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
        'ml="${_fmt(leftMm)}"-->$body';
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

/// Bảng hạng mục 7 cột — width trên từng ô (flutter_html bỏ qua colgroup).
const _itemTable = '''
<table style="width:100%;border-collapse:collapse;table-layout:fixed;margin:8px 0;font-size:12px;line-height:1.3">
<colgroup>
<col width="46"/><col width="216"/><col width="62"/><col width="62"/>
<col width="108"/><col width="108"/><col width="62"/><col width="108"/>
</colgroup>
<thead><tr style="background:#f3f4f6">
<th style="width:6%;border:1px solid #111;padding:5px 2px;text-align:center;white-space:nowrap"><b>STT</b></th>
<th style="width:28%;border:1px solid #111;padding:4px 4px;text-align:left"><b>Tên hàng</b></th>
<th style="width:8%;border:1px solid #111;padding:5px 2px;text-align:center;white-space:nowrap"><b>ĐVT</b></th>
<th style="width:8%;border:1px solid #111;padding:5px 2px;text-align:center;white-space:nowrap"><b>SL</b></th>
<th style="width:14%;border:1px solid #111;padding:5px 3px;text-align:right;white-space:nowrap"><b>Đơn giá</b></th>
<th style="width:14%;border:1px solid #111;padding:5px 3px;text-align:right;white-space:nowrap"><b>Thành tiền</b></th>
<th style="width:8%;border:1px solid #111;padding:5px 2px;text-align:center;white-space:nowrap"><b>BH</b></th>
<th style="width:14%;border:1px solid #111;padding:4px 2px;text-align:center"><b>Ảnh</b></th>
</tr></thead>
<tbody><!--BEGIN_ITEMS-->
<tr>
<td style="width:6%;border:1px solid #111;padding:5px 2px;text-align:center;vertical-align:middle">{STT}</td>
<td style="width:28%;border:1px solid #111;padding:5px 4px;text-align:left;vertical-align:middle">{Ten_Hang_Hoa}</td>
<td style="width:8%;border:1px solid #111;padding:5px 2px;text-align:center;vertical-align:middle">{Don_Vi_Tinh}</td>
<td style="width:8%;border:1px solid #111;padding:5px 2px;text-align:center;vertical-align:middle">{So_Luong}</td>
<td style="width:14%;border:1px solid #111;padding:5px 3px;text-align:right;vertical-align:middle">{Don_Gia}</td>
<td style="width:14%;border:1px solid #111;padding:5px 3px;text-align:right;vertical-align:middle">{Thanh_Tien}</td>
<td style="width:8%;border:1px solid #111;padding:5px 2px;text-align:center;vertical-align:middle">{Bao_Hanh}</td>
<td style="width:14%;border:1px solid #111;padding:3px;text-align:center;vertical-align:middle">{Hinh_Anh}</td>
</tr><!--END_ITEMS-->
</tbody>
<tfoot>
<tr><td colspan="5" style="border:1px solid #111;padding:5px 6px;text-align:right">Tổng tiền hàng</td>
<td colspan="3" style="border:1px solid #111;padding:5px 6px;text-align:right"><b>{Tong_Tien_Hang}</b></td></tr>
<tr><td colspan="5" style="border:1px solid #111;padding:5px 6px;text-align:right">Chiết khấu</td>
<td colspan="3" style="border:1px solid #111;padding:5px 6px;text-align:right">{Chiet_Khau_Hoa_Don}</td></tr>
<tr><td colspan="5" style="border:1px solid #111;padding:5px 6px;text-align:right">Thuế GTGT</td>
<td colspan="3" style="border:1px solid #111;padding:5px 6px;text-align:right">{Tien_Thue}</td></tr>
<tr style="background:#f8fafc"><td colspan="5" style="border:1px solid #111;padding:6px 6px;text-align:right"><b>TỔNG CỘNG</b></td>
<td colspan="3" style="border:1px solid #111;padding:6px 6px;text-align:right"><b>{Tong_Cong}</b></td></tr>
</tfoot></table>''';

/// Bảng nghiệm thu 6 cột, không rowspan (tránh lệch cột trên điện thoại).
const _acceptanceTable = '''
<table style="width:100%;border-collapse:collapse;table-layout:fixed;margin:8px 0;font-size:11px;line-height:1.3">
<colgroup>
<col width="62"/><col width="277"/><col width="77"/>
<col width="100"/><col width="100"/><col width="154"/>
</colgroup>
<thead><tr style="background:#f3f4f6">
<th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">STT</th>
<th style="width:36%;border:1px solid #111;padding:4px 4px;text-align:left">Hạng mục</th>
<th style="width:10%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">ĐVT</th>
<th style="width:13%;border:1px solid #111;padding:4px 2px;text-align:center">KL HĐ</th>
<th style="width:13%;border:1px solid #111;padding:4px 2px;text-align:center">KL thực tế</th>
<th style="width:20%;border:1px solid #111;padding:4px 4px;text-align:left">Ghi chú</th>
</tr></thead>
<tbody><!--BEGIN_ITEMS-->
<tr>
<td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{STT}</td>
<td style="width:36%;border:1px solid #111;padding:4px 4px;text-align:left;vertical-align:middle">{Ten_Hang_Hoa}</td>
<td style="width:10%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{Don_Vi_Tinh}</td>
<td style="width:13%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{So_Luong}</td>
<td style="width:13%;border:1px solid #111;padding:4px 2px;text-align:center;vertical-align:middle">{So_Luong}</td>
<td style="width:20%;border:1px solid #111;padding:4px 4px;vertical-align:middle">{Ghi_Chu}</td>
</tr><!--END_ITEMS-->
</tbody></table>''';

/// Quốc hiệu — chỉ div (không table) để preview/in không nhân đôi.
const _motto = '''
<div style="text-align:center;line-height:1.15;font-size:13px">
<b>CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM</b><br/>
<b><i>Độc lập – Tự do – Hạnh phúc</i></b>
<div style="letter-spacing:1px;margin:2px 0 4px">________________</div>
</div>''';

String _center(String inner, {int fontSize = 13}) =>
    '<div style="text-align:center;font-size:${fontSize}px;line-height:1.15;margin:4px 0 2px">$inner</div>';

/// Header 2 cột: công ty trái — quốc hiệu + ngày phải (BBNT, đề nghị TT).
String _twoColHeader({String leftExtra = '', String dateLine = 'Ngày {Ngay}'}) => '''
<table style="width:100%;border-collapse:collapse;border:none;margin:0 0 10px">
<tr>
<td style="width:50%;vertical-align:top;padding:0 12px 0 0;border:none;line-height:1.35">
<div style="font-size:14px;font-weight:700;text-transform:uppercase">{Ten_Cong_Ty}</div>
$leftExtra
</td>
<td style="width:50%;vertical-align:top;border:none;padding:0">
$_motto
<div style="text-align:center;font-size:13px">$dateLine</div>
</td></tr></table>''';

String _commercialA4(String documentType) {
  switch (documentType) {
    case PosPrintDocumentTypes.contract:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
$_motto
${_center('<b>HỢP ĐỒNG THI CÔNG</b>', fontSize: 18)}
${_center('Số HĐ: <b>{So_Hop_Dong}</b> · Theo báo giá: <b>{Ma_Bao_Gia}</b>')}

<p>- Căn cứ Bộ luật Dân sự số 91/2015/QH13 ngày 24/11/2015;<br/>
- Căn cứ Luật Thương mại số 36/2005/QH11 ngày 14/6/2005;<br/>
- Căn cứ theo nhu cầu của các bên.</p>

<p>Hợp đồng này được ký kết vào ngày <b>{Ngay}</b> giữa hai đơn vị sau đây:</p>

<p style="margin:6px 0"><b>BÊN A (Chủ đầu tư): {Ten_Cong_Ty_Khach}</b><br/>
Mã số thuế: {MST_Khach_Hang}<br/>
Địa chỉ: {Dia_Chi_Khach_Hang}<br/>
Điện thoại: {SDT}<br/>
Tài khoản số: {Tai_Khoan_Khach_Hang} — {Ngan_Hang_Khach_Hang}<br/>
Đại diện: <b>{Nguoi_Dai_Dien_Khach}</b> — Chức vụ: {Chuc_Vu_Khach}</p>

<p style="margin:6px 0"><b>BÊN B (Nhà thầu): {Ten_Cong_Ty}</b><br/>
Mã số thuế: {MST_Cua_Hang}<br/>
Địa chỉ: {Dia_Chi_Cong_Ty}<br/>
Điện thoại: {Dien_Thoai_Cong_Ty}<br/>
Tài khoản số: {Tai_Khoan_Cua_Hang} — {Ngan_Hang_Cua_Hang}<br/>
Đại diện: <b>{Nguoi_Dai_Dien_Cua_Hang}</b> — Chức vụ: {Chuc_Vu_Cua_Hang}</p>

<p>Sau khi thỏa thuận và thống nhất, Bên A đồng ý giao cho Bên B cung cấp, lắp đặt các hạng mục dưới đây, hai bên ký kết hợp đồng với các điều khoản sau:</p>

<p><b>Điều 1: Hạng mục thi công &amp; giá trị hợp đồng</b><br/>
Địa điểm thi công: {Dia_Diem_Thi_Cong}</p>
$_itemTable
<p>Giá trị hợp đồng: <b>{Tong_Cong} VNĐ</b><br/>
<i>Bằng chữ: {Tong_Cong_Bang_Chu}</i>.<br/>
Trọn gói vật tư, nhân công, vận chuyển, lắp đặt và đã bao gồm thuế GTGT.</p>

<p><b>Điều 2: Thời gian &amp; phương thức thanh toán</b><br/>
Hình thức: {Hinh_Thuc_Thanh_Toan}.<br/>
Đợt 1: Bên A tạm ứng 50% giá trị hợp đồng — <b>{Tam_Ung} VNĐ</b> trong vòng {Ky_Han_Thanh_Toan}.<br/>
Đợt 2: Bên A thanh toán phần còn lại <b>{Con_Lai_Hop_Dong} VNĐ</b> sau khi Bên B hoàn thành và hai bên ký biên bản nghiệm thu. Hồ sơ gồm: hồ sơ nghiệm thu, đề nghị thanh toán, hóa đơn GTGT.</p>

<p><b>Điều 3: Thời gian thi công</b><br/>
Dự kiến {Ky_Han_Thi_Cong} kể từ ngày Bên B nhận được tạm ứng theo Điều 2. Trừ trường hợp bất khả kháng.</p>

<p><b>Điều 4: Bảo hành</b><br/>
{Bao_Hanh}. {Dieu_Khoan}</p>

<p><b>Điều 5: Quyền &amp; nghĩa vụ các bên</b><br/>
Bên A: kiểm tra chất lượng, thanh toán đúng hạn.<br/>
Bên B: đảm bảo chất lượng, tiến độ, hồ sơ hợp lệ, bảo hành theo Điều 4.</p>

<p><b>Điều 6: Điều khoản chung</b><br/>
Hợp đồng lập thành 02 bản, mỗi bên giữ 01 bản, có giá trị pháp lý như nhau. Hai bên cam kết thực hiện đúng thỏa thuận.</p>

<table style="width:100%;border-collapse:collapse;border:none;margin-top:32px"><colgroup><col width="385"/><col width="385"/></colgroup><tr>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN BÊN A</b><br/><i>(Ký, ghi rõ họ tên)</i>
<br/><br/><br/><br/>
<b>{Nguoi_Dai_Dien_Khach}</b></td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN BÊN B</b><br/><i>(Ký, ghi rõ họ tên)</i>
<div style="text-align:center">{Con_Dau}</div>
<b>{Nguoi_Dai_Dien_Cua_Hang}</b></td>
</tr></table></div>''';

    case PosPrintDocumentTypes.acceptance:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
${_twoColHeader()}
${_center('<b>BIÊN BẢN NGHIỆM THU HOÀN THÀNH</b><br/><b>BÀN GIAO SẢN PHẨM ĐƯA VÀO SỬ DỤNG</b>', fontSize: 16)}

<p><b>1. Đối tượng nghiệm thu</b><br/>
- Tên hạng mục công trình: {Ten_Hang_Hoa}<br/>
- Địa điểm thi công: {Dia_Diem_Thi_Cong}<br/>
- Căn cứ hợp đồng số: <b>{So_Hop_Dong}</b> ký ngày {Ngay_Hop_Dong}</p>

<p><b>2. Thành phần trực tiếp nghiệm thu</b></p>
<p>● <b>Chủ đầu tư: {Ten_Cong_Ty_Khach}</b><br/>
- Mã số thuế: {MST_Khach_Hang}<br/>
- Địa chỉ: {Dia_Chi_Khach_Hang}<br/>
- Đại diện: {Nguoi_Dai_Dien_Khach} — Chức vụ: {Chuc_Vu_Khach}</p>
<p>● <b>Nhà thầu thi công: {Ten_Cong_Ty}</b><br/>
- Mã số thuế: {MST_Cua_Hang}<br/>
- Địa chỉ: {Dia_Chi_Cong_Ty}<br/>
- Đại diện: {Nguoi_Dai_Dien_Cua_Hang} — Chức vụ: {Chuc_Vu_Cua_Hang}</p>

<p><b>3. Thời gian nghiệm thu</b><br/>
- Bắt đầu: … giờ … ngày {Ngay}<br/>
- Kết thúc: … giờ … ngày {Ngay}<br/>
- Tại: Hiện trường công trình.</p>

<p><b>4. Đánh giá công việc xây dựng đã thực hiện</b><br/>
a. Tài liệu căn cứ: Hợp đồng số {So_Hop_Dong}, quy trình nghiệm thu đã thống nhất, các tiêu chuẩn thi công liên quan.<br/>
b. Khối lượng công việc:</p>
$_acceptanceTable
<p>c. Chất lượng công việc thi công: <b>Đạt yêu cầu.</b><br/>
d. Các ý kiến khác: {Ghi_Chu}</p>

<p><b>5. Giá trị quyết toán</b><br/>
Tổng giá trị quyết toán: <b>{Tong_Cong} VNĐ</b><br/>
<i>Bằng chữ: {Tong_Cong_Bang_Chu}.</i></p>

<p><b>6. Kết luận</b><br/>
- Chấp nhận nghiệm thu hoàn toàn hạng mục công trình và đưa vào sử dụng.<br/>
- Các bên trực tiếp nghiệm thu chịu trách nhiệm trước pháp luật về quyết định nghiệm thu và quyết toán này.<br/>
- Biên bản nghiệm thu này được lập thành 02 (hai) bản, mỗi bên 01 (một) bản, có giá trị pháp lý như nhau.</p>

<table style="width:100%;border-collapse:collapse;border:none;margin-top:32px"><colgroup><col width="385"/><col width="385"/></colgroup><tr>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN CHỦ ĐẦU TƯ</b><br/>{Chuc_Vu_Khach}
<br/><br/><br/><br/>
<b>{Nguoi_Dai_Dien_Khach}</b></td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN NHÀ THẦU THI CÔNG</b><br/>{Chuc_Vu_Cua_Hang}
<div style="text-align:center">{Con_Dau}</div>
<b>{Nguoi_Dai_Dien_Cua_Hang}</b></td>
</tr></table></div>''';

    case PosPrintDocumentTypes.handover:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
${_twoColHeader()}
${_center('<b>BIÊN BẢN BÀN GIAO CÔNG TRÌNH</b>', fontSize: 18)}
${_center('Số: <b>{So_Chung_Tu}</b> · Theo HĐ: {So_Hop_Dong} · Báo giá: {Ma_Bao_Gia}')}

<p><b>Bên giao (Nhà thầu): {Ten_Cong_Ty}</b><br/>
Mã số thuế: {MST_Cua_Hang} · ĐT: {Dien_Thoai_Cong_Ty}<br/>
Địa chỉ: {Dia_Chi_Cong_Ty}<br/>
Đại diện: {Nguoi_Dai_Dien_Cua_Hang} — {Chuc_Vu_Cua_Hang}</p>

<p><b>Bên nhận (Chủ đầu tư): {Ten_Cong_Ty_Khach}</b><br/>
Mã số thuế: {MST_Khach_Hang} · ĐT: {SDT}<br/>
Địa chỉ: {Dia_Chi_Khach_Hang}<br/>
Đại diện: {Nguoi_Dai_Dien_Khach} — {Chuc_Vu_Khach}</p>

<p><b>Địa điểm bàn giao:</b> {Dia_Diem_Thi_Cong}<br/>
<b>Thời gian bàn giao:</b> ngày {Ngay}.</p>

<p><b>Danh mục hạng mục bàn giao:</b></p>
$_itemTable

<p>Bên nhận đã kiểm tra hiện trường, xác nhận hạng mục đúng chủng loại, số lượng, chất lượng.<br/>
Bảo hành: {Bao_Hanh}. {Dieu_Khoan}<br/>
Ghi chú: {Ghi_Chu}</p>

<p>Biên bản lập thành 02 bản, mỗi bên giữ 01 bản có giá trị pháp lý như nhau.</p>

<table style="width:100%;border-collapse:collapse;border:none;margin-top:32px"><colgroup><col width="385"/><col width="385"/></colgroup><tr>
<td style="width:50%;text-align:center;vertical-align:top">
<b>BÊN NHẬN (Chủ đầu tư)</b><br/><i>(Ký, ghi rõ họ tên)</i>
<br/><br/><br/><br/>
<b>{Nguoi_Dai_Dien_Khach}</b></td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>BÊN GIAO (Nhà thầu)</b><br/><i>(Ký, ghi rõ họ tên)</i>
<div style="text-align:center">{Con_Dau}</div>
<b>{Nguoi_Dai_Dien_Cua_Hang}</b></td>
</tr></table></div>''';

    case PosPrintDocumentTypes.paymentRequest:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
${_twoColHeader(leftExtra: '<div style="font-style:italic;margin-top:4px">Số: {So_Chung_Tu}</div>')}
${_center('<b>ĐỀ NGHỊ THANH TOÁN</b>', fontSize: 18)}
${_center('<i>V/v: Thanh toán theo hợp đồng số {So_Hop_Dong}</i>')}

<p><b>Kính gửi:</b> {Ten_Cong_Ty_Khach}</p>

<p>Căn cứ theo hợp đồng số <b>{So_Hop_Dong}</b> ký ngày {Ngay_Hop_Dong} giữa {Ten_Cong_Ty_Khach} và {Ten_Cong_Ty} về việc {Ten_Hang_Hoa}.</p>

<p>Đến nay, Công ty chúng tôi đã hoàn tất triển khai / bàn giao theo danh sách chi tiết dưới đây (đính kèm biên bản nghiệm thu / đối soát):</p>

$_itemTable

<p>Nay kính đề nghị Quý Công ty thanh toán cho chúng tôi các khoản sau:</p>
<p>- Giá trị đề nghị thanh toán: <b>{Tong_Cong} VNĐ</b><br/>
<i>(Bằng chữ: {Tong_Cong_Bang_Chu})</i><br/>
- Hình thức thanh toán: {Hinh_Thuc_Thanh_Toan}<br/>
&nbsp;&nbsp;+ Số tài khoản: <b>{Tai_Khoan_Cua_Hang}</b><br/>
&nbsp;&nbsp;+ Ngân hàng: {Ngan_Hang_Cua_Hang}<br/>
&nbsp;&nbsp;+ Chủ tài khoản: {Chu_Tai_Khoan_Cua_Hang}</p>

<p>Rất mong Quý Công ty xem xét, đối chiếu và thanh toán theo đúng tiến độ đã thỏa thuận.</p>

<p><b>Trân trọng!</b></p>

<table style="width:100%;border-collapse:collapse;border:none;margin-top:32px"><colgroup><col width="385"/><col width="385"/></colgroup><tr>
<td style="width:50%"></td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN {Ten_Cong_Ty}</b><br/>{Chuc_Vu_Cua_Hang}
<div style="text-align:center">{Con_Dau}</div>
<b>{Nguoi_Dai_Dien_Cua_Hang}</b></td>
</tr></table></div>''';

    default: // quote — letterhead công ty, dấu treo chữ ký.
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:12.5px;color:#111;line-height:1.35">
<div style="border-bottom:1.5px solid #111;padding-bottom:6px;margin-bottom:8px">
<table style="width:100%;border-collapse:collapse;border:none"><tr>
<td style="width:88px;vertical-align:middle;border:none;padding:0 10px 0 0">{Logo}</td>
<td style="vertical-align:middle;border:none;padding:0">
<div style="font-size:16px;font-weight:700;text-transform:uppercase;letter-spacing:0.2px">{Ten_Cong_Ty}</div>
<div>MST: {MST_Cua_Hang} · ĐT: {Dien_Thoai_Cong_Ty}</div>
<div>{Dia_Chi_Cong_Ty}</div>
<div>{Dong_Email}</div>
</td></tr></table>
</div>
<div style="text-align:center;font-size:18px;font-weight:700;letter-spacing:1.2px;margin:2px 0">BẢNG BÁO GIÁ</div>
<div style="text-align:center;font-size:12px;margin-bottom:6px">Số: <b>{So_Chung_Tu}</b> · Ngày {Ngay} · Hiệu lực đến: <b>{Han_Bao_Gia}</b></div>

<table style="width:100%;border-collapse:collapse;margin:4px 0 8px;font-size:12.5px">
<tr>
<td style="width:22%;padding:2px 8px 2px 0;vertical-align:top"><b>Kính gửi</b></td>
<td style="padding:2px 0;vertical-align:top">{Ten_Cong_Ty_Khach}</td>
</tr>
<tr>
<td style="padding:2px 8px 2px 0;vertical-align:top"><b>Địa chỉ</b></td>
<td style="padding:2px 0;vertical-align:top">{Dia_Chi_Khach_Hang}</td>
</tr>
<tr>
<td style="padding:2px 8px 2px 0;vertical-align:top"><b>Điện thoại</b></td>
<td style="padding:2px 0;vertical-align:top">{SDT}</td>
</tr>
<tr>
<td style="padding:2px 8px 2px 0;vertical-align:top"><b>Thanh toán</b></td>
<td style="padding:2px 0;vertical-align:top">{Hinh_Thuc_Thanh_Toan}</td>
</tr>
</table>

<p style="margin:4px 0 6px">Kính gửi Quý khách bảng báo giá chi tiết như sau:</p>
$_itemTable
<div style="text-align:right;font-size:12px;font-style:italic;margin:2px 0 8px">Bằng chữ: {Tong_Cong_Bang_Chu}</div>

<div style="font-size:12.5px;line-height:1.4;margin:4px 0 8px">
<b>Điều khoản:</b> {Dieu_Khoan}<br/>
<b>Bảo hành:</b> {Bao_Hanh}<br/>
<b>Ghi chú:</b> {Ghi_Chu}
</div>
<p style="margin:4px 0 0">Rất mong nhận được sự hợp tác của Quý khách.<br/><b>Trân trọng.</b></p>

<table style="width:100%;border-collapse:collapse;margin-top:16px"><tr>
<td style="width:50%;text-align:center;vertical-align:bottom;padding:0 8px;border:none">
<div style="font-weight:700">KHÁCH HÀNG</div>
<div style="font-size:12px;font-style:italic">(Ký, ghi rõ họ tên)</div>
</td>
<td style="width:50%;text-align:center;vertical-align:bottom;padding:0 8px;border:none">
<div style="font-weight:700">ĐẠI DIỆN CÔNG TY</div>
<div style="font-size:12px;font-style:italic">{Chuc_Vu_Cua_Hang}</div>
</td>
</tr>
<tr>
<td style="height:100px;border:none"></td>
<td style="height:100px;text-align:center;vertical-align:middle;border:none">{Con_Dau}</td>
</tr>
<tr>
<td style="text-align:center;padding:6px 8px 0;border:none"><div style="font-weight:700">{Nguoi_Dai_Dien_Khach}</div></td>
<td style="text-align:center;padding:6px 8px 0;border:none"><div style="font-weight:700">{Nguoi_Dai_Dien_Cua_Hang}</div></td>
</tr></table></div>''';
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
