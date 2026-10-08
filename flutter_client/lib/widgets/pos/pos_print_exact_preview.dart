import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_print_template_v2.dart';
import '../../utils/pos_label_renderer.dart';
import '../../utils/pos_print_template_compiler.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../utils/pos_thermal_bitmap.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Số điểm in / mm theo khổ (K80 576/80, K58 384/58, tem 203 dpi).
double posPrintDotsPerMm(String paperSize) {
  final wMm = PosPrintPaperSizes.widthMm(paperSize);
  if (PosPrintPaperSizes.isLabelSize(paperSize)) return 203 / 25.4;
  return (wMm <= 58 ? 384 : 576) / wMm;
}

/// Có xem trước bằng ảnh in thật được không (khổ nhiệt / tem; A4–A5 dùng bản HTML).
bool posPrintHasExactPreview(String paperSize) =>
    paperSize != PosPrintPaperSizes.a4 && paperSize != PosPrintPaperSizes.a5;

class _Segment {
  _Segment.text(this.png, this.width, this.height, this.rows, this.lines)
      : qr = null,
        barcode = null;
  _Segment.qr(this.qr)
      : png = null,
        width = 0,
        height = 0,
        rows = const [],
        lines = const [],
        barcode = null;
  _Segment.barcode(this.barcode)
      : png = null,
        width = 0,
        height = 0,
        rows = const [],
        lines = const [],
        qr = null;

  final Uint8List? png;
  final int width;
  final int height;
  final List<({int line, double top, double height})> rows;
  final List<PosReceiptImageLine> lines;
  final PosPrintCompiledQr? qr;
  final PosPrintCompiledBarcode? barcode;
}

/// Xem trước ĐÚNG BẢN IN: dùng chính bộ vẽ ảnh gửi máy in nhiệt / máy tem
/// (cỡ chữ, xuống dòng, cột tiền, lề, khung giống hệt giấy in). Bấm vào dòng để chọn khối.
class PosPrintExactPreview extends StatefulWidget {
  const PosPrintExactPreview({
    super.key,
    required this.template,
    this.selectedBlockIndex,
    this.onSelectBlock,
    this.zoom = 1.0,
  });

  final PosPrintTemplateV2 template;
  final int? selectedBlockIndex;
  final ValueChanged<int>? onSelectBlock;
  /// 1.0 = vừa khung; > 1 phóng to (cuộn).
  final double zoom;

  @override
  State<PosPrintExactPreview> createState() => _PosPrintExactPreviewState();
}

class _PosPrintExactPreviewState extends State<PosPrintExactPreview> {
  Map<String, String> _data = const {};
  List<_Segment> _segments = const [];
  ui.Image? _label;
  Uint8List? _labelPng;
  bool _busy = true;
  String? _error;
  int _gen = 0;
  Timer? _debounce;
  String _lastKey = '';

  bool get _isLabel => PosPrintPaperSizes.isLabelSize(widget.template.paperSize);

  int get _paperDots {
    final wMm = PosPrintPaperSizes.widthMm(widget.template.paperSize);
    return _isLabel ? (wMm * 203 / 25.4).round() : (wMm <= 58 ? 384 : 576);
  }

  @override
  void initState() {
    super.initState();
    _data = posPrintSampleData(documentType: widget.template.documentType);
    _loadStore();
    _schedule(immediate: true);
  }

  @override
  void didUpdateWidget(covariant PosPrintExactPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template.documentType != widget.template.documentType) _loadStore();
    if (oldWidget.template.encode() != widget.template.encode()) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _label?.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    final s = await PosSellStoreSettings.load();
    if (!mounted) return;
    _data = posPrintSampleData(
      documentType: widget.template.documentType,
      storeName: s.storeName,
      storeAddress: s.address,
      storePhone: s.phone,
    );
    _schedule(immediate: true, force: true);
  }

  void _schedule({bool immediate = false, bool force = false}) {
    _debounce?.cancel();
    _debounce = Timer(immediate ? Duration.zero : const Duration(milliseconds: 180), () => _render(force: force));
  }

  Future<void> _render({bool force = false}) async {
    final tpl = widget.template;
    final key = tpl.encode();
    if (!force && key == _lastKey && _error == null) return;
    _lastKey = key;
    final gen = ++_gen;
    setState(() => _busy = true);
    try {
      final samples = posPrintSampleLines();
      final output = PosPrintTemplateCompiler.compile(
        template: tpl,
        data: _data,
        lineItems: tpl.documentType == PosPrintDocumentTypes.kitchenLabel ? samples.take(1).toList() : samples,
        vietQrImageUrl: 'sample',
      );
      if (_isLabel) {
        final r = await PosLabelRenderer.renderCompiledLabel(
          output: output,
          widthMm: PosPrintPaperSizes.widthMm(tpl.paperSize),
          heightMm: PosPrintPaperSizes.heightMm(tpl.paperSize),
        );
        final png = await _rasterToPng(r.raster, r.widthPx, r.heightPx);
        if (gen != _gen || !mounted) return;
        setState(() {
          _labelPng = png;
          _segments = const [];
          _busy = false;
          _error = null;
        });
        return;
      }
      final segs = <_Segment>[];
      var batch = <PosReceiptImageLine>[];
      Future<void> flush() async {
        if (batch.isEmpty) return;
        final r = await PosThermalBitmapEncoder.receiptPreview(
          batch,
          paperDots: _paperDots,
          frameStyle: output.frameStyle,
          frameInsetMm: output.frameInsetMm,
          frameMarginMm: output.frameMarginMm,
          sidePaddingMm: output.sidePaddingMm,
        );
        if (r != null) segs.add(_Segment.text(r.png, r.width, r.height, r.rows, batch));
        batch = [];
      }

      for (final step in output.steps) {
        if (step is PosPrintCompiledQr) {
          await flush();
          segs.add(_Segment.qr(step));
          continue;
        }
        if (step is PosPrintCompiledBarcode) {
          await flush();
          segs.add(_Segment.barcode(step));
          continue;
        }
        final line = compiledStepToImageLine(step);
        if (line != null) batch.add(line);
      }
      await flush();
      if (gen != _gen || !mounted) return;
      setState(() {
        _segments = segs;
        _labelPng = null;
        _busy = false;
        _error = null;
      });
    } catch (e) {
      if (gen != _gen || !mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  static Future<Uint8List?> _rasterToPng(Uint8List raster, int w, int h) async {
    final rgba = Uint8List(w * h * 4);
    final bpr = (w + 7) ~/ 8;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final on = (raster[y * bpr + (x >> 3)] & (0x80 >> (x & 7))) != 0;
        final i = (y * w + x) * 4;
        final v = on ? 0 : 255;
        rgba[i] = v;
        rgba[i + 1] = v;
        rgba[i + 2] = v;
        rgba[i + 3] = 255;
      }
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    final img = await c.future;
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return bd?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final tpl = widget.template;
    final wMm = PosPrintPaperSizes.widthMm(tpl.paperSize);
    return LayoutBuilder(builder: (context, c) {
      // Vừa khung; zoom > 1 thì cho cuộn ngang.
      final fitW = (c.maxWidth - 24).clamp(120.0, 760.0);
      final displayW = fitW * widget.zoom;
      final k = displayW / _paperDots; // px màn hình / điểm in
      final paper = _isLabel ? _buildLabel(displayW) : _buildReceipt(displayW, k);
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: (displayW + 24).clamp(c.maxWidth, double.infinity),
            child: Column(children: [
              Text(
                tr(_isLabel
                    ? 'Tem ${wMm.toInt()}×${PosPrintPaperSizes.heightMm(tpl.paperSize).toInt()} mm — ảnh in thật (203 dpi)'
                    : 'Khổ ${wMm.toInt()} mm — ảnh in thật ($_paperDots điểm)'),
                style: const TextStyle(fontSize: 11, color: SboxColors.slate600),
              ),
              const SizedBox(height: 6),
              Stack(children: [
                Container(
                  width: displayW,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 3))],
                    borderRadius: BorderRadius.circular(_isLabel ? 8 : 2),
                  ),
                  child: paper,
                ),
                if (_busy)
                  const Positioned(right: 6, top: 6, child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
              ]),
              const SizedBox(height: 6),
              _MmRuler(widthPx: displayW, widthMm: wMm),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tr('Không vẽ được bản in: $_error'), style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
            ]),
          ),
        ),
      );
    });
  }

  Widget _buildLabel(double displayW) {
    final png = _labelPng;
    if (png == null) return SizedBox(height: displayW * 0.6);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(png, width: displayW, fit: BoxFit.fitWidth, filterQuality: FilterQuality.medium, gaplessPlayback: true),
    );
  }

  Widget _buildReceipt(double displayW, double k) {
    if (_segments.isEmpty) return SizedBox(height: 160, child: Center(child: Text(tr(_busy ? 'Đang vẽ…' : 'Chưa có nội dung'))));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in _segments)
          if (s.png != null)
            SizedBox(
              width: displayW,
              height: s.height * k,
              child: Stack(children: [
                Positioned.fill(
                  child: Image.memory(s.png!, fit: BoxFit.fill, filterQuality: FilterQuality.medium, gaplessPlayback: true),
                ),
                for (final r in s.rows) _rowOverlay(s, r, k),
              ]),
            )
          else if (s.qr != null)
            _qrBox(s.qr!, k)
          else if (s.barcode != null)
            _barcodeBox(s.barcode!, k, displayW),
      ],
    );
  }

  Widget _rowOverlay(_Segment s, ({int line, double top, double height}) r, double k) {
    final idx = s.lines[r.line].sourceBlockIndex;
    if (idx == null) return const SizedBox.shrink();
    final selected = idx == widget.selectedBlockIndex;
    return Positioned(
      left: 0,
      right: 0,
      top: r.top * k,
      height: (r.height * k).clamp(2.0, double.infinity),
      child: MouseRegion(
        cursor: widget.onSelectBlock == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onSelectBlock == null ? null : () => widget.onSelectBlock!(idx),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? const Color(0x1A1E88E5) : Colors.transparent,
              border: selected ? Border.all(color: const Color(0xFF1E88E5), width: 1) : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _wrapSelect(int? idx, Widget child) {
    final selected = idx != null && idx == widget.selectedBlockIndex;
    return GestureDetector(
      onTap: idx == null || widget.onSelectBlock == null ? null : () => widget.onSelectBlock!(idx),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0x1A1E88E5) : null,
          border: selected ? Border.all(color: const Color(0xFF1E88E5)) : null,
        ),
        child: child,
      ),
    );
  }

  Widget _qrBox(PosPrintCompiledQr q, double k) {
    TextStyle st(double dots, {bool bold = false}) => TextStyle(
          fontFamily: 'BeVietnamPro',
          fontSize: dots * k,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: Colors.black,
          height: 1.28,
        );
    final size = q.size * k;
    return _wrapSelect(
      q.sourceBlockIndex,
      Padding(
        padding: EdgeInsets.symmetric(vertical: 4 * k),
        child: Column(children: [
          if ((q.title ?? '').trim().isNotEmpty) Text(q.title!.trim(), style: st(24, bold: true), textAlign: TextAlign.center),
          Container(
            width: size,
            height: size,
            margin: EdgeInsets.symmetric(vertical: 4 * k),
            decoration: BoxDecoration(border: Border.all(color: Colors.black54), color: const Color(0xFFF2F2F2)),
            child: Icon(Icons.qr_code_2, size: size * 0.8, color: Colors.black87),
          ),
          if (q.caption.trim().isNotEmpty) Text(q.caption.trim(), style: st(22), textAlign: TextAlign.center),
          if ((q.amountText ?? '').trim().isNotEmpty) Text('${q.amountText!.trim()} đ', style: st(24, bold: true)),
        ]),
      ),
    );
  }

  Widget _barcodeBox(PosPrintCompiledBarcode b, double k, double displayW) {
    return _wrapSelect(
      b.sourceBlockIndex,
      Padding(
        padding: EdgeInsets.symmetric(vertical: 6 * k),
        child: Column(children: [
          SizedBox(
            width: displayW * 0.62,
            height: b.height * k,
            child: CustomPaint(painter: _BarcodePainter(b.data)),
          ),
          if (b.showText)
            Text(b.data, style: TextStyle(fontFamily: 'BeVietnamPro', fontSize: 20 * k, color: Colors.black)),
        ]),
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.data);
  final String data;

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final els = Barcode.code128().make(data, width: size.width, height: size.height, drawText: false);
      final p = Paint()..color = Colors.black;
      for (final e in els) {
        if (e is BarcodeBar && e.black) {
          canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), p);
        }
      }
    } catch (_) {}
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => old.data != data;
}

class _MmRuler extends StatelessWidget {
  const _MmRuler({required this.widthPx, required this.widthMm});
  final double widthPx;
  final double widthMm;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widthPx,
      height: 18,
      child: CustomPaint(
        painter: _RulerPainter(widthMm),
        child: Center(
          child: Container(
            color: const Color(0xFFF4F6F8),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${widthMm.toInt()} mm', style: const TextStyle(fontSize: 10, color: SboxColors.slate600)),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.mm);
  final double mm;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, 4), Offset(size.width, 4), p);
    final perMm = size.width / mm;
    for (var i = 0; i <= mm; i++) {
      final x = i * perMm;
      final h = i % 10 == 0 ? 8.0 : (i % 5 == 0 ? 6.0 : 3.0);
      if (perMm < 2.5 && i % 5 != 0) continue;
      canvas.drawLine(Offset(x, 4), Offset(x, 4 + h), p);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.mm != mm;
}
