import 'package:flutter/foundation.dart';

import '../screens/settings_hub_screen.dart';

/// Global navigation notifier - allows navigating from any screen.
class NavigationNotifier {
  /// True khi [MainLayout] đã mount và lắng nghe [navigateTo].
  static final ValueNotifier<bool> mainLayoutReady = ValueNotifier<bool>(false);

  /// Mobile: màn mở từ drawer (không phải tab bottom) — AppBar [MainLayout] đã có tiêu đề.
  static final ValueNotifier<bool> mobileDrawerModuleActive =
      ValueNotifier<bool>(false);

  /// Nhãn màn hình hiện tại (sidebar tab) — hiển thị trên màn lỗi fatal.
  static final ValueNotifier<String?> currentScreenLabel =
      ValueNotifier<String?>(null);

  static final ValueNotifier<String?> currentModuleCode =
      ValueNotifier<String?>(null);

  static void reportScreen(String label, {String? moduleCode}) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return;
    currentScreenLabel.value = trimmed;
    currentModuleCode.value = moduleCode;
    if (moduleCode != null && moduleCode.isNotEmpty) {
      debugPrint('📍 Screen: $trimmed ($moduleCode)');
    } else {
      debugPrint('📍 Screen: $trimmed');
    }
  }

  static final ValueNotifier<int?> navigateTo = ValueNotifier<int?>(null);
  /// Điều hướng theo [NavItem.moduleCode] — tránh lệch index khi thêm màn mới.
  static final ValueNotifier<String?> navigateToModule =
      ValueNotifier<String?>(null);
  /// Tab ban đầu khi mở Duyệt lịch làm việc: 0=ca, 1=NV, 2=đổi ca
  static final ValueNotifier<int> scheduleApprovalTab = ValueNotifier<int>(0);
  /// Tab Duyệt chấm công: 0=chỉnh CC, 1=mobile
  static final ValueNotifier<int> attendanceApprovalTab = ValueNotifier<int>(0);
  /// Tab Cài đặt chấm công mobile: 0=cài đặt, 1=vị trí, 2=thiết bị
  static final ValueNotifier<int?> mobileAttendanceSettingsTab =
      ValueNotifier<int?>(null);
  /// Bộ lọc trạng thái khi mở Duyệt chấm công (-1=tất cả, 0=chờ duyệt)
  static final ValueNotifier<int> attendanceApprovalStatusFilter =
      ValueNotifier<int>(-1);
  /// Tab Nghỉ phép khi mở từ Tổng quan (-1=mặc định, 1=chờ duyệt cho QL)
  static final ValueNotifier<int> leaveInitialTab = ValueNotifier<int>(-1);
  /// Lọc ứng lương: -1=không đổi, 0=pending, 1=approved, 2=rejected, 3=cancelled
  static final ValueNotifier<int> advanceRequestsStatusFilter =
      ValueNotifier<int>(-1);
  /// Lọc phiếu phạt: null=không đổi, '0'=chờ, '1'=duyệt, ...
  static final ValueNotifier<String?> penaltyTicketsFilterStatus =
      ValueNotifier<String?>(null);
  /// Lọc công việc từ Tổng quan (-1=không đổi, index [WorkTaskStatus])
  static final ValueNotifier<int> taskFilterStatusIndex = ValueNotifier<int>(-1);
  static final ValueNotifier<bool> taskFilterOverdueOnly =
      ValueNotifier<bool>(false);
  /// Highlight bản ghi (id) sau khi mở từ thông báo
  static final ValueNotifier<String?> notificationHighlightId =
      ValueNotifier<String?>(null);

  /// Mở chi tiết hồ sơ công tác từ FCM / danh sách thông báo
  static void goToBusinessTripCase(String? caseId) {
    if (caseId != null && caseId.isNotEmpty) {
      notificationHighlightId.value = caseId;
    }
    goToModule('BusinessTripExpense');
  }
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

  /// Chuyển tab trong [PosMobileHubScreen] (0=Tổng quan … 4=Nhiều hơn).
  static final ValueNotifier<int?> posHubTab = ValueNotifier<int?>(null);

  /// POS bán hàng: trả true nếu đã xử lý nút Back (vd. về sơ đồ bàn).
  static Future<bool> Function()? posHandleSystemBack;

  /// Sau điều hướng tới Dashboard, mở [OvertimeScreen] (thông báo tăng ca).
  static final ValueNotifier<bool> pendingOpenOvertime =
      ValueNotifier<bool>(false);

  /// Intent mở form tạo từ Trợ lý AI (leave / advance / feedback / overtime / …).
  static final ValueNotifier<String?> pendingAiOpenCreate =
      ValueNotifier<String?>(null);

  /// Trả true nếu đúng intent đang chờ và đồng thời xóa cờ.
  static bool takePendingAiOpenCreate(String intent) {
    if (pendingAiOpenCreate.value != intent) return false;
    pendingAiOpenCreate.value = null;
    return true;
  }

  static void goTo(int screenIndex) {
    navigateTo.value = screenIndex;
    debugPrint('📍 Navigation requested to screen index: $screenIndex');
  }

  /// Thoát shell POS → trang chủ HRM (nếu có MainLayout); không thì tab Tổng quan.
  static void leavePosHubToAppHome() {
    if (mainLayoutReady.value) {
      goTo(home);
      return;
    }
    posHubTab.value = 0;
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
  static void goToAdvanceRequests() => goToAdvanceRequestsNav();
  static void goToAttendanceCorrections({String? highlightId}) {
    goToAttendanceApproval(
      statusFilter: 0,
      tab: 0,
      highlightId: highlightId,
    );
  }

  /// Mở màn Duyệt chấm công (tab chỉnh CC hoặc Mobile, lọc trạng thái, highlight).
  static void goToAttendanceApproval({
    int statusFilter = -1,
    int tab = 0,
    String? highlightId,
  }) {
    attendanceApprovalTab.value = tab.clamp(0, 1);
    attendanceApprovalStatusFilter.value = statusFilter;
    notificationHighlightId.value =
        (highlightId != null && highlightId.isNotEmpty) ? highlightId : null;
    goToModule('AttendanceApproval');
  }

  static void goToScheduleApproval({int tab = 0, String? highlightId}) {
    scheduleApprovalTab.value = tab.clamp(0, 3);
    if (highlightId != null && highlightId.isNotEmpty) {
      notificationHighlightId.value = highlightId;
    }
    goToModule('ScheduleApproval');
  }

  static void goToLeaves({String? highlightId, bool pendingOnly = false}) {
    leaveInitialTab.value = pendingOnly ? 1 : -1;
    notificationHighlightId.value =
        (highlightId != null && highlightId.isNotEmpty) ? highlightId : null;
    goToModule('Leave');
  }

  static void goToLeaveCreate() {
    pendingAiOpenCreate.value = 'leave';
    goToLeaves();
  }

  static void goToAdvanceRequestsNav({
    String? highlightId,
    bool pendingOnly = false,
  }) {
    advanceRequestsStatusFilter.value = pendingOnly ? 0 : -1;
    notificationHighlightId.value =
        (highlightId != null && highlightId.isNotEmpty) ? highlightId : null;
    goToModule('AdvanceRequests');
  }

  static void goToAdvanceCreate() {
    pendingAiOpenCreate.value = 'advance';
    goToAdvanceRequestsNav();
  }

  static void goToFeedbackCreate() {
    pendingAiOpenCreate.value = 'feedback';
    goTo(feedback);
  }

  static void goToShiftSwapCreate() {
    pendingAiOpenCreate.value = 'shift_swap';
    goToShiftSwap();
  }

  static void goToOvertime({bool openCreate = false}) {
    if (openCreate) pendingAiOpenCreate.value = 'overtime';
    pendingOpenOvertime.value = true;
    goToModule('Dashboard');
  }

  static void goToBusinessTripCreate() {
    pendingAiOpenCreate.value = 'business_trip';
    goToModule('BusinessTripExpense');
  }

  static void goToMealRegister() {
    pendingAiOpenCreate.value = 'meal';
    goTo(meals);
  }

  static void goToAttendanceCorrectionCreate() {
    pendingAiOpenCreate.value = 'attendance_correction';
    goToAttendanceCorrections();
  }

  static void goToPenaltyTicketsNav({
    String? highlightId,
    String? filterStatus,
  }) {
    penaltyTicketsFilterStatus.value = filterStatus;
    notificationHighlightId.value =
        (highlightId != null && highlightId.isNotEmpty) ? highlightId : null;
    goToModule('PenaltyTickets');
  }

  static void goToEmployeesHighlight(String? highlightId) {
    notificationHighlightId.value =
        (highlightId != null && highlightId.isNotEmpty) ? highlightId : null;
    goToModule('Employee');
  }

  static void goToTaskManagementNav({
    int? statusIndex,
    bool overdueOnly = false,
    String? highlightId,
  }) {
    taskFilterStatusIndex.value = statusIndex ?? -1;
    taskFilterOverdueOnly.value = overdueOnly;
    if (highlightId != null && highlightId.isNotEmpty) {
      notificationHighlightId.value = highlightId;
    }
    goToModule('Task');
  }

  static void goToOvertimeFromDashboard() {
    pendingOpenOvertime.value = true;
    goToModule('Dashboard');
  }

  static void goToMobileDeviceRegistration() =>
      goToModule('MobileDeviceRegistration');
  static void goToMobileAttendance() => goToModule('MobileAttendance');
  static void goToWorkSchedule() => goTo(workSchedule);
  static void goToNotifications() => goTo(notifications);
  static void goToEmployees() => goToModule('Employee');
  static void goToDepartments() => goTo(departments);
  static void goToTaskManagement() => goToModule('Task');
  static void goToAssetManagement() => goTo(assetManagement);
  static void goToCashTransaction({String? highlightId}) {
    notificationHighlightId.value =
        (highlightId != null && highlightId.isNotEmpty) ? highlightId : null;
    goTo(cashTransaction);
  }
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
  static void goToSalarySettings() {
    SettingsHubScreen.pendingSubIndex.value = 20;
    goToModule('SettingsHub');
  }

  static void goToNotificationSettings() {
    SettingsHubScreen.pendingSubIndex.value = 21;
    goToModule('SettingsHub');
  }
  static void goToBonusPenalty() => goToModule('BonusPenalty');
  static void goToAttendanceSummary() => goTo(attendanceSummary);
  static void goToAttendanceByShift() => goTo(attendanceByShift);
  static void goToKpi() => goTo(kpi);
  static void goToDeviceSettings() {
    SettingsHubScreen.pendingSubIndex.value = 12;
    goToModule('SettingsHub');
  }

  /// Reset intent điều hướng khi đổi phiên — tránh POS/HRM lẫn state cũ.
  static void resetForNewSession() {
    navigateTo.value = null;
    navigateToModule.value = null;
    posHubTab.value = null;
    pendingOpenOvertime.value = false;
    pendingAiOpenCreate.value = null;
    notificationHighlightId.value = null;
    mobileDrawerModuleActive.value = false;
    currentScreenLabel.value = null;
    currentModuleCode.value = null;
    scheduleApprovalTab.value = 0;
    attendanceApprovalTab.value = 0;
    mobileAttendanceSettingsTab.value = null;
    attendanceApprovalStatusFilter.value = -1;
    leaveInitialTab.value = -1;
    advanceRequestsStatusFilter.value = -1;
    penaltyTicketsFilterStatus.value = null;
    taskFilterStatusIndex.value = -1;
    taskFilterOverdueOnly.value = false;
    taskOpenComments.value = false;
    feedbackPreferInbox.value = false;
    posHandleSystemBack = null;
    SettingsHubScreen.pendingSubIndex.value = null;
  }
}
