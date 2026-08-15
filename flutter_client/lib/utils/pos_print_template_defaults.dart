import '../models/pos_print_template.dart';

/// HTML mẫu in mặc định (fallback khi API chưa có dữ liệu).
String posPrintDefaultHtml({
  String documentType = PosPrintDocumentTypes.saleInvoice,
  String paperSize = PosPrintPaperSizes.k80,
}) {
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
  <div style="display:flex;justify-content:space-between"><span><b>Số HĐ:</b> {Ma_Don_Hang}</span><span><b>{Ngay}</b></span></div>
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
      <div>Số: <b>{Ma_Don_Hang}</b></div><div>Ngày: {Ngay} {Gio}</div></td></tr></table>
  <table style="width:100%;border-collapse:collapse;border:1px solid #ccc;margin-top:12px">
    <thead><tr style="background:#f3f4f6">
      <th style="border:1px solid #ccc;padding:6px">STT</th>
      <th style="border:1px solid #ccc;padding:6px">Mã hàng</th>
      <th style="border:1px solid #ccc;padding:6px">Tên hàng</th>
      <th style="border:1px solid #ccc;padding:6px;text-align:right">Đơn giá</th>
      <th style="border:1px solid #ccc;padding:6px;text-align:center">SL</th>
      <th style="border:1px solid #ccc;padding:6px;text-align:right">Thành tiền</th>
    </tr></thead>
    <tbody><!--BEGIN_ITEMS-->
      <tr>
        <td style="border:1px solid #ccc;padding:5px;text-align:center">{STT}</td>
        <td style="border:1px solid #ccc;padding:5px">{Ma_Hang}</td>
        <td style="border:1px solid #ccc;padding:5px">{Ten_Hang_Hoa}</td>
        <td style="border:1px solid #ccc;padding:5px;text-align:right">{Don_Gia}</td>
        <td style="border:1px solid #ccc;padding:5px;text-align:center">{So_Luong}</td>
        <td style="border:1px solid #ccc;padding:5px;text-align:right">{Thanh_Tien}</td>
      </tr><!--END_ITEMS-->
    </tbody>
  </table>
  <div style="text-align:right;margin-top:12px">
    <div>Tổng tiền hàng: <b>{Tong_Tien_Hang}</b></div>
    <div>Tổng cộng: <b>{Tong_Cong}</b></div>
  </div>
</div>''';
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
