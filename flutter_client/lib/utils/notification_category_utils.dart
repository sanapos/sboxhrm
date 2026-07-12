/// Canonical notification category codes (aligned with server seed).
class NotificationCategoryUtils {
  NotificationCategoryUtils._();

  static const attendanceGroupCodes = {'attendance', 'device', 'travel_attendance'};

  static const entityTypeToCategory = {
    'attendance': 'attendance',
    'attendancecorrection': 'approval',
    'correction': 'approval',
    'device': 'device',
    'devicestatus': 'device',
    'admsdevice': 'device',
    'newattendance': 'attendance',
    'mobileattendance': 'attendance',
    'travelattendance': 'travel_attendance',
    'authorizedmobiledevice': 'attendance',
    'devicechangerequest': 'attendance',
    'mobiledeviceregistration': 'attendance',
    'communication': 'internal_comm',
    'workschedule': 'attendance',
    'scheduleregistration': 'approval',
    'shiftswap': 'shift',
    'shift': 'shift',
    'leave': 'leave',
    'leaverequest': 'leave',
    'advancerequest': 'payroll',
    'businesstripcase': 'business_trip',
    'businesstripexpense': 'business_trip',
    'penaltyticket': 'penalty',
    'worktask': 'task',
    'paymenttransaction': 'transaction',
    'cashtransaction': 'transaction',
    'possaleorder': 'pos',
    'posproduct': 'pos',
    'pospurchasereceipt': 'pos',
    'mealsession': 'meal',
    'mealmenu': 'meal',
    'mealrecord': 'meal',
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
      case 'department':
      case 'account':
        return 'hr';
      case 'transaction':
      case 'cashtransaction':
        return 'transaction';
      case 'mobile_attendance':
        return 'attendance';
      case 'travel_attendance':
        return 'travel_attendance';
      case 'penalty':
      case 'penaltyticket':
        return 'penalty';
      case 'allowance':
        return 'payroll';
      case 'meal':
        return 'meal';
      case 'store':
      case 'license':
        return 'system';
      case 'shift':
        return 'shift';
      case 'pos':
      case 'possaleorder':
      case 'posproduct':
      case 'pospurchasereceipt':
        return 'pos';
      case 'business_trip':
      case 'businesstrip':
      case 'businesstripcase':
      case 'businesstripexpense':
        return 'business_trip';
      case 'task':
      case 'worktask':
        return 'task';
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
