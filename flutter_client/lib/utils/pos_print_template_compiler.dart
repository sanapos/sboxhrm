import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import 'pos_print_template_renderer.dart';
import 'pos_thermal_bitmap.dart';

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
  });

  final String text;
  final double fontSize;
  final bool bold;
  final bool center;
  final bool right;
  final bool isDivider;
  final bool dividerEquals;

  PosReceiptImageLine toImageLine() => PosReceiptImageLine(
        text: text,
        fontSize: fontSize,
        bold: bold,
        center: center,
      );
}

/// Cặp nhãn — giá trị (Sunmi printRow).
class PosPrintCompiledPair {
  const PosPrintCompiledPair({
    required this.left,
    required this.right,
    this.fontSize = 24,
    this.bold = false,
  });

  final String left;
  final String right;
  final double fontSize;
  final bool bold;
}

/// Khối in mã VietQR.
class PosPrintCompiledQr {
  const PosPrintCompiledQr({
    required this.imageUrl,
    this.size = 160,
    this.title,
    this.caption = 'Quét VietQR thanh toán',
    this.amountText,
  });

  final String imageUrl;
  final int size;
  final String? title;
  final String caption;
  final String? amountText;
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
  static const _totalLabels = {
    'Tong_Tien_Hang': 'Tổng tiền hàng',
    'Chiet_Khau_Hoa_Don': 'Chiết khấu',
    'Tong_Cong': 'Tổng cộng',
    'Khach_Can_Tra': 'Khách cần trả',
    'Khach_Thanh_Toan': 'Đã thanh toán',
    'Tien_Thua': 'Tiền thừa',
    'Con_Lai': 'Còn lại',
    'Hinh_Thuc_Thanh_Toan': 'HTTT',
  };

  static String _resolveToken(String raw, Map<String, String> data) {
    var s = raw;
    for (final e in data.entries) {
      s = s.replaceAll('{${e.key}}', e.value);
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

    for (final block in template.blocks) {
      switch (block.type) {
        case PosPrintBlockType.text:
          final t = _resolveToken(block.text ?? '', data);
          if (t.trim().isNotEmpty) {
            steps.add(_lineFromStyle(t, block.style));
            htmlBuf.write(_htmlText(t, block.style));
          }
        case PosPrintBlockType.field:
          final t = data[block.field ?? ''] ?? '';
          if (t.trim().isNotEmpty) {
            steps.add(_lineFromStyle(t, block.style));
            htmlBuf.write(_htmlText(t, block.style));
          }
        case PosPrintBlockType.pair:
          final left = data[block.leftField ?? ''] ?? block.leftField ?? '';
          final right = data[block.rightField ?? ''] ?? block.rightField ?? '';
          if (left.isNotEmpty || right.isNotEmpty) {
            steps.add(PosPrintCompiledPair(
              left: left,
              right: right,
              fontSize: block.style.fontSize,
              bold: block.style.bold,
            ));
            htmlBuf.write(
              '<div style="display:flex;justify-content:space-between;'
              'font-size:${block.style.fontSize}px;'
              '${block.style.bold ? 'font-weight:bold;' : ''}">'
              '<span>$left</span><span>$right</span></div>',
            );
          }
        case PosPrintBlockType.divider:
          final ch = block.divider == PosPrintDividerStyle.equals ? '=' : '-';
          final chars = (block.dividerChars ?? defaultDividerChars(template.paperSize))
              .clamp(16, 80);
          final rule = List.filled(chars, ch).join();
          steps.add(PosPrintCompiledLine(
            text: rule,
            fontSize: block.style.fontSize,
            isDivider: true,
            dividerEquals: block.divider == PosPrintDividerStyle.equals,
          ));
          htmlBuf.write('<div style="border-top:1px dashed #999;margin:6px 0"></div>');
        case PosPrintBlockType.lineItems:
          htmlBuf.write('<!--BEGIN_ITEMS-->');
          for (final item in lineItems) {
            _appendSaleLine(steps, item, template.paperSize);
            htmlBuf.write(_htmlLineItem(item));
          }
          htmlBuf.write('<!--END_ITEMS-->');
        case PosPrintBlockType.lineItemsKitchen:
          final kLines = kitchenLines ?? lineItems;
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
              fontSize: block.style.fontSize,
              bold: true,
            ));
            if (note.trim().isNotEmpty) {
              steps.add(PosPrintCompiledLine(
                text: ' * $note',
                fontSize: block.style.fontSize - 2,
              ));
            }
          }
        case PosPrintBlockType.totals:
          for (final key in block.fields ?? []) {
            final val = data[key] ?? '';
            if (val.trim().isEmpty || val == '0') continue;
            final label = _totalLabels[key] ?? key;
            final isTotal = key == 'Tong_Cong';
            final style = isTotal ? (block.rightStyle ?? block.style) : block.style;
            steps.add(PosPrintCompiledPair(
              left: label,
              right: val,
              fontSize: style.fontSize,
              bold: style.bold || isTotal,
            ));
            htmlBuf.write(
              '<div style="display:flex;justify-content:space-between;'
              'font-size:${style.fontSize}px;${style.bold ? 'font-weight:bold;' : ''}">'
              '<span>$label</span><span>$val</span></div>',
            );
          }
        case PosPrintBlockType.spacer:
          steps.add(const PosPrintCompiledLine(text: ' ', fontSize: 18));
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
            ));
            htmlBuf.write(
              '<div style="text-align:center;margin:8px 0">'
              '<div style="border:1px dashed #999;padding:12px">[VietQR]</div>'
              '${caption.isNotEmpty ? '<div>$caption</div>' : ''}'
              '</div>',
            );
          }
      }
    }

    htmlBuf.write('</div>');
    final html = wrapPosPrintHtmlDocument(htmlBuf.toString(), paperSize: template.paperSize);
    return PosPrintCompiledOutput(steps: steps, html: html);
  }

  static PosPrintCompiledLine _lineFromStyle(String text, PosPrintTextStyle style) =>
      PosPrintCompiledLine(
        text: text,
        fontSize: style.fontSize,
        bold: style.bold,
        center: style.align == PosPrintTextAlign.center,
        right: style.align == PosPrintTextAlign.right,
      );

  static void _appendSaleLine(
    List<Object> steps,
    Map<String, String> item,
    String paperSize,
  ) {
    final name = item['Ten_Hang_Hoa'] ?? '';
    final code = item['Ma_Hang'] ?? '';
    final qty = item['So_Luong'] ?? '';
    final unit = item['Don_Vi_Tinh'] ?? '';
    final price = item['Don_Gia'] ?? '';
    final total = item['Thanh_Tien'] ?? '';
    final bodySize = paperSize == PosPrintPaperSizes.k58 ? 24.0 : 26.0;
    final smallSize = bodySize - 2;

    if (name.isNotEmpty) {
      steps.add(PosPrintCompiledLine(text: name, fontSize: bodySize, bold: true));
    }
    if (code.isNotEmpty) {
      steps.add(PosPrintCompiledLine(text: '($code)', fontSize: smallSize));
    }
    steps.add(PosPrintCompiledPair(
      left: '$qty $unit x $price',
      right: total,
      fontSize: bodySize,
      bold: true,
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

  static String _htmlLineItem(Map<String, String> item) =>
      '<div style="margin-bottom:6px">'
      '<div><b>${item['Ten_Hang_Hoa'] ?? ''}</b></div>'
      '<div style="display:flex;justify-content:space-between">'
      '<span>${item['So_Luong'] ?? ''} ${item['Don_Vi_Tinh'] ?? ''} x ${item['Don_Gia'] ?? ''}</span>'
      '<span><b>${item['Thanh_Tien'] ?? ''}</b></span></div></div>';

  static String renderSamplePreview(PosPrintTemplateV2 template) {
    return compile(
      template: template,
      data: posPrintSampleData(documentType: template.documentType),
      lineItems: posPrintSampleLines(),
      vietQrImageUrl: 'sample',
    ).html;
  }
}
