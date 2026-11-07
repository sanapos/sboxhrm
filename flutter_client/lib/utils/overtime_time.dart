/// Giờ người dùng nhập («8:30», «18:00») → dạng API TimeSpan nhận được («08:30:00»); sai dạng trả null.
String? normalizeOvertimeTime(String input) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(input.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  final s = int.parse(m.group(3) ?? '0');
  if (h > 23 || min > 59 || s > 59) return null;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(h)}:${two(min)}:${two(s)}';
}
