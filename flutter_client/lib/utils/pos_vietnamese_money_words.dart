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

  final groups = <String>[];
  var n = amount;
  var groupIdx = 0;

  while (n > 0) {
    final group = n % 1000;
    if (group != 0) {
      final chunk = _readThreeDigits(group, groupIdx > 0);
      final suffix = groupIdx < units.length ? units[groupIdx] : '';
      groups.add('$chunk$suffix');
    }
    n ~/= 1000;
    groupIdx++;
  }

  // Nhóm thấp → cao khi tách; ghép ngược để "hai triệu … nghìn".
  final text = groups.reversed.join(' ').trim();
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
  const w = [
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
  return w[d.clamp(0, 9)];
}
