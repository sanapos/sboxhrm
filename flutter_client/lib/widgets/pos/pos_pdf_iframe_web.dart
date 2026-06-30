import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

Widget buildPosPdfPreview(Uint8List bytes) {
  return _WebPdfIframe(bytes: bytes);
}

class _WebPdfIframe extends StatefulWidget {
  const _WebPdfIframe({required this.bytes});

  final Uint8List bytes;

  @override
  State<_WebPdfIframe> createState() => _WebPdfIframeState();
}

class _WebPdfIframeState extends State<_WebPdfIframe> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = 'pos-pdf-${widget.bytes.hashCode}-${DateTime.now().millisecondsSinceEpoch}';
    final blob = web.Blob(
      [widget.bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final url = web.URL.createObjectURL(blob);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
        ..src = url
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
