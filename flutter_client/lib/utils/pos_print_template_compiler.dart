import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import 'pos_print_template_renderer.dart';
import 'pos_receipt_layout.dart';
import 'pos_table_label.dart';
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

/// Một hàng hóa đơn: Tên | SL | Đ.giá | T.tiền.
class PosPrintCompiledSaleRow {
  const PosPrintCompiledSaleRow({
    required this.name,
    required this.qty,
    required this.price,
    required this.total,
    this.fontSize = 24,
    this.bold = true,
    this.sourceBlockIndex,
  });

  final String name;
  final String qty;
  final String price;
  final String total;
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
  if (step is PosPrintCompiledLine) {
    if (step.isDivider) {
      return const PosReceiptImageLine(text: '', isDivider: true);
    }
    if (step.text.trim().isEmpty) {
      return const PosReceiptImageLine(text: '', fontSize: 10);
    }
    return PosReceiptImageLine(
      text: step.text,
      fontSize: step.center
          ? step.fontSize.clamp(20, 30)
          : step.fontSize.clamp(16, 24),
      bold: step.bold || step.center,
      center: step.center,
    );
  }
  if (step is PosPrintCompiledPair) {
    final right = step.right.trim();
    return PosReceiptImageLine(
      text: step.left,
      rightText: right,
      rightSlotFrac: right.length <= 8 ? 0.20 : 0.38,
      fontSize: step.fontSize.clamp(16, 24),
      bold: true,
    );
  }
  if (step is PosPrintCompiledSaleRow) {
    // EscPos/Agent (XP-80C): chữ nhỏ hơn Sunmi native — giữ 4 cột một hàng.
    final fs = step.fontSize.clamp(13.0, 16.0);
    return PosReceiptImageLine(
      text: step.name,
      colQty: step.qty,
      colPrice: step.price,
      colTotal: step.total,
      fontSize: fs,
      bold: step.bold,
    );
  }
  return null;
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

  static List<PosPrintBlock> _ensureKitchenLabelInvoiceNo(
    List<PosPrintBlock> blocks,
  ) {
    final hasHd = blocks.any((b) =>
        b.field == 'Ma_Don_Hang' ||
        b.leftField == 'Ma_Don_Hang' ||
        (b.text ?? '').contains('{Ma_Don_Hang}'));
    if (hasHd) return blocks;
    final out = <PosPrintBlock>[];
    var inserted = false;
    for (final b in blocks) {
      out.add(b);
      final isTable = b.field == 'Ten_Ban' || b.leftField == 'Ten_Ban';
      if (!inserted && isTable) {
        out.add(PosPrintBlock(
          type: PosPrintBlockType.field,
          field: 'Ma_Don_Hang',
          style: const PosPrintTextStyle(fontSize: 16, bold: true),
        ));
        inserted = true;
      }
    }
    return out;
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

  /// Sau tiêu đề: Số HĐ → bàn+khu một hàng → ngày giờ một hàng.
  static List<PosPrintBlock> _normalizeSaleInvoiceHeader(
    List<PosPrintBlock> blocks,
  ) {
    final out = <PosPrintBlock>[];
    var inserted = false;
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final isTitle = b.type == PosPrintBlockType.field &&
          b.field == 'Tieu_De_In';
      out.add(b);
      if (!isTitle || inserted) continue;
      inserted = true;
      while (i + 1 < blocks.length) {
        final n = blocks[i + 1];
        if (n.type == PosPrintBlockType.divider ||
            n.type == PosPrintBlockType.lineItems) {
          break;
        }
        final f = n.field ?? n.leftField ?? '';
        final isGio = n.type == PosPrintBlockType.text &&
            (n.text ?? '').contains('{Gio}');
        final isMeta = f == 'Ten_Ban' ||
            f == 'Khu_Vuc' ||
            f == 'Ma_Don_Hang' ||
            f == 'Ngay' ||
            isGio;
        if (!isMeta) break;
        i++;
      }
      final style = b.style;
      out.add(PosPrintBlock(
        type: PosPrintBlockType.field,
        field: 'Ma_Don_Hang',
        label: 'Số HĐ:',
        style: PosPrintTextStyle(
          fontSize: style.fontSize,
          bold: true,
        ),
      ));
      out.add(PosPrintBlock(
        type: PosPrintBlockType.field,
        field: 'Ten_Ban',
        style: PosPrintTextStyle(
          fontSize: style.fontSize,
          bold: true,
        ),
      ));
      out.add(PosPrintBlock(
        type: PosPrintBlockType.field,
        field: 'Ngay',
        label: 'Ngày:',
        style: PosPrintTextStyle(
          fontSize: style.fontSize,
          bold: true,
        ),
      ));
    }
    return out;
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
    htmlBuf.write(
      '<div style="width:${width}mm;font-family:Arial,sans-serif;color:#000">',
    );

    data = Map<String, String>.from(data);
    final rawHd = data['Ma_Don_Hang'];
    if (rawHd != null && rawHd.trim().isNotEmpty) {
      data['Ma_Don_Hang'] = PosReceiptLayout.formatSaleInvoiceNo(rawHd);
    }

    final isKitchenLabel =
        template.documentType == PosPrintDocumentTypes.kitchenLabel;
    final blocks = template.documentType == PosPrintDocumentTypes.saleInvoice
        ? _normalizeSaleInvoiceHeader(template.blocks)
        : (isKitchenLabel
            ? _ensureKitchenLabelInvoiceNo(template.blocks)
            : template.blocks);
    var skipNextKhu = false;
    for (var bi = 0; bi < blocks.length; bi++) {
      final block = blocks[bi];
      switch (block.type) {
        case PosPrintBlockType.text:
          if (isKitchenLabel && _isQtyOnlyToken(block.text ?? '')) {
            continue;
          }
          final t = _resolveToken(block.text ?? '', data);
          if (t.trim().isNotEmpty) {
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
            final name = (data['Ten_Hang_Hoa'] ?? '').trim();
            final qty = (data['So_Luong'] ?? '').trim();
            final unit = (data['Don_Vi_Tinh'] ?? '').trim();
            final right = unit.isEmpty ? qty : '$qty $unit';
            if (name.isNotEmpty || right.isNotEmpty) {
              steps.add(PosPrintCompiledPair(
                left: name.isEmpty ? 'Món' : name,
                right: right,
                fontSize: block.style.fontSize,
                bold: true,
                sourceBlockIndex: bi,
              ));
              htmlBuf.write(
                '<div style="display:flex;justify-content:space-between;'
                'font-size:${block.style.fontSize}px;font-weight:bold">'
                '<span>${name.isEmpty ? 'Món' : name}</span>'
                '<span>$right</span></div>',
              );
            }
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
          if (raw.trim().isNotEmpty) {
            String? prefix = block.label?.trim();
            if (prefix == null || prefix.isEmpty) {
              final fieldKey = block.field;
              if (fieldKey != null) {
                prefix = block.fieldLabels?[fieldKey];
              }
            }
            final parts = raw.split(RegExp(r'[\r\n]+'));
            for (var pi = 0; pi < parts.length; pi++) {
              final chunk = parts[pi].trim();
              if (chunk.isEmpty) continue;
              final t = pi == 0 ? _withPrefix(prefix, chunk) : chunk;
              final topping = chunk.startsWith('+');
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
          var leftVal = data[leftKey] ?? leftKey;
          final rightVal = data[rightKey] ?? rightKey;
          if (isKitchenLabel && leftKey == 'Ten_Ban') {
            leftVal = formatPosTableOneLine(
              areaName: data['Khu_Vuc'],
              tableName: data['Ten_Ban'],
            );
            if (leftVal.trim().isEmpty) leftVal = data['Ten_Ban'] ?? '';
          }
          if (leftKey == 'Ma_Don_Hang') {
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
              '<div style="display:flex;justify-content:space-between;'
              'font-size:${pairSize}px;'
              '${pairBold ? 'font-weight:bold;' : ''}">'
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
          final fs = block.style.fontSize.clamp(14.0, 48.0);
          _appendSaleTableHeader(
            steps,
            block,
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
    }

    // Mẫu cũ thiếu khối VietQR nhưng caller đã truyền URL → vẫn in QR.
    if (vietQrImageUrl != null &&
        vietQrImageUrl.isNotEmpty &&
        !steps.any((s) => s is PosPrintCompiledQr)) {
      steps.add(PosPrintCompiledQr(
        imageUrl: vietQrImageUrl,
        size: 360,
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

  static void _appendSaleTableHeader(
    List<Object> steps,
    PosPrintBlock block, {
    required double fontSize,
    int? sourceBlockIndex,
  }) {
    steps.add(PosPrintCompiledSaleRow(
      name: resolveFieldLabel(block, 'Ten_Hang_Hoa',
          fallback: defaultColumnLabels['Ten_Hang_Hoa']),
      qty: resolveFieldLabel(block, 'So_Luong',
          fallback: defaultColumnLabels['So_Luong']),
      price: resolveFieldLabel(block, 'Don_Gia',
          fallback: defaultColumnLabels['Don_Gia']),
      total: resolveFieldLabel(block, 'Thanh_Tien',
          fallback: defaultColumnLabels['Thanh_Tien']),
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
    int? sourceBlockIndex,
  }) {
    final name = item['Ten_Hang_Hoa'] ?? '';
    final qty = item['So_Luong'] ?? '';
    final price = item['Don_Gia'] ?? '';
    final total = item['Thanh_Tien'] ?? '';
    final note = (item['Ghi_Chu'] ?? item['note'] ?? '').trim();
    final bodySize = style.fontSize.clamp(14.0, 48.0);
    final smallSize = (bodySize - 6).clamp(11.0, 48.0);

    steps.add(PosPrintCompiledSaleRow(
      name: name.isEmpty ? 'Món' : name,
      qty: qty,
      price: price,
      total: total,
      fontSize: bodySize,
      bold: true,
      sourceBlockIndex: sourceBlockIndex,
    ));
    for (final raw in note.split(RegExp(r'[\r\n]+'))) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      steps.add(PosPrintCompiledLine(
        text: tr('  $part'),
        fontSize: smallSize,
        bold: false,
        sourceBlockIndex: sourceBlockIndex,
      ));
    }
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
        : note.split(RegExp(r'[\r\n]+')).where((e) => e.trim().isNotEmpty).map((part) {
            final topping = part.trim().startsWith('+');
            return '<div style="font-weight:500;'
                'font-size:${(size - (topping ? 6 : 4)).clamp(11, 36)}px;'
                'color:#444">${part.trim()}</div>';
          }).join();
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
