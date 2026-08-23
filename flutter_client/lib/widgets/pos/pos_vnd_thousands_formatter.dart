import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Format tiền VND lúc gõ: `1000000` → `1.000.000` (locale vi_VN).
class PosVndThousandsFormatter extends TextInputFormatter {
  PosVndThousandsFormatter({this.maxDigits = 12});

  final int maxDigits;
  static final _fmt = NumberFormat('#,##0', 'vi_VN');

  /// Parse ô đã format (`1.000.000` / `1,000,000`) → số.
  static double parse(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return 0;
    return double.tryParse(digits) ?? 0;
  }

  static String format(num value) {
    if (value == 0) return '';
    return _fmt.format(value.round());
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length > maxDigits) {
      digits = digits.substring(0, maxDigits);
    }
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    // Bỏ số 0 đứng đầu (trừ khi chỉ còn 0).
    digits = digits.replaceFirst(RegExp(r'^0+(?=.)'), '');
    final n = int.tryParse(digits) ?? 0;
    final formatted = _fmt.format(n);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
