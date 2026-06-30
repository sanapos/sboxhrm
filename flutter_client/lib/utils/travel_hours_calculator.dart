import '../models/mobile_attendance.dart';

/// Loại chấm mobile: 0 vào, 1 ra, 2 bắt đầu đi, 3 đến điểm làm.
const int mobilePunchCheckIn = 0;
const int mobilePunchCheckOut = 1;
const int mobilePunchTravelStart = 2;
const int mobilePunchTravelArrive = 3;

bool isTravelPunchType(int punchType) =>
    punchType == mobilePunchTravelStart || punchType == mobilePunchTravelArrive;

String travelPunchTypeLabel(int punchType) {
  switch (punchType) {
    case mobilePunchTravelStart:
      return 'Bắt đầu đi';
    case mobilePunchTravelArrive:
      return 'Đến điểm làm';
    default:
      return 'Đi đường';
  }
}

/// Tổng giờ đi đường từ cặp Bắt đầu đi (2) → Đến điểm làm (3).
/// Chỉ tính bản ghi đã duyệt / tự duyệt. Hỗ trợ qua đêm nhiều ngày.
double computeTravelHoursFromMobileRecords(List<MobileAttendanceRecord> records) {
  final sorted = records
      .where((r) =>
          isTravelPunchType(r.punchType) &&
          (r.status == 'approved' || r.status == 'auto_approved'))
      .toList()
    ..sort((a, b) => a.punchTime.compareTo(b.punchTime));

  double totalHours = 0;
  DateTime? pendingStart;
  for (final r in sorted) {
    if (r.punchType == mobilePunchTravelStart) {
      pendingStart = r.punchTime;
    } else if (r.punchType == mobilePunchTravelArrive && pendingStart != null) {
      final end = r.punchTime;
      if (!end.isBefore(pendingStart)) {
        totalHours += end.difference(pendingStart).inMinutes / 60.0;
      }
      pendingStart = null;
    }
  }
  return totalHours;
}

/// Gom giờ đi đường theo mã / id nhân viên (OdooEmployeeId hoặc employee code).
Map<String, double> travelHoursByEmployeeKey(
  List<MobileAttendanceRecord> records,
) {
  final byEmp = <String, List<MobileAttendanceRecord>>{};
  for (final r in records) {
    if (!isTravelPunchType(r.punchType)) continue;
    final key = r.odooEmployeeId.trim();
    if (key.isEmpty) continue;
    byEmp.putIfAbsent(key, () => []).add(r);
  }
  final out = <String, double>{};
  byEmp.forEach((key, list) {
    out[key] = computeTravelHoursFromMobileRecords(list);
  });
  return out;
}
