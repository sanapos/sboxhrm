import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import '../../theme/sbox_tokens.dart';
import 'package:web/web.dart' as web;

Widget buildPosHtmlPreview(String htmlDocument, {bool? a4Paper}) {
  final t = htmlDocument.toLowerCase();
  final a4 = a4Paper ??
      (t.contains('a4') ||
          t.contains('210mm') ||
          t.contains('times new roman') ||
          t.contains('báo giá') ||
          t.contains('hợp đồng'));
  if (!a4) return _PosHtmlIframe(html: htmlDocument);
  // Trang A4 794px: màn hẹp (điện thoại) thu nhỏ vừa bề ngang — iframe nuốt thao tác cuộn ngang.
  return ColoredBox(
    color: SboxColors.slate200,
    child: LayoutBuilder(builder: (context, c) {
      const pageW = 794.0, pageH = 1123.0;
      final scale = ((c.maxWidth - 16) / pageW).clamp(0.3, 1.0);
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Center(
            child: SizedBox(
              width: pageW * scale,
              height: pageH * scale,
              child: _PosHtmlIframe(html: htmlDocument, scale: scale, pageWidth: pageW, pageHeight: pageH),
            ),
          ),
        ),
      );
    }),
  );
}

Future<void> printPosHtmlDocument(String htmlDocument) async {
  final blob = web.Blob(
    [htmlDocument.toJS].toJS,
    web.BlobPropertyBag(type: 'text/html;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final win = web.window.open(url, '_blank');
  if (win != null) {
    // Cho iframe/document tải xong rồi mở hộp thoại in.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    win.print();
  }
  web.URL.revokeObjectURL(url);
}

class _PosHtmlIframe extends StatefulWidget {
  const _PosHtmlIframe({required this.html, this.scale = 1, this.pageWidth, this.pageHeight});

  final String html;
  /// < 1: iframe giữ khổ trang thật, thu nhỏ bằng CSS transform.
  final double scale;
  final double? pageWidth;
  final double? pageHeight;

  @override
  State<_PosHtmlIframe> createState() => _PosHtmlIframeState();
}

class _PosHtmlIframeState extends State<_PosHtmlIframe> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'pos-html-${widget.html.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..srcdoc = widget.html.toJS;
      if (widget.scale < 1 && widget.pageWidth != null && widget.pageHeight != null) {
        iframe.style
          ..width = '${widget.pageWidth}px'
          ..height = '${widget.pageHeight}px'
          ..transformOrigin = '0 0'
          ..transform = 'scale(${widget.scale})';
      }
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
