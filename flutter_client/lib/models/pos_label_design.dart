import 'dart:convert';

/// Dấu đầu nội dung mẫu tem thiết kế tự do (lưu chung bảng mẫu in, cột htmlContent).
/// Mẫu khối V2 / HTML cũ không bắt đầu bằng dấu này → các bộ đọc cũ bỏ qua.
const kPosLabelDesignMarker = '<!-- SBOX_LABEL_DESIGN_V1 -->';

/// Loại phần tử trên tem.
enum PosLabelElementType {
  /// Chữ — chèn được trường dữ liệu {Ten_Hang_Hoa}…
  text,
  /// Mã vạch (CODE128 / EAN-13 tự nhận).
  barcode,
  /// Mã QR nội dung tự soạn.
  qr,
  /// Ảnh / logo đen trắng.
  image,
  /// Đường kẻ ngang / dọc.
  line,
  /// Khung chữ nhật (viền hoặc tô đen).
  box,
}

enum PosLabelAlign { left, center, right }

enum PosLabelVAlign { top, middle, bottom }

/// Một phần tử đặt trên tem — toạ độ / kích thước tính bằng mm từ góc trên trái tem.
class PosLabelElement {
  const PosLabelElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.text = '',
    this.fontSize = 9,
    this.bold = false,
    this.align = PosLabelAlign.left,
    this.vAlign = PosLabelVAlign.middle,
    this.maxLines = 2,
    this.autoShrink = true,
    this.invert = false,
    this.rotation = 0,
    this.showText = true,
    this.strokeMm = 0.3,
    this.filled = false,
    this.imageData,
  });

  final String id;
  final PosLabelElementType type;
  final double x;
  final double y;
  final double w;
  final double h;

  /// Chữ / nội dung mã vạch / nội dung QR — có token {Truong}.
  final String text;
  /// Cỡ chữ (pt). 1 pt = 0,3528 mm.
  final double fontSize;
  final bool bold;
  final PosLabelAlign align;
  final PosLabelVAlign vAlign;
  final int maxLines;
  /// Chữ dài hơn ô → tự thu nhỏ (tối đa còn 55%) rồi mới cắt «…».
  final bool autoShrink;
  /// Nền đen chữ trắng (ô giá nổi bật).
  final bool invert;
  /// Xoay 0 / 90 / 180 / 270 độ.
  final int rotation;
  /// Mã vạch: in số dưới vạch.
  final bool showText;
  /// Đường kẻ / khung: độ dày (mm).
  final double strokeMm;
  /// Khung: tô đen cả ô.
  final bool filled;
  /// Ảnh PNG base64 (đã chuyển đen trắng).
  final String? imageData;

  PosLabelElement copyWith({
    String? id,
    double? x,
    double? y,
    double? w,
    double? h,
    String? text,
    double? fontSize,
    bool? bold,
    PosLabelAlign? align,
    PosLabelVAlign? vAlign,
    int? maxLines,
    bool? autoShrink,
    bool? invert,
    int? rotation,
    bool? showText,
    double? strokeMm,
    bool? filled,
    String? imageData,
  }) =>
      PosLabelElement(
        id: id ?? this.id,
        type: type,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        text: text ?? this.text,
        fontSize: fontSize ?? this.fontSize,
        bold: bold ?? this.bold,
        align: align ?? this.align,
        vAlign: vAlign ?? this.vAlign,
        maxLines: maxLines ?? this.maxLines,
        autoShrink: autoShrink ?? this.autoShrink,
        invert: invert ?? this.invert,
        rotation: rotation ?? this.rotation,
        showText: showText ?? this.showText,
        strokeMm: strokeMm ?? this.strokeMm,
        filled: filled ?? this.filled,
        imageData: imageData ?? this.imageData,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'x': _r(x),
        'y': _r(y),
        'w': _r(w),
        'h': _r(h),
        if (text.isNotEmpty) 'text': text,
        if (type == PosLabelElementType.text) ...{
          'fontSize': fontSize,
          'bold': bold,
          'align': align.name,
          'vAlign': vAlign.name,
          'maxLines': maxLines,
          'autoShrink': autoShrink,
          'invert': invert,
        },
        if (rotation != 0) 'rotation': rotation,
        if (type == PosLabelElementType.barcode) 'showText': showText,
        if (type == PosLabelElementType.line || type == PosLabelElementType.box) 'strokeMm': strokeMm,
        if (type == PosLabelElementType.box) 'filled': filled,
        if (imageData != null) 'imageData': imageData,
      };

  static PosLabelElement fromJson(Map<String, dynamic> j) {
    double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
    T en<T extends Enum>(List<T> values, String k, T def) =>
        values.where((v) => v.name == j[k]).firstOrNull ?? def;
    return PosLabelElement(
      id: '${j['id'] ?? ''}',
      type: en(PosLabelElementType.values, 'type', PosLabelElementType.text),
      x: d('x', 0),
      y: d('y', 0),
      w: d('w', 10),
      h: d('h', 5),
      text: '${j['text'] ?? ''}',
      fontSize: d('fontSize', 9),
      bold: j['bold'] == true,
      align: en(PosLabelAlign.values, 'align', PosLabelAlign.left),
      vAlign: en(PosLabelVAlign.values, 'vAlign', PosLabelVAlign.middle),
      maxLines: (j['maxLines'] as num?)?.toInt() ?? 2,
      autoShrink: j['autoShrink'] != false,
      invert: j['invert'] == true,
      rotation: ((j['rotation'] as num?)?.toInt() ?? 0) % 360,
      showText: j['showText'] != false,
      strokeMm: d('strokeMm', 0.3),
      filled: j['filled'] == true,
      imageData: j['imageData'] as String?,
    );
  }

  static double _r(double v) => (v * 100).roundToDouble() / 100;
}

/// Mẫu tem thiết kế tự do: khổ tem + danh sách phần tử (vẽ theo thứ tự, phần tử sau nằm trên).
class PosLabelDesign {
  const PosLabelDesign({
    required this.documentType,
    required this.widthMm,
    required this.heightMm,
    required this.elements,
    this.name,
    this.gapMm = 2,
    this.columns = 1,
    this.columnGapMm = 2,
  });

  /// BarcodeLabel / ScaleLabel / SpecLabel.
  final String documentType;
  final String? name;
  /// Kích thước một tem (mm).
  final double widthMm;
  final double heightMm;
  /// Khe giữa hai tem theo chiều cuộn (mm).
  final double gapMm;
  /// Số tem trên một hàng (cuộn 2–3 tem ngang).
  final int columns;
  /// Khoảng cách giữa các tem trên cùng hàng (mm).
  final double columnGapMm;
  final List<PosLabelElement> elements;

  String get sizeLabel => '${_fmt(widthMm)}×${_fmt(heightMm)} mm${columns > 1 ? ' · $columns tem/hàng' : ''}';

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  PosLabelDesign copyWith({
    String? name,
    double? widthMm,
    double? heightMm,
    double? gapMm,
    int? columns,
    double? columnGapMm,
    List<PosLabelElement>? elements,
  }) =>
      PosLabelDesign(
        documentType: documentType,
        name: name ?? this.name,
        widthMm: widthMm ?? this.widthMm,
        heightMm: heightMm ?? this.heightMm,
        gapMm: gapMm ?? this.gapMm,
        columns: columns ?? this.columns,
        columnGapMm: columnGapMm ?? this.columnGapMm,
        elements: elements ?? this.elements,
      );

  Map<String, dynamic> toJson() => {
        'version': 1,
        'documentType': documentType,
        if (name != null) 'name': name,
        'widthMm': widthMm,
        'heightMm': heightMm,
        'gapMm': gapMm,
        'columns': columns,
        'columnGapMm': columnGapMm,
        'elements': [for (final e in elements) e.toJson()],
      };

  static PosLabelDesign fromJson(Map<String, dynamic> j) => PosLabelDesign(
        documentType: '${j['documentType'] ?? 'BarcodeLabel'}',
        name: j['name'] as String?,
        widthMm: (j['widthMm'] as num?)?.toDouble() ?? 50,
        heightMm: (j['heightMm'] as num?)?.toDouble() ?? 30,
        gapMm: (j['gapMm'] as num?)?.toDouble() ?? 2,
        columns: ((j['columns'] as num?)?.toInt() ?? 1).clamp(1, 4),
        columnGapMm: (j['columnGapMm'] as num?)?.toDouble() ?? 2,
        elements: [
          for (final e in (j['elements'] as List? ?? const []))
            if (e is Map) PosLabelElement.fromJson(Map<String, dynamic>.from(e)),
        ],
      );

  /// Nội dung lưu vào mẫu in (cột htmlContent).
  String encode() => '$kPosLabelDesignMarker\n${jsonEncode(toJson())}';

  static bool isDesign(String? content) => (content ?? '').trimLeft().startsWith(kPosLabelDesignMarker);

  static PosLabelDesign? tryParse(String? content) {
    if (!isDesign(content)) return null;
    try {
      final raw = content!.trimLeft().substring(kPosLabelDesignMarker.length).trim();
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
