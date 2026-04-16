// Professional WYSIWYG Rich Text Editor for Flutter Web
// Uses contentEditable div with a comprehensive formatting toolbar.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as dom;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';

// ══════════════════════════════════════════════════════════
// Controller
// ══════════════════════════════════════════════════════════

class RichEditorController {
  dom.Element? _editorElement;
  String _pendingHtml = '';

  void _attach(dom.Element element) {
    _editorElement = element;
    if (_pendingHtml.isNotEmpty) {
      _editorElement!.setInnerHtml(_pendingHtml, treeSanitizer: dom.NodeTreeSanitizer.trusted);
      _pendingHtml = '';
    }
  }

  String get html {
    if (_editorElement == null) return _pendingHtml;
    final h = _editorElement!.innerHtml ?? '';
    final textContent = _editorElement!.text?.trim() ?? '';
    if (textContent.isEmpty && !h.contains('<img') && !h.contains('<iframe')) return '';
    return h;
  }

  set html(String value) {
    _pendingHtml = value;
    if (_editorElement != null) {
      _editorElement!.setInnerHtml(value, treeSanitizer: dom.NodeTreeSanitizer.trusted);
    }
  }

  bool get isEmpty {
    if (_editorElement == null) return _pendingHtml.trim().isEmpty;
    final text = _editorElement!.text?.trim() ?? '';
    return text.isEmpty && !(_editorElement!.innerHtml?.contains('<img') ?? false) && !(_editorElement!.innerHtml?.contains('<iframe') ?? false);
  }

  void execCommand(String command, [String? value]) {
    dom.document.execCommand(command, false, value ?? '');
  }

  void insertHtml(String content) {
    execCommand('insertHTML', content);
  }

  void focus() {
    _editorElement?.focus();
  }

  void dispose() {
    _editorElement = null;
  }
}

// ══════════════════════════════════════════════════════════
// Rich Editor Widget
// ══════════════════════════════════════════════════════════

/// Callback type for image upload: takes bytes + fileName, returns the image URL or null.
typedef ImageUploadCallback = Future<String?> Function(List<int> bytes, String fileName);

class RichEditor extends StatefulWidget {
  final RichEditorController controller;
  final ValueChanged<String>? onChanged;
  final double minHeight;
  final String? placeholder;
  final ImageUploadCallback? onImageUpload;

  const RichEditor({
    super.key,
    required this.controller,
    this.onChanged,
    this.minHeight = 350,
    this.placeholder,
    this.onImageUpload,
  });

  @override
  State<RichEditor> createState() => _RichEditorState();
}

class _RichEditorState extends State<RichEditor> {
  static int _counter = 0;
  late final String _viewType;
  bool _isSourceMode = false;
  final _sourceController = TextEditingController();
  dom.Range? _savedRange;
  StreamSubscription? _inputSub;
  StreamSubscription? _blurSub;
  StreamSubscription? _clickSub;
  StreamSubscription? _mouseUpSub;
  StreamSubscription? _contextMenuSub;

  @override
  void initState() {
    super.initState();
    _viewType = 'rich-editor-${_counter++}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final container = dom.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.display = 'flex'
        ..style.flexDirection = 'column';

      final style = dom.StyleElement()..text = _editorCss;
      container.append(style);

      final editorDiv = dom.DivElement()
        ..className = 'rich-editor-content'
        ..contentEditable = 'true'
        ..setAttribute('spellcheck', 'true')
        ..style.flex = '1'
        ..style.outline = 'none'
        ..style.padding = '20px 24px'
        ..style.fontFamily =
            "'Inter','Segoe UI',-apple-system,BlinkMacSystemFont,sans-serif"
        ..style.fontSize = '15px'
        ..style.lineHeight = '1.8'
        ..style.color = '#1e293b'
        ..style.overflowY = 'auto'
        ..style.minHeight = '${widget.minHeight}px'
        ..style.background = '#fff';

      if (widget.placeholder != null) {
        editorDiv.setAttribute('data-placeholder', widget.placeholder!);
      }

      container.append(editorDiv);
      widget.controller._attach(editorDiv);

      _inputSub = editorDiv.onInput.listen((_) {
        widget.onChanged?.call(widget.controller.html);
      });

      _blurSub = editorDiv.onBlur.listen((_) {
        _saveSelection();
      });

      _mouseUpSub = editorDiv.onMouseUp.listen((_) {
        _saveSelection();
      });

      _clickSub = editorDiv.onClick.listen((event) {
        final target = event.target;
        if (target is dom.ImageElement) {
          event.preventDefault();
          _showImageEditDialog(target);
        }
      });

      _contextMenuSub = editorDiv.onContextMenu.listen((event) {
        final cell = _findTableCell(event.target);
        if (cell != null) {
          event.preventDefault();
          _showTableEditMenu(cell);
        }
      });

      return container;
    });
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    _blurSub?.cancel();
    _clickSub?.cancel();
    _mouseUpSub?.cancel();
    _contextMenuSub?.cancel();
    _sourceController.dispose();
    super.dispose();
  }

  void _saveSelection() {
    final sel = dom.window.getSelection();
    if (sel != null && (sel.rangeCount ?? 0) > 0) {
      _savedRange = sel.getRangeAt(0).cloneRange();
    }
  }

  void _restoreSelection() {
    final sel = dom.window.getSelection();
    if (sel == null) return;
    if (_savedRange != null) {
      sel.removeAllRanges();
      sel.addRange(_savedRange!);
    } else {
      final editor = widget.controller._editorElement;
      if (editor != null) {
        final range = dom.document.createRange();
        range.selectNodeContents(editor);
        range.collapse(false);
        sel.removeAllRanges();
        sel.addRange(range);
      }
    }
  }

  void _exec(String command, [String? value]) {
    widget.controller.focus();
    _restoreSelection();
    widget.controller.execCommand(command, value);
    Future.delayed(const Duration(milliseconds: 50), () {
      widget.onChanged?.call(widget.controller.html);
    });
  }

  void _insertContent(String htmlContent) {
    widget.controller.focus();
    _restoreSelection();
    if (htmlContent.contains('<iframe') || htmlContent.contains('<table')) {
      _insertHtmlDom(htmlContent);
    } else {
      widget.controller.insertHtml(htmlContent);
    }
    Future.delayed(const Duration(milliseconds: 50), () {
      widget.onChanged?.call(widget.controller.html);
    });
  }

  void _insertHtmlDom(String html) {
    final editor = widget.controller._editorElement;
    if (editor == null) return;
    final sel = dom.window.getSelection();
    if (sel != null && (sel.rangeCount ?? 0) > 0) {
      final range = sel.getRangeAt(0);
      range.deleteContents();
      final temp = dom.DivElement();
      temp.setInnerHtml(html, treeSanitizer: dom.NodeTreeSanitizer.trusted);
      final frag = dom.document.createDocumentFragment();
      dom.Node? lastNode;
      while (temp.firstChild != null) {
        lastNode = temp.firstChild!;
        frag.append(lastNode);
      }
      range.insertNode(frag);
      if (lastNode != null) {
        range.setStartAfter(lastNode);
        range.collapse(true);
        sel.removeAllRanges();
        sel.addRange(range);
      }
    } else {
      final temp = dom.DivElement();
      temp.setInnerHtml(html, treeSanitizer: dom.NodeTreeSanitizer.trusted);
      while (temp.firstChild != null) {
        editor.append(temp.firstChild!);
      }
    }
  }

  void _toggleSourceMode() {
    setState(() {
      if (!_isSourceMode) {
        _sourceController.text = widget.controller.html;
      } else {
        widget.controller.html = _sourceController.text;
        widget.onChanged?.call(_sourceController.text);
      }
      _isSourceMode = !_isSourceMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbar(),
          Container(
            height: widget.minHeight + 50,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: _isSourceMode
                ? _buildSourceEditor()
                : ClipRRect(
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                    child: HtmlElementView(viewType: _viewType),
                  ),
          ),
        ],
      ),
    );
  }

  // ─────────────── Source Code Editor ───────────────

  Widget _buildSourceEditor() {
    return TextField(
      controller: _sourceController,
      maxLines: null,
      expands: true,
      style: const TextStyle(
        fontFamily: 'Consolas, "Fira Code", monospace',
        fontSize: 13,
        height: 1.6,
        color: Color(0xFF334155),
      ),
      decoration: const InputDecoration(
        border: InputBorder.none,
        contentPadding: EdgeInsets.all(20),
        hintText: '<!-- Nhập mã HTML tại đây -->',
        hintStyle: TextStyle(color: Color(0xFFA1A1AA)),
      ),
      onChanged: (value) => widget.onChanged?.call(value),
    );
  }

  // ─────────────── Toolbar ───────────────

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Wrap(
        spacing: 1,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // ── Text Formatting ──
          _btn(Icons.format_bold, 'Đậm (Ctrl+B)', () => _exec('bold')),
          _btn(Icons.format_italic, 'Nghiêng (Ctrl+I)', () => _exec('italic')),
          _btn(Icons.format_underlined, 'Gạch chân (Ctrl+U)',
              () => _exec('underline')),
          _btn(Icons.format_strikethrough, 'Gạch ngang',
              () => _exec('strikeThrough')),
          _divider(),

          // ── Headings ──
          _headingDropdown(),
          _fontSizeDropdown(),
          _divider(),

          // ── Lists ──
          _btn(Icons.format_list_bulleted, 'Danh sách gạch đầu dòng',
              () => _exec('insertUnorderedList')),
          _btn(Icons.format_list_numbered, 'Danh sách đánh số',
              () => _exec('insertOrderedList')),
          _btn(Icons.checklist, 'Danh sách kiểm tra', _insertChecklist),
          _divider(),

          // ── Block Elements ──
          _btn(Icons.format_quote, 'Trích dẫn',
              () => _exec('formatBlock', 'blockquote')),
          _btn(Icons.code, 'Khối code',
              () => _insertContent('<pre><code>\n</code></pre>')),
          _btn(Icons.horizontal_rule, 'Đường kẻ ngang',
              () => _exec('insertHorizontalRule')),
          _divider(),

          // ── Alignment ──
          _btn(Icons.format_align_left, 'Căn trái',
              () => _exec('justifyLeft')),
          _btn(Icons.format_align_center, 'Căn giữa',
              () => _exec('justifyCenter')),
          _btn(Icons.format_align_right, 'Căn phải',
              () => _exec('justifyRight')),
          _btn(Icons.format_align_justify, 'Căn đều',
              () => _exec('justifyFull')),
          _divider(),

          // ── Insert ──
          _btn(Icons.link, 'Chèn liên kết', _showLinkDialog),
          _btn(Icons.image_outlined, 'Chèn hình ảnh', _showImageDialog),
          _btn(Icons.play_circle_outline, 'Chèn video YouTube', _showYoutubeDialog),
          _btn(Icons.table_chart_outlined, 'Chèn bảng', _showTableDialog),
          _btn(Icons.smart_button_outlined, 'Chèn nút', _showButtonDialog),
          _divider(),

          // ── Colors ──
          _colorButton(
              Icons.format_color_text, 'Màu chữ', (c) => _exec('foreColor', c)),
          _colorButton(Icons.format_color_fill, 'Màu nền chữ',
              (c) => _exec('hiliteColor', c)),
          _divider(),

          // ── History & Cleanup ──
          _btn(Icons.undo, 'Hoàn tác (Ctrl+Z)', () => _exec('undo')),
          _btn(Icons.redo, 'Làm lại (Ctrl+Y)', () => _exec('redo')),
          _btn(Icons.format_clear, 'Xóa định dạng',
              () => _exec('removeFormat')),
          _divider(),

          // ── Mode Toggle ──
          _btn(
            _isSourceMode ? Icons.edit_note : Icons.code,
            _isSourceMode ? 'Soạn thảo trực quan' : 'Xem mã HTML',
            _toggleSourceMode,
            isActive: _isSourceMode,
          ),
        ],
      ),
    );
  }

  // ─────────────── Toolbar Button Helpers ───────────────

  Widget _btn(IconData icon, String tooltip, VoidCallback onTap,
      {bool isActive = false}) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: const Color(0xFFE4E4E7),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFE8F0FE) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon,
                size: 18,
                color: isActive
                    ? const Color(0xFF1E3A5F)
                    : const Color(0xFF52525B)),
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFE4E4E7),
    );
  }

  // ─────────────── Heading Dropdown ───────────────

  Widget _headingDropdown() {
    return PopupMenuButton<String>(
      tooltip: 'Kiểu đề mục',
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.title, size: 18, color: Color(0xFF52525B)),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF52525B)),
          ],
        ),
      ),
      itemBuilder: (_) => [
        _headingItem('p', 'Đoạn văn', 14, FontWeight.normal),
        _headingItem('h1', 'Tiêu đề 1', 24, FontWeight.bold),
        _headingItem('h2', 'Tiêu đề 2', 20, FontWeight.bold),
        _headingItem('h3', 'Tiêu đề 3', 17, FontWeight.w600),
        _headingItem('h4', 'Tiêu đề 4', 15, FontWeight.w600),
      ],
      onSelected: (value) => _exec('formatBlock', value),
    );
  }

  PopupMenuItem<String> _headingItem(
      String value, String label, double size, FontWeight weight) {
    return PopupMenuItem(
      value: value,
      child: Text(label,
          style: TextStyle(fontSize: size, fontWeight: weight)),
    );
  }

  // ─────────────── Font Size Dropdown ───────────────

  Widget _fontSizeDropdown() {
    return PopupMenuButton<String>(
      tooltip: 'Cỡ chữ',
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_size, size: 18, color: Color(0xFF52525B)),
            SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF52525B)),
          ],
        ),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: '1',
            child: Text('Rất nhỏ', style: TextStyle(fontSize: 10))),
        const PopupMenuItem(
            value: '2',
            child: Text('Nhỏ', style: TextStyle(fontSize: 12))),
        const PopupMenuItem(
            value: '3',
            child: Text('Bình thường', style: TextStyle(fontSize: 14))),
        const PopupMenuItem(
            value: '4',
            child: Text('Vừa', style: TextStyle(fontSize: 16))),
        const PopupMenuItem(
            value: '5',
            child: Text('Lớn', style: TextStyle(fontSize: 18))),
        const PopupMenuItem(
            value: '6',
            child: Text('Rất lớn', style: TextStyle(fontSize: 22))),
        const PopupMenuItem(
            value: '7',
            child: Text('Cực lớn', style: TextStyle(fontSize: 28))),
      ],
      onSelected: (value) => _exec('fontSize', value),
    );
  }

  // ─────────────── Color Picker ───────────────

  Widget _colorButton(
      IconData icon, String tooltip, ValueChanged<String> onColor) {
    return PopupMenuButton<String>(
      tooltip: tooltip,
      offset: const Offset(0, 36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: const Color(0xFF52525B)),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: 200,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _editorColors
                  .map((color) => GestureDetector(
                        onTap: () {
                          onColor(color);
                          Navigator.pop(context);
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _hexToColor(color),
                            borderRadius: BorderRadius.circular(6),
                            border:
                                Border.all(color: const Color(0xFFE4E4E7)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────── Insert Checklist ───────────────

  void _insertChecklist() {
    _insertContent(
      '<ul style="list-style:none;padding-left:4px;margin:0.5em 0">'
      '<li style="margin:4px 0"><input type="checkbox" style="margin-right:8px;cursor:pointer;width:16px;height:16px;vertical-align:middle"/>Mục 1</li>'
      '<li style="margin:4px 0"><input type="checkbox" style="margin-right:8px;cursor:pointer;width:16px;height:16px;vertical-align:middle"/>Mục 2</li>'
      '<li style="margin:4px 0"><input type="checkbox" style="margin-right:8px;cursor:pointer;width:16px;height:16px;vertical-align:middle"/>Mục 3</li>'
      '</ul>',
    );
  }

  // ─────────────── Insert Link Dialog ───────────────

  void _showLinkDialog() {
    final urlCtrl = TextEditingController();
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.link, color: Color(0xFF1E3A5F), size: 22),
            SizedBox(width: 10),
            Text('Chèn liên kết',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: textCtrl,
                  decoration: InputDecoration(
                    labelText: 'Văn bản hiển thị',
                    hintText: 'Nhập văn bản...',
                    prefixIcon: const Icon(Icons.text_fields, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlCtrl,
                decoration: InputDecoration(
                  labelText: 'URL',
                  hintText: 'https://example.com',
                  prefixIcon: const Icon(Icons.link, size: 20),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton.icon(
            onPressed: () {
              final url = urlCtrl.text.trim();
              final text = textCtrl.text.trim();
              if (url.isNotEmpty && _isSafeUrl(url)) {
                final safeUrl = _escapeHtml(url);
                final safeText = _escapeHtml(text.isNotEmpty ? text : url);
                _insertContent(
                    '<a href="$safeUrl" target="_blank" rel="noopener noreferrer" style="color:#6366f1">$safeText</a>');
              }
              Navigator.pop(ctx);
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Chèn'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F)),
          ),
        ],
      ),
    );
  }

  // ─────────────── Insert Image Dialog ───────────────

  void _showImageDialog() {
    final urlCtrl = TextEditingController();
    final altCtrl = TextEditingController();
    String size = '100';
    String align = 'none';
    String borderRadius = '8';
    bool isUploading = false;
    String? uploadedUrl;
    int tabIndex = widget.onImageUpload != null ? 0 : 1; // 0=upload, 1=URL

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.image, color: Color(0xFF1E3A5F), size: 22),
              SizedBox(width: 10),
              Text('Chèn hình ảnh',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tab selector
                  if (widget.onImageUpload != null)
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDlgState(() => tabIndex = 0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: tabIndex == 0 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: tabIndex == 0 ? [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)
                                ] : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.upload_file, size: 18,
                                      color: tabIndex == 0 ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA)),
                                  const SizedBox(width: 6),
                                  Text('Upload ảnh',
                                      style: TextStyle(
                                        fontWeight: tabIndex == 0 ? FontWeight.w600 : FontWeight.normal,
                                        color: tabIndex == 0 ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA),
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setDlgState(() => tabIndex = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: tabIndex == 1 ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: tabIndex == 1 ? [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4)
                                ] : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.link, size: 18,
                                      color: tabIndex == 1 ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA)),
                                  const SizedBox(width: 6),
                                  Text('URL ảnh',
                                      style: TextStyle(
                                        fontWeight: tabIndex == 1 ? FontWeight.w600 : FontWeight.normal,
                                        color: tabIndex == 1 ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA),
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.onImageUpload != null) const SizedBox(height: 16),

                // Upload tab
                if (tabIndex == 0 && widget.onImageUpload != null) ...[
                  if (uploadedUrl != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: uploadedUrl!,
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                        errorWidget: (_, __, ___) => Container(
                          height: 150, color: Colors.grey[200],
                          child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Ảnh đã upload thành công!',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500))),
                        TextButton(
                          onPressed: isUploading ? null : () async {
                            setDlgState(() { uploadedUrl = null; });
                          },
                          child: const Text('Chọn ảnh khác'),
                        ),
                      ],
                    ),
                  ] else ...[
                    GestureDetector(
                      onTap: isUploading ? null : () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          allowMultiple: false,
                          withData: true,
                        );
                        if (result == null || result.files.isEmpty) return;
                        final file = result.files.first;
                        if (file.bytes == null) return;

                        setDlgState(() { isUploading = true; });
                        try {
                          final url = await widget.onImageUpload!(file.bytes!.toList(), file.name);
                          if (url != null) {
                            setDlgState(() {
                              uploadedUrl = url;
                              urlCtrl.text = url;
                            });
                          } else {
                            // Lỗi upload ảnh - đã tắt thông báo
                          }
                        } finally {
                          setDlgState(() { isUploading = false; });
                        }
                      },
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFCBD5E1), width: 2, style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFFAFAFA),
                        ),
                        child: isUploading
                            ? const Center(child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(strokeWidth: 3),
                                  SizedBox(height: 12),
                                  Text('Đang upload...', style: TextStyle(color: Color(0xFF71717A))),
                                ],
                              ))
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_upload_outlined, size: 40, color: Color(0xFFA1A1AA)),
                                  SizedBox(height: 8),
                                  Text('Nhấn để chọn ảnh từ thiết bị',
                                      style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.w500)),
                                  SizedBox(height: 4),
                                  Text('Hỗ trợ: JPG, PNG, GIF, WebP (tối đa 10MB)',
                                      style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
                                ],
                              ),
                      ),
                    ),
                  ],
                ],

                // URL tab
                if (tabIndex == 1) ...[
                  TextField(
                    controller: urlCtrl,
                    decoration: InputDecoration(
                      labelText: 'URL hình ảnh',
                      hintText: 'https://example.com/image.jpg',
                      prefixIcon: const Icon(Icons.image, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                TextField(
                  controller: altCtrl,
                  decoration: InputDecoration(
                    labelText: 'Mô tả ảnh (alt text)',
                    hintText: 'Mô tả cho hình ảnh...',
                    prefixIcon: const Icon(Icons.description, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Căn chỉnh:',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    _alignChip('Trái', Icons.format_align_left, align == 'none',
                        () => setDlgState(() => align = 'none')),
                    const SizedBox(width: 6),
                    _alignChip('Giữa', Icons.format_align_center, align == 'center',
                        () => setDlgState(() => align = 'center')),
                    const SizedBox(width: 6),
                    _alignChip('Phải', Icons.format_align_right, align == 'right',
                        () => setDlgState(() => align = 'right')),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Kích thước:',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('25%'),
                      selected: size == '25',
                      onSelected: (_) => setDlgState(() => size = '25'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('50%'),
                      selected: size == '50',
                      onSelected: (_) => setDlgState(() => size = '50'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('75%'),
                      selected: size == '75',
                      onSelected: (_) => setDlgState(() => size = '75'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('100%'),
                      selected: size == '100',
                      onSelected: (_) => setDlgState(() => size = '100'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Bo góc:',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Không'),
                      selected: borderRadius == '0',
                      onSelected: (_) => setDlgState(() => borderRadius = '0'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('8px'),
                      selected: borderRadius == '8',
                      onSelected: (_) => setDlgState(() => borderRadius = '8'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('16px'),
                      selected: borderRadius == '16',
                      onSelected: (_) => setDlgState(() => borderRadius = '16'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('24px'),
                      selected: borderRadius == '24',
                      onSelected: (_) => setDlgState(() => borderRadius = '24'),
                    ),
                  ],
                ),
                  ],
                ),
                ),
              ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: () {
                final url = tabIndex == 0 ? (uploadedUrl ?? '') : urlCtrl.text.trim();
                final alt = altCtrl.text.trim();
                if (url.isNotEmpty && _isSafeUrl(url)) {
                  final safeUrl = _escapeHtml(url);
                  final safeAlt = _escapeHtml(alt);
                  String imgStyle = 'max-width:$size%;border-radius:${borderRadius}px;';
                  switch (align) {
                    case 'center':
                      imgStyle += 'display:block;margin:8px auto;';
                      break;
                    case 'right':
                      imgStyle += 'display:block;margin:8px 0 8px auto;';
                      break;
                    default:
                      imgStyle += 'display:block;margin:8px 0;';
                  }
                  _insertContent(
                      '<img src="$safeUrl" alt="$safeAlt" '
                      'style="$imgStyle"/>');
                }
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Chèn'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Edit Image Dialog (click on existing image) ───────────────

  void _showImageEditDialog(dom.ImageElement img) {
    String currentSize = '100';
    String currentAlign = 'none';
    String currentBorderRadius = '8';
    final altCtrl = TextEditingController(text: img.alt ?? '');

    // Parse current styles using getPropertyValue for reliability
    final maxWidthStr = img.style.getPropertyValue('max-width');
    final maxWidthMatch = RegExp(r'(\d+)%').firstMatch(maxWidthStr);
    if (maxWidthMatch != null) currentSize = maxWidthMatch.group(1)!;

    final borderRadiusStr = img.style.getPropertyValue('border-radius');
    final borderRadiusMatch = RegExp(r'(\d+)').firstMatch(borderRadiusStr);
    if (borderRadiusMatch != null) currentBorderRadius = borderRadiusMatch.group(1)!;

    final marginLeft = img.style.getPropertyValue('margin-left').trim();
    final marginRight = img.style.getPropertyValue('margin-right').trim();
    final floatVal = img.style.getPropertyValue('float').trim();

    if (floatVal == 'left') {
      currentAlign = 'float-left';
    } else if (floatVal == 'right') {
      currentAlign = 'float-right';
    } else if (marginLeft == 'auto' && marginRight == 'auto') {
      currentAlign = 'center';
    } else if (marginLeft == 'auto') {
      currentAlign = 'right';
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          void applyStyles() {
            String newStyle = 'max-width:$currentSize%;border-radius:${currentBorderRadius}px;';
            switch (currentAlign) {
              case 'center':
                newStyle += 'display:block;margin:8px auto;';
                break;
              case 'right':
                newStyle += 'display:block;margin:8px 0 8px auto;';
                break;
              case 'float-left':
                newStyle += 'float:left;margin:0 12px 8px 0;';
                break;
              case 'float-right':
                newStyle += 'float:right;margin:0 0 8px 12px;';
                break;
              default:
                newStyle += 'display:block;margin:8px 0;';
            }
            img.setAttribute('style', newStyle);
            img.alt = altCtrl.text;
            widget.onChanged?.call(widget.controller.html);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.image, color: Color(0xFF1E3A5F), size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Chỉnh sửa hình ảnh',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Xóa ảnh',
                  onPressed: () {
                    img.remove();
                    widget.onChanged?.call(widget.controller.html);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Preview
                    ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: img.src ?? '',
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, __, ___) => Container(
                        height: 160,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey, size: 40),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Alignment
                  Row(
                    children: [
                      const Text('Căn chỉnh:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 12),
                      _alignChip('Trái', Icons.format_align_left, currentAlign == 'none',
                          () => setDlgState(() => currentAlign = 'none')),
                      const SizedBox(width: 6),
                      _alignChip('Giữa', Icons.format_align_center, currentAlign == 'center',
                          () => setDlgState(() => currentAlign = 'center')),
                      const SizedBox(width: 6),
                      _alignChip('Phải', Icons.format_align_right, currentAlign == 'right',
                          () => setDlgState(() => currentAlign = 'right')),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Size
                  Row(
                    children: [
                      const Text('Kích thước:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('25%'),
                        selected: currentSize == '25',
                        onSelected: (_) => setDlgState(() => currentSize = '25'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('50%'),
                        selected: currentSize == '50',
                        onSelected: (_) => setDlgState(() => currentSize = '50'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('75%'),
                        selected: currentSize == '75',
                        onSelected: (_) => setDlgState(() => currentSize = '75'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('100%'),
                        selected: currentSize == '100',
                        onSelected: (_) => setDlgState(() => currentSize = '100'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Border Radius
                  Row(
                    children: [
                      const Text('Bo góc:',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('Không'),
                        selected: currentBorderRadius == '0',
                        onSelected: (_) => setDlgState(() => currentBorderRadius = '0'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('8px'),
                        selected: currentBorderRadius == '8',
                        onSelected: (_) => setDlgState(() => currentBorderRadius = '8'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('16px'),
                        selected: currentBorderRadius == '16',
                        onSelected: (_) => setDlgState(() => currentBorderRadius = '16'),
                      ),
                      const SizedBox(width: 6),
                      ChoiceChip(
                        label: const Text('24px'),
                        selected: currentBorderRadius == '24',
                        onSelected: (_) => setDlgState(() => currentBorderRadius = '24'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Alt text
                  TextField(
                    controller: altCtrl,
                    decoration: InputDecoration(
                      labelText: 'Mô tả ảnh (alt text)',
                      prefixIcon: const Icon(Icons.description, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  ],
                ),
                ),
              ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Hủy')),
              FilledButton.icon(
                onPressed: () {
                  applyStyles();
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Áp dụng'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _alignChip(String label, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F0FE) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? const Color(0xFF1E3A5F) : const Color(0xFFCBD5E1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF71717A)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }

  // ─────────────── Table Cell Finder ───────────────

  dom.TableCellElement? _findTableCell(dom.EventTarget? target) {
    dom.Element? el = target is dom.Element ? target : null;
    while (el != null) {
      if (el.tagName == 'TD' || el.tagName == 'TH') {
        return el as dom.TableCellElement;
      }
      if (el.className.contains('rich-editor-content')) break;
      el = el.parent;
    }
    return null;
  }

  dom.TableElement? _findTable(dom.Element cell) {
    dom.Element? el = cell;
    while (el != null) {
      if (el is dom.TableElement) return el;
      el = el.parent;
    }
    return null;
  }

  // ─────────────── Table Edit Menu (Right-Click) ───────────────

  void _showTableEditMenu(dom.TableCellElement cell) {
    final table = _findTable(cell);
    if (table == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.table_chart, color: Color(0xFF1E3A5F), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Chỉnh sửa bảng',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Thêm hàng',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF52525B))),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _tableActionButton(Icons.vertical_align_top, 'Thêm hàng trên', () {
                    _tableAddRow(cell, table, above: true);
                    Navigator.pop(ctx);
                  })),
                  const SizedBox(width: 8),
                  Expanded(child: _tableActionButton(Icons.vertical_align_bottom, 'Thêm hàng dưới', () {
                    _tableAddRow(cell, table, above: false);
                    Navigator.pop(ctx);
                  })),
                ],
              ),
              const SizedBox(height: 14),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Thêm cột',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF52525B))),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _tableActionButton(Icons.arrow_back, 'Thêm cột trái', () {
                    _tableAddColumn(cell, table, left: true);
                    Navigator.pop(ctx);
                  })),
                  const SizedBox(width: 8),
                  Expanded(child: _tableActionButton(Icons.arrow_forward, 'Thêm cột phải', () {
                    _tableAddColumn(cell, table, left: false);
                    Navigator.pop(ctx);
                  })),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Xóa',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFFEF4444))),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _tableActionButton(Icons.table_rows_outlined, 'Xóa hàng', () {
                    _tableDeleteRow(cell, table);
                    Navigator.pop(ctx);
                  }, color: const Color(0xFFEF4444))),
                  const SizedBox(width: 8),
                  Expanded(child: _tableActionButton(Icons.view_column_outlined, 'Xóa cột', () {
                    _tableDeleteColumn(cell, table);
                    Navigator.pop(ctx);
                  }, color: const Color(0xFFEF4444))),
                  const SizedBox(width: 8),
                  Expanded(child: _tableActionButton(Icons.delete_forever_outlined, 'Xóa bảng', () {
                    table.remove();
                    widget.onChanged?.call(widget.controller.html);
                    Navigator.pop(ctx);
                  }, color: const Color(0xFFEF4444))),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Kiểu bảng',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF52525B))),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _tableActionButton(Icons.border_all, 'Thêm tiêu đề', () {
                    _tableToggleHeader(table, addHeader: true);
                    Navigator.pop(ctx);
                  })),
                  const SizedBox(width: 8),
                  Expanded(child: _tableActionButton(Icons.border_clear, 'Xóa tiêu đề', () {
                    _tableToggleHeader(table, addHeader: false);
                    Navigator.pop(ctx);
                  })),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableActionButton(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    final c = color ?? const Color(0xFF52525B);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color != null ? color.withValues(alpha: 0.3) : const Color(0xFFE4E4E7)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: c),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────── Table Manipulation Methods ───────────────

  void _tableAddRow(dom.TableCellElement cell, dom.TableElement table, {required bool above}) {
    final row = cell.parent;
    if (row == null) return;
    final numCols = row.children.length;
    final newRow = dom.document.createElement('tr');
    for (int i = 0; i < numCols; i++) {
      final td = dom.document.createElement('td');
      td.innerHtml = '&nbsp;';
      newRow.append(td);
    }
    if (above) {
      row.parent!.insertBefore(newRow, row);
    } else {
      final next = row.nextElementSibling;
      if (next != null) {
        row.parent!.insertBefore(newRow, next);
      } else {
        row.parent!.append(newRow);
      }
    }
    widget.onChanged?.call(widget.controller.html);
  }

  void _tableAddColumn(dom.TableCellElement cell, dom.TableElement table, {required bool left}) {
    final row = cell.parent as dom.Element;
    final cellIndex = row.children.toList().indexOf(cell);
    final allRows = table.querySelectorAll('tr');
    for (final r in allRows) {
      final cells = r.children.toList();
      final isHeaderRow = cells.isNotEmpty && cells.first.tagName == 'TH';
      final newCell = dom.document.createElement(isHeaderRow ? 'th' : 'td');
      newCell.innerHtml = '&nbsp;';
      final insertIdx = left ? cellIndex : cellIndex + 1;
      if (insertIdx < cells.length) {
        r.insertBefore(newCell, cells[insertIdx]);
      } else {
        r.append(newCell);
      }
    }
    widget.onChanged?.call(widget.controller.html);
  }

  void _tableDeleteRow(dom.TableCellElement cell, dom.TableElement table) {
    final row = cell.parent;
    if (row == null) return;
    final allRows = table.querySelectorAll('tr');
    if (allRows.length <= 1) {
      table.remove();
    } else {
      row.remove();
      final thead = table.querySelector('thead');
      if (thead != null && thead.children.isEmpty) thead.remove();
      final tbody = table.querySelector('tbody');
      if (tbody != null && tbody.children.isEmpty) tbody.remove();
    }
    widget.onChanged?.call(widget.controller.html);
  }

  void _tableDeleteColumn(dom.TableCellElement cell, dom.TableElement table) {
    final row = cell.parent as dom.Element;
    final cellIndex = row.children.toList().indexOf(cell);
    final allRows = table.querySelectorAll('tr');
    final onlyOneCol = allRows.every((r) => r.children.length <= 1);
    if (onlyOneCol) {
      table.remove();
    } else {
      for (final r in allRows) {
        final cells = r.children.toList();
        if (cellIndex < cells.length) {
          cells[cellIndex].remove();
        }
      }
    }
    widget.onChanged?.call(widget.controller.html);
  }

  void _tableToggleHeader(dom.TableElement table, {required bool addHeader}) {
    if (addHeader) {
      if (table.querySelector('thead') != null) return;
      final firstRow = table.querySelector('tr');
      if (firstRow == null) return;
      final thead = dom.document.createElement('thead');
      final newRow = dom.document.createElement('tr');
      for (final cell in firstRow.children.toList()) {
        final th = dom.document.createElement('th');
        th.innerHtml = cell.innerHtml;
        newRow.append(th);
      }
      thead.append(newRow);
      firstRow.remove();
      table.insertBefore(thead, table.firstChild);
    } else {
      final thead = table.querySelector('thead');
      if (thead == null) return;
      final tbody = table.querySelector('tbody') ?? table;
      for (final row in thead.querySelectorAll('tr').toList()) {
        final newRow = dom.document.createElement('tr');
        for (final cell in row.children.toList()) {
          final td = dom.document.createElement('td');
          td.innerHtml = cell.innerHtml;
          newRow.append(td);
        }
        if (tbody.firstChild != null) {
          tbody.insertBefore(newRow, tbody.firstChild);
        } else {
          tbody.append(newRow);
        }
      }
      thead.remove();
    }
    widget.onChanged?.call(widget.controller.html);
  }

  // ─────────────── Insert YouTube Dialog ───────────────

  void _showYoutubeDialog() {
    final urlCtrl = TextEditingController();
    String width = '100';
    String? previewId;

    String? extractVideoId(String url) {
      // youtube.com/watch?v=ID
      final uri = Uri.tryParse(url);
      if (uri == null) return null;
      if (uri.host.contains('youtube.com') && uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
      // youtu.be/ID
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      // youtube.com/embed/ID
      if (uri.host.contains('youtube.com') && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'embed') {
        return uri.pathSegments[1];
      }
      // youtube.com/shorts/ID
      if (uri.host.contains('youtube.com') && uri.pathSegments.length >= 2 && uri.pathSegments[0] == 'shorts') {
        return uri.pathSegments[1];
      }
      return null;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.play_circle_fill, color: Color(0xFFFF0000), size: 22),
              SizedBox(width: 10),
              Text('Chèn video YouTube',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: 'URL video YouTube',
                    hintText: 'https://www.youtube.com/watch?v=...',
                    prefixIcon: const Icon(Icons.link, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, size: 20),
                      tooltip: 'Xem trước',
                      onPressed: () {
                        final id = extractVideoId(urlCtrl.text.trim());
                        setDlgState(() => previewId = id);
                      },
                    ),
                  ),
                  onChanged: (v) {
                    final id = extractVideoId(v.trim());
                    if (id != previewId) setDlgState(() => previewId = id);
                  },
                ),
                const SizedBox(height: 14),
                if (previewId != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: 'https://img.youtube.com/vi/$previewId/hqdefault.jpg',
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, __, ___) => Container(
                        height: 180,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam_off, color: Colors.grey, size: 40),
                              SizedBox(height: 8),
                              Text('Không tải được thumbnail',
                                  style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Text('Video ID: $previewId',
                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 14),
                ] else if (urlCtrl.text.trim().isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('Không nhận dạng được URL YouTube. Vui lòng kiểm tra lại.',
                              style: TextStyle(color: Color(0xFFEF4444), fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    const Text('Chiều rộng:',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('50%'),
                      selected: width == '50',
                      onSelected: (_) => setDlgState(() => width = '50'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('75%'),
                      selected: width == '75',
                      onSelected: (_) => setDlgState(() => width = '75'),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('100%'),
                      selected: width == '100',
                      onSelected: (_) => setDlgState(() => width = '100'),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: previewId != null
                  ? () {
                      final videoId = previewId!;
                      final embedHtml =
                          '<div contenteditable="false" style="position:relative;width:$width%;padding-bottom:${(int.parse(width) * 56.25 / 100).toStringAsFixed(2)}%;margin:16px auto;border-radius:12px;overflow:hidden;box-shadow:0 4px 16px rgba(0,0,0,0.08);">'
                          '<iframe src="https://www.youtube.com/embed/$videoId" '
                          'style="position:absolute;top:0;left:0;width:100%;height:100%;border:none;" '
                          'frameborder="0" allowfullscreen allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share">'
                          '</iframe></div><p><br></p>';
                      _insertContent(embedHtml);
                      Navigator.pop(ctx);
                    }
                  : null,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Chèn video'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0000)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Insert Table Dialog ───────────────

  void _showTableDialog() {
    int rows = 3, cols = 3;
    bool hasHeader = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.table_chart, color: Color(0xFF1E3A5F), size: 22),
              SizedBox(width: 10),
              Text('Chèn bảng',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Text('Số hàng dữ liệu:',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: DropdownButtonFormField<int>(
                      value: rows,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: List.generate(
                          10,
                          (i) => DropdownMenuItem(
                              value: i + 1, child: Text('${i + 1}'))),
                      onChanged: (v) =>
                          setDlgState(() => rows = v ?? 3),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const Text('Số cột:',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    child: DropdownButtonFormField<int>(
                      value: cols,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      items: List.generate(
                          10,
                          (i) => DropdownMenuItem(
                              value: i + 1, child: Text('${i + 1}'))),
                      onChanged: (v) =>
                          setDlgState(() => cols = v ?? 3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: hasHeader,
                onChanged: (v) =>
                    setDlgState(() => hasHeader = v ?? true),
                title: const Text('Có hàng tiêu đề'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: () {
                final sb = StringBuffer('<table>');
                if (hasHeader) {
                  sb.write('<thead><tr>');
                  for (int c = 0; c < cols; c++) {
                    sb.write('<th>Tiêu đề ${c + 1}</th>');
                  }
                  sb.write('</tr></thead>');
                }
                sb.write('<tbody>');
                for (int r = 0; r < rows; r++) {
                  sb.write('<tr>');
                  for (int c = 0; c < cols; c++) {
                    sb.write('<td>&nbsp;</td>');
                  }
                  sb.write('</tr>');
                }
                sb.write('</tbody></table>');
                _insertContent(sb.toString());
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Chèn'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Insert Button / CTA Dialog ───────────────

  void _showButtonDialog() {
    final textCtrl = TextEditingController(text: 'Nhấn vào đây');
    final urlCtrl = TextEditingController();
    String color = '#6366F1';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.smart_button, color: Color(0xFF1E3A5F), size: 22),
              SizedBox(width: 10),
              Text('Chèn nút bấm',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: textCtrl,
                  decoration: InputDecoration(
                    labelText: 'Văn bản nút',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: 'URL liên kết',
                    hintText: 'https://...',
                    prefixIcon: const Icon(Icons.link, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Text('Màu nút:',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 12),
                    ...[
                      '#6366F1',
                      '#10B981',
                      '#F59E0B',
                      '#EF4444',
                      '#3B82F6',
                      '#8B5CF6'
                    ].map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () => setDlgState(() => color = c),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _hexToColor(c),
                              borderRadius: BorderRadius.circular(6),
                              border: color == c
                                  ? Border.all(
                                      color: Colors.white, width: 2)
                                  : null,
                              boxShadow: color == c
                                  ? [
                                      BoxShadow(
                                          color: _hexToColor(c)
                                              .withValues(alpha: 0.5),
                                          blurRadius: 6)
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: () {
                final text = textCtrl.text.trim();
                final url = urlCtrl.text.trim();
                if (text.isNotEmpty) {
                  final safeText = _escapeHtml(text);
                  String href = '';
                  if (url.isNotEmpty && _isSafeUrl(url)) {
                    final safeUrl = _escapeHtml(url);
                    href = ' href="$safeUrl" target="_blank" rel="noopener noreferrer"';
                  }
                  _insertContent(
                      '<a$href style="display:inline-block;padding:10px 24px;'
                      'background:$color;color:#fff;border-radius:8px;'
                      'text-decoration:none;font-weight:600;font-size:14px;'
                      'cursor:pointer;margin:8px 0">$safeText</a>');
                }
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Chèn'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F)),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── Hex Color Helper ───────────────

  /// Escape HTML special characters to prevent XSS/broken markup
  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// Validate URL is safe (block javascript: and data: protocols)
  static bool _isSafeUrl(String url) {
    final lower = url.trim().toLowerCase();
    if (lower.startsWith('javascript:') || lower.startsWith('data:')) return false;
    return true;
  }

  static Color _hexToColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
}

// ══════════════════════════════════════════════════════════
// HTML Content View (read-only renderer for detail dialogs)
// ══════════════════════════════════════════════════════════

class HtmlContentView extends StatefulWidget {
  final String html;
  final double? minHeight;

  const HtmlContentView({super.key, required this.html, this.minHeight});

  @override
  State<HtmlContentView> createState() => _HtmlContentViewState();
}

class _HtmlContentViewState extends State<HtmlContentView> {
  static int _counter = 0;
  late String _viewType;
  dom.DivElement? _contentDiv;
  double _measuredHeight = 500;

  @override
  void initState() {
    super.initState();
    _registerView();
  }

  void _registerView() {
    _viewType = 'html-content-${_counter++}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final wrapper = dom.DivElement()
        ..style.width = '100%'
        ..style.height = 'auto'
        ..style.overflow = 'visible';

      final style = dom.StyleElement()..text = _contentViewCss;
      wrapper.append(style);

      final div = dom.DivElement()
        ..className = 'html-content-view'
        ..style.width = '100%'
        ..style.height = 'auto'
        ..style.padding = '8px 0'
        ..style.margin = '0'
        ..style.boxSizing = 'border-box'
        ..style.fontFamily =
            "'Inter','Segoe UI',-apple-system,BlinkMacSystemFont,sans-serif"
        ..style.fontSize = '16px'
        ..style.lineHeight = '1.85'
        ..style.color = '#1e293b'
        ..style.overflow = 'visible'
        ..style.letterSpacing = '0.01em'
        ..style.wordBreak = 'break-word';
      // Use trusted sanitizer to allow img src attributes with http:// URLs
      div.setInnerHtml(widget.html, treeSanitizer: dom.NodeTreeSanitizer.trusted);
      _contentDiv = div;

      wrapper.append(div);

      // Measure content height after render
      Future.delayed(const Duration(milliseconds: 100), () => _measureHeight());
      Future.delayed(const Duration(milliseconds: 500), () => _measureHeight());
      Future.delayed(const Duration(milliseconds: 1500), () => _measureHeight());

      return wrapper;
    });
  }

  void _measureHeight() {
    if (_contentDiv == null || !mounted) return;
    final h = _contentDiv!.scrollHeight.toDouble();
    if (h > 0 && (h - _measuredHeight).abs() > 5) {
      setState(() => _measuredHeight = h + 32);
    }
  }

  @override
  void didUpdateWidget(covariant HtmlContentView old) {
    super.didUpdateWidget(old);
    if (old.html != widget.html) {
      if (_contentDiv != null) {
        _contentDiv!.setInnerHtml(widget.html, treeSanitizer: dom.NodeTreeSanitizer.trusted);
        Future.delayed(const Duration(milliseconds: 100), () => _measureHeight());
        Future.delayed(const Duration(milliseconds: 500), () => _measureHeight());
      } else {
        // Re-register view with new content
        setState(() {
          _registerView();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = _measuredHeight < (widget.minHeight ?? 100) ? (widget.minHeight ?? 100) : _measuredHeight;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Constants: Color Palette & CSS
// ══════════════════════════════════════════════════════════

const _editorColors = [
  '#000000', '#374151', '#6B7280', '#9CA3AF', '#D1D5DB', '#FFFFFF',
  '#DC2626', '#EA580C', '#D97706', '#CA8A04', '#65A30D', '#16A34A',
  '#0D9488', '#0891B2', '#0284C7', '#2563EB', '#4F46E5', '#6366F1',
  '#7C3AED', '#9333EA', '#C026D3', '#DB2777', '#E11D48', '#F43F5E',
];

const _editorCss = '''
  .rich-editor-content h1 { font-size: 2em; font-weight: 700; margin: 0.5em 0; color: #0f172a; line-height: 1.3; }
  .rich-editor-content h2 { font-size: 1.5em; font-weight: 700; margin: 0.5em 0; color: #1e293b; line-height: 1.3; }
  .rich-editor-content h3 { font-size: 1.25em; font-weight: 600; margin: 0.5em 0; color: #334155; line-height: 1.4; }
  .rich-editor-content h4 { font-size: 1.1em; font-weight: 600; margin: 0.5em 0; color: #475569; line-height: 1.4; }
  .rich-editor-content p { margin: 0.4em 0; }
  .rich-editor-content ul, .rich-editor-content ol { padding-left: 1.5em; margin: 0.5em 0; }
  .rich-editor-content li { margin: 0.2em 0; }
  .rich-editor-content blockquote {
    border-left: 4px solid #6366f1;
    margin: 1em 0;
    padding: 0.75em 1.25em;
    background: #f8fafc;
    color: #475569;
    border-radius: 0 8px 8px 0;
    font-style: italic;
  }
  .rich-editor-content pre {
    background: #1e293b;
    color: #e2e8f0;
    padding: 1em 1.25em;
    border-radius: 8px;
    font-family: 'Fira Code','Consolas','Monaco',monospace;
    font-size: 0.9em;
    overflow-x: auto;
    margin: 0.75em 0;
    line-height: 1.6;
  }
  .rich-editor-content code {
    background: #f1f5f9;
    padding: 0.15em 0.4em;
    border-radius: 4px;
    font-family: 'Fira Code','Consolas',monospace;
    font-size: 0.9em;
    color: #6366f1;
  }
  .rich-editor-content pre code { background:transparent; padding:0; color:inherit; font-size:inherit; }
  .rich-editor-content a { color: #6366f1; text-decoration: underline; cursor: pointer; }
  .rich-editor-content a:hover { color: #4f46e5; }
  .rich-editor-content img { max-width: 100%; border-radius: 8px; margin: 0.75em 0; display: block; cursor: pointer; transition: outline 0.15s, box-shadow 0.15s; }
  .rich-editor-content img:hover { outline: 3px solid #818cf8; outline-offset: 2px; box-shadow: 0 2px 8px rgba(99,102,241,0.15); }
  .rich-editor-content table { border-collapse: collapse; width: 100%; margin: 1em 0; border-radius: 8px; overflow: hidden; box-shadow: 0 1px 4px rgba(0,0,0,0.06); }
  .rich-editor-content th, .rich-editor-content td {
    border: 1px solid #e2e8f0;
    padding: 10px 14px;
    text-align: left;
    min-width: 50px;
    transition: background 0.15s, outline 0.15s;
  }
  .rich-editor-content th { background: linear-gradient(135deg, #f1f5f9, #e8ecf1); font-weight: 600; color: #334155; }
  .rich-editor-content td:hover, .rich-editor-content th:hover { background: #eef2ff; outline: 2px solid #818cf8; outline-offset: -2px; cursor: cell; }
  .rich-editor-content tr:hover td { background: #f8faff; }
  .rich-editor-content iframe { border-radius: 12px; }
  .rich-editor-content div[contenteditable="false"] { border-radius: 12px; overflow: hidden; box-shadow: 0 4px 16px rgba(0,0,0,0.08); margin: 16px 0; }
  .rich-editor-content hr { border: none; border-top: 2px solid #e2e8f0; margin: 1.5em 0; }
  .rich-editor-content:empty:before {
    content: attr(data-placeholder);
    color: #94a3b8;
    pointer-events: none;
    position: absolute;
  }
  .rich-editor-content strong { font-weight: 700; }
  .rich-editor-content em { font-style: italic; }
  .rich-editor-content u { text-decoration: underline; }
  .rich-editor-content s, .rich-editor-content strike { text-decoration: line-through; }
  .rich-editor-content mark { background: #fef08a; padding: 0 2px; border-radius: 2px; }
''';

const _contentViewCss = '''
  .html-content-view { max-width: 100%; }
  .html-content-view h1 { font-size: 2.2em; font-weight: 800; margin: 0.8em 0 0.4em; color: #0f172a; line-height: 1.25; letter-spacing: -0.02em; }
  .html-content-view h2 { font-size: 1.7em; font-weight: 700; margin: 0.7em 0 0.4em; color: #1e293b; line-height: 1.3; letter-spacing: -0.01em; border-bottom: 2px solid #f1f5f9; padding-bottom: 0.3em; }
  .html-content-view h3 { font-size: 1.35em; font-weight: 600; margin: 0.6em 0 0.3em; color: #334155; line-height: 1.35; }
  .html-content-view h4 { font-size: 1.15em; font-weight: 600; margin: 0.5em 0 0.3em; color: #475569; line-height: 1.4; }
  .html-content-view p { margin: 0.6em 0; font-size: 1em; }
  .html-content-view ul, .html-content-view ol { padding-left: 1.8em; margin: 0.6em 0; }
  .html-content-view li { margin: 0.35em 0; }
  .html-content-view blockquote {
    border-left: 4px solid #6366f1;
    margin: 1.2em 0;
    padding: 1em 1.5em;
    background: linear-gradient(135deg, #f8fafc, #eef2ff);
    color: #475569;
    border-radius: 0 10px 10px 0;
    font-style: italic;
    font-size: 1.05em;
    line-height: 1.7;
  }
  .html-content-view pre {
    background: #1e293b;
    color: #e2e8f0;
    padding: 1.2em 1.4em;
    border-radius: 10px;
    font-family: 'Fira Code', 'Cascadia Code', monospace;
    font-size: 0.9em;
    overflow-x: auto;
    line-height: 1.7;
    margin: 1em 0;
  }
  .html-content-view code {
    background: #f1f5f9;
    padding: 0.2em 0.5em;
    border-radius: 5px;
    font-family: 'Fira Code', 'Cascadia Code', monospace;
    font-size: 0.88em;
    color: #6366f1;
  }
  .html-content-view pre code { background:transparent; padding:0; color:inherit; }
  .html-content-view a { color: #6366f1; text-decoration: underline; text-underline-offset: 3px; }
  .html-content-view a:hover { color: #4f46e5; }
  .html-content-view img {
    max-width: 100%;
    border-radius: 10px;
    margin: 0.8em 0;
    box-shadow: 0 2px 12px rgba(0,0,0,0.08);
  }
  .html-content-view table {
    border-collapse: collapse;
    width: 100%;
    margin: 1.2em 0;
    border-radius: 10px;
    overflow: hidden;
    box-shadow: 0 1px 6px rgba(0,0,0,0.07);
    font-size: 0.95em;
  }
  .html-content-view th, .html-content-view td {
    border: 1px solid #e2e8f0;
    padding: 12px 16px;
    text-align: left;
  }
  .html-content-view th { background: linear-gradient(135deg, #f1f5f9, #e8ecf1); font-weight: 600; color: #334155; }
  .html-content-view tr:nth-child(even) td { background: #fafbfc; }
  .html-content-view tr:hover td { background: #f0f4ff; }
  .html-content-view iframe {
    border-radius: 12px;
    max-width: 100%;
    margin: 0.8em 0;
    box-shadow: 0 4px 16px rgba(0,0,0,0.1);
  }
  .html-content-view div[contenteditable="false"] { border-radius: 12px; overflow: hidden; }
  .html-content-view hr {
    border: none;
    border-top: 2px solid #e2e8f0;
    margin: 2em 0;
  }
  .html-content-view strong { font-weight: 700; }
  .html-content-view em { font-style: italic; }

  /* Smooth scrollbar */
  .html-content-view::-webkit-scrollbar { width: 6px; }
  .html-content-view::-webkit-scrollbar-track { background: transparent; }
  .html-content-view::-webkit-scrollbar-thumb { background: #cbd5e1; border-radius: 3px; }
  .html-content-view::-webkit-scrollbar-thumb:hover { background: #94a3b8; }
''';
