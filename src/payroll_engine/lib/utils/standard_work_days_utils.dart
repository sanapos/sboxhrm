/// Cách tính công chuẩn tháng trên hồ sơ lương nhân viên.
enum EmployeeStandardWorkMode {
  /// Số ngày trong tháng − ngày nghỉ có lương (weekday / off-N).
  monthMinusPaidLeave,

  /// Cố định N ngày (mặc định 26).
  fixedDays,
}

const String standardWorkModeAuto = 'Auto';
const String standardWorkModeFixedCustom = 'FixedCustom';

EmployeeStandardWorkMode parseEmployeeStandardWorkMode(
  Map<String, dynamic>? benefit,
) {
  final raw = (benefit?['standardWorkMode'] ?? benefit?['StandardWorkMode'])
      ?.toString()
      .trim();
  if (raw == null || raw.isEmpty) {
    return EmployeeStandardWorkMode.monthMinusPaidLeave;
  }
  final lower = raw.toLowerCase();
  if (lower == 'auto' || lower == '0') {
    return EmployeeStandardWorkMode.monthMinusPaidLeave;
  }
  // Fixed25…28, FixedCustom, or numeric enum > 0
  return EmployeeStandardWorkMode.fixedDays;
}

/// Số công cố định (1–31). Ưu tiên FixedStandardWorkDays; fallback Fixed25–28 / 26.
int parseFixedStandardWorkDays(Map<String, dynamic>? benefit,
    {int fallback = 26}) {
  final v =
      benefit?['fixedStandardWorkDays'] ?? benefit?['FixedStandardWorkDays'];
  if (v is num && v > 0) return v.round().clamp(1, 31);
  final parsed = int.tryParse(v?.toString() ?? '');
  if (parsed != null && parsed > 0) return parsed.clamp(1, 31);

  final mode =
      (benefit?['standardWorkMode'] ?? benefit?['StandardWorkMode'])?.toString();
  switch (mode) {
    case 'Fixed25':
      return 25;
    case 'Fixed26':
      return 26;
    case 'Fixed27':
      return 27;
    case 'Fixed28':
      return 28;
  }
  return fallback.clamp(1, 31);
}

bool parseDeductIfBelowFixedStandard(Map<String, dynamic>? benefit) {
  final v = benefit?['deductIfBelowFixedStandard'] ??
      benefit?['DeductIfBelowFixedStandard'];
  if (v == null) return true;
  if (v is bool) return v;
  return v.toString().toLowerCase() != 'false';
}

bool parseAddIfAboveFixedStandard(Map<String, dynamic>? benefit) {
  final v = benefit?['addIfAboveFixedStandard'] ??
      benefit?['AddIfAboveFixedStandard'];
  if (v == null) return true;
  if (v is bool) return v;
  return v.toString().toLowerCase() != 'false';
}

/// Công chuẩn lịch: số ngày tháng − ngày nghỉ có lương.
double calcCalendarStandardWorkDays({
  required int year,
  required int month,
  required String paidLeaveType,
  String paidDayOff = 'Sunday',
  /// Số ngày nghỉ isDayOff trên lịch phân ca trong tháng (paidLeaveType=schedule).
  int? scheduleDayOffCount,
}) {
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final monthStart = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month, daysInMonth);
  double offDays = 0;

  switch (paidLeaveType) {
    case 'sunday':
      for (var d = monthStart;
          !d.isAfter(monthEnd);
          d = d.add(const Duration(days: 1))) {
        if (d.weekday == DateTime.sunday) offDays++;
      }
      break;
    case 'saturday':
      for (var d = monthStart;
          !d.isAfter(monthEnd);
          d = d.add(const Duration(days: 1))) {
        if (d.weekday == DateTime.saturday) offDays++;
      }
      break;
    case 'sat-sun':
      for (var d = monthStart;
          !d.isAfter(monthEnd);
          d = d.add(const Duration(days: 1))) {
        if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          offDays++;
        }
      }
      break;
    case 'sat-afternoon-sun':
      for (var d = monthStart;
          !d.isAfter(monthEnd);
          d = d.add(const Duration(days: 1))) {
        if (d.weekday == DateTime.sunday) {
          offDays++;
        } else if (d.weekday == DateTime.saturday) {
          offDays += 0.5;
        }
      }
      break;
    case 'schedule':
      // Công chuẩn = số ngày tháng − ngày nghỉ trên lịch phân ca.
      // Chưa có lịch → không trừ (tránh mặc định CN).
      offDays = (scheduleDayOffCount ?? 0).toDouble();
      break;
    case 'off-1':
      offDays = 1;
      break;
    case 'off-2':
      offDays = 2;
      break;
    case 'off-3':
      offDays = 3;
      break;
    case 'off-4':
      offDays = 4;
      break;
    default:
      final weekly = paidDayOff.trim();
      if (weekly.isNotEmpty) {
        for (var d = monthStart;
            !d.isAfter(monthEnd);
            d = d.add(const Duration(days: 1))) {
          if ((weekly.contains('Sunday') && d.weekday == DateTime.sunday) ||
              (weekly.contains('Saturday') &&
                  d.weekday == DateTime.saturday)) {
            offDays++;
          }
        }
      }
  }

  final result = daysInMonth - offDays;
  return result > 0 ? result : daysInMonth.toDouble();
}

/// Kết quả công chuẩn dùng để chia lương tháng.
class ResolvedStandardWorkDays {
  const ResolvedStandardWorkDays({
    required this.mode,
    required this.divisor,
    required this.billableWorkDays,
    required this.rawWorkDays,
    required this.fixedDays,
    required this.calendarDays,
  });

  final EmployeeStandardWorkMode mode;

  /// Công chuẩn chia lương: dailyRate = Rate / divisor.
  final double divisor;

  /// Công tính lương: workSalary = dailyRate × billableWorkDays.
  final double billableWorkDays;

  /// Công thực tế từ chấm công.
  final double rawWorkDays;

  final int fixedDays;
  final double calendarDays;
}

///
/// Công thức lương tháng:
/// - `dailyRate = Rate / divisor`
/// - `workSalary = dailyRate × billableWorkDays`
///
/// **Auto (tháng − nghỉ có lương):**
/// - divisor = ngày tháng − nghỉ có lương
/// - billable = công thực tế (thiếu trừ, dư cộng tự nhiên)
///
/// **Cố định N ngày:**
/// - divisor = N (vd 26)
/// - Nếu công &lt; N và bật trừ → billable = công thực tế
/// - Nếu công &lt; N và tắt trừ → billable = N (trả đủ)
/// - Nếu công &gt; N và bật cộng → billable = công thực tế
/// - Nếu công &gt; N và tắt cộng → billable = N (không cộng dư)
ResolvedStandardWorkDays resolveStandardWorkDays({
  required Map<String, dynamic>? benefit,
  required int year,
  required int month,
  required double rawWorkDays,
  String? paidLeaveType,
  String paidDayOff = 'Sunday',
  int? scheduleDayOffCount,
}) {
  final mode = parseEmployeeStandardWorkMode(benefit);
  final leaveType =
      paidLeaveType ?? benefit?['paidLeaveType']?.toString() ?? 'sunday';
  final calendar = calcCalendarStandardWorkDays(
    year: year,
    month: month,
    paidLeaveType: leaveType,
    paidDayOff: paidDayOff,
    scheduleDayOffCount: scheduleDayOffCount,
  );
  final fixedDays = parseFixedStandardWorkDays(benefit);

  if (mode == EmployeeStandardWorkMode.monthMinusPaidLeave) {
    final divisor = calendar > 0 ? calendar : 26.0;
    return ResolvedStandardWorkDays(
      mode: mode,
      divisor: divisor,
      billableWorkDays: rawWorkDays,
      rawWorkDays: rawWorkDays,
      fixedDays: fixedDays,
      calendarDays: calendar,
    );
  }

  final divisor = fixedDays.toDouble();
  final deduct = parseDeductIfBelowFixedStandard(benefit);
  final add = parseAddIfAboveFixedStandard(benefit);
  double billable = rawWorkDays;

  if (rawWorkDays < divisor) {
    billable = deduct ? rawWorkDays : divisor;
  } else if (rawWorkDays > divisor) {
    billable = add ? rawWorkDays : divisor;
  } else {
    billable = rawWorkDays;
  }

  return ResolvedStandardWorkDays(
    mode: mode,
    divisor: divisor,
    billableWorkDays: billable,
    rawWorkDays: rawWorkDays,
    fixedDays: fixedDays,
    calendarDays: calendar,
  );
}
