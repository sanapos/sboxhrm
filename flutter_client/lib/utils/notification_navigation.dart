import 'package:flutter/foundation.dart';

import 'navigation_notifier.dart';
import 'admin_navigation.dart';
import '../screens/settings_hub_screen.dart';

/// Đích điều hướng khi user bấm thông báo (in-app, system tray, FCM).
class NotificationNavigationTarget {
  /// Khớp [NavItem.moduleCode] trong main_layout — không dùng index cứng.
  final String moduleCode;
  final int? settingsHubSubIndex;
  final int? scheduleApprovalTab;
  final int? attendanceApprovalTab;
  final int? attendanceApprovalStatusFilter;
  /// Tab trong [MobileAttendanceSettingsScreen]: 0=cài đặt, 1=vị trí, 2=thiết bị
  final int? mobileAttendanceSettingsTab;
  /// Mở tab bình luận / báo cáo trong chi tiết công việc
  final bool taskOpenComments;

  const NotificationNavigationTarget({
    required this.moduleCode,
    this.settingsHubSubIndex,
    this.scheduleApprovalTab,
    this.attendanceApprovalTab,
    this.attendanceApprovalStatusFilter,
    this.mobileAttendanceSettingsTab,
    this.taskOpenComments = false,
  });
}

/// Các giá trị `type` / `notificationType` từ server = mức độ thông báo, không phải màn hình.
const _notificationSeverityKeys = {
  'info',
  'success',
  'warning',
  'error',
  'approvalrequired',
};

/// Parse entity type từ FCM data (ưu tiên relatedEntityType, không nhầm với Info/Warning).
String? entityTypeFromPushData(Map<String, String> data) {
  final related = data['relatedEntityType']?.trim();
  if (related != null && related.isNotEmpty) return related;

  final fromUrl = entityTypeFromActionUrl(data['actionUrl']);
  if (fromUrl != null) return fromUrl;

  final legacy = data['type']?.trim();
  if (legacy != null &&
      legacy.isNotEmpty &&
      !_notificationSeverityKeys.contains(
          legacy.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), ''))) {
    return legacy;
  }
  return null;
}

/// `/attendance` → attendance; `/adms-devices` → Device.
String? entityTypeFromActionUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  final segs = url.split('/').where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final first = segs.first.toLowerCase();
  if (first == 'admin') {
    if (segs.length >= 2) {
      switch (segs[1].toLowerCase()) {
        case 'stores':
          return 'Store';
        case 'devices':
          return 'Device';
        case 'licenses':
          return 'LicenseKey';
        case 'agents':
          return 'Agent';
        case 'users':
          return 'User';
      }
    }
    return 'SystemAdmin';
  }
  if (first == 'adms-devices' || first == 'admsdevices') return 'Device';
  if (first == 'overtimes' || first == 'overtime') return 'Overtime';
  if (first == 'leaves' || first == 'leave') return 'Leave';
  if (first == 'tasks' || first == 'task') return 'WorkTask';
  return segs.first;
}

/// Tiêu đề rõ nghĩa hơn relatedEntityType chung chung (Benefit, Payroll…).
bool _titleOverridesApiEntity(String? title, String? relatedEntityType) {
  if (title == null || title.isEmpty) return false;
  final fromTitle = _inferEntityTypeFromTitle(title);
  if (fromTitle == null) return false;
  final rawKey = normalizeNotificationEntityType(relatedEntityType);
  final titleKey = normalizeNotificationEntityType(fromTitle);
  if (rawKey == null || rawKey == titleKey) return false;
  final t = title.toLowerCase();
  if (t.contains('thiết lập lương') ||
      t.contains('cấu hình bảng lương') ||
      t.contains('phiếu thưởng')) {
    return true;
  }
  if (t.contains('thiết bị') &&
      (t.contains('kết nối') || t.contains('ngắt') || t.contains('offline'))) {
    return true;
  }
  return false;
}

/// Suy ra entity khi API thiếu/không chuẩn relatedEntityType (màn danh sách thông báo).
String? resolveEntityTypeForNotification({
  String? relatedEntityType,
  String? categoryCode,
  String? actionUrl,
  String? title,
}) {
  final raw = relatedEntityType?.trim();

  if (_titleOverridesApiEntity(title, raw)) {
    final fromTitle = _inferEntityTypeFromTitle(title);
    if (fromTitle != null &&
        resolveNotificationNavigation(fromTitle, title: title) != null) {
      return fromTitle;
    }
  }

  if (raw != null &&
      raw.isNotEmpty &&
      resolveNotificationNavigation(raw, title: title) != null) {
    return raw;
  }

  final fromTitle = _inferEntityTypeFromTitle(title);
  if (fromTitle != null &&
      resolveNotificationNavigation(fromTitle, title: title) != null) {
    return fromTitle;
  }

  final fromCat = _inferEntityTypeFromCategory(categoryCode, title: title);
  if (fromCat != null &&
      resolveNotificationNavigation(fromCat, title: title) != null) {
    return fromCat;
  }

  final fromUrl = entityTypeFromActionUrl(actionUrl);
  if (fromUrl != null &&
      resolveNotificationNavigation(fromUrl, title: title) != null) {
    return fromUrl;
  }

  if (raw != null && raw.isNotEmpty) return raw;
  return null;
}

bool canNavigateFromNotification({
  String? relatedEntityType,
  String? categoryCode,
  String? actionUrl,
  String? title,
}) {
  final entity = resolveEntityTypeForNotification(
    relatedEntityType: relatedEntityType,
    categoryCode: categoryCode,
    actionUrl: actionUrl,
    title: title,
  );
  return entity != null &&
      resolveNotificationNavigation(entity, title: title) != null;
}

String? _inferEntityTypeFromTitle(String? title) {
  if (title == null || title.isEmpty) return null;
  final t = title.toLowerCase();

  if (t.contains('thiết lập lương') || t.contains('cấu hình bảng lương')) {
    return 'SalarySettings';
  }
  if (t.contains('phiếu thưởng')) return 'BonusPenalty';
  if (t.contains('nghỉ phép') || t.contains('đơn phép')) return 'Leave';
  if (t.contains('tăng ca')) return 'Overtime';
  if (t.contains('ứng lương')) return 'AdvanceRequest';
  if (t.contains('ứng công tác') ||
      t.contains('công tác phí') ||
      t.contains('hoạch toán công tác') ||
      t.contains('bổ sung giấy tờ công tác') ||
      (t.contains('công tác') &&
          (t.contains('duyệt') ||
              t.contains('từ chối') ||
              t.contains('chi ứng') ||
              t.contains('yêu cầu') ||
              t.contains('bổ sung')))) {
    return 'BusinessTripCase';
  }
  if (t.contains('phiếu phạt')) return 'PenaltyTicket';
  if (t.contains('sản lượng') || t.contains('import sản lượng')) {
    return 'ProductionEntry';
  }
  if (t.contains('kpi') || t.contains('lương kpi')) return 'KpiSalary';
  if (t.contains('thu chi') || t.contains('giao dịch thu')) {
    return 'CashTransaction';
  }
  if (t.contains('phản ánh') || t.contains('ý kiến')) return 'Feedback';
  if (t.contains('check-in') || t.contains('check in') || t.contains('hiện trường')) {
    return 'FieldCheckIn';
  }
  if (t.contains('đổi ca') || t.contains('hoán ca')) return 'ShiftSwap';
  if (t.contains('đăng ký lịch') || t.contains('duyệt lịch') || t.contains('hoàn tác duyệt lịch')) {
    return 'ScheduleRegistration';
  }
  if (t.contains('lịch làm') || t.contains('xóa lịch làm')) return 'WorkSchedule';
  if (t.contains('ca làm') || t.contains('ca mới')) return 'Shift';
  if (t.contains('chỉnh sửa chấm công') || t.contains('chỉnh công')) {
    return 'AttendanceCorrection';
  }
  if (t.contains('đăng ký thiết bị') ||
      t.contains('đổi thiết bị') ||
      t.contains('thiết bị chấm công')) {
    return 'AuthorizedMobileDevice';
  }
  if (t.contains('chấm đi đường') || t.contains('đi đường chờ duyệt')) {
    return 'MobileAttendance';
  }
  if (t.contains('chấm công mobile') ||
      (t.contains('chấm công') &&
          (t.contains('duyệt') || t.contains('từ chối') || t.contains('cần')))) {
    return 'MobileAttendance';
  }
  if (t.contains('chấm công') || t.contains('máy chấm')) return 'Attendance';
  if (t.contains('máy chấm công') ||
      t.contains('thiết bị') && (t.contains('kết nối') || t.contains('ngắt'))) {
    return 'Device';
  }
  if (t.contains('công việc') ||
      t.contains('bình luận') ||
      t.contains('tiến độ') ||
      t.contains('nhận việc')) {
    return 'WorkTask';
  }
  if (t.contains('tin nhắn') ||
      t.contains('bài viết') ||
      t.contains('thông báo nội bộ')) {
    return 'Communication';
  }
  if (t.contains('phụ cấp')) return 'Allowance';
  if (t.contains('phúc lợi')) return 'Benefit';
  if (t.contains('thưởng phạt') && !t.contains('phiếu thưởng')) {
    return 'BonusPenalty';
  }
  if (t.contains('bảng lương') || t.contains('phiếu lương')) return 'Payroll';
  if (t.contains('nhân viên') || t.contains('hồ sơ mới')) return 'Employee';
  if (t.contains('phòng ban')) return 'Department';
  if (t.contains('tài khoản') || t.contains('mật khẩu')) return 'Account';
  if (t.contains('thực đơn') || t.contains('suất ăn') || t.contains('bữa ăn')) {
    return 'MealMenu';
  }
  if (t.contains('thông báo hệ thống') || t.contains('announcement')) {
    return 'SystemAnnouncement';
  }
  return null;
}

String? _inferEntityTypeFromCategory(String? categoryCode, {String? title}) {
  if (categoryCode == null || categoryCode.isEmpty) return null;
  final c = categoryCode.toLowerCase().replaceAll(' ', '_');
  switch (c) {
    case 'leave':
      return 'Leave';
    case 'mobile_attendance':
      return _inferEntityTypeFromTitle(title) ?? 'MobileAttendance';
    case 'travel_attendance':
      return 'MobileAttendance';
    case 'attendance':
      return _inferEntityTypeFromTitle(title) ?? 'Attendance';
    case 'approval':
      return _inferEntityTypeFromTitle(title);
    case 'payroll':
    case 'salary':
      if (title != null && title.toLowerCase().contains('ứng lương')) {
        return 'AdvanceRequest';
      }
      if (title != null &&
          (title.toLowerCase().contains('thiết lập lương') ||
              title.toLowerCase().contains('cấu hình bảng lương'))) {
        return 'SalarySettings';
      }
      return _inferEntityTypeFromTitle(title) ?? 'Payroll';
    case 'penalty':
      return 'PenaltyTicket';
    case 'production':
      return 'ProductionEntry';
    case 'kpi':
      return 'Kpi';
    case 'meal':
      return 'MealMenu';
    case 'business_trip':
    case 'businesstrip':
      return 'BusinessTripCase';
    case 'transaction':
      return 'CashTransaction';
    case 'pos':
      return 'PosSaleOrder';
    case 'internal_comm':
      return 'Communication';
    case 'device':
      return 'Device';
    case 'hr':
      return _inferEntityTypeFromTitle(title) ?? 'Employee';
    case 'system':
      return 'SystemAnnouncement';
    case 'shift':
      return _inferEntityTypeFromTitle(title) ?? 'Shift';
    default:
      return null;
  }
}

/// Chuẩn hóa relatedEntityType từ API (PascalCase) / payload (camelCase).
String? normalizeNotificationEntityType(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty || s.toLowerCase() == 'notification') return null;
  return s.replaceAll(RegExp(r'[\s_-]+'), '').toLowerCase();
}

bool _titleLooksLikeManagerApproval(String title) {
  final t = title.toLowerCase();
  return t.contains('cần duyệt') ||
      t.contains('chờ duyệt') ||
      t.contains('đăng ký thiết bị chấm công mới') ||
      t.contains('yêu cầu đổi thiết bị') ||
      t.contains('chấm công') && t.contains('cần duyệt');
}

bool _titleOpensTaskComments(String? title) {
  if (title == null || title.isEmpty) return false;
  final t = title.toLowerCase();
  return t.contains('bình luận') ||
      t.contains('tiến độ') ||
      t.contains('báo cáo') ||
      t.contains('nhận việc') ||
      t.contains('từ chối');
}

bool _titleLooksLikeEmployeeSelfService(String title) {
  final t = title.toLowerCase();
  return t.contains('đã gửi đăng ký') ||
      t.contains('đăng ký thiết bị được duyệt') ||
      t.contains('đăng ký thiết bị bị từ chối') ||
      t.contains('yêu cầu đổi thiết bị đã gửi') ||
      t.contains('bạn có thể chấm công');
}

/// Thiết lập HRM → Chấm công mobile → tab Thiết bị (duyệt đăng ký / đổi máy).
const _mobileDeviceManagerSettingsTarget = NotificationNavigationTarget(
  moduleCode: 'SettingsHub',
  settingsHubSubIndex: 1,
  mobileAttendanceSettingsTab: 2,
);

NotificationNavigationTarget? _mobileDeviceTarget(String? title) {
  if (title != null && title.isNotEmpty) {
    if (_titleLooksLikeEmployeeSelfService(title)) {
      return const NotificationNavigationTarget(
        moduleCode: 'MobileDeviceRegistration',
      );
    }
    if (_titleLooksLikeManagerApproval(title)) {
      return _mobileDeviceManagerSettingsTarget;
    }
  }
  return _mobileDeviceManagerSettingsTarget;
}

/// Ánh xạ loại thực thể → màn hình SBOX HRM.
NotificationNavigationTarget? resolveNotificationNavigation(
  String? entityType, {
  String? title,
}) {
  final key = normalizeNotificationEntityType(entityType);
  switch (key) {
    // Chấm công thô / máy
    case 'attendance':
    case 'newattendance':
      return const NotificationNavigationTarget(moduleCode: 'Attendance');
    case 'device':
    case 'devicestatus':
    case 'admsdevice':
      return const NotificationNavigationTarget(
        moduleCode: 'SettingsHub',
        settingsHubSubIndex: 12,
      );

    // Mobile
    case 'mobileattendance':
      if (title != null) {
        final t = title.toLowerCase();
        if (t.contains('thành công') ||
            t.contains('đã duyệt') ||
            t.contains('bị từ chối')) {
          return const NotificationNavigationTarget(
            moduleCode: 'MobileAttendance',
          );
        }
      }
      return const NotificationNavigationTarget(
        moduleCode: 'AttendanceApproval',
        attendanceApprovalTab: 1,
        attendanceApprovalStatusFilter: 0,
      );
    case 'authorizedmobiledevice':
    case 'devicechangerequest':
    case 'mobiledeviceregistration':
      return _mobileDeviceTarget(title);

    // Duyệt chỉnh sửa CC
    case 'attendancecorrection':
    case 'correction':
      return const NotificationNavigationTarget(
        moduleCode: 'AttendanceApproval',
        attendanceApprovalTab: 0,
        attendanceApprovalStatusFilter: 0,
      );

    case 'overtime':
      return const NotificationNavigationTarget(moduleCode: 'Dashboard');

    // Nghỉ / ứng / lương
    case 'leave':
    case 'leaverequest':
      return const NotificationNavigationTarget(moduleCode: 'Leave');
    case 'advancerequest':
    case 'advance':
      return const NotificationNavigationTarget(moduleCode: 'AdvanceRequests');
    case 'businesstripcase':
    case 'businesstripexpense':
      return const NotificationNavigationTarget(moduleCode: 'BusinessTripExpense');
    case 'salarysettings':
      return const NotificationNavigationTarget(moduleCode: 'SalarySettings');
    case 'payroll':
      return const NotificationNavigationTarget(moduleCode: 'Payroll');
    case 'payslip':
      return const NotificationNavigationTarget(moduleCode: 'Payslip');

    // Lịch / đổi ca
    case 'shiftswap':
      return const NotificationNavigationTarget(moduleCode: 'ShiftSwap');
    case 'scheduleregistration':
      return const NotificationNavigationTarget(
        moduleCode: 'ScheduleApproval',
        scheduleApprovalTab: 0,
      );
    case 'workschedule':
      return const NotificationNavigationTarget(moduleCode: 'WorkSchedule');
    case 'shift':
      return const NotificationNavigationTarget(moduleCode: 'WorkSchedule');
    case 'schedule':
      return const NotificationNavigationTarget(
        moduleCode: 'ScheduleApproval',
        scheduleApprovalTab: 0,
      );

    // Nhân sự / phòng ban
    case 'employee':
      return const NotificationNavigationTarget(moduleCode: 'Employee');
    case 'department':
      return const NotificationNavigationTarget(moduleCode: 'Department');

    // Vận hành
    case 'worktask':
    case 'task':
      return NotificationNavigationTarget(
        moduleCode: 'Task',
        taskOpenComments: _titleOpensTaskComments(title),
      );
    case 'communication':
      return const NotificationNavigationTarget(moduleCode: 'Communication');
    case 'asset':
      return const NotificationNavigationTarget(moduleCode: 'Asset');
    case 'assetreport':
      return const NotificationNavigationTarget(moduleCode: 'AssetReport');
    case 'feedback':
      if (title != null && title.toLowerCase().contains('phản ánh mới')) {
        NavigationNotifier.feedbackPreferInbox.value = true;
      }
      return const NotificationNavigationTarget(moduleCode: 'Feedback');
    case 'fieldcheckin':
      return const NotificationNavigationTarget(moduleCode: 'FieldCheckIn');
    case 'productionentry':
    case 'production':
      return const NotificationNavigationTarget(moduleCode: 'Production');

    // Tài chính / phạt / phúc lợi
    case 'penaltyticket':
    case 'penaltytickets':
      return const NotificationNavigationTarget(moduleCode: 'PenaltyTickets');
    case 'cashtransaction':
      return const NotificationNavigationTarget(moduleCode: 'CashTransaction');
    case 'paymenttransaction':
      return const NotificationNavigationTarget(moduleCode: 'BonusPenalty');
    case 'transaction':
      return const NotificationNavigationTarget(moduleCode: 'CashTransaction');
    case 'bonuspenalty':
    case 'benefit':
      return const NotificationNavigationTarget(moduleCode: 'BonusPenalty');
    case 'allowance':
      return const NotificationNavigationTarget(
        moduleCode: 'SettingsHub',
        settingsHubSubIndex: 3,
      );

    // KPI / cơm
    case 'kpi':
    case 'kpisalary':
    case 'kpiperiod':
    case 'kpiemployeetarget':
      return const NotificationNavigationTarget(moduleCode: 'KPI');
    case 'mealrecord':
    case 'mealsession':
    case 'mealmenu':
      return const NotificationNavigationTarget(moduleCode: 'Meal');

    // Quản trị
    case 'account':
      return const NotificationNavigationTarget(
        moduleCode: 'SettingsHub',
        settingsHubSubIndex: 7,
      );
    case 'store':
    case 'renewal':
      return const NotificationNavigationTarget(moduleCode: 'SystemAdmin');
    case 'licensekey':
    case 'license':
      return const NotificationNavigationTarget(moduleCode: 'SystemAdmin');
    case 'agent':
      return const NotificationNavigationTarget(moduleCode: 'SystemAdmin');
    case 'systemannouncement':
      return const NotificationNavigationTarget(moduleCode: 'Notification');

    default:
      return null;
  }
}

/// Điều hướng từ thông báo; fallback về danh sách thông báo nếu không nhận diện được.
void navigateFromNotification({
  String? relatedEntityType,
  String? relatedEntityId,
  String? title,
  String? categoryCode,
  String? actionUrl,
  bool adminPortalMode = false,
  bool agentMode = false,
}) {
  if (adminPortalMode ||
      (actionUrl ?? '').startsWith('/admin') ||
      AdminNavigationNotifier.systemAdminReady.value) {
    AdminNavigationNotifier.navigate(
      agentMode: agentMode,
      actionUrl: actionUrl,
      relatedEntityType: relatedEntityType,
      categoryCode: categoryCode,
      relatedEntityId: relatedEntityId,
    );
    return;
  }

  final entity = resolveEntityTypeForNotification(
    relatedEntityType: relatedEntityType,
    categoryCode: categoryCode,
    actionUrl: actionUrl,
    title: title,
  );
  final target = resolveNotificationNavigation(entity, title: title);
  if (target == null) {
    if (kDebugMode) {
      debugPrint(
          '📍 Notification nav: unknown entity "$entity" (raw=$relatedEntityType) → notifications list');
    }
    NavigationNotifier.goToNotifications();
    return;
  }

  if (target.settingsHubSubIndex != null) {
    SettingsHubScreen.pendingSubIndex.value = target.settingsHubSubIndex;
  }
  if (target.scheduleApprovalTab != null) {
    NavigationNotifier.scheduleApprovalTab.value = target.scheduleApprovalTab!;
  }
  if (target.attendanceApprovalTab != null) {
    NavigationNotifier.attendanceApprovalTab.value = target.attendanceApprovalTab!;
  }
  if (target.attendanceApprovalStatusFilter != null) {
    NavigationNotifier.attendanceApprovalStatusFilter.value =
        target.attendanceApprovalStatusFilter!;
  }
  if (target.mobileAttendanceSettingsTab != null) {
    NavigationNotifier.mobileAttendanceSettingsTab.value =
        target.mobileAttendanceSettingsTab;
  }
  if (relatedEntityId != null && relatedEntityId.isNotEmpty) {
    NavigationNotifier.notificationHighlightId.value = relatedEntityId;
  }
  NavigationNotifier.taskOpenComments.value = target.taskOpenComments;

  if (normalizeNotificationEntityType(entity) == 'overtime') {
    NavigationNotifier.pendingOpenOvertime.value = true;
  }

  if (normalizeNotificationEntityType(entity) == 'businesstripcase' ||
      normalizeNotificationEntityType(entity) == 'businesstripexpense') {
    if (relatedEntityId != null && relatedEntityId.isNotEmpty) {
      NavigationNotifier.notificationHighlightId.value = relatedEntityId;
    }
  }

  if (kDebugMode) {
    debugPrint('📍 Notification nav: $entity → module ${target.moduleCode}');
  }
  NavigationNotifier.goToModule(target.moduleCode);
}
