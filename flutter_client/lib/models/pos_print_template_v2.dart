import 'dart:convert';
import '../l10n/app_tr.dart';

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
        fields: fields ?? this.fields,
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
      labels = rawLabels.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return PosPrintBlock(
      type: type,
      text: trN(json['text']?.toString()),
      field: json['field']?.toString(),
      leftField: json['leftField']?.toString(),
      rightField: json['rightField']?.toString(),
      label: json['label']?.toString(),
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
      qrTitle: json['qrTitle']?.toString(),
      qrCaption: json['qrCaption']?.toString() ?? 'Quét VietQR thanh toán',
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
  });

  final int version;
  final String paperSize;
  final String printerProfile;
  final String documentType;
  final List<PosPrintBlock> blocks;
  final String? name;

  PosPrintTemplateV2 copyWith({
    String? paperSize,
    String? printerProfile,
    String? documentType,
    List<PosPrintBlock>? blocks,
    String? name,
  }) =>
      PosPrintTemplateV2(
        version: version,
        paperSize: paperSize ?? this.paperSize,
        printerProfile: printerProfile ?? this.printerProfile,
        documentType: documentType ?? this.documentType,
        blocks: blocks ?? this.blocks,
        name: name ?? this.name,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'paperSize': paperSize,
        'printerProfile': printerProfile,
        'documentType': documentType,
        if (name != null) 'name': name,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory PosPrintTemplateV2.fromJson(Map<String, dynamic> json) =>
      PosPrintTemplateV2(
        version: (json['version'] as num?)?.toInt() ?? 1,
        paperSize: json['paperSize']?.toString() ?? 'K80',
        printerProfile: json['printerProfile']?.toString() ?? PosPrintPrinterProfiles.sunmiK80,
        documentType: json['documentType']?.toString() ?? 'SaleInvoice',
        name: json['name']?.toString(),
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => PosPrintBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
}

/// Marker nhận diện mẫu V2 trong HtmlContent.
const kPosPrintTemplateV2Marker = '<!--POS_TEMPLATE_V2-->';
