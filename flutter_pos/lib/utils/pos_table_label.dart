/// Nhãn bàn in phiếu / UI: «Nhóm · Tên bàn» (tránh trùng tên giữa các khu).
String formatPosTableLabel({
  String? areaName,
  String? tableName,
  String fallback = 'Bàn',
}) {
  final t = (tableName ?? '').trim();
  final a = (areaName ?? '').trim();
  if (t.isEmpty && a.isEmpty) return fallback;
  if (a.isEmpty) return t.isEmpty ? fallback : t;
  if (t.isEmpty) return a;
  return '$a · $t';
}

/// Một hàng: «Bàn: Bàn 01    Khu: Ngoài Sân» — cách nhẹ giữa bàn và khu.
String formatPosTableOneLine({
  String? areaName,
  String? tableName,
  String fallback = 'Bàn',
}) {
  final t = (tableName ?? '').trim();
  final a = (areaName ?? '').trim();
  if (t.isEmpty && a.isEmpty) return '';
  if (a.isEmpty) return t.isEmpty ? 'Bàn: $fallback' : _withResourceNoun(t);
  if (t.isEmpty) return 'Khu: $a';
  return '${_withResourceNoun(t)}    Khu: $a';
}

/// «Bàn: 05» nhưng «Phòng QA 1» (khách sạn / karaoke) — tránh «Bàn: Phòng QA 1».
String _withResourceNoun(String name) {
  final n = name.toLowerCase();
  const nouns = ['bàn', 'phòng', 'ghế', 'giường', 'room', 'table'];
  return nouns.any(n.startsWith) ? name : 'Bàn: $name';
}

/// Dòng in nhiệt — bàn và khu cùng một hàng.
List<String> formatPosTablePrintLines({
  String? areaName,
  String? tableName,
  String fallback = 'Bàn',
}) {
  final line = formatPosTableOneLine(
    areaName: areaName,
    tableName: tableName,
    fallback: fallback,
  );
  return line.isEmpty ? const [] : [line];
}
