import 'package:intl/intl.dart';

/// Chấm công thô / AttendanceLogs: `AttendanceTime` lưu giờ VN, JSON không có `Z`.
DateTime? parseAttendanceWallClock(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final hasTz = raw.endsWith('Z') ||
      raw.contains('+') ||
      RegExp(r'-\d{2}:\d{2}$').hasMatch(raw);
  if (hasTz) return DateTime.tryParse(raw)?.toLocal();
  return DateTime.tryParse(raw);
}

String formatAttendanceWallClock(
  dynamic value, {
  String pattern = 'HH:mm',
  String empty = '--',
}) {
  final local = parseAttendanceWallClock(value);
  if (local == null) return empty;
  return DateFormat(pattern).format(local);
}

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

/// Ngày lịch (StartDate, ViolationDate, correctionDate…) — giá trị là ngày VN, không quy đổi TZ.
DateTime? parseApiCalendarDate(dynamic value) {
  final local = parseAttendanceWallClock(value);
  if (local == null) return null;
  return DateTime(local.year, local.month, local.day);
}

String formatApiCalendarDate(
  dynamic value, {
  String pattern = 'dd/MM/yyyy',
  String empty = '--',
}) {
  final d = parseApiCalendarDate(value);
  if (d == null) return empty;
  return DateFormat(pattern).format(d);
}

/// Đầu kỳ báo cáo (ngày lịch VN, 00:00 local).
DateTime apiReportRangeStart(DateTime d) =>
    DateTime(d.year, d.month, d.day);

/// Cuối kỳ báo cáo inclusive (23:59:59 local).
DateTime apiReportRangeEnd(DateTime d) =>
    DateTime(d.year, d.month, d.day, 23, 59, 59, 999);
