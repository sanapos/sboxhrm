import 'dart:convert';
import '../l10n/app_tr.dart';

/// Đưa nhãn mẫu in không dấu (K57/K58 cũ) về tiếng Việt có dấu.
/// Khôi phục cả chuỗi nguyên và cụm nằm trong nhãn (`So HD: HD01…`).
String restoreVietnamesePrintLabel(String s) {
  if (s.isEmpty) return s;
  final start = s.length - s.trimLeft().length;
  final end = s.trimRight().length;
  if (end <= start) return s;
  final lead = s.substring(0, start);
  final tail = s.substring(end);
  var t = s.substring(start, end);

  final exact = _kUnsignedPrintExact[t];
  if (exact != null) return '$lead$exact$tail';

  for (final suf in const [':', '：']) {
    if (t.endsWith(suf) && t.length > 1) {
      final core = t.substring(0, t.length - suf.length).trimRight();
      final e = _kUnsignedPrintExact[core];
      if (e != null) return '$lead$e$suf$tail';
    }
  }

  var out = t;
  for (final e in _kUnsignedPrintPhrases) {
    if (out.contains(e.key)) out = out.replaceAll(e.key, e.value);
  }
  return '$lead$out$tail';
}

String? _restoreVnLabel(String? s) {
  if (s == null) return null;
  return restoreVietnamesePrintLabel(s);
}

/// Khớp cả chuỗi (sau trim). Từ ngắn chỉ exact — tránh đụng tên hàng.
const _kUnsignedPrintExact = <String, String>{
  'Ngay': 'Ngày',
  'Gio': 'Giờ',
  'So HD': 'Số HĐ',
  'So Hd': 'Số HĐ',
  'Ma HD': 'Mã HĐ',
  'Ma Hd': 'Mã HĐ',
  'KH': 'KH',
  'DT': 'ĐT',
  'D.gia': 'Đ.giá',
  'D.Gia': 'Đ.giá',
  'T.tien': 'T.tiền',
  'T.Tien': 'T.tiền',
  'TONG': 'TỔNG',
};

/// Cụm dài hơn — thay trong nhãn. Dài trước ngắn.
final _kUnsignedPrintPhrases = <MapEntry<String, String>>[
  MapEntry('Cam on quy khach!', 'Cảm ơn quý khách!'),
  MapEntry('CAM ON QUY KHACH!', 'CẢM ƠN QUÝ KHÁCH!'),
  MapEntry('Cam on quy khach', 'Cảm ơn quý khách'),
  MapEntry('CAM ON QUY KHACH', 'CẢM ƠN QUÝ KHÁCH'),
  MapEntry('Quet ma VietQR de thanh toan', 'Quét mã VietQR để thanh toán'),
  MapEntry('Quet VietQR thanh toan', 'Quét VietQR thanh toán'),
  MapEntry('*** PHIEU HUY ***', '*** PHIẾU HỦY ***'),
  MapEntry('*** BAO CHE BIEN ***', '*** BÁO CHẾ BIẾN ***'),
  MapEntry('HOA DON BAN HANG', 'HÓA ĐƠN BÁN HÀNG'),
  MapEntry('Hoa don ban hang', 'Hóa đơn bán hàng'),
  MapEntry('HOA DON DAT HANG', 'HÓA ĐƠN ĐẶT HÀNG'),
  MapEntry('Hoa don dat hang', 'Hóa đơn đặt hàng'),
  MapEntry('PHIEU TRA HANG', 'PHIẾU TRẢ HÀNG'),
  MapEntry('Phieu tra hang', 'Phiếu trả hàng'),
  MapEntry('PHIEU GIAO HANG', 'PHIẾU GIAO HÀNG'),
  MapEntry('Phieu giao hang', 'Phiếu giao hàng'),
  MapEntry('PHIEU BAO CHE BIEN', 'PHIẾU BÁO CHẾ BIẾN'),
  MapEntry('Phieu bao che bien', 'Phiếu báo chế biến'),
  MapEntry('PHIEU HUY BEP', 'PHIẾU HỦY BẾP'),
  MapEntry('Phieu huy bep', 'Phiếu hủy bếp'),
  MapEntry('PHIEU RA MON', 'PHIẾU RA MÓN'),
  MapEntry('Phieu ra mon', 'Phiếu ra món'),
  MapEntry('*** PHIEU RA MON ***', '*** PHIẾU RA MÓN ***'),
  MapEntry('Thoi gian goi', 'Thời gian gọi'),
  MapEntry('Thoi gian ra', 'Thời gian ra'),
  MapEntry('Ma don hang', 'Mã đơn hàng'),
  MapEntry('Hinh thuc thanh toan', 'Hình thức thanh toán'),
  MapEntry('HINH THUC THANH TOAN', 'HÌNH THỨC THANH TOÁN'),
  MapEntry('Tong thanh tien', 'Tổng thành tiền'),
  MapEntry('TONG THANH TIEN', 'TỔNG THÀNH TIỀN'),
  MapEntry('Tong tien hang', 'Tổng tiền hàng'),
  MapEntry('TONG TIEN HANG', 'TỔNG TIỀN HÀNG'),
  MapEntry('Khach thanh toan', 'Khách thanh toán'),
  MapEntry('KHACH THANH TOAN', 'KHÁCH THANH TOÁN'),
  MapEntry('Khach can tra', 'Khách cần trả'),
  MapEntry('KHACH CAN TRA', 'KHÁCH CẦN TRẢ'),
  MapEntry('Da thanh toan', 'Đã thanh toán'),
  MapEntry('DA THANH TOAN', 'ĐÃ THANH TOÁN'),
  MapEntry('Phi giao hang', 'Phí giao hàng'),
  MapEntry('PHI GIAO HANG', 'PHÍ GIAO HÀNG'),
  MapEntry('Chiet khau hoa don', 'Chiết khấu hóa đơn'),
  MapEntry('CHIET KHAU HOA DON', 'CHIẾT KHẤU HÓA ĐƠN'),
  MapEntry('Ten hang hoa', 'Tên hàng hóa'),
  MapEntry('TEN HANG HOA', 'TÊN HÀNG HÓA'),
  MapEntry('Don vi tinh', 'Đơn vị tính'),
  MapEntry('DON VI TINH', 'ĐƠN VỊ TÍNH'),
  MapEntry('Dia chi chi nhanh', 'Địa chỉ chi nhánh'),
  MapEntry('Ten cua hang', 'Tên cửa hàng'),
  MapEntry('TEN CUA HANG', 'TÊN CỬA HÀNG'),
  MapEntry('Dien thoai', 'Điện thoại'),
  MapEntry('DIEN THOAI', 'ĐIỆN THOẠI'),
  MapEntry('Khach hang', 'Khách hàng'),
  MapEntry('KHACH HANG', 'KHÁCH HÀNG'),
  MapEntry('Nguoi ban', 'Người bán'),
  MapEntry('NGUOI BAN', 'NGƯỜI BÁN'),
  MapEntry('Nguoi mua', 'Người mua'),
  MapEntry('Ghi chu', 'Ghi chú'),
  MapEntry('GHI CHU', 'GHI CHÚ'),
  MapEntry('Dia chi', 'Địa chỉ'),
  MapEntry('DIA CHI', 'ĐỊA CHỈ'),
  MapEntry('So luong', 'Số lượng'),
  MapEntry('SO LUONG', 'SỐ LƯỢNG'),
  MapEntry('Don gia', 'Đơn giá'),
  MapEntry('DON GIA', 'ĐƠN GIÁ'),
  MapEntry('Thanh tien', 'Thành tiền'),
  MapEntry('THANH TIEN', 'THÀNH TIỀN'),
  MapEntry('Thanh toan', 'Thanh toán'),
  MapEntry('THANH TOAN', 'THANH TOÁN'),
  MapEntry('Chiet khau', 'Chiết khấu'),
  MapEntry('CHIET KHAU', 'CHIẾT KHẤU'),
  MapEntry('Phu thu', 'Phụ thu'),
  MapEntry('PHU THU', 'PHỤ THU'),
  MapEntry('Tien thua', 'Tiền thừa'),
  MapEntry('TIEN THUA', 'TIỀN THỪA'),
  MapEntry('Tien mat', 'Tiền mặt'),
  MapEntry('TIEN MAT', 'TIỀN MẶT'),
  MapEntry('Con lai', 'Còn lại'),
  MapEntry('CON LAI', 'CÒN LẠI'),
  MapEntry('Con no', 'Còn nợ'),
  MapEntry('CON NO', 'CÒN NỢ'),
  MapEntry('Bang chu', 'Bằng chữ'),
  MapEntry('BANG CHU', 'BẰNG CHỮ'),
  MapEntry('Ten hang', 'Tên hàng'),
  MapEntry('TEN HANG', 'TÊN HÀNG'),
  MapEntry('Ma hang', 'Mã hàng'),
  MapEntry('MA HANG', 'MÃ HÀNG'),
  MapEntry('Ma vach', 'Mã vạch'),
  MapEntry('MA VACH', 'MÃ VẠCH'),
  MapEntry('So phieu', 'Số phiếu'),
  MapEntry('Goi luc', 'Gọi lúc'),
  MapEntry('Hoan tien', 'Hoàn tiền'),
  MapEntry('HOAN TIEN', 'HOÀN TIỀN'),
  MapEntry('Tong cong', 'Tổng cộng'),
  MapEntry('TONG CONG', 'TỔNG CỘNG'),
  MapEntry('Phi GH', 'Phí GH'),
  MapEntry('So HD', 'Số HĐ'),
  MapEntry('Ma HD', 'Mã HĐ'),
  MapEntry('D.gia', 'Đ.giá'),
  MapEntry('D.GIA', 'Đ.GIÁ'),
  MapEntry('T.tien', 'T.tiền'),
  MapEntry('T.TIEN', 'T.TIỀN'),
  MapEntry('So hoa don', 'Số hóa đơn'),
  MapEntry('Ma hoa don', 'Mã hóa đơn'),
  MapEntry('HOA DON', 'HÓA ĐƠN'),
  MapEntry('Hoa don', 'Hóa đơn'),
  MapEntry('PHIEU TAM TINH', 'PHIẾU TẠM TÍNH'),
  MapEntry('Phieu tam tinh', 'Phiếu tạm tính'),
  MapEntry('TAM TINH', 'TẠM TÍNH'),
  MapEntry('Tam tinh', 'Tạm tính'),
  MapEntry('Ban in lai', 'Bản in lại'),
  MapEntry('In lai', 'In lại'),
  MapEntry('Lan in', 'Lần in'),
  MapEntry('LAN IN', 'LẦN IN'),
  MapEntry('Thu ngan', 'Thu ngân'),
  MapEntry('THU NGAN', 'THU NGÂN'),
  MapEntry('Nhan vien', 'Nhân viên'),
  MapEntry('NHAN VIEN', 'NHÂN VIÊN'),
  MapEntry('Khach le', 'Khách lẻ'),
  MapEntry('KHACH LE', 'KHÁCH LẺ'),
  MapEntry('Quy khach', 'Quý khách'),
  MapEntry('QUY KHACH', 'QUÝ KHÁCH'),
  MapEntry('Xin cam on', 'Xin cảm ơn'),
  MapEntry('XIN CAM ON', 'XIN CẢM ƠN'),
  MapEntry('Cam on!', 'Cảm ơn!'),
  MapEntry('CAM ON!', 'CẢM ƠN!'),
  MapEntry('Hen gap lai', 'Hẹn gặp lại'),
  MapEntry('HEN GAP LAI', 'HẸN GẶP LẠI'),
  MapEntry('Tien hang', 'Tiền hàng'),
  MapEntry('TIEN HANG', 'TIỀN HÀNG'),
  MapEntry('Tong tien', 'Tổng tiền'),
  MapEntry('TONG TIEN', 'TỔNG TIỀN'),
  MapEntry('Thue VAT', 'Thuế VAT'),
  MapEntry('Thue GTGT', 'Thuế GTGT'),
  MapEntry('THUE GTGT', 'THUẾ GTGT'),
  MapEntry('Khu vuc', 'Khu vực'),
  MapEntry('KHU VUC', 'KHU VỰC'),
  MapEntry('So ban', 'Số bàn'),
  MapEntry('Ban:', 'Bàn:'),
]..sort((a, b) => b.key.length.compareTo(a.key.length));

/// Hồ sơ máy in — preset theo thiết bị + khổ giấy.
abstract final class PosPrintPrinterProfiles {
  static const sunmiK58 = 'sunmi_k58';
  static const sunmiK80 = 'sunmi_k80';
  static const zywellK80 = 'zywell_k80';
  static const genericK58 = 'generic_k58';
  static const genericK80 = 'generic_k80';

  static const labels = <String, String>{
    sunmiK58: 'Sunmi K58 (58mm)',
    sunmiK80: 'Sunmi K80 (80mm)',
    zywellK80: 'Zywell K80 (80mm)',
    genericK58: 'Máy in nhiệt K58',
    genericK80: 'Máy in nhiệt K80',
  };

  static String forPaperAndBrand({
    required String paperSize,
    required bool isSunmi,
    required bool isZywell,
  }) {
    final k58 = paperSize == 'K58';
    if (isSunmi) return k58 ? sunmiK58 : sunmiK80;
    if (isZywell) return k58 ? genericK58 : zywellK80;
    return k58 ? genericK58 : genericK80;
  }
}

enum PosPrintBlockType {
  text,
  field,
  pair,
  divider,
  lineItems,
  lineItemsKitchen,
  totals,
  spacer,
  vietQr,
  /// Mã vạch CODE128 từ token (Ma_Vach / Ma_Hang…).
  barcode,
}

/// Vị trí khối VietQR so với phần tổng cộng (editor tự sắp xếp lại khối).
enum PosPrintQrPlacement {
  aboveTotals,
  belowTotals,
  custom,
}

/// Viền in quanh bill / tem — nội dung lùi vào trong khung.
enum PosPrintFrameStyle {
  none,
  rectangle,
  rounded,
}

enum PosPrintTextAlign { left, center, right }

/// Kiểu đường kẻ.
enum PosPrintDividerStyle { dash, equals }

class PosPrintTextStyle {
  const PosPrintTextStyle({
    this.fontSize = 24,
    this.bold = false,
    this.align = PosPrintTextAlign.left,
  });

  final double fontSize;
  final bool bold;
  final PosPrintTextAlign align;

  PosPrintTextStyle copyWith({
    double? fontSize,
    bool? bold,
    PosPrintTextAlign? align,
  }) =>
      PosPrintTextStyle(
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        align: align ?? this.align,
      );

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'bold': bold,
        'align': align.name,
      };

  factory PosPrintTextStyle.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PosPrintTextStyle();
    return PosPrintTextStyle(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24,
      bold: json['bold'] == true,
      align: PosPrintTextAlign.values.firstWhere(
        (e) => e.name == json['align'],
        orElse: () => PosPrintTextAlign.left,
      ),
    );
  }
}

class PosPrintBlock {
  const PosPrintBlock({
    required this.type,
    this.text,
    this.field,
    this.leftField,
    this.rightField,
    this.label,
    this.fieldLabels,
    this.showColumnHeader = false,
    this.style = const PosPrintTextStyle(),
    this.rightStyle,
    this.divider = PosPrintDividerStyle.dash,
    this.dividerChars,
    this.fields,
    this.height = 8,
    this.qrSize = 160,
    this.qrTitle,
    this.qrCaption = 'Quét VietQR thanh toán',
    this.qrShowAmount = true,
    this.qrPlacement = PosPrintQrPlacement.belowTotals,
    this.barcodeHeight = 60,
    this.barcodeShowText = true,
  });

  final PosPrintBlockType type;
  final String? text;
  final String? field;
  final String? leftField;
  final String? rightField;
  /// Nhãn hiển thị (field/pair) — vd. "KH:", "Số HĐ:".
  final String? label;
  /// Nhãn theo token — totals / cột hàng / prefix pair.
  /// vd. {'Tong_Cong': 'Tổng tiền', 'Ten_Hang_Hoa': 'Tên hàng'}.
  final Map<String, String>? fieldLabels;
  /// In dòng tiêu đề cột trước danh sách hàng.
  final bool showColumnHeader;
  final PosPrintTextStyle style;
  final PosPrintTextStyle? rightStyle;
  final PosPrintDividerStyle divider;
  /// Số ký tự đường kẻ (null = tự động theo khổ giấy).
  final int? dividerChars;
  /// Các token tổng — ví dụ Tong_Cong, Khach_Thanh_Toan.
  /// Với [PosPrintBlockType.lineItems]: `['Ten_Hang_Hoa']` = chỉ in tên hàng.
  final List<String>? fields;
  final double height;
  /// Kích thước QR in (px/dot, 100–220).
  final int qrSize;
  final String? qrTitle;
  final String qrCaption;
  final bool qrShowAmount;
  final PosPrintQrPlacement qrPlacement;
  /// Chiều cao vạch barcode (dot), 40–120.
  final int barcodeHeight;
  /// In chữ mã dưới barcode.
  final bool barcodeShowText;

  /// `lineItems` có danh sách cột tùy chọn (khối «Tên hàng»).
  bool get usesCustomLineFields =>
      type == PosPrintBlockType.lineItems &&
      fields != null &&
      fields!.isNotEmpty;

  /// Danh sách hàng chỉ in tên món — không SL, ĐVT, đơn giá.
  bool get isNameOnlyLineItems =>
      usesCustomLineFields &&
      !showsLineField('So_Luong') &&
      !showsLineField('Don_Vi_Tinh') &&
      !showsLineField('Don_Gia') &&
      !showsLineField('Thanh_Tien');

  bool showsLineField(String token) {
    // Trường Ten_Hang_Hoa trên tem: tùy chọn SL / ĐVT / ghi chú giống khối「Tên hàng」.
    if (type == PosPrintBlockType.field && field == 'Ten_Hang_Hoa') {
      if (fields == null || fields!.isEmpty) {
        return token == 'Ten_Hang_Hoa' || token == 'So_Luong';
      }
      if (token == 'Ten_Hang_Hoa') return true;
      return fields!.contains(token);
    }
    if (type != PosPrintBlockType.lineItems) return true;
    if (!usesCustomLineFields) {
      return token != 'Don_Vi_Tinh';
    }
    if (token == 'Ten_Hang_Hoa') return true;
    return fields!.contains(token);
  }

  PosPrintBlock copyWith({
    PosPrintBlockType? type,
    String? text,
    String? field,
    String? leftField,
    String? rightField,
    String? label,
    bool clearLabel = false,
    Map<String, String>? fieldLabels,
    bool clearFieldLabels = false,
    bool? showColumnHeader,
    PosPrintTextStyle? style,
    PosPrintTextStyle? rightStyle,
    PosPrintDividerStyle? divider,
    int? dividerChars,
    bool clearDividerChars = false,
    List<String>? fields,
    bool clearFields = false,
    double? height,
    int? qrSize,
    String? qrTitle,
    bool clearQrTitle = false,
    String? qrCaption,
    bool? qrShowAmount,
    PosPrintQrPlacement? qrPlacement,
    int? barcodeHeight,
    bool? barcodeShowText,
  }) =>
      PosPrintBlock(
        type: type ?? this.type,
        text: trN(text ?? this.text),
        field: field ?? this.field,
        leftField: leftField ?? this.leftField,
        rightField: rightField ?? this.rightField,
        label: clearLabel ? null : (label ?? this.label),
        fieldLabels: clearFieldLabels ? null : (fieldLabels ?? this.fieldLabels),
        showColumnHeader: showColumnHeader ?? this.showColumnHeader,
        style: style ?? this.style,
        rightStyle: rightStyle ?? this.rightStyle,
        divider: divider ?? this.divider,
        dividerChars: clearDividerChars ? null : (dividerChars ?? this.dividerChars),
        fields: clearFields ? null : (fields ?? this.fields),
        height: height ?? this.height,
        qrSize: qrSize ?? this.qrSize,
        qrTitle: clearQrTitle ? null : (qrTitle ?? this.qrTitle),
        qrCaption: qrCaption ?? this.qrCaption,
        qrShowAmount: qrShowAmount ?? this.qrShowAmount,
        qrPlacement: qrPlacement ?? this.qrPlacement,
        barcodeHeight: barcodeHeight ?? this.barcodeHeight,
        barcodeShowText: barcodeShowText ?? this.barcodeShowText,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (text != null) 'text': text,
        if (field != null) 'field': field,
        if (leftField != null) 'leftField': leftField,
        if (rightField != null) 'rightField': rightField,
        if (label != null && label!.isNotEmpty) 'label': label,
        if (fieldLabels != null && fieldLabels!.isNotEmpty) 'fieldLabels': fieldLabels,
        if (showColumnHeader) 'showColumnHeader': true,
        'style': style.toJson(),
        if (rightStyle != null) 'rightStyle': rightStyle!.toJson(),
        if (type == PosPrintBlockType.divider) 'divider': divider.name,
        if (type == PosPrintBlockType.divider && dividerChars != null)
          'dividerChars': dividerChars,
        if (fields != null) 'fields': fields,
        if (type == PosPrintBlockType.spacer) 'height': height,
        if (type == PosPrintBlockType.vietQr) ...{
          'qrSize': qrSize,
          if (qrTitle != null && qrTitle!.isNotEmpty) 'qrTitle': qrTitle,
          'qrCaption': qrCaption,
          'qrShowAmount': qrShowAmount,
          'qrPlacement': qrPlacement.name,
        },
        if (type == PosPrintBlockType.barcode) ...{
          'barcodeHeight': barcodeHeight,
          'barcodeShowText': barcodeShowText,
        },
      };

  factory PosPrintBlock.fromJson(Map<String, dynamic> json) {
    final type = PosPrintBlockType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => PosPrintBlockType.text,
    );
    Map<String, String>? labels;
    final rawLabels = json['fieldLabels'];
    if (rawLabels is Map) {
      labels = rawLabels.map(
        (k, v) => MapEntry(k.toString(), restoreVietnamesePrintLabel(v.toString())),
      );
    }
    return PosPrintBlock(
      type: type,
      text: trN(_restoreVnLabel(json['text']?.toString())),
      field: json['field']?.toString(),
      leftField: json['leftField']?.toString(),
      rightField: json['rightField']?.toString(),
      label: _restoreVnLabel(json['label']?.toString()),
      fieldLabels: labels,
      showColumnHeader: json['showColumnHeader'] == true,
      style: PosPrintTextStyle.fromJson(json['style'] as Map<String, dynamic>?),
      rightStyle: json['rightStyle'] is Map
          ? PosPrintTextStyle.fromJson(json['rightStyle'] as Map<String, dynamic>)
          : null,
      divider: PosPrintDividerStyle.values.firstWhere(
        (e) => e.name == json['divider'],
        orElse: () => PosPrintDividerStyle.dash,
      ),
      dividerChars: json['dividerChars'] is num
          ? (json['dividerChars'] as num).toInt()
          : int.tryParse('${json['dividerChars']}'),
      fields: (json['fields'] as List?)?.map((e) => e.toString()).toList(),
      height: (json['height'] as num?)?.toDouble() ?? 8,
      qrSize: (json['qrSize'] is num ? (json['qrSize'] as num).toInt() : null) ?? 160,
      qrTitle: _restoreVnLabel(json['qrTitle']?.toString()),
      qrCaption: restoreVietnamesePrintLabel(
        json['qrCaption']?.toString() ?? 'Quét VietQR thanh toán',
      ),
      qrShowAmount: json['qrShowAmount'] != false,
      qrPlacement: PosPrintQrPlacement.values.firstWhere(
        (e) => e.name == json['qrPlacement'],
        orElse: () => PosPrintQrPlacement.belowTotals,
      ),
      barcodeHeight:
          (json['barcodeHeight'] is num ? (json['barcodeHeight'] as num).toInt() : null) ??
              60,
      barcodeShowText: json['barcodeShowText'] != false,
    );
  }
}

/// Mẫu in V2 — JSON lưu trong HtmlContent với marker.
class PosPrintTemplateV2 {
  const PosPrintTemplateV2({
    this.version = 1,
    required this.paperSize,
    required this.printerProfile,
    required this.documentType,
    required this.blocks,
    this.name,
    this.frameStyle = PosPrintFrameStyle.none,
    this.frameInsetMm = 2.5,
    this.frameMarginMm = 1.5,
  });

  final int version;
  final String paperSize;
  final String printerProfile;
  final String documentType;
  final List<PosPrintBlock> blocks;
  final String? name;
  /// Viền in quanh phiếu / tem.
  final PosPrintFrameStyle frameStyle;
  /// Khoảng cách từ viền khung tới chữ (mm).
  final double frameInsetMm;
  /// Khoảng cách từ mép giấy tới viền khung (mm).
  final double frameMarginMm;

  PosPrintTemplateV2 copyWith({
    String? paperSize,
    String? printerProfile,
    String? documentType,
    List<PosPrintBlock>? blocks,
    String? name,
    PosPrintFrameStyle? frameStyle,
    double? frameInsetMm,
    double? frameMarginMm,
  }) =>
      PosPrintTemplateV2(
        version: version,
        paperSize: paperSize ?? this.paperSize,
        printerProfile: printerProfile ?? this.printerProfile,
        documentType: documentType ?? this.documentType,
        blocks: blocks ?? this.blocks,
        name: name ?? this.name,
        frameStyle: frameStyle ?? this.frameStyle,
        frameInsetMm: frameInsetMm ?? this.frameInsetMm,
        frameMarginMm: frameMarginMm ?? this.frameMarginMm,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'paperSize': paperSize,
        'printerProfile': printerProfile,
        'documentType': documentType,
        if (name != null) 'name': name,
        if (frameStyle != PosPrintFrameStyle.none) 'frameStyle': frameStyle.name,
        if (frameStyle != PosPrintFrameStyle.none) 'frameInsetMm': frameInsetMm,
        if (frameStyle != PosPrintFrameStyle.none) 'frameMarginMm': frameMarginMm,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory PosPrintTemplateV2.fromJson(Map<String, dynamic> json) =>
      PosPrintTemplateV2(
        version: (json['version'] as num?)?.toInt() ?? 1,
        paperSize: json['paperSize']?.toString() ?? 'K80',
        printerProfile: json['printerProfile']?.toString() ?? PosPrintPrinterProfiles.sunmiK80,
        documentType: json['documentType']?.toString() ?? 'SaleInvoice',
        name: json['name']?.toString(),
        frameStyle: PosPrintFrameStyle.values.firstWhere(
          (e) => e.name == json['frameStyle'],
          orElse: () => PosPrintFrameStyle.none,
        ),
        frameInsetMm: (json['frameInsetMm'] as num?)?.toDouble() ?? 2.5,
        frameMarginMm: (json['frameMarginMm'] as num?)?.toDouble() ?? 1.5,
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => PosPrintBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
}

/// Marker nhận diện mẫu V2 trong HtmlContent.
const kPosPrintTemplateV2Marker = '<!--POS_TEMPLATE_V2-->';
