import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../utils/number_formatter.dart';
import '../../utils/pos_area_dims.dart';
import 'pos_theme.dart';

/// Tính giá hàng gia công theo m² — khớp server (PosQuotesController.AreaPricing).
class MadeToOrderPricing {
  MadeToOrderPricing._();

  /// Diện tích một bộ (m²) từ rộng × cao tính bằng mm.
  static double area(double? widthMm, double? heightMm) {
    if ((widthMm ?? 0) <= 0 || (heightMm ?? 0) <= 0) return 0;
    return (widthMm! * heightMm! / 1000000 * 10000).round() / 10000;
  }

  /// Giá một bộ = max(diện tích × đơn giá m², tối thiểu / bộ).
  static double setPrice(double areaM2, double pricePerM2, double? minPerSet) =>
      math.max((areaM2 * pricePerM2).roundToDouble(), minPerSet ?? 0);

  static final _m2 = NumberFormat('#,##0.###', 'vi_VN');
  static final _money = NumberFormat('#,##0', 'vi_VN');

  static String m2(double v) => _m2.format(v);

  /// Ghi chú giá: `DT 3,96 m²/bộ · 450.000đ/m² (tối thiểu 1.500.000đ/bộ)`.
  static String priceNote(double areaM2, double pricePerM2, double? minPerSet) {
    final min = (minPerSet ?? 0) > 0 ? ' (tối thiểu ${_money.format(minPerSet)}đ/bộ)' : '';
    return 'DT ${_m2.format(areaM2)} m²/bộ · ${_money.format(pricePerM2)}đ/m²$min';
  }

  static final _priceNotePattern = RegExp(r'^DT\s+\d', caseSensitive: false);

  /// Gộp ghi chú kích thước + ghi chú giá m² vào ghi chú dòng (thay bản cũ, giữ ghi chú khác).
  static String mergeNote(String? existing, {String? areaNote, String? priceNote}) {
    var merged = mergePosAreaLineNote(existing, areaNote ?? '');
    final parts = merged
        .split(RegExp(r'[;\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && !_priceNotePattern.hasMatch(s))
        .toList();
    if (priceNote != null && priceNote.trim().isNotEmpty) parts.add(priceNote.trim());
    return parts.join('; ');
  }
}

class MadeToOrderLineResult {
  const MadeToOrderLineResult({
    required this.widthMm,
    required this.heightMm,
    required this.sets,
    this.pricePerM2,
    this.minPerSet,
    required this.areaM2,
    required this.setPrice,
  });

  final double? widthMm;
  final double? heightMm;
  final double sets;
  final double? pricePerM2;
  final double? minPerSet;
  final double areaM2;

  /// Giá một bộ (đơn giá dòng). Null khi hàng tính theo bộ — giữ giá dòng hiện có.
  final double? setPrice;

  String? get areaNote =>
      buildPosAreaNote(width: widthMm, height: heightMm, unit: 'mm');

  String? get priceNote => (pricePerM2 ?? 0) > 0
      ? MadeToOrderPricing.priceNote(areaM2, pricePerM2!, minPerSet)
      : null;
}

/// Nhập một dòng hàng gia công: rộng × cao (mm), số bộ, đơn giá m² + tối thiểu / bộ.
Future<MadeToOrderLineResult?> showMadeToOrderLineDialog({
  required BuildContext context,
  required String productName,
  required bool priceByArea,
  double? widthMm,
  double? heightMm,
  double sets = 1,
  double? pricePerM2,
  double? minPerSet,
}) {
  return showDialog<MadeToOrderLineResult>(
    context: context,
    builder: (_) => _MadeToOrderLineDialog(
      productName: productName,
      priceByArea: priceByArea,
      widthMm: widthMm,
      heightMm: heightMm,
      sets: sets,
      pricePerM2: pricePerM2,
      minPerSet: minPerSet,
    ),
  );
}

class _MadeToOrderLineDialog extends StatefulWidget {
  const _MadeToOrderLineDialog({
    required this.productName,
    required this.priceByArea,
    this.widthMm,
    this.heightMm,
    required this.sets,
    this.pricePerM2,
    this.minPerSet,
  });

  final String productName;
  final bool priceByArea;
  final double? widthMm;
  final double? heightMm;
  final double sets;
  final double? pricePerM2;
  final double? minPerSet;

  @override
  State<_MadeToOrderLineDialog> createState() => _MadeToOrderLineDialogState();
}

class _MadeToOrderLineDialogState extends State<_MadeToOrderLineDialog> {
  static final _money = NumberFormat('#,##0', 'vi_VN');
  late final TextEditingController _w;
  late final TextEditingController _h;
  late final TextEditingController _sets;
  late final TextEditingController _perM2;
  late final TextEditingController _min;
  String? _error;

  @override
  void initState() {
    super.initState();
    String num0(double? v) => (v ?? 0) > 0 ? _money.format(v) : '';
    _w = TextEditingController(text: num0(widget.widthMm));
    _h = TextEditingController(text: num0(widget.heightMm));
    _sets = TextEditingController(text: formatPosDim(widget.sets <= 0 ? 1 : widget.sets));
    _perM2 = TextEditingController(text: num0(widget.pricePerM2));
    _min = TextEditingController(text: num0(widget.minPerSet));
  }

  @override
  void dispose() {
    _w.dispose();
    _h.dispose();
    _sets.dispose();
    _perM2.dispose();
    _min.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) {
    final v = parseFormattedNumber(c.text)?.toDouble();
    return v != null && v > 0 ? v : null;
  }

  double get _setsValue => parsePosDim(_sets.text) ?? 0;

  void _apply() {
    final w = _num(_w);
    final h = _num(_h);
    final sets = _setsValue;
    if (sets <= 0) {
      setState(() => _error = 'Số bộ phải lớn hơn 0');
      return;
    }
    final area = MadeToOrderPricing.area(w, h);
    double? perM2;
    double? min;
    double? setPrice;
    if (widget.priceByArea) {
      perM2 = _num(_perM2);
      min = _num(_min);
      if (perM2 == null) {
        setState(() => _error = 'Nhập đơn giá / m²');
        return;
      }
      if (area <= 0 && min == null) {
        setState(() => _error = 'Nhập rộng × cao (mm) hoặc giá tối thiểu / bộ');
        return;
      }
      setPrice = MadeToOrderPricing.setPrice(area, perM2, min);
    }
    Navigator.pop(
      context,
      MadeToOrderLineResult(
        widthMm: w,
        heightMm: h,
        sets: sets,
        pricePerM2: perM2,
        minPerSet: min,
        areaM2: area,
        setPrice: setPrice,
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? suffix, bool money = true, bool decimal = false}) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: money
          ? [ThousandSeparatorFormatter()]
          : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      onChanged: (_) => setState(() => _error = null),
      decoration: InputDecoration(
        labelText: tr(label),
        suffixText: suffix,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _num(_w);
    final h = _num(_h);
    final area = MadeToOrderPricing.area(w, h);
    final sets = _setsValue;
    final perM2 = _num(_perM2);
    final min = _num(_min);
    final setPrice =
        widget.priceByArea && perM2 != null ? MadeToOrderPricing.setPrice(area, perM2, min) : null;
    final minApplied = setPrice != null && min != null && (area * perM2!).round() < min;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Text(tr('Kích thước & số bộ')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(widget.productName), style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _field(_w, 'Rộng', suffix: 'mm')),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('×'),
                  ),
                  Expanded(child: _field(_h, 'Cao', suffix: 'mm')),
                ],
              ),
              const SizedBox(height: 10),
              _field(_sets, 'Số bộ', money: false, decimal: true),
              if (widget.priceByArea) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _field(_perM2, 'Đơn giá / m²', suffix: 'đ')),
                    const SizedBox(width: 8),
                    Expanded(child: _field(_min, 'Tối thiểu / bộ', suffix: 'đ')),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: PosTheme.kiotBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(area > 0
                          ? 'Diện tích: ${MadeToOrderPricing.m2(area)} m²/bộ · tổng ${MadeToOrderPricing.m2(area * sets)} m²'
                          : 'Nhập rộng × cao để tính diện tích'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (setPrice != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        tr('Giá 1 bộ: ${_money.format(setPrice)}đ${minApplied ? ' (áp giá tối thiểu)' : ''}'),
                        style: TextStyle(
                          fontSize: 13,
                          color: minApplied ? Colors.orange.shade800 : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('Thành tiền: ${_money.format(setPrice * sets)}đ'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(tr(_error!), style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(onPressed: _apply, child: Text(tr('Áp dụng'))),
      ],
    );
  }
}
