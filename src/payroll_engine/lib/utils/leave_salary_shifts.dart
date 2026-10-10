import 'dart:convert';

/// Ca làm việc gắn trong thiết lập lương (Benefit.Description: shifts:...).
class LeaveSalaryShifts {  static String parseDescField(String? description, String key) {
    if (description == null || description.isEmpty) return '';
    for (final part in description.split('|')) {
      final idx = part.indexOf(':');
      if (idx <= 0) continue;
      if (part.substring(0, idx).trim().toLowerCase() == key.toLowerCase()) {
        return part.substring(idx + 1).trim();
      }
    }
    return '';
  }

  static String normalizeShiftName(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Trả về danh sách ShiftTemplate id từ hồ sơ lương + danh mục ca.
  static List<String> templateIdsFromSalaryProfile(
    Map<String, dynamic>? profile,
    List<dynamic> shiftTemplates,
  ) {
    if (profile == null) return [];

    final shiftNameToId = <String, String>{};
    for (final st in shiftTemplates) {
      if (st is! Map) continue;
      final id = st['id']?.toString() ?? '';
      final name = st['name']?.toString() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) {
        shiftNameToId[normalizeShiftName(name)] = id;
      }
    }

    String? description;
    final benefit = profile['benefit'];
    if (benefit is Map) {
      description = benefit['description']?.toString();
    }
    description ??= profile['description']?.toString();

    final shiftsStr = parseDescField(description, 'shifts');
    if (shiftsStr.isEmpty) return [];

    final ids = <String>[];
    for (final raw in shiftsStr.split(',')) {
      final norm = normalizeShiftName(raw);
      if (norm.isEmpty) continue;
      final id = shiftNameToId[norm];
      if (id != null && !ids.contains(id)) ids.add(id);
    }
    return ids;
  }

  /// Gộp ca từ ShiftSalaryLevel (employeeIds JSON) — fallback legacy.
  static void mergeShiftSalaryLevels(
    Map<String, List<String>> employeeGuidToShiftIds,
    List<Map<String, dynamic>> shiftSalaryLevels,
  ) {
    for (final ssl in shiftSalaryLevels) {
      final shiftTemplateId = ssl['shiftTemplateId']?.toString() ?? '';
      if (shiftTemplateId.isEmpty) continue;

      final employeeIdsRaw = ssl['employeeIds'];
      List<String> empIds = [];
      if (employeeIdsRaw is String && employeeIdsRaw.isNotEmpty) {
        try {
          final parsed = json.decode(employeeIdsRaw);
          if (parsed is List) {
            empIds = parsed.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      } else if (employeeIdsRaw is List) {
        empIds = employeeIdsRaw.map((e) => e.toString()).toList();
      }

      for (final empGuid in empIds) {
        if (empGuid.isEmpty) continue;
        final list = employeeGuidToShiftIds.putIfAbsent(empGuid, () => []);
        if (!list.contains(shiftTemplateId)) list.add(shiftTemplateId);
      }
    }
  }

  /// Map Employee.Id → danh sách ShiftTemplate id từ batch hồ sơ lương.
  static Map<String, List<String>> buildEmployeeShiftAssignmentMap({
    required List<Map<String, dynamic>> salaryProfiles,
    required List<dynamic> shiftTemplates,
    List<Map<String, dynamic>> shiftSalaryLevels = const [],
  }) {
    final map = <String, List<String>>{};

    for (final profile in salaryProfiles) {
      final profileShiftIds = templateIdsFromSalaryProfile(
        profile,
        shiftTemplates,
      );
      if (profileShiftIds.isEmpty) continue;

      final employees = profile['employees'] as List? ?? [];
      for (final emp in employees) {
        if (emp is! Map) continue;
        final guid = emp['id']?.toString() ?? '';
        if (guid.isEmpty) continue;
        final list = map.putIfAbsent(guid, () => []);
        for (final id in profileShiftIds) {
          if (!list.contains(id)) list.add(id);
        }
      }
    }

    mergeShiftSalaryLevels(map, shiftSalaryLevels);
    return map;
  }

  /// Ca được gán cho một nhân viên (hồ sơ lương + ShiftSalaryLevel).
  static List<String> assignedShiftIdsForEmployee({
    required String employeeGuid,
    required List<dynamic> shiftTemplates,
    Map<String, dynamic>? employeeBenefit,
    List<Map<String, dynamic>> salaryProfiles = const [],
    List<Map<String, dynamic>> shiftSalaryLevels = const [],
  }) {
    if (employeeGuid.isEmpty) return [];

    final ids = <String>{};

    if (employeeBenefit != null) {
      ids.addAll(templateIdsFromSalaryProfile(employeeBenefit, shiftTemplates));
    }

    for (final profile in salaryProfiles) {
      final employees = profile['employees'] as List? ?? [];
      final inProfile = employees.any(
        (e) => e is Map && (e['id']?.toString() ?? '') == employeeGuid,
      );
      if (!inProfile) continue;
      ids.addAll(templateIdsFromSalaryProfile(profile, shiftTemplates));
    }

    final levelMap = <String, List<String>>{};
    mergeShiftSalaryLevels(levelMap, shiftSalaryLevels);
    ids.addAll(levelMap[employeeGuid] ?? const []);

    return ids.toList();
  }
}