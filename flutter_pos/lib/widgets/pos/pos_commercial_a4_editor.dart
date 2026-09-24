import 'package:flutter/material.dart';

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
    this.initialZoom = 0,
    this.paperSize = PosPrintPaperSizes.a4,
    this.onPageSetupChanged,
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

  @override
  State<PosCommercialA4Editor> createState() => _PosCommercialA4EditorState();
}

class _PosCommercialA4EditorState extends State<PosCommercialA4Editor> {
  final _api = ApiService();
  final _surfaceKey = GlobalKey<PosCommercialWordSurfaceState>();
  late String _html;
  late int _tab;
  late double _zoom; // 0 = vừa khung
  late PosCommercialPageSetup _setup;
  Map<String, dynamic>? _commercialProfile;
  String _fontFamily = "'Times New Roman', Times, serif";
  String _fontSize = '3'; // execCommand fontSize: 1..7
  bool _zoomOpen = false;
  bool _marginOpen = false;

  static const _fonts = <(String, String)>[
    ('Times', "'Times New Roman', Times, serif"),
    ('Arial', 'Arial, Helvetica, sans-serif'),
    ('Calibri', 'Calibri, Segoe UI, sans-serif'),
    ('Roboto', 'Roboto, sans-serif'),
    ('Courier', "'Courier New', Courier, monospace"),
  ];

  // execCommand('fontSize', 1..7) tương ứng ~10..36pt.
  static const _sizes = <(String, String)>[
    ('10', '1'),
    ('12', '2'),
    ('13', '3'),
    ('16', '4'),
    ('18', '5'),
    ('24', '6'),
    ('36', '7'),
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

  Future<void> _switchTab(int tab) async {
    await _surfaceKey.currentState?.flush();
    if (!mounted) return;
    setState(() => _tab = tab);
  }

  String get _previewHtml => renderPosPrintTemplateHtml(
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

  Widget _zoomSlider() {
    final label = _zoom <= 0 ? tr('Vừa rộng') : '${(_zoom * 100).round()}%';
    return Material(
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 8, 6),
        child: Row(
          children: [
            IconButton(
              tooltip: tr('Vừa rộng giấy'),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _zoom = 0),
              icon: const Icon(Icons.fit_screen, size: 20),
            ),
            Expanded(
              child: Slider(
                min: 0,
                max: 2,
                divisions: 20,
                value: _zoom <= 0 ? 0 : _zoom.clamp(0.2, 2),
                label: label,
                onChanged: (v) => setState(() => _zoom = v < 0.12 ? 0 : v),
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
      tr('Chạm vào chữ trên trang để sửa như Word. Bôi đen rồi chọn đậm / font / màu.'),
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
                          value: e.$2,
                          child: Text(e.$1,
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _fontSize = v);
                  _cmd('fontSize', v);
                },
              ),
            ),
            const VerticalDivider(width: 6),
            btn(Icons.undo, 'Hoàn tác', () => _cmd('undo')),
            btn(Icons.redo, 'Làm lại', () => _cmd('redo')),
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

  void _insertItemsTable() {
    _insert(
      '<table style="width:100%;border-collapse:collapse;table-layout:fixed;margin:8px 0;font-size:11px">'
      '<colgroup><col width="46"/><col width="293"/><col width="62"/><col width="62"/><col width="123"/><col width="123"/><col width="61"/></colgroup>'
      '<thead><tr style="background:#f3f4f6">'
      '<th style="width:6%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">STT</th>'
      '<th style="width:38%;border:1px solid #111;padding:4px 4px;text-align:left">Tên hàng</th>'
      '<th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">ĐVT</th>'
      '<th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">SL</th>'
      '<th style="width:16%;border:1px solid #111;padding:4px 3px;text-align:right;white-space:nowrap">Đơn giá</th>'
      '<th style="width:16%;border:1px solid #111;padding:4px 3px;text-align:right;white-space:nowrap">Thành tiền</th>'
      '<th style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center;white-space:nowrap">BH</th>'
      '</tr></thead>'
      '<tbody><!--BEGIN_ITEMS-->'
      '<tr>'
      '<td style="width:6%;border:1px solid #111;padding:4px 2px;text-align:center">{STT}</td>'
      '<td style="width:38%;border:1px solid #111;padding:4px 4px">{Ten_Hang_Hoa}</td>'
      '<td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center">{Don_Vi_Tinh}</td>'
      '<td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center">{So_Luong}</td>'
      '<td style="width:16%;border:1px solid #111;padding:4px 3px;text-align:right;white-space:nowrap">{Don_Gia}</td>'
      '<td style="width:16%;border:1px solid #111;padding:4px 3px;text-align:right;white-space:nowrap">{Thanh_Tien}</td>'
      '<td style="width:8%;border:1px solid #111;padding:4px 2px;text-align:center">{Bao_Hanh}</td>'
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

  Widget _tokenBar() {
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
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final t in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text(t.$2, style: const TextStyle(fontSize: 11)),
                onPressed: () => _insert('{${t.$1}}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paperCanvas({required bool preview}) {
    if (preview) {
      return buildPosA4ScaledSheet(
        zoom: _zoom,
        pad: EdgeInsets.all(_compact ? 6 : 12),
        pageWidth: _setup.cssWidth,
        pageHeight: _setup.cssHeight,
        buildChild: () => PosCommercialWordSurface(
          html: _previewHtml,
          editable: false,
          pageSetup: _setup,
          onChanged: (_) {},
        ),
      );
    }
    if (_compact) {
      return ColoredBox(
        color: const Color(0xFFE5E7EB),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: Colors.white,
            elevation: 6,
            child: PosCommercialWordSurface(
              key: _surfaceKey,
              html: _html,
              editable: true,
              pageSetup: _setup,
              onChanged: _emit,
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = 20.0;
        final availW = (constraints.maxWidth - pad * 2).clamp(180.0, 1600.0);
        final paperW = _zoom <= 0
            ? availW
            : (_setup.cssWidth * _zoom).clamp(240.0, 2000.0);
        final paperH = paperW * (_setup.cssHeight / _setup.cssWidth);
        return ColoredBox(
          color: const Color(0xFFE5E7EB),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(vertical: pad),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: pad),
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minWidth: constraints.maxWidth - pad * 2),
                  child: Center(
                    child: SizedBox(
                      width: paperW,
                      height: paperH,
                      child: Material(
                        color: Colors.white,
                        elevation: 8,
                        shadowColor: Colors.black26,
                        child: PosCommercialWordSurface(
                          key: _surfaceKey,
                          html: _html,
                          editable: true,
                          pageSetup: _setup,
                          onChanged: _emit,
                        ),
                      ),
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
}
