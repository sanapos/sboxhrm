import 'package:intl/intl.dart';

/// Ngày gửi API chỉnh công (không timezone — khớp backend VN).
String correctionDateOnly(DateTime dt) =>
    DateFormat('yyyy-MM-dd').format(DateTime(dt.year, dt.month, dt.day));

/// Giờ gửi API dạng TimeSpan HH:mm:ss.
String correctionTimeOnly(DateTime dt) => DateFormat('HH:mm:ss').format(dt);

/// Parse ngày từ API (tránh lệch khi chuỗi ISO có Z/offset).
DateTime? parseCorrectionApiDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  try {
    if (s.contains('T')) {
      final datePart = s.split('T').first;
      final parts = datePart.split('-');
      if (parts.length == 3) {
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }
    }
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  } catch (_) {
    return null;
  }
}

String? extractCorrectionRequestId(Map<String, dynamic> apiResult) {
  if (apiResult['isSuccess'] != true) return null;
  final data = apiResult['data'];
  if (data is Map) {
    final id = data['id']?.toString();
    if (id != null && id.isNotEmpty) return id;
  }
  return null;
}
