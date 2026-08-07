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
  final fs = paperSize == PosPrintPaperSizes.k58 ? '10px' : '11px';
  return '''
<div style="width:$width;max-width:100%;margin:0 auto;font-family:Arial,sans-serif;font-size:$fs;color:#000">
  <div style="text-align:center">
    <div style="font-weight:bold;font-size:13px">$title</div>
    <div style="font-weight:bold;margin-top:4px">{Ten_Cua_Hang}</div>
    <div>{Dia_Chi_Chi_Nhanh}</div>
    <div>ĐT: {Dien_Thoai_Chi_Nhanh}</div>
  </div>
  <div style="margin:8px 0;border-top:1px dashed #999"></div>
  <div>Số HĐ: <b>{Ma_Don_Hang}</b></div>
  <div>Ngày: {Ngay} {Gio}</div>
  <div>KH: {Khach_Hang}</div>
  <div>SDT: {SDT}</div>
  <div style="margin:8px 0;border-top:1px dashed #999"></div>
  <!--BEGIN_ITEMS-->
  <div style="margin-bottom:6px">
    <div><b>{Ten_Hang_Hoa}</b> <span style="color:#666">({Ma_Hang})</span></div>
    <div style="display:flex;justify-content:space-between">
      <span>{So_Luong} {Don_Vi_Tinh} x {Don_Gia}</span>
      <span><b>{Thanh_Tien}</b></span>
    </div>
  </div>
  <!--END_ITEMS-->
  <div style="margin:8px 0;border-top:1px dashed #999"></div>
  <div style="text-align:right">
    <div>Tổng tiền hàng: <b>{Tong_Tien_Hang}</b></div>
    <div>Chiết khấu: {Chiet_Khau_Hoa_Don}</div>
    <div style="font-size:12px;font-weight:bold;margin-top:4px">Tổng cộng: {Tong_Cong}</div>
    <div>Đã thanh toán: {Khach_Thanh_Toan} ({Hinh_Thuc_Thanh_Toan})</div>
    <div>Tiền thừa: {Tien_Thua}</div>
  </div>
  <div style="margin-top:6px;font-style:italic">{Tong_Cong_Bang_Chu}</div>
  <div style="margin-top:8px;text-align:center">Cảm ơn quý khách!</div>
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

String posPrintDefaultTemplateName(String paperSize) =>
    PosPrintPaperSizes.labels[paperSize] ?? paperSize;
