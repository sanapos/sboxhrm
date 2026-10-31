import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/pos_print_template_defaults.dart';
import 'pos_html_preview_stub.dart'
    if (dart.library.js_interop) 'pos_html_preview_web.dart';

/// HTML chứng từ khổ trang (A4/A5) bọc đủ vỏ in — đúng HTML gửi máy chủ khi In / Xuất PDF.
/// Chứng từ báo giá / hợp đồng (có comment khổ `POS_A4`) luôn bọc lại bằng vỏ của app, kể cả HTML máy chủ
/// đã bọc sẵn (vỏ máy chủ khác lề / CSS) — cùng vỏ với «Xuất PDF» nên xem trước khớp bản xuất.
String posPagePrintHtml(String htmlDocument) {
  final html = htmlDocument.trim();
  final isDoc = html.toLowerCase().contains('<html');
  if (isDoc && !html.contains('<!--POS_A4')) return html;
  final body = isDoc
      ? (RegExp(r'<body[^>]*>([\s\S]*)</body>', caseSensitive: false).firstMatch(html)?.group(1) ?? html)
      : html;
  return wrapPosCommercialPrintHtml(body, PosCommercialPageSetup.parse(body));
}

/// Xem trước chứng từ khổ trang bằng chính file PDF máy chủ dựng (Chromium, cùng đường «Xuất PDF» / In):
/// chữ, giãn dòng, lề, ngắt trang y hệt bản xuất. Trước đây xem trước dựng bằng trình hiển thị của app
/// (flutter_html trên Android, iframe một dải liền trên web) → lệch bản in. Mất mạng → bản HTML cũ kèm cảnh báo.
class PosServerPdfPreview extends StatefulWidget {
  const PosServerPdfPreview({super.key, required this.htmlDocument, this.onPdf});

  final String htmlDocument;

  /// Có file PDF (để nút In dùng đúng file đang xem).
  final ValueChanged<Uint8List>? onPdf;

  @override
  State<PosServerPdfPreview> createState() => _PosServerPdfPreviewState();
}

class _PosServerPdfPreviewState extends State<PosServerPdfPreview> {
  List<ui.Image>? _pages;
  bool _failed = false;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final p in _pages ?? const <ui.Image>[]) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final pdf = await ApiService().renderPosPrintPreviewPdf(posPagePrintHtml(widget.htmlDocument));
    if (!mounted) return;
    if (pdf == null) {
      setState(() => _failed = true);
      return;
    }
    final pages = <ui.Image>[];
    try {
      // 144 dpi: chữ 13px vẫn nét khi phóng to trên màn A4 dọc của máy bán hàng.
      await for (final raster in Printing.raster(pdf, dpi: 144)) {
        pages.add(await raster.toImage());
      }
    } catch (_) {}
    if (!mounted) {
      for (final p in pages) {
        p.dispose();
      }
      return;
    }
    if (pages.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    widget.onPdf?.call(pdf);
    setState(() => _pages = pages);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: SboxColors.warning.withOpacity(0.12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            tr('Không tải được bản in từ máy chủ — đang xem bản tạm trên máy, lề và ngắt trang có thể khác bản in.'),
            style: const TextStyle(fontSize: 12, color: SboxColors.slate700),
          ),
        ),
        Expanded(child: buildPosHtmlPreview(widget.htmlDocument, a4Paper: true)),
      ]);
    }
    final pages = _pages;
    if (pages == null) {
      return ColoredBox(
        color: SboxColors.slate200,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 10),
            Text(tr('Đang dựng bản in…'), style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
          ]),
        ),
      );
    }
    final page = Expanded(
      child: ColoredBox(
        color: SboxColors.slate200,
        child: LayoutBuilder(builder: (context, c) {
          // «Cả trang» = vừa bề ngang khung (tối đa khổ thật 96 dpi); phóng to → cuộn ngang.
          final fit = (c.maxWidth - 16).clamp(120.0, pages.first.width / 1.5);
          final w = fit * _zoom;
          final list = Column(
            children: [
              for (var i = 0; i < pages.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Container(
                  width: w,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x22000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                  child: AspectRatio(
                    aspectRatio: pages[i].width / pages[i].height,
                    child: RawImage(image: pages[i], fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  ),
                ),
              ],
            ],
          );
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: _zoom > 1
                  ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: list)
                  : Center(child: list),
            ),
          );
        }),
      ),
    );
    return Column(children: [
      Material(
        color: Colors.white,
        child: Row(children: [
          IconButton(
            tooltip: tr('Thu nhỏ'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 20),
            onPressed: _zoom <= 1 ? null : () => setState(() => _zoom = _zoom > 1.5 ? 1.5 : 1),
          ),
          Text(_zoom <= 1 ? tr('Cả trang') : '${(_zoom * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          IconButton(
            tooltip: tr('Phóng to'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 20),
            onPressed: _zoom >= 2 ? null : () => setState(() => _zoom = _zoom < 1.5 ? 1.5 : 2),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text('${pages.length} ${tr('trang')} · ${tr('đúng bản in')}',
                style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          ),
        ]),
      ),
      page,
    ]);
  }
}
