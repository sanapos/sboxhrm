/// Ca làm việc gắn trong thiết lập lương (Benefit.Description: shifts:...).
class LeaveSalaryShifts {
  static String parseDescField(String? description, String key) {
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
}
