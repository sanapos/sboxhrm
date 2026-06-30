/// Chuẩn hóa trạng thái phiếu POS từ API (enum string, số, hoặc lowercase).
String normalizePosDocStatus(dynamic raw, {String fallback = 'Draft'}) {
  if (raw == null) return fallback;
  if (raw is num) {
    return switch (raw.toInt()) {
      1 => _completedLike(fallback),
      2 => 'Cancelled',
      _ => fallback,
    };
  }
  final s = raw.toString().trim();
  if (s.isEmpty) return fallback;
  if (RegExp(r'^\d+$').hasMatch(s)) {
    return normalizePosDocStatus(int.parse(s), fallback: fallback);
  }
  final lower = s.toLowerCase();
  return switch (lower) {
    'draft' || 'inprogress' || 'in_progress' => fallback == 'InProgress'
        ? 'InProgress'
        : 'Draft',
    'completed' || 'complete' => 'Completed',
    'cancelled' || 'canceled' || 'cancel' => 'Cancelled',
    _ => s,
  };
}

String _completedLike(String fallback) =>
    fallback == 'InProgress' ? 'Completed' : 'Completed';
