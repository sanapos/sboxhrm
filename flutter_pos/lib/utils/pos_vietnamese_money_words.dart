/// Đọc số tiền thành chữ tiếng Việt (đồng chẵn).
String vietnameseMoneyInWords(int amount) {
  if (amount < 0) amount = -amount;
  if (amount == 0) return 'Không đồng';

  const units = [
    '',
    ' nghìn',
    ' triệu',
    ' tỷ',
    ' nghìn tỷ',
    ' triệu tỷ',
  ];

  // Tách nhóm 3 chữ số từ thấp → cao.
  final rawGroups = <int>[];
  var n = amount;
  while (n > 0) {
    rawGroups.add(n % 1000);
    n ~/= 1000;
  }

  final parts = <String>[];
  for (var i = rawGroups.length - 1; i >= 0; i--) {
    final group = rawGroups[i];
    if (group == 0) continue;
    // Có nhóm cao hơn (đã/sẽ in) → cần «không trăm» / «lẻ» đúng chỗ.
    final hasHigher = rawGroups.skip(i + 1).any((g) => g != 0);
    final chunk = _readThreeDigits(group, hasHigher);
    final suffix = i < units.length ? units[i] : '';
    parts.add('$chunk$suffix');
  }

  final text = parts.join(' ').trim();
  if (text.isEmpty) return 'Không đồng';
  return '${_capitalizeFirst(text)} đồng chẵn';
}

String _capitalizeFirst(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

String _readThreeDigits(int n, bool hasHigherGroup) {
  final hundred = n ~/ 100;
  final ten = (n % 100) ~/ 10;
  final unit = n % 10;
  final parts = <String>[];

  if (hundred > 0) {
    parts.add('${_digitWord(hundred)} trăm');
  } else if (hasHigherGroup && (ten > 0 || unit > 0)) {
    parts.add('không trăm');
  }

  if (ten > 1) {
    parts.add('${_digitWord(ten)} mươi');
    if (unit == 1) {
      parts.add('mốt');
    } else if (unit == 5) {
      parts.add('lăm');
    } else if (unit > 0) {
      parts.add(_digitWord(unit));
    }
  } else if (ten == 1) {
    parts.add('mười');
    if (unit == 1) {
      parts.add('một');
    } else if (unit == 5) {
      parts.add('lăm');
    } else if (unit > 0) {
      parts.add(_digitWord(unit));
    }
  } else if (unit > 0) {
    if (hundred > 0 || hasHigherGroup) {
      parts.add('lẻ');
    }
    parts.add(_digitWord(unit));
  }

  return parts.join(' ');
}

String _digitWord(int d) {
  const words = [
    'không',
    'một',
    'hai',
    'ba',
    'bốn',
    'năm',
    'sáu',
    'bảy',
    'tám',
    'chín',
  ];
  if (d < 0 || d > 9) return '';
  return words[d];
}
