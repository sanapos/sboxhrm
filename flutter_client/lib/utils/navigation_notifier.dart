import 'package:flutter/foundation.dart';

import '../screens/settings_hub_screen.dart';

/// Global navigation notifier - allows navigating from any screen.
class NavigationNotifier {
  /// True khi [MainLayout] đã mount và lắng nghe [navigateTo].
  static final ValueNotifier<bool> mainLayoutReady = ValueNotifier<bool>(false);

  static final ValueNotifier<int?> navigateTo = ValueNotifier<int?>(null);
  /// Điều hướng theo [NavItem.moduleCode] — tránh lệch index khi thêm màn mới.
  static final ValueNotifier<String?> navigateToModule =
      ValueNotifier<String?>(null);
  /// Tab ban đầu khi mở Duyệt lịch làm việc: 0=ca, 1=NV, 2=đổi ca
  static final ValueNotifier<int> scheduleApprovalTab = ValueNotifier<int>(0);
  /// Tab Duyệt chấm công: 0=chỉnh CC, 1=mobile
  static final ValueNotifier<int> attendanceApprovalTab = ValueNotifier<int>(0);
  /// Bộ lọc trạng thái khi mở Duyệt chấm công (-1=tất cả, 0=chờ duyệt)
  static final ValueNotifier<int> attendanceApprovalStatusFilter =
      ValueNotifier<int>(-1);
  /// Highlight bản ghi (id) sau khi mở từ thông báo
  static final ValueNotifier<String?> notificationHighlightId =
      ValueNotifier<String?>(null);
  /// Mở chi tiết công việc và cuộn tới bình luận/báo cáo tiến độ
  static final ValueNotifier<bool> taskOpenComments = ValueNotifier<bool>(false);
  /// Mở tab Hòm thư (thay vì Của tôi) khi vào Phản ánh từ thông báo gửi tới người nhận
  static final ValueNotifier<bool> feedbackPreferInbox =
      ValueNotifier<bool>(false);

  static const int home = 0;
  static const int notifications = 1;
  static const int dashboard = 2;
  static const int employees = 3;
  static const int deviceUsers = 4;
  static const int departments = 5;
  static const int leaves = 6;
  static const int salarySettings = 7;
  static const int attendance = 8;
  static const int workSchedule = 9;
  static const int attendanceSummary = 10;
  static const int attendanceByShift = 11;
  static const int attendanceApproval = 12;
  static const int scheduleApproval = 13;
  static const int payslip = 14;
  static const int payroll = 15;
  static const int mobileDeviceRegistration = 16;
  static const int mobileAttendance = 17;
  static const int meals = 18;
  static const int bonusPenalty = 19;
  static const int advanceRequests = 20;
  static const int cashTransaction = 21;
  static const int assetManagement = 22;
  static const int taskManagement = 23;
  static const int communication = 24;
  static const int kpi = 25;
  static const int production = 26;
  static const int feedback = 27;
  static const int fieldCheckIn = 28;
  // Báo cáo (khớp thứ tự _navItems trong main_layout.dart)
  static const int penaltyReport = 29;
  static const int cashReport = 30;
  static const int advanceReport = 31;
  static const int leaveReport = 32;
  static const int assetReport = 33;
  static const int agentLicenseKeys = 35;
  static const int settingsHub = 36;
  static const int settings = 37;
  static const int systemAdmin = 38;
  static const int penaltyTickets = 39;
  static const int notificationSettings = 40;
  static const int shiftSwap = 46;

  static final ValueNotifier<bool> goBackNotifier = ValueNotifier<bool>(false);

  /// Sau điều hướng tới Dashboard, mở [OvertimeScreen] (thông báo tăng ca).
  static final ValueNotifier<bool> pendingOpenOvertime =
      ValueNotifier<bool>(false);

  static void goTo(int screenIndex) {
    navigateTo.value = screenIndex;
    debugPrint('📍 Navigation requested to screen index: $screenIndex');
  }

  static void goToModule(String moduleCode) {
    navigateToModule.value = moduleCode;
    debugPrint('📍 Navigation requested to module: $moduleCode');
  }

  static void goBack() {
    goBackNotifier.value = !goBackNotifier.value;
    debugPrint('📍 Navigation back requested');
  }

  static void goToAttendance() => goTo(attendance);
  static void goToAdvanceRequests() => goTo(advanceRequests);
  static void goToAttendanceCorrections() {
    attendanceApprovalTab.value = 0;
    attendanceApprovalStatusFilter.value = 0;
    goTo(attendanceApproval);
  }

  static void goToMobileDeviceRegistration() =>
      goToModule('MobileDeviceRegistration');
  static void goToMobileAttendance() => goToModule('MobileAttendance');
  static void goToWorkSchedule() => goTo(workSchedule);
  static void goToNotifications() => goTo(notifications);
  static void goToEmployees() => goTo(employees);
  static void goToDepartments() => goTo(departments);
  static void goToLeaves() => goTo(leaves);
  static void goToTaskManagement() => goToModule('Task');
  static void goToAssetManagement() => goTo(assetManagement);
  static void goToCashTransaction() => goTo(cashTransaction);
  static void goToCommunication() => goTo(communication);
  static void goToPayroll() => goTo(payroll);
  static void goToPayslip() => goToModule('Payslip');
  static void goToShiftSwap() => goToModule('ShiftSwap');

  /// Ưu tiên phiếu lương cá nhân khi có quyền Payslip.
  static void goToPayModule({required bool preferPayslip}) {
    if (preferPayslip) {
      goToPayslip();
    } else {
      goToPayroll();
    }
  }
  static void goToSalarySettings() => goToModule('SalarySettings');
  static void goToBonusPenalty() => goToModule('BonusPenalty');
  static void goToAttendanceSummary() => goTo(attendanceSummary);
  static void goToAttendanceByShift() => goTo(attendanceByShift);
  static void goToKpi() => goTo(kpi);
  static void goToDeviceSettings() {
    SettingsHubScreen.pendingSubIndex.value = 12;
    goToModule('SettingsHub');
  }
}
