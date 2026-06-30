import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'pos_theme.dart';

const kPosDiscountPresets = [5, 10, 15, 20, 25, 30, 50, 75, 100];

/// Mệnh giá gợi ý khi chiết khấu theo tiền (VNĐ).
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

const _blue = Color(0xFF2563EB);

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
    text: initialInput == 0
        ? ''
        : (initialIsPercent
            ? (initialInput % 1 == 0
                ? initialInput.toStringAsFixed(0)
                : initialInput.toStringAsFixed(2))
            : NumberFormat('#,##0', 'vi_VN').format(initialInput)),
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
          title: Text(title),
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
                    Text(
                      'Tối đa: ${moneyFmt.format(baseAmount)}',
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
                    labelText: isPercent ? 'Phần trăm (%)' : 'Số tiền (đ)',
                    border: const OutlineInputBorder(),
                    suffixText: isPercent ? '%' : 'đ',
                  ),
                  onChanged: (_) => setDlg(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: kPosDiscountPresets.map((p) {
                    return ActionChip(
                      label: Text('$p%'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setDlg(() {
                          isPercent = true;
                          ctrl.text = '$p';
                        });
                      },
                    );
                  }).toList(),
                ),
                if (preview > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Chiết khấu: -${moneyFmt.format(preview)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
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
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: const Text('Áp dụng'),
            ),
          ],
        );
      },
    ),
  );
  ctrl.dispose();
  return result;
}

Widget _modeChip(String label, bool value, bool selected, VoidCallback onTap) {
  final active = selected == value;
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE8F0FE) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: active ? _blue : PosTheme.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: active ? _blue : PosTheme.textSecondary,
        ),
      ),
    ),
  );
}

/// Hàng chip gợi ý % — một dòng, cuộn ngang nếu thiếu chỗ.
Widget buildPosDiscountPresetChips({
  required ValueChanged<double> onPickPercent,
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: kPosDiscountPresets.map((p) {
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _discountChip('$p%', () => onPickPercent(p.toDouble())),
        );
      }).toList(),
    ),
  );
}

/// Hàng chip gợi ý số tiền VNĐ — một dòng.
Widget buildPosDiscountMoneyPresetChips({
  required NumberFormat moneyFmt,
  required ValueChanged<double> onPickAmount,
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: kPosDiscountMoneyPresets.map((amount) {
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: _discountChip(
            _compactVndLabel(amount, moneyFmt),
            () => onPickAmount(amount.toDouble()),
          ),
        );
      }).toList(),
    ),
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
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(4),
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: PosTheme.border),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
      ),
    ),
  );
}
