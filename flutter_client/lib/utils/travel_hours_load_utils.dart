import 'package:intl/intl.dart';

import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import 'travel_hours_calculator.dart';

/// Kết quả tải giờ đi đường từ mobile (đã mở rộng alias mã NV / GUID).
class TravelHoursMaps {
  const TravelHoursMaps({
    this.byEmployeeKey = const {},
    this.byEmployeeDateKey = const {},
  });

  final Map<String, double> byEmployeeKey;
  final Map<String, double> byEmployeeDateKey;

  static const empty = TravelHoursMaps();
}

final _dateKeyFmt = DateFormat('yyyy-MM-dd');

/// Giờ đi đường theo ngày đến điểm làm (chỉ bản ghi đã duyệt).
Map<String, double> travelHoursByEmployeeDateKey(
  List<MobileAttendanceRecord> records,
) {
  final byEmp = <String, List<MobileAttendanceRecord>>{};
  for (final r in records) {
    if (!isTravelPunchType(r.punchType)) continue;
    if (r.status != 'approved' && r.status != 'auto_approved') continue;
    final key = r.odooEmployeeId.trim();
    if (key.isEmpty) continue;
    byEmp.putIfAbsent(key, () => []).add(r);
  }

  final out = <String, double>{};
  for (final entry in byEmp.entries) {
    final list = entry.value
      ..sort((a, b) => a.punchTime.compareTo(b.punchTime));
    DateTime? pendingStart;
    for (final r in list) {
      if (r.punchType == mobilePunchTravelStart) {
        pendingStart = r.punchTime;
      } else if (r.punchType == mobilePunchTravelArrive &&
          pendingStart != null) {
        final end = r.punchTime;
        if (!end.isBefore(pendingStart)) {
          final hours = end.difference(pendingStart).inMinutes / 60.0;
          final dk = '${entry.key}|${_dateKeyFmt.format(end)}';
          out[dk] = (out[dk] ?? 0) + hours;
        }
        pendingStart = null;
      }
    }
  }
  return out;
}

void _aliasTravelKeys(
  Map<String, double> target,
  Map<String, double> source,
  List<String> aliases,
) {
  double? hours;
  for (final k in aliases) {
    final v = source[k];
    if (v != null && v > 0) {
      hours = v;
      break;
    }
  }
  if (hours == null || hours <= 0) return;
  for (final k in aliases) {
    if (k.isNotEmpty) target[k] = hours;
  }
}

void _aliasTravelDateKeys(
  Map<String, double> target,
  Map<String, double> source,
  List<String> aliases,
) {
  final dates = <String>{};
  for (final k in source.keys) {
    final i = k.indexOf('|');
    if (i > 0) dates.add(k.substring(i + 1));
  }
  for (final date in dates) {
    double? hours;
    for (final alias in aliases) {
      if (alias.isEmpty) continue;
      final v = source['$alias|$date'];
      if (v != null && v > 0) {
        hours = v;
        break;
      }
    }
    if (hours == null || hours <= 0) continue;
    for (final alias in aliases) {
      if (alias.isNotEmpty) target['$alias|$date'] = hours;
    }
  }
}

List<String> _employeeAliases(Map<String, dynamic> emp) {
  return [
    emp['id']?.toString() ?? '',
    emp['applicationUserId']?.toString() ?? '',
    emp['employeeCode']?.toString() ?? '',
    emp['pin']?.toString() ?? '',
    emp['employeeId']?.toString() ?? '',
  ].where((s) => s.trim().isNotEmpty).toList();
}

/// Tải giờ đi đường trong khoảng ngày (mobile Bắt đầu đi → Đến điểm làm).
Future<TravelHoursMaps> loadTravelHoursMaps({
  required ApiService api,
  required DateTime fromDate,
  required DateTime toDate,
  List<Map<String, dynamic>>? employeesList,
}) async {
  try {
    final toEnd = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59);
    // Chỉ lấy punch đi đường (2/3); pageSize cao vì history mặc định Take(200)
    // sẽ bỏ sót khi cửa hàng có nhiều chấm mobile trong tháng.
    final res = await api.getMobileAttendanceHistory(
      fromDate: DateTime(fromDate.year, fromDate.month, fromDate.day),
      toDate: toEnd,
      punchTypes: '2,3',
      pageSize: 5000,
    );
    if (res['isSuccess'] != true) return TravelHoursMaps.empty;
    final raw = res['data'];
    final dynamic list =
        raw is List ? raw : (raw is Map ? (raw['items'] ?? raw['records']) : null);
    if (list is! List) return TravelHoursMaps.empty;

    final records = list
        .whereType<Map>()
        .map((e) => MobileAttendanceRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final byEmp = Map<String, double>.from(travelHoursByEmployeeKey(records));
    final byDay = Map<String, double>.from(travelHoursByEmployeeDateKey(records));

    if (employeesList != null) {
      for (final emp in employeesList) {
        final aliases = _employeeAliases(emp);
        if (aliases.isEmpty) continue;
        _aliasTravelKeys(byEmp, byEmp, aliases);
        _aliasTravelDateKeys(byDay, byDay, aliases);
      }
    }

    return TravelHoursMaps(byEmployeeKey: byEmp, byEmployeeDateKey: byDay);
  } catch (_) {
    return TravelHoursMaps.empty;
  }
}

/// Tra cứu giờ đi đường một ngày (theo mã / GUID nhân viên).
double lookupTravelHoursForDay(
  Map<String, double> byEmployeeDateKey, {
  required DateTime date,
  String? employeeId,
  String? employeeCode,
  String? applicationUserId,
  String? employeeGuid,
  String? pin,
}) {
  final dateStr = _dateKeyFmt.format(date);
  for (final k in [
    applicationUserId,
    employeeGuid,
    employeeCode,
    employeeId,
    pin,
  ]) {
    if (k == null || k.trim().isEmpty) continue;
    final v = byEmployeeDateKey['${k.trim()}|$dateStr'];
    if (v != null && v > 0) return v;
  }
  return 0;
}

/// Tổng giờ đi đường cả kỳ (một nhân viên).
double lookupTravelHoursTotal(
  Map<String, double> byEmployeeKey, {
  String? employeeId,
  String? employeeCode,
  String? applicationUserId,
  String? employeeGuid,
  String? pin,
}) {
  for (final k in [
    applicationUserId,
    employeeGuid,
    employeeCode,
    employeeId,
    pin,
  ]) {
    if (k == null || k.trim().isEmpty) continue;
    final v = byEmployeeKey[k.trim()];
    if (v != null && v > 0) return v;
  }
  return 0;
}
