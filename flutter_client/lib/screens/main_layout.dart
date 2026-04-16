import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../models/hrm.dart';
import '../models/attendance.dart';
import '../widgets/notification_overlay.dart';
import 'notification_settings_screen.dart';
import 'employees_screen.dart';
import 'device_users_screen.dart';
import 'attendance_screen.dart';
import 'settings_screen.dart';
import 'system_admin_screen.dart';
import 'settings_hub_screen.dart';
import 'advance_requests_screen.dart';
import 'attendance_approval_screen.dart';
import 'notifications_screen.dart';
import 'work_schedule_screen.dart';
import 'schedule_approval_screen.dart';
import 'department_screen.dart';
import 'leave_screen.dart';
import 'task_management_screen.dart';
import 'asset_management_screen.dart';
import 'cash_transaction_screen.dart';
import 'communication_screen.dart';
import 'payroll_screen.dart';
import 'salary_settings_screen.dart';
import 'bonus_penalty_screen.dart';
import 'penalty_tickets_screen.dart';
import 'attendance_summary_screen.dart';
import 'attendance_by_shift_screen.dart';
import 'kpi_screen.dart';
import 'dashboard_screen.dart';
import 'hr_report_screen.dart';
import 'attendance_report_screen.dart';
import 'payroll_report_screen.dart';
import 'agent_license_keys_screen.dart';
import 'production_output_screen.dart';
import 'feedback_screen.dart';
import 'mobile_attendance_screen.dart';
import 'mobile_attendance_approval_screen.dart';
import 'mobile_device_registration_screen.dart';
import 'meal_tracking_screen.dart';
import 'field_checkin_screen.dart';
import '../utils/notification_sound_stub.dart';
import '../services/system_notification_service.dart';

/// Global notifiers for screen refresh
class ScreenRefreshNotifier {
  static final ValueNotifier<int> attendance = ValueNotifier<int>(0);
  static final ValueNotifier<int> devices = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceByShift = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceSummary = ValueNotifier<int>(0);
  static final ValueNotifier<int> payroll = ValueNotifier<int>(0);

  static void refreshAttendanceScreen() {
    attendance.value++;
    debugPrint('🔄 Triggered attendance screen refresh: ${attendance.value}');
  }

  static void refreshDevicesScreen() {
    devices.value++;
    debugPrint('🔄 Triggered devices screen refresh: ${devices.value}');
  }

  static void refreshAttendanceByShiftScreen() {
    attendanceByShift.value++;
  }

  static void refreshAttendanceSummaryScreen() {
    attendanceSummary.value++;
  }

  static void refreshPayrollScreen() {
    payroll.value++;
  }

  static final ValueNotifier<int> notifications = ValueNotifier<int>(0);

  static void refreshNotificationCount() {
    notifications.value++;
  }
}

/// Global navigation notifier - allows navigating from any screen
class NavigationNotifier {
  static final ValueNotifier<int?> navigateTo = ValueNotifier<int?>(null);

  // Screen indices mapping - must match _navItems order
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
  static const int payroll = 14;
  static const int bonusPenalty = 15;
  static const int advanceRequests = 16;
  static const int cashTransaction = 17;
  static const int assetManagement = 18;
  static const int taskManagement = 19;
  static const int communication = 20;
  static const int kpi = 21;
  static const int production = 22;
  static const int feedback = 23;
  static const int hrReport = 24;
  static const int attendanceReport = 25;
  static const int payrollReport = 26;
  static const int agentLicenseKeys = 27;
  static const int settingsHub = 28;
  static const int settings = 29;
  static const int systemAdmin = 30;
  static const int penaltyTickets = 31;
  static const int meals = 32;
  static const int notificationSettings = 33;
  static const int fieldCheckIn = 34;

  static final ValueNotifier<bool> goBackNotifier = ValueNotifier<bool>(false);

  static void goTo(int screenIndex) {
    navigateTo.value = screenIndex;
    debugPrint('📍 Navigation requested to screen index: $screenIndex');
  }

  static void goBack() {
    goBackNotifier.value = !goBackNotifier.value;
    debugPrint('📍 Navigation back requested');
  }

  static void goToAttendance() => goTo(attendance);
  static void goToAdvanceRequests() => goTo(advanceRequests);
  static void goToAttendanceCorrections() => goTo(attendance);
  static void goToWorkSchedule() => goTo(workSchedule);
  static void goToNotifications() => goTo(notifications);
  static void goToEmployees() => goTo(employees);
  static void goToDepartments() => goTo(departments);
  static void goToLeaves() => goTo(leaves);
  static void goToTaskManagement() => goTo(taskManagement);
  static void goToAssetManagement() => goTo(assetManagement);
  static void goToCashTransaction() => goTo(cashTransaction);
  static void goToCommunication() => goTo(communication);
  static void goToPayroll() => goTo(payroll);
  static void goToSalarySettings() => goTo(salarySettings);
  static void goToBonusPenalty() => goTo(bonusPenalty);
  static void goToAttendanceSummary() => goTo(attendanceSummary);
  static void goToAttendanceByShift() => goTo(attendanceByShift);
  static void goToKpi() => goTo(kpi);
  static void goToDeviceSettings() {
    SettingsHubScreen.pendingSubIndex.value = 12; // Máy chấm công
    goTo(settingsHub);
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isExpanded = true;
  int _unreadNotificationsCount = 0;
  final Set<String> _collapsedGroups = {};
  final List<int> _navigationHistory = [];
  final ApiService _apiService = ApiService();
  final SignalRService _signalRService = SignalRService();
  final NotificationOverlayManager _notificationManager =
      NotificationOverlayManager();
  final SystemNotificationService _systemNotification =
      SystemNotificationService();
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _attendanceSubscription;
  StreamSubscription? _deviceStatusSubscription;
  StreamSubscription? _communicationSubscription;

  // Popup queue: show one popup at a time to prevent overlap
  final List<Widget Function(VoidCallback onDismiss)> _popupQueue = [];
  OverlayEntry? _currentPopupEntry;
  bool _isShowingPopup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _systemNotification.initialize();
    _loadNotificationCount();
    _connectSignalR();
    _loadPermissions();

    // Listen for navigation requests from other screens
    NavigationNotifier.navigateTo.addListener(_onNavigationRequested);
    NavigationNotifier.goBackNotifier.addListener(_onGoBackRequested);
    ScreenRefreshNotifier.notifications.addListener(_loadNotificationCount);
  }

  /// Load quyền hiệu lực cho user hiện tại
  void _loadPermissions() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final permProvider = Provider.of<PermissionProvider>(context, listen: false);
    if (!permProvider.isLoaded && !permProvider.isLoading) {
      permProvider.loadPermissions(role: authUser?.role);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Khi app quay lại foreground: kết nối lại SignalR nếu bị mất và cập nhật badge
      if (!_signalRService.isConnected) {
        _connectSignalR();
      }
      _loadNotificationCount();
    }
  }

  void _onNavigationRequested() {
    final targetIndex = NavigationNotifier.navigateTo.value;
    if (targetIndex != null && mounted) {
      _navigateToIndex(targetIndex);
      // Reset the value to allow same navigation again
      NavigationNotifier.navigateTo.value = null;
    }
  }

  void _onGoBackRequested() {
    _goBack();
  }

  void _navigateToIndex(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _navigationHistory.add(_selectedIndex);
      // Keep history manageable
      if (_navigationHistory.length > 50) {
        _navigationHistory.removeAt(0);
      }
      _selectedIndex = index;
    });
  }

  void _goBack() {
    // If SettingsHub has an active sub-screen, go back to hub menu first
    if (SettingsHubScreen.internalBackCallback != null) {
      SettingsHubScreen.internalBackCallback!();
      return;
    }
    if (_navigationHistory.isNotEmpty && mounted) {
      setState(() {
        _selectedIndex = _navigationHistory.removeLast();
      });
    }
  }

  bool get _canGoBack => _navigationHistory.isNotEmpty || SettingsHubScreen.internalBackCallback != null;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    _attendanceSubscription?.cancel();
    _deviceStatusSubscription?.cancel();
    _communicationSubscription?.cancel();
    _currentPopupEntry?.remove();
    _currentPopupEntry = null;
    NavigationNotifier.navigateTo.removeListener(_onNavigationRequested);
    NavigationNotifier.goBackNotifier.removeListener(_onGoBackRequested);
    ScreenRefreshNotifier.notifications.removeListener(_loadNotificationCount);
    super.dispose();
  }

  /// Enqueue a popup and show it if no other popup is active
  void _enqueuePopup(Widget Function(VoidCallback onDismiss) builder) {
    _popupQueue.add(builder);
    _showNextPopup();
  }

  void _showNextPopup() {
    if (_isShowingPopup || _popupQueue.isEmpty || !mounted) return;
    _isShowingPopup = true;

    final builder = _popupQueue.removeAt(0);
    _currentPopupEntry = OverlayEntry(
      builder: (context) => builder(() {
        _currentPopupEntry?.remove();
        _currentPopupEntry = null;
        _isShowingPopup = false;
        // Show next popup after a short delay
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _showNextPopup();
        });
      }),
    );
    Overlay.of(context).insert(_currentPopupEntry!);
  }

  Future<void> _connectSignalR() async {
    try {
      // Cancel existing subscriptions to avoid duplicates on reconnect
      await _notificationSubscription?.cancel();
      await _attendanceSubscription?.cancel();
      await _deviceStatusSubscription?.cancel();
      await _communicationSubscription?.cancel();

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      // Get a valid (non-expired) token, refreshing if necessary
      final token = await authProvider.getValidToken();
      // Pass token factory for auto-refresh on reconnection
      await _signalRService.connect(null, token, () => authProvider.getValidToken());
      
      if (!mounted) return;
      // Join store group for store-scoped notifications
      final storeId = authProvider.user?.storeId;
      if (storeId != null && storeId.isNotEmpty) {
        await _signalRService.joinStoreGroup(storeId);
      }
      // Join user group for user-specific notifications
      final userId = authProvider.user?.id;
      if (userId != null && userId.isNotEmpty) {
        await _signalRService.joinUserGroup(userId);
      }
      
      _notificationSubscription =
          _signalRService.onNewNotification.listen(_handleNewNotification);
      // Listen for new attendance from ADMS devices
      _attendanceSubscription =
          _signalRService.onNewAttendance.listen(_handleNewAttendance);
      // Listen for device status changes (online/offline)
      _deviceStatusSubscription = _signalRService.onDeviceStatusChanged
          .listen(_handleDeviceStatusChanged);
      // Listen for communication events (messages, comments, reactions)
      _communicationSubscription =
          _signalRService.onCommunicationEvent.listen(_handleCommunicationEvent);
    } catch (e) {
      debugPrint('Error connecting SignalR in MainLayout: $e');
    }
  }

  /// Handle device status change - show popup when device connects/disconnects
  void _handleDeviceStatusChanged(DeviceStatusNotification notification) {
    if (!mounted) return;

    debugPrint(
        '📡 Device status changed: ${notification.deviceName} - ${notification.status}');

    // Kiểm tra nhóm thông báo chấm công có bật không (device thuộc nhóm chấm công)
    NotificationGroupSettings.isAttendanceEnabled().then((enabled) {
      if (!enabled || !mounted) return;
      final isMobile = mounted && MediaQuery.of(context).size.width < 600;
      // Mobile: không hiện popup/notif ở đây - để _handleNewNotification xử lý (có notificationId)
      if (!isMobile) {
        NotificationSound().play();
        _showDeviceStatusPopup(notification);
      }
    });

    // Auto-refresh ADMS devices screen (luôn refresh)
    ScreenRefreshNotifier.refreshDevicesScreen();
    // Cập nhật badge chuông vì device notification đã lưu vào DB
    _loadNotificationCount();
  }

  /// Show device status popup via queue
  void _showDeviceStatusPopup(DeviceStatusNotification notification) {
    _enqueuePopup((onDismiss) => _DeviceStatusPopup(
      notification: notification,
      onDismiss: onDismiss,
      onTap: () {
        onDismiss();
        _navigateToIndex(NavigationNotifier.deviceUsers);
      },
    ));
  }

  /// Handle new attendance from ADMS device - show popup globally
  void _handleNewAttendance(Attendance attendance) {
    if (!mounted) return;

    // Kiểm tra nhóm thông báo chấm công có bật không
    NotificationGroupSettings.isAttendanceEnabled().then((enabled) {
      if (!enabled || !mounted) return;

      final timeStr = DateFormat('HH:mm:ss').format(attendance.attendanceTime);
      final stateText = attendance.punchTypeText;
      final userName = attendance.employeeName ?? attendance.pin ?? 'Unknown';
      final isCheckIn = attendance.attendanceState == 0;
      final verifyType = attendance.verifyTypeText;
      final deviceName = attendance.deviceName ?? 'ADMS Device';

      final isMobile = mounted && MediaQuery.of(context).size.width < 600;
      // Mobile: không hiện popup/notif ở đây - để _handleNewNotification xử lý (có notificationId)
      if (!isMobile) {
        _showAttendancePopup(
          userName: userName,
          stateText: stateText,
          timeStr: timeStr,
          deviceName: deviceName,
          isCheckIn: isCheckIn,
          verifyType: verifyType,
        );
      }
    });

    // Auto-refresh attendance screen (luôn refresh bất kể bật/tắt thông báo)
    ScreenRefreshNotifier.refreshAttendanceScreen();
    ScreenRefreshNotifier.refreshAttendanceSummaryScreen();
    ScreenRefreshNotifier.refreshAttendanceByShiftScreen();
    ScreenRefreshNotifier.refreshPayrollScreen();
    // Cập nhật badge chuông vì attendance notification đã lưu vào DB
    _loadNotificationCount();
  }

  /// Show attendance popup via queue
  void _showAttendancePopup({
    required String userName,
    required String stateText,
    required String timeStr,
    required String deviceName,
    required bool isCheckIn,
    required String verifyType,
  }) {
    _enqueuePopup((onDismiss) => _AttendanceNotificationPopup(
      userName: userName,
      stateText: stateText,
      timeStr: timeStr,
      deviceName: deviceName,
      isCheckIn: isCheckIn,
      verifyType: verifyType,
      onDismiss: onDismiss,
      onTap: () {
        onDismiss();
        _navigateToIndex(NavigationNotifier.attendance);
      },
    ));
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final title = data['title'] ?? 'Thông báo mới';
      final message = data['message'] ?? '';
      final typeValue = data['type'] ?? 0;
      final type = _parseNotificationType(typeValue);
      final relatedEntityType = data['relatedEntityType'] as String?;
      final entityTypeLower = relatedEntityType?.toLowerCase();
      final notificationId = data['id']?.toString();

      // Cập nhật số thông báo chưa đọc từ server (chính xác hơn local increment)
      _loadNotificationCount();

      // Kiểm tra nhóm thông báo trước khi hiển thị popup
      _shouldShowNotification(relatedEntityType).then((shouldShow) {
        if (!shouldShow || !mounted) return;

        final isMobile = mounted && MediaQuery.of(context).size.width < 600;
        final isAttendanceOrDevice = entityTypeLower == 'attendance' ||
            entityTypeLower == 'device' ||
            entityTypeLower == 'devicestatus' ||
            entityTypeLower == 'newattendance';

        if (isMobile) {
          // Mobile: gửi notification hệ thống Android cho TẤT CẢ loại thông báo
          _systemNotification.showGeneral(
            title: title,
            message: message,
            relatedEntityType: relatedEntityType,
            notificationId: notificationId,
          );
        } else if (!isAttendanceOrDevice) {
          // Desktop: chỉ hiện popup cho các loại không phải attendance/device
          // (attendance/device đã có popup riêng từ handler của chúng)
          _notificationManager.show(
            title: title,
            message: message,
            type: type,
            relatedEntityType: relatedEntityType,
            duration: const Duration(seconds: 2),
            onTap: () {
              if (notificationId != null) {
                _apiService.markNotificationAsRead(notificationId).then((_) {
                  _loadNotificationCount();
                });
              }
              _navigateToIndex(_getIndexForEntityType(relatedEntityType));
            },
          );
        }
      });
    } catch (e) {
      debugPrint('Error handling notification: $e');
    }
  }

  /// Parse NotificationType an toàn từ int value
  NotificationType _parseNotificationType(dynamic typeValue) {
    if (typeValue is int && typeValue >= 0 && typeValue < NotificationType.values.length) {
      return NotificationType.values[typeValue];
    }
    // Fallback: map theo tên nếu là string
    if (typeValue is String) {
      final lower = typeValue.toLowerCase();
      for (final t in NotificationType.values) {
        if (t.name.toLowerCase() == lower) return t;
      }
    }
    return NotificationType.info;
  }

  /// Handle communication events (tin nhắn, bình luận, reaction)
  void _handleCommunicationEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    debugPrint('📡 Communication event received: $data');

    final eventType = data['eventType'] as String? ?? 'new';
    final title = data['title'] as String? ?? 'Tin nhắn mới';
    final message = data['message'] as String? ?? data['content'] as String? ?? '';

    // Cập nhật badge
    _loadNotificationCount();

    // Kiểm tra nhóm thông báo công việc có bật không
    NotificationGroupSettings.isWorkEnabled().then((enabled) {
      if (!enabled || !mounted) return;

      final isMobile = mounted && MediaQuery.of(context).size.width < 600;
      if (isMobile) {
        _systemNotification.showGeneral(
          title: title,
          message: message,
          relatedEntityType: 'Communication',
        );
      } else {
        _notificationManager.show(
          title: title,
          message: message,
          type: NotificationType.info,
          relatedEntityType: 'Communication',
          duration: const Duration(seconds: 3),
          onTap: () {
            _navigateToIndex(_getIndexForEntityType('Communication'));
          },
        );
      }
    });
  }

  /// Kiểm tra xem có nên hiển thị popup thông báo dựa trên nhóm bật/tắt
  Future<bool> _shouldShowNotification(String? relatedEntityType) async {
    if (NotificationGroupSettings.isAttendanceType(relatedEntityType)) {
      return await NotificationGroupSettings.isAttendanceEnabled();
    } else {
      return await NotificationGroupSettings.isWorkEnabled();
    }
  }

  Future<void> _loadNotificationCount() async {
    try {
      final summary = await _apiService.getNotificationSummary();
      if (mounted) {
        setState(() {
          _unreadNotificationsCount = summary['unreadCount'] ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Error loading notification count: $e');
    }
  }

  // Tìm index của màn hình Thông báo
  int get _notificationsIndex {
    for (int i = 0; i < _navItems.length; i++) {
      if (_navItems[i].moduleCode == 'Notification') return i;
    }
    return 8; // Default index
  }

  // Chuyển đến màn hình phù hợp theo loại thông báo
  int _getIndexForEntityType(String? entityType) {
    switch (entityType?.toLowerCase()) {
      case 'attendance':
      case 'attendancecorrection':
      case 'overtime':
      case 'newattendance':
        return NavigationNotifier.attendance;
      case 'leave':
        return NavigationNotifier.leaves;
      case 'device':
      case 'devicestatus':
      case 'admsdevice':
        return NavigationNotifier.deviceUsers;
      case 'workschedule':
      case 'scheduleregistration':
        return NavigationNotifier.workSchedule;
      case 'employee':
        return NavigationNotifier.employees;
      case 'payroll':
      case 'payslip':
        return NavigationNotifier.payroll;
      case 'task':
      case 'worktask':
        return NavigationNotifier.taskManagement;
      case 'communication':
        return NavigationNotifier.communication;
      case 'advancerequest':
        return NavigationNotifier.advanceRequests;
      case 'asset':
        return NavigationNotifier.assetManagement;
      case 'kpi':
      case 'kpisalary':
        return NavigationNotifier.kpi;
      case 'bonuspenalty':
        return NavigationNotifier.bonusPenalty;
      case 'cashtransaction':
        return NavigationNotifier.cashTransaction;
      case 'penaltytickets':
        return NavigationNotifier.penaltyTickets;
      default:
        return _notificationsIndex;
    }
  }

  final List<NavItem> _navItems = [
    // ══════════ TỔNG QUAN ══════════
    NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Trang chủ',
      screen: const SizedBox(), // Will be replaced by _HomeMenuScreen
      group: 'Tổng quan',
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'Home',
    ),
    NavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Thông báo',
      screen: const NotificationsScreen(),
      group: 'Tổng quan',
      showInSidebar: false,
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'Notification',
    ),

    // ══════════ HỒ SƠ NHÂN SỰ ══════════
    NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Tổng quan',
      subtitle: 'Bảng điều khiển tổng quan',
      screen: const DashboardScreen(),
      group: 'Tổng quan',
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'Dashboard',
    ),
    NavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Hồ sơ nhân sự',
      subtitle: 'Thông tin nhân viên, chức vụ',
      screen: const EmployeesScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'Employee',
    ),
    NavItem(
      icon: Icons.badge_outlined,
      activeIcon: Icons.badge,
      label: 'Nhân sự chấm công',
      subtitle: 'Nhân sự trên máy chấm công',
      screen: const DeviceUsersScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'DeviceUser',
    ),
    NavItem(
      icon: Icons.business_outlined,
      activeIcon: Icons.business,
      label: 'Phòng ban',
      subtitle: 'Cơ cấu tổ chức, sơ đồ phòng ban',
      screen: const DepartmentScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'Department',
    ),
    NavItem(
      icon: Icons.event_busy_outlined,
      activeIcon: Icons.event_busy,
      label: 'Nghỉ phép',
      subtitle: 'Đơn nghỉ phép, phép năm còn lại',
      screen: const LeaveScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'Leave',
    ),
    NavItem(
      icon: Icons.price_change_outlined,
      activeIcon: Icons.price_change,
      label: 'Thiết lập lương',
      subtitle: 'Cấu hình bảng lương',
      screen: const SalarySettingsScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'SalarySettings',
    ),

    // ══════════ CHẤM CÔNG ══════════
    NavItem(
      icon: Icons.access_time_outlined,
      activeIcon: Icons.access_time_filled,
      label: 'Chấm công',
      subtitle: 'Dữ liệu chấm công',
      screen: const AttendanceScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'Attendance',
    ),
    NavItem(
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month,
      label: 'Lịch làm việc',
      subtitle: 'Phân ca, lịch trình làm việc',
      screen: const WorkScheduleScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'WorkSchedule',
    ),
    NavItem(
      icon: Icons.summarize_outlined,
      activeIcon: Icons.summarize,
      label: 'Tổng hợp chấm công',
      subtitle: 'Bảng tổng hợp công theo tháng',
      screen: const AttendanceSummaryScreen(),
      group: 'Chấm công',
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'AttendanceSummary',
    ),
    NavItem(
      icon: Icons.schedule_outlined,
      activeIcon: Icons.schedule,
      label: 'Tổng hợp theo ca',
      subtitle: 'Thống kê giờ công theo ca làm',
      screen: const AttendanceByShiftScreen(),
      group: 'Chấm công',
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'AttendanceByShift',
    ),
    NavItem(
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      label: 'Duyệt chấm công',
      subtitle: 'Duyệt bổ sung, sửa chấm công',
      screen: const AttendanceApprovalScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'AttendanceApproval',
    ),
    NavItem(
      icon: Icons.assignment_turned_in_outlined,
      activeIcon: Icons.assignment_turned_in,
      label: 'Duyệt lịch làm việc',
      subtitle: 'Duyệt đề xuất đổi ca, lịch',
      screen: const ScheduleApprovalScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'ScheduleApproval',
    ),
    NavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Tổng hợp lương',
      subtitle: 'Bảng lương nhân viên',
      screen: const PayrollScreen(),
      group: 'Chấm công',
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'Payroll',
    ),

    NavItem(
      icon: Icons.app_registration_outlined,
      activeIcon: Icons.app_registration,
      label: 'Đăng ký chấm công Mobile',
      subtitle: 'Đăng ký thiết bị & khuôn mặt',
      screen: const MobileDeviceRegistrationScreen(),
      group: 'Chấm công',
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'MobileDeviceRegistration',
    ),
    NavItem(
      icon: Icons.phone_android_outlined,
      activeIcon: Icons.phone_android,
      label: 'Chấm công Mobile',
      subtitle: 'Chấm công bằng điện thoại',
      screen: const MobileAttendanceScreen(),
      group: 'Chấm công',
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'MobileAttendance',
    ),
    NavItem(
      icon: Icons.how_to_reg_outlined,
      activeIcon: Icons.how_to_reg,
      label: 'Duyệt chấm công Mobile',
      subtitle: 'Duyệt & quản lý đăng ký khuôn mặt',
      screen: const MobileAttendanceApprovalScreen(),
      group: 'Chấm công',
      themeColor: const Color(0xFF0284C7),
      moduleCode: 'MobileAttendanceApproval',
    ),
    NavItem(
      icon: Icons.restaurant_outlined,
      activeIcon: Icons.restaurant,
      label: 'Chấm cơm',
      subtitle: 'Quản lý suất ăn',
      screen: const MealTrackingScreen(),
      group: 'Quản lý Vận hành',
      themeColor: const Color(0xFF059669),
      moduleCode: 'Meal',
    ),

    // ══════════ TÀI CHÍNH ══════════
    NavItem(
      icon: Icons.card_giftcard_outlined,
      activeIcon: Icons.card_giftcard,
      label: 'Thưởng / Phạt',
      subtitle: 'Quản lý thưởng, kỷ luật nhân viên',
      screen: const BonusPenaltyScreen(),
      group: 'Tài chính',
      showInSidebar: false,
      themeColor: const Color(0xFFEC4899),
      moduleCode: 'BonusPenalty',
    ),
    NavItem(
      icon: Icons.money_outlined,
      activeIcon: Icons.money,
      label: 'Ứng lương',
      subtitle: 'Quản lý ứng lương',
      screen: const AdvanceRequestsScreen(),
      group: 'Tài chính',
      showInSidebar: false,
      themeColor: const Color(0xFFEC4899),
      moduleCode: 'AdvanceRequests',
    ),
    NavItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Thu chi',
      subtitle: 'Sổ thu chi, quỹ tiền mặt',
      screen: const CashTransactionScreen(),
      group: 'Tài chính',
      showInSidebar: false,
      themeColor: const Color(0xFFEC4899),
      moduleCode: 'CashTransaction',
    ),

    // ══════════ QUẢN LÝ VẬN HÀNH ══════════
    NavItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      label: 'Tài sản',
      subtitle: 'Quản lý tài sản, thiết bị công ty',
      screen: const AssetManagementScreen(),
      group: 'Quản lý Vận hành',
      showInSidebar: false,
      themeColor: const Color(0xFF059669),
      moduleCode: 'Asset',
    ),
    NavItem(
      icon: Icons.task_alt_outlined,
      activeIcon: Icons.task_alt,
      label: 'Công việc',
      subtitle: 'Giao việc, theo dõi tiến độ',
      screen: const TaskManagementScreen(),
      group: 'Quản lý Vận hành',
      showInSidebar: false,
      themeColor: const Color(0xFF059669),
      moduleCode: 'Task',
    ),
    NavItem(
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign,
      label: 'Truyền thông',
      subtitle: 'Tin tức, thông báo, nội quy nội bộ',
      screen: const CommunicationScreen(),
      group: 'Quản lý Vận hành',
      themeColor: const Color(0xFF059669),
      moduleCode: 'Communication',
    ),


    // ══════════ KPI ══════════
    NavItem(
      icon: Icons.trending_up_outlined,
      activeIcon: Icons.trending_up,
      label: 'KPI',
      subtitle: 'Chỉ tiêu, đánh giá hiệu suất',
      screen: const KpiScreen(),
      group: 'Quản lý Vận hành',
      themeColor: const Color(0xFF059669),
      moduleCode: 'KPI',
    ),

    // ══════════ SẢN LƯỢNG ══════════
    NavItem(
      icon: Icons.precision_manufacturing_outlined,
      activeIcon: Icons.precision_manufacturing,
      label: 'Sản lượng',
      subtitle: 'Nhập sản lượng, tính lương sản phẩm',
      screen: const ProductionOutputScreen(),
      group: 'Quản lý Vận hành',
      themeColor: const Color(0xFF059669),
      moduleCode: 'Production',
    ),

    // ══════════ PHẢN ÁNH / Ý KIẾN ══════════
    NavItem(
      icon: Icons.feedback_outlined,
      activeIcon: Icons.feedback,
      label: 'Phản ánh / Ý kiến',
      subtitle: 'Phản ánh, góp ý ẩn danh hoặc công khai',
      screen: const FeedbackScreen(),
      group: 'Quản lý Vận hành',
      themeColor: const Color(0xFF1E3A5F),
      moduleCode: 'Feedback',
    ),

    // ══════════ CHECK-IN ĐIỂM BÁN ══════════
    NavItem(
      icon: Icons.location_on_outlined,
      activeIcon: Icons.location_on,
      label: 'Check-in điểm bán',
      subtitle: 'Check-in, báo cáo tại điểm bán',
      screen: const FieldCheckInScreen(),
      group: 'Quản lý Vận hành',
      themeColor: const Color(0xFF059669),
      moduleCode: 'FieldCheckIn',
    ),

    // ══════════ BÁO CÁO ══════════
    NavItem(
      icon: Icons.people_alt_outlined,
      activeIcon: Icons.people_alt,
      label: 'Báo cáo nhân sự',
      subtitle: 'Thống kê nhân sự, phòng ban',
      screen: const HrReportScreen(),
      group: 'Báo cáo',
      showInSidebar: false,
      themeColor: const Color(0xFF7C3AED),
      moduleCode: 'HrReport',
    ),
    NavItem(
      icon: Icons.schedule_outlined,
      activeIcon: Icons.schedule,
      label: 'Báo cáo chấm công',
      subtitle: 'Ngày, tháng, đi muộn, phòng ban',
      screen: const AttendanceReportScreen(),
      group: 'Báo cáo',
      showInSidebar: false,
      themeColor: const Color(0xFF7C3AED),
      moduleCode: 'AttendanceReport',
    ),
    NavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Báo cáo lương',
      subtitle: 'Chi phí lương, phân bổ',
      screen: const PayrollReportScreen(),
      group: 'Báo cáo',
      showInSidebar: false,
      themeColor: const Color(0xFF7C3AED),
      moduleCode: 'PayrollReport',
    ),

    // ══════════ ĐẠI LÝ ══════════
    NavItem(
      icon: Icons.vpn_key_outlined,
      activeIcon: Icons.vpn_key,
      label: 'License Keys',
      subtitle: 'Danh sách key được cấp',
      screen: const AgentLicenseKeysScreen(),
      group: 'Đại lý',
      showInSidebar: true,
      themeColor: const Color(0xFFF59E0B),
      requiredRole: 'Agent',
    ),

    // ══════════ CÀI ĐẶT ══════════
    NavItem(
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune,
      label: 'Thiết lập HRM',
      subtitle: 'Ca làm, phụ cấp, bảo hiểm, thuế',
      screen: const SettingsHubScreen(),
      group: 'Cài đặt',
      showInSidebar: false,
      themeColor: const Color(0xFF64748B),
      moduleCode: 'SettingsHub',
    ),
    NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Cài đặt',
      subtitle: 'Giao diện, ngôn ngữ, kết nối',
      screen: const SettingsScreen(),
      group: 'Cài đặt',
      showInSidebar: false,
      themeColor: const Color(0xFF64748B),
      moduleCode: 'Settings',
    ),
    NavItem(
      icon: Icons.admin_panel_settings_outlined,
      activeIcon: Icons.admin_panel_settings,
      label: 'Quản trị hệ thống',
      subtitle: 'Quản lý server, database, logs',
      screen: const SystemAdminScreen(),
      group: 'Cài đặt',
      showInSidebar: true,
      themeColor: const Color(0xFF64748B),
      adminOnly: true,
    ),
    // ══════════ TÀI CHÍNH (phiếu phạt tự động) ══════════
    NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Phiếu phạt',
      subtitle: 'Phiếu phạt tự động từ chấm công',
      screen: const PenaltyTicketsScreen(),
      group: 'Tài chính',
      showInSidebar: false,
      themeColor: const Color(0xFFEC4899),
      moduleCode: 'PenaltyTickets',
    ),
    // ══════════ THIẾT LẬP THÔNG BÁO ══════════
    NavItem(
      icon: Icons.notifications_active_outlined,
      activeIcon: Icons.notifications_active,
      label: 'Thiết lập thông báo',
      subtitle: 'Bật/tắt thông báo chấm công & công việc',
      screen: const NotificationSettingsScreen(),
      group: 'Cài đặt',
      showInSidebar: true,
      themeColor: const Color(0xFFF59E0B),
      moduleCode: 'NotificationSettings',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 1024;
    final isTablet = MediaQuery.of(context).size.width >= 768;

    if (isDesktop) {
      return _buildDesktopLayout();
    } else if (isTablet) {
      return _buildTabletLayout();
    } else {
      return _buildMobileLayout();
    }
  }

  Widget _getScreenForIndex(int index) {
    if (index == 0) {
      final authUser = Provider.of<AuthProvider>(context, listen: false).user;
      final isSuperAdmin = authUser?.role == 'SuperAdmin';
      final isAgent = authUser?.role == 'Agent';
      return _HomeMenuScreen(
        navItems: _navItems,
        onItemTap: (idx) => _navigateToIndex(idx),
        allowedModules: (isSuperAdmin || isAgent) ? null : authUser?.allowedModules,
      );
    }
    return _navItems[index].screen;
  }

  // Desktop Layout với Navigation Rail mở rộng
  Widget _buildDesktopLayout() {
    return NotificationOverlay(
      child: Scaffold(
        body: Row(
          children: [
            // Sidebar
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _isExpanded ? 250 : 60,
              child: _buildSidebar(),
            ),
            // Main content
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: _getScreenForIndex(_selectedIndex),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Tablet Layout với Navigation Rail thu gọn
  Widget _buildTabletLayout() {
    return NotificationOverlay(
      child: Scaffold(
        body: Row(
          children: [
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height,
                ),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) {
                      _navigateToIndex(index);
                    },
                    labelType: NavigationRailLabelType.all,
                    destinations: _navItems
                        .map((item) => NavigationRailDestination(
                              icon: Icon(item.icon),
                              selectedIcon: Icon(item.activeIcon),
                              label: Text(item.localizedLabel(AppLocalizations.of(context))),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: _getScreenForIndex(_selectedIndex),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mobile bottom nav: 4 key screens + "Thêm" (opens drawer)
  // Each entry: (navIndex, icon, activeIcon, moduleCode)
  static const _mobileBottomNavDefs = [
    (navIndex: 0, icon: Icons.home_outlined, activeIcon: Icons.home, moduleCode: 'Home'),
    (navIndex: 2, icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, moduleCode: 'Dashboard'),
    (navIndex: 16, icon: Icons.fingerprint_outlined, activeIcon: Icons.fingerprint, moduleCode: 'MobileAttendance'),
    (navIndex: 14, icon: Icons.payments_outlined, activeIcon: Icons.payments, moduleCode: 'Payroll'),
  ];

  static String _mobileNavLabel(String moduleCode, AppLocalizations l) {
    // Short labels for bottom nav to prevent overflow
    switch (moduleCode) {
      case 'Payroll': return l.payrollShort;
      case 'Home': return l.home;
      case 'Dashboard': return l.overview;
      case 'MobileAttendance': return 'Chấm công';
      default: return moduleCode;
    }
  }

  // Scaffold key for programmatic drawer open from bottom nav "Thêm"
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();

  // Mobile Layout với Bottom Navigation
  Widget _buildMobileLayout() {
    final l = AppLocalizations.of(context);

    // Map _selectedIndex → bottom nav position; 4 = "Thêm" (drawer)
    final bottomNavIndex = _mobileBottomNavDefs.indexWhere((d) => d.navIndex == _selectedIndex);
    final safeBottomIndex = bottomNavIndex == -1 ? 4 : bottomNavIndex;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_canGoBack) {
          _goBack();
        } else {
          // Minimize app to background instead of killing
          SystemNavigator.pop();
        }
      },
      child: NotificationOverlay(
      child: Scaffold(
        key: _mobileScaffoldKey,
        appBar: AppBar(
          leading: _canGoBack
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goBack,
                  tooltip: l.goBack,
                )
              : null,
          title: Text(_navItems[_selectedIndex].localizedLabel(l)),
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: _unreadNotificationsCount > 0,
                label: Text(_unreadNotificationsCount > 99
                    ? '99+'
                    : '$_unreadNotificationsCount'),
                child: const Icon(Icons.notifications_outlined),
              ),
              onPressed: () {
                _navigateToIndex(_notificationsIndex);
                _loadNotificationCount();
              },
              tooltip: l.notifications,
            ),
            _buildUserMenu(),
          ],
        ),
        body: _getScreenForIndex(_selectedIndex),
        bottomNavigationBar: _buildModernBottomNav(safeBottomIndex, l),
        drawer: _buildDrawer(),
      ),
    ),
    );
  }

  Widget _buildModernBottomNav(int selectedIndex, AppLocalizations l) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final unselectedColor = isDark ? Colors.white54 : Colors.grey.shade500;

    // All items: 4 defs + "Thêm"
    final allItems = [
      ..._mobileBottomNavDefs.map((d) => (
        icon: d.icon,
        activeIcon: d.activeIcon,
        label: _mobileNavLabel(d.moduleCode, l),
        navIndex: d.navIndex,
        isCenterAction: d.moduleCode == 'MobileAttendance',
      )),
      (
        icon: Icons.grid_view_outlined,
        activeIcon: Icons.grid_view_rounded,
        label: l.more,
        navIndex: -1, // special: drawer
        isCenterAction: false,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: List.generate(allItems.length, (index) {
              final item = allItems[index];
              final isSelected = index == selectedIndex;

              // Center punch button with special elevated style
              if (item.isCenterAction) {
                return Expanded(
                  child: _buildCenterNavItem(
                    icon: item.activeIcon,
                    label: item.label,
                    isSelected: isSelected,
                    primaryColor: primaryColor,
                    surfaceColor: surfaceColor,
                    onTap: () => _navigateToIndex(item.navIndex),
                  ),
                );
              }

              return Expanded(
                child: _buildNavItem(
                  icon: isSelected ? item.activeIcon : item.icon,
                  label: item.label,
                  isSelected: isSelected,
                  selectedColor: primaryColor,
                  unselectedColor: unselectedColor,
                  onTap: () {
                    if (item.navIndex == -1) {
                      _mobileScaffoldKey.currentState?.openDrawer();
                    } else {
                      _navigateToIndex(item.navIndex);
                    }
                  },
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color primaryColor,
    required Color surfaceColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSelected
                    ? [primaryColor, primaryColor.withValues(alpha: 0.8)]
                    : [primaryColor.withValues(alpha: 0.85), primaryColor.withValues(alpha: 0.65)],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: isSelected ? 0.45 : 0.25),
                  blurRadius: isSelected ? 16 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isSelected ? primaryColor : primaryColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color selectedColor,
    required Color unselectedColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: isSelected
            ? BoxDecoration(
                color: selectedColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? selectedColor : unselectedColor,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? selectedColor : unselectedColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Sidebar cho Desktop
  Widget _buildSidebar() {
    // Group order
    const groupOrder = ['Tổng quan', 'Hồ sơ nhân sự', 'Chấm công', 'Tài chính', 'Quản lý Vận hành', 'Báo cáo', 'Đại lý', 'Cài đặt'];

    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final userRole = authUser?.role ?? '';
    final isSuperAdmin = userRole == 'SuperAdmin';
    final isAgent = userRole == 'Agent';
    final allowedModules = authUser?.allowedModules;
    final permProvider = Provider.of<PermissionProvider>(context);

    // Build grouped items preserving original indices (only sidebar items)
    final groupedItems = <String, List<MapEntry<int, NavItem>>>{};
    for (int i = 0; i < _navItems.length; i++) {
      if (!_navItems[i].showInSidebar) continue;
      if (_navItems[i].adminOnly && !isSuperAdmin) continue;
      if (_navItems[i].requiredRole != null && _navItems[i].requiredRole != userRole) continue;
      // Agents only see items with requiredRole == 'Agent'
      if (isAgent && _navItems[i].requiredRole != 'Agent') continue;
      // Lọc theo gói dịch vụ - SuperAdmin/Agent không bị giới hạn
      if (!isSuperAdmin && !isAgent && allowedModules != null && allowedModules.isNotEmpty
          && _navItems[i].moduleCode != null && !allowedModules.contains(_navItems[i].moduleCode)) {
        continue;
      }
      // Lọc theo quyền canView - ẩn module nếu không có quyền xem
      if (!permProvider.canView(_navItems[i].moduleCode)) continue;
      final group = _navItems[i].group.isEmpty ? 'Khác' : _navItems[i].group;
      groupedItems.putIfAbsent(group, () => []);
      groupedItems[group]!.add(MapEntry(i, _navItems[i]));
    }

    return Container(
      color: const Color(0xFFF1F4F6), // surface-container-low
      child: Column(
        children: [
          // Header with logo
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Container(
              height: 64,
              padding: EdgeInsets.symmetric(horizontal: _isExpanded ? 16 : 8),
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FA), // surface
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset('assets/logo.png', width: _isExpanded ? 32 : 28, height: _isExpanded ? 32 : 28),
                  ),
                  if (_isExpanded) ...[
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('SBOX HRM', style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900,
                        color: Color(0xFF0C56D0), letterSpacing: -0.5,
                      ), overflow: TextOverflow.ellipsis),
                    ),
                    Icon(Icons.chevron_left_rounded, color: const Color(0xFF586064).withValues(alpha: 0.5), size: 22),
                  ],
                ],
              ),
            ),
          ),

          // Grouped navigation items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: groupOrder.where((g) => groupedItems.containsKey(g)).expand((groupName) {
                final items = groupedItems[groupName]!;
                final isCollapsed = _collapsedGroups.contains(groupName);
                final groupColor = _HomeMenuScreen._groupColors[groupName] ?? const Color(0xFF586064);

                return [
                  // Group header (only when expanded)
                  if (_isExpanded)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_collapsedGroups.contains(groupName)) {
                            _collapsedGroups.remove(groupName);
                          } else {
                            _collapsedGroups.add(groupName);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(left: 20, right: 12, top: 16, bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                groupName.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: groupColor.withValues(alpha: 0.6),
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            Icon(
                              isCollapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                              size: 16,
                              color: const Color(0xFFABB3B7),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 12),

                  // Items
                  if (!isCollapsed || !_isExpanded)
                    ...items.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isSelected = _selectedIndex == index;
                      final accentColor = item.themeColor ?? groupColor;

                      final navWidget = Padding(
                        padding: EdgeInsets.symmetric(horizontal: _isExpanded ? 10 : 6, vertical: 2),
                        child: Material(
                          color: isSelected
                              ? accentColor.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => _navigateToIndex(index),
                            borderRadius: BorderRadius.circular(10),
                            hoverColor: const Color(0xFFE2E9EC), // surface-container-high
                            child: Container(
                              height: 40,
                              padding: EdgeInsets.symmetric(horizontal: _isExpanded ? 12 : 0),
                              decoration: isSelected && _isExpanded
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border(
                                        left: BorderSide(color: accentColor, width: 3),
                                      ),
                                    )
                                  : null,
                              child: Row(
                                mainAxisAlignment: _isExpanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isSelected ? item.activeIcon : item.icon,
                                    size: 20,
                                    color: isSelected
                                        ? accentColor
                                        : const Color(0xFF586064),
                                  ),
                                  if (_isExpanded) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.localizedLabel(AppLocalizations.of(context)),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isSelected
                                              ? const Color(0xFF2B3437)
                                              : const Color(0xFF586064),
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (item.highlight)
                                      Container(
                                        width: 7, height: 7,
                                        decoration: BoxDecoration(
                                          color: accentColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                      return _isExpanded
                          ? navWidget
                          : Tooltip(
                              message: item.localizedLabel(AppLocalizations.of(context)),
                              preferBelow: false,
                              verticalOffset: 0,
                              waitDuration: const Duration(milliseconds: 200),
                              child: navWidget,
                            );
                    }),
                ];
              }).toList(),
            ),
          ),

          // User section
          _buildSidebarUserSection(),
        ],
      ),
    );
  }

  // User section ở sidebar
  Widget _buildSidebarUserSection() {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: _isExpanded ? 10 : 6, vertical: 8),
      padding: EdgeInsets.all(_isExpanded ? 10 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA), // surface
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: _isExpanded ? 20 : 18,
            backgroundColor: const Color(0xFF0C56D0).withValues(alpha: 0.1),
            child: Text(
              (user?.fullName ?? 'U')[0].toUpperCase(),
              style: TextStyle(
                color: const Color(0xFF0C56D0),
                fontWeight: FontWeight.w700,
                fontSize: _isExpanded ? 16 : 14,
              ),
            ),
          ),
          if (_isExpanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.fullName ?? 'User',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF2B3437),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    user?.role ?? 'Employee',
                    style: const TextStyle(
                      color: Color(0xFF586064),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _showLogoutDialog(),
                borderRadius: BorderRadius.circular(8),
                hoverColor: const Color(0xFFE2E9EC),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.logout_rounded, size: 18, color: const Color(0xFF586064).withValues(alpha: 0.7)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Top bar
  Widget _buildTopBar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          if (_canGoBack)
            IconButton(
              icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
              onPressed: _goBack,
              tooltip: AppLocalizations.of(context).goBack,
            ),
          if (_canGoBack) const SizedBox(width: 4),
          Text(
            _navItems[_selectedIndex].localizedLabel(AppLocalizations.of(context)),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          // Search
          Container(
            width: 300,
            height: 40,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).search,
                hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFA1A1AA)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Notifications
          IconButton(
            icon: Badge(
              isLabelVisible: _unreadNotificationsCount > 0,
              label: Text(_unreadNotificationsCount > 99
                  ? '99+'
                  : '$_unreadNotificationsCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () {
              _navigateToIndex(_notificationsIndex);
              // Reload notification count khi chuyển đến màn hình thông báo
              _loadNotificationCount();
            },
            tooltip: AppLocalizations.of(context).notifications,
          ),
          const SizedBox(width: 8),
          _buildUserMenu(),
        ],
      ),
    );
  }

  // User menu
  Widget _buildUserMenu() {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
            child: Text(
              (user?.fullName ?? 'U')[0].toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.keyboard_arrow_down, size: 20),
        ],
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.fullName ?? 'User',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                user?.email ?? '',
                style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 20),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context).personalInfo),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 20),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context).settings),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout, size: 20, color: Colors.red),
              const SizedBox(width: 12),
              Text(AppLocalizations.of(context).logout, style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'profile':
            _navigateToIndex(NavigationNotifier.settingsHub);
            break;
          case 'settings':
            _navigateToIndex(NavigationNotifier.settings);
            break;
          case 'logout':
            _showLogoutDialog();
            break;
        }
      },
    );
  }

  // Drawer cho mobile
  Widget _buildDrawer() {
    const groupOrder = ['Tổng quan', 'Hồ sơ nhân sự', 'Chấm công', 'Tài chính', 'Quản lý Vận hành', 'Báo cáo', 'Đại lý', 'Cài đặt'];
    final l = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final authUser = authProvider.user;
    final userRole = authUser?.role ?? '';
    final isSuperAdmin = userRole == 'SuperAdmin';
    final isAgent = userRole == 'Agent';
    final allowedModules = authUser?.allowedModules;
    final permProvider = Provider.of<PermissionProvider>(context);

    // Build grouped items - same filtering as sidebar
    final groupedItems = <String, List<MapEntry<int, NavItem>>>{};
    for (int i = 0; i < _navItems.length; i++) {
      final item = _navItems[i];
      if (item.adminOnly && !isSuperAdmin) continue;
      if (item.requiredRole != null && item.requiredRole != userRole) continue;
      if (isAgent && item.requiredRole != 'Agent') continue;
      if (!isSuperAdmin && !isAgent && allowedModules != null && allowedModules.isNotEmpty
          && item.moduleCode != null && !allowedModules.contains(item.moduleCode)) {
        continue;
      }
      // Lọc theo quyền canView
      if (!permProvider.canView(item.moduleCode)) continue;
      final group = item.group.isEmpty ? 'Khác' : item.group;
      groupedItems.putIfAbsent(group, () => []);
      groupedItems[group]!.add(MapEntry(i, item));
    }

    return Drawer(
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8F9FA),
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset('assets/logo.png', width: 32, height: 32),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('SBOX HRM', style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900,
                    color: Color(0xFF0C56D0), letterSpacing: -0.5,
                  ), overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: const Color(0xFF586064).withValues(alpha: 0.5), size: 22),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: groupOrder.where((g) => groupedItems.containsKey(g)).map((groupName) {
                final items = groupedItems[groupName]!;
                // Translate group name
                final groupLabel = NavItem._groupMap[groupName] != null
                    ? NavItem._groupMap[groupName]!(l)
                    : groupName;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        groupLabel.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFA1A1AA),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...items.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isSelected = _selectedIndex == index;
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isSelected ? item.activeIcon : item.icon,
                          color: isSelected ? Theme.of(context).primaryColor : const Color(0xFF71717A),
                          size: 22,
                        ),
                        title: Text(
                          item.localizedLabel(l),
                          style: TextStyle(
                            color: isSelected ? Theme.of(context).primaryColor : null,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        selected: isSelected,
                        selectedTileColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        onTap: () {
                          _navigateToIndex(index);
                          Navigator.pop(context);
                        },
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(l.logout, style: const TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showLogoutDialog();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Logout dialog
  void _showLogoutDialog() {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.logout),
        content: Text(l.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<PermissionProvider>(context, listen: false).clear();
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l.logout),
          ),
        ],
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget screen;
  final bool badge;
  final bool highlight;
  final bool adminOnly;
  final String group;
  final bool showInSidebar;
  final String? subtitle;
  final Color? themeColor;
  final String? requiredRole;
  final String? moduleCode;

  NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.screen,
    this.badge = false,
    this.highlight = false,
    this.adminOnly = false,
    this.group = '',
    this.showInSidebar = true,
    this.subtitle,
    this.themeColor,
    this.requiredRole,
    this.moduleCode,
  });

  /// Get localized label based on moduleCode
  String localizedLabel(AppLocalizations l) {
    return _labelMap[moduleCode] != null ? _labelMap[moduleCode]!(l) : label;
  }

  /// Get localized subtitle
  String? localizedSubtitle(AppLocalizations l) {
    return _subtitleMap[moduleCode] != null ? _subtitleMap[moduleCode]!(l) : subtitle;
  }

  /// Get localized group name
  String localizedGroup(AppLocalizations l) {
    return _groupMap[group] != null ? _groupMap[group]!(l) : group;
  }

  static final Map<String, String Function(AppLocalizations)> _labelMap = {
    'Home': (l) => l.home,
    'Notification': (l) => l.notifications,
    'Dashboard': (l) => l.overview,
    'Employee': (l) => l.employeeRecords,
    'DeviceUser': (l) => l.deviceUsers,
    'Department': (l) => l.departments,
    'Leave': (l) => l.leave,
    'SalarySettings': (l) => l.salarySettings,
    'Attendance': (l) => l.attendance,
    'WorkSchedule': (l) => l.workSchedule,
    'AttendanceSummary': (l) => l.attendanceSummary,
    'AttendanceByShift': (l) => l.attendanceByShift,
    'AttendanceApproval': (l) => l.attendanceApproval,
    'ScheduleApproval': (l) => l.scheduleApproval,
    'Payroll': (l) => l.payrollSummary,
    'BonusPenalty': (l) => l.bonusPenalty,
    'AdvanceRequests': (l) => l.salaryAdvance,
    'CashTransaction': (l) => l.incomeExpense,
    'PenaltyTickets': (l) => 'Phiếu phạt',
    'Asset': (l) => l.assets,
    'Task': (l) => l.tasks,
    'Communication': (l) => l.communication,
    'KPI': (l) => 'KPI',
    'Feedback': (l) => 'Phản ánh / Ý kiến',
    'HrReport': (l) => l.hrReport,
    'AttendanceReport': (l) => l.attendanceReport,
    'PayrollReport': (l) => l.payrollReport,
    'SettingsHub': (l) => l.hrmSetup,
    'Settings': (l) => l.settings,
  };

  static final Map<String, String Function(AppLocalizations)> _subtitleMap = {
    'Dashboard': (l) => l.overviewDashboard,
    'Employee': (l) => l.employeeInfo,
    'DeviceUser': (l) => l.deviceUsersSubtitle,
    'SalarySettings': (l) => l.salaryConfigSubtitle,
    'Attendance': (l) => l.attendanceData,
    'Payroll': (l) => l.employeePayroll,
    'AdvanceRequests': (l) => l.advanceManagement,
    'HrReport': (l) => l.hrReportSubtitle,
    'AttendanceReport': (l) => l.attendanceReportSubtitle,
    'PayrollReport': (l) => l.payrollReportSubtitle,
  };

  static final Map<String, String Function(AppLocalizations)> _groupMap = {
    'Tổng quan': (l) => l.groupOverview,
    'Hồ sơ nhân sự': (l) => l.groupHrRecords,
    'Chấm công': (l) => l.groupAttendance,
    'Tài chính': (l) => l.groupFinance,
    'Quản lý Vận hành': (l) => l.groupOperations,
    'Báo cáo': (l) => l.groupReports,
    'Đại lý': (l) => l.groupAgent,
    'Cài đặt': (l) => l.groupSettings,
  };
}

// ══════════════════════════════════════════════════════════
// HOME MENU SCREEN - Dashboard hiển thị tất cả chức năng
// ══════════════════════════════════════════════════════════

class _HomeMenuScreen extends StatefulWidget {
  final List<NavItem> navItems;
  final ValueChanged<int> onItemTap;
  final List<String>? allowedModules;

  const _HomeMenuScreen({
    required this.navItems,
    required this.onItemTap,
    this.allowedModules,
  });

  static const _groupOrder = [
    'Hồ sơ nhân sự',
    'Chấm công',
    'Tài chính',
    'Quản lý Vận hành',
    'Báo cáo',
    'Cài đặt',
  ];

  static const _groupIcons = {
    'Hồ sơ nhân sự': Icons.people,
    'Chấm công': Icons.access_time_filled,
    'Tài chính': Icons.account_balance,
    'Quản lý Vận hành': Icons.business_center,
    'Báo cáo': Icons.assessment,
    'Cài đặt': Icons.settings,
  };

  static const _groupColors = {
    'Hồ sơ nhân sự': Color(0xFF1E3A5F),      // Navy
    'Chấm công': Color(0xFF0284C7),           // Sky 600
    'Tài chính': Color(0xFFEC4899),           // Pink 500
    'Quản lý Vận hành': Color(0xFF059669),   // Emerald 600
    'Báo cáo': Color(0xFF7C3AED),             // Violet 600
    'Cài đặt': Color(0xFF64748B),             // Slate 500
  };

  static const _groupDescriptions = {
    'Hồ sơ nhân sự': 'Quản lý thông tin nhân viên, phòng ban',
    'Chấm công': 'Theo dõi giờ làm, ca làm việc',
    'Tài chính': 'Lương, thưởng, phạt, tạm ứng',
    'Quản lý Vận hành': 'Truyền thông, KPI, đánh giá',
    'Báo cáo': 'Báo cáo & phân tích dữ liệu',
    'Cài đặt': 'Cấu hình hệ thống, thiết bị',
  };

  @override
  State<_HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<_HomeMenuScreen> {
  String _greeting = '';
  String _greetingIcon = '☀️';

  @override
  void initState() {
    super.initState();
    _updateGreeting();
  }

  void _updateGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      _greeting = 'Chào buổi sáng';
      _greetingIcon = '☀️';
    } else if (hour < 18) {
      _greeting = 'Chào buổi chiều';
      _greetingIcon = '🌤️';
    } else {
      _greeting = 'Chào buổi tối';
      _greetingIcon = '🌙';
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final isMobile = MediaQuery.of(context).size.width < 768;
    final padding = isMobile ? 16.0 : 28.0;
    final permProvider = Provider.of<PermissionProvider>(context);

    // Group items
    final groupedItems = <String, List<MapEntry<int, NavItem>>>{};
    for (int i = 0; i < widget.navItems.length; i++) {
      final item = widget.navItems[i];
      if (item.group == 'Tổng quan') continue;
      if (item.adminOnly) continue;
      if (item.requiredRole != null) continue;
      if (widget.allowedModules != null && widget.allowedModules!.isNotEmpty
          && item.moduleCode != null && !widget.allowedModules!.contains(item.moduleCode)) {
        continue;
      }
      // Lọc theo quyền canView
      if (!permProvider.canView(item.moduleCode)) continue;
      final group = item.group.isEmpty ? 'Khác' : item.group;
      groupedItems.putIfAbsent(group, () => []);
      groupedItems[group]!.add(MapEntry(i, item));
    }

    return Container(
      color: const Color(0xFFF1F4F6),
      child: ListView(
        padding: EdgeInsets.all(padding),
        children: [
          // ═══════════════ HERO GREETING BANNER ═══════════════
          Container(
            padding: EdgeInsets.all(isMobile ? 20 : 28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0C56D0), Color(0xFF004ABA)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0C56D0).withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_greetingIcon $_greeting,',
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user?.fullName ?? 'User',
                        style: TextStyle(
                          fontSize: isMobile ? 20 : 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatTodayDate(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isMobile)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.bubble_chart,
                      size: 40,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ═══════════════ QUICK NAV STRIP ═══════════════
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _HomeMenuScreen._groupOrder
                  .where((g) => groupedItems.containsKey(g))
                  .map((groupName) {
                final groupColor = _HomeMenuScreen._groupColors[groupName] ?? Colors.grey;
                final groupIcon = _HomeMenuScreen._groupIcons[groupName] ?? Icons.folder;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Icon(groupIcon, size: 16, color: groupColor),
                    label: Builder(
                      builder: (context) {
                        final l = AppLocalizations.of(context);
                        return Text(
                          NavItem._groupMap[groupName]?.call(l) ?? groupName,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: groupColor),
                        );
                      },
                    ),
                    backgroundColor: groupColor.withValues(alpha: 0.06),
                    side: BorderSide(color: groupColor.withValues(alpha: 0.15)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onPressed: () {
                      // Scroll to group — scroll to first item of group
                      final items = groupedItems[groupName];
                      if (items != null && items.isNotEmpty) {
                        widget.onItemTap(items.first.key);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 28),

          // ═══════════════ FEATURE GROUPS ═══════════════
          ..._HomeMenuScreen._groupOrder
              .where((g) => groupedItems.containsKey(g))
              .map((groupName) {
            final items = groupedItems[groupName]!;
            final groupColor = _HomeMenuScreen._groupColors[groupName] ?? Colors.grey;
            final groupIcon = _HomeMenuScreen._groupIcons[groupName] ?? Icons.folder;
            final groupDesc = _HomeMenuScreen._groupDescriptions[groupName] ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [groupColor, groupColor.withValues(alpha: 0.7)],
                          ),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(groupIcon, size: 18, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Builder(
                              builder: (context) {
                                final l = AppLocalizations.of(context);
                                return Text(
                                  NavItem._groupMap[groupName]?.call(l) ?? groupName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF2B3437),
                                    letterSpacing: -0.3,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 2),
                            Text(
                              groupDesc,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF586064),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: groupColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${items.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: groupColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Items - list on mobile, grid on desktop
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobileLayout = constraints.maxWidth < 600;

                      if (isMobileLayout) {
                        // DECK layout: mỗi chức năng 1 hàng
                        return Column(
                          children: items.map((entry) {
                            final item = entry.value;
                            final index = entry.key;
                            final itemColor = item.themeColor ?? groupColor;
                            final l = AppLocalizations.of(context);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _MenuCard(
                                icon: item.activeIcon,
                                label: item.localizedLabel(l),
                                subtitle: item.localizedSubtitle(l),
                                color: itemColor,
                                onTap: () => widget.onItemTap(index),
                              ),
                            );
                          }).toList(),
                        );
                      }

                      // Desktop: grid layout
                      final crossAxisCount = constraints.maxWidth > 900 ? 4 : 3;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: items.map((entry) {
                          final item = entry.value;
                          final index = entry.key;
                          final itemColor = item.themeColor ?? groupColor;
                          final cardWidth = (constraints.maxWidth - (crossAxisCount - 1) * 10) / crossAxisCount;

                          final l = AppLocalizations.of(context);
                          return SizedBox(
                            width: cardWidth,
                            child: _MenuCard(
                              icon: item.activeIcon,
                              label: item.localizedLabel(l),
                              subtitle: item.localizedSubtitle(l),
                              color: itemColor,
                              onTap: () => widget.onItemTap(index),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatTodayDate() {
    final now = DateTime.now();
    final weekdays = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
    final months = ['Th01', 'Th02', 'Th03', 'Th04', 'Th05', 'Th06', 'Th07', 'Th08', 'Th09', 'Th10', 'Th11', 'Th12'];
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
  }
}

class _MenuCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_MenuCard> createState() => _MenuCardState();
}

class _MenuCardState extends State<_MenuCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => _animController.forward(),
        onTapUp: (_) {
          _animController.reverse();
          widget.onTap();
        },
        onTapCancel: () => _animController.reverse(),
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _isHovered
                  ? widget.color.withValues(alpha: 0.06)
                  : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isHovered
                    ? widget.color.withValues(alpha: 0.25)
                    : const Color(0xFFE8ECF0),
                width: 1,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                // Icon container with gradient
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.color.withValues(alpha: 0.15),
                        widget.color.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(width: 12),
                // Label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _isHovered ? widget.color : const Color(0xFF2B3437),
                          letterSpacing: -0.1,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8A9199),
                            height: 1.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedOpacity(
                  opacity: _isHovered ? 1.0 : 0.3,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: _isHovered ? widget.color : const Color(0xFFB0B7BD),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact Attendance notification toast - clean and modern design
class _AttendanceNotificationPopup extends StatefulWidget {
  final String userName;
  final String stateText;
  final String timeStr;
  final String deviceName;
  final bool isCheckIn;
  final String verifyType;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  const _AttendanceNotificationPopup({
    required this.userName,
    required this.stateText,
    required this.timeStr,
    required this.deviceName,
    required this.isCheckIn,
    required this.verifyType,
    required this.onDismiss,
    this.onTap,
  });

  @override
  State<_AttendanceNotificationPopup> createState() =>
      _AttendanceNotificationPopupState();
}

class _AttendanceNotificationPopupState
    extends State<_AttendanceNotificationPopup>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _progressController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _progressController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
    _progressController.forward().then((_) {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() async {
    _progressController.stop();
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accentColor =
        widget.isCheckIn ? const Color(0xFF22C55E) : const Color(0xFFF59E0B);

    return Positioned(
      top: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: 320,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar at top
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) => Container(
                        height: 3,
                        width: double.infinity,
                        color: Colors.grey.shade200,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (1.0 - _progressController.value).clamp(0.0, 1.0),
                          child: Container(color: accentColor),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Status icon
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              widget.isCheckIn
                                  ? Icons.login_rounded
                                  : Icons.logout_rounded,
                              color: accentColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: accentColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        widget.isCheckIn
                                            ? 'CHECK IN'
                                            : 'CHECK OUT',
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      widget.timeStr,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: _dismiss,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Icon(Icons.close,
                                              size: 16,
                                              color: Colors.grey.shade400),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.userName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1F2937),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.router_outlined,
                                        size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        widget.deviceName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                              _getVerifyIcon(widget.verifyType),
                                              size: 10,
                                              color: Colors.grey.shade600),
                                          const SizedBox(width: 3),
                                          Text(
                                            widget.verifyType,
                                            style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getVerifyIcon(String verifyType) {
    if (verifyType.contains('Khuôn mặt') || verifyType.contains('Face')) {
      return Icons.face;
    } else if (verifyType.contains('Vân tay') ||
        verifyType.contains('Finger')) {
      return Icons.fingerprint;
    } else if (verifyType.contains('Thẻ') || verifyType.contains('Card')) {
      return Icons.credit_card;
    } else if (verifyType.contains('Mật khẩu') ||
        verifyType.contains('Password')) {
      return Icons.password;
    }
    return Icons.verified_user;
  }
}

/// Compact Device status notification toast - clean and modern design
class _DeviceStatusPopup extends StatefulWidget {
  final DeviceStatusNotification notification;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  const _DeviceStatusPopup({
    required this.notification,
    required this.onDismiss,
    this.onTap,
  });

  @override
  State<_DeviceStatusPopup> createState() => _DeviceStatusPopupState();
}

class _DeviceStatusPopupState extends State<_DeviceStatusPopup>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _progressController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _progressController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
    _progressController.forward().then((_) {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() async {
    _progressController.stop();
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _progressController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Color get _statusColor {
    switch (widget.notification.eventType) {
      case 'DeviceOnline':
        return const Color(0xFF22C55E); // Green
      case 'DeviceOffline':
        return const Color(0xFFEF4444); // Red
      case 'NewDeviceDetected':
        return const Color(0xFF1E3A5F); // Blue
      default:
        return const Color(0xFF6B7280); // Gray
    }
  }

  IconData get _statusIcon {
    switch (widget.notification.eventType) {
      case 'DeviceOnline':
        return Icons.wifi_rounded;
      case 'DeviceOffline':
        return Icons.wifi_off_rounded;
      case 'NewDeviceDetected':
        return Icons.add_circle_rounded;
      default:
        return Icons.router_rounded;
    }
  }

  String get _statusLabel {
    switch (widget.notification.eventType) {
      case 'DeviceOnline':
        return 'ONLINE';
      case 'DeviceOffline':
        return 'OFFLINE';
      case 'NewDeviceDetected':
        return 'NEW';
      default:
        return 'STATUS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeStr =
        DateFormat('HH:mm:ss').format(widget.notification.timestamp);

    return Positioned(
      top: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                width: 320,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar at top
                    AnimatedBuilder(
                      animation: _progressController,
                      builder: (context, child) => Container(
                        height: 3,
                        width: double.infinity,
                        color: Colors.grey.shade200,
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (1.0 - _progressController.value).clamp(0.0, 1.0),
                          child: Container(color: _statusColor),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Status icon with animated pulse for offline
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _statusIcon,
                              color: _statusColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _statusColor,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        _statusLabel,
                                        style: const TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: _dismiss,
                                      child: MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Icon(Icons.close,
                                              size: 16,
                                              color: Colors.grey.shade400),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.notification.deviceName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1F2937),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      'SN: ${widget.notification.serialNumber}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    if (widget.notification.location !=
                                        null) ...[
                                      const SizedBox(width: 8),
                                      Icon(Icons.location_on_outlined,
                                          size: 11,
                                          color: Colors.grey.shade500),
                                      const SizedBox(width: 2),
                                      Expanded(
                                        child: Text(
                                          widget.notification.location!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
