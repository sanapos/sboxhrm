/// Canonical notification category codes (aligned with server seed).
class NotificationCategoryUtils {
  NotificationCategoryUtils._();

  static const attendanceGroupCodes = {'attendance', 'device'};

  static const entityTypeToCategory = {
    'attendance': 'attendance',
    'attendancecorrection': 'approval',
    'device': 'device',
    'devicestatus': 'device',
    'newattendance': 'attendance',
    'communication': 'internal_comm',
    'workschedule': 'attendance',
    'scheduleregistration': 'approval',
  };

  /// Maps legacy sender codes to seeded category codes.
  static String? normalizeCategory(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    switch (code.trim().toLowerCase()) {
      case 'communication':
        return 'internal_comm';
      case 'salary':
        return 'payroll';
      case 'employee':
        return 'hr';
      case 'transaction':
        return 'payroll';
      case 'mobile_attendance':
        return 'attendance';
      case 'penalty':
        return 'approval';
      case 'allowance':
        return 'payroll';
      case 'meal':
        return 'system';
      case 'department':
        return 'hr';
      case 'account':
        return 'hr';
      case 'store':
        return 'system';
      case 'license':
        return 'system';
      case 'shift':
        return 'attendance';
      default:
        return code.trim().toLowerCase();
    }
  }

  static bool isAttendanceCategory(String? code) {
    final normalized = normalizeCategory(code) ?? code?.toLowerCase();
    return normalized != null && attendanceGroupCodes.contains(normalized);
  }

  /// Resolve category for preference lookup / popup filtering.
  static String resolveCategory({
    String? categoryCode,
    String? relatedEntityType,
  }) {
    final fromPayload = normalizeCategory(categoryCode);
    if (fromPayload != null && fromPayload.isNotEmpty) return fromPayload;

    if (relatedEntityType != null && relatedEntityType.isNotEmpty) {
      final mapped = entityTypeToCategory[relatedEntityType.toLowerCase()];
      if (mapped != null) return mapped;
    }

    return 'system';
  }
}
