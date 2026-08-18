import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'pos_form_keyboard.dart';
import 'pos_numeric_keypad.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const kPosDiscountPresets = [5, 10, 15, 20, 25, 30, 50, 75, 100];

/// Mệnh giá gợi ý cố định khi chưa có giá tham chiếu.
const kPosDiscountMoneyPresets = [
  10000,
  20000,
  50000,
  100000,
  200000,
  500000,
  1000000,
  2000000,
  5000000,
];

/// Gợi ý số tiền chiết khấu phù hợp với [baseAmount] (VNĐ).
List<int> posDiscountMoneyPresetsForAmount(double baseAmount) {
  if (baseAmount <= 0) return [1000, 2000, 5000];

  final max = baseAmount.round();
  final picked = <int>{};

  for (final pct in [5, 10, 15, 20, 25, 50]) {
    final v = (baseAmount * pct / 100).round();
    if (v > 0 && v <= max) picked.add(v);
  }

  const nice = [
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
    50000,
    100000,
    200000,
    500000,
    1000000,
    2000000,
    5000000,
  ];
  for (final v in nice) {
    if (v <= max) picked.add(v);
  }
  picked.add(max);

  final sorted = picked.toList()..sort();
  if (sorted.length <= 9) return sorted;

  final result = <int>[];
  for (var i = 0; i < 9; i++) {
    final idx = ((sorted.length - 1) * i / 8).round();
    result.add(sorted[idx]);
  }
  return result.toSet().toList()..sort();
}

const _kiotBlue = PosTheme.kiotBlue;
class PosDiscountEditResult {
  const PosDiscountEditResult({
    required this.input,
    required this.isPercent,
    required this.amount,
  });

  final double input;
  final bool isPercent;
  final double amount;
}

/// Dialog chỉnh chiết khấu với gợi ý % nhanh.
Future<PosDiscountEditResult?> showPosDiscountEditorDialog({
  required BuildContext context,
  required String title,
  required double baseAmount,
  double initialInput = 0,
  bool initialIsPercent = false,
}) async {
  final ctrl = TextEditingController(
    text: tr(initialInput == 0
        ? ''
        : (initialIsPercent
            ? (initialInput % 1 == 0
                ? initialInput.toStringAsFixed(0)
                : initialInput.toStringAsFixed(2))
            : NumberFormat('#,##0', 'vi_VN').format(initialInput))),
  );
  var isPercent = initialIsPercent;
  final moneyFmt = NumberFormat('#,##0', 'vi_VN');

  double computeAmount(String raw) {
    final v = double.tryParse(raw.replaceAll(',', '').replaceAll('%', '')) ?? 0;
    if (isPercent) {
      return (baseAmount * v / 100).clamp(0, baseAmount);
    }
    return v.clamp(0, baseAmount);
  }

  final result = await showDialog<PosDiscountEditResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        final preview = computeAmount(ctrl.text);
        return AlertDialog(
          title: Text(tr(title)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _modeChip('%', true, isPercent, () => setDlg(() {
                          isPercent = true;
                          ctrl.text = ctrl.text.replaceAll(',', '');
                        })),
                    const SizedBox(width: 6),
                    _modeChip('đ', false, isPercent, () => setDlg(() {
                          isPercent = false;
                        })),
                    const Spacer(),
                    Text(tr('Tối đa: ${moneyFmt.format(baseAmount)}'),
                      style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PosNoSoftKeyboardField(
                  controller: ctrl,
                  autofocus: true,
                  allowDecimal: true,
                  keypadTitle: isPercent ? 'Chiết khấu %' : 'Chiết khấu tiền',
                  decoration: InputDecoration(
                    labelText: tr(isPercent ? 'Phần trăm (%)' : 'Số tiền (đ)'),
                    border: const OutlineInputBorder(),
                    suffixText: tr(isPercent ? '%' : 'đ'),
                  ),
                  onChanged: (_) => setDlg(() {}),
                ),
                const SizedBox(height: 8),
                if (isPercent)
                  buildPosDiscountPresetChips(
                    onPickPercent: (p) => setDlg(() {
                      isPercent = true;
                      ctrl.text = p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
                    }),
                  )
                else
                  buildPosDiscountMoneyPresetChips(
                    moneyFmt: moneyFmt,
                    baseAmount: baseAmount,
                    onPickAmount: (a) => setDlg(() {
                      isPercent = false;
                      ctrl.text = moneyFmt.format(a);
                    }),
                  ),
                if (preview > 0) ...[
                  const SizedBox(height: 10),
                  Text(tr('Chiết khấu: -${moneyFmt.format(preview)}'),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
            FilledButton(
              onPressed: () {
                final raw = ctrl.text.replaceAll(',', '').replaceAll('%', '');
                final input = double.tryParse(raw) ?? 0;
                Navigator.pop(
                  ctx,
                  PosDiscountEditResult(
                    input: input,
                    isPercent: isPercent,
                    amount: computeAmount(ctrl.text),
                  ),
                );
              },
              style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
              child: Text(tr('Áp dụng')),
            ),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
  return result;
}

/// Bottom sheet chỉnh chiết khấu — tối ưu mobile.
Future<PosDiscountEditResult?> showPosDiscountEditorSheet({
  required BuildContext context,
  required String title,
  required double baseAmount,
  double initialInput = 0,
  bool initialIsPercent = false,
}) {
  return showModalBottomSheet<PosDiscountEditResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: posImeBottomPad(ctx)),
      child: _PosDiscountEditorBody(
        title: title,
        baseAmount: baseAmount,
        initialInput: initialInput,
        initialIsPercent: initialIsPercent,
        onDone: (r) => Navigator.pop(ctx, r),
        onCancel: () => Navigator.pop(ctx),
      ),
    ),
  );
}

class _PosDiscountEditorBody extends StatefulWidget {
  const _PosDiscountEditorBody({
    required this.title,
    required this.baseAmount,
    required this.initialInput,
    required this.initialIsPercent,
    required this.onDone,
    required this.onCancel,
  });

  final String title;
  final double baseAmount;
  final double initialInput;
  final bool initialIsPercent;
  final ValueChanged<PosDiscountEditResult> onDone;
  final VoidCallback onCancel;

  @override
  State<_PosDiscountEditorBody> createState() => _PosDiscountEditorBodyState();
}

class _PosDiscountEditorBodyState extends State<_PosDiscountEditorBody> {
  late final TextEditingController ctrl;
  late bool isPercent;
  final moneyFmt = NumberFormat('#,##0', 'vi_VN');

  @override
  void initState() {
    super.initState();
    isPercent = widget.initialIsPercent;
    ctrl = TextEditingController(
      text: tr(widget.initialInput == 0
          ? ''
          : (widget.initialIsPercent
              ? widget.initialInput.toStringAsFixed(
                  widget.initialInput % 1 == 0 ? 0 : 2)
              : moneyFmt.format(widget.initialInput))),
    );
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  double computeAmount(String raw) {
    final v = double.tryParse(raw.replaceAll(',', '').replaceAll('%', '')) ?? 0;
    if (isPercent) {
      return (widget.baseAmount * v / 100).clamp(0, widget.baseAmount);
    }
    return v.clamp(0, widget.baseAmount);
  }

  @override
  Widget build(BuildContext context) {
    final preview = computeAmount(ctrl.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr(widget.title),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              _modeChip('%', true, isPercent, () => setState(() {
                    isPercent = true;
                    ctrl.text = ctrl.text.replaceAll(',', '');
                  })),
              const SizedBox(width: 6),
              _modeChip('đ', false, isPercent, () => setState(() => isPercent = false)),
              const Spacer(),
              Text(tr('Tối đa: ${moneyFmt.format(widget.baseAmount)}'),
                style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr(isPercent ? 'Phần trăm (%)' : 'Số tiền (đ)'),
              border: const OutlineInputBorder(),
              suffixText: tr(isPercent ? '%' : 'đ'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (isPercent)
            buildPosDiscountPresetChips(
              onPickPercent: (p) => setState(() {
                isPercent = true;
                ctrl.text = p % 1 == 0 ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
              }),
            )
          else
            buildPosDiscountMoneyPresetChips(
              moneyFmt: moneyFmt,
              baseAmount: widget.baseAmount,
              onPickAmount: (a) => setState(() {
                isPercent = false;
                ctrl.text = moneyFmt.format(a);
              }),
            ),
          if (preview > 0) ...[
            const SizedBox(height: 10),
            Text(tr('Chiết khấu: -${moneyFmt.format(preview)}'),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 13, color: Colors.red.shade700),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(onPressed: widget.onCancel, child: Text(tr('Huỷ'))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    final raw = ctrl.text.replaceAll(',', '').replaceAll('%', '');
                    final input = double.tryParse(raw) ?? 0;
                    widget.onDone(PosDiscountEditResult(
                      input: input,
                      isPercent: isPercent,
                      amount: computeAmount(ctrl.text),
                    ));
                  },
                  style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                  child: Text(tr('Áp dụng')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Widget _modeChip(String label, bool value, bool selected, VoidCallback onTap) {
  final active = selected == value;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? PosTheme.kiotBlueLight : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: active ? _kiotBlue : PosTheme.border),
      ),
      child: Text(
        tr(label),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? _kiotBlue : PosTheme.textSecondary,
        ),
      ),
    ),
  );
}

/// Hàng chip gợi ý % — giãn đều full chiều ngang.
Widget buildPosDiscountPresetChips({
  required ValueChanged<double> onPickPercent,
  List<int>? percents,
}) {
  final values = percents ?? kPosDiscountPresets;
  if (values.length <= 6) {
    return Row(
      children: values.map((p) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _discountChip('$p%', () => onPickPercent(p.toDouble())),
          ),
        );
      }).toList(),
    );
  }
  return Wrap(
    spacing: 4,
    runSpacing: 4,
    children: values.map((p) {
      return SizedBox(
        width: 44,
        child: _discountChip('$p%', () => onPickPercent(p.toDouble())),
      );
    }).toList(),
  );
}

/// Hàng chip gợi ý số tiền VNĐ — theo [baseAmount] nếu có.
Widget buildPosDiscountMoneyPresetChips({
  required NumberFormat moneyFmt,
  required ValueChanged<double> onPickAmount,
  double? baseAmount,
}) {
  final amounts = baseAmount != null && baseAmount > 0
      ? posDiscountMoneyPresetsForAmount(baseAmount)
      : kPosDiscountMoneyPresets;

  if (amounts.length <= 6) {
    return Row(
      children: amounts.map((amount) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _discountChip(
              _compactVndLabel(amount, moneyFmt),
              () => onPickAmount(amount.toDouble()),
            ),
          ),
        );
      }).toList(),
    );
  }

  return Wrap(
    spacing: 4,
    runSpacing: 4,
    children: amounts.map((amount) {
      return SizedBox(
        width: 72,
        child: _discountChip(
          _compactVndLabel(amount, moneyFmt),
          () => onPickAmount(amount.toDouble()),
        ),
      );
    }).toList(),
  );
}

String _compactVndLabel(int amount, NumberFormat moneyFmt) {
  if (amount >= 1000000 && amount % 1000000 == 0) {
    return '${amount ~/ 1000000}tr';
  }
  if (amount >= 1000 && amount % 1000 == 0) {
    return '${amount ~/ 1000}k';
  }
  return moneyFmt.format(amount);
}

Widget _discountChip(String label, VoidCallback onTap) {
  return Material(
    color: PosTheme.kiotBlueLight,
    borderRadius: BorderRadius.circular(4),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _kiotBlue.withValues(alpha: 0.25)),
        ),
        child: Text(
          tr(label),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _kiotBlue,
          ),
        ),
      ),
    ),
  );
}
