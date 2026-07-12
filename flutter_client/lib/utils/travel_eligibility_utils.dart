import '../models/mobile_attendance.dart';
import '../services/api_service.dart';

/// Các khóa nhận diện nhân viên (id, mã, userId, pin…) để khớp giờ đi đường / thiết bị.
Set<String> employeeTravelKeyAliases(Map<String, dynamic> emp) {
  final keys = <String>{};
  for (final k in [
    emp['id'],
    emp['employeeId'],
    emp['employeeCode'],
    emp['applicationUserId'],
    emp['pin'],
  ]) {
    final s = k?.toString().trim();
    if (s != null && s.isNotEmpty) keys.add(s);
  }
  return keys;
}

bool _deviceEmployeeMatches(Map<String, dynamic> emp, String deviceEmployeeId) {
  final target = deviceEmployeeId.trim().toLowerCase();
  if (target.isEmpty) return false;
  for (final alias in employeeTravelKeyAliases(emp)) {
    if (alias.toLowerCase() == target) return true;
  }
  return false;
}

bool isEmployeeTravelEligible({
  required Set<String> eligibleKeys,
  String? employeeId,
  String? employeeCode,
  String? applicationUserId,
  String? employeeGuid,
  String? pin,
}) {
  if (eligibleKeys.isEmpty) return false;
  for (final k in [
    employeeGuid,
    employeeId,
    applicationUserId,
    employeeCode,
    pin,
  ]) {
    final s = k?.trim();
    if (s != null && s.isNotEmpty && eligibleKeys.contains(s)) return true;
  }
  return false;
}

/// NV có thiết bị mobile đã duyệt và bật chấm đi đường.
Future<Set<String>> loadTravelEligibleEmployeeKeys(
  ApiService api, {
  List<Map<String, dynamic>>? employeesList,
}) async {
  final keys = <String>{};
  try {
    final res = await api.getAuthorizedDevices();
    if (res['isSuccess'] != true) return keys;
    final raw = res['data'] ?? res['items'] ?? res;
    if (raw is! List) return keys;

    for (final item in raw) {
      if (item is! Map) continue;
      final device = AuthorizedDevice.fromJson(Map<String, dynamic>.from(item));
      if (!device.isAuthorized || !device.allowTravelCheckIn) continue;

      final empId = device.employeeId?.trim();
      if (empId != null && empId.isNotEmpty) keys.add(empId);

      if (employeesList != null && empId != null && empId.isNotEmpty) {
        for (final emp in employeesList) {
          if (_deviceEmployeeMatches(emp, empId)) {
            keys.addAll(employeeTravelKeyAliases(emp));
          }
        }
      }
    }
  } catch (_) {}
  return keys;
}
