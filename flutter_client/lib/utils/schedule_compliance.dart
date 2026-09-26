import 'package:intl/intl.dart';

import 'shift_records_calculator.dart';

/// Trạng thái một ca khi đối chiếu lịch làm việc với chấm công thực tế.
enum ScheduleComplianceStatus {
  /// Có lịch, làm đúng ca, không trễ / sớm.
  onTime,
  /// Có lịch, làm đúng ca nhưng đi trễ hoặc về sớm.
  lateEarly,
  /// Có lịch, vào ca nhưng thiếu giờ ra.
  missingOut,
  /// Có lịch ca A nhưng chấm công khớp ca khác.
  wrongShift,
  /// Có lịch, không chấm công, không nghỉ phép.
  absent,
  /// Có lịch, không chấm công, đã có đơn nghỉ phép duyệt.
  onLeave,
  /// Chấm công trong ngày không có lịch / ngày nghỉ trên lịch / ca ngoài lịch.
  offSchedule,
}

String scheduleComplianceLabel(ScheduleComplianceStatus s) => switch (s) {
      ScheduleComplianceStatus.onTime => 'Đúng lịch',
      ScheduleComplianceStatus.lateEarly => 'Đi trễ / Về sớm',
      ScheduleComplianceStatus.missingOut => 'Thiếu chấm ra',
      ScheduleComplianceStatus.wrongShift => 'Sai ca',
      ScheduleComplianceStatus.absent => 'Vắng có lịch',
      ScheduleComplianceStatus.onLeave => 'Nghỉ phép',
      ScheduleComplianceStatus.offSchedule => 'Đi làm ngoài lịch',
    };

/// Một dòng đối chiếu (một ca có lịch, hoặc một ca làm ngoài lịch).
class ScheduleComplianceRow {
  final String employeeId;
  final String employeeCode;
  final String employeeName;
  final String department;
  final DateTime date;
  final String scheduledShift;
  final String actualShift;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final int lateMinutes;
  final int earlyMinutes;
  final ScheduleComplianceStatus status;

  const ScheduleComplianceRow({
    required this.employeeId,
    required this.employeeCode,
    required this.employeeName,
    required this.department,
    required this.date,
    required this.scheduledShift,
    required this.actualShift,
    required this.checkIn,
    required this.checkOut,
    required this.lateMinutes,
    required this.earlyMinutes,
    required this.status,
  });
}

/// Tổng hợp theo nhân viên hoặc phòng ban.
class ScheduleComplianceStat {
  final String key;
  final String label;
  final String department;
  final Map<ScheduleComplianceStatus, int> counts = {
    for (final s in ScheduleComplianceStatus.values) s: 0,
  };

  ScheduleComplianceStat(this.key, this.label, this.department);

  int count(ScheduleComplianceStatus s) => counts[s] ?? 0;

  /// Số ca có lịch (không tính ca làm ngoài lịch).
  int get scheduled => counts.entries
      .where((e) => e.key != ScheduleComplianceStatus.offSchedule)
      .fold(0, (a, e) => a + e.value);

  /// Ca có lịch cần có mặt (trừ nghỉ phép đã duyệt).
  int get expected => scheduled - count(ScheduleComplianceStatus.onLeave);

  /// Tỷ lệ tuân thủ = đúng lịch / ca cần có mặt.
  double? get complianceRate =>
      expected <= 0 ? null : count(ScheduleComplianceStatus.onTime) / expected;

  /// Tỷ lệ có mặt = (ca cần có mặt − vắng) / ca cần có mặt.
  double? get attendanceRate => expected <= 0
      ? null
      : (expected - count(ScheduleComplianceStatus.absent)) / expected;
}

class ScheduleComplianceResult {
  final List<ScheduleComplianceRow> rows;
  final List<ScheduleComplianceStat> byEmployee;
  final List<ScheduleComplianceStat> byDepartment;
  final ScheduleComplianceStat total;

  const ScheduleComplianceResult({
    required this.rows,
    required this.byEmployee,
    required this.byDepartment,
    required this.total,
  });
}

String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  final d = DateTime.tryParse(raw.toString());
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

/// Đối chiếu lịch (API /work-schedules) với kết quả [computeDailyShiftRecords] —
/// cùng bộ tính với «Tổng hợp chấm công theo ca».
///
/// [employees]: danh sách NV (id GUID, employeeCode, pin, tên, phòng ban) để quy mọi mã về GUID.
/// [isOnApprovedLeave]: (GUID NV, ngày) → có đơn nghỉ phép đã duyệt.
/// Chỉ xét «Đi làm ngoài lịch» cho NV có ít nhất một dòng lịch trong kỳ (cửa hàng không
/// xếp lịch cho NV đó thì không coi là ngoài lịch).
ScheduleComplianceResult computeScheduleCompliance({
  required List<Map<String, dynamic>> schedules,
  required List<DailyShiftRecord> records,
  required List<Map<String, dynamic>> employees,
  required DateTime fromDate,
  required DateTime toDate,
  bool Function(String employeeGuid, DateTime day)? isOnApprovedLeave,
}) {
  final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
  final to = DateTime(toDate.year, toDate.month, toDate.day);
  bool inRange(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  // Mọi mã (GUID, mã NV, PIN) → GUID.
  final toGuid = <String, String>{};
  final info = <String, Map<String, dynamic>>{};
  for (final e in employees) {
    final id = e['id']?.toString() ?? '';
    if (id.isEmpty) continue;
    info[id] = e;
    toGuid[id] = id;
    for (final k in [e['employeeCode'], e['pin'], e['code']]) {
      final v = k?.toString() ?? '';
      if (v.isNotEmpty) toGuid.putIfAbsent(v, () => id);
    }
  }
  String? guidOf(Iterable<String?> ids) {
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      final g = toGuid[id];
      if (g != null) return g;
    }
    return null;
  }

  // Lịch: GUID|ngày → danh sách (id ca, tên ca); ngày nghỉ trên lịch.
  final scheduled = <String, List<(String?, String)>>{};
  final dayOff = <String>{};
  final scheduledEmployees = <String>{};
  final names = <String, String>{};
  for (final s in schedules) {
    final date = _parseDate(s['date']);
    if (date == null || !inRange(date)) continue;
    final guid = guidOf([s['employeeUserId']?.toString(), s['employeeCode']?.toString()]) ??
        s['employeeUserId']?.toString() ??
        '';
    if (guid.isEmpty) continue;
    scheduledEmployees.add(guid);
    final n = s['employeeName']?.toString() ?? '';
    if (n.isNotEmpty) names.putIfAbsent(guid, () => n);
    final key = '$guid|${_dayKey(date)}';
    if (s['isDayOff'] == true) {
      dayOff.add(key);
      continue;
    }
    scheduled.putIfAbsent(key, () => []).add((
      s['shiftId']?.toString(),
      s['shiftName']?.toString() ?? '',
    ));
  }

  // Chấm công: GUID|ngày → các ca đã làm.
  final worked = <String, List<ShiftLateEarlyItem>>{};
  final recordNames = <String, String>{};
  for (final r in records) {
    if (!inRange(r.date)) continue;
    final guid = guidOf([r.employeeId, r.employeeCode]);
    if (guid == null) continue;
    recordNames.putIfAbsent(guid, () => r.employeeName);
    worked.putIfAbsent('$guid|${_dayKey(r.date)}', () => []).addAll(r.shiftItems);
  }

  final rows = <ScheduleComplianceRow>[];
  ScheduleComplianceRow row(String guid, DateTime date, String sched, ShiftLateEarlyItem? it,
      ScheduleComplianceStatus status) {
    final e = info[guid];
    final name = [e?['lastName'], e?['firstName']]
        .map((x) => x?.toString().trim() ?? '')
        .where((x) => x.isNotEmpty)
        .join(' ');
    return ScheduleComplianceRow(
      employeeId: guid,
      employeeCode: e?['employeeCode']?.toString() ?? '',
      employeeName: name.isNotEmpty
          ? name
          : (e?['fullName'] ?? e?['name'])?.toString() ??
              names[guid] ??
              recordNames[guid] ??
              '-',
      department: (e?['department'] ?? e?['departmentName'])?.toString().trim().isNotEmpty == true
          ? (e?['department'] ?? e?['departmentName']).toString().trim()
          : 'Chưa có phòng ban',
      date: date,
      scheduledShift: sched,
      actualShift: it == null ? '' : (it.shiftName.isEmpty ? 'Không khớp ca' : it.shiftName),
      checkIn: it?.checkIn,
      checkOut: it?.checkOut,
      lateMinutes: it?.lateMinutes ?? 0,
      earlyMinutes: it?.earlyMinutes ?? 0,
      status: status,
    );
  }

  final keys = {...scheduled.keys, ...worked.keys};
  for (final key in keys) {
    final sep = key.indexOf('|');
    final guid = key.substring(0, sep);
    final date = DateTime.parse(key.substring(sep + 1));
    final plan = scheduled[key] ?? const [];
    final items = List<ShiftLateEarlyItem>.from(worked[key] ?? const []);

    for (final (shiftId, shiftName) in plan) {
      // 1) Làm đúng ca đã xếp.
      final idx = items.indexWhere(
          (it) => shiftId != null && it.shiftTemplateId == shiftId);
      if (idx >= 0) {
        final it = items.removeAt(idx);
        final status = it.checkOut == null
            ? ScheduleComplianceStatus.missingOut
            : (it.lateMinutes > 0 || it.earlyMinutes > 0)
                ? ScheduleComplianceStatus.lateEarly
                : ScheduleComplianceStatus.onTime;
        rows.add(row(guid, date, shiftName, it, status));
        continue;
      }
      // 2) Có chấm công nhưng ca khác (hoặc không khớp ca nào) → sai ca.
      final other = items.indexWhere((it) =>
          it.shiftTemplateId == null ||
          !plan.any((p) => p.$1 != null && p.$1 == it.shiftTemplateId));
      if (other >= 0) {
        final it = items.removeAt(other);
        rows.add(row(guid, date, shiftName, it, ScheduleComplianceStatus.wrongShift));
        continue;
      }
      // 3) Không chấm công.
      final leave = isOnApprovedLeave?.call(guid, date) ?? false;
      rows.add(row(guid, date, shiftName, null,
          leave ? ScheduleComplianceStatus.onLeave : ScheduleComplianceStatus.absent));
    }

    // Ca còn lại = làm ngoài lịch (chỉ NV có dùng lịch trong kỳ).
    if (scheduledEmployees.contains(guid)) {
      for (final it in items) {
        rows.add(row(
          guid,
          date,
          dayOff.contains(key) ? 'Nghỉ (theo lịch)' : '',
          it,
          ScheduleComplianceStatus.offSchedule,
        ));
      }
    }
  }

  rows.sort((a, b) {
    final dc = b.date.compareTo(a.date);
    if (dc != 0) return dc;
    return a.employeeName.compareTo(b.employeeName);
  });

  final byEmp = <String, ScheduleComplianceStat>{};
  final byDept = <String, ScheduleComplianceStat>{};
  final total = ScheduleComplianceStat('all', 'Tất cả', '');
  for (final r in rows) {
    final e = byEmp.putIfAbsent(r.employeeId,
        () => ScheduleComplianceStat(r.employeeId, r.employeeName, r.department));
    final d = byDept.putIfAbsent(
        r.department, () => ScheduleComplianceStat(r.department, r.department, r.department));
    for (final s in [e, d, total]) {
      s.counts[r.status] = s.count(r.status) + 1;
    }
  }
  int byRate(ScheduleComplianceStat a, ScheduleComplianceStat b) =>
      (a.complianceRate ?? 2).compareTo(b.complianceRate ?? 2);

  return ScheduleComplianceResult(
    rows: rows,
    byEmployee: byEmp.values.toList()..sort(byRate),
    byDepartment: byDept.values.toList()..sort(byRate),
    total: total,
  );
}

/// Một ca trong ngày: định mức ↔ số người xếp lịch ↔ số người có mặt thực tế.
class ShiftStaffingRow {
  final DateTime date;
  final String shiftName;
  final int scheduled;
  final int present;
  final int lateEarly;
  final int absent;
  final int onLeave;
  final int wrongShift;
  final int? minRequired;
  final int? maxAllowed;

  const ShiftStaffingRow({
    required this.date,
    required this.shiftName,
    required this.scheduled,
    required this.present,
    required this.lateEarly,
    required this.absent,
    required this.onLeave,
    required this.wrongShift,
    this.minRequired,
    this.maxAllowed,
  });

  /// Có mặt thực tế so với định mức.
  String get status {
    final min = minRequired, max = maxAllowed;
    if (min == null) return 'Chưa có định mức';
    if (present < min) return 'Thiếu người';
    if (max != null && max > 0 && present > max) return 'Vượt định mức';
    return 'Đạt';
  }

  /// Lịch xếp so với định mức (xếp đủ nhưng vắng → thiếu thực tế).
  bool get scheduledShort => minRequired != null && scheduled < minRequired!;
}

/// Gom kết quả đối chiếu theo (ngày, ca theo lịch) và ghép định mức nhân sự
/// (`/work-schedules/staffing-quotas`): định mức chung (không phòng ban) nếu có,
/// không thì cộng các định mức theo phòng ban; ưu tiên định mức theo thứ trong tuần.
List<ShiftStaffingRow> computeShiftStaffing(
  List<ScheduleComplianceRow> rows,
  List<Map<String, dynamic>> quotas,
) {
  (int, int)? limitsFor(String shiftName, DateTime date) {
    final qs = quotas
        .where((q) => (q['shiftName']?.toString() ?? '').trim() == shiftName.trim())
        .toList();
    if (qs.isEmpty) return null;
    final general = qs.where((q) => (q['department']?.toString() ?? '').trim().isEmpty).toList();
    final use = general.isNotEmpty ? [general.first] : qs;
    var min = 0, max = 0;
    for (final q in use) {
      final daily = (q['dailyQuotas'] as List?)?.whereType<Map>().firstWhere(
            (d) => (d['dayOfWeek'] as num?)?.toInt() == date.weekday,
            orElse: () => const {},
          );
      min += ((daily?['minEmployees'] ?? q['minEmployees']) as num?)?.toInt() ?? 0;
      max += ((daily?['maxEmployees'] ?? q['maxEmployees']) as num?)?.toInt() ?? 0;
    }
    return (min, max);
  }

  final groups = <String, List<ScheduleComplianceRow>>{};
  for (final r in rows) {
    if (r.status == ScheduleComplianceStatus.offSchedule || r.scheduledShift.isEmpty) continue;
    groups.putIfAbsent('${_dayKey(r.date)}|${r.scheduledShift}', () => []).add(r);
  }
  final out = <ShiftStaffingRow>[];
  for (final g in groups.values) {
    int c(ScheduleComplianceStatus s) => g.where((r) => r.status == s).length;
    final limits = limitsFor(g.first.scheduledShift, g.first.date);
    out.add(ShiftStaffingRow(
      date: g.first.date,
      shiftName: g.first.scheduledShift,
      scheduled: g.length,
      present: c(ScheduleComplianceStatus.onTime) +
          c(ScheduleComplianceStatus.lateEarly) +
          c(ScheduleComplianceStatus.missingOut),
      lateEarly: c(ScheduleComplianceStatus.lateEarly),
      absent: c(ScheduleComplianceStatus.absent),
      onLeave: c(ScheduleComplianceStatus.onLeave),
      wrongShift: c(ScheduleComplianceStatus.wrongShift),
      minRequired: limits?.$1,
      maxAllowed: limits?.$2,
    ));
  }
  out.sort((a, b) {
    final d = b.date.compareTo(a.date);
    return d != 0 ? d : a.shiftName.compareTo(b.shiftName);
  });
  return out;
}
