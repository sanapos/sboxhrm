import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import 'pos_numeric_keypad.dart';
import 'pos_theme.dart';

class PosLineQtyResult {
  const PosLineQtyResult({
    required this.qty,
    required this.decimal,
    this.areaNote,
  });

  final double qty;
  final bool decimal;

  /// `Dài 2,5 m · Rộng 1,2 m` khi nhập theo diện tích.
  final String? areaNote;
}

final _areaNotePattern = RegExp(
  r'^Dài\s+\d+(?:[.,]\d+)?(?:\s+\S+)?\s+·\s+Rộng\s+\d+(?:[.,]\d+)?',
  caseSensitive: false,
);

/// Thay ghi chú kích thước cũ, giữ các ghi chú khác.
String mergePosAreaLineNote(String? existing, String areaNote) {
  final parts = (existing ?? '')
      .split(RegExp(r'[;\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !_areaNotePattern.hasMatch(s))
      .toList();
  final note = areaNote.trim();
  if (note.isNotEmpty) parts.add(note);
  return parts.join('; ');
}

String _dimUnit(String unitName) {
  final raw = unitName.trim();
  final u = raw.toLowerCase().replaceAll('²', '2').replaceAll(' ', '');
  if (u == 'm2' || u == 'met2' || u == 'mét2') return 'm';
  return raw;
}

String _noteNumber(double v) {
  var s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

String _qtyNumber(double v) {
  var s = v.toStringAsFixed(4);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

double? _parseDim(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (v == null || v <= 0) return null;
  return v;
}

({double length, double width})? _parseExistingArea(String? note) {
  if (note == null || note.trim().isEmpty) return null;
  final re = RegExp(
    r'Dài\s+(\d+(?:[.,]\d+)?)\s*(?:\S+\s+)?·\s*Rộng\s+(\d+(?:[.,]\d+)?)',
    caseSensitive: false,
  );
  final m = re.firstMatch(note);
  if (m == null) return null;
  final length = _parseDim(m.group(1)!);
  final width = _parseDim(m.group(2)!);
  if (length == null || width == null) return null;
  return (length: length, width: width);
}

Future<PosLineQtyResult?> showPosLineQtyDialog({
  required BuildContext context,
  required String productName,
  required String unitName,
  required double initialQty,
  required bool allowDecimal,
  required bool enterByArea,
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
    this.serialOnly = false,
    this.existingNote,
  });

  final String productName;
  final String unitName;
  final double initialQty;
  final bool allowDecimal;
  final bool enterByArea;
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

  String get _unit => _dimUnit(widget.unitName);

  @override
  void initState() {
    super.initState();
    _decimal = widget.allowDecimal;
    final parsed =
        widget.enterByArea ? _parseExistingArea(widget.existingNote) : null;
    _area = widget.enterByArea;
    if (_area) _decimal = true;
    _qtyCtrl = TextEditingController(
      text: _qtyNumber(widget.initialQty),
    );
    _lengthCtrl = TextEditingController(
      text: parsed == null ? '' : _qtyNumber(parsed.length),
    );
    _widthCtrl = TextEditingController(
      text: parsed == null ? '' : _qtyNumber(parsed.width),
    );
    _lengthCtrl.addListener(_syncArea);
    _widthCtrl.addListener(_syncArea);
  }

  @override
  void dispose() {
    _lengthCtrl.removeListener(_syncArea);
    _widthCtrl.removeListener(_syncArea);
    _qtyCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    super.dispose();
  }

  void _syncArea({bool rebuild = true}) {
    if (!_area) return;
    final length = _parseDim(_lengthCtrl.text);
    final width = _parseDim(_widthCtrl.text);
    final next = (length != null && width != null) ? _qtyNumber(length * width) : '';
    if (_qtyCtrl.text != next) _qtyCtrl.text = next;
    if (rebuild && mounted) setState(() {});
  }

  String? _areaNote() {
    final length = _parseDim(_lengthCtrl.text);
    final width = _parseDim(_widthCtrl.text);
    if (length == null || width == null) return null;
    final unit = _unit;
    final unitSuffix = unit.isEmpty ? '' : ' $unit';
    return 'Dài ${_noteNumber(length)}$unitSuffix · Rộng ${_noteNumber(width)}$unitSuffix';
  }

  void _apply() {
    if (_area) {
      final length = _parseDim(_lengthCtrl.text);
      final width = _parseDim(_widthCtrl.text);
      if (length == null || width == null) return;
      final note = _areaNote();
      if (note == null) return;
      Navigator.pop(
        context,
        PosLineQtyResult(
          qty: double.parse((length * width).toStringAsFixed(4)),
          decimal: true,
          areaNote: note,
        ),
      );
      return;
    }
    final v = _parseDim(_qtyCtrl.text);
    if (v == null) return;
    Navigator.pop(
      context,
      PosLineQtyResult(qty: v, decimal: _decimal),
    );
  }

  @override
  Widget build(BuildContext context) {
    final length = _parseDim(_lengthCtrl.text);
    final width = _parseDim(_widthCtrl.text);
    final area = (length != null && width != null) ? length * width : null;
    return AlertDialog(
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
              Text(
                tr(area == null
                    ? 'Diện tích = dài × rộng'
                    : 'Diện tích: ${_noteNumber(area)}${widget.unitName.trim().isEmpty ? '' : ' ${widget.unitName.trim()}'}'),
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
