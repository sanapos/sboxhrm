import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../services/api_service.dart';
import '../../utils/pos_print_template_defaults.dart';
import '../../utils/pos_print_template_renderer.dart';
import 'pos_commercial_word_stub.dart'
    if (dart.library.js_interop) 'pos_commercial_word_web.dart';
import 'pos_html_preview_stub.dart';

/// Soạn mẫu A4 kiểu Word: ribbon (font, cỡ, đậm/nghiêng, căn, màu, bảng, undo)
/// + trang giấy A4 contenteditable + tab «Xem trước» render HTML thật.
///
/// Trang giấy cuộn theo chiều dọc, có zoom và chế độ toàn màn hình — không
/// ép AspectRatio vừa khung nhỏ (sẽ làm chữ nhỏ như tem).
class PosCommercialA4Editor extends StatefulWidget {
  const PosCommercialA4Editor({
    super.key,
    required this.html,
    required this.documentType,
    required this.onChanged,
    this.immersive = false,
    this.compact = false,
    this.initialTab = 0,
    this.initialZoom = 1,
    this.paperSize = PosPrintPaperSizes.a4,
    this.onPageSetupChanged,
    this.snapshot = false,
  });

  final String html;
  final String documentType;
  final ValueChanged<String> onChanged;
  final String paperSize;
  final ValueChanged<PosCommercialPageSetup>? onPageSetupChanged;

  /// Mở trong route toàn màn hình (ẩn hướng dẫn, hiện nút Thu nhỏ).
  final bool immersive;

  /// Mobile: ẩn ribbon, chỉ thanh Soạn/Xem + công cụ trong sheet.
  final bool compact;

  /// 0 = Soạn thảo, 1 = Xem trước.
  final int initialTab;

  /// 0 = vừa khung (fit-width); còn lại là hệ số (0.5–2.0).
  final double initialZoom;

  /// Sửa một chứng từ đã render: không đổ dòng mẫu, không đụng mẫu chung.
  final bool snapshot;

  @override
  State<PosCommercialA4Editor> createState() => PosCommercialA4EditorState();
}

class PosCommercialA4EditorState extends State<PosCommercialA4Editor> {
  final _api = ApiService();
  final _surfaceKey = GlobalKey<PosCommercialWordSurfaceState>();
  late String _html;
  late int _tab;
  late double _zoom; // 0 = vừa khung
  late PosCommercialPageSetup _setup;
  Map<String, dynamic>? _commercialProfile;
  String _fontFamily = "'Times New Roman', Times, serif";
  String _fontSize = '13';
  String _lineHeight = '1.15';
  bool _zoomOpen = false;
  bool _marginOpen = false;
  bool _htmlEditorOpen = false;
  final _pageScroll = ScrollController();
  double _contentH = 0;

  static const _fonts = <(String, String)>[
    ('Times', "'Times New Roman', Times, serif"),
    ('Arial', 'Arial, Helvetica, sans-serif'),
    ('Calibri', 'Calibri, Segoe UI, sans-serif'),
    ('Roboto', 'Roboto, sans-serif'),
    ('Courier', "'Courier New', Courier, monospace"),
  ];

  static const _sizes = <String>['10', '11', '12', '13', '14', '16', '18', '20', '24', '28', '36'];
  static const _lineHeights = <(String, String)>[
    ('1.0', '1'),
    ('1.15', '1.15'),
    ('1.5', '1.5'),
    ('2.0', '2'),
  ];

  static const _fontColors = <Color>[
    Colors.black,
    Color(0xFFDC2626),
    Color(0xFF16A34A),
    Color(0xFF2563EB),
    Color(0xFFF59E0B),
    Color(0xFF6B7280),
  ];

  @override
  void initState() {
    super.initState();
    _html = widget.html;
    _tab = widget.initialTab.clamp(0, 1);
    _zoom = widget.initialZoom;
    _setup = PosCommercialPageSetup.parse(
      widget.html,
      fallbackPaper: widget.paperSize,
    );
    _loadCommercialProfile();
  }

  Future<void> _loadCommercialProfile() async {
    final res = await _api.getPosCommercialProfile();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _commercialProfile =
            Map<String, dynamic>.from(res['data'] as Map);
      });
    }
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PosCommercialA4Editor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html && widget.html != _html) {
      _html = widget.html;
      _setup = PosCommercialPageSetup.parse(
        widget.html,
        fallbackPaper: widget.paperSize,
      );
    } else if (oldWidget.paperSize != widget.paperSize &&
        widget.paperSize != _setup.paperSize) {
      _setup = _setup.copyWith(
        paperSize: PosPrintPaperSizes.normalizeCommercialPaper(widget.paperSize),
      );
    }
  }

  void _emit(String html) {
    _html = html;
    widget.onChanged(html);
    // Không gọi setState để tránh làm mất caret trong iframe.
  }

  Future<String> flushHtml() async {
    await _surfaceKey.currentState?.flush();
    return _html;
  }

  void _applySetup(PosCommercialPageSetup next) {
    _setup = next;
    final html = next.applyToHtml(_html);
    _emit(html);
    widget.onPageSetupChanged?.call(next);
    setState(() {});
  }

  void _cmd(String cmd, [String? value]) {
    _surfaceKey.currentState?.exec(cmd, value);
  }

  void _insert(String html) {
    _surfaceKey.currentState?.insertHtml(html);
  }

  void _script(String js) {
    _surfaceKey.currentState?.runScript(js);
  }

  void _onPageWheel(double dy) {
    if (!_pageScroll.hasClients) return;
    final pos = _pageScroll.position;
    _pageScroll.jumpTo((pos.pixels + dy).clamp(0.0, pos.maxScrollExtent));
  }

  Future<void> _switchTab(int tab) async {
    await _surfaceKey.currentState?.flush();
    if (!mounted) return;
    setState(() => _tab = tab);
  }

  String get _previewHtml => widget.snapshot
      ? _html
      : renderPosPrintTemplateHtml(
        _html,
        data: posPrintSampleData(
          documentType: widget.documentType,
          commercialProfile: _commercialProfile,
        ),
        lineItems: posPrintSampleLines(
          count: PosPrintDocumentTypes.isCommercial(widget.documentType) ? 8 : 2,
        ),
        wrapDocument: false,
        paperSize: _setup.paperSize,
      );

  bool get _compact {
    if (widget.compact) return true;
    return MediaQuery.sizeOf(context).width < 800;
  }

  @override
  Widget build(BuildContext context) {
    if (_compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _compactBar(),
          if (_zoomOpen) _zoomSlider(),
          Expanded(child: _paperCanvas(preview: _tab == 1)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.immersive) _immersiveBar() else _hintRow(),
        const SizedBox(height: 6),
        _ribbon(),
        const SizedBox(height: 6),
        _tokenBar(),
        const SizedBox(height: 6),
        _modeAndZoomRow(),
        if (_zoomOpen) _zoomSlider(),
        const SizedBox(height: 6),
        _pageSetupPanel(compact: true),
        const SizedBox(height: 8),
        Expanded(child: _paperCanvas(preview: _tab == 1)),
      ],
    );
  }

  Widget _compactBar() {
    Widget modeBtn(int tab, IconData icon, String label) {
      final on = _tab == tab;
      return Material(
        color: on ? const Color(0xFF2563EB) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _switchTab(tab),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: on ? Colors.white : const Color(0xFF374151)),
                const SizedBox(width: 6),
                Text(
                  tr(label),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: on ? Colors.white : const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
        child: Row(
          children: [
            if (widget.immersive)
              IconButton(
                tooltip: tr('Thu nhỏ'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 22),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            Expanded(child: modeBtn(0, Icons.edit_outlined, 'Soạn')),
            const SizedBox(width: 8),
            Expanded(child: modeBtn(1, Icons.visibility_outlined, 'Xem')),
            IconButton(
              tooltip: tr('Thu phóng'),
              onPressed: () => setState(() => _zoomOpen = !_zoomOpen),
              icon: Icon(
                Icons.zoom_in,
                size: 24,
                color: _zoomOpen ? const Color(0xFF2563EB) : null,
              ),
            ),
            IconButton(
              tooltip: tr('Khổ giấy & lề'),
              visualDensity: VisualDensity.compact,
              onPressed: _openToolsSheet,
              icon: const Icon(Icons.tune, size: 22),
            ),
            if (!widget.immersive)
              IconButton(
                tooltip: tr('Toàn màn hình'),
                visualDensity: VisualDensity.compact,
                onPressed: _openFullscreen,
                icon: const Icon(Icons.fullscreen, size: 22),
              ),
          ],
        ),
      ),
    );
  }

  double get _viewZoom => _zoom <= 0 ? 1 : _zoom.clamp(0.25, 2);

  Widget _zoomSlider() {
    final zoom = _viewZoom;
    final label = '${(zoom * 100).round()}%';
    return Material(
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('100% — đúng khổ A4'),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _zoom = 1),
              icon: const Icon(Icons.fit_screen, size: 20),
            ),
            Expanded(
              child: Slider(
                min: 0.25,
                max: 2,
                divisions: 7,
                value: zoom,
                label: label,
                onChanged: (v) => setState(() => _zoom = v),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tokenWrap() {
    final chips = <(String, String)>[
      ...PosPrintTokens.store,
      ...PosPrintTokens.customer,
      ...PosPrintTokens.order,
      ...PosPrintTokens.commercial,
      ...PosPrintTokens.totals.take(8),
      ('Chieu_Dai', 'Cột dài'),
      ('Chieu_Rong', 'Cột rộng'),
      ('Chieu_Cao', 'Cột cao'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final t in chips)
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(t.$2, style: const TextStyle(fontSize: 11)),
              onPressed: () {
                _insert('{${t.$1}}');
                if (_tab != 0) setState(() => _tab = 0);
              },
            ),
        ],
      ),
    );
  }

  Future<void> _openToolsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr('Định dạng & chèn trường'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(tr('Xong')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _pageSetupPanel(),
                const SizedBox(height: 12),
                _ribbon(),
                const SizedBox(height: 10),
                _tokenWrap(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageSetupPanel({bool compact = false}) {
    Widget mmSlider(String label, double value, ValueChanged<double> onMm) {
      return Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(tr(label), style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Slider(
              min: PosCommercialPageSetup.minMm,
              max: PosCommercialPageSetup.maxMm,
              divisions: 25,
              value: value.clamp(
                PosCommercialPageSetup.minMm,
                PosCommercialPageSetup.maxMm,
              ),
              label: '${value.round()} mm',
              onChanged: onMm,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${value.round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
    }

    return Material(
      color: const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, compact ? 6 : 10, 10, compact ? 4 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  tr('Khổ giấy'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    ButtonSegment(value: PosPrintPaperSizes.a4, label: Text(tr('A4'))),
                    ButtonSegment(value: PosPrintPaperSizes.a5, label: Text(tr('A5'))),
                  ],
                  selected: {_setup.paperSize},
                  onSelectionChanged: (s) => _applySetup(
                    _setup.copyWith(paperSize: s.first),
                  ),
                ),
            TextButton.icon(
              onPressed: compact
                  ? () => setState(() => _marginOpen = !_marginOpen)
                  : () => _applySetup(
                        PosCommercialPageSetup(paperSize: _setup.paperSize),
                      ),
              icon: Icon(
                compact
                    ? (_marginOpen ? Icons.expand_less : Icons.expand_more)
                    : Icons.space_bar,
                size: 18,
              ),
              label: Text(
                compact
                    ? tr('Lề ${_setup.topMm.round()}·${_setup.rightMm.round()}·${_setup.bottomMm.round()}·${_setup.leftMm.round()} mm')
                    : tr('Lề 12mm'),
              ),
            ),
          ],
        ),
        if (!compact || _marginOpen) ...[
            const SizedBox(height: 4),
            Text(
              tr('Lề so với nội dung (mm)'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            mmSlider('Trên', _setup.topMm, (v) => _applySetup(_setup.copyWith(topMm: v))),
            mmSlider('Phải', _setup.rightMm, (v) => _applySetup(_setup.copyWith(rightMm: v))),
            mmSlider('Dưới', _setup.bottomMm, (v) => _applySetup(_setup.copyWith(bottomMm: v))),
            mmSlider('Trái', _setup.leftMm, (v) => _applySetup(_setup.copyWith(leftMm: v))),
            if (compact)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _applySetup(
                    PosCommercialPageSetup(paperSize: _setup.paperSize),
                  ),
                  child: Text(tr('Đặt lại 12mm')),
                ),
              ),
        ],
          ],
        ),
      ),
    );
  }

  Widget _hintRow() {
    return Text(
      tr(widget.snapshot
          ? 'Sửa chữ của riêng chứng từ này. Mẫu chung và chứng từ khác không đổi.'
          : 'Chạm vào chữ trên trang để sửa như Word. Bôi đen rồi chọn đậm / font / màu.'),
      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
    );
  }

  Widget _immersiveBar() {
    return Material(
      color: const Color(0xFF111827),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('Thu nhỏ'),
              color: Colors.white,
              icon: const Icon(Icons.fullscreen_exit),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                tr(_tab == 0
                    ? 'Soạn thảo toàn màn hình — cuộn để xem hết trang'
                    : 'Xem trước A4 toàn màn hình'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Text(
              tr('Đóng để lưu mẫu'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeAndZoomRow() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(
              value: 0,
              label: Text(tr('Soạn thảo')),
              icon: const Icon(Icons.edit_document, size: 18),
            ),
            ButtonSegment(
              value: 1,
              label: Text(tr('Xem trước')),
              icon: const Icon(Icons.visibility_outlined, size: 18),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => _switchTab(s.first),
        ),
        IconButton.filledTonal(
          tooltip: tr('Thu phóng'),
          onPressed: () => setState(() => _zoomOpen = !_zoomOpen),
          icon: Icon(
            Icons.zoom_in,
            color: _zoomOpen ? const Color(0xFF2563EB) : null,
          ),
        ),
        if (!widget.immersive)
          FilledButton.icon(
            onPressed: _openFullscreen,
            icon: const Icon(Icons.fullscreen, size: 18),
            label: Text(tr('Toàn màn hình')),
          )
        else
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.fullscreen_exit, size: 18),
            label: Text(tr('Thu nhỏ')),
          ),
      ],
    );
  }

  Future<void> _openFullscreen() async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: const Color(0xFFE5E7EB),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: PosCommercialA4Editor(
                html: _html,
                documentType: widget.documentType,
                onChanged: _emit,
                immersive: true,
                compact: _compact,
                initialTab: _tab,
                initialZoom: _zoom,
                paperSize: _setup.paperSize,
                onPageSetupChanged: (s) {
                  _setup = s;
                  widget.onPageSetupChanged?.call(s);
                },
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _ribbon() {
    Widget btn(IconData icon, String tip, VoidCallback onTap) {
      return Tooltip(
        message: tr(tip),
        child: IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(icon, size: 20),
          onPressed: onTap,
        ),
      );
    }

    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          runSpacing: 2,
          children: [
            SizedBox(
              width: 132,
              child: DropdownButtonFormField<String>(
                value: _fontFamily,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6),
                  border: OutlineInputBorder(),
                ),
                items: _fonts
                    .map((e) => DropdownMenuItem(
                          value: e.$2,
                          child: Text(e.$1,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: e.$2.split(',').first)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _fontFamily = v);
                  _cmd('fontName', v);
                },
              ),
            ),
            SizedBox(
              width: 64,
              child: DropdownButtonFormField<String>(
                value: _fontSize,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6),
                  border: OutlineInputBorder(),
                ),
                items: _sizes
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e, style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _fontSize = v);
                  _script('sboxFontPt($v)');
                },
              ),
            ),
            const VerticalDivider(width: 6),
            btn(Icons.undo, 'Hoàn tác', () => _script('sboxUndo()')),
            btn(Icons.redo, 'Làm lại', () => _script('sboxRedo()')),
            btn(Icons.code, 'HTML', _editHtml),
            const VerticalDivider(width: 6),
            btn(Icons.format_bold, 'Đậm', () => _cmd('bold')),
            btn(Icons.format_italic, 'Nghiêng', () => _cmd('italic')),
            btn(Icons.format_underline, 'Gạch dưới', () => _cmd('underline')),
            btn(Icons.format_strikethrough, 'Gạch ngang',
                () => _cmd('strikeThrough')),
            const VerticalDivider(width: 6),
            btn(Icons.format_align_left, 'Căn trái',
                () => _cmd('justifyLeft')),
            btn(Icons.format_align_center, 'Căn giữa',
                () => _cmd('justifyCenter')),
            btn(Icons.format_align_right, 'Căn phải',
                () => _cmd('justifyRight')),
            btn(Icons.format_align_justify, 'Căn đều',
                () => _cmd('justifyFull')),
            const VerticalDivider(width: 6),
            btn(Icons.format_indent_decrease, 'Giảm thụt',
                () => _cmd('outdent')),
            btn(Icons.format_indent_increase, 'Tăng thụt',
                () => _cmd('indent')),
            const VerticalDivider(width: 6),
            btn(Icons.format_list_bulleted, 'Danh sách',
                () => _cmd('insertUnorderedList')),
            btn(Icons.format_list_numbered, 'Đánh số',
                () => _cmd('insertOrderedList')),
            _colorButton(),
            _highlightButton(),
            const VerticalDivider(width: 6),
            btn(Icons.title, 'Tiêu đề', () => _cmd('formatBlock', 'h2')),
            btn(Icons.horizontal_rule, 'Đường kẻ ngang',
                () => _cmd('insertHorizontalRule')),
            const VerticalDivider(width: 6),
            TextButton.icon(
              onPressed: _insertItemsTable,
              icon: const Icon(Icons.table_view_outlined, size: 18),
              label: Text(tr('Chèn bảng hàng')),
            ),
            TextButton.icon(
              onPressed: () => _showTableDialog(),
              icon: const Icon(Icons.grid_on, size: 18),
              label: Text(tr('Chèn bảng')),
            ),
            TextButton.icon(
              onPressed: _insertSignatureBlock,
              icon: const Icon(Icons.draw_outlined, size: 18),
              label: Text(tr('Khối ký tên')),
            ),
            const VerticalDivider(width: 6),
            SizedBox(
              width: 88,
              child: DropdownButtonFormField<String>(
                value: _lineHeight,
                isDense: true,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Dãn dòng',
                  contentPadding: EdgeInsets.symmetric(horizontal: 6),
                  border: OutlineInputBorder(),
                ),
                items: _lineHeights
                    .map((e) => DropdownMenuItem(value: e.$2, child: Text(e.$1)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _lineHeight = v);
                  _script('sboxStyle("lineHeight","$v")');
                },
              ),
            ),
            btn(Icons.vertical_align_top, 'Thêm khoảng trước đoạn',
                () => _script('sboxStyle("marginTop","10px")')),
            btn(Icons.vertical_align_bottom, 'Thêm khoảng sau đoạn',
                () => _script('sboxStyle("marginBottom","10px")')),
            const VerticalDivider(width: 6),
            btn(Icons.image_outlined, 'Chèn ảnh / logo', _insertImage),
            btn(Icons.photo_size_select_small, 'Thu nhỏ ảnh',
                () => _script('sboxImageWidth(-24)')),
            btn(Icons.photo_size_select_large, 'Phóng ảnh',
                () => _script('sboxImageWidth(24)')),
            btn(Icons.format_align_left, 'Ảnh căn trái',
                () => _script('sboxImageAlign("left")')),
            btn(Icons.format_align_center, 'Ảnh căn giữa',
                () => _script('sboxImageAlign("center")')),
            btn(Icons.format_align_right, 'Ảnh căn phải',
                () => _script('sboxImageAlign("right")')),
            const VerticalDivider(width: 6),
            btn(Icons.table_rows, 'Thêm dòng bảng',
                () => _script('sboxTableRow(true)')),
            btn(Icons.delete_outline, 'Xóa dòng bảng',
                () => _script('sboxTableRow(false)')),
            btn(Icons.call_merge, 'Gộp ô sang phải', () => _script('sboxMerge()')),
            btn(Icons.arrow_back, 'Đẩy khối sang trái',
                () => _script('sboxNudgeBlock(-12)')),
            btn(Icons.arrow_forward, 'Đẩy khối sang phải',
                () => _script('sboxNudgeBlock(12)')),
          ],
        ),
      ),
    );
  }

  Widget _colorButton() {
    return PopupMenuButton<Color>(
      tooltip: tr('Màu chữ'),
      icon: const Icon(Icons.format_color_text, size: 20),
      itemBuilder: (_) => [
        for (final c in _fontColors)
          PopupMenuItem(
            value: c,
            child: Row(children: [
              Container(width: 18, height: 18, color: c),
              const SizedBox(width: 8),
              Text(_hex(c)),
            ]),
          ),
      ],
      onSelected: (c) => _cmd('foreColor', _hex(c)),
    );
  }

  Widget _highlightButton() {
    return PopupMenuButton<Color>(
      tooltip: tr('Tô nền'),
      icon: const Icon(Icons.border_color_outlined, size: 20),
      itemBuilder: (_) => [
        for (final c in [
          const Color(0xFFFDE68A),
          const Color(0xFFBBF7D0),
          const Color(0xFFBFDBFE),
          const Color(0xFFFECACA),
          Colors.white,
        ])
          PopupMenuItem(
            value: c,
            child: Row(children: [
              Container(width: 18, height: 18, color: c),
              const SizedBox(width: 8),
              Text(_hex(c)),
            ]),
          ),
      ],
      onSelected: (c) {
        _cmd('hiliteColor', _hex(c));
        _cmd('backColor', _hex(c));
      },
    );
  }

  String _hex(Color c) {
    int ch(double v) => (v * 255.0).round().clamp(0, 255);
    return '#'
        '${ch(c.r).toRadixString(16).padLeft(2, '0')}'
        '${ch(c.g).toRadixString(16).padLeft(2, '0')}'
        '${ch(c.b).toRadixString(16).padLeft(2, '0')}';
  }

  void _insertImage() {
    _surfaceKey.currentState?.rememberCaret();
    pickTemplateImage((src) {
      _surfaceKey.currentState?.insertImageDataUrl(src);
    });
  }

  String _htmlForAi(String html) {
    if (html.contains('THAM SỐ ĐỘNG')) return html;
    final lines = <String>[
      'THAM SỐ ĐỘNG — giữ nguyên chữ trong ngoặc nhọn {Ten_Tham_So}.',
      'Có thể đổi bố cục, cỡ chữ, căn lề. Không đổi tên tham số và không xóa <!--BEGIN_ITEMS--> <!--END_ITEMS-->.',
      for (final t in _allTokens) '{${t.$1}} = ${t.$2}',
    ];
    return '<!--\n${lines.join('\n')}\n-->\n$html';
  }

  void _insertItemsTable() {
    _insert(
      '<table style="width:100%;border-collapse:collapse;table-layout:fixed;margin:8px 0;font-size:11px">'
      '<colgroup><col width="46"/><col width="216"/><col width="62"/><col width="62"/><col width="108"/><col width="108"/><col width="62"/><col width="108"/></colgroup>'
      '<thead><tr style="background:#f3f4f6">'
      '<th style="width:6%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">STT</th>'
      '<th style="width:28%;border:1px solid #111;padding:4px 4px;text-align:left">Tên hàng</th>'
      '<th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">ĐVT</th>'
      '<th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">SL</th>'
      '<th style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right">Đơn giá</th>'
      '<th style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right">Thành tiền</th>'
      '<th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">BH</th>'
      '<th style="width:14%;border:1px solid #111;padding:4px 2px;text-align:center">Ảnh</th>'
      '</tr></thead>'
      '<tbody><!--BEGIN_ITEMS-->'
      '<tr>'
      '<td style="width:6%;border:1px solid #111;padding:4px 2px;text-align:center">{STT}</td>'
      '<td style="width:28%;border:1px solid #111;padding:4px 4px">{Ten_Hang_Hoa}</td>'
      '<td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center">{Don_Vi_Tinh}</td>'
      '<td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center">{So_Luong}</td>'
      '<td style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right">{Don_Gia}</td>'
      '<td style="width:14%;border:1px solid #111;padding:4px 3px;text-align:right">{Thanh_Tien}</td>'
      '<td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center">{Bao_Hanh}</td>'
      '<td style="width:14%;border:1px solid #111;padding:3px;text-align:center">{Hinh_Anh}</td>'
      '</tr><!--END_ITEMS--></tbody></table>',
    );
  }

  void _insertSignatureBlock() {
    _insert(
      '<table style="width:100%;margin-top:24px"><tr>'
      '<td style="width:50%;text-align:center;vertical-align:top">'
      '<b>ĐẠI DIỆN BÊN A</b><br/><i>(Ký, ghi rõ họ tên)</i>'
      '<div style="height:60px"></div>'
      '{Khach_Hang}</td>'
      '<td style="width:50%;text-align:center;vertical-align:top">'
      '<b>ĐẠI DIỆN BÊN B</b><br/><i>(Ký, ghi rõ họ tên)</i>'
      '<div style="height:60px"></div>'
      '{Ten_Cua_Hang}</td>'
      '</tr></table>',
    );
  }

  Future<void> _showTableDialog() async {
    var rows = 3;
    var cols = 3;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('Chèn bảng')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Text(tr('Hàng: $rows')),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 12,
                  divisions: 11,
                  value: rows.toDouble(),
                  onChanged: (v) => setDlg(() => rows = v.round()),
                ),
              ),
            ]),
            Row(children: [
              Text(tr('Cột: $cols')),
              Expanded(
                child: Slider(
                  min: 1,
                  max: 8,
                  divisions: 7,
                  value: cols.toDouble(),
                  onChanged: (v) => setDlg(() => cols = v.round()),
                ),
              ),
            ]),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Hủy'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Chèn'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final buf = StringBuffer(
        '<table style="width:100%;border-collapse:collapse;margin:6px 0">');
    for (var r = 0; r < rows; r++) {
      buf.write('<tr>');
      for (var c = 0; c < cols; c++) {
        buf.write(
            '<td style="border:1px solid #000;padding:4px 6px">&nbsp;</td>');
      }
      buf.write('</tr>');
    }
    buf.write('</table>');
    _insert(buf.toString());
  }

  List<(String, String)> get _allTokens => [
        ...PosPrintTokens.store,
        ...PosPrintTokens.customer,
        ...PosPrintTokens.order,
        ...PosPrintTokens.commercial,
        ...PosPrintTokens.line,
        ...PosPrintTokens.totals,
      ];

  Widget _tokenBar() {
    return Autocomplete<(String, String)>(
      displayStringForOption: (t) => t.$2,
      optionsBuilder: (text) {
        final q = text.text.trim().toLowerCase();
        return _allTokens.where((t) {
          if (q.isEmpty) return true;
          return t.$1.toLowerCase().contains(q) ||
              t.$2.toLowerCase().contains(q);
        });
      },
      onSelected: (t) => _insert('{${t.$1}}'),
      fieldViewBuilder: (context, controller, focus, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focus,
          decoration: InputDecoration(
            isDense: true,
            hintText: tr('Tìm tham số để chèn…'),
            prefixIcon: const Icon(Icons.search, size: 18),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
          onSubmitted: (_) => onSubmit(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final t in options)
                    ListTile(
                      dense: true,
                      title: Text(t.$2),
                      subtitle: Text('{${t.$1}}'),
                      onTap: () => onSelected(t),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _editHtml() async {
    await _surfaceKey.currentState?.flush();
    if (!mounted) return;
    setState(() => _htmlEditorOpen = true);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final ctrl = TextEditingController(text: _htmlForAi(_html));
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('HTML mẫu in')),
        content: SizedBox(
          width: 760,
          height: 460,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontFamily: 'Consolas', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Ctrl+A rồi Ctrl+C để copy. Ctrl+V để dán.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: ctrl.text));
            },
            child: Text(tr('Sao chép')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Đóng')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Dán vào mẫu')),
          ),
        ],
      ),
    );
    final next = ctrl.text;
    ctrl.dispose();
    if (!mounted) return;
    setState(() => _htmlEditorOpen = false);
    if (ok == true) _emit(next);
  }

  Widget _paperCanvas({required bool preview}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = 20.0;
        final scale = _viewZoom;
        final paperW = _setup.cssWidth * scale;
        return ColoredBox(
          color: const Color(0xFFE5E7EB),
          child: Scrollbar(
            controller: _pageScroll,
            thumbVisibility: true,
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: SingleChildScrollView(
              controller: _pageScroll,
              padding: EdgeInsets.symmetric(vertical: pad),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minWidth: constraints.maxWidth - pad * 2),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _pageRuler(paperW),
                        if (preview && !_htmlEditorOpen)
                          buildPosA4ZoomedPage(_previewHtml, zoom: scale)
                        else
                          PosA4UniformScale(
                            scale: scale,
                            child: SizedBox(
                              width: _setup.cssWidth,
                              height: math.max(
                                _setup.cssHeight,
                                _contentH <= 0 ? _setup.cssHeight : _contentH,
                              ),
                              child: Material(
                                color: Colors.white,
                                elevation: 8,
                                shadowColor: Colors.black26,
                                child: _htmlEditorOpen
                                    ? const ColoredBox(color: Colors.white)
                                    : PosCommercialWordSurface(
                                        key: _surfaceKey,
                                        html: _html,
                                        editable: true,
                                        pageSetup: _setup,
                                        onChanged: _emit,
                                        onWheel: _onPageWheel,
                                        onContentHeight: (h) {
                                          if ((h - _contentH).abs() < 12) return;
                                          setState(() => _contentH = h);
                                        },
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pageRuler(double paperW) {
    final widthMm = _setup.isA5 ? 148.0 : 210.0;
    return SizedBox(
      width: paperW,
      height: 22,
      child: CustomPaint(
        painter: _RulerPainter(
          widthMm: widthMm,
          leftMm: _setup.leftMm,
          rightMm: _setup.rightMm,
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.widthMm,
    required this.leftMm,
    required this.rightMm,
  });

  final double widthMm;
  final double leftMm;
  final double rightMm;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRect(Offset.zero & size, bg);
    final pxPerMm = size.width / widthMm;
    final margin = Paint()..color = const Color(0xFFE2E8F0);
    canvas.drawRect(Rect.fromLTWH(0, 0, leftMm * pxPerMm, size.height), margin);
    final rightW = rightMm * pxPerMm;
    canvas.drawRect(
      Rect.fromLTWH(size.width - rightW, 0, rightW, size.height),
      margin,
    );
    final tick = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var mm = 0; mm <= widthMm; mm += 10) {
      final x = mm * pxPerMm;
      canvas.drawLine(Offset(x, 8), Offset(x, size.height), tick);
      tp.text = TextSpan(
        text: '$mm',
        style: const TextStyle(fontSize: 8, color: Color(0xFF334155)),
      );
      tp.layout();
      tp.paint(canvas, Offset(x + 2, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.leftMm != leftMm ||
      oldDelegate.rightMm != rightMm ||
      oldDelegate.widthMm != widthMm;
}
