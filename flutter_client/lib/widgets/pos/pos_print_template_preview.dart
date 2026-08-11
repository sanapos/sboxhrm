import 'package:flutter/material.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_print_template_v2.dart';
import '../../utils/pos_print_template_compiler.dart';
import '../../utils/pos_print_template_renderer.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Xem trước mẫu in V2 — render Flutter native (khớp layout in nhiệt).
Widget buildPosPrintTemplatePreview(
  PosPrintTemplateV2 template, {
  int? selectedBlockIndex,
}) {
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
                for (final step in output.steps)
                  _PreviewStep(
                    step: step,
                    paperPx: paperPx,
                    selectedBlockIndex: selectedBlockIndex,
                  ),
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
  // ~3.8 px / mm — K80 (~304px) rõ hơn K58 (~220px).
  return (wMm * 3.8).clamp(140.0, 380.0);
}

double _previewFontSize(double printerFontSize, double paperPx) =>
    (printerFontSize * paperPx / 384).clamp(9.0, 22.0);

int? _stepSourceIndex(Object step) {
  if (step is PosPrintCompiledLine) return step.sourceBlockIndex;
  if (step is PosPrintCompiledPair) return step.sourceBlockIndex;
  if (step is PosPrintCompiledQr) return step.sourceBlockIndex;
  if (step is PosPrintCompiledBarcode) return step.sourceBlockIndex;
  return null;
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.step,
    required this.paperPx,
    this.selectedBlockIndex,
  });

  final Object step;
  final double paperPx;
  final int? selectedBlockIndex;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (step is PosPrintCompiledLine) {
      child = _PreviewLine(line: step as PosPrintCompiledLine, paperPx: paperPx);
    } else if (step is PosPrintCompiledPair) {
      child = _PreviewPair(pair: step as PosPrintCompiledPair, paperPx: paperPx);
    } else if (step is PosPrintCompiledQr) {
      child = _PreviewQr(qr: step as PosPrintCompiledQr, paperPx: paperPx);
    } else if (step is PosPrintCompiledBarcode) {
      child = _PreviewBarcode(
        barcode: step as PosPrintCompiledBarcode,
        paperPx: paperPx,
      );
    } else {
      return const SizedBox.shrink();
    }

    final src = _stepSourceIndex(step);
    final selected =
        selectedBlockIndex != null && src != null && src == selectedBlockIndex;
    if (!selected) return child;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3BF),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: child,
    );
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          width: paperPx,
          height: 1.5,
          color: Colors.black87,
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
