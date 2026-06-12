import 'package:flutter/material.dart';

/// Preset khoảng ngày cho màn chấm công (Tổng hợp / Theo ca).
class AttendanceDateRangePresets {
  AttendanceDateRangePresets._();

  static DateTime _calendarToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  /// Ngày làm việc logic theo [day_end_time].
  /// VD day_end=05:00 → mọi chấm trước 05:00 thuộc ngày làm việc hôm trước
  /// (ca 22:00–03:00: Vào 22:00 + Ra 03:00 sáng hôm sau cùng một ngày làm việc).
  static DateTime logicalWorkDay(
    DateTime punchTime, {
    int dayEndHour = 0,
    int dayEndMinute = 0,
  }) {
    final dayEnd = dayEndHour * 60 + dayEndMinute;
    if (dayEnd > 0) {
      final punchMinutes = punchTime.hour * 60 + punchTime.minute;
      if (punchMinutes < dayEnd) {
        final prev = punchTime.subtract(const Duration(days: 1));
        return DateTime(prev.year, prev.month, prev.day);
      }
    }
    return DateTime(punchTime.year, punchTime.month, punchTime.day);
  }

  static bool isLogicalDayInRange(
    DateTime logicalDay,
    DateTimeRange range,
  ) {
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return !logicalDay.isBefore(start) && !logicalDay.isAfter(end);
  }

  static DateTimeRange resolve(
    String preset, {
    DateTime? customFrom,
    DateTime? customTo,
  }) {
    final now = DateTime.now();
    final today = _calendarToday();

    switch (preset) {
      case 'today':
        return DateTimeRange(start: today, end: now);
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: y, end: endOfDay(y));
      case 'week':
        final thisMonday = today.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(start: thisMonday, end: now);
      case 'lastWeek':
        final thisMonday = today.subtract(Duration(days: now.weekday - 1));
        final lastMonday = thisMonday.subtract(const Duration(days: 7));
        final lastSunday = thisMonday.subtract(const Duration(days: 1));
        return DateTimeRange(start: lastMonday, end: endOfDay(lastSunday));
      case 'month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case 'lastMonth':
        final firstThisMonth = DateTime(today.year, today.month, 1);
        final lastDayPrev = firstThisMonth.subtract(const Duration(days: 1));
        final firstPrev =
            DateTime(lastDayPrev.year, lastDayPrev.month, lastDayPrev.day);
        return DateTimeRange(
          start: DateTime(firstPrev.year, firstPrev.month, 1),
          end: endOfDay(lastDayPrev),
        );
      default:
        final from = customFrom ?? today.subtract(const Duration(days: 30));
        final to = customTo ?? now;
        return DateTimeRange(
          start: DateTime(from.year, from.month, from.day),
          end: to,
        );
    }
  }

  /// Từ ngày gọi API — lùi 1 ngày khi có cắt ca để đủ log Vào ca đêm.
  static DateTime fetchFromDate(
    DateTime rangeStart, {
    int dayEndHour = 0,
    int dayEndMinute = 0,
  }) {
    final start = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    if (dayEndHour > 0 || dayEndMinute > 0) {
      return start.subtract(const Duration(days: 1));
    }
    return start;
  }

  /// Đến ngày gọi API — cộng 1 ngày khi có cắt ca để lấy Ra ca đêm sáng hôm sau
  /// (VD ngày làm việc 31/03 kết thúc 01/04 lúc 05:00 cần log 01/04 03:00).
  static DateTime fetchToDate(
    DateTime rangeEnd, {
    int dayEndHour = 0,
    int dayEndMinute = 0,
  }) {
    final end = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
    if (dayEndHour > 0 || dayEndMinute > 0) {
      return end.add(const Duration(days: 1));
    }
    return end;
  }
}
