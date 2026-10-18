import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../utils/pos_area_dims.dart';
import 'pos_numeric_keypad.dart';
import 'pos_theme.dart';

export '../../utils/pos_area_dims.dart'
    show mergePosAreaLineNote, parsePosAreaDims;

class PosLineQtyResult {
  const PosLineQtyResult({
    required this.qty,
    required this.decimal,
    this.areaNote,
    this.length,
    this.width,
    this.height,
  });

  final double qty;
  final bool decimal;

  /// `Dài 2,5 m · Rộng 1,2 m` hoặc `Rộng 1,2 m · Cao 2,4 m`.
  final String? areaNote;
  final double? length;
  final double? width;
  final double? height;
}

/// Đơn vị của từng chiều: hàng bán theo m² / «Cái» / «Bộ»… → «m». Chỉ giữ khi đơn vị bán
/// vốn là đơn vị dài (cm, mm, m). Trước đây ghi chú ra «Rộng 1,2 Cái».
String _dimUnit(String unitName) {
  final raw = unitName.trim();
  final u = raw.toLowerCase().replaceAll('²', '2').replaceAll(' ', '');
  if (const {'m', 'cm', 'mm', 'mét', 'met'}.contains(u)) return raw;
  return 'm';
}

String _qtyNumber(double v) {
  var s = v.toStringAsFixed(4);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

Future<PosLineQtyResult?> showPosLineQtyDialog({
  required BuildContext context,
  required String productName,
  required String unitName,
  required double initialQty,
  required bool allowDecimal,
  required bool enterByArea,
  bool askLength = true,
  bool askWidth = true,
  bool askHeight = true,
  bool serialOnly = false,
  String? existingNote,
  /// Để nhớ kích thước hay dùng của từng hàng (chip chọn nhanh).
  String? productId,
  /// Kích thước chọn nhanh cài cho hàng trong form hàng hóa.
  List<double> quickSizes = const [],
}) {
  return showDialog<PosLineQtyResult>(
    context: context,
    builder: (ctx) => _PosLineQtyDialog(
      productName: productName,
      unitName: unitName,
      initialQty: initialQty,
      allowDecimal: allowDecimal,
      enterByArea: enterByArea,
      askLength: askLength,
      askWidth: askWidth,
      askHeight: askHeight,
      serialOnly: serialOnly,
      existingNote: existingNote,
      productId: productId,
      quickSizes: quickSizes,
    ),
  );
}

const _kRecentDimMax = 6;

String _recentDimKey(String productId, String axis) => 'pos_area_recent_${productId}_$axis';

class _PosLineQtyDialog extends StatefulWidget {
  const _PosLineQtyDialog({
    required this.productName,
    required this.unitName,
    required this.initialQty,
    required this.allowDecimal,
    required this.enterByArea,
    this.askLength = true,
    this.askWidth = true,
    this.askHeight = true,
    this.serialOnly = false,
    this.existingNote,
    this.productId,
    this.quickSizes = const [],
  });

  final String? productId;
  final List<double> quickSizes;
  final String productName;
  final String unitName;
  final double initialQty;
  final bool allowDecimal;
  final bool enterByArea;
  final bool askLength;
  final bool askWidth;
  final bool askHeight;
  final bool serialOnly;
  final String? existingNote;

  @override
  State<_PosLineQtyDialog> createState() => _PosLineQtyDialogState();
}

class _PosLineQtyDialogState extends State<_PosLineQtyDialog> {
  late bool _decimal;
  late bool _area;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _lengthCtrl;
  late final TextEditingController _widthCtrl;
  late final TextEditingController _heightCtrl;

  String get _unit => _dimUnit(widget.unitName);

  /// Kích thước đã dùng gần đây cho hàng này, theo từng chiều (mới nhất trước).
  final Map<String, List<double>> _recent = {};

  @override
  void initState() {
    super.initState();
    _decimal = widget.allowDecimal;
    final parsed =
        widget.enterByArea ? parsePosAreaDims(widget.existingNote) : const PosAreaDims();
    _area = widget.enterByArea;
    if (_area) _decimal = true;
    _qtyCtrl = TextEditingController(
      text: _qtyNumber(widget.initialQty),
    );
    _lengthCtrl = TextEditingController(
      text: parsed.length == null ? '' : _qtyNumber(parsed.length!),
    );
    _widthCtrl = TextEditingController(
      text: parsed.width == null ? '' : _qtyNumber(parsed.width!),
    );
    _heightCtrl = TextEditingController(
      text: parsed.height == null ? '' : _qtyNumber(parsed.height!),
    );
    _lengthCtrl.addListener(_syncArea);
    _widthCtrl.addListener(_syncArea);
    _heightCtrl.addListener(_syncArea);
    if (_area) _loadRecent();
  }

  Future<void> _loadRecent() async {
    final id = widget.productId;
    if (id == null || id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = <String, List<double>>{};
      for (final axis in const ['length', 'width', 'height']) {
        next[axis] = (prefs.getStringList(_recentDimKey(id, axis)) ?? const [])
            .map(double.tryParse)
            .whereType<double>()
            .toList();
      }
      if (mounted) setState(() => _recent.addAll(next));
    } catch (_) {}
  }

  Future<void> _saveRecent(PosAreaDims dims) async {
    final id = widget.productId;
    if (id == null || id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = {'length': dims.length, 'width': dims.width, 'height': dims.height};
      for (final e in values.entries) {
        final v = e.value;
        if (v == null) continue;
        final list = [v, ...(_recent[e.key] ?? const <double>[]).where((x) => x != v)]
            .take(_kRecentDimMax)
            .map((x) => x.toString())
            .toList();
        await prefs.setStringList(_recentDimKey(id, e.key), list);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _lengthCtrl.removeListener(_syncArea);
    _widthCtrl.removeListener(_syncArea);
    _heightCtrl.removeListener(_syncArea);
    _qtyCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  PosAreaDims get _dims => PosAreaDims(
        length: _area ? parsePosDim(_lengthCtrl.text) : null,
        width: _area ? parsePosDim(_widthCtrl.text) : null,
        height: _area ? parsePosDim(_heightCtrl.text) : null,
      );

  void _syncArea({bool rebuild = true}) {
    if (!_area) return;
    final measure = _dims.measure;
    final next = measure == null ? '' : _qtyNumber(measure);
    if (_qtyCtrl.text != next) _qtyCtrl.text = next;
    if (rebuild && mounted) setState(() {});
  }

  String? _areaNote() {
    final dims = _dims;
    return buildPosAreaNote(
      length: dims.length,
      width: dims.width,
      height: dims.height,
      unit: _unit,
    );
  }

  void _apply() {
    if (_area) {
      final dims = _dims;
      final measure = dims.measure;
      final note = _areaNote();
      if (measure == null || note == null) return;
      unawaited(_saveRecent(dims));
      Navigator.pop(
        context,
        PosLineQtyResult(
          qty: double.parse(measure.toStringAsFixed(4)),
          decimal: true,
          areaNote: note,
          length: dims.length,
          width: dims.width,
          height: dims.height,
        ),
      );
      return;
    }
    final v = parsePosDim(_qtyCtrl.text);
    if (v == null) return;
    Navigator.pop(
      context,
      PosLineQtyResult(qty: v, decimal: _decimal),
    );
  }

  /// Ô nhập một chiều + chip chọn nhanh: kích thước cài cho hàng, rồi kích thước
  /// hay dùng trên máy này (biểu tượng lịch sử).
  Widget _dimField(String label, String axis, TextEditingController ctrl) {
    final preset = widget.quickSizes;
    final recent = (_recent[axis] ?? const <double>[])
        .where((v) => !preset.contains(v))
        .toList();
    final sizes = <double>[...preset, ...recent].take(14).toList();
    final current = parsePosDim(ctrl.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          PosNoSoftKeyboardField(
            controller: ctrl,
            allowDecimal: true,
            keypadTitle: label,
            decoration: InputDecoration(
              labelText: tr(label),
              suffixText: _unit.isEmpty ? null : _unit,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (sizes.isNotEmpty) const SizedBox(height: 6),
          if (sizes.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final v in sizes)
                ChoiceChip(
                  label: Text(formatPosDim(v)),
                  selected: current == v,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: recent.contains(v)
                      ? const Icon(Icons.history, size: 14)
                      : null,
                  onSelected: (_) => ctrl.text = formatPosDim(v),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dims = _dims;
    final area = dims.measure;
    final unitLabel = widget.unitName.trim();
    // Chỉ hiện các chiều đã cài cho hàng (form hàng hóa); cài thiếu thì hiện đủ 3.
    final axes = [widget.askLength, widget.askWidth, widget.askHeight].where((v) => v).length;
    final showLength = axes < 2 || widget.askLength;
    final showWidth = axes < 2 || widget.askWidth;
    final showHeight = axes < 2 || widget.askHeight;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(tr('Số lượng')),
      // Rộng cố định: trước co theo nội dung → bấm chip kích thước (ẩn gợi ý) hộp thu hẹp, nút «Áp dụng» chạy chỗ.
      content: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 80).clamp(260.0, 440.0),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(widget.productName),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (widget.serialOnly) ...[
              const SizedBox(height: 8),
              Text(
                tr('Hàng seri chỉ bán số nguyên'),
                style: const TextStyle(
                  fontSize: 12,
                  color: PosTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (_area) ...[
              if (showLength) _dimField('Chiều dài', 'length', _lengthCtrl),
              if (showWidth) _dimField('Chiều rộng', 'width', _widthCtrl),
              if (showHeight) _dimField('Chiều cao', 'height', _heightCtrl),
              Text(
                tr(area == null
                    ? 'Nhập ít nhất 2 chiều. Diện tích = các ô đã nhập nhân với nhau (dài × rộng hoặc rộng × cao).'
                    : 'Diện tích: ${formatPosDim(area)}${_unit == 'm' ? ' m²' : (unitLabel.isEmpty ? '' : ' $unitLabel')}'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ] else
              PosNoSoftKeyboardField(
                controller: _qtyCtrl,
                allowDecimal: _decimal,
                autofocus: true,
                keypadTitle: 'Số lượng',
                decoration: InputDecoration(
                  labelText: tr('Số lượng'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Hủy')),
        ),
        FilledButton(
          onPressed: _apply,
          child: Text(tr('Áp dụng')),
        ),
      ],
    );
  }
}
