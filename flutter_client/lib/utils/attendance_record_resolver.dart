import 'package:intl/intl.dart';



import '../models/attendance.dart';



/// Kiểm tra chuỗi có phải GUID hợp lệ (API attendance id).

bool isValidAttendanceGuid(String? value) {

  if (value == null || value.isEmpty) return false;

  return RegExp(

    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',

  ).hasMatch(value.trim());

}



int _punchDeltaSeconds(DateTime a, DateTime b) =>

    a.difference(b).inSeconds.abs();



bool _matchesEmployee(Attendance att, Set<String> codes) {

  final keys = <String>{

    if (att.employeeId != null && att.employeeId!.isNotEmpty) att.employeeId!,

    if (att.enrollNumber != null && att.enrollNumber!.isNotEmpty)

      att.enrollNumber!,

    if (att.pin != null && att.pin!.isNotEmpty) att.pin!,

  };

  return codes.intersection(keys).isNotEmpty;

}



/// Tham chiếu log chấm công (id + PIN máy) khớp NV + ngày làm việc + giờ chấm.
class AttendancePunchRef {
  final String id;
  final String? pin;

  const AttendancePunchRef({required this.id, this.pin});
}

/// Tìm bản ghi chấm công trong danh sách đã tải (dùng trước khi xóa/sửa).
Attendance? findAttendanceForPunch({
  required List<Attendance> attendances,
  required String employeeKey,
  String? employeeCode,
  String? pin,
  required DateTime workDate,
  required DateTime punchTime,
  String? preferredId,
  DateTime Function(DateTime punchTime)? logicalDayOf,
}) =>
    _findAttendanceForPunch(
      attendances: attendances,
      employeeKey: employeeKey,
      employeeCode: employeeCode,
      pin: pin,
      workDate: workDate,
      punchTime: punchTime,
      preferredId: preferredId,
      logicalDayOf: logicalDayOf,
    );

Attendance? _findAttendanceForPunch({
  required List<Attendance> attendances,
  required String employeeKey,
  String? employeeCode,
  String? pin,
  required DateTime workDate,
  required DateTime punchTime,
  String? preferredId,
  DateTime Function(DateTime punchTime)? logicalDayOf,
}) {
  final dateKey = DateFormat('yyyy-MM-dd').format(workDate);
  final codes = <String>{
    if (employeeKey.isNotEmpty) employeeKey,
    if (employeeCode != null && employeeCode.isNotEmpty) employeeCode,
    if (pin != null && pin.isNotEmpty) pin,
  };

  Attendance? exact;
  Attendance? nearest;
  Attendance? preferredMatch;

  for (final att in attendances) {
    if (!_matchesEmployee(att, codes)) continue;

    final logical = logicalDayOf != null
        ? logicalDayOf(att.punchTime)
        : DateTime(
            att.punchTime.year,
            att.punchTime.month,
            att.punchTime.day,
          );
    if (DateFormat('yyyy-MM-dd').format(logical) != dateKey) continue;

    if (isValidAttendanceGuid(preferredId) && att.id == preferredId) {
      preferredMatch = att;
    }

    final delta = _punchDeltaSeconds(att.punchTime, punchTime);
    if (delta <= 120) {
      if (exact == null ||
          _punchDeltaSeconds(att.punchTime, punchTime) <
              _punchDeltaSeconds(exact.punchTime, punchTime)) {
        exact = att;
      }
    }

    if (att.punchTime.year == punchTime.year &&
        att.punchTime.month == punchTime.month &&
        att.punchTime.day == punchTime.day &&
        att.punchTime.hour == punchTime.hour &&
        att.punchTime.minute == punchTime.minute) {
      if (nearest == null ||
          _punchDeltaSeconds(att.punchTime, punchTime) <
              _punchDeltaSeconds(nearest.punchTime, punchTime)) {
        nearest = att;
      }
    }
  }

  final byTime = exact ?? nearest;
  if (byTime != null) return byTime;

  if (preferredMatch != null) {
    final delta = _punchDeltaSeconds(preferredMatch.punchTime, punchTime);
    if (delta <= 120) return preferredMatch;
  }

  return null;
}

AttendancePunchRef? resolveAttendancePunchRef({
  required List<Attendance> attendances,
  required String employeeKey,
  String? employeeCode,
  String? pin,
  required DateTime workDate,
  required DateTime punchTime,
  String? preferredId,
  DateTime Function(DateTime punchTime)? logicalDayOf,
}) {
  final pick = _findAttendanceForPunch(
    attendances: attendances,
    employeeKey: employeeKey,
    employeeCode: employeeCode,
    pin: pin,
    workDate: workDate,
    punchTime: punchTime,
    preferredId: preferredId,
    logicalDayOf: logicalDayOf,
  );
  if (pick == null || !isValidAttendanceGuid(pick.id)) return null;
  final devicePin = pick.pin?.trim();
  return AttendancePunchRef(
    id: pick.id,
    pin: devicePin != null && devicePin.isNotEmpty ? devicePin : pin,
  );
}

/// Tìm ID log chấm công theo NV + ngày + giờ (giây) khi summary thiếu punchId.
String? resolveAttendanceIdForPunch({
  required List<Attendance> attendances,
  required String employeeKey,
  String? employeeCode,
  String? pin,
  required DateTime workDate,
  required DateTime punchTime,
  String? preferredId,
  DateTime Function(DateTime punchTime)? logicalDayOf,
}) {
  return resolveAttendancePunchRef(
    attendances: attendances,
    employeeKey: employeeKey,
    employeeCode: employeeCode,
    pin: pin,
    workDate: workDate,
    punchTime: punchTime,
    preferredId: preferredId,
    logicalDayOf: logicalDayOf,
  )?.id;
}

