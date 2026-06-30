import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/attendance.dart';
import 'attendance_load_utils.dart';
import 'leave_salary_shifts.dart';

/// Một dòng tổng hợp ca trong ngày cho một nhân viên.
/// Đây là single source of truth dùng chung cho:
///  • Tab "Tổng hợp theo ca" (attendance_by_shift_tab.dart)
///  • Card KPI "Đi trễ / Về sớm" trên Dashboard
class DailyShiftRecord {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final DateTime date;
  final String dayOfWeek;
  final List<DateTime> punchTimes;
  final List<String> attendanceIds;
  final List<String> shiftNames;
  final int lateMinutes;
  final int earlyMinutes;
  final int overtimeMinutes;
  final double workHours;
  final double decimalHours;
  final String status;
  final Color statusColor;
  final double workCount;

  DailyShiftRecord({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.date,
    required this.dayOfWeek,
    required this.punchTimes,
    this.attendanceIds = const [],
    this.shiftNames = const [],
    required this.lateMinutes,
    required this.earlyMinutes,
    required this.overtimeMinutes,
    required this.workHours,
    required this.decimalHours,
    required this.status,
    required this.statusColor,
    required this.workCount,
  });
}

int _parseTimeSpanToMinutes(String? timeStr) {
  if (timeStr == null || timeStr.isEmpty) return 0;
  final parts = timeStr.split(':');
  if (parts.length < 2) return 0;
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

int _dateTimeToMinutes(DateTime dt) => dt.hour * 60 + dt.minute;

bool _isCheckOutAttendance(Attendance att) => att.attendanceState == 1;

/// Một cặp Vào/Ra trong ngày — có thể chỉ có Ra (ca HC sau tăng ca).
class DayAttendancePair {
  final DateTime? checkIn;
  final DateTime? checkOut;
  final bool checkInInferred;

  const DayAttendancePair({
    this.checkIn,
    this.checkOut,
    this.checkInInferred = false,
  });

  bool get isOrphanOut => checkIn == null && checkOut != null;
  bool get isMissingOut => checkIn != null && checkOut == null;
}

List<DayAttendancePair> _pairOddEvenByTime(List<Attendance> sorted) {
  final pairs = <DayAttendancePair>[];
  for (var i = 0; i < sorted.length; i += 2) {
    if (i + 1 < sorted.length) {
      pairs.add(DayAttendancePair(
        checkIn: sorted[i].punchTime,
        checkOut: sorted[i + 1].punchTime,
      ));
    } else {
      pairs.add(DayAttendancePair(checkIn: sorted[i].punchTime));
    }
  }
  return pairs;
}

/// Chuỗi Vào/Ra từ máy có đủ tin để ghép theo loại (không fallback chẵn/lẻ).
bool _attendanceStateSequenceIsReliable(List<Attendance> sorted) {
  var inCount = 0;
  var outCount = 0;
  var maxConsecutiveIn = 0;
  var maxConsecutiveOut = 0;
  var runIn = 0;
  var runOut = 0;

  for (final att in sorted) {
    if (_isCheckOutAttendance(att)) {
      outCount++;
      runOut++;
      runIn = 0;
      if (runOut > maxConsecutiveOut) maxConsecutiveOut = runOut;
    } else {
      inCount++;
      runIn++;
      runOut = 0;
      if (runIn > maxConsecutiveIn) maxConsecutiveIn = runIn;
    }
  }

  // VD: 1 Ra (07:00 bổ sung sai) + 3 Vào máy → lệch 2, không tin được.
  if ((inCount - outCount).abs() > 1) return false;
  // ≥3 Vào/Ra liên tiếp → máy thường không gửi đúng loại.
  if (maxConsecutiveIn >= 3 || maxConsecutiveOut >= 3) return false;

  return true;
}

bool _shouldPairByAttendanceState(List<Attendance> sorted) {
  if (sorted.length < 2) {
    return sorted.length == 1 && _isCheckOutAttendance(sorted.first);
  }
  final hasIn = sorted.any((a) => !_isCheckOutAttendance(a));
  final hasOut = sorted.any((a) => _isCheckOutAttendance(a));
  if (!hasIn || !hasOut) return false;
  return _attendanceStateSequenceIsReliable(sorted);
}

/// Ghép cặp chấm công trong ngày.
/// Ưu tiên loại Vào/Ra khi chuỗi máy gửi đáng tin; ngược lại chẵn/lẻ theo thời gian.
List<DayAttendancePair> buildDayAttendancePairs(List<Attendance> dayAtts) {
  final sorted = List<Attendance>.from(dayAtts)
    ..sort((a, b) => a.punchTime.compareTo(b.punchTime));
  if (sorted.isEmpty) return [];

  if (!_shouldPairByAttendanceState(sorted)) {
    return _pairOddEvenByTime(sorted);
  }

  final pairs = <DayAttendancePair>[];
  Attendance? pendingIn;
  for (final att in sorted) {
    if (!_isCheckOutAttendance(att)) {
      if (pendingIn != null) {
        pairs.add(DayAttendancePair(checkIn: pendingIn.punchTime));
      }
      pendingIn = att;
    } else {
      if (pendingIn != null) {
        pairs.add(DayAttendancePair(
          checkIn: pendingIn.punchTime,
          checkOut: att.punchTime,
        ));
        pendingIn = null;
      } else {
        pairs.add(DayAttendancePair(checkOut: att.punchTime));
      }
    }
  }
  if (pendingIn != null) {
    pairs.add(DayAttendancePair(checkIn: pendingIn.punchTime));
  }
  return pairs;
}

/// Tìm ca hành chính khớp khi NV chỉ chấm Ra (sau khi làm tăng ca liền trước).
Map<String, dynamic>? matchShiftForOrphanCheckOut({
  required int checkOutMinutes,
  required List<String> candidateIds,
  required Map<String, Map<String, dynamic>> shiftTemplateMap,
  Set<String> usedShiftIds = const {},
  int pairIndex = 0,
}) {
  Map<String, dynamic>? best;
  var bestScore = 1 << 30;

  if (candidateIds.isEmpty) return null;
  final ordered = _sortShiftIdsByStart(candidateIds, shiftTemplateMap);
  final scoped = pairIndex > 0 && pairIndex < ordered.length
      ? ordered.sublist(pairIndex)
      : ordered;

  for (final stId in scoped) {
    if (usedShiftIds.contains(stId)) continue;
    final st = shiftTemplateMap[stId];
    if (st == null || st['isActive'] == false) continue;
    if (isOvertimeShiftTemplate(st)) continue;

    final startMin = _parseTimeSpanToMinutes(st['startTime']?.toString());
    final endMin = _parseTimeSpanToMinutes(st['endTime']?.toString());
    final isCrossMidnight = startMin > endMin;
    final otThreshold =
        (st['overtimeMinutesThreshold'] as num?)?.toInt() ?? 30;
    final earlyCheckIn = (st['earlyCheckInMinutes'] as num?)?.toInt() ?? 30;

    if (isCrossMidnight) {
      // Ra sáng hôm sau (VD 03:00) thuộc ca 22:00–03:00
      if (checkOutMinutes <= endMin + otThreshold) {
        final distToEnd = (checkOutMinutes - endMin).abs();
        if (distToEnd < bestScore) {
          bestScore = distToEnd;
          best = st;
        }
      }
      continue;
    }

    if (checkOutMinutes < startMin - earlyCheckIn) continue;
    if (checkOutMinutes > endMin + otThreshold) continue;

    final distToEnd = (checkOutMinutes - endMin).abs();
    final score = distToEnd;
    if (score < bestScore) {
      bestScore = score;
      best = st;
    }
  }
  return best;
}

/// Suy ra giờ Vào ca hành chính khi NV chỉ chấm Ra sau tăng ca.
DateTime? inferAdminCheckInForOrphanOut({
  required DateTime checkOut,
  required Map<String, dynamic> matchedShift,
  DateTime? previousCheckOut,
}) {
  final shiftStartMin =
      _parseTimeSpanToMinutes(matchedShift['startTime']?.toString());
  final shiftEndMin =
      _parseTimeSpanToMinutes(matchedShift['endTime']?.toString());
  final isCrossMidnight = shiftStartMin > shiftEndMin;

  var startDay = checkOut;
  if (isCrossMidnight) {
    final outMin = _dateTimeToMinutes(checkOut);
    // Ra trước giờ tan ca (03:00) → Vào ca tối hôm trước (22:00)
    if (outMin <= shiftEndMin) {
      startDay = checkOut.subtract(const Duration(days: 1));
    }
  }

  final shiftStart = DateTime(
    startDay.year,
    startDay.month,
    startDay.day,
    shiftStartMin ~/ 60,
    shiftStartMin % 60,
  );

  if (previousCheckOut != null) {
    final gapMinutes = checkOut.difference(previousCheckOut).inMinutes;
    if (gapMinutes >= 0 && gapMinutes <= 360) {
      return previousCheckOut.isAfter(shiftStart)
          ? previousCheckOut
          : shiftStart;
    }
  }
  return shiftStart;
}

/// Loại ca từ thiết lập ca (`shiftType` trên ShiftTemplate).
enum ShiftTemplateKind { administrative, overtime, overnight }

/// Đọc shiftType — khớp với [shift_settings_screen._getShiftType].
ShiftTemplateKind parseShiftTemplateKind(Map<String, dynamic>? st) {
  if (st == null) return ShiftTemplateKind.administrative;
  final raw = (st['shiftType'] ?? '').toString().toLowerCase();
  if (raw.contains('tăng ca') ||
      raw.contains('tang ca') ||
      raw.contains('tangca') ||
      raw.contains('overtime')) {
    return ShiftTemplateKind.overtime;
  }
  if (raw.contains('qua đêm') ||
      raw.contains('qua dem') ||
      raw.contains('quadem') ||
      raw.contains('overnight')) {
    return ShiftTemplateKind.overnight;
  }
  return ShiftTemplateKind.administrative;
}

bool isOvertimeShiftTemplate(Map<String, dynamic>? st) =>
    parseShiftTemplateKind(st) == ShiftTemplateKind.overtime;

bool isOvernightShiftTemplate(Map<String, dynamic>? st) =>
    parseShiftTemplateKind(st) == ShiftTemplateKind.overnight;

/// Hệ số lương ca qua đêm (+30%) — chỉ áp cho ca có shiftType Qua đêm.
double applyOvernightShiftCoefficient({
  required double workSalary,
  required int totalShifts,
  required int overnightShifts,
}) {
  if (overnightShifts <= 0 || totalShifts <= 0) return workSalary;
  final regularShifts = totalShifts - overnightShifts;
  final perShift = workSalary / totalShifts;
  return perShift * regularShifts + perShift * 1.3 * overnightShifts;
}

/// How well a punch pair fits a shift (lower penalty = better match).
class _ShiftPunchFit {
  final Map<String, dynamic> shift;
  final String shiftId;
  final int effectiveLateIn;
  final int effectiveEarlyOut;
  final int distanceToStart;

  const _ShiftPunchFit({
    required this.shift,
    required this.shiftId,
    required this.effectiveLateIn,
    required this.effectiveEarlyOut,
    required this.distanceToStart,
  });

  int get penaltyScore => effectiveLateIn + effectiveEarlyOut;
}

/// Evaluate check-in/out against one shift template. Returns null when punch
/// is outside allowed windows (too early, or too late beyond maximumAllowedLate).
_ShiftPunchFit? _evaluateShiftPunchFit(
  Map<String, dynamic> st,
  int punchInMinutes, {
  int? punchOutMinutes,
}) {
  if (st['isActive'] == false) return null;

  final shiftId = st['id']?.toString() ?? '';
  if (shiftId.isEmpty) return null;

  final shiftStartMin = _parseTimeSpanToMinutes(st['startTime']?.toString());
  final shiftEndMin = _parseTimeSpanToMinutes(st['endTime']?.toString());
  final isCrossMidnight = shiftStartMin > shiftEndMin;

  final lateGrace = (st['lateGraceMinutes'] as num?)?.toInt() ?? 5;
  final earlyGrace = (st['earlyLeaveGraceMinutes'] as num?)?.toInt() ?? 5;
  final earlyCheckIn = (st['earlyCheckInMinutes'] as num?)?.toInt() ?? 30;
  final maxAllowedLate =
      (st['maximumAllowedLateMinutes'] as num?)?.toInt() ?? 0;

  int rawEarlyIn = 0;
  int rawLateIn = 0;
  if (isCrossMidnight) {
    if (punchInMinutes < shiftStartMin && punchInMinutes > shiftEndMin) {
      rawEarlyIn = shiftStartMin - punchInMinutes;
    } else if (punchInMinutes >= shiftStartMin) {
      rawLateIn = punchInMinutes - shiftStartMin;
    } else if (punchInMinutes < shiftEndMin) {
      rawLateIn = (1440 - shiftStartMin) + punchInMinutes;
    }
  } else {
    if (punchInMinutes < shiftStartMin) {
      rawEarlyIn = shiftStartMin - punchInMinutes;
    } else if (punchInMinutes > shiftStartMin) {
      rawLateIn = punchInMinutes - shiftStartMin;
    }
  }

  if (rawEarlyIn > earlyCheckIn) return null;
  if (maxAllowedLate > 0 && rawLateIn > maxAllowedLate) return null;

  // Không cho chấm VÀO sau giờ tan ca (ca thường, không qua đêm).
  if (!isCrossMidnight && punchInMinutes > shiftEndMin) return null;

  var effectiveLateIn = rawLateIn;
  if (effectiveLateIn > 0 && effectiveLateIn <= lateGrace) effectiveLateIn = 0;

  var effectiveEarlyOut = 0;
  if (punchOutMinutes != null) {
    int rawEarlyOut = 0;
    if (isCrossMidnight) {
      if (punchOutMinutes <= shiftEndMin) {
        rawEarlyOut = shiftEndMin - punchOutMinutes;
      } else if (punchOutMinutes >= shiftStartMin) {
        rawEarlyOut = (1440 - punchOutMinutes) + shiftEndMin;
      }
    } else if (punchOutMinutes < shiftEndMin) {
      rawEarlyOut = shiftEndMin - punchOutMinutes;
    }
    effectiveEarlyOut = rawEarlyOut;
    if (effectiveEarlyOut > 0 && effectiveEarlyOut <= earlyGrace) {
      effectiveEarlyOut = 0;
    }
  }

  var distanceToStart = (punchInMinutes - shiftStartMin).abs();
  if (distanceToStart > 720) distanceToStart = 1440 - distanceToStart;

  return _ShiftPunchFit(
    shift: st,
    shiftId: shiftId,
    effectiveLateIn: effectiveLateIn,
    effectiveEarlyOut: effectiveEarlyOut,
    distanceToStart: distanceToStart,
  );
}

/// Pick the best shift when an employee has multiple assigned templates.
/// Prefers a shift where the punch is on-time (no late after grace) over a
/// closer shift that would count as late — e.g. punch 13:14 matches 13:30-17:30
/// instead of 13:00-17:00 (14P trễ).
List<String> _sortShiftIdsByStart(
  Iterable<String> ids,
  Map<String, Map<String, dynamic>> shiftTemplateMap,
) {
  final list = ids.toList();
  list.sort((a, b) {
    final sa = _parseTimeSpanToMinutes(
        shiftTemplateMap[a]?['startTime']?.toString());
    final sb = _parseTimeSpanToMinutes(
        shiftTemplateMap[b]?['startTime']?.toString());
    return sa.compareTo(sb);
  });
  return list;
}

Map<String, dynamic>? findBestMatchingShift({
  required int punchInMinutes,
  int? punchOutMinutes,
  required List<String> candidateIds,
  required Map<String, Map<String, dynamic>> shiftTemplateMap,
  Set<String> usedShiftIds = const {},
  int pairIndex = 0,
  /// When true (default), never fall back to shifts outside [candidateIds].
  bool assignedOnly = true,
}) {
  if (candidateIds.isEmpty) return null;
  if (shiftTemplateMap.isEmpty) return null;

  _ShiftPunchFit? pickBest(Iterable<String> ids) {
    _ShiftPunchFit? best;
    for (final stId in ids) {
      if (usedShiftIds.contains(stId)) continue;
      final st = shiftTemplateMap[stId];
      if (st == null) continue;
      final fit = _evaluateShiftPunchFit(
        st,
        punchInMinutes,
        punchOutMinutes: punchOutMinutes,
      );
      if (fit == null) continue;
      if (best == null ||
          fit.penaltyScore < best.penaltyScore ||
          (fit.penaltyScore == best.penaltyScore &&
              fit.effectiveLateIn < best.effectiveLateIn) ||
          (fit.penaltyScore == best.penaltyScore &&
              fit.effectiveLateIn == best.effectiveLateIn &&
              fit.distanceToStart < best.distanceToStart)) {
        best = fit;
      }
    }
    return best;
  }

  // Cặp chấm thứ i (0=sáng, 1=chiều, …) chỉ xét ca có thứ tự >= i sau khi
  // sắp xếp theo giờ vào — tránh ca chiều 13:24 bị gán ca sáng 07:00/11:00.
  final orderedPrimary = _sortShiftIdsByStart(candidateIds, shiftTemplateMap);
  final scopedPrimary = pairIndex > 0 && pairIndex < orderedPrimary.length
      ? orderedPrimary.sublist(pairIndex)
      : orderedPrimary;
  var best = pickBest(scopedPrimary);

  // Legacy: only when explicitly allowed — never match unassigned HRM shifts.
  if (!assignedOnly &&
      (best == null || best.distanceToStart > 180)) {
    final orderedAll =
        _sortShiftIdsByStart(shiftTemplateMap.keys, shiftTemplateMap);
    final scopedAll = pairIndex > 0 && pairIndex < orderedAll.length
        ? orderedAll.sublist(pairIndex)
        : orderedAll;
    final fallback = pickBest(scopedAll);
    if (fallback != null &&
        (best == null || fallback.distanceToStart < best.distanceToStart)) {
      best = fallback;
    }
  }

  if (best == null || best.distanceToStart > 180) return null;
  return best.shift;
}

String _getDayOfWeekVN(int weekday) {
  const days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
  return days[(weekday - 1).clamp(0, 6)];
}

/// Lookup tables built from raw inputs once per compute call.
class _ShiftLookups {
  final Map<String, Map<String, dynamic>> shiftTemplateMap;
  final Map<String, String> employeeCodeToGuid;
  final Map<String, List<String>> employeeGuidToShiftTemplateIds;
  final Map<String, int> employeeGuidToShiftsPerDay;
  final Map<String, String> employeeCodeToWeeklyOffDays;
  final Map<String, double> employeeCodeToHolidayMultiplier;
  final Map<String, int> employeeCodeToHolidayOvertimeType;

  _ShiftLookups({
    required this.shiftTemplateMap,
    required this.employeeCodeToGuid,
    required this.employeeGuidToShiftTemplateIds,
    required this.employeeGuidToShiftsPerDay,
    required this.employeeCodeToWeeklyOffDays,
    required this.employeeCodeToHolidayMultiplier,
    required this.employeeCodeToHolidayOvertimeType,
  });

  factory _ShiftLookups.build({
    required List<Map<String, dynamic>> shiftTemplates,
    required List<Map<String, dynamic>> shiftSalaryLevels,
    required List<Map<String, dynamic>> salaryProfiles,
    List<Map<String, dynamic>>? employeesList,
  }) {
    final shiftTemplateMap = <String, Map<String, dynamic>>{};
    for (final st in shiftTemplates) {
      final id = st['id']?.toString() ?? '';
      if (id.isNotEmpty) {
        shiftTemplateMap[id] = st;
      }
    }

    final employeeCodeToGuid = <String, String>{};
    final employeeGuidToShiftsPerDay = <String, int>{};
    final employeeCodeToWeeklyOffDays = <String, String>{};
    final employeeCodeToHolidayMultiplier = <String, double>{};
    final employeeCodeToHolidayOvertimeType = <String, int>{};
    final employeeGuidToShiftTemplateIds = <String, List<String>>{};

    for (final profile in salaryProfiles) {
      final shiftsPerDay = profile['shiftsPerDay'] as int? ?? 1;
      final weeklyOffDays = profile['weeklyOffDays']?.toString() ?? 'Sunday';
      final holidayMultiplier =
          (profile['holidayMultiplier'] as num?)?.toDouble() ?? 2.0;
      final holidayOvertimeType =
          (profile['holidayOvertimeType'] as num?)?.toInt() ?? 1;

      final employees = profile['employees'] as List? ?? [];
      for (final emp in employees) {
        if (emp is Map<String, dynamic>) {
          final guid = emp['id']?.toString() ?? '';
          final code = emp['employeeCode']?.toString() ?? '';
          if (guid.isNotEmpty && code.isNotEmpty) {
            employeeCodeToGuid[code] = guid;
            employeeGuidToShiftsPerDay[guid] = shiftsPerDay;
            employeeCodeToWeeklyOffDays[code] = weeklyOffDays;
            employeeCodeToHolidayMultiplier[code] = holidayMultiplier;
            employeeCodeToHolidayOvertimeType[code] = holidayOvertimeType;
          }
        }
      }
    }

    // Ca gán trong thiết lập lương HRM (Benefit.Description + ShiftSalaryLevel).
    employeeGuidToShiftTemplateIds.addAll(
      LeaveSalaryShifts.buildEmployeeShiftAssignmentMap(
        salaryProfiles: salaryProfiles,
        shiftTemplates: shiftTemplates,
        shiftSalaryLevels: shiftSalaryLevels,
      ),
    );

    // Log chấm công thường dùng PIN (enrollNumber) — alias sang GUID hồ sơ lương.
    if (employeesList != null) {
      for (final emp in employeesList) {
        final code = emp['employeeCode']?.toString() ?? '';
        final pin = emp['pin']?.toString() ?? '';
        final guid = emp['id']?.toString() ?? '';
        if (code.isEmpty || pin.isEmpty || guid.isEmpty) continue;
        final mappedGuid = employeeCodeToGuid[code];
        if (mappedGuid == null || mappedGuid.isEmpty) continue;
        employeeCodeToGuid[pin] = mappedGuid;
        if (employeeGuidToShiftTemplateIds.containsKey(mappedGuid)) {
          employeeGuidToShiftTemplateIds[pin] =
              List<String>.from(employeeGuidToShiftTemplateIds[mappedGuid]!);
        }
        if (!employeeCodeToWeeklyOffDays.containsKey(pin) &&
            employeeCodeToWeeklyOffDays.containsKey(code)) {
          employeeCodeToWeeklyOffDays[pin] =
              employeeCodeToWeeklyOffDays[code]!;
        }
        if (!employeeCodeToHolidayMultiplier.containsKey(pin) &&
            employeeCodeToHolidayMultiplier.containsKey(code)) {
          employeeCodeToHolidayMultiplier[pin] =
              employeeCodeToHolidayMultiplier[code]!;
        }
        if (!employeeCodeToHolidayOvertimeType.containsKey(pin) &&
            employeeCodeToHolidayOvertimeType.containsKey(code)) {
          employeeCodeToHolidayOvertimeType[pin] =
              employeeCodeToHolidayOvertimeType[code]!;
        }
      }
    }

    return _ShiftLookups(
      shiftTemplateMap: shiftTemplateMap,
      employeeCodeToGuid: employeeCodeToGuid,
      employeeGuidToShiftTemplateIds: employeeGuidToShiftTemplateIds,
      employeeGuidToShiftsPerDay: employeeGuidToShiftsPerDay,
      employeeCodeToWeeklyOffDays: employeeCodeToWeeklyOffDays,
      employeeCodeToHolidayMultiplier: employeeCodeToHolidayMultiplier,
      employeeCodeToHolidayOvertimeType: employeeCodeToHolidayOvertimeType,
    );
  }

  Map<String, dynamic>? findMatchingShift(
    int punchInMinutes,
    List<String> assignedShiftIds, {
    int? punchOutMinutes,
    Set<String> usedShiftIds = const {},
    int pairIndex = 0,
  }) {
    return findBestMatchingShift(
      punchInMinutes: punchInMinutes,
      punchOutMinutes: punchOutMinutes,
      candidateIds: assignedShiftIds,
      shiftTemplateMap: shiftTemplateMap,
      usedShiftIds: usedShiftIds,
      pairIndex: pairIndex,
    );
  }

  bool isWeeklyOffDay(DateTime date, String employeeCode) {
    final weeklyOff = employeeCodeToWeeklyOffDays[employeeCode] ?? 'Sunday';
    final weekday = date.weekday;
    if (weeklyOff.contains('Sunday') && weekday == DateTime.sunday) return true;
    if (weeklyOff.contains('Saturday') && weekday == DateTime.saturday) {
      return true;
    }
    return false;
  }

  double? getHolidayRate(
    DateTime date,
    String employeeCode,
    List<dynamic> holidays,
  ) {
    final empGuid = employeeCodeToGuid[employeeCode];
    for (final h in holidays) {
      if (h is! Map<String, dynamic>) continue;
      final holidayDate = DateTime.tryParse(h['date']?.toString() ?? '');
      if (holidayDate == null) continue;
      final isRecurring = h['isRecurring'] == true;
      bool dateMatch = isRecurring
          ? holidayDate.month == date.month && holidayDate.day == date.day
          : holidayDate.year == date.year &&
              holidayDate.month == date.month &&
              holidayDate.day == date.day;
      if (!dateMatch) continue;
      final employeeCodes = h['employeeCodes'] as List?;
      final employeeIds = h['employeeIds'] as List?;
      final scopeList = <String>[
        if (employeeCodes != null)
          ...employeeCodes.map((e) => e?.toString() ?? ''),
        if (employeeIds != null) ...employeeIds.map((e) => e?.toString() ?? ''),
      ].where((s) => s.isNotEmpty).toList();
      if (scopeList.isNotEmpty) {
        final inScope = scopeList
            .any((s) => s == employeeCode || (empGuid != null && s == empGuid));
        if (!inScope) continue;
      }
      return (h['salaryRate'] as num?)?.toDouble() ?? 3.0;
    }
    return null;
  }
}

DateTime _getLogicalDate(DateTime punchTime, int dayEndHour, int dayEndMinute) {
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

List<Attendance> _filterByLogicalWorkDayRange(
  List<Attendance> attendances,
  DateTime fromDate,
  DateTime toDate, {
  required int dayEndHour,
  required int dayEndMinute,
}) {
  final rangeStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
  final rangeEnd = DateTime(toDate.year, toDate.month, toDate.day);
  return attendances.where((att) {
    final logical = _getLogicalDate(att.punchTime, dayEndHour, dayEndMinute);
    return !logical.isBefore(rangeStart) && !logical.isAfter(rangeEnd);
  }).toList();
}

List<DayAttendancePair> _logicalDayPairsFromAttendances(
  List<Attendance> dayAtts, {
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  if (dayEndHour > 0 || dayEndMinute > 0) {
    return buildSummaryDayPairs(
      dayAtts,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
    ).map((p) {
      if (p.checkIn != null && p.checkOut != null) {
        return DayAttendancePair(
          checkIn: p.checkIn!.punchTime,
          checkOut: p.checkOut!.punchTime,
        );
      }
      if (p.checkIn != null) {
        return DayAttendancePair(checkIn: p.checkIn!.punchTime);
      }
      return DayAttendancePair(checkOut: p.checkOut!.punchTime);
    }).toList();
  }
  return buildDayAttendancePairs(dayAtts);
}

/// Tính toàn bộ records ca/ngày cho danh sách attendances.
/// Cùng thuật toán với tab "Tổng hợp theo ca" để Dashboard hiển thị
/// đồng nhất số "Đi trễ / Về sớm" với tab.
List<DailyShiftRecord> computeDailyShiftRecords({
  required List<Attendance> attendances,
  required DateTime fromDate,
  required DateTime toDate,
  List<Map<String, dynamic>> shiftTemplates = const [],
  List<Map<String, dynamic>> shiftSalaryLevels = const [],
  List<Map<String, dynamic>> salaryProfiles = const [],
  List<Map<String, dynamic>>? employeesList,
  List<dynamic> holidays = const [],
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final lookups = _ShiftLookups.build(
    shiftTemplates: shiftTemplates,
    shiftSalaryLevels: shiftSalaryLevels,
    salaryProfiles: salaryProfiles,
    employeesList: employeesList,
  );

  // Lọc theo ngày làm việc logic (day_end_time), không theo ngày lịch thuần.
  final filtered = _filterByLogicalWorkDayRange(
    attendances,
    fromDate,
    toDate,
    dayEndHour: dayEndHour,
    dayEndMinute: dayEndMinute,
  );

  final Map<String, Map<String, List<Attendance>>> grouped = {};
  for (final att in filtered) {
    final empKey = att.employeeId ?? att.enrollNumber ?? 'unknown';
    final logicalDate =
        _getLogicalDate(att.punchTime, dayEndHour, dayEndMinute);
    final dateKey = DateFormat('yyyy-MM-dd').format(logicalDate);
    grouped.putIfAbsent(empKey, () => {});
    grouped[empKey]!.putIfAbsent(dateKey, () => []).add(att);
  }

  final records = <DailyShiftRecord>[];
  grouped.forEach((employeeCode, dateMap) {
    dateMap.forEach((dateStr, dayAttendances) {
      if (dayAttendances.isEmpty) return;
      dayAttendances.sort((a, b) => a.punchTime.compareTo(b.punchTime));
      final first = dayAttendances.first;
      final date = DateTime.parse(dateStr);

      final punchTimes = dayAttendances.map((a) => a.punchTime).toList();
      final attendanceIds = dayAttendances.map((a) => a.id).toList();

      final empGuid = lookups.employeeCodeToGuid[employeeCode] ?? '';
      final assignedShiftIds =
          lookups.employeeGuidToShiftTemplateIds[empGuid] ?? [];
      final shiftsPerDay = lookups.employeeGuidToShiftsPerDay[empGuid] ?? 1;

      int totalLate = 0;
      int totalEarly = 0;
      int totalOT = 0;
      double totalWorkHours = 0;
      double totalDecimalHours = 0;
      double totalWorkCount = 0;
      bool hasMissingPunch = false;
      final shiftNames = <String>[];
      final missingOutShiftNames = <String>[];
      final usedShiftIds = <String>{};
      final dayPairs = _logicalDayPairsFromAttendances(
        dayAttendances,
        dayEndHour: dayEndHour,
        dayEndMinute: dayEndMinute,
      );

      for (var pairIndex = 0; pairIndex < dayPairs.length; pairIndex++) {
        final pair = dayPairs[pairIndex];
        DateTime? punchIn = pair.checkIn;
        final punchOut = pair.checkOut;

        Map<String, dynamic>? matchedShift;
        if (pair.isOrphanOut && punchOut != null) {
          final outMin = _dateTimeToMinutes(punchOut);
          matchedShift = matchShiftForOrphanCheckOut(
            checkOutMinutes: outMin,
            candidateIds: assignedShiftIds,
            shiftTemplateMap: lookups.shiftTemplateMap,
            usedShiftIds: usedShiftIds,
            pairIndex: pairIndex,
          );
          if (matchedShift != null) {
            final prevOut = pairIndex > 0
                ? dayPairs[pairIndex - 1].checkOut
                : null;
            punchIn = inferAdminCheckInForOrphanOut(
              checkOut: punchOut,
              matchedShift: matchedShift,
              previousCheckOut: prevOut,
            );
          }
        }

        if (punchIn == null) {
          if (pair.isOrphanOut) hasMissingPunch = true;
          continue;
        }

        final punchInMinutes = _dateTimeToMinutes(punchIn);
        final punchOutMinutes =
            punchOut != null ? _dateTimeToMinutes(punchOut) : null;
        matchedShift ??= lookups.findMatchingShift(
          punchInMinutes,
          assignedShiftIds,
          punchOutMinutes: punchOutMinutes,
          usedShiftIds: usedShiftIds,
          pairIndex: pairIndex,
        );

        if (matchedShift != null) {
          final shiftId = matchedShift['id']?.toString() ?? '';
          if (shiftId.isNotEmpty) usedShiftIds.add(shiftId);
          final name = matchedShift['name']?.toString() ?? '';
          if (name.isNotEmpty && !shiftNames.contains(name)) {
            shiftNames.add(name);
          }
        }

        final isOtShift = isOvertimeShiftTemplate(matchedShift);

        int lateCalc = 0;
        int lateGrace = 5;
        int earlyGrace = 5;
        int shiftStartMin = 0;
        int shiftEndMin = 0;
        int shiftDurationMin = 0;
        bool isCrossMidnight = false;
        int overtimeThreshold = 0;
        if (matchedShift != null && !isOtShift) {
          shiftStartMin =
              _parseTimeSpanToMinutes(matchedShift['startTime']?.toString());
          shiftEndMin =
              _parseTimeSpanToMinutes(matchedShift['endTime']?.toString());
          isCrossMidnight = shiftStartMin > shiftEndMin;
          shiftDurationMin = isCrossMidnight
              ? (1440 - shiftStartMin + shiftEndMin)
              : (shiftEndMin - shiftStartMin);
          lateGrace = (matchedShift['lateGraceMinutes'] as num?)?.toInt() ?? 5;
          earlyGrace =
              (matchedShift['earlyLeaveGraceMinutes'] as num?)?.toInt() ?? 5;
          overtimeThreshold =
              (matchedShift['overtimeMinutesThreshold'] as num?)?.toInt() ?? 30;

          if (isCrossMidnight) {
            if (punchInMinutes >= shiftStartMin) {
              lateCalc = punchInMinutes - shiftStartMin;
            } else if (punchInMinutes < shiftEndMin) {
              lateCalc = (1440 - shiftStartMin) + punchInMinutes;
            }
          } else if (punchInMinutes > shiftStartMin) {
            lateCalc = punchInMinutes - shiftStartMin;
          }
          if (lateCalc > 0 && lateCalc <= lateGrace) lateCalc = 0;
          if (lateCalc > 0) totalLate += lateCalc;
        } else if (matchedShift != null && isOtShift) {
          shiftStartMin =
              _parseTimeSpanToMinutes(matchedShift['startTime']?.toString());
          shiftEndMin =
              _parseTimeSpanToMinutes(matchedShift['endTime']?.toString());
          isCrossMidnight = shiftStartMin > shiftEndMin;
        }

        if (punchOut == null) {
          hasMissingPunch = true;
          String name = matchedShift?['name']?.toString() ?? '';
          if (name.isEmpty) {
            final hh = punchIn.hour.toString().padLeft(2, '0');
            final mm = punchIn.minute.toString().padLeft(2, '0');
            name = 'ca lúc $hh:$mm';
          }
          if (!missingOutShiftNames.contains(name)) {
            missingOutShiftNames.add(name);
          }
          continue;
        }

        final outMinutes = punchOutMinutes!;
        var effectiveOut = punchOut;
        if (effectiveOut.isBefore(punchIn)) {
          effectiveOut = effectiveOut.add(const Duration(days: 1));
        }
        final actualWorkedMinutes = effectiveOut.difference(punchIn).inMinutes;

        // Ca Tăng ca: không tính đi trễ/về sớm — chỉ cộng giờ làm thực tế vào OT.
        if (matchedShift != null && isOtShift) {
          if (actualWorkedMinutes > 0) {
            totalOT += actualWorkedMinutes;
            totalWorkHours += actualWorkedMinutes / 60.0;
            totalDecimalHours += actualWorkedMinutes / 60.0;
          }
          continue;
        }

        if (matchedShift != null) {
          int earlyCalc = 0;
          if (isCrossMidnight) {
            if (outMinutes <= shiftEndMin) {
              earlyCalc = shiftEndMin - outMinutes;
            } else if (outMinutes >= shiftStartMin) {
              earlyCalc = (1440 - outMinutes) + shiftEndMin;
            }
          } else if (outMinutes < shiftEndMin) {
            earlyCalc = shiftEndMin - outMinutes;
          }
          if (earlyCalc > 0 && earlyCalc <= earlyGrace) earlyCalc = 0;

          int extraMin = 0;
          if (isCrossMidnight) {
            if (outMinutes > shiftEndMin && outMinutes < shiftStartMin) {
              extraMin = outMinutes - shiftEndMin;
            }
          } else if (outMinutes > shiftEndMin) {
            extraMin = outMinutes - shiftEndMin;
          }
          if (extraMin > overtimeThreshold) {
            totalOT += extraMin;
            earlyCalc = 0;
          } else {
            extraMin = 0;
          }
          if (earlyCalc > 0) totalEarly += earlyCalc;

          if (lateCalc <= 0 && earlyCalc <= 0 && extraMin <= 0) {
            totalWorkHours += shiftDurationMin / 60.0;
          } else {
            totalWorkHours += actualWorkedMinutes / 60.0;
          }
          totalDecimalHours += actualWorkedMinutes / 60.0;
          // Chỉ tính 1 ca khi NV làm đủ ít nhất 2/3 số giờ ca quy định
          final minMinutesForShift =
              shiftDurationMin > 0 ? (shiftDurationMin * 2.0 / 3.0).round() : 0;
          if (actualWorkedMinutes >= minMinutesForShift) {
            totalWorkCount += shiftsPerDay > 0 ? 1.0 / shiftsPerDay : 1.0;
          }
        } else {
          totalWorkHours += actualWorkedMinutes / 60.0;
          totalDecimalHours += actualWorkedMinutes / 60.0;
          totalWorkCount += shiftsPerDay > 0 ? 1.0 / shiftsPerDay : 1.0;
        }
      }

      final isRestDay = lookups.isWeeklyOffDay(date, employeeCode);
      final holidayRate = lookups.getHolidayRate(date, employeeCode, holidays);
      final isHoliday = holidayRate != null;
      final holidayOvertimeType =
          lookups.employeeCodeToHolidayOvertimeType[employeeCode] ?? 1;
      final holidayMultiplier =
          lookups.employeeCodeToHolidayMultiplier[employeeCode] ?? 2.0;

      if ((isRestDay || isHoliday) && totalWorkCount > 0) {
        if (isHoliday) {
          totalWorkCount *= holidayRate;
          totalWorkHours *= holidayRate;
          totalDecimalHours *= holidayRate;
        } else if (isRestDay) {
          if (holidayOvertimeType == 1) {
            totalWorkCount *= holidayMultiplier;
            totalWorkHours *= holidayMultiplier;
            totalDecimalHours *= holidayMultiplier;
          }
        }
      }

      String status;
      Color statusColor;
      if (hasMissingPunch && totalWorkCount == 0) {
        status = 'Thiếu chấm';
        statusColor = Colors.grey;
      } else if (isHoliday && totalWorkCount > 0) {
        status = 'Tăng ca ngày lễ';
        statusColor = Colors.deepOrange;
        if (totalLate > 0) status = 'Đi trễ - $status';
        if (totalEarly > 0) status = '$status - Về sớm';
      } else if (isRestDay && totalWorkCount > 0) {
        status = 'Tăng ca ngày nghỉ';
        statusColor = Colors.purple;
        if (totalLate > 0) status = 'Đi trễ - $status';
        if (totalEarly > 0) status = '$status - Về sớm';
      } else if (totalLate > 0 && totalEarly > 0) {
        status = 'Đi trễ - Về sớm';
        statusColor = Colors.red;
      } else if (totalLate > 0) {
        status = 'Đi trễ';
        statusColor = Colors.orange;
      } else if (totalEarly > 0) {
        status = 'Về sớm';
        statusColor = Colors.red;
      } else if (totalOT > 0 && totalWorkCount == 0) {
        status = 'Tăng ca';
        statusColor = Colors.amber;
      } else if (totalWorkCount > 0) {
        status = 'Hợp lệ';
        statusColor = Colors.green;
      } else {
        status = 'Thiếu chấm';
        statusColor = Colors.grey;
      }
      if (hasMissingPunch && totalWorkCount > 0) {
        if (missingOutShiftNames.isNotEmpty) {
          final extra = 'Thiếu ra ${missingOutShiftNames.join(", ")}';
          status = totalLate > 0 || totalEarly > 0 ? '$status • $extra' : extra;
        } else {
          status = totalLate > 0 || totalEarly > 0
              ? '$status • Thiếu chấm'
              : 'Thiếu chấm';
        }
        statusColor = Colors.orange;
      }

      records.add(DailyShiftRecord(
        employeeId: employeeCode,
        employeeName: first.employeeName?.isNotEmpty == true
            ? first.employeeName!
            : (first.deviceUserName?.isNotEmpty == true
                ? first.deviceUserName!
                : '-'),
        employeeCode: first.employeeId ?? first.enrollNumber ?? '-',
        date: date,
        dayOfWeek: _getDayOfWeekVN(date.weekday),
        punchTimes: punchTimes,
        attendanceIds: attendanceIds,
        shiftNames: shiftNames,
        lateMinutes: totalLate,
        earlyMinutes: totalEarly,
        overtimeMinutes: totalOT,
        workHours: totalWorkHours,
        decimalHours: totalDecimalHours,
        status: status,
        statusColor: statusColor,
        workCount: totalWorkCount,
      ));
    });
  });

  records.sort((a, b) {
    final nameComp = a.employeeName.compareTo(b.employeeName);
    if (nameComp != 0) return nameComp;
    return a.date.compareTo(b.date);
  });
  return records;
}

/// Tra cứu record ca/ngày theo khóa `employeeKey|yyyy-MM-dd` (cùng khóa nhóm log).
Map<String, DailyShiftRecord> dailyShiftRecordByAttendanceKey(
  List<DailyShiftRecord> records,
) {
  final map = <String, DailyShiftRecord>{};
  for (final r in records) {
    final dk = DateFormat('yyyy-MM-dd').format(r.date);
    void put(String key) {
      if (key.isEmpty || key == '-') return;
      map['$key|$dk'] = r;
    }

    put(r.employeeId);
    put(r.employeeCode);
  }
  return map;
}

/// Một dòng đi trễ / về sớm cho riêng từng ca trong ngày của một nhân viên.
/// Khác với [DailyShiftRecord] (gộp theo ngày), bản ghi này được phát sinh
/// CHO MỖI CA — phục vụ Dashboard hiển thị chi tiết "đi trễ từng ca không
/// gộp chung lại 1 ngày".
class DailyShiftLateEntry {
  final String employeeId;
  final String employeeCode;
  final String employeeName;
  final DateTime date;
  final String shiftName;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int lateMinutes;
  final int earlyMinutes;

  DailyShiftLateEntry({
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.date,
    required this.shiftName,
    required this.checkIn,
    required this.checkOut,
    required this.lateMinutes,
    required this.earlyMinutes,
  });
}

/// Trả về danh sách per-ca có đi trễ HOẶC về sớm.
/// Cùng pairing logic với [computeDailyShiftRecords] nhưng yield 1 entry / ca.
List<DailyShiftLateEntry> computeDailyShiftLateEntries({
  required List<Attendance> attendances,
  required DateTime fromDate,
  required DateTime toDate,
  List<Map<String, dynamic>> shiftTemplates = const [],
  List<Map<String, dynamic>> shiftSalaryLevels = const [],
  List<Map<String, dynamic>> salaryProfiles = const [],
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final pairs = computeDailyShiftPairs(
    attendances: attendances,
    fromDate: fromDate,
    toDate: toDate,
    shiftTemplates: shiftTemplates,
    shiftSalaryLevels: shiftSalaryLevels,
    salaryProfiles: salaryProfiles,
    dayEndHour: dayEndHour,
    dayEndMinute: dayEndMinute,
  );
  return pairs
      .where((p) => p.lateMinutes > 0 || p.earlyMinutes > 0)
      .map((p) => DailyShiftLateEntry(
            employeeId: p.employeeId,
            employeeCode: p.employeeCode,
            employeeName: p.employeeName,
            date: p.date,
            shiftName: p.shiftName,
            checkIn: p.checkIn,
            checkOut: p.checkOut,
            lateMinutes: p.lateMinutes,
            earlyMinutes: p.earlyMinutes,
          ))
      .toList();
}

/// Một dòng pair (ca) trong ngày — bao gồm tất cả ca, không lọc theo trễ/sớm.
/// Dùng cho realtime attendance card để hiển thị mỗi ca riêng.
class DailyShiftPair {
  final String employeeId;
  final String employeeCode;
  final String employeeName;
  final DateTime date;
  final String shiftName;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int lateMinutes;
  final int earlyMinutes;
  final bool hasMatchedShift;
  final bool isOvernight;
  /// Id ca (ShiftTemplate) — dùng tra bậc lương ca theo từng ca.
  final String? shiftTemplateId;

  DailyShiftPair({
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.date,
    required this.shiftName,
    required this.checkIn,
    required this.checkOut,
    required this.lateMinutes,
    required this.earlyMinutes,
    required this.hasMatchedShift,
    this.isOvernight = false,
    this.shiftTemplateId,
  });
}

List<DailyShiftPair> computeDailyShiftPairs({
  required List<Attendance> attendances,
  required DateTime fromDate,
  required DateTime toDate,
  List<Map<String, dynamic>> shiftTemplates = const [],
  List<Map<String, dynamic>> shiftSalaryLevels = const [],
  List<Map<String, dynamic>> salaryProfiles = const [],
  List<Map<String, dynamic>>? employeesList,
  int dayEndHour = 0,
  int dayEndMinute = 0,
}) {
  final lookups = _ShiftLookups.build(
    shiftTemplates: shiftTemplates,
    shiftSalaryLevels: shiftSalaryLevels,
    salaryProfiles: salaryProfiles,
    employeesList: employeesList,
  );

  final filtered = _filterByLogicalWorkDayRange(
    attendances,
    fromDate,
    toDate,
    dayEndHour: dayEndHour,
    dayEndMinute: dayEndMinute,
  );

  final Map<String, Map<String, List<Attendance>>> grouped = {};
  for (final att in filtered) {
    final empKey = att.employeeId ?? att.enrollNumber ?? 'unknown';
    final logicalDate =
        _getLogicalDate(att.punchTime, dayEndHour, dayEndMinute);
    final dateKey = DateFormat('yyyy-MM-dd').format(logicalDate);
    grouped.putIfAbsent(empKey, () => {});
    grouped[empKey]!.putIfAbsent(dateKey, () => []).add(att);
  }

  final pairs = <DailyShiftPair>[];
  grouped.forEach((employeeCode, dateMap) {
    dateMap.forEach((dateStr, dayAttendances) {
      if (dayAttendances.isEmpty) return;
      dayAttendances.sort((a, b) => a.punchTime.compareTo(b.punchTime));
      final first = dayAttendances.first;
      final date = DateTime.parse(dateStr);

      final empGuid = lookups.employeeCodeToGuid[employeeCode] ?? '';
      final assignedShiftIds =
          lookups.employeeGuidToShiftTemplateIds[empGuid] ?? [];
      final usedShiftIds = <String>{};
      final dayPairs = _logicalDayPairsFromAttendances(
        dayAttendances,
        dayEndHour: dayEndHour,
        dayEndMinute: dayEndMinute,
      );

      for (var pairIndex = 0; pairIndex < dayPairs.length; pairIndex++) {
        final pair = dayPairs[pairIndex];
        DateTime? punchIn = pair.checkIn;
        final punchOut = pair.checkOut;

        Map<String, dynamic>? matchedShift;
        if (pair.isOrphanOut && punchOut != null) {
          final outMin = _dateTimeToMinutes(punchOut);
          matchedShift = matchShiftForOrphanCheckOut(
            checkOutMinutes: outMin,
            candidateIds: assignedShiftIds,
            shiftTemplateMap: lookups.shiftTemplateMap,
            usedShiftIds: usedShiftIds,
            pairIndex: pairIndex,
          );
          if (matchedShift != null) {
            final prevOut = pairIndex > 0
                ? dayPairs[pairIndex - 1].checkOut
                : null;
            punchIn = inferAdminCheckInForOrphanOut(
              checkOut: punchOut,
              matchedShift: matchedShift,
              previousCheckOut: prevOut,
            );
          }
        }

        if (punchIn == null) continue;

        final punchInMinutes = _dateTimeToMinutes(punchIn);
        final punchOutMinutes =
            punchOut != null ? _dateTimeToMinutes(punchOut) : null;
        matchedShift ??= lookups.findMatchingShift(
          punchInMinutes,
          assignedShiftIds,
          punchOutMinutes: punchOutMinutes,
          usedShiftIds: usedShiftIds,
          pairIndex: pairIndex,
        );
        if (matchedShift != null) {
          final shiftId = matchedShift['id']?.toString() ?? '';
          if (shiftId.isNotEmpty) usedShiftIds.add(shiftId);
        }

        String shiftName;
        String? pairShiftTemplateId;
        int lateCalc = 0;
        int earlyCalc = 0;
        final isOtShift = isOvertimeShiftTemplate(matchedShift);
        if (matchedShift != null) {
          pairShiftTemplateId = matchedShift['id']?.toString();
          shiftName = matchedShift['name']?.toString() ?? '';
          if (!isOtShift) {
            final shiftStartMin =
                _parseTimeSpanToMinutes(matchedShift['startTime']?.toString());
            final shiftEndMin =
                _parseTimeSpanToMinutes(matchedShift['endTime']?.toString());
            final isCrossMidnight = shiftStartMin > shiftEndMin;
            final lateGrace =
                (matchedShift['lateGraceMinutes'] as num?)?.toInt() ?? 5;
            final earlyGrace =
                (matchedShift['earlyLeaveGraceMinutes'] as num?)?.toInt() ?? 5;

            if (isCrossMidnight) {
              if (punchInMinutes >= shiftStartMin) {
                lateCalc = punchInMinutes - shiftStartMin;
              } else if (punchInMinutes < shiftEndMin) {
                lateCalc = (1440 - shiftStartMin) + punchInMinutes;
              }
            } else if (punchInMinutes > shiftStartMin) {
              lateCalc = punchInMinutes - shiftStartMin;
            }
            if (lateCalc > 0 && lateCalc <= lateGrace) lateCalc = 0;

            if (punchOut != null) {
              final outMin = _dateTimeToMinutes(punchOut);
              if (isCrossMidnight) {
                if (outMin <= shiftEndMin) {
                  earlyCalc = shiftEndMin - outMin;
                } else if (outMin >= shiftStartMin) {
                  earlyCalc = (1440 - outMin) + shiftEndMin;
                }
              } else if (outMin < shiftEndMin) {
                earlyCalc = shiftEndMin - outMin;
              }
              if (earlyCalc > 0 && earlyCalc <= earlyGrace) earlyCalc = 0;
            }
          }
        } else {
          shiftName = 'Chưa xếp ca';
        }

        pairs.add(DailyShiftPair(
          employeeId: employeeCode,
          employeeCode: first.employeeId ?? first.enrollNumber ?? '-',
          employeeName: first.employeeName?.isNotEmpty == true
              ? first.employeeName!
              : (first.deviceUserName?.isNotEmpty == true
                  ? first.deviceUserName!
                  : '-'),
          date: date,
          shiftName: shiftName,
          checkIn: punchIn,
          checkOut: punchOut,
          lateMinutes: lateCalc,
          earlyMinutes: earlyCalc,
          hasMatchedShift: matchedShift != null,
          isOvernight: isOvernightShiftTemplate(matchedShift),
          shiftTemplateId: pairShiftTemplateId,
        ));
      }
    });
  });

  pairs.sort((a, b) {
    final dc = b.date.compareTo(a.date);
    if (dc != 0) return dc;
    final t1 = a.checkIn ?? a.date;
    final t2 = b.checkIn ?? b.date;
    return t2.compareTo(t1);
  });
  return pairs;
}

/// Công / giờ / trễ-sớm / tăng ca — lấy từ [DailyShiftRecord] (tab Tổng hợp theo ca).
class PayrollShiftAttendanceStats {
  final double workDays;
  final double totalWorkHours;
  final double standardHours;
  final double otHoursWeekday;
  final double otHoursWeekend;
  final double otHoursHoliday;
  final int lateCount;
  final int lateMinutes;
  final int earlyCount;
  final int earlyMinutes;
  final int totalShifts;
  final int overnightShifts;

  const PayrollShiftAttendanceStats({
    this.workDays = 0,
    this.totalWorkHours = 0,
    this.standardHours = 0,
    this.otHoursWeekday = 0,
    this.otHoursWeekend = 0,
    this.otHoursHoliday = 0,
    this.lateCount = 0,
    this.lateMinutes = 0,
    this.earlyCount = 0,
    this.earlyMinutes = 0,
    this.totalShifts = 0,
    this.overnightShifts = 0,
  });
}

/// Gộp records ca/ngày của một NV thành chỉ số dùng cho bảng lương.
PayrollShiftAttendanceStats aggregatePayrollStatsFromShiftRecords({
  required List<DailyShiftRecord> records,
  required double standardDayHours,
  required List<DailyShiftPair> shiftPairs,
}) {
  double workDays = 0;
  double totalWorkHours = 0;
  double standardHours = 0;
  double otHoursWeekday = 0;
  double otHoursWeekend = 0;
  double otHoursHoliday = 0;
  int lateCount = 0;
  int lateMinutes = 0;
  int earlyCount = 0;
  int earlyMinutes = 0;

  for (final r in records) {
    if (r.lateMinutes > 0) {
      lateCount++;
      lateMinutes += r.lateMinutes;
    }
    if (r.earlyMinutes > 0) {
      earlyCount++;
      earlyMinutes += r.earlyMinutes;
    }

    final hrs = r.workHours;
    totalWorkHours += hrs;

    if (r.status.contains('Tăng ca ngày lễ')) {
      otHoursHoliday += hrs;
      continue;
    }
    if (r.status.contains('Tăng ca ngày nghỉ')) {
      otHoursWeekend += hrs;
      continue;
    }

    if (r.workCount <= 0) continue;

    workDays += r.workCount;
    if (hrs <= standardDayHours) {
      standardHours += hrs;
    } else {
      standardHours += standardDayHours;
      otHoursWeekday += hrs - standardDayHours;
    }
  }

  final completedPairs =
      shiftPairs.where((p) => p.checkOut != null).toList();
  final totalShifts = completedPairs.length;
  final overnightShifts =
      completedPairs.where((p) => p.isOvernight).length;

  return PayrollShiftAttendanceStats(
    workDays: workDays,
    totalWorkHours: totalWorkHours,
    standardHours: standardHours,
    otHoursWeekday: otHoursWeekday,
    otHoursWeekend: otHoursWeekend,
    otHoursHoliday: otHoursHoliday,
    lateCount: lateCount,
    lateMinutes: lateMinutes,
    earlyCount: earlyCount,
    earlyMinutes: earlyMinutes,
    totalShifts: totalShifts,
    overnightShifts: overnightShifts,
  );
}

/// Parse employeeIds từ ShiftSalaryLevel (JSON string hoặc list).
List<String> parseShiftSalaryLevelEmployeeIds(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }
  if (raw is String && raw.isNotEmpty) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        return parsed.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
  }
  return [];
}

/// Tìm bậc lương ca: ưu tiên mức gán NV, sau đó mức mặc định (employeeIds rỗng).
Map<String, dynamic>? findShiftSalaryLevelForPair({
  required List<Map<String, dynamic>> shiftSalaryLevels,
  required String shiftTemplateId,
  required String employeeGuid,
}) {
  if (shiftTemplateId.isEmpty) return null;

  Map<String, dynamic>? defaultLevel;
  for (final level in shiftSalaryLevels) {
    if (level['isActive'] == false) continue;
    if (level['shiftTemplateId']?.toString() != shiftTemplateId) continue;

    final empIds = parseShiftSalaryLevelEmployeeIds(level['employeeIds']);
    if (empIds.isEmpty) {
      defaultLevel ??= level;
      continue;
    }
    if (employeeGuid.isNotEmpty && empIds.contains(employeeGuid)) {
      return level;
    }
  }
  return defaultLevel;
}

/// Giờ làm thực tế của một cặp chấm công (check-in → check-out).
double dailyShiftPairWorkHours(DailyShiftPair pair) {
  final checkIn = pair.checkIn;
  final checkOut = pair.checkOut;
  if (checkIn == null || checkOut == null) return 0;

  var out = checkOut;
  if (out.isBefore(checkIn)) {
    out = out.add(const Duration(days: 1));
  }
  final mins = out.difference(checkIn).inMinutes;
  return mins > 0 ? mins / 60.0 : 0;
}

double _shiftSalaryFieldDouble(dynamic v, [double fallback = 0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

/// Kết quả lương cho một ca hoàn thành.
class ShiftPairPayrollResult {
  final double salary;
  final double allowance;
  final double effectiveHourlyRate;

  const ShiftPairPayrollResult({
    required this.salary,
    required this.allowance,
    required this.effectiveHourlyRate,
  });
}

/// Tính lương một ca: tra bậc lương ca hoặc fallback [fallbackFixedShiftRate].
ShiftPairPayrollResult calcShiftPairPayroll({
  required DailyShiftPair pair,
  required Map<String, dynamic>? level,
  required double fallbackFixedShiftRate,
  required double standardDayHours,
}) {
  final overnightCoef = pair.isOvernight ? 1.3 : 1.0;
  final pairHours = dailyShiftPairWorkHours(pair);

  if (level == null) {
    final amount = fallbackFixedShiftRate * overnightCoef;
    final effHourly = standardDayHours > 0
        ? fallbackFixedShiftRate / standardDayHours
        : 0.0;
    return ShiftPairPayrollResult(
      salary: amount,
      allowance: 0,
      effectiveHourlyRate: effHourly,
    );
  }

  final lvlRateType = level['rateType']?.toString() ?? 'fixed';
  final allowance = _shiftSalaryFieldDouble(level['shiftAllowance']);
  final lvlFixedRate =
      _shiftSalaryFieldDouble(level['fixedRate'], fallbackFixedShiftRate);
  final lvlHourlyRate = _shiftSalaryFieldDouble(level['hourlyRate']);
  final lvlMultiplier = _shiftSalaryFieldDouble(level['multiplier'], 1.0);

  switch (lvlRateType) {
    case 'hourly':
      final effHourly = lvlHourlyRate > 0
          ? lvlHourlyRate
          : (standardDayHours > 0
              ? fallbackFixedShiftRate / standardDayHours
              : 0.0);
      var amount = effHourly * pairHours;
      if (pair.isOvernight && standardDayHours > 0) {
        amount += effHourly * standardDayHours * 0.3;
      }
      return ShiftPairPayrollResult(
        salary: amount,
        allowance: allowance,
        effectiveHourlyRate: effHourly,
      );
    case 'multiplier':
      final perShift = fallbackFixedShiftRate * lvlMultiplier;
      final amount = perShift * overnightCoef;
      final effHourly =
          standardDayHours > 0 ? perShift / standardDayHours : 0.0;
      return ShiftPairPayrollResult(
        salary: amount,
        allowance: allowance,
        effectiveHourlyRate: effHourly,
      );
    default:
      final fixed = lvlFixedRate > 0 ? lvlFixedRate : fallbackFixedShiftRate;
      final amount = fixed * overnightCoef;
      final effHourly = standardDayHours > 0 ? fixed / standardDayHours : 0.0;
      return ShiftPairPayrollResult(
        salary: amount,
        allowance: allowance,
        effectiveHourlyRate: effHourly,
      );
  }
}

/// Tổng lương ca + phụ cấp ca — cộng dồn theo từng ca hoàn thành.
class ShiftBasedPayrollTotals {
  final double workSalary;
  final double shiftAllowance;
  final double hourlyRate;

  const ShiftBasedPayrollTotals({
    required this.workSalary,
    required this.shiftAllowance,
    required this.hourlyRate,
  });
}

ShiftBasedPayrollTotals calcShiftBasedPayrollFromPairs({
  required List<DailyShiftPair> shiftPairs,
  required List<Map<String, dynamic>> shiftSalaryLevels,
  required String employeeGuid,
  required double fallbackFixedShiftRate,
  required double standardDayHours,
  required double totalWorkHours,
}) {
  double workSalary = 0;
  double shiftAllowance = 0;
  double hourlyRateSum = 0;
  int pairCount = 0;

  final completedPairs = shiftPairs.where((p) => p.checkOut != null).toList();
  for (final pair in completedPairs) {
    final level = findShiftSalaryLevelForPair(
      shiftSalaryLevels: shiftSalaryLevels,
      shiftTemplateId: pair.shiftTemplateId ?? '',
      employeeGuid: employeeGuid,
    );
    final result = calcShiftPairPayroll(
      pair: pair,
      level: level,
      fallbackFixedShiftRate: fallbackFixedShiftRate,
      standardDayHours: standardDayHours,
    );
    workSalary += result.salary;
    shiftAllowance += result.allowance;
    if (result.effectiveHourlyRate > 0) {
      hourlyRateSum += result.effectiveHourlyRate;
      pairCount++;
    }
  }

  final hourlyRate = totalWorkHours > 0
      ? workSalary / totalWorkHours
      : (pairCount > 0
          ? hourlyRateSum / pairCount
          : (standardDayHours > 0
              ? fallbackFixedShiftRate / standardDayHours
              : 0.0));

  return ShiftBasedPayrollTotals(
    workSalary: workSalary,
    shiftAllowance: shiftAllowance,
    hourlyRate: hourlyRate,
  );
}
