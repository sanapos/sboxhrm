import 'package:flutter/material.dart';

/// Định mức nhân sự theo ca / phòng ban / thứ trong tuần.
class StaffingQuotaUtils {
  static const weekdayLabels = [
    'T2',
    'T3',
    'T4',
    'T5',
    'T6',
    'T7',
    'CN',
  ];

  static List<Map<String, dynamic>> parseDailyQuotas(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Map<String, dynamic>? pickQuotaForDepartment(
    List<Map<String, dynamic>> quotas,
    String shiftId, {
    String? department,
  }) {
    if (department != null && department.trim().isNotEmpty) {
      final dept = quotas.cast<Map<String, dynamic>?>().firstWhere(
            (q) =>
                q != null &&
                q['shiftTemplateId']?.toString() == shiftId &&
                (q['department']?.toString() ?? '').toLowerCase() ==
                    department.toLowerCase(),
            orElse: () => null,
          );
      if (dept != null) return dept;
    }
    return quotas.cast<Map<String, dynamic>?>().firstWhere(
          (q) =>
              q != null &&
              q['shiftTemplateId']?.toString() == shiftId &&
              (q['department'] == null ||
                  q['department'].toString().trim().isEmpty),
          orElse: () => null,
        );
  }

  static (int min, int max) limitsForDate(
    Map<String, dynamic> quota,
    DateTime date,
  ) {
    final fallbackMin = (quota['minEmployees'] as num?)?.toInt() ?? 0;
    final fallbackMax = (quota['maxEmployees'] as num?)?.toInt() ?? 0;
    final daily = parseDailyQuotas(quota['dailyQuotas']);
    if (daily.isEmpty) return (fallbackMin, fallbackMax);

    final iso = date.weekday;
    for (final row in daily) {
      if ((row['dayOfWeek'] as num?)?.toInt() == iso) {
        return (
          (row['minEmployees'] as num?)?.toInt() ?? fallbackMin,
          (row['maxEmployees'] as num?)?.toInt() ?? fallbackMax,
        );
      }
    }
    return (fallbackMin, fallbackMax);
  }

  static int warningThreshold(Map<String, dynamic> quota) =>
      (quota['warningThreshold'] as num?)?.toInt() ?? 2;

  /// underMin | overMax | nearMax | ok | none
  static String statusForCount(
    Map<String, dynamic>? quota,
    DateTime date,
    int count,
  ) {
    if (quota == null) return 'none';
    final (min, max) = limitsForDate(quota, date);
    final warn = warningThreshold(quota);
    if (max > 0 && count > max) return 'overMax';
    if (min > 0 && count < min) return 'underMin';
    if (max > 0 && count >= max) return 'overMax';
    if (max > 0 && max - count <= warn) return 'nearMax';
    return 'ok';
  }

  static List<Map<String, dynamic>> defaultWeeklyRows({
    int min = 1,
    int max = 10,
  }) =>
      List.generate(
        7,
        (i) => {
          'dayOfWeek': i + 1,
          'minEmployees': min,
          'maxEmployees': max,
        },
      );

  static Color colorForStatus(String status) {
    switch (status) {
      case 'overMax':
        return const Color(0xFFEF4444);
      case 'underMin':
        return const Color(0xFF3B82F6);
      case 'nearMax':
        return const Color(0xFFF59E0B);
      case 'ok':
        return const Color(0xFF22C55E);
      default:
        return const Color(0xFF71717A);
    }
  }

  static List<Map<String, dynamic>> quotasForShift(
    List<Map<String, dynamic>> quotas,
    String shiftId, {
    String? filterDepartment,
  }) {
    var list = quotas
        .where((q) => q['shiftTemplateId']?.toString() == shiftId)
        .toList();
    if (filterDepartment != null && filterDepartment.trim().isNotEmpty) {
      final f = filterDepartment.trim().toLowerCase();
      list = list
          .where((q) {
            final d = (q['department']?.toString() ?? '').trim().toLowerCase();
            return d.isEmpty || d == f;
          })
          .toList();
    }
    if (list.isEmpty) return [];
    final deptSpecific = list
        .where((q) => (q['department']?.toString() ?? '').trim().isNotEmpty)
        .toList();
    if (deptSpecific.isNotEmpty) return deptSpecific;
    return list;
  }

  static ShiftDayStaffingStatus evaluateShiftDay({
    required List<Map<String, dynamic>> quotas,
    required String shiftId,
    required DateTime date,
    required Map<String, int> countByDepartment,
    String? filterDepartment,
  }) {
    final applicable = quotasForShift(
      quotas,
      shiftId,
      filterDepartment: filterDepartment,
    );
    if (applicable.isEmpty) return ShiftDayStaffingStatus.empty;

    var hasUnderMin = false;
    var hasOverMax = false;
    var hasNearMax = false;
    final deptStatuses = <Map<String, dynamic>>[];

    for (final quota in applicable) {
      final dept = (quota['department']?.toString() ?? '').trim();
      int count;
      if (dept.isEmpty) {
        count = countByDepartment.values.fold<int>(0, (a, b) => a + b);
      } else {
        count = 0;
        for (final e in countByDepartment.entries) {
          if (e.key.toLowerCase() == dept.toLowerCase()) count += e.value;
        }
      }
      final status = statusForCount(quota, date, count);
      final (min, max) = limitsForDate(quota, date);
      deptStatuses.add({
        'department': dept.isEmpty ? 'Tất cả' : dept,
        'count': count,
        'min': min,
        'max': max,
        'status': status,
      });
      if (status == 'underMin') hasUnderMin = true;
      if (status == 'overMax') hasOverMax = true;
      if (status == 'nearMax') hasNearMax = true;
    }

    return ShiftDayStaffingStatus(
      hasUnderMin: hasUnderMin,
      hasOverMax: hasOverMax,
      hasNearMax: hasNearMax,
      departmentStatuses: deptStatuses,
    );
  }

  static List<Map<String, dynamic>> dailyRowsFromQuota(
    Map<String, dynamic>? quota, {
    int defaultMin = 1,
    int defaultMax = 10,
  }) {
    final daily = parseDailyQuotas(quota?['dailyQuotas']);
    final byDay = <int, Map<String, dynamic>>{};
    for (final row in daily) {
      final d = (row['dayOfWeek'] as num?)?.toInt();
      if (d != null && d >= 1 && d <= 7) byDay[d] = row;
    }
    final baseMin = (quota?['minEmployees'] as num?)?.toInt() ?? defaultMin;
    final baseMax = (quota?['maxEmployees'] as num?)?.toInt() ?? defaultMax;
    return List.generate(7, (i) {
      final day = i + 1;
      final existing = byDay[day];
      return {
        'dayOfWeek': day,
        'minEmployees':
            (existing?['minEmployees'] as num?)?.toInt() ?? baseMin,
        'maxEmployees':
            (existing?['maxEmployees'] as num?)?.toInt() ?? baseMax,
      };
    });
  }
}

/// Trạng thái định mức cho một ca + ngày (có thể nhiều phòng ban).
class ShiftDayStaffingStatus {
  final bool hasUnderMin;
  final bool hasOverMax;
  final bool hasNearMax;
  final List<Map<String, dynamic>> departmentStatuses;

  const ShiftDayStaffingStatus({
    required this.hasUnderMin,
    required this.hasOverMax,
    required this.hasNearMax,
    required this.departmentStatuses,
  });

  static const empty = ShiftDayStaffingStatus(
    hasUnderMin: false,
    hasOverMax: false,
    hasNearMax: false,
    departmentStatuses: [],
  );
}
