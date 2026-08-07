import 'package:flutter/material.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_print_template_v2.dart';
import '../../utils/pos_print_template_compiler.dart';
import '../../utils/pos_print_template_renderer.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Xem trước mẫu in V2 — render Flutter native (khớp layout in nhiệt).
Widget buildPosPrintTemplatePreview(PosPrintTemplateV2 template) {
  final output = PosPrintTemplateCompiler.compile(
    template: template,
    data: posPrintSampleData(documentType: template.documentType),
    lineItems: posPrintSampleLines(),
    vietQrImageUrl: 'sample',
  );
  if (output.steps.isEmpty) {
    return Center(child: Text(tr('Chưa có nội dung')));
  }

  final paperPx = _paperPreviewWidthPx(template.paperSize);

  return LayoutBuilder(
    builder: (context, constraints) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: paperPx,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final step in output.steps) _PreviewStep(step: step, paperPx: paperPx),
              ],
            ),
          ),
        ),
      );
    },
  );
}

double _paperPreviewWidthPx(String paperSize) {
  final wMm = PosPrintPaperSizes.widthMm(paperSize);
  // ~3.6 px / mm — tem nhỏ vẫn đọc được trên preview.
  return (wMm * 3.6).clamp(140.0, 320.0);
}

double _previewFontSize(double printerFontSize, double paperPx) =>
    (printerFontSize * paperPx / 384).clamp(9.0, 22.0);

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({required this.step, required this.paperPx});

  final Object step;
  final double paperPx;

  @override
  Widget build(BuildContext context) {
    if (step is PosPrintCompiledLine) {
      return _PreviewLine(line: step as PosPrintCompiledLine, paperPx: paperPx);
    }
    if (step is PosPrintCompiledPair) {
      return _PreviewPair(pair: step as PosPrintCompiledPair, paperPx: paperPx);
    }
    if (step is PosPrintCompiledQr) {
      return _PreviewQr(qr: step as PosPrintCompiledQr, paperPx: paperPx);
    }
    if (step is PosPrintCompiledBarcode) {
      return _PreviewBarcode(
        barcode: step as PosPrintCompiledBarcode,
        paperPx: paperPx,
      );
    }
    return const SizedBox.shrink();
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.line, required this.paperPx});

  final PosPrintCompiledLine line;
  final double paperPx;

  @override
  Widget build(BuildContext context) {
    if (line.isDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          tr(line.text),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            height: 1,
            color: line.dividerEquals ? Colors.black87 : Colors.grey.shade600,
            fontFamily: 'monospace',
          ),
        ),
      );
    }
    if (line.text.trim().isEmpty) {
      return const SizedBox(height: 6);
    }

    final align = line.center
        ? TextAlign.center
        : line.right
            ? TextAlign.right
            : TextAlign.left;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        tr(line.text),
        textAlign: align,
        style: TextStyle(
          fontSize: _previewFontSize(line.fontSize, paperPx),
          fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
          height: 1.15,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _PreviewPair extends StatelessWidget {
  const _PreviewPair({required this.pair, required this.paperPx});

  final PosPrintCompiledPair pair;
  final double paperPx;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: _previewFontSize(pair.fontSize, paperPx),
      fontWeight: pair.bold ? FontWeight.w700 : FontWeight.w400,
      height: 1.15,
      color: Colors.black,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(tr(pair.left), style: style)),
          const SizedBox(width: 6),
          Text(tr(pair.right), style: style, textAlign: TextAlign.right),
        ],
      ),
    );
  }
}

class _PreviewQr extends StatelessWidget {
  const _PreviewQr({required this.qr, required this.paperPx});

  final PosPrintCompiledQr qr;
  final double paperPx;

  @override
  Widget build(BuildContext context) {
    final captionStyle = TextStyle(
      fontSize: _previewFontSize(22, paperPx),
      fontWeight: FontWeight.w600,
      color: Colors.black,
    );
    final size = (qr.size * paperPx / 384).clamp(72.0, 160.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          if (qr.title != null && qr.title!.trim().isNotEmpty)
            Text(tr(qr.title!.trim()), textAlign: TextAlign.center, style: captionStyle),
          Container(
            width: size,
            height: size,
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              color: Colors.grey.shade100,
            ),
            child: const Icon(Icons.qr_code_2, size: 48, color: Colors.black54),
          ),
          if (qr.caption.trim().isNotEmpty)
            Text(tr(qr.caption.trim()), textAlign: TextAlign.center, style: captionStyle),
          if (qr.amountText != null && qr.amountText!.trim().isNotEmpty)
            Text(tr('${qr.amountText!.trim()} đ'),
              textAlign: TextAlign.center,
              style: captionStyle.copyWith(fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

class _PreviewBarcode extends StatelessWidget {
  const _PreviewBarcode({required this.barcode, required this.paperPx});

  final PosPrintCompiledBarcode barcode;
  final double paperPx;

  @override
  Widget build(BuildContext context) {
    final h = (barcode.height * paperPx / 384).clamp(28.0, 72.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Container(
            height: h,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              color: Colors.grey.shade50,
            ),
            child: Text(
              tr('|||| ${barcode.data} ||||'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: _previewFontSize(18, paperPx),
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (barcode.showText)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr(barcode.data),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: _previewFontSize(18, paperPx),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
