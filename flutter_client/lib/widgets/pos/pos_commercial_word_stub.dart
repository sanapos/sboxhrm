import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/pos_commercial_editor_js.dart';
import '../../utils/pos_print_template_defaults.dart';
import '../../utils/pos_print_template_renderer.dart';
import 'pos_html_preview_stub.dart';

/// Android / iOS: soạn trên tờ A4 contenteditable (như Word).
/// Desktop không có WebView: fallback ô chữ (ít dùng).
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
  WebViewController? _controller;
  late final TextEditingController _fallback;
  String _lastHtml = '';
  bool _ignoreJs = false;
  bool _ready = false;

  static bool get _useWebView {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return true;
      default:
        return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _lastHtml = widget.html;
    _fallback = TextEditingController(text: widget.html);
    if (_useWebView) {
      final c = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFFFFFFF))
        ..addJavaScriptChannel(
          'SboxHost',
          onMessageReceived: (msg) {
            if (_ignoreJs || !widget.editable) return;
            _lastHtml = posPrintRestoreItemMarkers(msg.message);
            widget.onChanged(_lastHtml);
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) {
            _ready = true;
          }),
        )
        ..loadHtmlString(
          _wrapDoc(widget.html, widget.editable, widget.pageSetup),
        );
      _controller = c;
    }
  }

  @override
  void didUpdateWidget(covariant PosCommercialWordSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_useWebView) {
      if (oldWidget.html != widget.html && widget.html != _fallback.text) {
        _fallback.text = widget.html;
      }
      return;
    }
    final c = _controller;
    if (c == null) return;
    final setupChanged = oldWidget.pageSetup.paperSize != widget.pageSetup.paperSize ||
        oldWidget.pageSetup.paddingCss != widget.pageSetup.paddingCss;
    if (oldWidget.editable != widget.editable ||
        setupChanged ||
        (oldWidget.html != widget.html && widget.html != _lastHtml)) {
      _ignoreJs = true;
      _lastHtml = widget.html;
      c
          .loadHtmlString(
            _wrapDoc(widget.html, widget.editable, widget.pageSetup),
          )
          .whenComplete(() {
        _ignoreJs = false;
      });
    }
  }

  @override
  void dispose() {
    _fallback.dispose();
    super.dispose();
  }

  Future<void> flush() async {
    final c = _controller;
    if (c == null || !_ready || !widget.editable) return;
    try {
      await c.runJavaScript('if(window._sboxFlush)_sboxFlush();');
    } catch (_) {}
  }

  void exec(String cmd, [String? value]) {
    if (!_useWebView) {
      _fallbackExec(cmd, value);
      return;
    }
    final c = _controller;
    if (c == null || !_ready) return;
    final jsCmd = jsonEncode(cmd);
    final jsVal = value == null ? 'null' : jsonEncode(value);
    c.runJavaScript(
      'document.execCommand($jsCmd,false,$jsVal);if(window._sboxFlush)_sboxFlush();',
    );
  }

  void insertHtml(String html) => exec('insertHTML', html);

  void rememberCaret() {}

  void insertImageDataUrl(String src) {
    if (!src.startsWith('data:image')) return;
    insertHtml(
      '<p style="text-align:center;margin:8px 0"><img src="$src" style="width:160px;max-width:100%;height:auto" /></p>',
    );
  }

  void runScript(String js) {
    final c = _controller;
    if (c == null || !_ready) return;
    c.runJavaScript('$js;if(window._sboxFlush)_sboxFlush();');
  }

  void _fallbackExec(String cmd, [String? value]) {
    final wrap = switch (cmd) {
      'bold' => ('<b>', '</b>'),
      'italic' => ('<i>', '</i>'),
      'underline' => ('<u>', '</u>'),
      'justifyCenter' => ('<div style="text-align:center">', '</div>'),
      'justifyRight' => ('<div style="text-align:right">', '</div>'),
      'insertUnorderedList' => ('<ul><li>', '</li></ul>'),
      _ => ('', ''),
    };
    if (wrap.$1.isEmpty && (value == null || value.isEmpty)) return;
    final t = _fallback.value;
    final start = t.selection.start < 0 ? t.text.length : t.selection.start;
    final end = t.selection.end < 0 ? start : t.selection.end;
    final sel = t.text.substring(start, end);
    final insert = value != null && value.isNotEmpty
        ? value
        : '${wrap.$1}$sel${wrap.$2}';
    final next = t.text.replaceRange(start, end, insert);
    _fallback.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.editable) {
      final s = widget.pageSetup;
      const mm = 3.78;
      return buildPosRenderedHtml(
        widget.html,
        a4Width: true,
        shrinkWrap: true,
        pageWidth: widget.pageSetup.cssWidth,
        bodyPadding: HtmlPaddings.only(
          top: s.topMm * mm,
          right: s.rightMm * mm,
          bottom: s.bottomMm * mm,
          left: s.leftMm * mm,
        ),
      );
    }
    if (!_useWebView) {
      return TextField(
        controller: _fallback,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(
          fontFamily: 'Times New Roman',
          fontSize: 13.5,
          height: 1.45,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
        onChanged: widget.onChanged,
      );
    }
    final c = _controller;
    if (c == null) {
      return const SizedBox.expand();
    }
    return WebViewWidget(controller: c);
  }
}

class PosHtmlSourceField extends StatefulWidget {
  const PosHtmlSourceField({super.key, required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<PosHtmlSourceField> createState() => PosHtmlSourceFieldState();
}

class PosHtmlSourceFieldState extends State<PosHtmlSourceField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get text => _ctrl.text;

  Future<void> copyAll() async {
    await Clipboard.setData(ClipboardData(text: _ctrl.text));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      maxLines: null,
      expands: true,
      style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
      decoration: const InputDecoration(border: OutlineInputBorder()),
      onChanged: widget.onChanged,
    );
  }
}

void pickTemplateImage(void Function(String dataUrl) onPicked) {
  FilePicker.platform.pickFiles(type: FileType.image, withData: true).then((picked) {
    final bytes = picked?.files.single.bytes;
    if (bytes == null || bytes.isEmpty) return;
    final name = picked!.files.single.name.toLowerCase();
    final mime = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg';
    onPicked('data:$mime;base64,${base64Encode(bytes)}');
  });
}

String _wrapDoc(String html, bool editable, PosCommercialPageSetup setup) {
  final body = posPrintProtectItemMarkers(html)
      .replaceAll(RegExp(r'</script', caseSensitive: false), '<\\/script')
      .replaceAll(RegExp(r'</body', caseSensitive: false), '<\\/body');
  final edit = editable ? 'true' : 'false';
  return '''
<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=2">
<style>
  html,body{margin:0;background:#fff;}
  body{
    font-family:"Times New Roman",Times,serif;
    font-size:13px;line-height:1.45;color:#111;
    padding:${setup.paddingCss};box-sizing:border-box;
    outline:none;word-wrap:break-word;overflow-wrap:anywhere;overflow-x:hidden;
    min-height:100%;
    caret-color:#2563eb;
  }
  body[contenteditable="true"]{cursor:text;}
  h1,h2,h3{text-align:center;margin:8px 0;}
  h2{font-size:17px;font-weight:bold;text-transform:uppercase;}
  p{margin:6px 0;}
  table{border-collapse:collapse;width:100%;max-width:100%;table-layout:fixed;margin:8px 0;}
  th,td{padding:5px 6px;vertical-align:top;word-wrap:break-word;overflow-wrap:anywhere;}
  table[style*="border:1px"] th, table[style*="border:1px"] td,
  th[style*="border:1px"], td[style*="border:1px"]{
    border:1px solid #111;
  }
  img{max-width:100%;height:auto;}
  #sbox-ruler{position:sticky;top:0;height:22px;background:#f8fafc;border-bottom:1px solid #cbd5e1;}
  #sbox-caret{position:absolute;top:0;width:2px;height:22px;background:#2563eb;}
</style>
</head>
<body contenteditable="$edit"><div id="sbox-ruler" contenteditable="false"><div id="sbox-caret"></div></div>$body</body>
<script>
function _sboxFlush(){
  try{ SboxHost.postMessage(sboxCleanHtml()); }catch(e){}
}
$posCommercialEditorScript
document.body.addEventListener('input', function(){ sboxSnap(); _sboxFlush(); });
document.addEventListener('selectionchange', sboxPlaceCaret);
sboxSnap();
document.body.addEventListener('keyup', _sboxFlush);
document.body.addEventListener('blur', _sboxFlush);
document.body.addEventListener('paste', function(ev){
  try{
    var html = ev.clipboardData && ev.clipboardData.getData('text/html');
    if(!html) return;
    ev.preventDefault();
    html = html.replace(/<!--\\[if[^\\]]+\\]>[\\s\\S]*?<!\\[endif\\]-->/g,'')
               .replace(/mso-[^:]+:[^;"]+;?/g,'').replace(/class="[^"]*"/g,'');
    document.execCommand('insertHTML', false, html);
  }catch(e){}
});
</script>
</html>''';
}
