import 'dart:convert';
import 'dart:typed_data';

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import 'pos_einvoice_qr.dart';
import 'pos_print_template_renderer.dart';
import 'pos_receipt_layout.dart';
import 'pos_table_label.dart';
import 'pos_thermal_bitmap.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Khoảng trống / thụt lề của một bước in (điểm in), lấy từ kiểu khối.
class PosPrintStepLayout {
  const PosPrintStepLayout({
    this.spaceBefore = 0,
    this.spaceAfter = 0,
    this.indentLeft = 0,
    this.indentRight = 0,
    this.minHeight = 0,
  });

  final double spaceBefore;
  final double spaceAfter;
  final double indentLeft;
  final double indentRight;
  final double minHeight;
}

/// Khối ảnh / logo đã biên dịch.
class PosPrintCompiledImage {
  const PosPrintCompiledImage({
    required this.bytes,
    this.widthFrac = 0.6,
    this.align = PosPrintTextAlign.center,
    this.layout,
    this.sourceBlockIndex,
  });

  final Uint8List bytes;
  final double widthFrac;
  final PosPrintTextAlign align;
  final PosPrintStepLayout? layout;
  final int? sourceBlockIndex;
}

/// Một dòng in Sunmi / bitmap sau biên dịch.
class PosPrintCompiledLine {
  const PosPrintCompiledLine({
    required this.text,
    this.fontSize = 24,
    this.bold = false,
    this.center = false,
    this.right = false,
    this.isDivider = false,
    this.dividerEquals = false,
    this.sourceBlockIndex,
    this.layout,
  });

  final PosPrintStepLayout? layout;
  final String text;
  final double fontSize;
  final bool bold;
  final bool center;
  final bool right;
  final bool isDivider;
  final bool dividerEquals;
  final int? sourceBlockIndex;

  PosReceiptImageLine toImageLine() => PosReceiptImageLine(
        text: isDivider ? '' : tr(text),
        fontSize: fontSize,
        bold: bold,
        center: center,
        right: right,
        isDivider: isDivider,
      );
}

/// Cặp nhãn — giá trị (Sunmi printRow).
class PosPrintCompiledPair {
  const PosPrintCompiledPair({
    required this.left,
    required this.right,
    this.fontSize = 24,
    this.bold = false,
    this.sourceBlockIndex,
    this.layout,
  });

  final PosPrintStepLayout? layout;
  final String left;
  final String right;
  final double fontSize;
  final bool bold;
  final int? sourceBlockIndex;
}

/// Một hàng hóa đơn: Tên | SL | Đ.giá | T.tiền — cột ẩn khi [showQty]/[showPrice]/[showTotal] = false.
class PosPrintCompiledSaleRow {
  const PosPrintCompiledSaleRow({
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
    this.fontSize = 24,
    this.bold = true,
    this.showQty = true,
    this.showPrice = true,
    this.showTotal = true,
    this.sourceBlockIndex,
    this.layout,
  });

  final PosPrintStepLayout? layout;
  final String name;
  final String qty;
  final String price;
  final String total;
  final double fontSize;
  final bool bold;
  final bool showQty;
  final bool showPrice;
  final bool showTotal;
  final int? sourceBlockIndex;

  /// Chỉ in tên hàng — không cột SL / đơn giá / thành tiền.
  bool get nameOnly => !showQty && !showPrice && !showTotal;
}

/// Khối in mã VietQR.
class PosPrintCompiledQr {
  const PosPrintCompiledQr({
    required this.imageUrl,
    this.size = 160,
    this.title,
    this.caption = 'Quét VietQR thanh toán',
    this.amountText,
    this.sourceBlockIndex,
  });

  final String imageUrl;
  final int size;
  final String? title;
  final String caption;
  final String? amountText;
  final int? sourceBlockIndex;
}

/// Khối in mã vạch CODE128.
class PosPrintCompiledBarcode {
  const PosPrintCompiledBarcode({
    required this.data,
    this.height = 60,
    this.showText = true,
    this.sourceBlockIndex,
  });

  final String data;
  final int height;
  final bool showText;
  final int? sourceBlockIndex;
}

/// Kết quả biên dịch mẫu V2.
class PosPrintCompiledOutput {
  const PosPrintCompiledOutput({
    required this.steps,
    required this.html,
    this.frameStyle = PosPrintFrameStyle.none,
    this.frameInsetMm = 2.5,
    this.frameMarginMm = 1.5,
    this.sidePaddingMm,
  });

  /// Lề trái/phải nội dung (mm) — null = mặc định máy.
  final double? sidePaddingMm;
  /// Xen kẽ dòng chữ và cặp nhãn-giá trị theo thứ tự in.
  final List<Object> steps;
  final String html;
  final PosPrintFrameStyle frameStyle;
  final double frameInsetMm;
  final double frameMarginMm;

  List<PosReceiptImageLine> get imageLines => steps
      .whereType<PosPrintCompiledLine>()
      .map((l) => l.toImageLine())
      .toList();

  /// Đủ loại bước (kể cả hàng hóa / cặp tiền) — in ảnh Sunmi đúng khổ giấy.
  List<PosReceiptImageLine> get printImageLines {
    final out = <PosReceiptImageLine>[];
    for (final step in steps) {
      final line = compiledStepToImageLine(step);
      if (line != null) out.add(line);
    }
    return out;
  }
}

PosReceiptImageLine? compiledStepToImageLine(Object step) {
  const none = PosPrintStepLayout();
  if (step is PosPrintCompiledImage) {
    final l = step.layout ?? none;
    return PosReceiptImageLine(
      text: '',
      imageBytes: step.bytes,
      imageWidthFrac: step.widthFrac,
      center: step.align == PosPrintTextAlign.center,
      right: step.align == PosPrintTextAlign.right,
      spaceBefore: l.spaceBefore,
      spaceAfter: l.spaceAfter,
      indentLeft: l.indentLeft,
      indentRight: l.indentRight,
      sourceBlockIndex: step.sourceBlockIndex,
    );
  }
  if (step is PosPrintCompiledLine) {
    final l = step.layout ?? none;
    if (step.isDivider) {
      return PosReceiptImageLine(
        text: '',
        isDivider: true,
        spaceBefore: l.spaceBefore,
        spaceAfter: l.spaceAfter,
        indentLeft: l.indentLeft,
        indentRight: l.indentRight,
        sourceBlockIndex: step.sourceBlockIndex,
      );
    }
    if (step.text.trim().isEmpty) {
      return PosReceiptImageLine(
        text: '',
        fontSize: 10,
        spaceBefore: l.spaceBefore,
        spaceAfter: l.spaceAfter,
        minHeight: l.minHeight,
        sourceBlockIndex: step.sourceBlockIndex,
      );
    }
    return PosReceiptImageLine(
      text: step.text,
      fontSize: designedThermalFontSize(step.fontSize),
      bold: step.bold,
      center: step.center,
      right: step.right,
      spaceBefore: l.spaceBefore,
      spaceAfter: l.spaceAfter,
      indentLeft: l.indentLeft,
      indentRight: l.indentRight,
      sourceBlockIndex: step.sourceBlockIndex,
    );
  }
  if (step is PosPrintCompiledPair) {
    final l = step.layout ?? none;
    final right = step.right.trim();
    return PosReceiptImageLine(
      text: step.left,
      rightText: right,
      rightSlotFrac: PosPrintTemplateCompiler.pairRightSlotFrac(right),
      fontSize: designedThermalFontSize(step.fontSize),
      bold: step.bold,
      spaceBefore: l.spaceBefore,
      spaceAfter: l.spaceAfter,
      indentLeft: l.indentLeft,
      indentRight: l.indentRight,
      sourceBlockIndex: step.sourceBlockIndex,
    );
  }
  if (step is PosPrintCompiledSaleRow) {
    final l = step.layout ?? none;
    if (step.nameOnly) {
      return PosReceiptImageLine(
        text: step.name,
        fontSize: designedThermalFontSize(step.fontSize),
        bold: step.bold,
        spaceBefore: l.spaceBefore,
        spaceAfter: l.spaceAfter,
        indentLeft: l.indentLeft,
        indentRight: l.indentRight,
        sourceBlockIndex: step.sourceBlockIndex,
      );
    }
    if (step.showQty && !step.showPrice && !step.showTotal) {
      return PosReceiptImageLine(
        text: step.name,
        rightText: step.qty,
        rightSlotFrac: PosPrintTemplateCompiler.pairRightSlotFrac(step.qty),
        fontSize: designedThermalFontSize(step.fontSize),
        bold: step.bold,
        spaceBefore: l.spaceBefore,
        spaceAfter: l.spaceAfter,
        indentLeft: l.indentLeft,
        indentRight: l.indentRight,
        sourceBlockIndex: step.sourceBlockIndex,
      );
    }
    return PosReceiptImageLine(
      text: step.name,
      colQty: step.showQty ? step.qty : null,
      colPrice: step.showPrice ? step.price : null,
      colTotal: step.showTotal ? step.total : null,
      fontSize: designedThermalFontSize(step.fontSize),
      bold: step.bold,
      spaceBefore: l.spaceBefore,
      spaceAfter: l.spaceAfter,
      indentLeft: l.indentLeft,
      indentRight: l.indentRight,
      sourceBlockIndex: step.sourceBlockIndex,
    );
  }
  return null;
}

/// Gắn khoảng trống / thụt lề / chữ HOA của từng khối vào các bước in của khối đó
/// (khoảng trên = bước đầu, khoảng dưới = bước cuối, thụt lề = mọi bước).
List<Object> applyPosPrintBlockLayout(List<Object> steps, List<PosPrintBlock> blocks) {
  int? idx(Object s) => switch (s) {
        PosPrintCompiledLine x => x.sourceBlockIndex,
        PosPrintCompiledPair x => x.sourceBlockIndex,
        PosPrintCompiledSaleRow x => x.sourceBlockIndex,
        PosPrintCompiledImage x => x.sourceBlockIndex,
        _ => null,
      };
  final first = <int, int>{};
  final last = <int, int>{};
  for (var i = 0; i < steps.length; i++) {
    final b = idx(steps[i]);
    if (b == null) continue;
    first.putIfAbsent(b, () => i);
    last[b] = i;
  }
  final out = List<Object>.from(steps);
  for (var i = 0; i < out.length; i++) {
    final bi = idx(out[i]);
    if (bi == null || bi < 0 || bi >= blocks.length) continue;
    final block = blocks[bi];
    final st = block.style;
    final spacer = block.type == PosPrintBlockType.spacer;
    if (!st.hasLayout && !st.uppercase && !spacer) continue;
    final layout = PosPrintStepLayout(
      spaceBefore: first[bi] == i ? st.spaceBefore : 0,
      spaceAfter: last[bi] == i ? st.spaceAfter : 0,
      indentLeft: st.indentLeft,
      indentRight: st.indentRight,
      minHeight: spacer ? block.height.clamp(0.0, 400.0) : 0,
    );
    String up(String v) => st.uppercase ? v.toUpperCase() : v;
    final s = out[i];
    out[i] = switch (s) {
      PosPrintCompiledLine x => PosPrintCompiledLine(
          text: x.isDivider ? x.text : up(x.text),
          fontSize: x.fontSize,
          bold: x.bold,
          center: x.center,
          right: x.right,
          isDivider: x.isDivider,
          dividerEquals: x.dividerEquals,
          sourceBlockIndex: x.sourceBlockIndex,
          layout: layout,
        ),
      PosPrintCompiledPair x => PosPrintCompiledPair(
          left: up(x.left),
          right: up(x.right),
          fontSize: x.fontSize,
          bold: x.bold,
          sourceBlockIndex: x.sourceBlockIndex,
          layout: layout,
        ),
      PosPrintCompiledSaleRow x => PosPrintCompiledSaleRow(
          name: up(x.name),
          qty: x.qty,
          price: x.price,
          total: x.total,
          fontSize: x.fontSize,
          bold: x.bold,
          showQty: x.showQty,
          showPrice: x.showPrice,
          showTotal: x.showTotal,
          sourceBlockIndex: x.sourceBlockIndex,
          layout: layout,
        ),
      PosPrintCompiledImage x => PosPrintCompiledImage(
          bytes: x.bytes,
          widthFrac: x.widthFrac,
          align: x.align,
          sourceBlockIndex: x.sourceBlockIndex,
          layout: layout,
        ),
      _ => s,
    };
  }
  return out;
}

/// Giải mã ảnh base64 của khối ảnh (rỗng / hỏng → null).
Uint8List? decodePosPrintImageData(String? data) {
  if (data == null || data.trim().isEmpty) return null;
  try {
    final raw = data.contains(',') ? data.substring(data.indexOf(',') + 1) : data;
    return base64Decode(raw.trim());
  } catch (_) {
    return null;
  }
}

/// Cỡ chữ in = cỡ trên trang chỉnh sửa (14–48). Không kẹp xuống 24px.
double designedThermalFontSize(double fontSize) => fontSize.clamp(12.0, 64.0);

/// Mẫu nhiệt / tem: cỡ chữ, khoảng cách trong mẫu là ĐIỂM IN (K80 = 576 điểm / 80 mm).
/// HTML trước đây ghi thẳng «px» → chữ to gần gấp đôi so với bản in; đổi sang mm cho đúng tỉ lệ.
String thermalHtmlToMm(String html, String paperSize) {
  if (paperSize == PosPrintPaperSizes.a4 || paperSize == PosPrintPaperSizes.a5) return html;
  final widthMm = PosPrintPaperSizes.widthMm(paperSize);
  final dots = PosPrintPaperSizes.isLabelSize(paperSize)
      ? widthMm * 203 / 25.4
      : (widthMm <= 58 ? 384.0 : 576.0);
  final k = widthMm / dots;
  return html
      .replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)px'), (m) {
        final v = double.parse(m.group(1)!) * k;
        return '${v.toStringAsFixed(2)}mm';
      })
      .replaceFirst('font-family:Arial,sans-serif;', "font-family:'Be Vietnam Pro',Arial,sans-serif;line-height:1.28;");
}

/// Biên dịch mẫu V2 → HTML preview + dòng in nhiệt/Sunmi.
abstract final class PosPrintTemplateCompiler {
  /// Nhãn mặc định cho các dòng tổng — UI / presets có thể ghi đè qua fieldLabels.
  static const defaultTotalLabels = <String, String>{
    'Tong_Tien_Hang': 'Tổng tiền hàng',
    'Chiet_Khau_Hoa_Don': 'Chiết khấu',
    'Tien_Thue': 'Thuế',
    'Thue': 'Thuế',
    'VAT': 'VAT',
    'Phu_Thu': 'Phụ thu',
    'Phi_Giao_Hang': 'Phí giao hàng',
    'Tong_Cong': 'Tổng cộng',
    'Khach_Can_Tra': 'Khách cần trả',
    'Khach_Thanh_Toan': 'Đã thanh toán',
    'Tien_Thua': 'Tiền thừa',
    'Con_Lai': 'Còn lại',
    'Hinh_Thuc_Thanh_Toan': 'HTTT',
    'Tong_Cong_Bang_Chu': 'Bằng chữ',
  };

  static const defaultColumnLabels = <String, String>{
    'Ten_Hang_Hoa': 'Tên hàng',
    'Don_Gia': 'Đơn giá',
    'So_Luong': 'SL',
    'Thanh_Tien': 'Thành tiền',
  };

  /// Header cột K58 — chữ ngắn để khỏi vỡ "Đơn" / "Thanh".
  static const k58ColumnLabels = <String, String>{
    'Ten_Hang_Hoa': 'Tên hàng',
    'Don_Gia': 'Đ.giá',
    'So_Luong': 'SL',
    'Thanh_Tien': 'T.T',
  };

  static String resolveFieldLabel(
    PosPrintBlock block,
    String token, {
    String? fallback,
    bool k58 = false,
  }) {
    final custom = block.fieldLabels?[token]?.trim();
    if (custom != null && custom.isNotEmpty) {
      if (k58 && k58ColumnLabels.containsKey(token) && custom.length > 6) {
        return k58ColumnLabels[token]!;
      }
      return restoreVietnamesePrintLabel(custom);
    }
    if (k58 && k58ColumnLabels.containsKey(token)) {
      return k58ColumnLabels[token]!;
    }
    if (fallback != null && fallback.isNotEmpty) {
      return restoreVietnamesePrintLabel(fallback);
    }
    return restoreVietnamesePrintLabel(
      defaultTotalLabels[token] ?? defaultColumnLabels[token] ?? token,
    );
  }

  static bool _isK58InvoiceMetaKey(String key) =>
      key == 'Ma_Don_Hang' || key == 'Ngay' || key == 'Gio';

  static String _k58InvoiceMetaLabel(String key) => switch (key) {
        'Ma_Don_Hang' => 'Số HĐ',
        'Ngay' => 'Ngày',
        'Gio' => 'Giờ',
        _ => key,
      };

  static String _withPrefix(String? label, String value) {
    final l = (label ?? '').trim();
    if (l.isEmpty) return value;
    if (l.endsWith(':') || l.endsWith('：') || l.endsWith(' ')) {
      return '$l$value';
    }
    return '$l: $value';
  }

  /// SL / ĐVT tách riêng trên tem bếp — compiler gộp vào tên món, không in khối này.
  static bool kitchenLabelHidesBlock(PosPrintBlock block) {
    if (block.type == PosPrintBlockType.text &&
        _isQtyOnlyToken(block.text ?? '')) {
      return true;
    }
    if (block.type == PosPrintBlockType.field &&
        _isKitchenLabelQtyField(block.field)) {
      return true;
    }
    if (block.type == PosPrintBlockType.pair &&
        _isKitchenLabelQtyField(block.leftField) &&
        ((block.rightField ?? '').isEmpty ||
            _isKitchenLabelQtyField(block.rightField))) {
      return true;
    }
    return false;
  }

  static bool _isQtyOnlyToken(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    // Chỉ token số lượng / đơn vị — đã gộp cạnh tên món trên tem.
    final compact = s.replaceAll(RegExp(r'\s+'), ' ');
    return compact == '{So_Luong}' ||
        compact == '{So_Luong} {Don_Vi_Tinh}' ||
        compact == '{Don_Vi_Tinh}' ||
        compact == 'SL: {So_Luong}' ||
        compact == 'SL:{So_Luong}' ||
        compact == 'SL {So_Luong}' ||
        compact == 'SL: {So_Luong} {Don_Vi_Tinh}' ||
        compact == 'SL:{So_Luong} {Don_Vi_Tinh}' ||
        RegExp(r'^SL\s*:\s*\{So_Luong\}(\s*\{Don_Vi_Tinh\})?$',
                caseSensitive: false)
            .hasMatch(compact);
  }

  static bool _isKitchenLabelQtyField(String? field) {
    final f = (field ?? '').trim();
    return f == 'So_Luong' || f == 'Don_Vi_Tinh';
  }

  static PosPrintTextStyle _toppingNoteStyle(PosPrintTextStyle base) =>
      PosPrintTextStyle(
        fontSize: (base.fontSize - 6).clamp(11.0, 36.0),
        bold: false,
        align: PosPrintTextAlign.left,
      );

  static String _resolveToken(String raw, Map<String, String> data) {
    var s = raw;
    for (final e in data.entries) {
      s = s.replaceAll('{${e.key}}', e.value);
    }
    // Mẫu cũ từng hard-code chữ mẫu «Mười sáu triệu…» — thay bằng tổng đúng.
    final bangChu = data['Tong_Cong_Bang_Chu'];
    if (bangChu != null &&
        bangChu.isNotEmpty &&
        s.contains('đồng chẵn') &&
        !s.contains('{Tong_Cong_Bang_Chu}')) {
      s = s.replaceAll(RegExp(r'[^\n]*đồng chẵn'), bangChu);
    }
    return s;
  }

  static int defaultDividerChars(String paperSize) =>
      paperSize == PosPrintPaperSizes.k58 ? 52 : 68;

  /// Rỗng / 0 / gạch — không in dù khối đang bật trong mẫu.
  static bool isBlankPrintValue(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return true;
    const blanks = {'—', '-', '–', '...', 'N/A', 'n/a'};
    if (blanks.contains(s)) return true;
    final lower = s.toLowerCase();
    if (lower == 'bán cho người tiêu dùng' || lower == 'khách lẻ') {
      return true;
    }
    final compact = s.replaceAll(RegExp(r'[\s.,đĐ₫vndVND]'), '');
    return compact == '0';
  }

  static double pairRightSlotFrac(String right) {
    final n = right.trim().length;
    if (n <= 6) return 0.24;
    if (n <= 9) return 0.36;
    if (n <= 12) return 0.46;
    return 0.55;
  }

  static bool _textTokensAllBlank(String template, Map<String, String> data) {
    final tokens = RegExp(r'\{([^}]+)\}').allMatches(template);
    if (tokens.isEmpty) return false;
    return tokens.every((m) => isBlankPrintValue(data[m.group(1)]));
  }

  static PosPrintCompiledOutput compile({
    required PosPrintTemplateV2 template,
    required Map<String, String> data,
    required List<Map<String, String>> lineItems,
    List<Map<String, String>>? kitchenLines,
    String? vietQrImageUrl,
  }) {
    final steps = <Object>[];
    final htmlBuf = StringBuffer();
    final width = PosPrintPaperSizes.widthMm(template.paperSize);

    data = Map<String, String>.from(data);
    final rawHd = data['Ma_Don_Hang'];
    if (rawHd != null && rawHd.trim().isNotEmpty) {
      data['Ma_Don_Hang'] = PosReceiptLayout.formatSaleInvoiceNo(rawHd);
    }

    final k58 = template.paperSize == PosPrintPaperSizes.k58;
    final isSaleDoc = template.documentType == PosPrintDocumentTypes.saleInvoice ||
        template.documentType == PosPrintDocumentTypes.saleReturn;
    var working = template;
    if (k58 && isSaleDoc) {
      PosPrintTextStyle shrink(PosPrintTextStyle s) {
        if (s.fontSize <= 18) return s;
        return s.copyWith(fontSize: (s.fontSize - 2).clamp(14.0, 48.0));
      }
      working = template.copyWith(
        blocks: template.blocks
            .map((b) => b.copyWith(
                  style: shrink(b.style),
                  rightStyle: shrink(b.rightStyle ?? b.style),
                ))
            .toList(),
      );
    }

    final isKitchenLabel =
        working.documentType == PosPrintDocumentTypes.kitchenLabel;
    final isBarcodeLabel =
        working.documentType == PosPrintDocumentTypes.barcodeLabel;
    var effectiveItems = lineItems;
    if (k58 && isSaleDoc) {
      effectiveItems = [
        for (final item in lineItems)
          {
            ...item,
            'Don_Gia': PosReceiptLayout.compactPrintedMoney(item['Don_Gia'] ?? ''),
            'Thanh_Tien':
                PosReceiptLayout.compactPrintedMoney(item['Thanh_Tien'] ?? ''),
          },
      ];
    }
    var effectiveKitchen = kitchenLines ?? lineItems;
    // Tem: khối「Tên hàng」lineItems — nếu caller chỉ điền data.Ten_Hang_Hoa thì tự tạo 1 dòng.
    if ((isKitchenLabel || isBarcodeLabel) && effectiveItems.isEmpty) {
      final name = (data['Ten_Hang_Hoa'] ?? '').trim();
      if (name.isNotEmpty) {
        effectiveItems = [
          {
            'Ten_Hang_Hoa': name,
            'So_Luong': data['So_Luong'] ?? '1',
            'Don_Vi_Tinh': data['Don_Vi_Tinh'] ?? '',
            'Ghi_Chu': data['Ghi_Chu'] ?? '',
            'Don_Gia': data['Don_Gia'] ?? '',
            'Ma_Hang': data['Ma_Hang'] ?? '',
            'Ma_Vach': data['Ma_Vach'] ?? '',
          },
        ];
      }
    }
    if (isKitchenLabel) {
      // Tem bếp: đúng 1 sản phẩm / 1 tem.
      if (effectiveItems.isNotEmpty) {
        final first = effectiveItems.first;
        for (final e in first.entries) {
          final cur = (data[e.key] ?? '').trim();
          if (cur.isEmpty && e.value.trim().isNotEmpty) {
            data[e.key] = e.value;
          }
        }
        effectiveItems = [first];
      }
      effectiveKitchen = effectiveItems.isNotEmpty
          ? effectiveItems
          : (effectiveKitchen.isEmpty
              ? effectiveKitchen
              : [effectiveKitchen.first]);
    }

    final framed = template.frameStyle != PosPrintFrameStyle.none;
    final framePad = framed ? template.frameInsetMm.clamp(1.0, 12.0) : 0.0;
    final frameMargin = framed ? template.frameMarginMm.clamp(0.5, 8.0) : 0.0;
    final frameRadius = template.frameStyle == PosPrintFrameStyle.rounded ? 5 : 0;
    final frameCss = framed
        ? 'border:1.6px solid #000;border-radius:${frameRadius}px;'
            'margin:${frameMargin}mm;padding:${framePad}mm;box-sizing:border-box;'
        : '';
    htmlBuf.write(
      '<div style="width:${width}mm;font-family:Arial,sans-serif;color:#000;$frameCss'
      '${!framed && template.sidePaddingMm != null ? 'padding:0 ${template.sidePaddingMm}mm;' : ''}">',
    );
    var skipNextKhu = false;
    for (var bi = 0; bi < working.blocks.length; bi++) {
      final block = working.blocks[bi];
      final st = block.style;
      final wrapHtml = st.hasLayout || st.uppercase;
      if (wrapHtml) {
        htmlBuf.write('<div style="'
            '${st.spaceBefore > 0 ? 'margin-top:${st.spaceBefore}px;' : ''}'
            '${st.spaceAfter > 0 ? 'margin-bottom:${st.spaceAfter}px;' : ''}'
            '${st.indentLeft > 0 ? 'padding-left:${st.indentLeft}px;' : ''}'
            '${st.indentRight > 0 ? 'padding-right:${st.indentRight}px;' : ''}'
            '${st.uppercase ? 'text-transform:uppercase;' : ''}">');
      }
      // try/finally: các nhánh dùng `continue` vẫn đóng thẻ bao khối.
      try {
      switch (block.type) {
        case PosPrintBlockType.image:
          final bytes = decodePosPrintImageData(block.imageData);
          if (bytes != null) {
            steps.add(PosPrintCompiledImage(
              bytes: bytes,
              widthFrac: block.imageWidthPct.clamp(10, 100) / 100,
              align: block.style.align,
              sourceBlockIndex: bi,
            ));
            final a = block.style.align.name;
            htmlBuf.write('<div style="text-align:$a;margin:2px 0">'
                '<img src="data:image/png;base64,${base64Encode(bytes)}" '
                'style="width:${block.imageWidthPct.clamp(10, 100)}%;height:auto"></div>');
          }
        case PosPrintBlockType.text:
          if (isKitchenLabel && _isQtyOnlyToken(block.text ?? '')) {
            continue;
          }
          final t = restoreVietnamesePrintLabel(
            _resolveToken(block.text ?? '', data),
          );
          if (t.trim().isNotEmpty &&
              !_textTokensAllBlank(block.text ?? '', data)) {
            steps.add(_lineFromStyle(t, block.style, sourceBlockIndex: bi));
            htmlBuf.write(_htmlText(t, block.style));
          }
        case PosPrintBlockType.field:
          if (block.field == 'Khu_Vuc' && skipNextKhu) {
            skipNextKhu = false;
            continue;
          }
          // Tem: SL đã nằm cùng hàng tên món — bỏ block So_Luong/ĐVT riêng.
          if (isKitchenLabel && _isKitchenLabelQtyField(block.field)) {
            continue;
          }
          if (isKitchenLabel && block.field == 'Ten_Hang_Hoa') {
            // Giống khối「Tên hàng」: tên ~3/4 khổ, SL góc phải; ghi chú () nếu bật.
            final showQty = block.showsLineField('So_Luong');
            final showUnit = block.showsLineField('Don_Vi_Tinh');
            final showNote = block.showsLineField('Ghi_Chu');
            final row = <String, String>{
              'Ten_Hang_Hoa': data['Ten_Hang_Hoa'] ?? '',
              'So_Luong': data['So_Luong'] ?? '',
              'Don_Vi_Tinh': data['Don_Vi_Tinh'] ?? '',
              'Ghi_Chu': data['Ghi_Chu'] ?? '',
              'Don_Gia': '',
              'Thanh_Tien': '',
            };
            _appendSaleLine(
              steps,
              row,
              block.style.copyWith(bold: true),
              showQty: showQty,
              showUnit: showUnit,
              showPrice: false,
              showTotal: false,
              showNote: showNote,
              sourceBlockIndex: bi,
              wrapNoteParens: true,
            );
            htmlBuf.write(
              _htmlLineItem(
                row,
                block.style.copyWith(bold: true),
                showQty: showQty,
                showUnit: showUnit,
                showPrice: false,
                showTotal: false,
                showNote: showNote,
                wrapNoteParens: true,
              ),
            );
            continue;
          }
          var raw = data[block.field ?? ''] ?? '';
          if (block.field == 'Ten_Ban') {
            raw = formatPosTableOneLine(
              areaName: data['Khu_Vuc'],
              tableName: data['Ten_Ban'],
            );
            skipNextKhu = true;
            if (raw.trim().isNotEmpty) {
              steps.add(_lineFromStyle(raw, block.style, sourceBlockIndex: bi));
              htmlBuf.write(_htmlText(raw, block.style));
            }
            continue;
          }
          // Luôn tính lại bằng chữ từ Tong_Cong (tránh mẫu hard-code cũ).
          if (block.field == 'Tong_Cong_Bang_Chu') {
            final fromData = data['Tong_Cong_Bang_Chu'];
            if (fromData != null && fromData.trim().isNotEmpty) {
              raw = fromData;
            }
          }
          if (k58 && isSaleDoc && block.field == 'Gio') {
            continue;
          }
          if (!isBlankPrintValue(raw)) {
            String? prefix = block.label?.trim();
            if (prefix == null || prefix.isEmpty) {
              final fieldKey = block.field;
              if (fieldKey != null) {
                prefix = block.fieldLabels?[fieldKey];
              }
            }
            if (prefix != null && prefix.isNotEmpty) {
              prefix = restoreVietnamesePrintLabel(prefix);
            }
            if (k58 && isSaleDoc && block.field == 'Ma_Don_Hang') {
              prefix ??= 'Số HĐ';
              final t = restoreVietnamesePrintLabel(_withPrefix(prefix, raw));
              steps.add(_lineFromStyle(
                t,
                block.style.copyWith(align: PosPrintTextAlign.left),
                sourceBlockIndex: bi,
              ));
              htmlBuf.write(_htmlText(
                t,
                block.style.copyWith(align: PosPrintTextAlign.left),
              ));
              continue;
            }
            if (k58 && isSaleDoc && block.field == 'Ngay') {
              prefix ??= 'Ngày';
              final gio = (data['Gio'] ?? '').trim();
              final dated = gio.isEmpty ? raw : '$raw  $gio';
              final t = restoreVietnamesePrintLabel(_withPrefix(prefix, dated));
              steps.add(_lineFromStyle(
                t,
                block.style.copyWith(align: PosPrintTextAlign.left),
                sourceBlockIndex: bi,
              ));
              htmlBuf.write(_htmlText(
                t,
                block.style.copyWith(align: PosPrintTextAlign.left),
              ));
              continue;
            }
            final parts = raw.split(RegExp(r'[\r\n]+'));
            for (var pi = 0; pi < parts.length; pi++) {
              var chunk = parts[pi].trim();
              if (chunk.isEmpty) continue;
              if (isKitchenLabel && block.field == 'Ghi_Chu') {
                chunk = _formatKitchenNote(chunk);
              }
              final t = pi == 0 ? _withPrefix(prefix, chunk) : chunk;
              final topping = chunk.startsWith('+') || chunk.startsWith('(+');
              final style = topping
                  ? _toppingNoteStyle(block.style)
                  : block.style;
              steps.add(_lineFromStyle(t, style, sourceBlockIndex: bi));
              htmlBuf.write(_htmlText(t, style));
            }
          }
        case PosPrintBlockType.pair:
          final leftKey = block.leftField ?? '';
          final rightKey = block.rightField ?? '';
          // Tem: cặp chỉ chứa SL/ĐVT — bỏ (đã gộp với tên món).
          if (isKitchenLabel &&
              _isKitchenLabelQtyField(leftKey) &&
              (rightKey.isEmpty || _isKitchenLabelQtyField(rightKey))) {
            continue;
          }
          var leftVal = data[leftKey] ?? '';
          var rightVal = data[rightKey] ?? '';
          if (isKitchenLabel && leftKey == 'Ten_Ban') {
            leftVal = formatPosTableOneLine(
              areaName: data['Khu_Vuc'],
              tableName: data['Ten_Ban'],
            );
            if (leftVal.trim().isEmpty) leftVal = data['Ten_Ban'] ?? '';
          }
          if (isKitchenLabel && leftKey == 'Ma_Don_Hang') {
            final hd = _withPrefix(
              block.fieldLabels?['Ma_Don_Hang'] ?? block.label ?? 'Số HĐ:',
              leftVal,
            );
            if (hd.trim().isNotEmpty) {
              steps.add(_lineFromStyle(hd, block.style, sourceBlockIndex: bi));
              htmlBuf.write(_htmlText(hd, block.style));
            }
            if (rightKey == 'Ngay' && rightVal.trim().isNotEmpty) {
              final ngay = _withPrefix(
                block.fieldLabels?['Ngay'] ?? 'Ngày:',
                rightVal,
              );
              steps.add(_lineFromStyle(ngay, block.style, sourceBlockIndex: bi));
              htmlBuf.write(_htmlText(ngay, block.style));
            }
            continue;
          }
          if (isBlankPrintValue(leftVal)) leftVal = '';
          if (isBlankPrintValue(rightVal)) rightVal = '';
          // K58: Số HĐ / Ngày mỗi loại một hàng — khỏi cắt HD30082026 và năm.
          if (k58 &&
              isSaleDoc &&
              _isK58InvoiceMetaKey(leftKey) &&
              _isK58InvoiceMetaKey(rightKey)) {
            void emitMeta(String key, String val) {
              final v = val.trim();
              if (v.isEmpty) return;
              final label = restoreVietnamesePrintLabel(
                block.fieldLabels?[key] ?? _k58InvoiceMetaLabel(key),
              );
              final t = _withPrefix(label, v);
              steps.add(_lineFromStyle(
                t,
                block.style.copyWith(align: PosPrintTextAlign.left),
                sourceBlockIndex: bi,
              ));
              htmlBuf.write(_htmlText(
                t,
                block.style.copyWith(align: PosPrintTextAlign.left),
              ));
            }

            final hd = leftKey == 'Ma_Don_Hang'
                ? leftVal
                : rightKey == 'Ma_Don_Hang'
                    ? rightVal
                    : '';
            var ngay = leftKey == 'Ngay'
                ? leftVal
                : rightKey == 'Ngay'
                    ? rightVal
                    : '';
            var gio = leftKey == 'Gio'
                ? leftVal
                : rightKey == 'Gio'
                    ? rightVal
                    : (data['Gio'] ?? '');
            if (hd.trim().isNotEmpty) emitMeta('Ma_Don_Hang', hd);
            if (ngay.trim().isEmpty) ngay = data['Ngay'] ?? '';
            if (ngay.trim().isNotEmpty) {
              final g = gio.trim();
              emitMeta('Ngay', g.isEmpty ? ngay : '$ngay  $g');
            } else if (gio.trim().isNotEmpty) {
              emitMeta('Gio', gio);
            }
            continue;
          }
          String? leftPrefix = block.label?.trim();
          if (leftPrefix == null || leftPrefix.isEmpty) {
            leftPrefix = block.fieldLabels?[leftKey];
          }
          leftPrefix = restoreVietnamesePrintLabel(leftPrefix ?? '');
          if (leftPrefix.isEmpty) leftPrefix = null;
          final rightRaw = block.fieldLabels?[rightKey];
          final rightPrefix = (rightRaw == null || rightRaw.trim().isEmpty)
              ? null
              : restoreVietnamesePrintLabel(rightRaw);
          final left = leftVal.isEmpty ? '' : _withPrefix(leftPrefix, leftVal);
          final right = rightVal.isEmpty
              ? ''
              : ((rightPrefix != null && rightPrefix.trim().isNotEmpty)
                  ? _withPrefix(rightPrefix, rightVal)
                  : rightVal);
          if (left.isEmpty && right.isEmpty) {
            continue;
          }
          if (right.isEmpty) {
            steps.add(_lineFromStyle(left, block.style, sourceBlockIndex: bi));
            htmlBuf.write(_htmlText(left, block.style));
            continue;
          }
          if (left.isEmpty) {
            steps.add(PosPrintCompiledPair(
              left: '',
              right: right,
              fontSize: block.style.fontSize,
              bold: block.style.bold,
              sourceBlockIndex: bi,
            ));
            htmlBuf.write(
              '<div style="text-align:right;white-space:nowrap;'
              'font-size:${block.style.fontSize}px;'
              '${block.style.bold ? 'font-weight:bold;' : ''}">$right</div>',
            );
            continue;
          }
          final tablePair = isKitchenLabel && leftKey == 'Ten_Ban';
          final pairSize = tablePair
              ? (block.style.fontSize + 6).clamp(16.0, 40.0)
              : block.style.fontSize;
          final pairBold = tablePair || block.style.bold;
          steps.add(PosPrintCompiledPair(
            left: left,
            right: right,
            fontSize: pairSize,
            bold: pairBold,
            sourceBlockIndex: bi,
          ));
          htmlBuf.write(
            '<div style="display:flex;justify-content:space-between;align-items:baseline;'
            'font-size:${pairSize}px;'
            '${pairBold ? 'font-weight:bold;' : ''}">'
            '<span style="padding-right:8px">$left</span>'
            '<span style="white-space:nowrap;flex-shrink:0">$right</span></div>',
          );
        case PosPrintBlockType.divider:
          // Đường kẻ đặc full khổ giấy — không dùng ===== / -----.
          steps.add(PosPrintCompiledLine(
            text: '',
            fontSize: 14,
            isDivider: true,
            dividerEquals: false,
            sourceBlockIndex: bi,
          ));
          htmlBuf.write(
            '<div style="border-top:1.5px solid #000;margin:6px 0;width:100%"></div>',
          );
        case PosPrintBlockType.lineItems:
          final fs = block.style.fontSize.clamp(14.0, 48.0);
          final headerStyle = block.rightStyle ?? block.style;
          final headerFs = headerStyle.fontSize.clamp(12.0, 48.0);
          final custom = block.usesCustomLineFields;
          final showQty = block.showsLineField('So_Luong');
          final showUnit = block.showsLineField('Don_Vi_Tinh');
          final showPrice = block.showsLineField('Don_Gia');
          final showTotal = !custom && block.showsLineField('Thanh_Tien');
          final showNote = !custom || block.showsLineField('Ghi_Chu');
          if (!custom && block.showColumnHeader) {
            _appendSaleTableHeader(
              steps,
              block,
              fontSize: headerFs,
              bold: headerStyle.bold,
              sourceBlockIndex: bi,
              k58: k58,
            );
          }
          htmlBuf.write(
            '<div style="font-size:${fs}px;margin:2px 0 6px;'
            '${block.style.bold ? 'font-weight:bold;' : ''}">',
          );
          htmlBuf.write('<!--BEGIN_ITEMS-->');
          for (final item in effectiveItems) {
            _appendSaleLine(
              steps,
              item,
              block.style,
              showQty: showQty,
              showUnit: showUnit,
              showPrice: showPrice,
              showTotal: showTotal,
              showNote: showNote,
              wrapNoteParens: isKitchenLabel,
              sourceBlockIndex: bi,
              k58: k58 && isSaleDoc,
            );
            htmlBuf.write(_htmlLineItem(
              item,
              block.style,
              showQty: showQty,
              showUnit: showUnit,
              showPrice: showPrice,
              showTotal: showTotal,
              showNote: showNote,
            ));
          }
          htmlBuf.write('<!--END_ITEMS-->');
          htmlBuf.write('</div>');
        case PosPrintBlockType.lineItemsKitchen:
          final kLines = effectiveKitchen;
          final kSize = block.style.fontSize.clamp(14.0, 48.0);
          for (var i = 0; i < kLines.length; i++) {
            final item = kLines[i];
            final name = item['Ten_Hang_Hoa'] ?? item['name'] ?? '';
            final qty = item['So_Luong'] ?? item['qty'] ?? '';
            final unit = item['Don_Vi_Tinh'] ?? item['unit'] ?? '';
            final note = item['Ghi_Chu'] ?? item['note'] ?? '';
            final right = unit.isEmpty ? qty : '$qty $unit';
            steps.add(PosPrintCompiledPair(
              left: '${i + 1}. $name',
              right: right,
              fontSize: kSize,
              bold: block.style.bold,
              sourceBlockIndex: bi,
            ));
            for (final raw in note.split(RegExp(r'[\r\n]+'))) {
              final part = raw.trim();
              if (part.isEmpty) continue;
              final topping = part.startsWith('+');
              steps.add(PosPrintCompiledLine(
                text: tr(topping ? '  $part' : '  * $part'),
                fontSize: topping
                    ? (kSize - 8).clamp(12.0, 36.0)
                    : (kSize - 6).clamp(12.0, 36.0),
                bold: false,
                sourceBlockIndex: bi,
              ));
            }
          }
        case PosPrintBlockType.totals:
          for (final key in block.fields ?? []) {
            final val = data[key] ?? '';
            if (isBlankPrintValue(val)) continue;
            final label = restoreVietnamesePrintLabel(
              resolveFieldLabel(block, key, k58: k58),
            );
            final isTotal = key == 'Tong_Cong';
            final style = isTotal ? (block.rightStyle ?? block.style) : block.style;
            final size = style.fontSize.clamp(14.0, 48.0);
            steps.add(PosPrintCompiledPair(
              left: label,
              right: val,
              fontSize: size,
              bold: style.bold,
              sourceBlockIndex: bi,
            ));
            htmlBuf.write(
              '<div style="display:flex;justify-content:space-between;align-items:baseline;'
              'font-size:${size}px;${style.bold ? 'font-weight:bold;' : ''}">'
              '<span style="padding-right:8px">$label</span>'
              '<span style="white-space:nowrap;flex-shrink:0">$val</span></div>',
            );
          }
        case PosPrintBlockType.spacer:
          steps.add(PosPrintCompiledLine(
            text: tr(' '),
            fontSize: 18,
            sourceBlockIndex: bi,
          ));
          htmlBuf.write('<div style="height:${block.height}px"></div>');
        case PosPrintBlockType.vietQr:
          if (vietQrImageUrl != null && vietQrImageUrl.isNotEmpty) {
            final title = restoreVietnamesePrintLabel(
              _resolveToken(block.qrTitle ?? '', data).trim(),
            );
            final caption = restoreVietnamesePrintLabel(
              _resolveToken(block.qrCaption, data).trim(),
            );
            final amount = block.qrShowAmount ? (data['Tong_Cong'] ?? '') : '';
            steps.add(PosPrintCompiledQr(
              imageUrl: vietQrImageUrl,
              size: block.qrSize.clamp(240, 400),
              title: title.isEmpty ? null : title,
              caption: caption.isEmpty ? 'Quét VietQR thanh toán' : caption,
              amountText: amount.trim().isEmpty ? null : amount.trim(),
              sourceBlockIndex: bi,
            ));
            htmlBuf.write(
              '<div style="text-align:center;margin:8px 0">'
              '<div style="border:1px dashed #999;padding:12px">[VietQR]</div>'
              '${caption.isNotEmpty ? '<div>$caption</div>' : ''}'
              '</div>',
            );
          }
        case PosPrintBlockType.barcode:
          final codeField = block.field ?? 'Ma_Vach';
          var code = (data[codeField] ?? '').trim();
          if (code.isEmpty) {
            code = (data['Ma_Hang'] ?? '').trim();
          }
          if (code.isNotEmpty) {
            final h = block.barcodeHeight.clamp(40, 120);
            steps.add(PosPrintCompiledBarcode(
              data: code,
              height: h,
              showText: block.barcodeShowText,
              sourceBlockIndex: bi,
            ));
            htmlBuf.write(
              '<div style="text-align:center;margin:6px 0">'
              '<div style="letter-spacing:1px;font-family:monospace;'
              'border:1px solid #999;padding:10px 6px;font-size:12px">'
              '|||| $code ||||</div>'
              '${block.barcodeShowText ? '<div style="margin-top:2px;font-size:11px">$code</div>' : ''}'
              '</div>',
            );
          }
      }
      } finally {
        if (wrapHtml) htmlBuf.write('</div>');
      }
    }

    if (isSaleDoc) {
      _appendEInvoiceBlock(steps, htmlBuf, working, data, k58: k58);
    }

    htmlBuf.write('</div>');
    final html = wrapPosPrintHtmlDocument(
      thermalHtmlToMm(htmlBuf.toString(), template.paperSize),
      paperSize: template.paperSize,
    );
    return PosPrintCompiledOutput(
      steps: applyPosPrintBlockLayout(steps, working.blocks),
      html: html,
      frameStyle: template.frameStyle,
      frameInsetMm: template.frameInsetMm,
      frameMarginMm: template.frameMarginMm,
      sidePaddingMm: template.sidePaddingMm,
    );
  }

  /// Mẫu đã tự đặt biến {HDDT_…} → chỉ thêm mã QR, không lặp lại chữ.
  static bool _templateUsesEInvoiceTokens(PosPrintTemplateV2 template) {
    bool has(String? v) => (v ?? '').contains('HDDT_');
    for (final b in template.blocks) {
      if (has(b.text) || has(b.field) || has(b.leftField) || has(b.rightField)) {
        return true;
      }
      if ((b.fields ?? const <String>[]).any((f) => f.startsWith('HDDT_'))) {
        return true;
      }
    }
    return false;
  }

  /// Khối HĐĐT cuối bill (khi đơn đã phát hành HĐĐT): ký hiệu, số, mã CQT, mã tra cứu, QR tra cứu.
  static void _appendEInvoiceBlock(
    List<Object> steps,
    StringBuffer htmlBuf,
    PosPrintTemplateV2 template,
    Map<String, String> data, {
    required bool k58,
  }) {
    final no = (data['HDDT_So'] ?? '').trim();
    final qrData = (data['HDDT_QR'] ?? '').trim();
    if (no.isEmpty || qrData.isEmpty) return;
    final body = k58 ? 20.0 : 22.0;
    final small = k58 ? 18.0 : 20.0;

    void line(String text, {double? size, bool bold = false, bool center = true}) {
      steps.add(PosPrintCompiledLine(
        text: text,
        fontSize: size ?? body,
        bold: bold,
        center: center,
      ));
      htmlBuf.write(
        '<div style="text-align:${center ? 'center' : 'left'};font-size:${size ?? body}px;'
        '${bold ? 'font-weight:bold;' : ''}">$text</div>',
      );
    }

    if (!_templateUsesEInvoiceTokens(template)) {
      steps.add(const PosPrintCompiledLine(text: '', fontSize: 14, isDivider: true));
      htmlBuf.write('<div style="border-top:1.5px solid #000;margin:6px 0;width:100%"></div>');
      line('HÓA ĐƠN ĐIỆN TỬ', bold: true);
      final series = (data['HDDT_Ky_Hieu'] ?? '').trim();
      line(series.isEmpty ? 'Số: $no' : 'Ký hiệu: $series - Số: $no', bold: true);
      final mst = (data['HDDT_MST_Ban'] ?? '').trim();
      if (mst.isNotEmpty) line('MST người bán: $mst', size: small);
      final cqt = (data['HDDT_Ma_CQT'] ?? '').trim();
      if (cqt.isNotEmpty) line('Mã CQT: $cqt', size: small);
      final lookupCode = (data['HDDT_Ma_Tra_Cuu'] ?? '').trim();
      if (lookupCode.isNotEmpty) line('Mã tra cứu: $lookupCode', size: small);
    }

    steps.add(PosPrintCompiledQr(
      imageUrl: posInlineQrUrl(qrData),
      size: 260,
      caption: 'Quét mã để tra cứu hóa đơn điện tử',
    ));
    final svg = posQrSvg(qrData, size: 110);
    htmlBuf.write(
      '<div style="text-align:center;margin:6px 0">$svg'
      '<div style="font-size:${small}px">Quét mã để tra cứu hóa đơn điện tử</div></div>',
    );
    final link = (data['HDDT_Link_Tra_Cuu'] ?? '').trim();
    if (link.isNotEmpty && link.length <= 64) {
      line(link.replaceFirst(RegExp(r'^https?://'), ''), size: small - 2);
    }
  }

  static void _appendSaleTableHeader(
    List<Object> steps,
    PosPrintBlock block, {
    required double fontSize,
    bool bold = true,
    int? sourceBlockIndex,
    bool k58 = false,
  }) {
    final cols = k58 ? k58ColumnLabels : defaultColumnLabels;
    steps.add(PosPrintCompiledSaleRow(
      name: resolveFieldLabel(block, 'Ten_Hang_Hoa',
          fallback: cols['Ten_Hang_Hoa'], k58: k58),
      qty: resolveFieldLabel(block, 'So_Luong',
          fallback: cols['So_Luong'], k58: k58),
      price: resolveFieldLabel(block, 'Don_Gia',
          fallback: cols['Don_Gia'], k58: k58),
      total: resolveFieldLabel(block, 'Thanh_Tien',
          fallback: cols['Thanh_Tien'], k58: k58),
      fontSize: fontSize,
      bold: bold,
      sourceBlockIndex: sourceBlockIndex,
    ));
  }

  static PosPrintCompiledLine _lineFromStyle(
    String text,
    PosPrintTextStyle style, {
    int? sourceBlockIndex,
  }) =>
      PosPrintCompiledLine(
        text: tr(restoreVietnamesePrintLabel(text)),
        fontSize: style.fontSize,
        bold: style.bold,
        center: style.align == PosPrintTextAlign.center,
        right: style.align == PosPrintTextAlign.right,
        sourceBlockIndex: sourceBlockIndex,
      );


  /// Ghi chú tem bếp: bọc trong ngoặc ().
  static String _formatKitchenNote(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if ((t.startsWith('(') && t.endsWith(')')) ||
        (t.startsWith('（') && t.endsWith('）'))) {
      return t;
    }
    return '($t)';
  }

  static String _saleItemName(
    Map<String, String> item, {
    required bool stripUnit,
  }) {
    var name = (item['Ten_Hang_Hoa'] ?? '').trim();
    if (stripUnit) {
      final unit = (item['Don_Vi_Tinh'] ?? '').trim();
      if (unit.isNotEmpty) {
        final suffix = ' ($unit)';
        if (name.endsWith(suffix)) {
          name = name.substring(0, name.length - suffix.length).trim();
        }
      }
    }
    return name.isEmpty ? 'Món' : name;
  }

  static String _qtyWithUnit(
    Map<String, String> item, {
    required bool showQty,
    required bool showUnit,
  }) {
    final qty = (item['So_Luong'] ?? '').trim();
    final unit = (item['Don_Vi_Tinh'] ?? '').trim();
    if (showQty && showUnit) {
      if (qty.isEmpty) return unit;
      if (unit.isEmpty) return qty;
      return '$qty $unit';
    }
    if (showQty) return qty;
    if (showUnit) return unit;
    return '';
  }

  static void _appendSaleLine(
    List<Object> steps,
    Map<String, String> item,
    PosPrintTextStyle style, {
    bool showQty = true,
    bool showUnit = false,
    bool showPrice = true,
    bool showTotal = true,
    bool showNote = true,
    bool wrapNoteParens = false,
    int? sourceBlockIndex,
    bool k58 = false,
  }) {
    final stripUnit = !showUnit;
    final name = _saleItemName(item, stripUnit: stripUnit);
    final qty = _qtyWithUnit(item, showQty: showQty, showUnit: showUnit);
    final price = showPrice ? (item['Don_Gia'] ?? '') : '';
    final total = showTotal ? (item['Thanh_Tien'] ?? '') : '';
    final note = showNote ? (item['Ghi_Chu'] ?? item['note'] ?? '').trim() : '';
    final bodySize = k58
        ? (style.fontSize - 2).clamp(13.0, 48.0)
        : style.fontSize.clamp(14.0, 48.0);
    final smallSize = (bodySize - 6).clamp(11.0, 48.0);

    steps.add(PosPrintCompiledSaleRow(
      name: name,
      qty: qty,
      price: price,
      total: total,
      fontSize: bodySize,
      bold: k58 ? false : style.bold,
      showQty: showQty || showUnit,
      showPrice: showPrice,
      showTotal: showTotal,
      sourceBlockIndex: sourceBlockIndex,
    ));
    if (!showNote) return;
    for (final raw in note.split(RegExp(r'[\r\n]+'))) {
      var part = raw.trim();
      if (part.isEmpty) continue;
      if (wrapNoteParens) part = _formatKitchenNote(part);
      steps.add(PosPrintCompiledLine(
        text: tr('  $part'),
        fontSize: smallSize,
        bold: false,
        sourceBlockIndex: sourceBlockIndex,
      ));
    }
  }

  static String _htmlText(String t, PosPrintTextStyle style) {
    t = restoreVietnamesePrintLabel(t);
    final align = switch (style.align) {
      PosPrintTextAlign.center => 'center',
      PosPrintTextAlign.right => 'right',
      _ => 'left',
    };
    return '<div style="text-align:$align;font-size:${style.fontSize}px;'
        '${style.bold ? 'font-weight:bold;' : ''}">$t</div>';
  }

  static String _htmlLineItem(
    Map<String, String> item,
    PosPrintTextStyle style, {
    bool showQty = true,
    bool showUnit = false,
    bool showPrice = true,
    bool showTotal = true,
    bool showNote = true,
    bool wrapNoteParens = false,
  }) {
    final size = style.fontSize.clamp(14.0, 48.0);
    final name = _saleItemName(item, stripUnit: !showUnit);
    final qty = _qtyWithUnit(item, showQty: showQty, showUnit: showUnit);
    final note = showNote ? (item['Ghi_Chu'] ?? item['note'] ?? '').trim() : '';
    final noteHtml = note.isEmpty
        ? ''
        : note.split(RegExp(r'[\r\n]+')).where((e) => e.trim().isNotEmpty).map((part) {
            var text = part.trim();
            if (wrapNoteParens) text = _formatKitchenNote(text);
            final topping = text.startsWith('+') || text.startsWith('(+');
            return '<div style="font-weight:500;'
                'font-size:${(size - (topping ? 6 : 4)).clamp(11, 36)}px;'
                'color:#444">$text</div>';
          }).join();
    final extras = <String>[
      if (showQty || showUnit) qty,
      if (showPrice) item['Don_Gia'] ?? '',
      if (showTotal) item['Thanh_Tien'] ?? '',
    ].where((e) => e.trim().isNotEmpty).join(' · ');
    return '<div style="padding:3px 0;${style.bold ? 'font-weight:bold;' : ''}">'
        '<div>$name${extras.isEmpty ? '' : '  $extras'}</div>$noteHtml</div>';
  }

  static String renderSamplePreview(PosPrintTemplateV2 template) {
    return compile(
      template: template,
      data: posPrintSampleData(documentType: template.documentType),
      lineItems: posPrintSampleLines(),
      vietQrImageUrl: 'sample',
    ).html;
  }
}
