import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../utils/pos_commercial_editor_js.dart';
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
    this.onWheel,
    this.onContentHeight,
  });

  final String html;
  final ValueChanged<String> onChanged;
  final bool editable;
  final PosCommercialPageSetup pageSetup;
  final ValueChanged<double>? onWheel;
  final ValueChanged<double>? onContentHeight;

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

    body.addEventListener('input', ((web.Event ev) {
      sync(ev);
      _reportHeight(body);
    }).toJS);
    body.addEventListener('keyup', sync.toJS);
    body.addEventListener('blur', sync.toJS);
    doc.addEventListener(
      'wheel',
      ((web.Event ev) {
        final we = ev as web.WheelEvent;
        if (we.deltaY == 0) return;
      }).toJS,
    );
    _reportHeight(body);
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
  html,body{margin:0;background:#fff;}
  html{height:100%;overflow-y:scroll;overflow-x:hidden;}
  body{overflow:visible;}
  ::-webkit-scrollbar{width:12px;}
  ::-webkit-scrollbar-thumb{background:#94a3b8;border-radius:6px;}
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
  img{max-width:100%;height:auto;}
  .sbox-img{vertical-align:middle;}
  #sbox-ruler{position:sticky;top:0;z-index:5;height:22px;background:#f8fafc;border-bottom:1px solid #cbd5e1;cursor:ew-resize;user-select:none;}
  #sbox-caret{position:absolute;top:0;width:2px;height:22px;background:#2563eb;}
</style></head>
<body contenteditable="$editableAttr"><div id="sbox-ruler" contenteditable="false"><div id="sbox-caret"></div></div>${posPrintProtectItemMarkers(html)}</body>
<script>
function _sboxFlush(){}
$posCommercialEditorScript
document.addEventListener('selectionchange', sboxPlaceCaret);
document.body.addEventListener('input', function(){ sboxSnap(); });
sboxSnap();
var ruler = document.getElementById('sbox-ruler');
if(ruler){
  ruler.addEventListener('mousedown', function(ev){
    ev.preventDefault();
    var el = sboxBlock();
    if(!el || el===document.body || el.id==='sbox-ruler') return;
    var host = ruler.getBoundingClientRect();
    el.style.marginLeft = Math.max(0, ev.clientX-host.left)+'px';
    sboxSnap();
    if(window._sboxFlush) _sboxFlush();
  });
}
</script>
</html>''';
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
      doc.body?.focus();
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

  web.Range? _savedRange;

  void rememberCaret() {
    final sel = _iframe?.contentDocument?.getSelection();
    if (sel != null && sel.rangeCount > 0) {
      _savedRange = sel.getRangeAt(0);
    }
  }

  void _reportHeight(web.HTMLElement body) {
    final h = body.scrollHeight.toDouble();
    if (h > 40) widget.onContentHeight?.call(h + 8);
  }

  void insertImageDataUrl(String src) {
    final doc = _iframe?.contentDocument;
    final body = doc?.body;
    if (doc == null || body == null || !src.startsWith('data:image')) return;
    final img = doc.createElement('img') as web.HTMLImageElement
      ..className = 'sbox-last'
      ..src = src;
    img.style.width = '160px';
    img.style.maxWidth = '100%';
    img.style.height = 'auto';
    final span = doc.createElement('span') as web.HTMLElement
      ..className = 'sbox-img';
    span.setAttribute('contenteditable', 'false');
    span.style.display = 'inline-block';
    span.style.maxWidth = '100%';
    span.appendChild(img);
    final p = doc.createElement('p') as web.HTMLElement;
    p.style.textAlign = 'center';
    p.style.margin = '8px 0';
    p.appendChild(span);
    final sel = doc.getSelection();
    web.Range? range;
    if (sel != null && sel.rangeCount > 0) {
      range = sel.getRangeAt(0);
    } else {
      range = _savedRange;
    }
    if (range != null) {
      range.collapse(false);
      range.insertNode(p);
    } else {
      body.appendChild(p);
    }
    _reportHeight(body);
    final html = _readHtml(body);
    _lastAppliedHtml = html;
    widget.onChanged(html);
  }

  void runScript(String js) {
    final doc = _iframe?.contentDocument;
    if (doc == null) return;
    final script = doc.createElement('script') as web.HTMLScriptElement;
    script.text = js;
    (doc.body ?? doc.documentElement)?.appendChild(script);
    script.remove();
    final body = doc.body;
    if (body != null) {
      final html = _readHtml(body);
      _lastAppliedHtml = html;
      widget.onChanged(html);
    }
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

  String _stripEditorChrome(String html) {
    const start = '<div id="sbox-ruler"';
    final i = html.indexOf(start);
    if (i >= 0) {
      const endMark = '</div></div>';
      final end = html.indexOf(endMark, i);
      if (end >= 0) {
        html = html.replaceRange(i, end + endMark.length, '');
      }
    }
    return html.replaceAll(
      RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
      '',
    );
  }

  String _readHtml(web.HTMLElement body) {
    final raw = body.innerHTML;
    final text = raw is JSString ? raw.toDart : raw.toString();
    return posPrintRestoreItemMarkers(_stripEditorChrome(text));
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

/// Ô HTML thật của trình duyệt — Ctrl+C / Ctrl+V hoạt động, không bị Flutter chặn.
class PosHtmlSourceField extends StatefulWidget {
  const PosHtmlSourceField({super.key, required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<PosHtmlSourceField> createState() => PosHtmlSourceFieldState();
}

class PosHtmlSourceFieldState extends State<PosHtmlSourceField> {
  late final String _viewType;
  web.HTMLTextAreaElement? _area;

  @override
  void initState() {
    super.initState();
    _viewType = 'sbox-html-${identityHashCode(this)}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final area = web.HTMLTextAreaElement()
        ..value = widget.initial
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.boxSizing = 'border-box'
        ..style.fontFamily = 'Consolas, monospace'
        ..style.fontSize = '12px'
        ..spellcheck = false;
      area.addEventListener(
        'input',
        ((web.Event _) => widget.onChanged(area.value)).toJS,
      );
      _area = area;
      return area;
    });
  }

  String get text => _area?.value ?? widget.initial;

  Future<void> copyAll() async {
    final area = _area;
    if (area == null) return;
    area.focus();
    area.select();
    try {
      await web.window.navigator.clipboard.writeText(area.value).toDart;
    } catch (_) {
      area.ownerDocument?.execCommand('copy');
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

web.HTMLInputElement? _keptImageInput;

void pickTemplateImage(void Function(String dataUrl) onPicked) {
  _keptImageInput?.remove();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/*'
    ..style.position = 'fixed'
    ..style.left = '-1000px';
  web.document.body?.appendChild(input);
  _keptImageInput = input;
  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) return;
      _readCompressedImage(file, onPicked);
    }).toJS,
  );
  input.click();
}

void _readCompressedImage(web.File file, void Function(String dataUrl) onPicked) {
  final reader = web.FileReader();
  reader.addEventListener(
    'load',
    ((web.Event _) {
      final raw = reader.result;
      final src = raw == null
          ? ''
          : (raw is JSString ? raw.toDart : raw.toString());
      if (!src.startsWith('data:image')) return;
      final img = web.HTMLImageElement();
      img.addEventListener(
        'load',
        ((web.Event _) {
          var w = img.naturalWidth;
          var h = img.naturalHeight;
          if (w <= 0 || h <= 0) {
            onPicked(src);
            return;
          }
          const maxSide = 900;
          if (w > maxSide || h > maxSide) {
            final scale = maxSide / (w > h ? w : h);
            w = (w * scale).round();
            h = (h * scale).round();
          }
          final canvas = web.HTMLCanvasElement()
            ..width = w
            ..height = h;
          canvas.context2D.drawImage(img, 0, 0, w, h);
          final out = canvas.toDataURL('image/jpeg', 0.72.toJS);
          onPicked(out.startsWith('data:image') ? out : src);
        }).toJS,
      );
      img.src = src;
    }).toJS,
  );
  reader.readAsDataURL(file);
}
