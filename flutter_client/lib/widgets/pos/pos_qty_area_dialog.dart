import 'package:flutter/material.dart';
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

String _dimUnit(String unitName) {
  final raw = unitName.trim();
  final u = raw.toLowerCase().replaceAll('²', '2').replaceAll(' ', '');
  if (u == 'm2' || u == 'met2' || u == 'mét2') return 'm';
  return raw;
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
    ),
  );
}

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
  });

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

  @override
  Widget build(BuildContext context) {
    final dims = _dims;
    final area = dims.measure;
    final unitLabel = widget.unitName.trim();
    final showLength = _area || widget.askLength;
    final showWidth = _area || widget.askWidth;
    final showHeight = _area || widget.askHeight;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(tr('Số lượng')),
      content: SingleChildScrollView(
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
              if (showLength)
              PosNoSoftKeyboardField(
                controller: _lengthCtrl,
                allowDecimal: true,
                keypadTitle: 'Chiều dài',
                decoration: InputDecoration(
                  labelText: tr('Chiều dài'),
                  suffixText: _unit.isEmpty ? null : _unit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              if (showWidth)
              PosNoSoftKeyboardField(
                controller: _widthCtrl,
                allowDecimal: true,
                keypadTitle: 'Chiều rộng',
                decoration: InputDecoration(
                  labelText: tr('Chiều rộng'),
                  suffixText: _unit.isEmpty ? null : _unit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              if (showHeight)
              PosNoSoftKeyboardField(
                controller: _heightCtrl,
                allowDecimal: true,
                keypadTitle: 'Chiều cao',
                decoration: InputDecoration(
                  labelText: tr('Chiều cao'),
                  suffixText: _unit.isEmpty ? null : _unit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(area == null
                    ? 'Nhập ít nhất 2 chiều. Diện tích = các ô đã nhập nhân với nhau (dài × rộng hoặc rộng × cao).'
                    : 'Diện tích: ${formatPosDim(area)}${unitLabel.isEmpty ? '' : ' $unitLabel'}'),
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
