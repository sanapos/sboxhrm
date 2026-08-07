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

/// Dòng in nhiệt K58 hẹp — tách khu / bàn để không xuống hàng giữa tên.
List<String> formatPosTablePrintLines({
  String? areaName,
  String? tableName,
  String fallback = 'Bàn',
}) {
  final t = (tableName ?? '').trim();
  final a = (areaName ?? '').trim();
  if (t.isEmpty && a.isEmpty) return const [];
  if (a.isEmpty) return ['Bàn: ${t.isEmpty ? fallback : t}'];
  if (t.isEmpty) return ['Khu: $a'];
  return ['Bàn: $t', 'Khu: $a'];
}
