import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import 'pos_print_template_renderer.dart';
import 'pos_thermal_bitmap.dart';
import '../l10n/app_tr.dart';

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
  });

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
  });

  final String left;
  final String right;
  final double fontSize;
  final bool bold;
  final int? sourceBlockIndex;
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
  });

  /// Xen kẽ dòng chữ và cặp nhãn-giá trị theo thứ tự in.
  final List<Object> steps;
  final String html;

  List<PosReceiptImageLine> get imageLines => steps
      .whereType<PosPrintCompiledLine>()
      .map((l) => l.toImageLine())
      .toList();
}

/// Biên dịch mẫu V2 → HTML preview + dòng in nhiệt/Sunmi.
abstract final class PosPrintTemplateCompiler {
  /// Nhãn mặc định cho các dòng tổng — UI / presets có thể ghi đè qua fieldLabels.
  static const defaultTotalLabels = <String, String>{
    'Tong_Tien_Hang': 'Tổng tiền hàng',
    'Chiet_Khau_Hoa_Don': 'Chiết khấu',
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
    'Don_Gia': 'Đ.giá',
    'So_Luong': 'SL',
    'Thanh_Tien': 'TT',
  };

  static String resolveFieldLabel(
    PosPrintBlock block,
    String token, {
    String? fallback,
  }) {
    final custom = block.fieldLabels?[token]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return defaultTotalLabels[token] ??
        defaultColumnLabels[token] ??
        token;
  }

  static String _withPrefix(String? label, String value) {
    final l = (label ?? '').trim();
    if (l.isEmpty) return value;
    if (l.endsWith(':') || l.endsWith('：') || l.endsWith(' ')) {
      return '$l$value';
    }
    return '$l: $value';
  }

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
    htmlBuf.write(
      '<div style="width:${width}mm;font-family:Arial,sans-serif;color:#000">',
    );

    for (var bi = 0; bi < template.blocks.length; bi++) {
      final block = template.blocks[bi];
      switch (block.type) {
        case PosPrintBlockType.text:
          final t = _resolveToken(block.text ?? '', data);
          if (t.trim().isNotEmpty) {
            steps.add(_lineFromStyle(t, block.style, sourceBlockIndex: bi));
            htmlBuf.write(_htmlText(t, block.style));
          }
        case PosPrintBlockType.field:
          var raw = data[block.field ?? ''] ?? '';
          // Luôn tính lại bằng chữ từ Tong_Cong (tránh mẫu hard-code cũ).
          if (block.field == 'Tong_Cong_Bang_Chu') {
            final fromData = data['Tong_Cong_Bang_Chu'];
            if (fromData != null && fromData.trim().isNotEmpty) {
              raw = fromData;
            }
          }
          if (raw.trim().isNotEmpty) {
            String? prefix = block.label?.trim();
            if (prefix == null || prefix.isEmpty) {
              final fieldKey = block.field;
              if (fieldKey != null) {
                prefix = block.fieldLabels?[fieldKey];
              }
            }
            final t = _withPrefix(prefix, raw);
            steps.add(_lineFromStyle(t, block.style, sourceBlockIndex: bi));
            htmlBuf.write(_htmlText(t, block.style));
          }
        case PosPrintBlockType.pair:
          final leftKey = block.leftField ?? '';
          final rightKey = block.rightField ?? '';
          final leftVal = data[leftKey] ?? leftKey;
          final rightVal = data[rightKey] ?? rightKey;
          String? leftPrefix = block.label?.trim();
          if (leftPrefix == null || leftPrefix.isEmpty) {
            leftPrefix = block.fieldLabels?[leftKey];
          }
          final rightPrefix = block.fieldLabels?[rightKey];
          final left = _withPrefix(leftPrefix, leftVal);
          final right = (rightPrefix != null && rightPrefix.trim().isNotEmpty)
              ? _withPrefix(rightPrefix, rightVal)
              : rightVal;
          if (left.isNotEmpty || right.isNotEmpty) {
            steps.add(PosPrintCompiledPair(
              left: left,
              right: right,
              fontSize: block.style.fontSize,
              bold: block.style.bold,
              sourceBlockIndex: bi,
            ));
            htmlBuf.write(
              '<div style="display:flex;justify-content:space-between;'
              'font-size:${block.style.fontSize}px;'
              '${block.style.bold ? 'font-weight:bold;' : ''}">'
              '<span>$left</span><span>$right</span></div>',
            );
          }
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
          final k58 = _isNarrowThermal(template.paperSize);
          final fs = block.style.fontSize.clamp(14.0, 48.0);
          _appendSaleTableHeader(
            steps,
            block,
            k58: k58,
            fontSize: fs,
            sourceBlockIndex: bi,
          );
          htmlBuf.write(
            '<table style="width:100%;border-collapse:collapse;'
            'font-size:${fs}px;margin:2px 0 6px">',
          );
          htmlBuf.write(
            '<thead><tr style="border-bottom:2px solid #000">'
            '<th style="text-align:left;padding:3px 2px 4px">Tên hàng</th>'
            '<th style="text-align:center;width:14%;padding:3px 2px 4px">SL</th>'
            '<th style="text-align:right;width:24%;padding:3px 2px 4px">Đ.giá</th>'
            '<th style="text-align:right;width:26%;padding:3px 2px 4px">TT</th>'
            '</tr></thead><tbody>',
          );
          htmlBuf.write('<!--BEGIN_ITEMS-->');
          for (final item in lineItems) {
            _appendSaleLine(
              steps,
              item,
              block.style,
              k58: k58,
              sourceBlockIndex: bi,
            );
            htmlBuf.write(_htmlLineItem(item, block.style));
          }
          htmlBuf.write('<!--END_ITEMS-->');
          htmlBuf.write('</tbody></table>');
        case PosPrintBlockType.lineItemsKitchen:
          final kLines = kitchenLines ?? lineItems;
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
            if (note.trim().isNotEmpty) {
              steps.add(PosPrintCompiledLine(
                text: tr(' * $note'),
                fontSize: (kSize - 2).clamp(12.0, 48.0),
                sourceBlockIndex: bi,
              ));
            }
          }
        case PosPrintBlockType.totals:
          for (final key in block.fields ?? []) {
            final val = data[key] ?? '';
            if (val.trim().isEmpty || val == '0') continue;
            final label = resolveFieldLabel(block, key);
            final isTotal = key == 'Tong_Cong';
            final style = isTotal ? (block.rightStyle ?? block.style) : block.style;
            final size = style.fontSize.clamp(14.0, 48.0);
            steps.add(PosPrintCompiledPair(
              left: label,
              right: val,
              fontSize: size,
              bold: style.bold || isTotal,
              sourceBlockIndex: bi,
            ));
            htmlBuf.write(
              '<div style="display:flex;justify-content:space-between;'
              'font-size:${size}px;${style.bold || isTotal ? 'font-weight:bold;' : ''}">'
              '<span>$label</span><span>$val</span></div>',
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
            final title = _resolveToken(block.qrTitle ?? '', data).trim();
            final caption = _resolveToken(block.qrCaption, data).trim();
            final amount = block.qrShowAmount ? (data['Tong_Cong'] ?? '') : '';
            steps.add(PosPrintCompiledQr(
              imageUrl: vietQrImageUrl,
              size: block.qrSize.clamp(100, 220),
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
    }

    // Mẫu cũ thiếu khối VietQR nhưng caller đã truyền URL → vẫn in QR.
    if (vietQrImageUrl != null &&
        vietQrImageUrl.isNotEmpty &&
        !steps.any((s) => s is PosPrintCompiledQr)) {
      steps.add(PosPrintCompiledQr(
        imageUrl: vietQrImageUrl,
        size: 160,
        caption: 'Quét VietQR thanh toán',
        amountText: (data['Tong_Cong'] ?? '').trim().isEmpty
            ? null
            : (data['Tong_Cong'] ?? '').trim(),
      ));
      htmlBuf.write(
        '<div style="text-align:center;margin:8px 0">'
        '<div style="border:1px dashed #999;padding:12px">[VietQR]</div>'
        '<div>Quét VietQR thanh toán</div>'
        '</div>',
      );
    }

    htmlBuf.write('</div>');
    final html = wrapPosPrintHtmlDocument(htmlBuf.toString(), paperSize: template.paperSize);
    return PosPrintCompiledOutput(steps: steps, html: html);
  }

  static bool _isNarrowThermal(String paperSize) =>
      paperSize == PosPrintPaperSizes.k58 ||
      PosPrintPaperSizes.widthMm(paperSize) <= 58;

  static void _appendSaleTableHeader(
    List<Object> steps,
    PosPrintBlock block, {
    required bool k58,
    required double fontSize,
    int? sourceBlockIndex,
  }) {
    final left = resolveFieldLabel(block, 'Ten_Hang_Hoa',
        fallback: defaultColumnLabels['Ten_Hang_Hoa']);
    final right = k58 ? 'SL            TT' : 'SL × Đ.giá              TT';
    steps.add(PosPrintCompiledPair(
      left: left,
      right: right,
      fontSize: fontSize,
      bold: true,
      sourceBlockIndex: sourceBlockIndex,
    ));
  }

  static PosPrintCompiledLine _lineFromStyle(
    String text,
    PosPrintTextStyle style, {
    int? sourceBlockIndex,
  }) =>
      PosPrintCompiledLine(
        text: tr(text),
        fontSize: style.fontSize,
        bold: style.bold,
        center: style.align == PosPrintTextAlign.center,
        right: style.align == PosPrintTextAlign.right,
        sourceBlockIndex: sourceBlockIndex,
      );

  static void _appendSaleLine(
    List<Object> steps,
    Map<String, String> item,
    PosPrintTextStyle style, {
    required bool k58,
    int? sourceBlockIndex,
  }) {
    final name = item['Ten_Hang_Hoa'] ?? '';
    final qty = item['So_Luong'] ?? '';
    final unit = item['Don_Vi_Tinh'] ?? '';
    final price = item['Don_Gia'] ?? '';
    final total = item['Thanh_Tien'] ?? '';
    final note = (item['Ghi_Chu'] ?? item['note'] ?? '').trim();
    final bodySize = style.fontSize.clamp(14.0, 48.0);
    final smallSize = (bodySize - 4).clamp(12.0, 48.0);

    if (name.isNotEmpty) {
      steps.add(PosPrintCompiledLine(
        text: tr(name),
        fontSize: bodySize,
        bold: true,
        sourceBlockIndex: sourceBlockIndex,
      ));
    }
    if (note.isNotEmpty) {
      steps.add(PosPrintCompiledLine(
        text: tr('  $note'),
        fontSize: smallSize,
        sourceBlockIndex: sourceBlockIndex,
      ));
    }
    final qtyBit = unit.isEmpty ? qty : '$qty $unit';
    final left = k58 ? qtyBit : '$qtyBit × $price';
    steps.add(PosPrintCompiledPair(
      left: left,
      right: total,
      fontSize: bodySize,
      bold: true,
      sourceBlockIndex: sourceBlockIndex,
    ));
  }

  static String _htmlText(String t, PosPrintTextStyle style) {
    final align = switch (style.align) {
      PosPrintTextAlign.center => 'center',
      PosPrintTextAlign.right => 'right',
      _ => 'left',
    };
    return '<div style="text-align:$align;font-size:${style.fontSize}px;'
        '${style.bold ? 'font-weight:bold;' : ''}">$t</div>';
  }

  static String _htmlLineItem(Map<String, String> item, PosPrintTextStyle style) {
    final size = style.fontSize.clamp(14.0, 48.0);
    final note = (item['Ghi_Chu'] ?? item['note'] ?? '').trim();
    final noteHtml = note.isEmpty
        ? ''
        : '<div style="font-weight:normal;font-size:${(size - 4).clamp(11, 40)}px;'
            'font-style:italic;color:#333">$note</div>';
    return '<tr style="border-bottom:1px dotted #555">'
        '<td style="padding:5px 2px 3px;font-weight:bold;vertical-align:top">'
        '${item['Ten_Hang_Hoa'] ?? ''}$noteHtml</td>'
        '<td style="text-align:center;vertical-align:top;padding:5px 2px">'
        '${item['So_Luong'] ?? ''}</td>'
        '<td style="text-align:right;vertical-align:top;padding:5px 2px">'
        '${item['Don_Gia'] ?? ''}</td>'
        '<td style="text-align:right;vertical-align:top;padding:5px 2px;font-weight:bold">'
        '${item['Thanh_Tien'] ?? ''}</td></tr>';
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
