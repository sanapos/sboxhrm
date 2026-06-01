import 'package:intl/intl.dart';

/// API/PostgreSQL `timestamp without time zone` — giá trị là UTC, JSON thường không có `Z`.
DateTime? parseApiUtcDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) {
    return value.isUtc
        ? value.toLocal()
        : DateTime.utc(
                value.year,
                value.month,
                value.day,
                value.hour,
                value.minute,
                value.second,
                value.millisecond,
                value.microsecond)
            .toLocal();
  }
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final hasTz = raw.endsWith('Z') ||
      raw.contains('+') ||
      RegExp(r'-\d{2}:\d{2}$').hasMatch(raw);
  final normalized = hasTz ? raw : '${raw}Z';
  return DateTime.tryParse(normalized)?.toLocal();
}

String formatApiDateTime(
  dynamic value, {
  String pattern = 'dd/MM/yyyy HH:mm',
  String empty = '--',
}) {
  final local = parseApiUtcDateTime(value);
  if (local == null) return empty;
  return DateFormat(pattern).format(local);
}
