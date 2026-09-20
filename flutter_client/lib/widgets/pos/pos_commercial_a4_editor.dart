import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../services/api_service.dart';
import '../../utils/pos_print_template_renderer.dart';
import 'pos_commercial_word_stub.dart'
    if (dart.library.js_interop) 'pos_commercial_word_web.dart';

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
    this.initialTab = 0,
    this.initialZoom = 0,
  });

  final String html;
  final String documentType;
  final ValueChanged<String> onChanged;

  /// Mở trong route toàn màn hình (ẩn hướng dẫn, hiện nút Thu nhỏ).
  final bool immersive;

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
  final _previewKey = GlobalKey<PosCommercialWordSurfaceState>();
  late String _html;
  late int _tab;
  late double _zoom; // 0 = vừa khung
  Map<String, dynamic>? _commercialProfile;
  String _fontFamily = "'Times New Roman', Times, serif";
  String _fontSize = '3'; // execCommand fontSize: 1..7

  /// Chiều rộng CSS của A4 @ 96dpi — mốc 100%.
  static const _a4CssWidth = 794.0;
  static const _zoomSteps = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

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
    }
  }

  void _emit(String html) {
    _html = html;
    widget.onChanged(html);
    // Không gọi setState để tránh làm mất caret trong iframe.
  }

  void _cmd(String cmd, [String? value]) {
    _surfaceKey.currentState?.exec(cmd, value);
  }

  void _insert(String html) {
    _surfaceKey.currentState?.insertHtml(html);
    if (!kIsWeb) {
      _html = '$_html$html';
      widget.onChanged(_html);
      setState(() {});
    }
  }

  String get _previewHtml => renderPosPrintTemplateHtml(
        _html,
        data: posPrintSampleData(
          documentType: widget.documentType,
          commercialProfile: _commercialProfile,
        ),
        lineItems: posPrintSampleLines(),
        wrapDocument: false,
        paperSize: PosPrintPaperSizes.a4,
      );

  @override
  Widget build(BuildContext context) {
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
        const SizedBox(height: 8),
        Expanded(child: _paperCanvas(preview: _tab == 1)),
      ],
    );
  }

  Widget _hintRow() {
    return Text(
      tr('Bôi đen chữ rồi chọn font / cỡ / đậm / màu. Phóng to hoặc toàn màn hình để dễ xem.'),
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
    final zoomLabel =
        _zoom <= 0 ? tr('Vừa khung') : '${(_zoom * 100).round()}%';
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
              label: Text(tr('Xem trước A4')),
              icon: const Icon(Icons.visibility_outlined, size: 18),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        Material(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: tr('Thu nhỏ'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 18),
                onPressed: _zoomOut,
              ),
              PopupMenuButton<double>(
                tooltip: tr('Tỷ lệ xem'),
                onSelected: (v) => setState(() => _zoom = v),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 0, child: Text(tr('Vừa khung'))),
                  for (final z in _zoomSteps)
                    PopupMenuItem(
                      value: z,
                      child: Text('${(z * 100).round()}%'),
                    ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    zoomLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Phóng to'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                onPressed: _zoomIn,
              ),
            ],
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

  void _zoomIn() {
    if (_zoom <= 0) {
      setState(() => _zoom = 1.25);
      return;
    }
    final i = _zoomSteps.indexWhere((z) => z > _zoom + 0.001);
    if (i >= 0) setState(() => _zoom = _zoomSteps[i]);
  }

  void _zoomOut() {
    if (_zoom <= 0) {
      setState(() => _zoom = 0.75);
      return;
    }
    final prev = _zoomSteps.lastWhere((z) => z < _zoom - 0.001, orElse: () => 0);
    setState(() => _zoom = prev);
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
                initialTab: _tab,
                initialZoom: 0,
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
      '<table style="width:100%;border-collapse:collapse;margin:6px 0">'
      '<thead><tr>'
      '<th style="border:1px solid #000;padding:4px 6px">STT</th>'
      '<th style="border:1px solid #000;padding:4px 6px">Hàng hóa / dịch vụ</th>'
      '<th style="border:1px solid #000;padding:4px 6px">ĐVT</th>'
      '<th style="border:1px solid #000;padding:4px 6px">SL</th>'
      '<th style="border:1px solid #000;padding:4px 6px;text-align:right">Đơn giá</th>'
      '<th style="border:1px solid #000;padding:4px 6px;text-align:right">Thành tiền</th>'
      '<th style="border:1px solid #000;padding:4px 6px">Bảo hành</th>'
      '</tr></thead>'
      '<tbody><!--BEGIN_ITEMS-->'
      '<tr>'
      '<td style="border:1px solid #000;padding:4px 6px;text-align:center">{STT}</td>'
      '<td style="border:1px solid #000;padding:4px 6px">{Ten_Hang_Hoa}</td>'
      '<td style="border:1px solid #000;padding:4px 6px;text-align:center">{Don_Vi_Tinh}</td>'
      '<td style="border:1px solid #000;padding:4px 6px;text-align:center">{So_Luong}</td>'
      '<td style="border:1px solid #000;padding:4px 6px;text-align:right">{Don_Gia}</td>'
      '<td style="border:1px solid #000;padding:4px 6px;text-align:right">{Thanh_Tien}</td>'
      '<td style="border:1px solid #000;padding:4px 6px">{Bao_Hanh}</td>'
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
    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = 20.0;
        final availW = (constraints.maxWidth - pad * 2).clamp(280.0, 1600.0);
        final paperW = _zoom <= 0
            ? availW.clamp(480.0, 1100.0)
            : (_a4CssWidth * _zoom).clamp(320.0, 2000.0);
        final paperH = paperW * 297 / 210;
        return ColoredBox(
          color: const Color(0xFFE5E7EB),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: pad),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: pad),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth - pad * 2),
                  child: Center(
                    child: SizedBox(
                      width: paperW,
                      height: paperH,
                      child: Material(
                        color: Colors.white,
                        elevation: 8,
                        shadowColor: Colors.black26,
                        child: preview
                            ? PosCommercialWordSurface(
                                key: _previewKey,
                                html: _previewHtml,
                                editable: false,
                                onChanged: (_) {},
                              )
                            : PosCommercialWordSurface(
                                key: _surfaceKey,
                                html: _html,
                                editable: true,
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
