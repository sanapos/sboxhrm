/// Ngày nghỉ tuần theo hồ sơ lương (ưu tiên paidLeaveType).
bool isEmployeeRestDay(
  DateTime day, {
  String? paidLeaveType,
  String? weeklyOffDays,
}) {
  final plt = (paidLeaveType ?? '').trim().toLowerCase();
  switch (plt) {
    case 'sunday':
      return day.weekday == DateTime.sunday;
    case 'saturday':
      return day.weekday == DateTime.saturday;
    case 'sat-sun':
      return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    case 'sat-afternoon-sun':
      // Chiều T7 nửa công — cả ngày T7 vẫn tính ngày làm việc sáng → chỉ CN nghỉ.
      return day.weekday == DateTime.sunday;
    case 'schedule':
      // Ngày nghỉ lấy từ Lịch làm việc (isDayOff) — không cố định T7/CN.
      return false;
    case 'off-1':
    case 'off-2':
    case 'off-3':
    case 'off-4':
      // Số ngày nghỉ cố định / tháng — không map theo weekday.
      return false;
  }

  // Không mặc định Chủ nhật khi trống (tránh OT nhầm khi làm CN).
  final weekly = (weeklyOffDays ?? '').trim();
  if (weekly.isEmpty) return false;
  if (weekly.contains('Sunday') && day.weekday == DateTime.sunday) return true;
  if (weekly.contains('Saturday') && day.weekday == DateTime.saturday) {
    return true;
  }
  return false;
}
