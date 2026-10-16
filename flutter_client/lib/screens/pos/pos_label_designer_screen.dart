import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_label_design.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_design_painter.dart';
import '../../utils/pos_label_design_presets.dart';
import '../../utils/pos_print_template_renderer.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_print_template_tools.dart';

/// Trường dữ liệu chèn được vào tem (theo loại tem) — tên dễ hiểu thay cho mã {Token}.
List<(String, String)> posLabelDesignFields(String documentType) => switch (documentType) {
      PosPrintDocumentTypes.scaleLabel => PosPrintTokens.scaleLabel,
      PosPrintDocumentTypes.specLabel => PosPrintTokens.specLabel,
      _ => [
          for (final t in PosPrintTokens.label)
            if (!const {'Ten_Ban', 'Ma_Don_Hang', 'Ghi_Chu', 'So_Luong', 'Gio'}.contains(t.$1)) t,
        ],
    };

/// Trình soạn tem: đặt chữ / trường / mã vạch / QR / ảnh / kẻ / khung tự do trên tem đúng tỉ lệ mm.
class PosLabelDesignerScreen extends StatefulWidget {
  const PosLabelDesignerScreen({super.key, required this.design, this.template});

  final PosLabelDesign design;
  /// Mẫu đang sửa (null = mẫu mới, lưu sẽ tạo).
  final PosPrintTemplate? template;

  @override
  State<PosLabelDesignerScreen> createState() => _PosLabelDesignerScreenState();
}

enum _Drag { none, move, resize }

class _PosLabelDesignerScreenState extends State<PosLabelDesignerScreen> {
  final _api = ApiService();
  late PosLabelDesign _d;
  late final TextEditingController _nameCtrl;
  final _undo = <PosLabelDesign>[];
  final _redo = <PosLabelDesign>[];
  String? _selId;
  double _zoom = 1;
  bool _dirty = false;
  bool _saving = false;
  Map<String, String> _data = const {};
  String _dataLabel = 'Dữ liệu mẫu';
  Map<String, ui.Image> _images = const {};
  final _canvasFocus = FocusNode();

  // Kéo / đổi cỡ
  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  PosLabelElement? _dragOrig;
  List<double> _guideX = const [];
  List<double> _guideY = const [];

  static const _snap = 0.5;

  @override
  void initState() {
    super.initState();
    _d = widget.design;
    _nameCtrl = TextEditingController(text: widget.template?.name ?? _d.name ?? 'Mẫu tem mới');
    _data = posPrintSampleData(documentType: _d.documentType);
    unawaited(_loadStoreName());
    unawaited(_reloadImages());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _canvasFocus.dispose();
    super.dispose();
  }

  Future<void> _loadStoreName() async {
    final s = await PosSellStoreSettings.load();
    final name = s.storeName.trim();
    if (!mounted || name.isEmpty) return;
    setState(() => _data = {..._data, 'Ten_Cua_Hang': name});
  }

  Future<void> _reloadImages() async {
    final imgs = await PosLabelDesignPainter.loadImages(_d);
    if (mounted) setState(() => _images = imgs);
  }

  PosLabelElement? get _sel => _d.elements.where((e) => e.id == _selId).firstOrNull;

  // ── Sửa mẫu + hoàn tác ───────────────────────────────────────────────────
  void _commit(PosLabelDesign next, {bool history = true}) {
    if (history) {
      _undo.add(_d);
      if (_undo.length > 80) _undo.removeAt(0);
      _redo.clear();
    }
    setState(() {
      _d = next;
      _dirty = true;
    });
  }

  void _updateSel(PosLabelElement Function(PosLabelElement e) f, {bool history = true}) {
    final s = _sel;
    if (s == null) return;
    _commit(_d.copyWith(elements: [for (final e in _d.elements) e.id == s.id ? f(e) : e]), history: history);
  }

  void _undoStep() {
    if (_undo.isEmpty) return;
    _redo.add(_d);
    setState(() {
      _d = _undo.removeLast();
      _dirty = true;
      if (_sel == null) _selId = null;
    });
    unawaited(_reloadImages());
  }

  void _redoStep() {
    if (_redo.isEmpty) return;
    _undo.add(_d);
    setState(() {
      _d = _redo.removeLast();
      _dirty = true;
    });
    unawaited(_reloadImages());
  }

  void _add(PosLabelElement e) {
    _commit(_d.copyWith(elements: [..._d.elements, e]));
    setState(() => _selId = e.id);
    _canvasFocus.requestFocus();
  }

  PosLabelElement _newEl(PosLabelElementType type, {String text = '', double? w, double? h}) {
    final ew = math.min(w ?? _d.widthMm * 0.6, _d.widthMm);
    final eh = math.min(h ?? 6, _d.heightMm);
    return PosLabelElement(
      id: PosLabelDesignPresets.newId(),
      type: type,
      x: _snapV((_d.widthMm - ew) / 2),
      y: _snapV((_d.heightMm - eh) / 2),
      w: ew,
      h: eh,
      text: text,
      fontSize: 8,
      align: PosLabelAlign.center,
    );
  }

  void _addText([String text = 'Chữ mới']) => _add(_newEl(PosLabelElementType.text, text: text, h: 5));

  void _addBarcode() =>
      _add(_newEl(PosLabelElementType.barcode, text: '{Ma_Vach}', w: _d.widthMm * 0.8, h: _d.heightMm * 0.35));

  void _addQr() {
    final side = math.min(_d.heightMm * 0.6, _d.widthMm * 0.5);
    _add(_newEl(PosLabelElementType.qr, text: '{Ma_Hang}', w: side, h: side));
  }

  void _addLine() => _add(_newEl(PosLabelElementType.line, w: _d.widthMm - 3, h: 1));

  void _addBox() => _add(_newEl(PosLabelElementType.box, w: _d.widthMm * 0.5, h: _d.heightMm * 0.3));

  Future<void> _addImage() async {
    final raw = await _pickImageData(_d.widthMm * 0.4);
    if (raw == null) return;
    final e = _newEl(PosLabelElementType.image, w: _d.widthMm * 0.4, h: _d.heightMm * 0.4).copyWith(imageData: raw);
    _add(e);
    unawaited(_reloadImages());
  }

  Future<String?> _pickImageData(double widthMm) async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = r?.files.single.bytes;
    if (bytes == null) return null;
    final data = preparePosPrintImage(bytes, maxWidth: (widthMm * 8).round().clamp(64, 800));
    if (data == null && mounted) {
      NotificationOverlayManager().showError(title: 'Ảnh', message: tr('Không đọc được ảnh (dùng PNG / JPG)'));
    }
    return data;
  }

  void _deleteSel() {
    final s = _sel;
    if (s == null) return;
    _commit(_d.copyWith(elements: _d.elements.where((e) => e.id != s.id).toList()));
    setState(() => _selId = null);
  }

  void _duplicateSel() {
    final s = _sel;
    if (s == null) return;
    _add(s.copyWith(id: PosLabelDesignPresets.newId(), x: s.x + 1, y: s.y + 1));
  }

  void _moveLayer(int delta) {
    final s = _sel;
    if (s == null) return;
    final list = [..._d.elements];
    final i = list.indexWhere((e) => e.id == s.id);
    final j = (i + delta).clamp(0, list.length - 1);
    if (i == j) return;
    list.removeAt(i);
    list.insert(j, s);
    _commit(_d.copyWith(elements: list));
  }

  double _snapV(double v) => (v / _snap).roundToDouble() * _snap;

  // ── Kéo thả trên tem ─────────────────────────────────────────────────────
  PosLabelElement? _hit(Offset mm) {
    for (final e in _d.elements.reversed) {
      if (Rect.fromLTWH(e.x, e.y, math.max(e.w, 1.5), math.max(e.h, 1.5)).inflate(0.4).contains(mm)) return e;
    }
    return null;
  }

  bool _onResizeHandle(Offset px, double s) {
    final e = _sel;
    if (e == null) return false;
    final corner = Offset((e.x + e.w) * s, (e.y + e.h) * s);
    return (px - corner).distance <= 14;
  }

  void _panStart(Offset px, double s) {
    _canvasFocus.requestFocus();
    if (_onResizeHandle(px, s)) {
      _drag = _Drag.resize;
    } else {
      final hit = _hit(px / s);
      if (hit == null) {
        setState(() => _selId = null);
        _drag = _Drag.none;
        return;
      }
      setState(() => _selId = hit.id);
      _drag = _Drag.move;
    }
    _dragStart = px;
    _dragOrig = _sel;
    if (_dragOrig != null) {
      _undo.add(_d);
      _redo.clear();
    }
  }

  void _panUpdate(Offset px, double s) {
    final o = _dragOrig;
    if (o == null || _drag == _Drag.none) return;
    final dx = (px.dx - _dragStart.dx) / s;
    final dy = (px.dy - _dragStart.dy) / s;
    if (_drag == _Drag.resize) {
      _updateSel(
          (e) => e.copyWith(
                w: math.max(1.5, _snapV(o.w + dx)),
                h: math.max(1.0, _snapV(o.h + dy)),
              ),
          history: false);
      return;
    }
    var x = _snapV(o.x + dx);
    var y = _snapV(o.y + dy);
    // Bắt đường căn: mép / tâm tem và mép / tâm phần tử khác (≤ 0,8 mm).
    final gx = <double>[];
    final gy = <double>[];
    final tx = <double>[0, _d.widthMm / 2, _d.widthMm];
    final ty = <double>[0, _d.heightMm / 2, _d.heightMm];
    for (final e in _d.elements) {
      if (e.id == o.id) continue;
      tx.addAll([e.x, e.x + e.w / 2, e.x + e.w]);
      ty.addAll([e.y, e.y + e.h / 2, e.y + e.h]);
    }
    double? best(List<double> mine, List<double> targets, List<double> guides) {
      double? off;
      var bestD = 0.8;
      for (final m in mine) {
        for (final t in targets) {
          final dd = (t - m).abs();
          if (dd < bestD) {
            bestD = dd;
            off = t - m;
            guides
              ..clear()
              ..add(t);
          }
        }
      }
      return off;
    }

    final ox = best([x, x + o.w / 2, x + o.w], tx, gx);
    final oy = best([y, y + o.h / 2, y + o.h], ty, gy);
    if (ox != null) x += ox;
    if (oy != null) y += oy;
    x = x.clamp(-o.w + 1, _d.widthMm - 1);
    y = y.clamp(-o.h + 1, _d.heightMm - 1);
    setState(() {
      _guideX = gx;
      _guideY = gy;
    });
    _updateSel((e) => e.copyWith(x: x, y: y), history: false);
  }

  void _panEnd() {
    _drag = _Drag.none;
    _dragOrig = null;
    setState(() {
      _guideX = const [];
      _guideY = const [];
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent ev) {
    if (ev is! KeyDownEvent && ev is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = ev.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && k == LogicalKeyboardKey.keyZ) {
      HardwareKeyboard.instance.isShiftPressed ? _redoStep() : _undoStep();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyY) {
      _redoStep();
      return KeyEventResult.handled;
    }
    if (_sel == null) return KeyEventResult.ignored;
    if (ctrl && k == LogicalKeyboardKey.keyD) {
      _duplicateSel();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      _deleteSel();
      return KeyEventResult.handled;
    }
    final step = HardwareKeyboard.instance.isShiftPressed ? 2.0 : _snap;
    final move = switch (k) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (move == null) return KeyEventResult.ignored;
    _updateSel((e) => e.copyWith(x: e.x + move.dx * step, y: e.y + move.dy * step));
    return KeyEventResult.handled;
  }

  // ── Lưu ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    final name = _nameCtrl.text.trim().isEmpty ? 'Mẫu tem' : _nameCtrl.text.trim();
    final design = _d.copyWith(name: name);
    final paper = PosPrintPaperSizes.toApiPaperSize(
        design.documentType, PosPrintPaperSizes.customLabelId(design.widthMm, design.heightMm));
    setState(() => _saving = true);
    final t = widget.template;
    final res = t == null
        ? await _api.createPosPrintTemplate({
            'name': name,
            'documentType': design.documentType,
            'paperSize': paper,
            'htmlContent': design.encode(),
            'isDefault': false,
            'isActive': true,
            'sortOrder': 0,
          })
        : await _api.updatePosPrintTemplate(
            t.id, t.copyWith(name: name, paperSize: paper, htmlContent: design.encode()).toSaveJson());
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      _dirty = false;
      NotificationOverlayManager().showSuccess(title: 'Đã lưu mẫu tem', message: tr(name));
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Không lưu được', message: res['message']?.toString() ?? '');
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ thay đổi?')),
        content: Text(tr('Mẫu tem chưa lưu. Thoát sẽ mất các thay đổi.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Ở lại'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ thay đổi'))),
        ],
      ),
    );
    return ok == true;
  }

  // ── Dữ liệu xem thử ──────────────────────────────────────────────────────
  Future<void> _pickSampleProduct() async {
    final p = await showDialog<PosProduct>(context: context, builder: (_) => const _ProductPickDialog());
    if (p == null || !mounted) return;
    final store = _data['Ten_Cua_Hang'];
    final opts = PosBarcodePrintOptions(
      template: defaultBarcodeLabelTemplate,
      codeField: PosBarcodeCodeField.barcode,
      storeMode: PosBarcodeStoreMode.withStore,
      storeName: store,
    );
    setState(() {
      _data = {...posPrintSampleData(documentType: _d.documentType), ...posBarcodeLabelData(p, opts)};
      _dataLabel = p.name;
    });
  }

  Future<void> _previewPrint() async {
    final img = await PosLabelDesignPainter.renderPng(_d, _data, pxPerMm: 203 / 25.4);
    if (!mounted || img == null) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bản in thật — ${_d.sizeLabel} (203 dpi)')),
        content: Container(
          decoration: BoxDecoration(border: Border.all(color: SboxColors.slate300)),
          child: Image.memory(img, filterQuality: FilterQuality.none),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
      ),
    );
  }

  // ── Giao diện ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          _dirty = false;
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F4F8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0.5,
          foregroundColor: SboxColors.text,
          titleSpacing: 0,
          title: Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                onChanged: (_) => _dirty = true,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: tr('Tên mẫu tem'),
                ),
              ),
            ),
            if (wide)
              Text(tr('${PosPrintDocumentTypes.all[_d.documentType] ?? ''} · ${_d.sizeLabel}'),
                  style: const TextStyle(fontSize: 13, color: SboxColors.slate500)),
          ]),
          actions: [
            IconButton(
                tooltip: tr('Hoàn tác (Ctrl+Z)'), onPressed: _undo.isEmpty ? null : _undoStep, icon: const Icon(Icons.undo)),
            IconButton(
                tooltip: tr('Làm lại (Ctrl+Y)'), onPressed: _redo.isEmpty ? null : _redoStep, icon: const Icon(Icons.redo)),
            IconButton(tooltip: tr('Xem bản in thật'), onPressed: _previewPrint, icon: const Icon(Icons.print_outlined)),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(tr(_saving ? 'Đang lưu…' : 'Lưu mẫu')),
              ),
            ),
          ],
        ),
        body: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(width: 230, child: _panel(_buildToolbox())),
                Expanded(child: _buildCanvasArea()),
                SizedBox(width: 320, child: _panel(_buildProperties())),
              ])
            : DefaultTabController(
                length: 3,
                child: Column(children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.42, child: _buildCanvasArea()),
                  Material(
                    color: Colors.white,
                    child: TabBar(tabs: [
                      Tab(text: tr('Thêm')),
                      Tab(text: tr('Thuộc tính')),
                      Tab(text: tr('Lớp')),
                    ]),
                  ),
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: TabBarView(children: [
                        _buildAddButtons(),
                        _buildProperties(),
                        _buildLayers(),
                      ]),
                    ),
                  ),
                ]),
              ),
      ),
    );
  }

  Widget _panel(Widget child) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border.symmetric(vertical: BorderSide(color: SboxColors.slate200)),
        ),
        child: child,
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
        child: Text(tr(t), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
      );

  Widget _buildToolbox() => ListView(children: [
        _sectionTitle('THÊM VÀO TEM'),
        _buildAddButtons(shrink: true),
        _sectionTitle('CÁC LỚP (trên cùng ở đầu)'),
        _buildLayers(shrink: true),
      ]);

  Widget _buildAddButtons({bool shrink = false}) {
    final fields = posLabelDesignFields(_d.documentType);
    Widget btn(IconData icon, String label, VoidCallback onTap) => ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(icon, size: 20, color: SboxColors.primary),
          title: Text(tr(label), style: const TextStyle(fontSize: 13.5)),
          onTap: onTap,
        );
    return ListView(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      children: [
        PopupMenuButton<String>(
          tooltip: tr('Chèn trường dữ liệu'),
          onSelected: (f) => _addText('{$f}'),
          itemBuilder: (_) => [for (final f in fields) PopupMenuItem(value: f.$1, child: Text(tr(f.$2)))],
          child: IgnorePointer(child: btn(Icons.data_object, 'Trường dữ liệu…', () {})),
        ),
        btn(Icons.text_fields, 'Chữ', _addText),
        btn(Icons.view_week_outlined, 'Mã vạch', _addBarcode),
        btn(Icons.qr_code_2, 'Mã QR', _addQr),
        btn(Icons.image_outlined, 'Ảnh / logo', _addImage),
        btn(Icons.horizontal_rule, 'Đường kẻ', _addLine),
        btn(Icons.crop_square, 'Khung / ô đen', _addBox),
      ],
    );
  }

  String _elementLabel(PosLabelElement e) {
    final names = {for (final f in posLabelDesignFields(_d.documentType)) f.$1: f.$2};
    String friendly(String s) => s.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => '[${names[m[1]] ?? m[1]}]');
    return switch (e.type) {
      PosLabelElementType.text => friendly(e.text).replaceAll('\n', ' '),
      PosLabelElementType.barcode => 'Mã vạch ${friendly(PosLabelDesignPainter.codeTemplate(e))}',
      PosLabelElementType.qr => 'QR ${friendly(PosLabelDesignPainter.codeTemplate(e)).replaceAll('\n', ' ')}',
      PosLabelElementType.image => 'Ảnh / logo',
      PosLabelElementType.line => 'Đường kẻ',
      PosLabelElementType.box => e.filled ? 'Ô đen' : 'Khung',
    };
  }

  IconData _elementIcon(PosLabelElementType t) => switch (t) {
        PosLabelElementType.text => Icons.text_fields,
        PosLabelElementType.barcode => Icons.view_week_outlined,
        PosLabelElementType.qr => Icons.qr_code_2,
        PosLabelElementType.image => Icons.image_outlined,
        PosLabelElementType.line => Icons.horizontal_rule,
        PosLabelElementType.box => Icons.crop_square,
      };

  Widget _buildLayers({bool shrink = false}) {
    final els = _d.elements.reversed.toList();
    if (els.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(tr('Chưa có gì trên tem — bấm mục ở trên để thêm.'),
            style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
      );
    }
    return ListView(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      children: [
        for (final e in els)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            selected: e.id == _selId,
            selectedTileColor: SboxColors.primary.withValues(alpha: 0.08),
            leading: Icon(_elementIcon(e.type), size: 18),
            title: Text(tr(_elementLabel(e)), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            onTap: () {
              setState(() => _selId = e.id);
              _canvasFocus.requestFocus();
            },
          ),
      ],
    );
  }

  Widget _buildCanvasArea() {
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          const Icon(Icons.dataset_outlined, size: 18, color: SboxColors.slate500),
          const SizedBox(width: 6),
          Flexible(
            child: Text(tr('Xem thử với: $_dataLabel'),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
          TextButton(onPressed: _pickSampleProduct, child: Text(tr('Chọn hàng'))),
          if (_dataLabel != 'Dữ liệu mẫu')
            TextButton(
              onPressed: () => setState(() {
                _data = {...posPrintSampleData(documentType: _d.documentType), 'Ten_Cua_Hang': _data['Ten_Cua_Hang'] ?? ''};
                _dataLabel = 'Dữ liệu mẫu';
              }),
              child: Text(tr('Dữ liệu mẫu')),
            ),
          const Spacer(),
          IconButton(
              tooltip: tr('Thu nhỏ'),
              onPressed: () => setState(() => _zoom = (_zoom / 1.25).clamp(0.4, 4)),
              icon: const Icon(Icons.zoom_out, size: 20)),
          Text('${(_zoom * 100).round()}%', style: const TextStyle(fontSize: 12)),
          IconButton(
              tooltip: tr('Phóng to'),
              onPressed: () => setState(() => _zoom = (_zoom * 1.25).clamp(0.4, 4)),
              icon: const Icon(Icons.zoom_in, size: 20)),
          IconButton(
              tooltip: tr('Vừa khung'), onPressed: () => setState(() => _zoom = 1), icon: const Icon(Icons.fit_screen, size: 20)),
        ]),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final fit = math.min((c.maxWidth - 48) / _d.widthMm, (c.maxHeight - 56) / _d.heightMm);
          final s = math.max(1.0, fit * _zoom);
          final w = _d.widthMm * s;
          final h = _d.heightMm * s;
          return Focus(
            focusNode: _canvasFocus,
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _canvasFocus.requestFocus(),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: c.maxWidth, minHeight: c.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          GestureDetector(
                            onPanStart: (d) => _panStart(d.localPosition, s),
                            onPanUpdate: (d) => _panUpdate(d.localPosition, s),
                            onPanEnd: (_) => _panEnd(),
                            onTapDown: (d) {
                              _canvasFocus.requestFocus();
                              setState(() => _selId = _hit(d.localPosition / s)?.id);
                            },
                            child: MouseRegion(
                              cursor: SystemMouseCursors.move,
                              child: Container(
                                decoration: BoxDecoration(boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 3)),
                                ]),
                                child: CustomPaint(
                                  size: Size(w, h),
                                  painter: _CanvasPainter(
                                    design: _d,
                                    data: _data,
                                    pxPerMm: s,
                                    images: _images,
                                    selected: _sel,
                                    guideX: _guideX,
                                    guideY: _guideY,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(tr(_d.sizeLabel), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    ]);
  }

  // ── Bảng thuộc tính ──────────────────────────────────────────────────────
  Widget _buildProperties() {
    final e = _sel;
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: e == null ? _labelProps() : _elementProps(e));
  }

  List<Widget> _labelProps() => [
        _sectionTitle('KHỔ TEM'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final sz in PosLabelDesignPresets.sizes)
              ChoiceChip(
                label: Text('${sz.$1.toStringAsFixed(0)}×${sz.$2.toStringAsFixed(0)}'),
                selected: _d.widthMm == sz.$1 && _d.heightMm == sz.$2,
                onSelected: (_) => _resizeLabel(sz.$1, sz.$2),
              ),
          ]),
        ),
        _row([
          _NumField(label: 'Rộng (mm)', value: _d.widthMm, min: 10, max: 200, onChanged: (v) => _resizeLabel(v, _d.heightMm)),
          _NumField(label: 'Cao (mm)', value: _d.heightMm, min: 8, max: 300, onChanged: (v) => _resizeLabel(_d.widthMm, v)),
        ]),
        _row([
          _NumField(label: 'Khe giữa tem (mm)', value: _d.gapMm, min: 0, max: 20, onChanged: (v) => _commit(_d.copyWith(gapMm: v))),
          _IntDrop(
            label: 'Số tem / hàng',
            value: _d.columns,
            items: const [1, 2, 3, 4],
            onChanged: (v) => _commit(_d.copyWith(columns: v)),
          ),
        ]),
        if (_d.columns > 1)
          _row([
            _NumField(
                label: 'Cách giữa 2 tem ngang (mm)',
                value: _d.columnGapMm,
                min: 0,
                max: 20,
                onChanged: (v) => _commit(_d.copyWith(columnGapMm: v))),
          ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
          child: Text(
            tr('Bấm một phần tử trên tem để sửa. Kéo để di chuyển, kéo chấm góc dưới phải để đổi cỡ. '
                'Phím mũi tên nhích 0,5 mm (Shift: 2 mm), Delete xóa, Ctrl+D nhân bản, Ctrl+Z hoàn tác.'),
            style: const TextStyle(fontSize: 12, color: SboxColors.slate500, height: 1.4),
          ),
        ),
      ];

  /// Đổi khổ tem: co giãn toàn bộ phần tử theo tỉ lệ (không phải đặt lại từng ô).
  void _resizeLabel(double w, double h) {
    if (w <= 0 || h <= 0 || (w == _d.widthMm && h == _d.heightMm)) return;
    final sx = w / _d.widthMm;
    final sy = h / _d.heightMm;
    final sf = math.min(sx, sy);
    _commit(_d.copyWith(widthMm: w, heightMm: h, elements: [
      for (final e in _d.elements)
        e.copyWith(
          x: _snapV(e.x * sx),
          y: _snapV(e.y * sy),
          w: _snapV(e.w * sx),
          h: _snapV(e.h * sy),
          fontSize: (e.fontSize * sf * 10).roundToDouble() / 10,
        ),
    ]));
  }

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Row(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: children[i]),
          ],
        ]),
      );

  List<Widget> _elementProps(PosLabelElement e) {
    final fields = posLabelDesignFields(_d.documentType);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        child: Row(children: [
          IconButton(
              tooltip: tr('Bỏ chọn'), onPressed: () => setState(() => _selId = null), icon: const Icon(Icons.arrow_back, size: 20)),
          Expanded(
            child: Text(tr(_elementLabel(e)),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(tooltip: tr('Đưa lên trên'), onPressed: () => _moveLayer(1), icon: const Icon(Icons.flip_to_front, size: 20)),
          IconButton(tooltip: tr('Đưa xuống dưới'), onPressed: () => _moveLayer(-1), icon: const Icon(Icons.flip_to_back, size: 20)),
          IconButton(tooltip: tr('Nhân bản (Ctrl+D)'), onPressed: _duplicateSel, icon: const Icon(Icons.copy_all_outlined, size: 20)),
          IconButton(
              tooltip: tr('Xóa (Delete)'),
              onPressed: _deleteSel,
              icon: const Icon(Icons.delete_outline, size: 20, color: SboxColors.danger)),
        ]),
      ),
      if (e.type == PosLabelElementType.text ||
          e.type == PosLabelElementType.barcode ||
          e.type == PosLabelElementType.qr) ...[
        _sectionTitle(switch (e.type) {
          PosLabelElementType.barcode => 'NỘI DUNG MÃ VẠCH',
          PosLabelElementType.qr => 'NỘI DUNG MÃ QR',
          _ => 'NỘI DUNG',
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: _TokenTextField(
            key: ValueKey('txt-${e.id}'),
            value: e.text,
            fields: fields,
            multiline: e.type != PosLabelElementType.barcode,
            onChanged: (v) => _updateSel((x) => x.copyWith(text: v), history: false),
          ),
        ),
      ],
      if (e.type == PosLabelElementType.text) ...[
        _sectionTitle('CHỮ'),
        _row([
          _NumField(
              label: 'Cỡ chữ (pt)', value: e.fontSize, min: 3, max: 72, onChanged: (v) => _updateSel((x) => x.copyWith(fontSize: v))),
          _IntDrop(
              label: 'Số dòng tối đa',
              value: e.maxLines,
              items: const [1, 2, 3, 4, 5, 6],
              onChanged: (v) => _updateSel((x) => x.copyWith(maxLines: v))),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FilterChip(
                label: Text(tr('Đậm')), selected: e.bold, onSelected: (v) => _updateSel((x) => x.copyWith(bold: v))),
            FilterChip(
                label: Text(tr('Nền đen chữ trắng')),
                selected: e.invert,
                onSelected: (v) => _updateSel((x) => x.copyWith(invert: v))),
            FilterChip(
                label: Text(tr('Tự thu nhỏ cho vừa')),
                selected: e.autoShrink,
                onSelected: (v) => _updateSel((x) => x.copyWith(autoShrink: v))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          child: Row(children: [
            Expanded(
              child: SegmentedButton<PosLabelAlign>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PosLabelAlign.left, icon: Icon(Icons.format_align_left, size: 18)),
                  ButtonSegment(value: PosLabelAlign.center, icon: Icon(Icons.format_align_center, size: 18)),
                  ButtonSegment(value: PosLabelAlign.right, icon: Icon(Icons.format_align_right, size: 18)),
                ],
                selected: {e.align},
                onSelectionChanged: (s) => _updateSel((x) => x.copyWith(align: s.first)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SegmentedButton<PosLabelVAlign>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PosLabelVAlign.top, icon: Icon(Icons.vertical_align_top, size: 18)),
                  ButtonSegment(value: PosLabelVAlign.middle, icon: Icon(Icons.vertical_align_center, size: 18)),
                  ButtonSegment(value: PosLabelVAlign.bottom, icon: Icon(Icons.vertical_align_bottom, size: 18)),
                ],
                selected: {e.vAlign},
                onSelectionChanged: (s) => _updateSel((x) => x.copyWith(vAlign: s.first)),
              ),
            ),
          ]),
        ),
      ],
      if (e.type == PosLabelElementType.barcode)
        SwitchListTile(
          dense: true,
          title: Text(tr('In số dưới mã vạch')),
          value: e.showText,
          onChanged: (v) => _updateSel((x) => x.copyWith(showText: v)),
        ),
      if (e.type == PosLabelElementType.image)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: OutlinedButton.icon(
            onPressed: () async {
              final data = await _pickImageData(e.w);
              if (data == null) return;
              _updateSel((x) => x.copyWith(imageData: data));
              unawaited(_reloadImages());
            },
            icon: const Icon(Icons.image_outlined),
            label: Text(tr('Đổi ảnh')),
          ),
        ),
      if (e.type == PosLabelElementType.line || e.type == PosLabelElementType.box) ...[
        _row([
          _NumField(
              label: 'Độ dày nét (mm)',
              value: e.strokeMm,
              min: 0.1,
              max: 5,
              onChanged: (v) => _updateSel((x) => x.copyWith(strokeMm: v))),
        ]),
        if (e.type == PosLabelElementType.box)
          SwitchListTile(
            dense: true,
            title: Text(tr('Tô đen cả ô')),
            value: e.filled,
            onChanged: (v) => _updateSel((x) => x.copyWith(filled: v)),
          ),
      ],
      _sectionTitle('VỊ TRÍ & KÍCH THƯỚC (mm)'),
      _row([
        _NumField(label: 'Trái (X)', value: e.x, min: -200, max: 300, onChanged: (v) => _updateSel((x) => x.copyWith(x: v))),
        _NumField(label: 'Trên (Y)', value: e.y, min: -200, max: 300, onChanged: (v) => _updateSel((x) => x.copyWith(y: v))),
      ]),
      _row([
        _NumField(label: 'Rộng', value: e.w, min: 1, max: 300, onChanged: (v) => _updateSel((x) => x.copyWith(w: v))),
        _NumField(label: 'Cao', value: e.h, min: 0.5, max: 300, onChanged: (v) => _updateSel((x) => x.copyWith(h: v))),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          ActionChip(
              label: Text(tr('Căn giữa ngang')),
              onPressed: () => _updateSel((x) => x.copyWith(x: _snapV((_d.widthMm - x.w) / 2)))),
          ActionChip(
              label: Text(tr('Căn giữa dọc')),
              onPressed: () => _updateSel((x) => x.copyWith(y: _snapV((_d.heightMm - x.h) / 2)))),
          ActionChip(
              label: Text(tr('Rộng hết tem')),
              onPressed: () => _updateSel((x) => x.copyWith(x: 1.5, w: _d.widthMm - 3))),
          ActionChip(
              label: Text(tr('Xoay ${(e.rotation + 90) % 360}°')),
              onPressed: () => _updateSel((x) => x.copyWith(rotation: (x.rotation + 90) % 360))),
        ]),
      ),
    ];
  }
}

/// Vẽ tem + khung chọn + đường căn trên màn soạn.
class _CanvasPainter extends CustomPainter {
  _CanvasPainter({
    required this.design,
    required this.data,
    required this.pxPerMm,
    required this.images,
    required this.selected,
    required this.guideX,
    required this.guideY,
  });

  final PosLabelDesign design;
  final Map<String, String> data;
  final double pxPerMm;
  final Map<String, ui.Image> images;
  final PosLabelElement? selected;
  final List<double> guideX;
  final List<double> guideY;

  @override
  void paint(Canvas canvas, Size size) {
    PosLabelDesignPainter.paint(canvas, design, data, pxPerMm, images: images, placeholders: true);
    // Lưới 1 mm mờ
    final grid = Paint()..color = const Color(0x0F2563EB);
    if (pxPerMm >= 6) {
      for (var x = 5.0; x < design.widthMm; x += 5) {
        canvas.drawLine(Offset(x * pxPerMm, 0), Offset(x * pxPerMm, size.height), grid);
      }
      for (var y = 5.0; y < design.heightMm; y += 5) {
        canvas.drawLine(Offset(0, y * pxPerMm), Offset(size.width, y * pxPerMm), grid);
      }
    }
    // Khung các phần tử (mờ) để biết ô nằm đâu
    final outline = Paint()
      ..color = const Color(0x332563EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final e in design.elements) {
      canvas.drawRect(Rect.fromLTWH(e.x * pxPerMm, e.y * pxPerMm, e.w * pxPerMm, e.h * pxPerMm), outline);
    }
    final s = selected;
    if (s != null) {
      final r = Rect.fromLTWH(s.x * pxPerMm, s.y * pxPerMm, s.w * pxPerMm, s.h * pxPerMm);
      canvas.drawRect(
          r,
          Paint()
            ..color = const Color(0xFF2563EB)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      canvas.drawCircle(r.bottomRight, 7, Paint()..color = Colors.white);
      canvas.drawCircle(r.bottomRight, 5, Paint()..color = const Color(0xFF2563EB));
    }
    final guide = Paint()
      ..color = const Color(0xFFE11D48)
      ..strokeWidth = 1;
    for (final x in guideX) {
      canvas.drawLine(Offset(x * pxPerMm, 0), Offset(x * pxPerMm, size.height), guide);
    }
    for (final y in guideY) {
      canvas.drawLine(Offset(0, y * pxPerMm), Offset(size.width, y * pxPerMm), guide);
    }
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = SboxColors.slate300
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter old) => true;
}

/// Ô số (mm / pt) — gõ số, Enter / rời ô là áp dụng; số bên ngoài đổi (kéo trên tem) thì cập nhật lại.
class _NumField extends StatefulWidget {
  const _NumField({required this.label, required this.value, required this.onChanged, this.min = 0, this.max = 999});
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  State<_NumField> createState() => _NumFieldState();
}

class _NumFieldState extends State<_NumField> {
  late final TextEditingController _c = TextEditingController(text: _fmt(widget.value));
  final _f = FocusNode();

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  void initState() {
    super.initState();
    _f.addListener(() {
      if (!_f.hasFocus) _apply();
    });
  }

  @override
  void didUpdateWidget(covariant _NumField old) {
    super.didUpdateWidget(old);
    if (!_f.hasFocus && _fmt(widget.value) != _c.text) _c.text = _fmt(widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  void _apply() {
    final v = double.tryParse(_c.text.replaceAll(',', '.').trim());
    if (v == null) {
      _c.text = _fmt(widget.value);
      return;
    }
    final clamped = v.clamp(widget.min, widget.max).toDouble();
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        focusNode: _f,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        decoration: InputDecoration(labelText: tr(widget.label), isDense: true, border: const OutlineInputBorder()),
        onSubmitted: (_) => _apply(),
      );
}

class _IntDrop extends StatelessWidget {
  const _IntDrop({required this.label, required this.value, required this.items, required this.onChanged});
  final String label;
  final int value;
  final List<int> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        value: items.contains(value) ? value : items.first,
        isDense: true,
        decoration: InputDecoration(labelText: tr(label), isDense: true, border: const OutlineInputBorder()),
        items: [for (final i in items) DropdownMenuItem(value: i, child: Text('$i'))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
}

/// Ô nội dung có nút «Chèn trường» (chèn {Token} tại con trỏ).
class _TokenTextField extends StatefulWidget {
  const _TokenTextField({
    super.key,
    required this.value,
    required this.fields,
    required this.onChanged,
    this.multiline = true,
  });
  final String value;
  final List<(String, String)> fields;
  final ValueChanged<String> onChanged;
  final bool multiline;

  @override
  State<_TokenTextField> createState() => _TokenTextFieldState();
}

class _TokenTextFieldState extends State<_TokenTextField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _insert(String token) {
    final sel = _c.selection;
    final text = _c.text;
    final at = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final next = text.replaceRange(at, end, '{$token}');
    _c.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: at + token.length + 2));
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _c,
          minLines: 1,
          maxLines: widget.multiline ? 4 : 1,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          onChanged: widget.onChanged,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<String>(
            tooltip: tr('Chèn trường dữ liệu'),
            onSelected: _insert,
            itemBuilder: (_) => [for (final f in widget.fields) PopupMenuItem(value: f.$1, child: Text(tr(f.$2)))],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_circle_outline, size: 18, color: SboxColors.primary),
                const SizedBox(width: 4),
                Text(tr('Chèn trường dữ liệu'),
                    style: const TextStyle(color: SboxColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ]);
}

/// Chọn một hàng để xem thử tem với dữ liệu thật.
class _ProductPickDialog extends StatefulWidget {
  const _ProductPickDialog();

  @override
  State<_ProductPickDialog> createState() => _ProductPickDialogState();
}

class _ProductPickDialogState extends State<_ProductPickDialog> {
  final _api = ApiService();
  List<PosProduct> _items = [];
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    final res = await _api.getPosProducts(search: q.trim().isEmpty ? null : q.trim(), pageSize: 30);
    if (!mounted || seq != _seq) return;
    final raw = res['isSuccess'] == true && res['data'] is Map ? ((res['data'] as Map)['items'] as List? ?? const []) : const [];
    setState(() => _items = raw.map((e) => PosProduct.fromJson(Map<String, dynamic>.from(e as Map))).toList());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Xem thử với hàng')),
        content: SizedBox(
          width: 460,
          height: 420,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                  isDense: true, prefixIcon: const Icon(Icons.search), hintText: tr('Tìm tên, mã hàng, mã vạch'), border: const OutlineInputBorder()),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(children: [
                for (final p in _items)
                  ListTile(
                    dense: true,
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${p.productCode}${(p.barcode ?? '').isNotEmpty ? ' · ${p.barcode}' : ''}'),
                    onTap: () => Navigator.pop(context, p),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng')))],
      );
}
