import 'package:flutter/material.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_print_template_v2.dart';
import '../../utils/pos_print_template_compiler.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_sell_store_settings.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Xem trước mẫu in V2 — cỡ chữ / tên cửa hàng khớp bill in nhiệt.
Widget buildPosPrintTemplatePreview(
  PosPrintTemplateV2 template, {
  int? selectedBlockIndex,
}) {
  return _PosPrintTemplatePreviewLive(
    template: template,
    selectedBlockIndex: selectedBlockIndex,
  );
}

class _PosPrintTemplatePreviewLive extends StatefulWidget {
  const _PosPrintTemplatePreviewLive({
    required this.template,
    this.selectedBlockIndex,
  });

  final PosPrintTemplateV2 template;
  final int? selectedBlockIndex;

  @override
  State<_PosPrintTemplatePreviewLive> createState() =>
      _PosPrintTemplatePreviewLiveState();
}

class _PosPrintTemplatePreviewLiveState
    extends State<_PosPrintTemplatePreviewLive> {
  Map<String, String> _data = const {};

  @override
  void initState() {
    super.initState();
    _data = posPrintSampleData(documentType: widget.template.documentType);
    _loadStore();
  }

  @override
  void didUpdateWidget(covariant _PosPrintTemplatePreviewLive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template.documentType != widget.template.documentType) {
      _loadStore();
    }
  }

  Future<void> _loadStore() async {
    final s = await PosSellStoreSettings.load();
    if (!mounted) return;
    setState(() {
      _data = posPrintSampleData(
        documentType: widget.template.documentType,
        storeName: s.storeName,
        storeAddress: s.address,
        storePhone: s.phone,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final template = widget.template;
    final samples = posPrintSampleLines();
    final lines = template.documentType == PosPrintDocumentTypes.kitchenLabel
        ? samples.take(1).toList()
        : samples;
    final output = PosPrintTemplateCompiler.compile(
      template: template,
      data: _data,
      lineItems: lines,
      // Chỉ hiện QR khi mẫu có khối VietQR — URL mẫu để khối đó vẽ placeholder.
      vietQrImageUrl: 'sample',
    );
    if (output.steps.isEmpty) {
      return Center(child: Text(tr('Chưa có nội dung')));
    }

    final metrics = _PaperPreviewMetrics.of(template.paperSize);
    final scale =
        metrics.widthPx / PosPrintPaperSizes.thermalDots(template.paperSize);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = (constraints.maxWidth - 16).clamp(80.0, 2000.0);
        final fit = metrics.widthPx > maxW ? maxW / metrics.widthPx : 1.0;
        final paperW = metrics.widthPx * fit;
        final paperH = metrics.fixedHeightPx == null
            ? null
            : metrics.fixedHeightPx! * fit;
        final minH = metrics.minHeightPx * fit;

        final framed = template.frameStyle != PosPrintFrameStyle.none;
        final marginMm = framed ? template.frameMarginMm.clamp(0.5, 8.0) : 0.0;
        final insetMm = framed ? template.frameInsetMm.clamp(1.0, 12.0) : 0.0;
        final marginPx = marginMm * 3.78 * fit;
        final insetPx = insetMm * 3.78 * fit;
        final rounded = template.frameStyle == PosPrintFrameStyle.rounded;

        final innerContent = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: metrics.isLabel ? 4 * fit : 6 * fit,
            vertical: metrics.isLabel ? 3 * fit : 8 * fit,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final step in output.steps)
                _PreviewStep(
                  step: step,
                  scale: scale * fit,
                  selectedBlockIndex: widget.selectedBlockIndex,
                ),
            ],
          ),
        );
        final content = !framed
            ? innerContent
            : Padding(
                padding: EdgeInsets.all(marginPx.clamp(2.0, 28.0)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 1.6 * fit.clamp(0.7, 1.4)),
                    borderRadius: rounded
                        ? BorderRadius.circular((metrics.isLabel ? 7 : 4) * fit)
                        : BorderRadius.zero,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(insetPx.clamp(3.0, 32.0)),
                    child: innerContent,
                  ),
                ),
              );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Column(
            children: [
              Text(
                tr(metrics.caption),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tr(metrics.sizeHint),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              if (template.documentType == PosPrintDocumentTypes.kitchenLabel)
                Text(
                  tr('1 sản phẩm / 1 tem'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                ),
              if (fit < 0.99) ...[
                const SizedBox(height: 2),
                Text(
                  tr('Thu nhỏ ${(fit * 100).round()}% để vừa màn hình'),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                ),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE7E2D8),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC9C2B4)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: paperW,
                      height: paperH,
                      constraints: paperH == null
                          ? BoxConstraints(minHeight: minH)
                          : null,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: Colors.black87,
                          width: metrics.isLabel ? 1.5 : 2,
                        ),
                        borderRadius: metrics.isLabel
                            ? BorderRadius.circular(5)
                            : BorderRadius.zero,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 10,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: paperH == null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!metrics.isLabel) const _ThermalPerforation(),
                                content,
                              ],
                            )
                          : Stack(
                              children: [
                                Positioned.fill(
                                  child: SingleChildScrollView(
                                    physics: const NeverScrollableScrollPhysics(),
                                    child: content,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: paperW,
                      child: _MmRuler(
                        widthMm: metrics.widthMm,
                        heightMm: metrics.isLabel ? metrics.heightMm : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Tỉ lệ ~96 dpi (3.78 px/mm) — K80 80 mm và tem 50×30 / 40×30 đúng khổ đối chiếu.
class _PaperPreviewMetrics {
  const _PaperPreviewMetrics({
    required this.widthMm,
    required this.heightMm,
    required this.isLabel,
    required this.widthPx,
    this.fixedHeightPx,
    required this.minHeightPx,
    required this.caption,
    required this.sizeHint,
  });

  final double widthMm;
  final double heightMm;
  final bool isLabel;
  final double widthPx;
  final double? fixedHeightPx;
  final double minHeightPx;
  final String caption;
  final String sizeHint;

  factory _PaperPreviewMetrics.of(String paperSize) {
    const pxPerMm = 3.78;
    final wMm = PosPrintPaperSizes.widthMm(paperSize);
    final hMm = PosPrintPaperSizes.heightMm(paperSize);
    final isLabel = PosPrintPaperSizes.isLabelSize(paperSize);
    final isPage = paperSize == PosPrintPaperSizes.a4 ||
        paperSize == PosPrintPaperSizes.a5;
    // A4/A5 quá rộng nếu 1:1 — thu để vừa panel; K80/tem giữ tỉ lệ thật.
    final px = isPage ? 1.2 : pxPerMm;
    final short = PosPrintPaperSizes.shortLabel(paperSize);
    final caption = isLabel
        ? 'Tem $short mm'
        : paperSize == PosPrintPaperSizes.k80
            ? 'Hóa đơn K80'
            : paperSize == PosPrintPaperSizes.k58
                ? 'Hóa đơn K58'
                : PosPrintPaperSizes.displayLabel(paperSize);
    final sizeHint = isLabel
        ? 'Khổ thật $short mm — khung đúng tỉ lệ tem in'
        : isPage
            ? 'Khổ ${wMm.toInt()}×${hMm.toInt()} mm (thu nhỏ trên màn hình)'
            : 'Khổ thật rộng ${wMm.toInt()} mm — khung bill nhiệt';
    return _PaperPreviewMetrics(
      widthMm: wMm,
      heightMm: hMm,
      isLabel: isLabel,
      widthPx: wMm * px,
      fixedHeightPx: isLabel ? hMm * px : null,
      minHeightPx: isLabel ? hMm * px : (isPage ? 80 : 90 * pxPerMm),
      caption: caption,
      sizeHint: sizeHint,
    );
  }
}

class _ThermalPerforation extends StatelessWidget {
  const _ThermalPerforation();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 8,
      width: double.infinity,
      child: CustomPaint(painter: _DashPainter()),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MmRuler extends StatelessWidget {
  const _MmRuler({required this.widthMm, this.heightMm});

  final double widthMm;
  final double? heightMm;

  @override
  Widget build(BuildContext context) {
    final h = heightMm;
    final label = h != null && h > 0
        ? '${widthMm.toInt()} × ${h.toInt()} mm'
        : '← ${widthMm.toInt()} mm →';
    return Row(
      children: [
        Container(width: 1, height: 10, color: Colors.black54),
        Expanded(child: Container(height: 1, color: Colors.black54)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            tr(label),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: Colors.black54)),
        Container(width: 1, height: 10, color: Colors.black54),
      ],
    );
  }
}

/// Cùng tỉ lệ với bitmap in (fontSize trên canvas [thermalDots] điểm).
double _previewFontSize(double printerFontSize, double scale) =>
    (printerFontSize * scale).clamp(8.0, 48.0);

int? _stepSourceIndex(Object step) {
  if (step is PosPrintCompiledLine) return step.sourceBlockIndex;
  if (step is PosPrintCompiledPair) return step.sourceBlockIndex;
  if (step is PosPrintCompiledSaleRow) return step.sourceBlockIndex;
  if (step is PosPrintCompiledQr) return step.sourceBlockIndex;
  if (step is PosPrintCompiledBarcode) return step.sourceBlockIndex;
  return null;
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.step,
    required this.scale,
    this.selectedBlockIndex,
  });

  final Object step;
  final double scale;
  final int? selectedBlockIndex;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (step is PosPrintCompiledLine) {
      child = _PreviewLine(line: step as PosPrintCompiledLine, scale: scale);
    } else if (step is PosPrintCompiledSaleRow) {
      child = _PreviewSaleRow(
        row: step as PosPrintCompiledSaleRow,
        scale: scale,
      );
    } else if (step is PosPrintCompiledPair) {
      child = _PreviewPair(pair: step as PosPrintCompiledPair, scale: scale);
    } else if (step is PosPrintCompiledQr) {
      child = _PreviewQr(qr: step as PosPrintCompiledQr, scale: scale);
    } else if (step is PosPrintCompiledBarcode) {
      child = _PreviewBarcode(
        barcode: step as PosPrintCompiledBarcode,
        scale: scale,
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
  const _PreviewLine({required this.line, required this.scale});

  final PosPrintCompiledLine line;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (line.isDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Container(
          width: double.infinity,
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
          fontSize: _previewFontSize(line.fontSize, scale),
          fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
          height: 1.15,
          color: Colors.black,
        ),
      ),
    );
  }
}

class _PreviewSaleRow extends StatelessWidget {
  const _PreviewSaleRow({required this.row, required this.scale});

  final PosPrintCompiledSaleRow row;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: _previewFontSize(row.fontSize, scale),
      fontWeight: row.bold ? FontWeight.w700 : FontWeight.w400,
      height: 1.15,
      color: Colors.black,
    );
    if (row.nameOnly) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Text(tr(row.name), style: style),
      );
    }
    if (row.showQty && !row.showPrice && !row.showTotal) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: Text(tr(row.name), style: style)),
            const SizedBox(width: 6),
            Expanded(
              flex: 1,
              child: Text(tr(row.qty), style: style, textAlign: TextAlign.right),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: Text(tr(row.name), style: style)),
          if (row.showQty)
            SizedBox(
              width: 36,
              child: Text(tr(row.qty), style: style, textAlign: TextAlign.right),
            ),
          if (row.showPrice)
            SizedBox(
              width: 48,
              child: Text(tr(row.price), style: style, textAlign: TextAlign.right),
            ),
          if (row.showTotal)
            SizedBox(
              width: 52,
              child: Text(tr(row.total), style: style, textAlign: TextAlign.right),
            ),
        ],
      ),
    );
  }
}

class _PreviewPair extends StatelessWidget {
  const _PreviewPair({required this.pair, required this.scale});

  final PosPrintCompiledPair pair;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: _previewFontSize(pair.fontSize, scale),
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
  const _PreviewQr({required this.qr, required this.scale});

  final PosPrintCompiledQr qr;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final captionStyle = TextStyle(
      fontSize: _previewFontSize(22, scale),
      fontWeight: FontWeight.w600,
      color: Colors.black,
    );
    final size = (qr.size * scale).clamp(72.0, 160.0);
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
  const _PreviewBarcode({required this.barcode, required this.scale});

  final PosPrintCompiledBarcode barcode;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final h = (barcode.height * scale).clamp(28.0, 72.0);
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
                fontSize: _previewFontSize(18, scale),
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
                  fontSize: _previewFontSize(18, scale),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
