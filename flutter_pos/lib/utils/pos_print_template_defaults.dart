import '../models/pos_print_template.dart';

/// HTML mẫu in mặc định (fallback khi API chưa có dữ liệu).
String posPrintDefaultHtml({
  String documentType = PosPrintDocumentTypes.saleInvoice,
  String paperSize = PosPrintPaperSizes.k80,
}) {
  if (PosPrintDocumentTypes.isCommercial(documentType)) {
    return _commercialA4(documentType);
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

/// Bảng hạng mục 7 cột dùng cho báo giá / bàn giao / đề nghị thanh toán.
const _itemTable = '''
<table style="width:100%;border-collapse:collapse;margin:8px 0;font-size:12.5px">
<thead><tr style="background:#f0f0f0">
<th style="border:1px solid #000;padding:5px 4px;width:6%">STT</th>
<th style="border:1px solid #000;padding:5px 4px">Tên hàng hóa / dịch vụ</th>
<th style="border:1px solid #000;padding:5px 4px;width:8%">ĐVT</th>
<th style="border:1px solid #000;padding:5px 4px;width:8%">SL</th>
<th style="border:1px solid #000;padding:5px 4px;width:14%;text-align:right">Đơn giá</th>
<th style="border:1px solid #000;padding:5px 4px;width:16%;text-align:right">Thành tiền</th>
<th style="border:1px solid #000;padding:5px 4px;width:12%">Bảo hành</th>
</tr></thead>
<tbody><!--BEGIN_ITEMS-->
<tr>
<td style="border:1px solid #000;padding:4px;text-align:center">{STT}</td>
<td style="border:1px solid #000;padding:4px">{Ten_Hang_Hoa}</td>
<td style="border:1px solid #000;padding:4px;text-align:center">{Don_Vi_Tinh}</td>
<td style="border:1px solid #000;padding:4px;text-align:center">{So_Luong}</td>
<td style="border:1px solid #000;padding:4px;text-align:right">{Don_Gia}</td>
<td style="border:1px solid #000;padding:4px;text-align:right">{Thanh_Tien}</td>
<td style="border:1px solid #000;padding:4px">{Bao_Hanh}</td>
</tr><!--END_ITEMS-->
</tbody>
<tfoot>
<tr><td colspan="5" style="border:1px solid #000;padding:5px 8px;text-align:right"><b>Tổng tiền hàng</b></td>
<td style="border:1px solid #000;padding:5px 8px;text-align:right"><b>{Tong_Tien_Hang}</b></td><td style="border:1px solid #000"></td></tr>
<tr><td colspan="5" style="border:1px solid #000;padding:5px 8px;text-align:right">Chiết khấu</td>
<td style="border:1px solid #000;padding:5px 8px;text-align:right">{Chiet_Khau_Hoa_Don}</td><td style="border:1px solid #000"></td></tr>
<tr><td colspan="5" style="border:1px solid #000;padding:5px 8px;text-align:right">Thuế GTGT</td>
<td style="border:1px solid #000;padding:5px 8px;text-align:right">{Tien_Thue}</td><td style="border:1px solid #000"></td></tr>
<tr style="background:#fafafa"><td colspan="5" style="border:1px solid #000;padding:6px 8px;text-align:right"><b>TỔNG CỘNG</b></td>
<td style="border:1px solid #000;padding:6px 8px;text-align:right;font-size:14px"><b>{Tong_Cong}</b></td><td style="border:1px solid #000"></td></tr>
</tfoot></table>''';

/// Bảng nghiệm thu 5 cột (STT · Tên · ĐVT · KL HĐ · KL Thực tế · Ghi chú).
const _acceptanceTable = '''
<table style="width:100%;border-collapse:collapse;margin:8px 0;font-size:12.5px">
<thead>
<tr style="background:#f0f0f0">
<th rowspan="2" style="border:1px solid #000;padding:5px 4px;width:6%">STT</th>
<th rowspan="2" style="border:1px solid #000;padding:5px 4px">Tên hàng hóa / hạng mục</th>
<th rowspan="2" style="border:1px solid #000;padding:5px 4px;width:10%">ĐVT</th>
<th colspan="2" style="border:1px solid #000;padding:5px 4px;width:24%">Khối lượng</th>
<th rowspan="2" style="border:1px solid #000;padding:5px 4px;width:20%">Ghi chú</th>
</tr>
<tr style="background:#f0f0f0">
<th style="border:1px solid #000;padding:5px 4px">Hợp đồng</th>
<th style="border:1px solid #000;padding:5px 4px">Thực tế</th>
</tr>
</thead>
<tbody><!--BEGIN_ITEMS-->
<tr>
<td style="border:1px solid #000;padding:4px;text-align:center">{STT}</td>
<td style="border:1px solid #000;padding:4px">{Ten_Hang_Hoa}</td>
<td style="border:1px solid #000;padding:4px;text-align:center">{Don_Vi_Tinh}</td>
<td style="border:1px solid #000;padding:4px;text-align:center">{So_Luong}</td>
<td style="border:1px solid #000;padding:4px;text-align:center">{So_Luong}</td>
<td style="border:1px solid #000;padding:4px">{Ghi_Chu}</td>
</tr><!--END_ITEMS-->
</tbody></table>''';

const _motto = '''
<div style="text-align:center;line-height:1.35">
<div style="font-weight:bold;font-size:13px">CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM</div>
<div style="font-weight:bold;font-size:13px">Độc lập – Tự do – Hạnh phúc</div>
<div style="border-bottom:1px solid #000;width:180px;margin:2px auto 6px"></div>
</div>''';

/// Header 2 cột: tên công ty bên trái, quốc hiệu bên phải + ngày.
String _twoColHeader(String rightExtra) => '''
<table style="width:100%;border-collapse:collapse;margin-bottom:8px"><tr>
<td style="width:50%;vertical-align:top;padding-right:8px">
<div style="font-weight:bold;font-size:13px;text-transform:uppercase">{Ten_Cua_Hang}</div>
<div>MST: {MST_Cua_Hang}</div>
<div style="font-style:italic">Số: {So_Chung_Tu}</div>
</td>
<td style="width:50%;vertical-align:top">
$_motto
<div style="text-align:center">{Dia_Chi_Chi_Nhanh}, ngày {Ngay}</div>
$rightExtra
</td></tr></table>''';

String _commercialA4(String documentType) {
  switch (documentType) {
    case PosPrintDocumentTypes.contract:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
$_motto
<h2 style="text-align:center;font-size:16px;text-transform:uppercase;margin:6px 0">HỢP ĐỒNG THI CÔNG</h2>
<div style="text-align:center;margin-bottom:6px">Số HĐ: <b>{So_Hop_Dong}</b> · Theo báo giá: <b>{Ma_Bao_Gia}</b></div>

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

<p style="margin:6px 0"><b>BÊN B (Nhà thầu): {Ten_Cua_Hang}</b><br/>
Mã số thuế: {MST_Cua_Hang}<br/>
Địa chỉ: {Dia_Chi_Chi_Nhanh}<br/>
Điện thoại: {Dien_Thoai_Chi_Nhanh}<br/>
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

<table style="width:100%;margin-top:32px"><tr>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN BÊN A</b><br/><i>(Ký, ghi rõ họ tên)</i>
<div style="height:70px"></div>
{Nguoi_Dai_Dien_Khach}</td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN BÊN B</b><br/><i>(Ký, ghi rõ họ tên)</i>
<div style="height:70px"></div>
{Nguoi_Dai_Dien_Cua_Hang}</td>
</tr></table></div>''';

    case PosPrintDocumentTypes.acceptance:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
${_twoColHeader('')}
<h2 style="text-align:center;font-size:16px;text-transform:uppercase;margin:6px 0">BIÊN BẢN NGHIỆM THU HOÀN THÀNH<br/>BÀN GIAO SẢN PHẨM ĐƯA VÀO SỬ DỤNG</h2>

<p><b>1. Đối tượng nghiệm thu</b><br/>
- Tên hạng mục công trình: {Ten_Hang_Hoa}<br/>
- Địa điểm thi công: {Dia_Diem_Thi_Cong}<br/>
- Căn cứ hợp đồng số: <b>{So_Hop_Dong}</b> ký ngày {Ngay_Hop_Dong}</p>

<p><b>2. Thành phần trực tiếp nghiệm thu</b></p>
<p>● <b>Chủ đầu tư: {Ten_Cong_Ty_Khach}</b><br/>
- Mã số thuế: {MST_Khach_Hang}<br/>
- Địa chỉ: {Dia_Chi_Khach_Hang}<br/>
- Đại diện: {Nguoi_Dai_Dien_Khach} — Chức vụ: {Chuc_Vu_Khach}</p>
<p>● <b>Nhà thầu thi công: {Ten_Cua_Hang}</b><br/>
- Mã số thuế: {MST_Cua_Hang}<br/>
- Địa chỉ: {Dia_Chi_Chi_Nhanh}<br/>
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

<table style="width:100%;margin-top:32px"><tr>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN CHỦ ĐẦU TƯ</b><br/>{Chuc_Vu_Khach}
<div style="height:70px"></div>
{Nguoi_Dai_Dien_Khach}</td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN NHÀ THẦU THI CÔNG</b><br/>{Chuc_Vu_Cua_Hang}
<div style="height:70px"></div>
{Nguoi_Dai_Dien_Cua_Hang}</td>
</tr></table></div>''';

    case PosPrintDocumentTypes.handover:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
${_twoColHeader('')}
<h2 style="text-align:center;font-size:16px;text-transform:uppercase;margin:6px 0">BIÊN BẢN BÀN GIAO CÔNG TRÌNH</h2>
<div style="text-align:center;margin-bottom:6px">Số: <b>{So_Chung_Tu}</b> · Theo HĐ: {So_Hop_Dong} · Báo giá: {Ma_Bao_Gia}</div>

<p><b>Bên giao (Nhà thầu): {Ten_Cua_Hang}</b><br/>
Mã số thuế: {MST_Cua_Hang} · ĐT: {Dien_Thoai_Chi_Nhanh}<br/>
Địa chỉ: {Dia_Chi_Chi_Nhanh}<br/>
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

<table style="width:100%;margin-top:32px"><tr>
<td style="width:50%;text-align:center;vertical-align:top">
<b>BÊN NHẬN (Chủ đầu tư)</b><br/><i>(Ký, ghi rõ họ tên)</i>
<div style="height:70px"></div>
{Nguoi_Dai_Dien_Khach}</td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>BÊN GIAO (Nhà thầu)</b><br/><i>(Ký, ghi rõ họ tên)</i>
<div style="height:70px"></div>
{Nguoi_Dai_Dien_Cua_Hang}</td>
</tr></table></div>''';

    case PosPrintDocumentTypes.paymentRequest:
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
${_twoColHeader('')}
<h2 style="text-align:center;font-size:16px;text-transform:uppercase;margin:6px 0">ĐỀ NGHỊ THANH TOÁN</h2>
<div style="text-align:center;font-style:italic;margin-bottom:8px">V/v: Thanh toán theo hợp đồng số {So_Hop_Dong}</div>

<p><b>Kính gửi:</b> {Ten_Cong_Ty_Khach}</p>

<p>Căn cứ theo hợp đồng số <b>{So_Hop_Dong}</b> ký ngày {Ngay_Hop_Dong} giữa {Ten_Cong_Ty_Khach} và {Ten_Cua_Hang} về việc {Ten_Hang_Hoa}.</p>

<p>Đến nay, Công ty chúng tôi đã hoàn tất triển khai / bàn giao theo danh sách chi tiết dưới đây (đính kèm biên bản nghiệm thu / đối soát):</p>

$_itemTable

<p>Nay kính đề nghị Quý Công ty thanh toán cho chúng tôi các khoản sau:</p>
<p>- Giá trị đề nghị thanh toán: <b>{Tong_Cong} VNĐ</b><br/>
<i>(Bằng chữ: {Tong_Cong_Bang_Chu})</i><br/>
- Hình thức thanh toán: {Hinh_Thuc_Thanh_Toan}<br/>
&nbsp;&nbsp;+ Số tài khoản: <b>{Tai_Khoan_Cua_Hang}</b><br/>
&nbsp;&nbsp;+ Ngân hàng: {Ngan_Hang_Cua_Hang}<br/>
&nbsp;&nbsp;+ Chủ tài khoản: {Ten_Cua_Hang}</p>

<p>Rất mong Quý Công ty xem xét, đối chiếu và thanh toán theo đúng tiến độ đã thỏa thuận.</p>

<p><b>Trân trọng!</b></p>

<table style="width:100%;margin-top:32px"><tr>
<td style="width:50%"></td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN {Ten_Cua_Hang}</b><br/>{Chuc_Vu_Cua_Hang}
<div style="height:70px"></div>
{Nguoi_Dai_Dien_Cua_Hang}</td>
</tr></table></div>''';

    default: // quote
      return '''
<div style="font-family:'Times New Roman',Times,serif;font-size:13px;color:#000;padding:8px 12px">
<table style="width:100%;border-collapse:collapse;margin-bottom:6px"><tr>
<td style="width:50%;vertical-align:top">
<div style="font-weight:bold;font-size:14px;text-transform:uppercase">{Ten_Cua_Hang}</div>
<div>MST: {MST_Cua_Hang}</div>
<div>{Dia_Chi_Chi_Nhanh}</div>
<div>ĐT: {Dien_Thoai_Chi_Nhanh} · Email: {Email_Cua_Hang}</div>
<div>TK: {Tai_Khoan_Cua_Hang} — {Ngan_Hang_Cua_Hang}</div>
<div>Chủ TK: {Chu_Tai_Khoan_Cua_Hang}</div>
<div>Đại diện: {Nguoi_Dai_Dien_Cua_Hang} — {Chuc_Vu_Cua_Hang}</div>
</td>
<td style="width:50%;vertical-align:top">
$_motto
<div style="text-align:center">{Dia_Chi_Chi_Nhanh}, ngày {Ngay}</div>
</td></tr></table>

<h2 style="text-align:center;font-size:16px;text-transform:uppercase;margin:6px 0">BẢNG BÁO GIÁ</h2>
<div style="text-align:center;margin-bottom:8px">Số: <b>{So_Chung_Tu}</b> · Có hiệu lực đến: <b>{Han_Bao_Gia}</b></div>

<p><b>Kính gửi:</b> {Ten_Cong_Ty_Khach} (đại diện: {Nguoi_Dai_Dien_Khach})<br/>
MST: {MST_Khach_Hang} · Điện thoại: {SDT}<br/>
Địa chỉ: {Dia_Chi_Khach_Hang}<br/>
Hình thức thanh toán: {Hinh_Thuc_Thanh_Toan} — Hạn báo giá: {Han_Bao_Gia}</p>

<p>Công ty chúng tôi xin trân trọng gửi Quý khách hàng bảng báo giá hàng hóa / dịch vụ như sau:</p>
$_itemTable

<p><b>Điều khoản:</b><br/>{Dieu_Khoan}<br/>
Bảo hành: {Bao_Hanh}<br/>
Ghi chú: {Ghi_Chu}</p>

<p>Rất mong nhận được sự hợp tác của Quý khách hàng.<br/><b>Trân trọng!</b></p>

<table style="width:100%;margin-top:32px"><tr>
<td style="width:50%;text-align:center;vertical-align:top">
<b>KHÁCH HÀNG</b><br/><i>(Ký, ghi rõ họ tên)</i>
<div style="height:60px"></div>
{Nguoi_Dai_Dien_Khach}</td>
<td style="width:50%;text-align:center;vertical-align:top">
<b>ĐẠI DIỆN {Ten_Cua_Hang}</b><br/>{Chuc_Vu_Cua_Hang}
<div style="height:60px"></div>
{Nguoi_Dai_Dien_Cua_Hang}</td>
</tr></table></div>''';
  }
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
