import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildPosHtmlPreview(String htmlDocument) {
  return _PosHtmlIframe(html: htmlDocument);
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
  const _PosHtmlIframe({required this.html});

  final String html;

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
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
