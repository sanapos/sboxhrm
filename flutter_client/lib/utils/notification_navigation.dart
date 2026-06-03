import 'package:flutter/foundation.dart';

import 'navigation_notifier.dart';
import '../screens/settings_hub_screen.dart';

/// Đích điều hướng khi user bấm thông báo (in-app, system tray, FCM).
class NotificationNavigationTarget {
  final int screenIndex;
  final int? settingsHubSubIndex;
  final int? scheduleApprovalTab;
  final int? attendanceApprovalTab;
  final int? attendanceApprovalStatusFilter;
  /// Mở tab bình luận / báo cáo trong chi tiết công việc
  final bool taskOpenComments;

  const NotificationNavigationTarget({
    required this.screenIndex,
    this.settingsHubSubIndex,
    this.scheduleApprovalTab,
    this.attendanceApprovalTab,
    this.attendanceApprovalStatusFilter,
    this.taskOpenComments = false,
  });
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

NotificationNavigationTarget? _mobileDeviceTarget(String? title) {
  if (title != null && title.isNotEmpty) {
    if (_titleLooksLikeEmployeeSelfService(title)) {
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.mobileDeviceRegistration,
      );
    }
    if (_titleLooksLikeManagerApproval(title)) {
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.attendanceApproval,
        attendanceApprovalTab: 1,
      );
    }
  }
  return const NotificationNavigationTarget(
    screenIndex: NavigationNotifier.attendanceApproval,
    attendanceApprovalTab: 1,
  );
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
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.attendance,
      );
    case 'device':
    case 'devicestatus':
    case 'admsdevice':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.settingsHub,
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
            screenIndex: NavigationNotifier.mobileAttendance,
          );
        }
      }
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.attendanceApproval,
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
        screenIndex: NavigationNotifier.attendanceApproval,
        attendanceApprovalTab: 0,
        attendanceApprovalStatusFilter: 0,
      );

    case 'overtime':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.attendance,
      );

    // Nghỉ / ứng / lương
    case 'leave':
    case 'leaverequest':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.leaves,
      );
    case 'advancerequest':
    case 'advance':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.advanceRequests,
      );
    case 'payroll':
    case 'payslip':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.payroll,
      );

    // Lịch / đổi ca
    case 'shiftswap':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.scheduleApproval,
        scheduleApprovalTab: 2,
      );
    case 'scheduleregistration':
    case 'workschedule':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.scheduleApproval,
        scheduleApprovalTab: 0,
      );
    case 'shift':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.workSchedule,
      );
    case 'schedule':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.scheduleApproval,
        scheduleApprovalTab: 0,
      );

    // Nhân sự / phòng ban
    case 'employee':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.employees,
      );
    case 'department':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.departments,
      );

    // Vận hành
    case 'worktask':
    case 'task':
      return NotificationNavigationTarget(
        screenIndex: NavigationNotifier.taskManagement,
        taskOpenComments: _titleOpensTaskComments(title),
      );
    case 'communication':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.communication,
      );
    case 'asset':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.assetManagement,
      );
    case 'feedback':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.feedback,
      );
    case 'fieldcheckin':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.fieldCheckIn,
      );
    case 'productionentry':
    case 'production':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.production,
      );

    // Tài chính / phạt / phúc lợi
    case 'penaltyticket':
    case 'penaltytickets':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.penaltyTickets,
      );
    case 'cashtransaction':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.cashTransaction,
      );
    case 'paymenttransaction':
    case 'transaction':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.cashTransaction,
      );
    case 'bonuspenalty':
    case 'benefit':
    case 'allowance':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.bonusPenalty,
      );

    // KPI / cơm
    case 'kpi':
    case 'kpisalary':
    case 'kpiperiod':
    case 'kpiemployeetarget':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.kpi,
      );
    case 'mealrecord':
    case 'mealsession':
    case 'mealmenu':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.meals,
      );

    // Quản trị
    case 'account':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.settings,
        settingsHubSubIndex: 7,
      );
    case 'store':
      return const NotificationNavigationTarget(
        screenIndex: NavigationNotifier.systemAdmin,
      );

    default:
      return null;
  }
}

/// Điều hướng từ thông báo; fallback về danh sách thông báo nếu không nhận diện được.
void navigateFromNotification({
  String? relatedEntityType,
  String? relatedEntityId,
  String? title,
}) {
  final target = resolveNotificationNavigation(relatedEntityType, title: title);
  if (target == null) {
    if (kDebugMode) {
      debugPrint(
          '📍 Notification nav: unknown entity "$relatedEntityType" → notifications list');
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
  if (relatedEntityId != null && relatedEntityId.isNotEmpty) {
    NavigationNotifier.notificationHighlightId.value = relatedEntityId;
  }
  NavigationNotifier.taskOpenComments.value = target.taskOpenComments;

  if (kDebugMode) {
    debugPrint(
        '📍 Notification nav: $relatedEntityType → screen ${target.screenIndex}');
  }
  NavigationNotifier.goTo(target.screenIndex);
}

/// Index màn hình cho popup desktop (main_layout) — tương thích code cũ.
int screenIndexForNotificationEntity(String? entityType, {String? title}) {
  final target = resolveNotificationNavigation(entityType, title: title);
  return target?.screenIndex ?? NavigationNotifier.notifications;
}
