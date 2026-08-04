import 'package:intl/intl.dart';

import 'attendance_report_helpers.dart';

/// `paidLeaveType` — ngày nghỉ theo lịch phân ca (WorkSchedule.isDayOff).
const String kPaidLeaveTypeSchedule = 'schedule';

/// Parse response `getWorkSchedules` / `getMyWorkSchedules`.
List<Map<String, dynamic>> extractWorkScheduleItems(
  Map<String, dynamic> result,
) {
  if (result['isSuccess'] != true || result['data'] == null) return [];
  final data = result['data'];
  final items = data is List
      ? data
      : (data is Map ? (data['items'] ?? const []) : const []);
  if (items is! List) return [];
  return items
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

bool isSchedulePaidLeaveType(String? paidLeaveType) {
  final t = (paidLeaveType ?? '').trim().toLowerCase();
  return t == kPaidLeaveTypeSchedule;
}

bool isFlatOffPaidLeaveType(String? paidLeaveType) {
  final t = (paidLeaveType ?? '').trim().toLowerCase();
  return t == 'off-1' || t == 'off-2' || t == 'off-3' || t == 'off-4';
}

/// Không dùng weekday cố định (T7/CN) để nhận ngày nghỉ.
bool usesCalendarWeekdayOff(String? paidLeaveType) {
  if (isSchedulePaidLeaveType(paidLeaveType) ||
      isFlatOffPaidLeaveType(paidLeaveType)) {
    return false;
  }
  return true;
}

String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(
      DateTime(d.year, d.month, d.day));

/// Keys `code|yyyy-MM-dd` / `userId|yyyy-MM-dd` / `guid|yyyy-MM-dd` cho ngày nghỉ lịch.
Set<String> buildScheduleDayOffKeys(
  Iterable<dynamic> schedules, {
  Map<String, String>? employeeCodeToGuid,
}) {
  final out = <String>{};
  for (final raw in schedules) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    if (m['isDayOff'] != true) continue;
    final date = _parseScheduleDate(m['date']);
    if (date == null) continue;
    final dk = _dayKey(date);
    final code = m['employeeCode']?.toString() ?? '';
    final userId = m['employeeUserId']?.toString() ?? '';
    if (code.isNotEmpty) {
      out.add('$code|$dk');
      final guid = employeeCodeToGuid?[code];
      if (guid != null && guid.isNotEmpty) out.add('$guid|$dk');
    }
    if (userId.isNotEmpty) out.add('$userId|$dk');
  }
  return out;
}

/// Ngày có xếp ca làm (không phải ngày nghỉ trên lịch).
Set<String> buildScheduleWorkDayKeys(
  Iterable<dynamic> schedules, {
  Map<String, String>? employeeCodeToGuid,
}) {
  final out = <String>{};
  for (final raw in schedules) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    if (m['isDayOff'] == true) continue;
    final date = _parseScheduleDate(m['date']);
    if (date == null) continue;
    final dk = _dayKey(date);
    final code = m['employeeCode']?.toString() ?? '';
    final userId = m['employeeUserId']?.toString() ?? '';
    if (code.isNotEmpty) {
      out.add('$code|$dk');
      final guid = employeeCodeToGuid?[code];
      if (guid != null && guid.isNotEmpty) out.add('$guid|$dk');
    }
    if (userId.isNotEmpty) out.add('$userId|$dk');
  }
  return out;
}

/// Nhân viên có ít nhất 1 dòng lịch trong kỳ.
Set<String> buildEmployeesWithSchedule(Iterable<dynamic> schedules) {
  final out = <String>{};
  for (final raw in schedules) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final code = m['employeeCode']?.toString() ?? '';
    final userId = m['employeeUserId']?.toString() ?? '';
    if (code.isNotEmpty) out.add(code);
    if (userId.isNotEmpty) out.add(userId);
  }
  return out;
}

int countScheduleDayOffsInMonth(
  Iterable<dynamic> schedules, {
  required String employeeCode,
  required int year,
  required int month,
  String? employeeGuid,
  String? employeeUserId,
}) {
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 0);
  final seen = <String>{};
  for (final raw in schedules) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    if (m['isDayOff'] != true) continue;
    final code = m['employeeCode']?.toString() ?? '';
    final userId = m['employeeUserId']?.toString() ?? '';
    final match = code == employeeCode ||
        (employeeGuid != null && code == employeeGuid) ||
        (employeeUserId != null && userId == employeeUserId) ||
        (employeeGuid != null && userId == employeeGuid);
    if (!match && code != employeeCode) continue;
    final date = _parseScheduleDate(m['date']);
    if (date == null) continue;
    if (date.isBefore(monthStart) || date.isAfter(monthEnd)) continue;
    seen.add(_dayKey(date));
  }
  return seen.length;
}

bool scheduleKeyHit(Set<String> keys, DateTime day, Iterable<String> ids) {
  if (keys.isEmpty) return false;
  final dk = _dayKey(day);
  for (final id in ids) {
    if (id.isEmpty) continue;
    if (keys.contains('$id|$dk')) return true;
  }
  return false;
}

/// Ngày nghỉ: lịch phân ca (isDayOff) hoặc weekday hồ sơ lương.
bool isEmployeeRestDayWithSchedule(
  DateTime day, {
  String? paidLeaveType,
  String? weeklyOffDays,
  Set<String> scheduleDayOffKeys = const {},
  Iterable<String> employeeIds = const [],
}) {
  if (scheduleKeyHit(scheduleDayOffKeys, day, employeeIds)) return true;
  return isEmployeeRestDay(
    day,
    paidLeaveType: paidLeaveType,
    weeklyOffDays: weeklyOffDays,
  );
}

DateTime? _parseScheduleDate(dynamic raw) {
  if (raw == null) return null;
  if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
  final s = raw.toString();
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}
