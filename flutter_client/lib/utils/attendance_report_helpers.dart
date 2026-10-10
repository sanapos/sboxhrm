import 'package:intl/intl.dart';

import '../models/attendance.dart';
import 'attendance_date_range_presets.dart';
import 'attendance_leave_lookup.dart';

export 'package:payroll_engine/utils/rest_day.dart';

bool isHolidayDate(
  DateTime day,
  List<dynamic> holidays, {
  String? employeeCode,
  String? employeeGuid,
}) {
  for (final h in holidays) {
    if (h is! Map) continue;
    final holidayDate = DateTime.tryParse(h['date']?.toString() ?? '');
    if (holidayDate == null) continue;
    final isRecurring = h['isRecurring'] == true;
    final dateMatch = isRecurring
        ? holidayDate.month == day.month && holidayDate.day == day.day
        : holidayDate.year == day.year &&
            holidayDate.month == day.month &&
            holidayDate.day == day.day;
    if (!dateMatch) continue;

    final employeeCodes = h['employeeCodes'] as List?;
    final employeeIds = h['employeeIds'] as List?;
    final scope = <String>[
      if (employeeCodes != null)
        ...employeeCodes.map((e) => e?.toString() ?? ''),
      if (employeeIds != null) ...employeeIds.map((e) => e?.toString() ?? ''),
    ].where((s) => s.isNotEmpty).toList();

    if (scope.isNotEmpty) {
      final inScope = scope.any((s) =>
          (employeeCode != null && s == employeeCode) ||
          (employeeGuid != null && s == employeeGuid));
      if (!inScope) continue;
    }
    return true;
  }
  return false;
}

/// Key `code|yyyy-MM-dd` / `guid|yyyy-MM-dd` cho ngày có ít nhất 1 lần chấm.
Set<String> buildAttendanceDayKeys(
  List<Attendance> attendances, {
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final keys = <String>{};
  final fmt = DateFormat('yyyy-MM-dd');
  for (final att in attendances) {
    if (att.isTravelPunch) continue;
    final logical = AttendanceDateRangePresets.logicalWorkDay(
      att.punchTime,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    );
    final dk = fmt.format(logical);
    final code = att.employeeId ?? att.enrollNumber;
    if (code != null && code.isNotEmpty) keys.add('$code|$dk');
    // employeeId trên Attendance đôi khi là GUID
    final id = att.employeeId;
    if (id != null && id.isNotEmpty) keys.add('$id|$dk');
  }
  return keys;
}

bool employeeHasPunchOnDay({
  required Set<String> punchKeys,
  required String dateKey,
  String? employeeCode,
  String? employeeGuid,
  String? applicationUserId,
}) {
  final ids = <String>[
    if (employeeCode != null && employeeCode.isNotEmpty) employeeCode,
    if (employeeGuid != null && employeeGuid.isNotEmpty) employeeGuid,
    if (applicationUserId != null && applicationUserId.isNotEmpty)
      applicationUserId,
  ];
  for (final id in ids) {
    if (punchKeys.contains('$id|$dateKey')) return true;
  }
  return false;
}

String absenceKindLabel(AbsenceCellKind kind) {
  switch (kind) {
    case AbsenceCellKind.holiday:
      return 'Lễ';
    case AbsenceCellKind.weeklyOff:
      return 'Nghỉ tuần';
    case AbsenceCellKind.approvedLeave:
      return 'Phép';
    case AbsenceCellKind.pendingLeave:
      return 'Chờ phép';
    case AbsenceCellKind.unpaidAbsent:
      return 'Vắng không phép';
  }
}
