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
  if (a.isEmpty) return 'Bàn: ${t.isEmpty ? fallback : t}';
  if (t.isEmpty) return 'Khu: $a';
  return 'Bàn: $t    Khu: $a';
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
