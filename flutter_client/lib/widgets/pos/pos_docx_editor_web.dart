import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// Trình soạn mẫu Word trực quan có trên nền tảng này (web).
const bool posDocxEditorSupported = true;

/// Khung soạn mẫu Word: trang HTML do máy chủ dựng (giống bản in) + nhận thao tác (bôi đen, bấm ô trường…)
/// qua postMessage. Đổi [html] thì nạp lại nhưng giữ vị trí cuộn.
class PosDocxEditorFrame extends StatefulWidget {
  const PosDocxEditorFrame({super.key, required this.html, required this.onMessage});

  final String html;
  final void Function(Map<String, dynamic> message) onMessage;

  @override
  State<PosDocxEditorFrame> createState() => _PosDocxEditorFrameState();
}

class _PosDocxEditorFrameState extends State<PosDocxEditorFrame> {
  late final String _viewType;
  late final web.HTMLIFrameElement _iframe;
  JSFunction? _listener;
  double _scrollY = 0;

  @override
  void initState() {
    super.initState();
    _viewType = 'pos-docx-editor-${DateTime.now().microsecondsSinceEpoch}';
    _iframe = web.document.createElement('iframe') as web.HTMLIFrameElement
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%';
    // HTML dựng từ file Word khách tải lên → chạy cô lập: chỉ cho script của trang soạn (không cùng origin với app
    // → không đọc được token / gọi API thay người dùng). Liên lạc với app chỉ qua postMessage.
    _iframe.setAttribute('sandbox', 'allow-scripts');
    _iframe.srcdoc = widget.html.toJS;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _iframe);

    _listener = ((web.MessageEvent e) {
      // Chỉ nhận tin từ đúng khung soạn này.
      if (e.source != _iframe.contentWindow) return;
      try {
        // Chỉ nhận chuỗi JSON (khung soạn gửi JSON.stringify); dữ liệu khác → lỗi → bỏ qua.
        final m = jsonDecode((e.data as JSString).toDart);
        if (m is! Map || m['src'] != 'sbox-docx') return;
        // Khung cô lập (sandbox) không cho đọc / đặt vị trí cuộn từ ngoài → trang soạn tự báo và nhận lệnh cuộn.
        if (m['type'] == 'scroll') {
          _scrollY = (m['y'] as num?)?.toDouble() ?? _scrollY;
          return;
        }
        if (m['type'] == 'ready' && _scrollY > 0) {
          _iframe.contentWindow
              ?.postMessage(jsonEncode({'src': 'sbox-docx-parent', 'scrollY': _scrollY}).toJS, '*'.toJS);
        }
        widget.onMessage(Map<String, dynamic>.from(m));
      } catch (_) {}
    }).toJS;
    web.window.addEventListener('message', _listener);
  }

  @override
  void didUpdateWidget(covariant PosDocxEditorFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      // Vị trí cuộn: lấy theo tin «scroll» trang soạn gửi lên (khung sandbox không đọc được scrollY).
      _iframe.srcdoc = widget.html.toJS;
    }
  }

  @override
  void dispose() {
    if (_listener != null) web.window.removeEventListener('message', _listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
