class PosAreaDims {
  const PosAreaDims({this.length, this.width, this.height});

  final double? length;
  final double? width;
  final double? height;

  /// Nhân các chiều đã nhập. Cần ít nhất hai chiều.
  double? get measure {
    final parts = [length, width, height].whereType<double>().toList();
    if (parts.length < 2) return null;
    var product = 1.0;
    for (final v in parts) {
      product *= v;
    }
    return product;
  }
}

double? parsePosDim(String raw) {
  final v = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (v == null || v <= 0) return null;
  return v;
}

String formatPosDim(double? value) {
  if (value == null || value <= 0) return '';
  var s = value.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s.replaceAll('.', ',');
}

PosAreaDims parsePosAreaDims(String? note) {
  if (note == null || note.trim().isEmpty) return const PosAreaDims();
  double? read(String label) {
    final m = RegExp(
      '$label\\s+(\\d+(?:[.,]\\d+)?)',
      caseSensitive: false,
    ).firstMatch(note);
    if (m == null) return null;
    return parsePosDim(m.group(1)!);
  }

  return PosAreaDims(
    length: read('Dài'),
    width: read('Rộng'),
    height: read('Cao'),
  );
}

String? buildPosAreaNote({
  double? length,
  double? width,
  double? height,
  String unit = '',
}) {
  final suffix = unit.trim().isEmpty ? '' : ' ${unit.trim()}';
  final bits = <String>[];
  if (length != null) bits.add('Dài ${formatPosDim(length)}$suffix');
  if (width != null) bits.add('Rộng ${formatPosDim(width)}$suffix');
  if (height != null) bits.add('Cao ${formatPosDim(height)}$suffix');
  if (bits.length < 2) return null;
  return bits.join(' · ');
}

final _areaNotePattern = RegExp(
  r'^(?:Dài|Rộng|Cao)\s+\d+(?:[.,]\d+)?(?:\s+\S+)?(?:\s+·\s+(?:Dài|Rộng|Cao)\s+\d+(?:[.,]\d+)?(?:\s+\S+)?)+',
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
