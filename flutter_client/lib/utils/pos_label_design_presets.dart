import 'dart:math' as math;

import '../models/pos_label_design.dart';
import '../models/pos_print_template.dart';

/// Một mẫu tem dựng sẵn (chọn khi «Tạo mẫu», rồi sửa trong trình soạn).
class PosLabelDesignPreset {
  const PosLabelDesignPreset(this.key, this.name, this.description, this.build);
  final String key;
  final String name;
  final String description;
  final PosLabelDesign Function(double widthMm, double heightMm) build;
}

/// Mẫu tem dựng sẵn cho tem sản phẩm / tem cân / tem thông số. Toạ độ tính theo tỉ lệ khổ tem.
abstract final class PosLabelDesignPresets {
  /// Khổ tem thường gặp (mm).
  static const sizes = <(double, double)>[
    (50, 30),
    (40, 30),
    (35, 22),
    (60, 40),
    (58, 40),
    (70, 50),
    (100, 50),
    (100, 150),
  ];

  static int _seq = 0;
  static String newId() => 'e${DateTime.now().microsecondsSinceEpoch}${_seq++}';

  static PosLabelElement _text(String text, double x, double y, double w, double h,
          {double size = 8,
          bool bold = false,
          PosLabelAlign align = PosLabelAlign.left,
          int lines = 1,
          bool invert = false}) =>
      PosLabelElement(
        id: newId(),
        type: PosLabelElementType.text,
        x: x,
        y: y,
        w: w,
        h: h,
        text: text,
        fontSize: size,
        bold: bold,
        align: align,
        maxLines: lines,
        invert: invert,
      );

  static PosLabelElement _barcode(double x, double y, double w, double h, {bool showText = true}) => PosLabelElement(
        id: newId(),
        type: PosLabelElementType.barcode,
        x: x,
        y: y,
        w: w,
        h: h,
        text: '{Ma_Vach}',
        showText: showText,
      );

  static PosLabelElement _qr(String content, double x, double y, double side) => PosLabelElement(
        id: newId(),
        type: PosLabelElementType.qr,
        x: x,
        y: y,
        w: side,
        h: side,
        text: content,
      );

  /// Cỡ chữ theo chiều cao tem (tem 30 mm = 1; tem nhỏ chữ nhỏ lại, tem to chữ to lên — có giới hạn).
  static double _k(double h) => (h / 30).clamp(0.72, 2.2);

  static PosLabelDesign _d(String type, double w, double h, String name, List<PosLabelElement> els) =>
      PosLabelDesign(documentType: type, widthMm: w, heightMm: h, name: name, elements: els);

  static List<PosLabelDesignPreset> forType(String documentType) => switch (documentType) {
        PosPrintDocumentTypes.scaleLabel => _scale,
        PosPrintDocumentTypes.specLabel => _spec,
        PosPrintDocumentTypes.kitchenLabel => _kitchen,
        _ => _product,
      };

  static PosLabelDesignPreset blank(String documentType) => PosLabelDesignPreset(
        'blank',
        'Mẫu trắng',
        'Tự đặt chữ, mã vạch, QR, ảnh',
        (w, h) => _d(documentType, w, h, 'Mẫu trắng', const []),
      );

  // ── Tem sản phẩm ─────────────────────────────────────────────────────────
  static final _product = <PosLabelDesignPreset>[
    PosLabelDesignPreset('product_basic', 'Cơ bản', 'Tên · mã vạch · giá', (w, h) {
      const m = 1.5;
      final k = _k(h);
      return _d(PosPrintDocumentTypes.barcodeLabel, w, h, 'Tem sản phẩm cơ bản', [
        _text('{Ten_Hang_Hoa}', m, m, w - 2 * m, h * 0.27,
            size: 9 * k, bold: true, align: PosLabelAlign.center, lines: 2),
        _barcode(m, h * 0.32, w - 2 * m, h * 0.40),
        _text('{Don_Gia} đ', m, h * 0.74, w - 2 * m, h * 0.24, size: 12 * k, bold: true, align: PosLabelAlign.center),
      ]);
    }),
    PosLabelDesignPreset('product_price', 'Giá nổi bật', 'Ô giá nền đen bên phải mã vạch', (w, h) {
      const m = 1.2;
      final k = _k(h);
      final priceW = w * 0.38;
      return _d(PosPrintDocumentTypes.barcodeLabel, w, h, 'Tem giá nổi bật', [
        _text('{Ten_Cua_Hang}', m, m * 0.6, w - 2 * m, h * 0.13, size: 6 * k, align: PosLabelAlign.center),
        _text('{Ten_Hang_Hoa}', m, h * 0.15, w - 2 * m, h * 0.27, size: 8.5 * k, bold: true, lines: 2),
        _barcode(m, h * 0.45, w - priceW - 2.5 * m, h * 0.52),
        _text('{Don_Gia}đ', w - priceW - m, h * 0.48, priceW, h * 0.42,
            size: 11 * k, bold: true, align: PosLabelAlign.center, invert: true),
      ]);
    }),
    PosLabelDesignPreset('product_code', 'Có mã hàng & ĐVT', 'Tên · mã vạch · mã hàng · giá/ĐVT', (w, h) {
      const m = 1.5;
      final k = _k(h);
      return _d(PosPrintDocumentTypes.barcodeLabel, w, h, 'Tem có mã hàng', [
        _text('{Ten_Hang_Hoa}', m, m, w - 2 * m, h * 0.25,
            size: 8.5 * k, bold: true, align: PosLabelAlign.center, lines: 2),
        _barcode(m, h * 0.29, w - 2 * m, h * 0.42),
        _text('{Ma_Hang}', m, h * 0.75, (w - 2 * m) * 0.42, h * 0.22, size: 6.5 * k),
        _text('{Don_Gia}đ/{Don_Vi_Tinh}', m + (w - 2 * m) * 0.42, h * 0.74, (w - 2 * m) * 0.58, h * 0.24,
            size: 10.5 * k, bold: true, align: PosLabelAlign.right),
      ]);
    }),
  ];

  // ── Tem cân ──────────────────────────────────────────────────────────────
  static final _scale = <PosLabelDesignPreset>[
    PosLabelDesignPreset('scale_std', 'Tem cân chuẩn', 'Cửa hàng · tên · KL / đơn giá · thành tiền · mã cân · HSD',
        (w, h) {
      const m = 1.2;
      final k = _k(h);
      final cw = w - 2 * m;
      return _d(PosPrintDocumentTypes.scaleLabel, w, h, 'Tem cân chuẩn', [
        _text('{Ten_Cua_Hang}', m, m * 0.5, cw, h * 0.11, size: 6 * k, bold: true, align: PosLabelAlign.center),
        _text('{Ten_Hang_Hoa}', m, h * 0.11, cw, h * 0.18, size: 9 * k, bold: true, align: PosLabelAlign.center),
        _text('KL: {Khoi_Luong}', m, h * 0.30, cw * 0.5, h * 0.13, size: 7.5 * k, bold: true),
        _text('{Don_Gia_Kg}', m + cw * 0.5, h * 0.30, cw * 0.5, h * 0.13,
            size: 7.5 * k, bold: true, align: PosLabelAlign.right),
        _text('{Thanh_Tien} đ', m, h * 0.44, cw, h * 0.21,
            size: 12 * k, bold: true, align: PosLabelAlign.center, invert: true),
        _barcode(m, h * 0.67, cw, h * 0.21),
        _text('In: {Ngay_Gio_In}', m, h * 0.885, cw * 0.55, h * 0.11, size: 5.5 * k),
        _text('HSD: {HSD}', m + cw * 0.55, h * 0.885, cw * 0.45, h * 0.11,
            size: 5.5 * k, bold: true, align: PosLabelAlign.right),
      ]);
    }),
    PosLabelDesignPreset('scale_compact', 'Gọn (tem nhỏ)', 'Tên · KL × đơn giá · thành tiền · mã cân', (w, h) {
      const m = 1.2;
      final k = _k(h);
      final cw = w - 2 * m;
      return _d(PosPrintDocumentTypes.scaleLabel, w, h, 'Tem cân gọn', [
        _text('{Ten_Hang_Hoa}', m, m * 0.5, cw, h * 0.2, size: 8.5 * k, bold: true, align: PosLabelAlign.center),
        _text('{Khoi_Luong} × {Don_Gia_Kg}', m, h * 0.21, cw, h * 0.15, size: 7 * k, align: PosLabelAlign.center),
        _text('{Thanh_Tien} đ', m, h * 0.37, cw, h * 0.22, size: 12 * k, bold: true, align: PosLabelAlign.center),
        _barcode(m, h * 0.6, cw, h * 0.28),
        _text('HSD: {HSD}', m, h * 0.885, cw, h * 0.11, size: 5.5 * k, bold: true, align: PosLabelAlign.center),
      ]);
    }),
    PosLabelDesignPreset('scale_side', 'Thành tiền bên phải', 'Mã cân bên trái, ô thành tiền nền đen bên phải',
        (w, h) {
      const m = 1.2;
      final k = _k(h);
      final cw = w - 2 * m;
      final rightW = cw * 0.42;
      return _d(PosPrintDocumentTypes.scaleLabel, w, h, 'Tem cân thành tiền bên phải', [
        _text('{Ten_Hang_Hoa}', m, m * 0.5, cw, h * 0.2, size: 9 * k, bold: true),
        _text('KL: {Khoi_Luong}', m, h * 0.22, cw - rightW - m, h * 0.13, size: 7 * k, bold: true),
        _text('ĐG: {Don_Gia_Kg}', m, h * 0.35, cw - rightW - m, h * 0.13, size: 7 * k),
        _text('Thành tiền\n{Thanh_Tien} đ', w - m - rightW, h * 0.22, rightW, h * 0.3,
            size: 9 * k, bold: true, align: PosLabelAlign.center, lines: 2, invert: true),
        _barcode(m, h * 0.54, cw, h * 0.32),
        _text('In: {Ngay_Gio_In} · HSD: {HSD}', m, h * 0.885, cw, h * 0.11, size: 5.5 * k, align: PosLabelAlign.center),
      ]);
    }),
  ];

  // ── Tem ly / tem báo bếp ─────────────────────────────────────────────────
  static final _kitchen = <PosLabelDesignPreset>[
    PosLabelDesignPreset('cup_std', 'Tem ly chuẩn', 'Bàn · thứ tự ly · tên món · topping / ghi chú · mã đơn · giờ', (w, h) {
      const m = 1.2;
      final k = _k(h);
      final cw = w - 2 * m;
      return _d(PosPrintDocumentTypes.kitchenLabel, w, h, 'Tem ly chuẩn', [
        _text('{Ten_Ban}', m, m * 0.5, cw * 0.65, h * 0.17, size: 8 * k, bold: true),
        _text('{So_Luong}', m + cw * 0.65, m * 0.5, cw * 0.35, h * 0.17, size: 8 * k, bold: true, align: PosLabelAlign.right),
        _text('{Ten_Hang_Hoa}', m, h * 0.19, cw, h * 0.3, size: 10 * k, bold: true, lines: 2),
        _text('{Ghi_Chu}', m, h * 0.5, cw, h * 0.34, size: 6.5 * k, lines: 3),
        _text('{Ma_Don_Hang}', m, h * 0.86, cw * 0.5, h * 0.13, size: 5.5 * k),
        _text('{Gio} {Ngay}', m + cw * 0.5, h * 0.86, cw * 0.5, h * 0.13, size: 5.5 * k, align: PosLabelAlign.right),
      ]);
    }),
    PosLabelDesignPreset('cup_bar', 'Thanh bàn nền đen', 'Bàn · ly trên thanh đen, tên món to, size · giá', (w, h) {
      const m = 1.2;
      final k = _k(h);
      final cw = w - 2 * m;
      return _d(PosPrintDocumentTypes.kitchenLabel, w, h, 'Tem ly thanh bàn', [
        _text('{Ten_Ban} · Ly {So_Luong}', 0, 0, w, h * 0.19, size: 8 * k, bold: true, align: PosLabelAlign.center, invert: true),
        _text('{Ten_Hang_Hoa}', m, h * 0.21, cw, h * 0.32, size: 10.5 * k, bold: true, align: PosLabelAlign.center, lines: 2),
        _text('{Ghi_Chu}', m, h * 0.54, cw, h * 0.3, size: 6.5 * k, align: PosLabelAlign.center, lines: 3),
        _text('{Don_Vi_Tinh}', m, h * 0.86, cw * 0.4, h * 0.13, size: 6 * k, bold: true),
        _text('{Don_Gia}đ · {Gio}', m + cw * 0.4, h * 0.86, cw * 0.6, h * 0.13, size: 6 * k, align: PosLabelAlign.right),
      ]);
    }),
    PosLabelDesignPreset('cup_store', 'Có tên quán', 'Tên quán · tên món · topping · bàn · giờ', (w, h) {
      const m = 1.2;
      final k = _k(h);
      final cw = w - 2 * m;
      return _d(PosPrintDocumentTypes.kitchenLabel, w, h, 'Tem ly có tên quán', [
        _text('{Ten_Cua_Hang}', m, m * 0.4, cw, h * 0.14, size: 6.5 * k, bold: true, align: PosLabelAlign.center),
        PosLabelElement(id: newId(), type: PosLabelElementType.line, x: m, y: h * 0.16, w: cw, h: 0.6, strokeMm: 0.25),
        _text('{Ten_Hang_Hoa}', m, h * 0.19, cw, h * 0.3, size: 10 * k, bold: true, align: PosLabelAlign.center, lines: 2),
        _text('{Ghi_Chu}', m, h * 0.5, cw, h * 0.33, size: 6.5 * k, align: PosLabelAlign.center, lines: 3),
        _text('{Ten_Ban} · {So_Luong}', m, h * 0.85, cw * 0.6, h * 0.14, size: 6.5 * k, bold: true),
        _text('{Gio}', m + cw * 0.6, h * 0.85, cw * 0.4, h * 0.14, size: 6 * k, align: PosLabelAlign.right),
      ]);
    }),
  ];

  // ── Tem thông số ─────────────────────────────────────────────────────────
  static final _spec = <PosLabelDesignPreset>[
    PosLabelDesignPreset('spec_qr', 'Thông số + QR', 'Tên · thương hiệu / KL / KT / bảo hành · QR bên phải', (w, h) {
      const m = 1.5;
      final k = _k(h);
      final side = math.min(h * 0.68, w * 0.38);
      final leftW = w - side - 3 * m;
      final top = h * 0.24;
      final rowH = (h - top - m) / 5;
      final rows = ['Mã: {Ma_Hang}', 'TH: {Thuong_Hieu}', 'KL: {Khoi_Luong_SP}', 'KT: {Kich_Thuoc}', 'BH: {Bao_Hanh}'];
      return _d(PosPrintDocumentTypes.specLabel, w, h, 'Tem thông số + QR', [
        _text('{Ten_Hang_Hoa}', m, m * 0.6, w - 2 * m, h * 0.22, size: 9 * k, bold: true, lines: 2),
        for (var i = 0; i < rows.length; i++)
          _text(rows[i], m, top + i * rowH, leftW, rowH, size: 6.5 * k, bold: i == rows.length - 1),
        _qr('{Ma_Hang}\n{Ten_Hang_Hoa}\n{Thong_So}', w - m - side, h - m - side, side),
      ]);
    }),
    PosLabelDesignPreset('spec_barcode', 'Thông số + mã vạch', 'Tên · dòng thông số gộp · mã vạch', (w, h) {
      const m = 1.5;
      final k = _k(h);
      return _d(PosPrintDocumentTypes.specLabel, w, h, 'Tem thông số + mã vạch', [
        _text('{Ten_Hang_Hoa}', m, m * 0.6, w - 2 * m, h * 0.22, size: 9 * k, bold: true, lines: 2),
        _text('{Thong_So}', m, h * 0.26, w - 2 * m, h * 0.36, size: 6.5 * k, lines: 3),
        _barcode(m, h * 0.64, w - 2 * m, h * 0.34),
      ]);
    }),
    PosLabelDesignPreset('spec_warranty', 'Tem bảo hành', 'Tên · mã · ngày · thời hạn bảo hành nổi bật', (w, h) {
      const m = 1.5;
      final k = _k(h);
      final cw = w - 2 * m;
      return _d(PosPrintDocumentTypes.specLabel, w, h, 'Tem bảo hành', [
        _text('{Ten_Cua_Hang}', m, m * 0.5, cw, h * 0.14, size: 6.5 * k, bold: true, align: PosLabelAlign.center),
        _text('{Ten_Hang_Hoa}', m, h * 0.16, cw, h * 0.22, size: 8.5 * k, bold: true, align: PosLabelAlign.center, lines: 2),
        _text('BẢO HÀNH {Bao_Hanh}', m, h * 0.4, cw, h * 0.2,
            size: 10 * k, bold: true, align: PosLabelAlign.center, invert: true),
        _barcode(m, h * 0.63, cw, h * 0.25),
        _text('Ngày: {Ngay}', m, h * 0.885, cw, h * 0.11, size: 5.5 * k, align: PosLabelAlign.center),
      ]);
    }),
  ];
}
