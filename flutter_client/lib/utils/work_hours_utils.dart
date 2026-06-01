/// Shared work-hours and payroll-period helpers (system AppSettings).
class WorkHoursUtils {
  static const String roundingNone = 'none';

  /// Round worked hours per [roundingRule] ?? from Thiết lập hệ thống.
  static double roundHours(double hours, String roundingRule) {
    if (hours <= 0) return 0;
    final rule = roundingRule.trim().toLowerCase();
    if (rule.isEmpty || rule == roundingNone) return hours;
    final minutes = (hours * 60).round();
    return roundMinutes(minutes, rule) / 60.0;
  }

  /// Round minutes: step = 15 for up/down/nearest.
  static int roundMinutes(int minutes, String rule) {
    if (minutes <= 0) return 0;
    const step = 15;
    switch (rule) {
      case 'round_up':
        return ((minutes + step - 1) ~/ step) * step;
      case 'round_down':
        return (minutes ~/ step) * step;
      case 'round_nearest':
        return ((minutes + step ~/ 2) ~/ step) * step;
      default:
        return minutes;
    }
  }

  /// Current open payroll cycle from [payrollCutoffDay] (1 = calendar month).
  static ({DateTime from, DateTime to}) currentPayrollCycle(
    int payrollCutoffDay,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = payrollCutoffDay.clamp(1, 31);
    if (cutoff == 1) {
      return (from: DateTime(today.year, today.month, 1), to: now);
    }
    final DateTime from;
    if (today.day > cutoff) {
      from = DateTime(today.year, today.month, cutoff + 1);
    } else {
      final prevMonth = DateTime(today.year, today.month - 1, 1);
      from = DateTime(prevMonth.year, prevMonth.month, cutoff + 1);
    }
    return (from: from, to: now);
  }

  /// Last closed payroll cycle (full period ending on cutoff day).
  static ({DateTime from, DateTime to}) lastClosedPayrollCycle(
    int payrollCutoffDay,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final cutoff = payrollCutoffDay.clamp(1, 31);
    if (cutoff == 1) {
      final start = DateTime(today.year, today.month - 1, 1);
      final end = DateTime(today.year, today.month, 0);
      return (from: start, to: DateTime(end.year, end.month, end.day, 23, 59, 59));
    }
    late DateTime periodEnd;
    late DateTime periodStart;
    if (today.day > cutoff) {
      periodEnd = DateTime(today.year, today.month, cutoff);
      periodStart = DateTime(periodEnd.year, periodEnd.month - 1, cutoff + 1);
    } else {
      periodEnd = DateTime(today.year, today.month - 1, cutoff);
      periodStart = DateTime(periodEnd.year, periodEnd.month - 1, cutoff + 1);
    }
    return (
      from: periodStart,
      to: DateTime(periodEnd.year, periodEnd.month, periodEnd.day, 23, 59, 59),
    );
  }

  /// Calendar month (cutoff = 1).
  static ({DateTime from, DateTime to}) calendarMonth(DateTime now) {
    return (
      from: DateTime(now.year, now.month, 1),
      to: now,
    );
  }

  /// Logical work date from [day_end_time] (punch before cutoff → previous day).
  static DateTime logicalWorkDate(
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

  /// Whether [date] is a paid weekly off day per Benefit settings.
  static bool isPaidWeeklyOff(
    DateTime date, {
    required String paidLeaveType,
    required String paidDayOff,
  }) {
    switch (paidLeaveType) {
      case 'sunday':
        return date.weekday == DateTime.sunday;
      case 'saturday':
        return date.weekday == DateTime.saturday;
      case 'sat-sun':
        return date.weekday == DateTime.saturday ||
            date.weekday == DateTime.sunday;
      case 'sat-afternoon-sun':
        return date.weekday == DateTime.sunday;
      case 'off-1':
      case 'off-2':
      case 'off-3':
      case 'off-4':
        return false;
      default:
        return (paidDayOff.contains('Sunday') &&
                date.weekday == DateTime.sunday) ||
            (paidDayOff.contains('Saturday') &&
                date.weekday == DateTime.saturday);
    }
  }

  /// Standard work days in [from]..[to] (inclusive calendar days).
  static double standardWorkDaysInRange({
    required DateTime from,
    required DateTime to,
    required String paidLeaveType,
    required String paidDayOff,
    int? fixedMonthlyStandardDays,
  }) {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return 0;

    int periodDays = 0;
    double offDays = 0;

    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      periodDays++;
      switch (paidLeaveType) {
        case 'sunday':
          if (d.weekday == DateTime.sunday) offDays++;
          break;
        case 'saturday':
          if (d.weekday == DateTime.saturday) offDays++;
          break;
        case 'sat-sun':
          if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
            offDays++;
          }
          break;
        case 'sat-afternoon-sun':
          if (d.weekday == DateTime.sunday) {
            offDays++;
          } else if (d.weekday == DateTime.saturday) {
            offDays += 0.5;
          }
          break;
        case 'off-1':
        case 'off-2':
        case 'off-3':
        case 'off-4':
          break;
        default:
          if ((paidDayOff.contains('Sunday') &&
                  d.weekday == DateTime.sunday) ||
              (paidDayOff.contains('Saturday') &&
                  d.weekday == DateTime.saturday)) {
            offDays++;
          }
      }
    }

    if (paidLeaveType == 'off-1' ||
        paidLeaveType == 'off-2' ||
        paidLeaveType == 'off-3' ||
        paidLeaveType == 'off-4') {
      final flatOff = switch (paidLeaveType) {
        'off-1' => 1.0,
        'off-2' => 2.0,
        'off-3' => 3.0,
        'off-4' => 4.0,
        _ => 0.0,
      };
      final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
      offDays = flatOff * periodDays / daysInMonth;
    }

    final computed = periodDays - offDays;
    if (fixedMonthlyStandardDays != null &&
        fixedMonthlyStandardDays > 0 &&
        (paidLeaveType == 'off-1' ||
            paidLeaveType == 'off-2' ||
            paidLeaveType == 'off-3' ||
            paidLeaveType == 'off-4')) {
      final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
      final prorated = fixedMonthlyStandardDays * periodDays / daysInMonth;
      return prorated > computed ? prorated : computed;
    }
    return computed;
  }
}
