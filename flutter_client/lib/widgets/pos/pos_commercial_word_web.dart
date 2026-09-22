import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../utils/pos_print_template_defaults.dart';
import '../../utils/pos_print_template_renderer.dart';

/// Trang A4 contenteditable trên web — thanh công cụ gọi execCommand như Word.
///
/// Chỉ đẩy `innerHTML` lại khi HTML từ parent thay đổi thật sự so với lần cuối
/// ta đã ghi vào (tránh reset caret khi parent setState chỉ đơn thuần lưu).
class PosCommercialWordSurface extends StatefulWidget {
  const PosCommercialWordSurface({
    super.key,
    required this.html,
    required this.onChanged,
    this.editable = true,
    this.pageSetup = const PosCommercialPageSetup(),
  });

  final String html;
  final ValueChanged<String> onChanged;
  final bool editable;
  final PosCommercialPageSetup pageSetup;

  @override
  State<PosCommercialWordSurface> createState() =>
      PosCommercialWordSurfaceState();
}

class PosCommercialWordSurfaceState extends State<PosCommercialWordSurface> {
  late final String _viewType;
  web.HTMLIFrameElement? _iframe;
  bool _applying = false;
  String _lastAppliedHtml = '';

  @override
  void initState() {
    super.initState();
    _viewType =
        'sbox-word-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    _lastAppliedHtml = widget.html;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe =
          web.document.createElement('iframe') as web.HTMLIFrameElement
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..srcdoc = _wrap(widget.html).toJS;
      iframe.addEventListener(
        'load',
        ((web.Event _) {
          _iframe = iframe;
          _bind(iframe);
        }).toJS,
      );
      _iframe = iframe;
      return iframe;
    });
  }

  void _bind(web.HTMLIFrameElement iframe) {
    final doc = iframe.contentDocument;
    if (doc == null) return;
    final body = doc.body;
    if (body == null) return;
    body.setAttribute('contenteditable', widget.editable ? 'true' : 'false');
    if (!widget.editable) return;
    void sync(web.Event _) {
      if (_applying) return;
      final html = _readHtml(body);
      _lastAppliedHtml = html;
      widget.onChanged(html);
    }

    body.addEventListener('input', sync.toJS);
    body.addEventListener('keyup', sync.toJS);
    body.addEventListener('blur', sync.toJS);
    // Paste-clean: remove Word/Google Docs junk styles.
    body.addEventListener(
      'paste',
      ((web.Event ev) {
        try {
          final ce = ev as web.ClipboardEvent;
          final data = ce.clipboardData;
          if (data == null) return;
          final html = data.getData('text/html');
          if (html.isEmpty) return;
          ev.preventDefault();
          final cleaned = _sanitizePastedHtml(html);
          doc.execCommand('insertHTML', false, cleaned);
        } catch (_) {}
      }).toJS,
    );
  }

  String _sanitizePastedHtml(String raw) {
    // Bỏ Office style (mso-*), font tags có face MS…, span rỗng.
    var s = raw;
    s = s.replaceAll(RegExp(r'<!--\[if [^\]]+\]>[\s\S]*?<!\[endif\]-->'), '');
    s = s.replaceAll(RegExp(r'<o:p[^>]*>.*?</o:p>'), '');
    s = s.replaceAll(RegExp(r'mso-[^:]+:[^;"]+;?'), '');
    s = s.replaceAll(RegExp(r'style="\s*"'), '');
    s = s.replaceAll(RegExp(r'class="[^"]*"'), '');
    return s;
  }

  String _wrap(String html) {
    final editableAttr = widget.editable ? 'true' : 'false';
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8">
<style>
  html,body{margin:0;background:#fff;height:100%;}
  html{overflow:auto;}
  body{
    font-family:"Times New Roman",Times,serif;
    font-size:14px;line-height:1.5;color:#111;
    padding:${widget.pageSetup.paddingCss};min-height:100%;box-sizing:border-box;
    outline:none;word-wrap:break-word;overflow-wrap:anywhere;overflow-x:hidden;
  }
  table{border-collapse:collapse;width:100%;max-width:100%;table-layout:fixed;}
  td,th{padding:5px 7px;vertical-align:top;word-wrap:break-word;overflow-wrap:anywhere;}
  h1,h2,h3{text-align:center;margin:8px 0;}
  h2{font-size:18px;font-weight:bold;text-transform:uppercase;}
  p{margin:6px 0;}
</style></head>
<body contenteditable="$editableAttr">${posPrintProtectItemMarkers(html)}</body></html>''';
  }

  Future<void> flush() async {
    final body = _iframe?.contentDocument?.body;
    if (body == null) return;
    final html = _readHtml(body);
    _lastAppliedHtml = html;
    widget.onChanged(html);
  }

  void exec(String cmd, [String? value]) {
    final doc = _iframe?.contentDocument;
    if (doc == null) return;
    try {
      doc.execCommand(cmd, false, value ?? '');
    } catch (_) {}
    final body = doc.body;
    if (body != null) {
      final html = _readHtml(body);
      _lastAppliedHtml = html;
      widget.onChanged(html);
    }
  }

  void insertHtml(String html) {
    exec('insertHTML', html);
  }

  @override
  void didUpdateWidget(covariant PosCommercialWordSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editable != widget.editable) {
      _iframe?.contentDocument?.body
          ?.setAttribute('contenteditable', widget.editable ? 'true' : 'false');
    }
    if (oldWidget.pageSetup.paddingCss != widget.pageSetup.paddingCss ||
        oldWidget.pageSetup.paperSize != widget.pageSetup.paperSize) {
      _iframe?.srcdoc = _wrap(widget.html).toJS;
      _lastAppliedHtml = widget.html;
      return;
    }
    if (oldWidget.html == widget.html) return;
    // Nếu HTML mới trùng với thứ ta vừa ghi ra (user gõ → onChanged →
    // parent setState → didUpdateWidget) thì không đụng vào body để giữ caret.
    if (widget.html == _lastAppliedHtml) return;
    final body = _iframe?.contentDocument?.body;
    if (body == null) return;
    _applying = true;
    body.innerHTML = posPrintProtectItemMarkers(widget.html).toJS;
    _lastAppliedHtml = widget.html;
    _applying = false;
  }

  String _readHtml(web.HTMLElement body) {
    final raw = body.innerHTML;
    final text = raw is JSString ? raw.toDart : raw.toString();
    return posPrintRestoreItemMarkers(text);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
