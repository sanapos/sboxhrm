import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_label_design.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_print_template_v2.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/pos_label_design_painter.dart';
import '../../utils/pos_label_design_presets.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_print_template_v2_codec.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_label_designer_screen.dart';

/// Ba loại tem dùng trình soạn tem.
const kPosLabelDesignTypes = [
  (PosPrintDocumentTypes.barcodeLabel, 'Tem sản phẩm', Icons.qr_code_scanner),
  (PosPrintDocumentTypes.scaleLabel, 'Tem cân', Icons.scale_outlined),
  (PosPrintDocumentTypes.specLabel, 'Tem thông số', Icons.qr_code_2),
];

/// «Mẫu tem»: danh sách mẫu của tem sản phẩm / tem cân / tem thông số — tạo từ mẫu dựng sẵn, soạn trong
/// trình soạn tem, đặt mẫu đang dùng. Mẫu khối / HTML cũ chuyển được sang dạng mới.
class PosLabelTemplatesScreen extends StatefulWidget {
  const PosLabelTemplatesScreen({super.key, this.initialType, this.embedded = false});

  final String? initialType;
  /// Nhúng trong màn «Mẫu in» (không thanh tiêu đề riêng).
  final bool embedded;

  @override
  State<PosLabelTemplatesScreen> createState() => _PosLabelTemplatesScreenState();
}

class _PosLabelTemplatesScreenState extends State<PosLabelTemplatesScreen> {
  final _api = ApiService();
  late String _type;
  bool _loading = true;
  List<({PosPrintTemplate t, PosLabelDesign d})> _designs = [];
  List<PosPrintTemplate> _legacy = [];

  @override
  void initState() {
    super.initState();
    _type = kPosLabelDesignTypes.any((t) => t.$1 == widget.initialType)
        ? widget.initialType!
        : PosPrintDocumentTypes.barcodeLabel;
    _load();
  }

  @override
  void didUpdateWidget(covariant PosLabelTemplatesScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialType != old.initialType && widget.initialType != null && widget.initialType != _type) {
      _type = widget.initialType!;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosPrintTemplates(documentType: _type);
    final list = parsePosPrintTemplatesResponse(res).where((t) => t.isActive).toList();
    if (!mounted) return;
    setState(() {
      _designs = [
        for (final t in list)
          if (PosLabelDesign.tryParse(t.htmlContent) case final d?) (t: t, d: d),
      ];
      _legacy = list.where((t) => !PosLabelDesign.isDesign(t.htmlContent)).toList();
      _loading = false;
    });
  }

  String get _typeName => kPosLabelDesignTypes.firstWhere((t) => t.$1 == _type).$2;

  Future<void> _openDesigner(PosLabelDesign d, {PosPrintTemplate? template}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PosLabelDesignerScreen(design: d, template: template)),
    );
    if (saved == true) await _load();
  }

  Future<void> _create() async {
    final picked = await showDialog<PosLabelDesign>(
      context: context,
      builder: (_) => _NewLabelDialog(documentType: _type),
    );
    if (picked == null || !mounted) return;
    await _openDesigner(picked);
  }

  Future<void> _setDefault(PosPrintTemplate t) async {
    final res = await _api.setDefaultPosPrintTemplate(t.id);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã chọn mẫu đang dùng', message: tr('$_typeName: ${t.name}'));
      await _load();
    }
  }

  Future<void> _duplicate(PosPrintTemplate t, PosLabelDesign d) async {
    final copy = d.copyWith(name: '${t.name} (bản sao)');
    final res = await _api.createPosPrintTemplate({
      'name': copy.name,
      'documentType': _type,
      'paperSize': t.paperSize,
      'htmlContent': copy.encode(),
      'isDefault': false,
      'isActive': true,
      'sortOrder': _designs.length,
    });
    if (res['isSuccess'] == true) await _load();
  }

  Future<void> _delete(PosPrintTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa mẫu «${t.name}»?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deletePosPrintTemplate(t.id);
    if (res['isSuccess'] == true) {
      await _load();
    } else {
      NotificationOverlayManager().showError(title: 'Không xóa được', message: res['message']?.toString() ?? '');
    }
  }

  /// Mẫu cũ → mẫu trình soạn (giữ id / trạng thái «đang dùng»).
  Future<void> _convert(PosPrintTemplate t) async {
    final v2 = PosPrintTemplateV2Codec.tryParse(t.htmlContent);
    final size = PosPrintPaperSizes.toLabelTemplateId(v2?.paperSize ?? t.paperSize);
    final dims = PosPrintPaperSizes.customLabelDims(size) ??
        (PosPrintPaperSizes.widthMm(size), PosPrintPaperSizes.heightMm(size));
    final w = dims.$1 > 0 ? dims.$1 : 50.0;
    final h = dims.$2 > 0 ? dims.$2 : 30.0;
    final design = v2 != null
        ? posLabelDesignFromBlocks(v2, _type, w, h)
        : PosLabelDesignPresets.forType(_type).first.build(w, h);
    await _openDesigner(design.copyWith(name: t.name), template: t);
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final t in kPosLabelDesignTypes)
                ButtonSegment(value: t.$1, icon: Icon(t.$3, size: 18), label: Text(tr(t.$2))),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              setState(() => _type = s.first);
              _load();
            },
          ),
          FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: Text(tr('Tạo mẫu $_typeName')),
          ),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (_designs.isEmpty)
                  _EmptyState(typeName: _typeName, onCreate: _create)
                else
                  Wrap(spacing: 14, runSpacing: 14, children: [
                    for (final x in _designs)
                      _DesignCard(
                        template: x.t,
                        design: x.d,
                        onEdit: () => _openDesigner(x.d, template: x.t),
                        onDefault: x.t.isDefault ? null : () => _setDefault(x.t),
                        onDuplicate: () => _duplicate(x.t, x.d),
                        onDelete: () => _delete(x.t),
                      ),
                  ]),
                if (_legacy.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(tr('Mẫu kiểu cũ (${_legacy.length})'),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate600)),
                  const SizedBox(height: 4),
                  Text(
                    tr('Soạn theo khối / HTML — không kéo thả được. Bấm «Chuyển sang trình soạn mới» để mở bằng trình soạn tem '
                        '(giữ nội dung và trạng thái đang dùng).'),
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500),
                  ),
                  const SizedBox(height: 8),
                  for (final t in _legacy)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.history_edu_outlined),
                        title: Text(t.name),
                        subtitle: Text(tr(
                            '${PosPrintPaperSizes.displayLabel(t.paperSize)}${t.isDefault ? ' · đang dùng' : ''}')),
                        trailing: Wrap(spacing: 4, children: [
                          TextButton(onPressed: () => _convert(t), child: Text(tr('Chuyển sang trình soạn mới'))),
                          IconButton(
                              tooltip: tr('Xóa'),
                              onPressed: () => _delete(t),
                              icon: const Icon(Icons.delete_outline, color: SboxColors.danger)),
                        ]),
                      ),
                    ),
                ],
              ]),
      ),
    ]);
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F4F8),
      appBar: AppBar(
        title: Text(tr('Mẫu tem')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.5,
        foregroundColor: SboxColors.text,
      ),
      body: body,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.typeName, required this.onCreate});
  final String typeName;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(children: [
          const Icon(Icons.label_outline, size: 40, color: SboxColors.slate400),
          const SizedBox(height: 8),
          Text(tr('Chưa có mẫu $typeName'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(tr('Chọn khổ tem và một mẫu dựng sẵn rồi sửa theo ý.'),
              style: const TextStyle(color: SboxColors.slate500)),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: Text(tr('Tạo mẫu'))),
        ]),
      );
}

/// Ảnh thu nhỏ tem vẽ bằng bộ vẽ tem (dữ liệu mẫu).
class _LabelThumb extends StatefulWidget {
  const _LabelThumb({required this.design, this.maxW = 240, this.maxH = 150});
  final PosLabelDesign design;
  final double maxW;
  final double maxH;

  @override
  State<_LabelThumb> createState() => _LabelThumbState();
}

class _LabelThumbState extends State<_LabelThumb> {
  Uint8List? _png;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant _LabelThumb old) {
    super.didUpdateWidget(old);
    if (old.design != widget.design) _render();
  }

  Future<void> _render() async {
    final d = widget.design;
    final png = await PosLabelDesignPainter.renderPng(d, posPrintSampleData(documentType: d.documentType), pxPerMm: 8);
    if (mounted) setState(() => _png = png);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.design;
    final s = math.min(widget.maxW / d.widthMm, widget.maxH / d.heightMm);
    return Container(
      width: d.widthMm * s,
      height: d.heightMm * s,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SboxColors.slate300),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: _png == null ? const SizedBox.shrink() : Image.memory(_png!, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
    );
  }
}

class _DesignCard extends StatelessWidget {
  const _DesignCard({
    required this.template,
    required this.design,
    required this.onEdit,
    required this.onDefault,
    required this.onDuplicate,
    required this.onDelete,
  });
  final PosPrintTemplate template;
  final PosLabelDesign design;
  final VoidCallback onEdit;
  final VoidCallback? onDefault;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onEdit,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: template.isDefault ? SboxColors.success : SboxColors.slate200,
                    width: template.isDefault ? 1.6 : 1),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  height: 170,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F4F8),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  alignment: Alignment.center,
                  child: _LabelThumb(design: design),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(template.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(tr(design.sizeLabel), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                      ]),
                    ),
                    if (template.isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: SboxColors.successSoft, borderRadius: BorderRadius.circular(20)),
                        child: Text(tr('Đang dùng'),
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: SboxColors.successText)),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (v) => switch (v) {
                        'default' => onDefault?.call(),
                        'dup' => onDuplicate(),
                        'del' => onDelete(),
                        _ => onEdit(),
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                        if (onDefault != null) PopupMenuItem(value: 'default', child: Text(tr('Dùng mẫu này khi in'))),
                        PopupMenuItem(value: 'dup', child: Text(tr('Nhân bản'))),
                        PopupMenuItem(value: 'del', child: Text(tr('Xóa'))),
                      ],
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Row(children: [
                    TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: Text(tr('Soạn'))),
                    if (onDefault != null)
                      TextButton.icon(
                          onPressed: onDefault,
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: Text(tr('Dùng khi in'))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}

/// Tạo mẫu mới: chọn khổ tem (có sẵn / tự nhập) + mẫu dựng sẵn (xem trước theo khổ đã chọn).
class _NewLabelDialog extends StatefulWidget {
  const _NewLabelDialog({required this.documentType});
  final String documentType;

  @override
  State<_NewLabelDialog> createState() => _NewLabelDialogState();
}

class _NewLabelDialogState extends State<_NewLabelDialog> {
  double _w = 50;
  double _h = 30;
  late final _wCtrl = TextEditingController(text: '50');
  late final _hCtrl = TextEditingController(text: '30');
  String _preset = '';

  @override
  void dispose() {
    _wCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  List<PosLabelDesignPreset> get _presets =>
      [...PosLabelDesignPresets.forType(widget.documentType), PosLabelDesignPresets.blank(widget.documentType)];

  void _setSize(double w, double h) => setState(() {
        _w = w;
        _h = h;
        _wCtrl.text = w.toStringAsFixed(w == w.roundToDouble() ? 0 : 1);
        _hCtrl.text = h.toStringAsFixed(h == h.roundToDouble() ? 0 : 1);
      });

  @override
  Widget build(BuildContext context) {
    final presets = _presets;
    final sel = _preset.isEmpty ? presets.first.key : _preset;
    return AlertDialog(
      title: Text(tr('Tạo mẫu tem')),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(tr('1. Khổ tem'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in PosLabelDesignPresets.sizes)
                ChoiceChip(
                  label: Text('${s.$1.toStringAsFixed(0)}×${s.$2.toStringAsFixed(0)} mm'),
                  selected: _w == s.$1 && _h == s.$2,
                  onSelected: (_) => _setSize(s.$1, s.$2),
                ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _wCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Rộng (mm)'), isDense: true, border: const OutlineInputBorder()),
                  onChanged: (v) => setState(() => _w = (double.tryParse(v.replaceAll(',', '.')) ?? _w).clamp(10, 200)),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _hCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: tr('Cao (mm)'), isDense: true, border: const OutlineInputBorder()),
                  onChanged: (v) => setState(() => _h = (double.tryParse(v.replaceAll(',', '.')) ?? _h).clamp(8, 300)),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(tr('Nhập đúng khổ tem dán trên cuộn (không tính phần đế).'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              ),
            ]),
            const SizedBox(height: 18),
            Text(tr('2. Mẫu bắt đầu'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final p in presets)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _preset = p.key),
                  child: Container(
                    width: 230,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel == p.key ? SboxColors.primary : SboxColors.slate200, width: sel == p.key ? 2 : 1),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        height: 120,
                        alignment: Alignment.center,
                        color: const Color(0xFFF1F4F8),
                        child: _LabelThumb(design: p.build(_w, _h), maxW: 200, maxH: 105),
                      ),
                      const SizedBox(height: 6),
                      Text(tr(p.name), style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(tr(p.description), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: () => Navigator.pop(context, presets.firstWhere((p) => p.key == sel).build(_w, _h)),
          child: Text(tr('Mở trình soạn')),
        ),
      ],
    );
  }
}

/// Mẫu khối V2 cũ → phần tử đặt tự do (xếp từ trên xuống, co lại nếu dài hơn tem).
PosLabelDesign posLabelDesignFromBlocks(PosPrintTemplateV2 v2, String documentType, double w, double h) {
  const m = 1.5;
  const dotsPerMm = 8.0;
  final els = <PosLabelElement>[];
  var y = 1.0;
  PosLabelAlign al(PosPrintTextAlign a) => switch (a) {
        PosPrintTextAlign.center => PosLabelAlign.center,
        PosPrintTextAlign.right => PosLabelAlign.right,
        PosPrintTextAlign.left => PosLabelAlign.left,
      };
  // Cỡ chữ V2 tính theo điểm in (203 dpi) → pt.
  double pt(double dots) => (dots / (203 / 72) * 10).roundToDouble() / 10;
  PosLabelElement text(String s, PosPrintTextStyle st, double x, double ww) {
    final hh = math.max(2.5, st.fontSize / dotsPerMm * 1.2);
    return PosLabelElement(
      id: PosLabelDesignPresets.newId(),
      type: PosLabelElementType.text,
      x: x,
      y: y,
      w: ww,
      h: hh,
      text: st.uppercase ? s.toUpperCase() : s,
      fontSize: pt(st.fontSize),
      bold: st.bold,
      align: al(st.align),
      maxLines: 1,
    );
  }

  for (final b in v2.blocks) {
    switch (b.type) {
      case PosPrintBlockType.text:
      case PosPrintBlockType.field:
        final s = b.type == PosPrintBlockType.field
            ? '${(b.label ?? '').isNotEmpty ? '${b.label}: ' : ''}{${b.field}}'
            : (b.text ?? '');
        final e = text(s, b.style, m, w - 2 * m);
        els.add(e);
        y += e.h;
      case PosPrintBlockType.pair:
        final l = text('{${b.leftField}}', b.style, m, (w - 2 * m) / 2);
        final r = text('{${b.rightField}}', b.rightStyle ?? b.style, m + (w - 2 * m) / 2, (w - 2 * m) / 2)
            .copyWith(align: PosLabelAlign.right);
        els.addAll([l, r]);
        y += math.max(l.h, r.h);
      case PosPrintBlockType.barcode:
        final hh = b.barcodeQr ? math.min(b.barcodeHeight / dotsPerMm, w * 0.5) : b.barcodeHeight / dotsPerMm + (b.barcodeShowText ? 3 : 0);
        els.add(PosLabelElement(
          id: PosLabelDesignPresets.newId(),
          type: b.barcodeQr ? PosLabelElementType.qr : PosLabelElementType.barcode,
          x: b.barcodeQr ? (w - hh) / 2 : m,
          y: y,
          w: b.barcodeQr ? hh : w - 2 * m,
          h: hh,
          text: (b.codeContent ?? '').isNotEmpty ? b.codeContent! : '{${b.field ?? 'Ma_Vach'}}',
          showText: b.barcodeShowText,
        ));
        y += hh + 0.5;
      case PosPrintBlockType.divider:
        els.add(PosLabelElement(
            id: PosLabelDesignPresets.newId(), type: PosLabelElementType.line, x: m, y: y, w: w - 2 * m, h: 1));
        y += 1;
      case PosPrintBlockType.spacer:
        y += b.height / dotsPerMm;
      case PosPrintBlockType.image:
        final iw = (w - 2 * m) * b.imageWidthPct / 100;
        els.add(PosLabelElement(
          id: PosLabelDesignPresets.newId(),
          type: PosLabelElementType.image,
          x: (w - iw) / 2,
          y: y,
          w: iw,
          h: iw * 0.5,
          imageData: b.imageData,
        ));
        y += iw * 0.5;
      default:
        break;
    }
  }
  // Dài hơn tem → co toạ độ dọc + cỡ chữ cho vừa.
  final total = y + 1;
  if (total > h) {
    final k = h / total;
    for (var i = 0; i < els.length; i++) {
      final e = els[i];
      els[i] = e.copyWith(y: e.y * k, h: e.h * k, fontSize: (e.fontSize * k * 10).roundToDouble() / 10);
    }
  }
  return PosLabelDesign(documentType: documentType, widthMm: w, heightMm: h, elements: els, name: v2.name);
}
