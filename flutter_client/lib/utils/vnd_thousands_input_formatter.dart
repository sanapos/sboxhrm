import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../l10n/app_tr.dart';

/// Nhập số tiền VND — hiển thị phân tách hàng nghìn (1.000.000).
class VndThousandsInputFormatter extends TextInputFormatter {
  VndThousandsInputFormatter({this.allowDecimal = false});

  final bool allowDecimal;
  static final _fmt = NumberFormat('#,##0', 'vi_VN');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    if (allowDecimal) {
      final cleaned = newValue.text.replaceAll(RegExp(r'[^\d.]'), '');
      final parts = cleaned.split('.');
      final intPart = int.tryParse(parts.first.replaceAll('.', '')) ??
          int.tryParse(parts.first);
      if (intPart == null && cleaned != '.') return oldValue;
      final buf = StringBuffer();
      if (intPart != null) {
        buf.write(_fmt.format(intPart));
      } else {
        buf.write('0');
      }
      if (parts.length > 1) {
        buf.write('.');
        buf.write(parts[1].replaceAll(RegExp(r'\D'), '').takeChars(2));
      } else if (cleaned.endsWith('.')) {
        buf.write('.');
      }
      final text = buf.toString();
      return TextEditingValue(
        text: tr(text),
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final number = int.tryParse(digits);
    if (number == null) return oldValue;
    final formatted = _fmt.format(number);
    return TextEditingValue(
      text: tr(formatted),
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String format(num value) {
    final n = value.round();
    return _fmt.format(n);
  }

  static double parse(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0;
  }
}

extension on String {
  String takeChars(int n) => length <= n ? this : substring(0, n);
}
