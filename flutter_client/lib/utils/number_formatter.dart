import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Formatter phân tách hàng nghìn khi nhập số (VD: 1.000.000)
class ThousandSeparatorFormatter extends TextInputFormatter {
  static final _fmt = NumberFormat('#,###', 'vi_VN');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final isNegative = newValue.text.startsWith('-');
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) {
      return isNegative
          ? newValue.copyWith(text: '-', selection: const TextSelection.collapsed(offset: 1))
          : const TextEditingValue();
    }
    final number = int.tryParse(digitsOnly);
    if (number == null) return newValue;
    final formatted = '${isNegative ? '-' : ''}${_fmt.format(number)}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Format số thành chuỗi phân tách hàng nghìn (VD: 1.000.000)
String formatNumber(dynamic v) {
  if (v == null) return '';
  final n = v is num ? v : num.tryParse(v.toString());
  if (n == null || n == 0) return '';
  return NumberFormat('#,###', 'vi_VN').format(n);
}

/// Parse chuỗi đã format về num (bỏ dấu phân tách)
num? parseFormattedNumber(String text) {
  if (text.isEmpty) return null;
  return num.tryParse(text.replaceAll(RegExp(r'[^\d\-]'), ''));
}
