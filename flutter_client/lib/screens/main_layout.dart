import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_tr.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../services/global_location_reporter.dart';
import '../services/notification_preferences_cache.dart';
import '../services/signalr_service.dart';
import '../services/pos_print_agent_service.dart';
import '../utils/pos_print_agent_settings.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_qr_order_voice.dart';
import '../services/pos_sell_catalog_cache.dart';
import '../utils/pos_sell_stock_patch.dart';
import '../models/mobile_bottom_nav_config.dart';
import '../models/mobile_quick_actions_config.dart';
import '../services/mobile_bottom_nav_prefs.dart';
import '../services/mobile_quick_actions_prefs.dart';
import '../utils/mobile_bottom_nav_catalog.dart';
import '../utils/mobile_quick_actions_catalog.dart';
import '../widgets/mobile_bottom_nav_config_sheet.dart';
import '../widgets/mobile_quick_actions_config_sheet.dart';
import '../widgets/announcement_banner.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/ai_assistant_sheet.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_pushed_screen_shell.dart';
import '../models/hrm.dart';
import '../models/user.dart';
import '../models/attendance.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/device_sync_progress_overlay.dart';
import '../utils/navigation_notifier.dart';
import 'notification_settings_screen.dart';
import 'employees_screen.dart';
import 'device_users_screen.dart';
import 'attendance_screen.dart';
import 'settings_screen.dart';
import 'system_admin_screen.dart';
import 'settings_hub_screen.dart';
import 'advance_requests_screen.dart';
import 'business_trip_expense_screen.dart';
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
import 'payslip_screen.dart';
import 'salary_settings_screen.dart';
import 'bonus_penalty_screen.dart';
import 'penalty_tickets_screen.dart';
import 'attendance_summary_screen.dart';
import 'attendance_by_shift_screen.dart';
import 'kpi_screen.dart';
import 'dashboard_screen.dart';
import 'overtime_screen.dart';

import 'penalty_report_screen.dart';
import 'cash_report_screen.dart';
import 'advance_report_screen.dart';
import 'business_trip_report_screen.dart';
import 'leave_report_screen.dart';
import 'attendance_report_screen.dart';
import 'late_early_report_screen.dart';
import 'travel_hours_report_screen.dart';
import 'asset_report_screen.dart';
import 'downloaded_documents_screen.dart';
import 'agent_license_keys_screen.dart';
import 'production_output_screen.dart';
import 'feedback_screen.dart';
import 'mobile_attendance_screen.dart';
import '../utils/notification_display_utils.dart';
import '../utils/notification_navigation.dart';
import '../utils/pending_notification_launch.dart';
import 'mobile_device_registration_screen.dart';
import 'meal_tracking_screen.dart';
import 'field_checkin_screen.dart';
import 'pos_products_screen.dart';
import 'pos_sell_screen.dart';
import 'pos_sale_order_list_screen.dart';
import 'pos_sale_return_list_screen.dart';
import 'pos_supplier_list_screen.dart';
import 'warehouse/wh_mobile_nav.dart';
import 'pos/pos_split_report_screens.dart';
import 'hkd_books_screen.dart';
import 'pos/pos_cancel_return_history_screen.dart';
import 'pos/pos_customer_debt_report_screen.dart';
import 'pos/pos_customers_screen.dart';
import 'pos/pos_appointment_day_screen.dart';
import 'pos/pos_warranty_lookup_screen.dart';
import 'pos/pos_mobile_hub_screen.dart';
import 'shift_swap_screen.dart';
import '../utils/permission_navigation.dart';
import '../utils/responsive_helper.dart';
import '../utils/store_role_helper.dart';
import '../widgets/module_route_guard.dart';
import '../widgets/pos/pos_hub_scope.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_theme.dart';
import '../utils/notification_sound_stub.dart';
import '../services/system_notification_service.dart';
import '../services/app_permission_service.dart';

export '../utils/navigation_notifier.dart';

/// Global notifiers for screen refresh
class ScreenRefreshNotifier {
  static final ValueNotifier<int> attendance = ValueNotifier<int>(0);
  static final ValueNotifier<int> devices = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceByShift = ValueNotifier<int>(0);
  static final ValueNotifier<int> attendanceSummary = ValueNotifier<int>(0);
  static final ValueNotifier<int> payroll = ValueNotifier<int>(0);
  static final ValueNotifier<int> dashboard = ValueNotifier<int>(0);

  static void refreshDashboardScreen() {
    dashboard.value++;
    debugPrint('🔄 Triggered dashboard screen refresh: ${dashboard.value}');
  }

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

  static final ValueNotifier<int> mobileAttendanceSettings = ValueNotifier<int>(0);
  static final ValueNotifier<int> mobileDeviceRegistration = ValueNotifier<int>(0);

  static void refreshMobileAttendanceSettings() {
    mobileAttendanceSettings.value++;
  }

  static void refreshMobileDeviceRegistration() {
    mobileDeviceRegistration.value++;
  }

  static final ValueNotifier<int> posProducts = ValueNotifier<int>(0);
  static final ValueNotifier<int> posSellProductGrid = ValueNotifier<int>(0);
  static final ValueNotifier<List<PosSellStockLineDelta>?> posSellStockPatch =
      ValueNotifier<List<PosSellStockLineDelta>?>(null);
  static final ValueNotifier<int> posSaleOrders = ValueNotifier<int>(0);
  static final ValueNotifier<int> posPurchaseReceipts = ValueNotifier<int>(0);
  static final ValueNotifier<int> posOverview = ValueNotifier<int>(0);
  static final ValueNotifier<int> posPriceLists = ValueNotifier<int>(0);
  static final ValueNotifier<int> posSellIndustry = ValueNotifier<int>(0);

  static void refreshPosProducts() {
    posProducts.value++;
  }

  static void refreshPosSellProductGrid() {
    posSellProductGrid.value++;
  }

  static void refreshPosPriceLists() {
    posPriceLists.value++;
  }

  /// Đổi hồ sơ ngành / cờ bàn–ghế — màn bán hàng cần tải lại.
  static void refreshPosSellIndustry() {
    posSellIndustry.value++;
  }

  /// Cộng/trừ tồn trên lưới bán hàng (theo SP/biến thể — khớp server).
  static void patchPosSellStockLines(List<PosSellStockLineDelta> lines) {
    if (lines.isEmpty) return;
    posSellStockPatch.value = List<PosSellStockLineDelta>.from(lines);
  }

  /// Ghi patch vào cache catalog — khi lưới bán chưa mount (F&B sơ đồ / tablet TT)
  /// vẫn trừ đúng tồn khi mở lại thực đơn trong TTL 20 phút.
  static Future<void> _applyStockLinesToSellCatalogCache(
    List<PosSellStockLineDelta> lines, {
    String? storeId,
  }) async {
    final id = (storeId ?? PosSellCatalogCache.instance.lastStoreId)?.trim() ?? '';
    if (id.isEmpty || lines.isEmpty) return;
    try {
      final snap = await PosSellCatalogCache.instance.read(id);
      if (snap == null || snap.items.isEmpty) return;
      final updated = snap.items
          .map((p) => applyPosSellStockLines(p, lines))
          .toList(growable: false);
      await PosSellCatalogCache.instance.write(
        id,
        items: updated,
        catalogVersion: snap.catalogVersion,
      );
    } catch (_) {}
  }

  static void refreshPosSaleOrders() {
    posSaleOrders.value++;
  }

  static void refreshPosPurchaseReceipts() {
    posPurchaseReceipts.value++;
  }

  static void refreshPosOverview() {
    posOverview.value++;
  }

  static Timer? _posStockRefreshTimer;
  static _PendingPosStockRefresh? _pendingPosRefresh;

  static void _flushPosStockRefresh() {
    final pending = _pendingPosRefresh;
    _pendingPosRefresh = null;
    if (pending == null) return;
    refreshPosProducts();
    refreshPosSaleOrders();
    refreshPosPurchaseReceipts();
    refreshPosOverview();
    if (pending.reloadCatalog) {
      unawaited(PosSellCatalogCache.instance.invalidateLast());
      refreshPosSellProductGrid();
    }
  }

  /// [sellStockLines]: patch tồn lưới bán hàng (bán / trả / nhập / hủy).
  /// Mặc định không reload catalog khi đã có patch — tránh refresh storm.
  static void refreshPosAfterStockChange({
    List<PosSellStockLineDelta>? sellStockLines,
    bool? reloadSellCatalog,
    String? storeId,
  }) {
    final hasPatch = sellStockLines != null && sellStockLines.isNotEmpty;
    if (hasPatch) {
      final lines = List<PosSellStockLineDelta>.from(sellStockLines!);
      // Listener lưới (nếu mount) áp dụng ngay + ghi cache + clear notifier.
      patchPosSellStockLines(lines);
      // F&B/tablet: lưới dispose → notifier còn lines → ghi cache rồi clear
      // để remount không trừ lần 2.
      if (posSellStockPatch.value != null) {
        unawaited(_applyStockLinesToSellCatalogCache(lines, storeId: storeId)
            .whenComplete(() {
          if (posSellStockPatch.value != null) {
            posSellStockPatch.value = null;
          }
        }));
      }
    }
    final reloadCatalog = reloadSellCatalog ?? !hasPatch;
    _pendingPosRefresh = _PendingPosStockRefresh(reloadCatalog: reloadCatalog);
    _posStockRefreshTimer?.cancel();
    _posStockRefreshTimer = Timer(const Duration(milliseconds: 300), _flushPosStockRefresh);
  }

  static Timer? _attendanceRefreshTimer;
  static Timer? _notificationCountTimer;

  /// Gom refresh chấm công — tối đa 1 lần / 2s thay vì mỗi punch.
  static void scheduleAttendanceDataRefresh() {
    _attendanceRefreshTimer?.cancel();
    _attendanceRefreshTimer = Timer(const Duration(seconds: 2), () {
      refreshAttendanceScreen();
      refreshAttendanceSummaryScreen();
      refreshAttendanceByShiftScreen();
      refreshPayrollScreen();
      refreshDashboardScreen();
    });
  }

  static void scheduleNotificationCountRefresh() {
    _notificationCountTimer?.cancel();
    _notificationCountTimer = Timer(const Duration(milliseconds: 800), () {
      notifications.value++;
    });
  }
}

class _PendingPosStockRefresh {
  const _PendingPosStockRefresh({required this.reloadCatalog});
  final bool reloadCatalog;
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isExpanded = false;
  static const _kSidebarExpanded = 'main_sidebar_expanded';
  static const _kLastNavIndex = 'main_layout_last_nav_index';
  final ValueNotifier<int> _unreadNotificationsCount = ValueNotifier<int>(0);
  Timer? _notifCountDebounce;
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
  bool _isConnectingSignalR = false;
  bool _topSearchExpanded = false;

  // Popup queue: show one popup at a time to prevent overlap
  final List<Widget Function(VoidCallback onDismiss)> _popupQueue = [];
  OverlayEntry? _currentPopupEntry;
  bool _isShowingPopup = false;

  /// Cached home screen — kept alive via Offstage on desktop/tablet so scroll position is preserved.
  Widget? _homeScreenCache;
  List<String>? _homeAllowedModulesCached;
  bool? _homeBypassPackageFilterCached;
  final Map<int, Widget> _mobileBottomScreenCache = {};
  /// Last visible bottom-nav stack index — used while Home stays Offstage under drawer/POS.
  int? _lastMobileBottomStackIdx;

  // Tracks when SignalR connected so we can suppress stale notifications
  // that were already shown by FCM while the app was in the background.
  DateTime? _signalRConnectedAt;

  // Tracks background/foreground transitions so we can suppress notifications
  // that FCM already showed as system notifications while the app was paused.
  // When SignalR is still alive during background, it buffers events and
  // re-delivers them on resume — those would duplicate what FCM already showed.
  DateTime? _lastBackgroundedAt;
  DateTime? _lastForegroundedAt;

  @override
  void initState() {
    super.initState();
    NavigationNotifier.mainLayoutReady.value = true;
    WidgetsBinding.instance.addObserver(this);
    _systemNotification.initialize();
    _loadNotificationCount();
    _connectSignalR();
    _loadPermissions();
    _loadSidebarPreference();
    unawaited(_restoreLastNavIndex());
    MobileBottomNavPrefs.loadAll();
    MobileBottomNavPrefs.revision.addListener(_onMobileNavPrefsChanged);
    MobileQuickActionsPrefs.revision.addListener(_onMobileNavPrefsChanged);

    // Listen for navigation requests from other screens
    NavigationNotifier.navigateTo.addListener(_onNavigationRequested);
    NavigationNotifier.navigateToModule.addListener(_onModuleNavigationRequested);
    NavigationNotifier.goBackNotifier.addListener(_onGoBackRequested);
    ScreenRefreshNotifier.notifications.addListener(_loadNotificationCount);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportCurrentScreen();
      PendingNotificationLaunch.tryConsume();
      if (!kIsWeb) {
        AppPermissionService.promptEssentialPermissionsIfNeeded(context);
      }
    });
  }

  void _reportCurrentScreen() {
    if (_selectedIndex < 0 || _selectedIndex >= _navItems.length) return;
    final item = _navItems[_selectedIndex];
    var label = item.label;
    if (_selectedIndex == NavigationNotifier.settingsHub) {
      final sub = SettingsHubScreen.activeSubPageTitle;
      if (sub != null && sub.isNotEmpty) label = sub;
    }
    NavigationNotifier.reportScreen(label, moduleCode: item.moduleCode);
  }

  /// Load quyền hiệu lực cho user hiện tại
  void _loadPermissions() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final permProvider =
        Provider.of<PermissionProvider>(context, listen: false);
    if (!permProvider.isLoaded && !permProvider.isLoading) {
      permProvider.loadPermissions(role: authUser?.role);
    }
  }

  Future<void> _loadSidebarPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final expanded = prefs.getBool(_kSidebarExpanded);
    if (!mounted || expanded == null) return;
    setState(() => _isExpanded = expanded);
  }

  Future<void> _restoreLastNavIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt(_kLastNavIndex);
      if (!mounted || idx == null) return;
      if (idx < 0 || idx >= _navItems.length) return;
      if (idx == _selectedIndex) return;
      // Khôi phục module sau khi OS kill app (tắt màn hình / thiếu RAM).
      setState(() => _selectedIndex = idx);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportCurrentScreen();
      });
    } catch (_) {}
  }

  Future<void> _persistLastNavIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastNavIndex, index);
    } catch (_) {}
  }

  Future<void> _toggleSidebar() async {
    setState(() => _isExpanded = !_isExpanded);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSidebarExpanded, _isExpanded);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Record when app goes to background so we can suppress notifications
      // that FCM already showed via the system tray during this period.
      _lastBackgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      // Record foreground time; _isFcmDuplicate() uses this as the suppression cutoff.
      _lastForegroundedAt = DateTime.now();
      // Kiểm tra license cửa hàng — chặn ngay nếu đã hết hạn trong lúc app nền
      if (mounted) {
        context.read<AuthProvider>().verifyStoreLicense();
      }
      // Khi app quay lại foreground: kết nối lại SignalR nếu bị mất và cập nhật badge.
      // Luôn ensureRunning Agent (kể cả SignalR còn connected) — tránh phải tắt/bật tay.
      if (!_signalRService.isConnected) {
        _connectSignalR();
      } else {
        final storeId = context.read<AuthProvider>().user?.storeId;
        if (storeId != null && storeId.isNotEmpty) {
          unawaited(
            PosPrintAgentService.instance
                .ensureRunning(storeId, forceReregister: false),
          );
        }
      }
      _loadNotificationCount();
      final user = context.read<AuthProvider>().currentUser;
      GlobalLocationReporter.instance.resume(
        employeeId: user?.employeeId ?? user?.id,
      );
    }
  }

  void _onNavigationRequested() {
    final targetIndex = NavigationNotifier.navigateTo.value;
    if (targetIndex != null && mounted) {
      final openOvertime = NavigationNotifier.pendingOpenOvertime.value;
      if (openOvertime) {
        NavigationNotifier.pendingOpenOvertime.value = false;
      }
      if (targetIndex != _selectedIndex) {
        if (!_tryNavigateToIndex(targetIndex)) {
          NavigationNotifier.navigateTo.value = null;
          return;
        }
      }
      NavigationNotifier.navigateTo.value = null;
      if (openOvertime) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openOvertimeScreen();
        });
      }
    }
  }

  void _openOvertimeScreen() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canView('Overtime')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Bạn không có quyền xem Tăng ca'))),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const HrmPushedScreenShell(
          title: 'Quản lý tăng ca',
          child: OvertimeScreen(),
        ),
      ),
    );
  }

  void _onModuleNavigationRequested() {
    final code = NavigationNotifier.navigateToModule.value;
    if (code == null || code.isEmpty || !mounted) return;

    final openOvertime = NavigationNotifier.pendingOpenOvertime.value;
    if (openOvertime) {
      NavigationNotifier.pendingOpenOvertime.value = false;
    }

    int? idx;
    for (var i = 0; i < _navItems.length; i++) {
      if (_navItems[i].moduleCode == code) {
        idx = i;
        break;
      }
    }
    NavigationNotifier.navigateToModule.value = null;

    if (idx != null) {
      if (idx != _selectedIndex) {
        if (!_tryNavigateToIndex(idx)) return;
      }
    } else {
      final perm = Provider.of<PermissionProvider>(context, listen: false);
      if (!PermissionNavigation.canNavigate(perm, code)) {
        PermissionNavigation.showDenied(context, code);
      } else if (kDebugMode) {
        debugPrint('📍 Module not found in nav: $code');
      }
    }

    if (openOvertime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openOvertimeScreen();
      });
    }
  }

  void _onGoBackRequested() {
    _goBack();
  }

  int? _navIndexForModule(String moduleCode) {
    for (var i = 0; i < _navItems.length; i++) {
      if (_navItems[i].moduleCode == moduleCode) return i;
    }
    return null;
  }

  bool _isNavItemVisible(int index) {
    if (index < 0 || index >= _navItems.length) return false;
    final item = _navItems[index];
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final userRole = authUser?.role ?? '';
    final normalizedRole = userRole.toLowerCase();
    final isSuperAdmin = normalizedRole == 'superadmin';
    final isAgent = normalizedRole == 'agent';
    final bypassPackage =
        StoreRoleHelper.bypassesPackageFilter(userRole);
    final allowedModules = authUser?.allowedModules;
    final perm = Provider.of<PermissionProvider>(context, listen: false);

    if (item.adminOnly && !isSuperAdmin) return false;
    if (item.requiredRole != null && item.requiredRole != userRole) {
      return false;
    }
    if (isAgent && item.requiredRole != 'Agent') return false;
    if (!PermissionNavigation.isAllowedByPackageOrRole(
      item.moduleCode,
      allowedModules: allowedModules,
      perm: perm,
      bypassPackageFilter: bypassPackage,
    )) {
      return false;
    }
    return PermissionNavigation.canNavigate(perm, item.moduleCode);
  }

  List<int> _visibleNavIndices() {
    return [
      for (var i = 0; i < _navItems.length; i++)
        if (_isNavItemVisible(i)) i,
    ];
  }

  List<({IconData icon, IconData activeIcon, String moduleCode})>
      _visibleMobileBottomNavDefs() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final allowedModules = authUser?.allowedModules;
    final role = authUser?.role;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final visible = <({IconData icon, IconData activeIcon, String moduleCode})>[];
    for (final d in _mobileBottomNavCandidates) {
      if (!PermissionNavigation.canAccessModule(
        d.moduleCode,
        allowedModules: allowedModules,
        perm: perm,
        role: role,
      )) {
        continue;
      }
      visible.add(d);
      if (visible.length >= 4) break;
    }
    if (visible.isEmpty) {
      visible.add(_mobileBottomNavCandidates.first);
    }
    return visible;
  }

  bool _tryNavigateToIndex(int index) {
    if (index < 0 || index >= _navItems.length) return false;
    final moduleCode = _navItems[index].moduleCode;
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final allowedModules = authUser?.allowedModules;
    final bypassPackage =
        StoreRoleHelper.bypassesPackageFilter(authUser?.role);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!PermissionNavigation.isAllowedByPackageOrRole(
      moduleCode,
      allowedModules: allowedModules,
      perm: perm,
      bypassPackageFilter: bypassPackage,
    )) {
      if (moduleCode != null && moduleCode.isNotEmpty) {
        PermissionNavigation.showDenied(context, moduleCode);
      }
      return false;
    }
    if (!PermissionNavigation.canNavigate(perm, moduleCode)) {
      if (moduleCode != null && moduleCode.isNotEmpty) {
        PermissionNavigation.showDenied(context, moduleCode);
      }
      return false;
    }
    _navigateToIndex(index);
    return true;
  }

  void _navigateToModule(String moduleCode) {
    final idx = _navIndexForModule(moduleCode);
    if (idx != null) _tryNavigateToIndex(idx);
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
    unawaited(_persistLastNavIndex(index));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportCurrentScreen();
    });
  }

  void _goBack() {
    // If SettingsHub has an active sub-screen, go back to hub menu first
    if (SettingsHubScreen.internalBackCallback != null) {
      SettingsHubScreen.internalBackCallback!();
      return;
    }
    if (TaskManagementScreen.internalBackCallback != null) {
      TaskManagementScreen.internalBackCallback!();
      return;
    }
    if (_navigationHistory.isNotEmpty && mounted) {
      setState(() {
        _selectedIndex = _navigationHistory.removeLast();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reportCurrentScreen();
      });
    }
  }

  bool get _canGoBack =>
      _navigationHistory.isNotEmpty ||
      SettingsHubScreen.internalBackCallback != null ||
      TaskManagementScreen.internalBackCallback != null;

  String _settingsHubTitle(AppLocalizations l) {
    if (_selectedIndex == NavigationNotifier.settingsHub) {
      final sub = SettingsHubScreen.activeSubPageTitle;
      if (sub != null && sub.isNotEmpty) return sub;
    }
    return _navItems[_selectedIndex].localizedLabel(l);
  }

  void _onMobileNavPrefsChanged() {
    // Slot set may change — drop stale bottom-tab widgets so indices remount cleanly.
    _mobileBottomScreenCache.clear();
    _lastMobileBottomStackIdx = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MobileBottomNavPrefs.revision.removeListener(_onMobileNavPrefsChanged);
    MobileQuickActionsPrefs.revision.removeListener(_onMobileNavPrefsChanged);
    NavigationNotifier.mainLayoutReady.value = false;
    NavigationNotifier.mobileDrawerModuleActive.value = false;
    WidgetsBinding.instance.removeObserver(this);
    _notificationSubscription?.cancel();
    _attendanceSubscription?.cancel();
    _deviceStatusSubscription?.cancel();
    _communicationSubscription?.cancel();
    _currentPopupEntry?.remove();
    _currentPopupEntry = null;
    NavigationNotifier.navigateTo.removeListener(_onNavigationRequested);
    NavigationNotifier.navigateToModule.removeListener(_onModuleNavigationRequested);
    NavigationNotifier.goBackNotifier.removeListener(_onGoBackRequested);
    ScreenRefreshNotifier.notifications.removeListener(_loadNotificationCount);
    _notifCountDebounce?.cancel();
    _unreadNotificationsCount.dispose();
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
    if (_isConnectingSignalR) return; // Prevent concurrent calls
    _isConnectingSignalR = true;
    try {
      // Cancel existing subscriptions to avoid duplicates on reconnect
      await _notificationSubscription?.cancel();
      await _attendanceSubscription?.cancel();
      await _deviceStatusSubscription?.cancel();
      await _communicationSubscription?.cancel();

      if (!mounted) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      // Get a valid (non-expired) token, refreshing if necessary
      final token = await authProvider.getValidToken();
      // Pass token factory for auto-refresh on reconnection
      await _signalRService.connect(
          null, token, () => authProvider.getValidToken());
      _signalRConnectedAt = DateTime.now();

      if (!mounted) return;
      // Join store group for store-scoped notifications
      final storeId = authProvider.user?.storeId;
      if (storeId != null && storeId.isNotEmpty) {
        await _signalRService.joinStoreGroup(storeId);
        await PosPrintOrchestrator.instance.ensureListening();
        // Gắn tên tài khoản vào heartbeat Agent (máy khác thấy ai đang giữ).
        final agentSettings = await PosPrintAgentSettings.load();
        if (agentSettings.enabled) {
          final u = authProvider.user;
          final label = [
            if ((u?.fullName ?? '').trim().isNotEmpty) u!.fullName.trim(),
            if ((u?.email ?? '').trim().isNotEmpty) u!.email.trim(),
          ].join(' · ');
          if (label.isNotEmpty && agentSettings.accountLabel != label) {
            await agentSettings.copyWith(accountLabel: label).save();
          }
        }
        await PosPrintAgentService.instance.ensureRunning(storeId);
        unawaited(PosQrOrderVoiceAlert.instance.start());
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
      _communicationSubscription = _signalRService.onCommunicationEvent
          .listen(_handleCommunicationEvent);
    } catch (e) {
      debugPrint('Error connecting SignalR in MainLayout: $e');
    } finally {
      _isConnectingSignalR = false;
    }
  }

  /// Handle device status change - show popup when device connects/disconnects
  void _handleDeviceStatusChanged(DeviceStatusNotification notification) {
    if (!mounted) return;

    debugPrint(
        '📡 Device status changed: ${notification.deviceName} - ${notification.status}');

    // Kiểm tra nhóm thông báo chấm công (category device)
    _shouldShowNotification(
      categoryCode: 'device',
      relatedEntityType: 'Device',
    ).then((enabled) {
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
            SettingsHubScreen.pendingSubIndex.value = 12;
            _tryNavigateToIndex(NavigationNotifier.settingsHub);
          },
        ));
  }

  /// Toast góc trên + panel tiến trình đồng bộ máy góc dưới phải.
  Widget _wrapAppShell(Widget child) {
    return NotificationOverlay(
      child: DeviceSyncProgressOverlay(child: child),
    );
  }

  /// Handle new attendance from ADMS device - show popup globally
  void _handleNewAttendance(Attendance attendance) {
    if (!mounted) return;

    if (DeviceSyncProgressManager.shouldSuppressAttendancePopup(
        attendance.attendanceTime)) {
      ScreenRefreshNotifier.scheduleAttendanceDataRefresh();
      ScreenRefreshNotifier.scheduleNotificationCountRefresh();
      return;
    }

    // Kiểm tra thiết lập category attendance
    _shouldShowNotification(
      categoryCode: 'attendance',
      relatedEntityType: 'Attendance',
    ).then((enabled) {
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

    // Auto-refresh attendance screen (debounced — tránh refresh storm khi nhiều máy chấm)
    ScreenRefreshNotifier.scheduleAttendanceDataRefresh();
    ScreenRefreshNotifier.scheduleNotificationCountRefresh();
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
            _tryNavigateToIndex(NavigationNotifier.attendance);
          },
        ));
  }

  /// Returns true when this notification was almost certainly already displayed
  /// by FCM as a system notification while the app was backgrounded.
  ///
  /// Scenario: app goes to background → FCM auto-shows system notification
  /// → SignalR socket buffers the same event → app resumes → Dart processes
  /// the buffer → would show a duplicate via [_systemNotification.showGeneral].
  ///
  /// We suppress if BOTH conditions hold:
  ///   1. The notification's createdAt falls after the last background time
  ///      (i.e. it arrived while the app was paused).
  ///   2. We are still within 15 seconds of the app coming back to foreground
  ///      (the backlog is processed immediately on resume; after 15 s any new
  ///      notification is genuinely live and must not be suppressed).
  bool _isFcmDuplicate(String? createdAtStr) {
    if (createdAtStr == null ||
        _lastBackgroundedAt == null ||
        _lastForegroundedAt == null) {
      return false;
    }
    final notifTs = DateTime.tryParse(createdAtStr)?.toLocal();
    if (notifTs == null) return false;
    // Allow 3-second slack for server/device clock skew.
    final backgroundedAt =
        _lastBackgroundedAt!.subtract(const Duration(seconds: 3));
    final suppressUntil = _lastForegroundedAt!.add(const Duration(seconds: 15));
    return notifTs.isAfter(backgroundedAt) &&
        DateTime.now().isBefore(suppressUntil);
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final display = resolveNotificationDisplay(data);
      final title = display.title;
      final message = display.body;
      final typeValue = data['type'] ?? 0;
      final type = _parseNotificationType(typeValue);
      final relatedEntityType = data['relatedEntityType'] as String?;
      final entityTypeLower = relatedEntityType?.toLowerCase();
      final notificationId = data['id']?.toString();

      // Cập nhật số thông báo chưa đọc từ server (chính xác hơn local increment)
      _loadNotificationCount();

      // Kiểm tra thiết lập trước khi hiển thị popup
      _shouldShowNotification(
        relatedEntityType: relatedEntityType,
        categoryCode: data['categoryCode']?.toString(),
      ).then((shouldShow) {
        if (!shouldShow || !mounted) return;

        final isMobile = mounted && MediaQuery.of(context).size.width < 600;
        final isAttendanceOrDevice = entityTypeLower == 'attendance' ||
            entityTypeLower == 'device' ||
            entityTypeLower == 'devicestatus' ||
            entityTypeLower == 'newattendance' ||
            entityTypeLower == 'mobileattendance' ||
            entityTypeLower == 'authorizedmobiledevice' ||
            entityTypeLower == 'devicechangerequest';

        if (isAttendanceOrDevice &&
            DeviceSyncProgressManager.shouldSuppressAttendanceNotifications) {
          return;
        }

        if (entityTypeLower == 'authorizedmobiledevice' ||
            entityTypeLower == 'devicechangerequest') {
          ScreenRefreshNotifier.refreshMobileAttendanceSettings();
          ScreenRefreshNotifier.refreshMobileDeviceRegistration();
        }

        if (isMobile) {
          // Guard 1 (reconnect): nếu SignalR vừa kết nối lại (<15s) và notification
          // được tạo TRƯỚC khi kết nối → FCM đã show rồi khi app ở background, bỏ qua.
          final createdAtStr = data['createdAt'] as String?;
          if (createdAtStr != null && _signalRConnectedAt != null) {
            final notifTs = DateTime.tryParse(createdAtStr)?.toLocal();
            final connectedSince =
                DateTime.now().difference(_signalRConnectedAt!);
            if (notifTs != null &&
                connectedSince < const Duration(seconds: 15) &&
                notifTs.isBefore(
                    _signalRConnectedAt!.add(const Duration(seconds: 1)))) {
              return; // Already shown by FCM (reconnect replay)
            }
          }
          // Guard 2 (background buffer): SignalR có thể buffer events khi app ở
          // background và deliver lại khi resume — FCM đã show chúng rồi.
          if (_isFcmDuplicate(data['createdAt'] as String?)) {
            debugPrint('🔔 Suppressed background duplicate: $title');
            return;
          }
          _systemNotification.showGeneral(
            title: title,
            message: message,
            categoryLabel: display.categoryLabel,
            relatedEntityType: relatedEntityType,
            notificationId: notificationId,
            relatedEntityId: data['relatedEntityId']?.toString(),
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
              navigateFromNotification(
                relatedEntityType: relatedEntityType,
                relatedEntityId: data['relatedEntityId']?.toString() ??
                    notificationId,
                title: title,
                categoryCode: data['categoryCode']?.toString(),
                actionUrl: data['actionUrl']?.toString() ??
                    data['relatedUrl']?.toString(),
              );
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
    if (typeValue is int &&
        typeValue >= 0 &&
        typeValue < NotificationType.values.length) {
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

    final title = data['title'] as String? ?? 'Tin nhắn mới';
    final message =
        data['message'] as String? ?? data['content'] as String? ?? '';

    // Cập nhật badge
    _loadNotificationCount();

    // Kiểm tra thiết lập category truyền thông nội bộ
    _shouldShowNotification(
      categoryCode: 'internal_comm',
      relatedEntityType: 'Communication',
    ).then((enabled) {
      if (!enabled || !mounted) return;

      final isMobile = mounted && MediaQuery.of(context).size.width < 600;
      if (isMobile) {
        // Suppress if FCM already showed this notification while app was backgrounded.
        final createdAtStr =
            data['createdAt'] as String? ?? data['timestamp'] as String?;
        if (_isFcmDuplicate(createdAtStr)) {
          debugPrint(
              '🔔 Suppressed background duplicate (communication): $title');
          return;
        }
        _systemNotification.showGeneral(
          title: title,
          message: message,
          relatedEntityType: 'Communication',
          notificationId: data['notificationId']?.toString() ??
              data['id']?.toString(),
          relatedEntityId: data['relatedEntityId']?.toString() ??
              data['communicationId']?.toString(),
        );
      } else {
        final commId = data['relatedEntityId']?.toString() ??
            data['communicationId']?.toString();
        final notifRowId =
            data['notificationId']?.toString() ?? data['id']?.toString();
        _notificationManager.show(
          title: title,
          message: message,
          type: NotificationType.info,
          relatedEntityType: 'Communication',
          duration: const Duration(seconds: 3),
          onTap: () {
            if (notifRowId != null) {
              _apiService.markNotificationAsRead(notifRowId).then((_) {
                _loadNotificationCount();
              });
            }
            navigateFromNotification(
              relatedEntityType: 'Communication',
              relatedEntityId: commId,
              title: title,
              categoryCode: 'internal_comm',
            );
          },
        );
      }
    });
  }

  /// Kiểm tra user có bật nhận loại thông báo này (server preferences + nhóm local).
  Future<bool> _shouldShowNotification({
    String? relatedEntityType,
    String? categoryCode,
  }) async {
    await NotificationPreferencesCache.instance.ensureLoaded(_apiService);
    return NotificationPreferencesCache.instance.isCategoryEnabled(
      categoryCode: categoryCode,
      relatedEntityType: relatedEntityType,
    );
  }

  Future<void> _loadNotificationCount() async {
    _notifCountDebounce?.cancel();
    _notifCountDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_fetchNotificationCount());
    });
  }

  Future<void> _fetchNotificationCount() async {
    try {
      final summary = await _apiService.getNotificationSummary();
      if (!mounted) return;
      final n = summary['unreadCount'];
      _unreadNotificationsCount.value =
          n is int ? n : int.tryParse('$n') ?? 0;
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

  final List<NavItem> _navItems = [
    // ══════════ TỔNG QUAN ══════════
    NavItem(
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      label: 'Trang chủ',
      screen: const SizedBox(), // Will be replaced by _HomeMenuScreen
      group: 'Tổng quan',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Home',
    ),
    NavItem(
      icon: Icons.notifications_outlined,
      activeIcon: Icons.notifications,
      label: 'Thông báo',
      screen: const NotificationsScreen(),
      group: 'Tổng quan',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Notification',
    ),

    // ══════════ HỒ SƠ NHÂN SỰ ══════════
    NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Tổng quan',
      subtitle: 'Tổng quan',
      screen: const DashboardScreen(),
      group: 'Tổng quan',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Dashboard',
    ),
    NavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Hồ sơ nhân sự',
      subtitle: 'Hồ sơ NV',
      screen: const EmployeesScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Employee',
    ),
    NavItem(
      icon: Icons.badge_outlined,
      activeIcon: Icons.badge,
      label: 'Nhân sự chấm công',
      subtitle: 'User máy CC',
      screen: const DeviceUsersScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'DeviceUser',
    ),
    NavItem(
      icon: Icons.business_outlined,
      activeIcon: Icons.business,
      label: 'Phòng ban',
      subtitle: 'Phòng ban',
      screen: const DepartmentScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Department',
    ),
    NavItem(
      icon: Icons.event_busy_outlined,
      activeIcon: Icons.event_busy,
      label: 'Nghỉ phép',
      subtitle: 'Đơn nghỉ',
      screen: const LeaveScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Leave',
    ),
    NavItem(
      icon: Icons.price_change_outlined,
      activeIcon: Icons.price_change,
      label: 'Thiết lập lương',
      subtitle: 'Cấu hình lương',
      screen: const SalarySettingsScreen(),
      group: 'Hồ sơ nhân sự',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'SalarySettings',
    ),

    // ══════════ CHẤM CÔNG ══════════
    NavItem(
      icon: Icons.access_time_outlined,
      activeIcon: Icons.access_time_filled,
      label: 'Chấm công thô',
      subtitle: 'Log máy CC',
      screen: const AttendanceScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Attendance',
    ),
    NavItem(
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month,
      label: 'Lịch làm việc',
      subtitle: 'Phân ca',
      screen: const WorkScheduleScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'WorkSchedule',
    ),
    NavItem(
      icon: Icons.summarize_outlined,
      activeIcon: Icons.summarize,
      label: 'Tổng hợp chấm công',
      subtitle: 'Tổng hợp công',
      screen: const AttendanceSummaryScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'AttendanceSummary',
    ),
    NavItem(
      icon: Icons.schedule_outlined,
      activeIcon: Icons.schedule,
      label: 'Tổng hợp chấm công theo ca',
      subtitle: 'Công theo ca',
      screen: const AttendanceByShiftScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'AttendanceByShift',
    ),
    NavItem(
      icon: Icons.timer_off_outlined,
      activeIcon: Icons.timer_off,
      label: 'Đi trễ / Về sớm',
      subtitle: 'Trễ / sớm',
      screen: const LateEarlyReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'LateEarlyReport',
    ),
    NavItem(
      icon: Icons.directions_car_outlined,
      activeIcon: Icons.directions_car,
      label: 'Báo cáo đi đường',
      subtitle: 'Giờ đi đường',
      screen: const TravelHoursReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'TravelHoursReport',
    ),
    NavItem(
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      label: 'Duyệt chấm công',
      subtitle: 'Duyệt CC',
      screen: const AttendanceApprovalScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'AttendanceApproval',
    ),
    NavItem(
      icon: Icons.assignment_turned_in_outlined,
      activeIcon: Icons.assignment_turned_in,
      label: 'Duyệt lịch làm việc',
      subtitle: 'Duyệt lịch',
      screen: const ScheduleApprovalScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'ScheduleApproval',
    ),
    NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Phiếu lương',
      subtitle: 'Phiếu lương',
      screen: const PayslipScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Payslip',
    ),
    NavItem(
      icon: Icons.payments_outlined,
      activeIcon: Icons.payments,
      label: 'Tổng hợp lương',
      subtitle: 'Bảng lương',
      screen: const PayrollScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Payroll',
    ),

    NavItem(
      icon: Icons.app_registration_outlined,
      activeIcon: Icons.app_registration,
      label: 'Đăng ký chấm công Mobile',
      subtitle: 'Đăng ký TB',
      screen: const MobileDeviceRegistrationScreen(),
      group: 'Chấm công',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'MobileDeviceRegistration',
    ),
    NavItem(
      icon: Icons.phone_android_outlined,
      activeIcon: Icons.phone_android,
      label: 'Chấm công Mobile',
      subtitle: 'Chấm trên ĐT',
      screen: const MobileAttendanceScreen(),
      group: 'Chấm công',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'MobileAttendance',
    ),
    NavItem(
      icon: Icons.restaurant_outlined,
      activeIcon: Icons.restaurant,
      label: 'Chấm cơm',
      subtitle: 'Suất ăn',
      screen: const MealTrackingScreen(),
      group: 'Quản lý Vận hành',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Meal',
    ),

    // ══════════ TÀI CHÍNH ══════════
    NavItem(
      icon: Icons.card_giftcard_outlined,
      activeIcon: Icons.card_giftcard,
      label: 'Phiếu thưởng',
      subtitle: 'Thưởng',
      screen: const BonusPenaltyScreen(bonusOnly: true),
      group: 'Tài chính',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'BonusPenalty',
    ),
    NavItem(
      icon: Icons.money_outlined,
      activeIcon: Icons.money,
      label: 'Ứng lương',
      subtitle: 'Ứng lương',
      screen: const AdvanceRequestsScreen(),
      group: 'Tài chính',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'AdvanceRequests',
    ),
    NavItem(
      icon: Icons.flight_takeoff_outlined,
      activeIcon: Icons.flight_takeoff,
      label: 'Công tác phí',
      subtitle: 'Công tác phí',
      screen: const BusinessTripExpenseScreen(),
      group: 'Tài chính',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'BusinessTripExpense',
    ),
    NavItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Thu chi',
      subtitle: 'Thu chi',
      screen: const CashTransactionScreen(),
      group: 'Tài chính',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'CashTransaction',
    ),

    // ══════════ QUẢN LÝ VẬN HÀNH ══════════
    NavItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      label: 'Tài sản',
      subtitle: 'Tài sản',
      screen: const AssetManagementScreen(),
      group: 'Quản lý Vận hành',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Asset',
    ),
    NavItem(
      icon: Icons.task_alt_outlined,
      activeIcon: Icons.task_alt,
      label: 'Công việc',
      subtitle: 'Công việc',
      screen: const TaskManagementScreen(),
      group: 'Quản lý Vận hành',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Task',
    ),
    NavItem(
      icon: Icons.campaign_outlined,
      activeIcon: Icons.campaign,
      label: 'Truyền thông',
      subtitle: 'Thông báo',
      screen: const CommunicationScreen(),
      group: 'Quản lý Vận hành',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Communication',
    ),

    // ══════════ KPI ══════════
    NavItem(
      icon: Icons.trending_up_outlined,
      activeIcon: Icons.trending_up,
      label: 'KPI',
      subtitle: 'KPI',
      screen: const KpiScreen(),
      group: 'Quản lý Vận hành',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'KPI',
    ),

    // ══════════ SẢN LƯỢNG ══════════
    NavItem(
      icon: Icons.precision_manufacturing_outlined,
      activeIcon: Icons.precision_manufacturing,
      label: 'Sản lượng',
      subtitle: 'Sản lượng',
      screen: const ProductionOutputScreen(),
      group: 'Quản lý Vận hành',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Production',
    ),

    // ══════════ PHẢN ÁNH / Ý KIẾN ══════════
    NavItem(
      icon: Icons.feedback_outlined,
      activeIcon: Icons.feedback,
      label: 'Phản ánh / Ý kiến',
      subtitle: 'Góp ý',
      screen: const FeedbackScreen(),
      group: 'Quản lý Vận hành',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Feedback',
    ),

    // ══════════ CHECK-IN ĐIỂM BÁN ══════════
    NavItem(
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
      label: 'Bản đồ nhân sự',
      subtitle: 'Vị trí NV',
      screen: const FieldCheckInScreen(),
      group: 'Quản lý Vận hành',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'FieldCheckIn',
    ),

    // ══════════ POS / BÁN HÀNG ══════════
    NavItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      label: 'Hàng hóa',
      subtitle: 'SP, tồn, giá',
      screen: const PosProductsScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosProducts',
    ),
    NavItem(
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale,
      label: 'Bán hàng',
      subtitle: 'Thu ngân',
      screen: const PosSellScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosSell',
    ),
    NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Đơn hàng',
      subtitle: 'Hóa đơn',
      screen: const PosSaleOrderListScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosSaleOrders',
    ),
    NavItem(
      icon: Icons.assignment_return_outlined,
      activeIcon: Icons.assignment_return,
      label: 'Trả hàng bán',
      subtitle: 'Trả hàng',
      screen: const PosSaleReturnListScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosSaleReturns',
    ),
    NavItem(
      icon: Icons.event_available_outlined,
      activeIcon: Icons.event_available,
      label: 'Đặt bàn / lịch hẹn',
      subtitle: 'Đặt bàn',
      screen: const PosAppointmentDayScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosBooking',
    ),
    NavItem(
      icon: Icons.people_outline,
      activeIcon: Icons.people,
      label: 'Khách hàng POS',
      subtitle: 'Khách hàng',
      screen: const PosCustomersScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosCustomers',
    ),
    NavItem(
      icon: Icons.verified_outlined,
      activeIcon: Icons.verified,
      label: 'Bảo hành POS',
      subtitle: 'Bảo hành',
      screen: const PosWarrantyLookupScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosWarranty',
    ),
    NavItem(
      icon: Icons.local_shipping_outlined,
      activeIcon: Icons.local_shipping,
      label: 'Nhà cung cấp',
      subtitle: 'NCC',
      screen: const PosSupplierListScreen(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosPurchaseReceipts',
    ),
    NavItem(
      icon: Icons.shopping_cart_outlined,
      activeIcon: Icons.shopping_cart,
      label: 'Nhập hàng NCC',
      subtitle: 'Nhập hàng',
      screen: const WhAdaptivePurchaseReceiptList(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosPurchaseReceipts',
    ),
    NavItem(
      icon: Icons.reply_outlined,
      activeIcon: Icons.reply,
      label: 'Trả hàng nhập',
      subtitle: 'Trả NCC',
      screen: const WhAdaptivePurchaseReturnList(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosPurchaseReturns',
    ),
    NavItem(
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      label: 'Kiểm kho',
      subtitle: 'Kiểm kê',
      screen: const WhAdaptiveStockCountList(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosStockCounts',
    ),
    NavItem(
      icon: Icons.delete_forever_outlined,
      activeIcon: Icons.delete_forever,
      label: 'Xuất hủy',
      subtitle: 'Xuất hủy',
      screen: const WhAdaptiveDamageIssueList(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosDamageIssues',
    ),
    NavItem(
      icon: Icons.outbox_outlined,
      activeIcon: Icons.outbox,
      label: 'Xuất dùng nội bộ',
      subtitle: 'Xuất nội bộ',
      screen: const WhAdaptiveInternalUseList(),
      group: 'POS',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosInternalUseIssues',
    ),
    // ══════════ BÁO CÁO ══════════
    NavItem(
      icon: Icons.analytics_outlined,
      activeIcon: Icons.analytics,
      label: 'Báo cáo POS',
      subtitle: '14 báo cáo',
      screen: const PosReportsHubScreen(),
      group: 'Báo cáo',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosSalesReport',
    ),
    NavItem(
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book,
      label: 'Thuế hộ kinh doanh',
      subtitle: 'Dưới 1 tỷ / 1–3 tỷ / trên 3 tỷ',
      screen: const HkdBooksScreen(),
      group: 'Báo cáo',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'HkdBooks',
    ),
    NavItem(
      icon: Icons.history,
      activeIcon: Icons.history,
      label: 'Báo cáo hủy / trả',
      subtitle: 'Hủy / trả',
      screen: const PosCancelReturnHistoryScreen(),
      group: 'Báo cáo',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosSaleReturns',
    ),
    NavItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Công nợ khách hàng',
      subtitle: 'Công nợ',
      screen: const PosCustomerDebtReportScreen(),
      group: 'Báo cáo',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PosSalesReport',
    ),
    NavItem(
      icon: Icons.fact_check_outlined,
      activeIcon: Icons.fact_check,
      label: 'Báo cáo chấm công',
      subtitle: 'Vắng / trễ',
      screen: const AttendanceReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'AttendanceReport',
    ),
    NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Báo cáo phạt',
      subtitle: 'Phiếu phạt',
      screen: const PenaltyReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PenaltyReport',
    ),
    NavItem(
      icon: Icons.account_balance_wallet_outlined,
      activeIcon: Icons.account_balance_wallet,
      label: 'Báo cáo thu chi',
      subtitle: 'Thu chi',
      screen: const CashReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'CashReport',
    ),
    NavItem(
      icon: Icons.money_outlined,
      activeIcon: Icons.money,
      label: 'Báo cáo ứng lương',
      subtitle: 'Ứng lương',
      screen: const AdvanceReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'AdvanceReport',
    ),
    NavItem(
      icon: Icons.flight_takeoff_outlined,
      activeIcon: Icons.flight_takeoff,
      label: 'Báo cáo công tác phí',
      subtitle: 'Công tác',
      screen: const BusinessTripReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'BusinessTripReport',
    ),
    NavItem(
      icon: Icons.event_busy_outlined,
      activeIcon: Icons.event_busy,
      label: 'Báo cáo nghỉ phép',
      subtitle: 'Nghỉ phép',
      screen: const LeaveReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'LeaveReport',
    ),
    NavItem(
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      label: 'Báo cáo tài sản',
      subtitle: 'Tài sản',
      screen: const AssetReportScreen(),
      group: 'Báo cáo',
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'AssetReport',
    ),
    // Không moduleCode: chỉ mục file local trên máy, không API / không phân quyền.
    NavItem(
      icon: Icons.folder_special_outlined,
      activeIcon: Icons.folder_special,
      label: 'Quản lý tài liệu tải xuống',
      subtitle: 'File máy này',
      screen: const DownloadedDocumentsScreen(),
      group: 'Báo cáo',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
    ),

    // ══════════ ĐẠI LÝ ══════════
    NavItem(
      icon: Icons.vpn_key_outlined,
      activeIcon: Icons.vpn_key,
      label: 'License Keys',
      subtitle: 'Key đại lý',
      screen: const AgentLicenseKeysScreen(),
      group: 'Đại lý',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      requiredRole: 'Agent',
    ),

    // ══════════ CÀI ĐẶT ══════════
    NavItem(
      icon: Icons.tune_outlined,
      activeIcon: Icons.tune,
      label: 'Thiết lập HRM',
      subtitle: 'Thiết lập HRM',
      screen: const SettingsHubScreen(),
      group: 'Cài đặt',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'SettingsHub',
    ),
    NavItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings,
      label: 'Cài đặt',
      subtitle: 'Giao diện',
      screen: const SettingsScreen(),
      group: 'Cài đặt',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'Settings',
    ),
    NavItem(
      icon: Icons.admin_panel_settings_outlined,
      activeIcon: Icons.admin_panel_settings,
      label: 'Quản trị hệ thống',
      subtitle: 'Server',
      screen: const SystemAdminScreen(),
      group: 'Cài đặt',
      showInSidebar: true,
      themeColor: HrmPageChrome.primaryNavy,
      adminOnly: true,
      moduleCode: 'SystemAdmin',
    ),
    // ══════════ TÀI CHÍNH (phiếu phạt tự động) ══════════
    NavItem(
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      label: 'Phiếu phạt',
      subtitle: 'Phạt tự động',
      screen: const PenaltyTicketsScreen(),
      group: 'Tài chính',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'PenaltyTickets',
    ),
    // Thiết lập thông báo → vào qua Thiết lập HRM (phân quyền module NotificationSettings).
    NavItem(
      icon: Icons.notifications_active_outlined,
      activeIcon: Icons.notifications_active,
      label: 'Thiết lập thông báo',
      subtitle: 'Thông báo',
      screen: const NotificationSettingsScreen(),
      group: 'Cài đặt',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'NotificationSettings',
    ),
    NavItem(
      icon: Icons.swap_horiz_outlined,
      activeIcon: Icons.swap_horiz,
      label: 'Đổi ca làm việc',
      subtitle: 'Đổi ca',
      screen: const ShiftSwapScreen(),
      group: 'Chấm công',
      showInSidebar: false,
      themeColor: HrmPageChrome.primaryNavy,
      moduleCode: 'ShiftSwap',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Rebuild khi allowedModules được tải sau đăng nhập / khôi phục phiên.
    context.watch<AuthProvider>();

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

  List<String>? _homeAllowedModules() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    if (StoreRoleHelper.bypassesPackageFilter(authUser?.role)) {
      return null;
    }
    return authUser?.allowedModules;
  }

  bool _homeBypassPackageFilter() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    return StoreRoleHelper.bypassesPackageFilter(authUser?.role);
  }

  Widget _getHomeScreen() {
    final allowed = _homeAllowedModules();
    final bypass = _homeBypassPackageFilter();
    if (_homeScreenCache != null &&
        _homeAllowedModulesCached == allowed &&
        _homeBypassPackageFilterCached == bypass) {
      return _homeScreenCache!;
    }
    _homeAllowedModulesCached = allowed;
    _homeBypassPackageFilterCached = bypass;
    _homeScreenCache = _HomeMenuScreen(
      key: const ValueKey('main_home_menu'),
      navItems: _navItems,
      onItemTap: _tryNavigateToIndex,
      allowedModules: allowed,
      bypassPackageFilter: bypass,
    );
    return _homeScreenCache!;
  }

  Widget _getScreenForIndex(int index) {
    if (index == 0) return _getHomeScreen();
    return ModuleRouteGuard(
      moduleCode: _navItems[index].moduleCode,
      child: _navItems[index].screen,
    );
  }

  /// Desktop/tablet: keep home mounted (Offstage) so returning from a module restores scroll.
  Widget _buildPersistentMainContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _selectedIndex != 0,
          child: _getHomeScreen(),
        ),
        if (_selectedIndex != 0) _getScreenForIndex(_selectedIndex),
      ],
    );
  }

  // Desktop Layout với Navigation Rail mở rộng
  Widget _buildDesktopLayout() {
    final moduleCode = _navItems[_selectedIndex].moduleCode;
    final posFullscreen = moduleCode == 'PosSell';

    if (posFullscreen) {
      // POS desktop fullscreen — ẩn sidebar + top bar HRM.
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
            return;
          }
          final handler = NavigationNotifier.posHandleSystemBack;
          if (handler != null && await handler()) return;
          _tryNavigateToIndex(0);
        },
        child: _wrapAppShell(
          Scaffold(
            body: _buildPersistentMainContent(),
          ),
        ),
      );
    }

    return _wrapAppShell(
      Scaffold(
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
                  const AnnouncementBanner(),
                  Expanded(
                    child: _buildPersistentMainContent(),
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
    final moduleCode = _navItems[_selectedIndex].moduleCode;
    if (moduleCode == 'PosSell') {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
            return;
          }
          final handler = NavigationNotifier.posHandleSystemBack;
          if (handler != null && await handler()) return;
          _tryNavigateToIndex(0);
        },
        child: _wrapAppShell(
          Scaffold(body: _buildPersistentMainContent()),
        ),
      );
    }

    return _wrapAppShell(
      Scaffold(
        body: Row(
          children: [
            SingleChildScrollView(
              child: SizedBox(
                // Chiều cao cố định — tránh IntrinsicHeight gây Stack Overflow khi
                // NavigationRail đo lại intrinsic size (Samsung tablet / Fold mở).
                height: MediaQuery.sizeOf(context).height,
                child: Builder(
                  builder: (context) {
                    final visibleIndices = _visibleNavIndices();
                    final railSelected = visibleIndices.indexOf(_selectedIndex);
                    final safeRailSelected = railSelected < 0
                        ? 0
                        : railSelected.clamp(0, visibleIndices.length - 1);
                    return NavigationRail(
                      selectedIndex: visibleIndices.isEmpty
                          ? 0
                          : safeRailSelected,
                      onDestinationSelected: (railIndex) {
                        if (railIndex >= 0 &&
                            railIndex < visibleIndices.length) {
                          _tryNavigateToIndex(visibleIndices[railIndex]);
                        }
                      },
                      labelType: NavigationRailLabelType.all,
                      destinations: visibleIndices
                          .map((i) => NavigationRailDestination(
                                icon: Icon(_navItems[i].icon),
                                selectedIcon: Icon(_navItems[i].activeIcon),
                                label: Text(tr(_navItems[i].localizedLabel(
                                    AppLocalizations.of(context)))),
                              ))
                          .toList(),
                    );
                  },
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(),
                  const AnnouncementBanner(),
                  Expanded(
                    child: _buildPersistentMainContent(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mobile bottom nav: ưu tiên module quan trọng, lọc theo gói dịch vụ.
  static const _mobileBottomNavCandidates = [
    (
      icon: Icons.home_outlined,
      activeIcon: Icons.home,
      moduleCode: 'Home'
    ),
    (
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      moduleCode: 'Dashboard'
    ),
    (
      icon: Icons.fingerprint_outlined,
      activeIcon: Icons.fingerprint,
      moduleCode: 'MobileAttendance'
    ),
    (
      icon: Icons.task_alt_outlined,
      activeIcon: Icons.task_alt,
      moduleCode: 'Task'
    ),
    (
      icon: Icons.point_of_sale_outlined,
      activeIcon: Icons.point_of_sale,
      moduleCode: 'PosSell'
    ),
    (
      icon: Icons.inventory_2_outlined,
      activeIcon: Icons.inventory_2,
      moduleCode: 'PosProducts'
    ),
    (
      icon: Icons.receipt_long_outlined,
      activeIcon: Icons.receipt_long,
      moduleCode: 'PosSaleOrders'
    ),
  ];

  static String _mobileNavLabel(String moduleCode, AppLocalizations l) {
    // Short labels for bottom nav to prevent overflow
    switch (moduleCode) {
      case 'Task':
        return l.tasks;
      case 'Home':
        return l.home;
      case 'Dashboard':
        return l.overview;
      case 'MobileAttendance':
        return 'Chấm công';
      case 'PosSell':
        return l.posSell;
      case 'PosProducts':
        return l.posProducts;
      case 'PosSaleOrders':
        return l.posSaleOrders;
      case 'Employee':
        return l.employeeRecords;
      case 'Payroll':
        return l.payrollSummary;
      case 'Leave':
        return l.leave;
      case 'Communication':
        return l.communication;
      case 'PosSalesReport':
        return l.posSalesReport;
      case 'HkdBooks':
        return 'Thuế hộ kinh doanh';
      case 'SettingsHub':
        return l.settings;
      case 'Notification':
        return l.notifications;
      case 'Payslip':
        return l.payrollSummary;
      default:
        return moduleCode;
    }
  }

  // Scaffold key for programmatic drawer open from bottom nav "Thêm"
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

  int _bottomNavSlotIndexForModule(String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return -1;
    final layout = _resolvedMainNavLayout();
    for (var i = 0; i < layout.slots.length; i++) {
      final slotId = layout.slots[i];
      if (slotId == MobileBottomNavCatalog.drawerId) continue;
      final def = _mainNavDef(slotId);
      if (def?.moduleCode == moduleCode && _canAccessMainSlot(slotId)) {
        return i;
      }
    }
    return -1;
  }

  // Mobile Layout với Bottom Navigation
  Widget _buildMobileLayout() {
    final l = AppLocalizations.of(context);
    final moduleCode = _navItems[_selectedIndex].moduleCode;
    final posHubFullscreen =
        Responsive.isMobile(context) && PosHubModules.isPrimary(moduleCode);

    final bottomNavIndex = _bottomNavSlotIndexForModule(moduleCode);
    final isBottomNav = bottomNavIndex >= 0;
    NavigationNotifier.mobileDrawerModuleActive.value =
        !posHubFullscreen && !isBottomNav;
    final safeBottomIndex = isBottomNav ? bottomNavIndex : -1;

    final scaffold = Scaffold(
      key: _mobileScaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 44,
        leading: _canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back, size: 22),
                onPressed: _goBack,
                tooltip: tr(l.goBack),
                visualDensity: VisualDensity.compact,
              )
            : null,
        titleTextStyle: Theme.of(context)
            .textTheme
            .headlineLarge
            ?.copyWith(fontSize: 17),
        title: Text(
          tr(_settingsHubTitle(l)),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        // Mobile: AI + thông báo đặt thẳng trên AppBar; action trang → FAB.
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6)),
            onPressed: () => showAiAssistant(context),
            tooltip: tr('Trợ lý ảo AI'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _unreadNotificationsCount,
            builder: (context, count, _) {
              return IconButton(
                visualDensity: VisualDensity.compact,
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(tr(count > 99 ? '99+' : '$count')),
                  child: const Icon(Icons.notifications_outlined),
                ),
                onPressed: () {
                  _tryNavigateToIndex(_notificationsIndex);
                  _loadNotificationCount();
                },
                tooltip: tr(AppLocalizations.of(context).notifications),
              );
            },
          ),
          const SizedBox(width: 2),
          _buildUserMenu(),
        ],
      ),
      body: Column(
        children: [
          const AnnouncementBanner(),
          Expanded(
            child: _buildMobileBody(bottomStackOnly: posHubFullscreen),
          ),
        ],
      ),
      floatingActionButton: const PageTopActionsFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: _buildModernBottomNav(safeBottomIndex, l),
      drawer: _buildDrawer(),
    );

    // POS fullscreen: keep MainLayout shell (Home IndexedStack) mounted Offstage
    // so returning home does not remount and flicker.
    if (posHubFullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
            return;
          }
          final handler = NavigationNotifier.posHandleSystemBack;
          if (handler != null && await handler()) return;
          if (_canGoBack) {
            _goBack();
          } else {
            _tryNavigateToIndex(0);
          }
        },
        child: _wrapAppShell(
          Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: true,
                child: TickerMode(
                  enabled: false,
                  child: scaffold,
                ),
              ),
              PosMobileHubScreen(
                key: const ValueKey('pos_mobile_hub'),
                initialTab: PosHubModules.tabIndexForModule(moduleCode),
              ),
            ],
          ),
        ),
      );
    }

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
      child: _wrapAppShell(scaffold),
    );
  }

  /// Mobile body: keep bottom-nav screens (esp. Home) mounted via Offstage when
  /// opening drawer modules — mirrors desktop [_buildPersistentMainContent].
  ///
  /// [bottomStackOnly]: used under POS hub Offstage — keep Home alive without
  /// also mounting the POS module screen (hub already hosts it).
  Widget _buildMobileBody({bool bottomStackOnly = false}) {
    final layout = _resolvedMainNavLayout();
    final bottomNavIndices = <int>[];
    for (final slotId in layout.slots) {
      if (slotId == MobileBottomNavCatalog.emptyId ||
          slotId == MobileBottomNavCatalog.drawerId ||
          !_canAccessMainSlot(slotId)) {
        continue;
      }
      final def = _mainNavDef(slotId);
      if (def?.moduleCode == null) continue;
      final idx = _navIndexForModule(def!.moduleCode!);
      if (idx != null) bottomNavIndices.add(idx);
    }

    void cacheIndex(int i) {
      _mobileBottomScreenCache.putIfAbsent(
        i,
        () => _getScreenForIndex(i),
      );
    }

    // Always keep Home in the stack once bottom-nav includes it.
    if (bottomNavIndices.contains(0)) {
      cacheIndex(0);
    }

    if (bottomNavIndices.isEmpty) {
      return bottomStackOnly
          ? const SizedBox.shrink()
          : _getScreenForIndex(_selectedIndex);
    }

    final isBottomNav = bottomNavIndices.contains(_selectedIndex);
    if (isBottomNav) {
      cacheIndex(_selectedIndex);
      _lastMobileBottomStackIdx = bottomNavIndices.indexOf(_selectedIndex);
    }

    final homeStackIdx = bottomNavIndices.indexOf(0);
    final fallbackIdx = homeStackIdx >= 0 ? homeStackIdx : 0;
    final rawStackIdx = isBottomNav
        ? bottomNavIndices.indexOf(_selectedIndex)
        : (_lastMobileBottomStackIdx ?? fallbackIdx);
    final stackIdx = rawStackIdx.clamp(0, bottomNavIndices.length - 1);
    cacheIndex(bottomNavIndices[stackIdx]);

    final stack = IndexedStack(
      index: stackIdx,
      sizing: StackFit.expand,
      children: [
        for (final i in bottomNavIndices)
          KeyedSubtree(
            key: ValueKey('mobile_bottom_$i'),
            child: _mobileBottomScreenCache[i] ?? const SizedBox.shrink(),
          ),
      ],
    );

    if (bottomStackOnly || isBottomNav) return stack;

    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: true,
          child: TickerMode(
            enabled: false,
            child: stack,
          ),
        ),
        _getScreenForIndex(_selectedIndex),
      ],
    );
  }

  // Mobile bottom nav: 5 ô cố định, chức năng tùy chỉnh qua [MobileBottomNavPrefs].
  Set<String> _allowedMainNavSlotIds() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final allowedModules = authUser?.allowedModules;
    final role = authUser?.role;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final ids = <String>{MobileBottomNavCatalog.drawerId};
    for (final d in MobileBottomNavCatalog.mainItems) {
      if (d.moduleCode == null) continue;
      if (PermissionNavigation.canAccessModule(
        d.moduleCode!,
        allowedModules: allowedModules,
        perm: perm,
        role: role,
      )) {
        ids.add(d.id);
      }
    }
    return ids;
  }

  MobileBottomNavLayout _resolvedMainNavLayout() {
    return MobileBottomNavPrefs.mainLayout.normalized(
      defaultSlots: MobileBottomNavLayout.defaultMainSlots,
      allowedIds: _allowedMainNavSlotIds(),
    );
  }

  bool _canAccessMainSlot(String slotId) {
    if (slotId == MobileBottomNavCatalog.emptyId) return false;
    if (slotId == MobileBottomNavCatalog.drawerId) return true;
    return _allowedMainNavSlotIds().contains(slotId);
  }

  MobileBottomNavItemDef? _mainNavDef(String slotId) =>
      MobileBottomNavCatalog.mapFor(MobileBottomNavCatalog.mainItems)[slotId];

  Set<String> _allowedQuickActionModuleCodes() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final allowedModules = authUser?.allowedModules;
    final role = authUser?.role;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final out = <String>{};
    for (final def in MobileQuickActionsCatalog.items) {
      if (PermissionNavigation.canAccessModule(
        def.moduleCode,
        allowedModules: allowedModules,
        perm: perm,
        role: role,
      )) {
        out.add(def.moduleCode);
      }
    }
    return out;
  }

  MobileQuickActionsLayout _resolvedQuickActionsLayout() {
    return MobileQuickActionsPrefs.layout.normalized(
      allowedModules: _allowedQuickActionModuleCodes(),
    );
  }

  Widget _buildDrawerQuickActionsSection() {
    final layout = _resolvedQuickActionsLayout();
    final modules =
        layout.modules.where((c) => c.isNotEmpty).toList(growable: false);
    if (modules.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tr('TRUY CẬP NHANH'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFA1A1AA),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Tùy chỉnh truy cập nhanh'),
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  onPressed: () {
                    Navigator.pop(context);
                    MobileQuickActionsConfigSheet.show(context);
                  },
                ),
              ],
            ),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 0.92,
              children: modules.map((code) {
                final def = MobileQuickActionsCatalog.map[code];
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      final idx = _navIndexForModule(code);
                      if (idx != null && _tryNavigateToIndex(idx)) {
                        Navigator.pop(context);
                      }
                    },
                    onLongPress: () {
                      Navigator.pop(context);
                      MobileQuickActionsConfigSheet.show(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            def?.icon ?? Icons.apps_outlined,
                            color: theme.colorScheme.primary,
                            size: 24,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(def?.label ?? code),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _mobileNavLabelForSlot(String slotId, AppLocalizations l) {
    if (slotId == MobileBottomNavCatalog.drawerId) return l.more;
    final def = _mainNavDef(slotId);
    if (def == null) return 'Trống';
    return _mobileNavLabel(def.moduleCode ?? def.id, l);
  }

  Widget _buildModernBottomNav(int selectedSlotIndex, AppLocalizations l) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final unselectedColor = isDark ? Colors.white54 : Colors.grey.shade500;

    final layout = _resolvedMainNavLayout();

    return GestureDetector(
      onLongPress: () =>
          MobileBottomNavConfigSheet.show(context, initialPage: 0),
      child: Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: List.generate(MobileBottomNavLayout.slotCount, (index) {
              final slotId = layout.slots[index];
              final def = _mainNavDef(slotId);
              final enabled = _canAccessMainSlot(slotId);
              final isSelected = selectedSlotIndex == index;
              final label = _mobileNavLabelForSlot(slotId, l);
              final useCenter = index == 2 &&
                  def != null &&
                  def.centerStyle &&
                  enabled &&
                  slotId != MobileBottomNavCatalog.emptyId;

              if (slotId == MobileBottomNavCatalog.emptyId || !enabled) {
                return Expanded(child: _buildDisabledNavSlot(label: label));
              }

              if (slotId == MobileBottomNavCatalog.drawerId) {
                return Expanded(
                  child: _buildNavItem(
                    icon: isSelected
                        ? Icons.grid_view_rounded
                        : Icons.grid_view_outlined,
                    label: label,
                    isSelected: isSelected,
                    selectedColor: primaryColor,
                    unselectedColor: unselectedColor,
                    onTap: () =>
                        _mobileScaffoldKey.currentState?.openDrawer(),
                  ),
                );
              }

              if (useCenter) {
                return Expanded(
                  child: _buildCenterNavItem(
                    icon: def!.activeIcon,
                    label: label,
                    isSelected: isSelected,
                    primaryColor: primaryColor,
                    surfaceColor: surfaceColor,
                    onTap: () => _navigateToModule(def.moduleCode!),
                  ),
                );
              }

              return Expanded(
                child: _buildNavItem(
                  icon: isSelected ? def!.activeIcon : def!.icon,
                  label: label,
                  isSelected: isSelected,
                  selectedColor: primaryColor,
                  unselectedColor: unselectedColor,
                  onTap: () => _navigateToModule(def!.moduleCode!),
                ),
              );
            }),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildDisabledNavSlot({required String label}) {
    return Opacity(
      opacity: 0.35,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.remove, size: 20, color: Colors.grey),
          const SizedBox(height: 2),
          Text(
            tr(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
        ],
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
            width: 46,
            height: 46,
            margin: const EdgeInsets.only(bottom: 1),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isSelected
                    ? [primaryColor, primaryColor.withValues(alpha: 0.8)]
                    : [
                        primaryColor.withValues(alpha: 0.85),
                        primaryColor.withValues(alpha: 0.65)
                      ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      primaryColor.withValues(alpha: isSelected ? 0.35 : 0.2),
                  blurRadius: isSelected ? 12 : 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          Text(
            tr(label),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isSelected
                  ? primaryColor
                  : primaryColor.withValues(alpha: 0.7),
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
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: isSelected
            ? BoxDecoration(
                color: selectedColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? selectedColor : unselectedColor,
            ),
            const SizedBox(height: 1),
            Text(
              tr(label),
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
    const groupOrder = [
      'Tổng quan',
      'Hồ sơ nhân sự',
      'Chấm công',
      'Tài chính',
      'Quản lý Vận hành',
      'Báo cáo',
      'Đại lý',
      'Cài đặt'
    ];

    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final userRole = authUser?.role ?? '';
    final normalizedRole = userRole.toLowerCase();
    final isSuperAdmin = normalizedRole == 'superadmin';
    final isAgent = normalizedRole == 'agent';
    final bypassPackage =
        StoreRoleHelper.bypassesPackageFilter(userRole);
    final allowedModules = authUser?.allowedModules;
    final permProvider = Provider.of<PermissionProvider>(context);

    // Build grouped items preserving original indices (only sidebar items)
    final groupedItems = <String, List<MapEntry<int, NavItem>>>{};
    for (int i = 0; i < _navItems.length; i++) {
      if (!_navItems[i].showInSidebar) continue;
      if (_navItems[i].adminOnly && !isSuperAdmin) continue;
      if (_navItems[i].requiredRole != null &&
          _navItems[i].requiredRole != userRole) {
        continue;
      }
      // Agents only see items with requiredRole == 'Agent'
      if (isAgent && _navItems[i].requiredRole != 'Agent') continue;
      // Lọc theo gói dịch vụ - SuperAdmin/Agent không bị giới hạn
      if (!PermissionNavigation.isAllowedByPackageOrRole(
        _navItems[i].moduleCode,
        allowedModules: allowedModules,
        perm: permProvider,
        bypassPackageFilter: bypassPackage,
      )) {
        continue;
      }
      // Lọc theo quyền canView - ẩn module nếu không có quyền xem
      if (!permProvider.canViewNav(_navItems[i].moduleCode)) continue;
      final group = _navItems[i].group.isEmpty ? 'Khác' : _navItems[i].group;
      groupedItems.putIfAbsent(group, () => []);
      groupedItems[group]!.add(MapEntry(i, _navItems[i]));
    }

    return Container(
      color: const Color(0xFFF1F4F6), // surface-container-low
      child: Column(
        children: [
          // Header with logo — bấm để mở/ thu sidebar
          Tooltip(
            message: _isExpanded ? 'Thu gọn menu' : 'Mở rộng menu',
            child: GestureDetector(
              onTap: _toggleSidebar,
              child: Container(
                height: 64,
                padding: EdgeInsets.symmetric(horizontal: _isExpanded ? 16 : 8),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F9FA), // surface
                ),
                child: _isExpanded
                    ? Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(7),
                            child: Image.asset('assets/logo.png',
                                width: 32, height: 32),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(tr('SBOX HRM'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: HrmPageChrome.primaryNavy,
                                  letterSpacing: -0.5,
                                ),
                                overflow: TextOverflow.ellipsis),
                          ),
                          Icon(Icons.chevron_left_rounded,
                              color: const Color(0xFF586064).withValues(alpha: 0.5),
                              size: 22),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.asset('assets/logo.png',
                                width: 26, height: 26),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: const Color(0xFF586064).withValues(alpha: 0.45),
                              size: 16),
                        ],
                      ),
              ),
            ),
          ),

          // Grouped navigation items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: groupOrder
                  .where((g) => groupedItems.containsKey(g))
                  .expand((groupName) {
                final items = groupedItems[groupName]!;
                final isCollapsed = _collapsedGroups.contains(groupName);
                final groupColor = _HomeMenuScreen._groupColors[groupName] ??
                    const Color(0xFF586064);

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
                        padding: const EdgeInsets.only(
                            left: 20, right: 12, top: 16, bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr(groupName.toUpperCase()),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: groupColor.withValues(alpha: 0.6),
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                            Icon(
                              isCollapsed
                                  ? Icons.expand_more_rounded
                                  : Icons.expand_less_rounded,
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
                      final accentColor = HrmPageChrome.primaryNavy;

                      final navWidget = Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: _isExpanded ? 10 : 6, vertical: 2),
                        child: Material(
                          color: isSelected
                              ? accentColor.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: () => _tryNavigateToIndex(index),
                            borderRadius: BorderRadius.circular(10),
                            hoverColor: const Color(
                                0xFFE2E9EC), // surface-container-high
                            child: Container(
                              height: 40,
                              padding: EdgeInsets.symmetric(
                                  horizontal: _isExpanded ? 12 : 0),
                              decoration: isSelected && _isExpanded
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border(
                                        left: BorderSide(
                                            color: accentColor, width: 3),
                                      ),
                                    )
                                  : null,
                              child: Row(
                                mainAxisAlignment: _isExpanded
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
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
                                        tr(item.localizedLabel(
                                            AppLocalizations.of(context))),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isSelected
                                              ? const Color(0xFF2B3437)
                                              : const Color(0xFF586064),
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (item.highlight)
                                      Container(
                                        width: 7,
                                        height: 7,
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
                              message: item
                                  .localizedLabel(AppLocalizations.of(context)),
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
      margin:
          EdgeInsets.symmetric(horizontal: _isExpanded ? 10 : 6, vertical: 8),
      padding: EdgeInsets.all(_isExpanded ? 10 : 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA), // surface
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: _isExpanded ? 20 : 18,
            backgroundColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
            child: Text(
              tr((user?.fullName ?? 'U')[0].toUpperCase()),
              style: TextStyle(
                color: HrmPageChrome.primaryNavy,
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
                    tr(user?.fullName ?? 'User'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF2B3437),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    tr(user?.role ?? 'Employee'),
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
                  child: Icon(Icons.logout_rounded,
                      size: 18,
                      color: const Color(0xFF586064).withValues(alpha: 0.7)),
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
              icon: Icon(Icons.arrow_back,
                  color: Theme.of(context).colorScheme.onSurface),
              onPressed: _goBack,
              tooltip: tr(AppLocalizations.of(context).goBack),
            ),
          if (_canGoBack) const SizedBox(width: 4),
          Text(
            tr(_settingsHubTitle(AppLocalizations.of(context))),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ListenableBuilder(
              listenable: PageTopActions.instance,
              builder: (context, _) {
                final acts = PageTopActions.instance.actions;
                if (acts.isEmpty) return const SizedBox.shrink();
                return Align(
                  alignment: Alignment.centerRight,
                  child: PageTopActionsBar(actions: acts),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          // Search thu gọn → bấm icon mới mở field (tránh che action).
          if (_topSearchExpanded)
            SizedBox(
              width: 200,
              height: 40,
              child: TextField(
                autofocus: true,
                onTapOutside: (_) =>
                    setState(() => _topSearchExpanded = false),
                decoration: InputDecoration(
                  hintText: tr(AppLocalizations.of(context).search),
                  hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                  prefixIcon:
                      const Icon(Icons.search, color: Color(0xFFA1A1AA), size: 20),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() => _topSearchExpanded = false),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: tr(AppLocalizations.of(context).search),
              onPressed: () => setState(() => _topSearchExpanded = true),
            ),
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6)),
            onPressed: () => showAiAssistant(context),
            tooltip: tr('Trợ lý ảo AI'),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _unreadNotificationsCount,
            builder: (context, count, _) {
              return IconButton(
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text(tr(count > 99 ? '99+' : '$count')),
                  child: const Icon(Icons.notifications_outlined),
                ),
                onPressed: () {
                  _tryNavigateToIndex(_notificationsIndex);
                  _loadNotificationCount();
                },
                tooltip: tr(AppLocalizations.of(context).notifications),
              );
            },
          ),
          const SizedBox(width: 4),
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
            backgroundColor:
                Theme.of(context).primaryColor.withValues(alpha: 0.2),
            child: Text(
              tr((user?.fullName ?? 'U')[0].toUpperCase()),
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
                tr(user?.fullName ?? 'User'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                tr(user?.email ?? ''),
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
              Text(tr(AppLocalizations.of(context).personalInfo)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 20),
              const SizedBox(width: 12),
              Text(tr(AppLocalizations.of(context).settings)),
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
              Text(tr(AppLocalizations.of(context).logout),
                  style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'profile':
            _tryNavigateToIndex(NavigationNotifier.settings);
            break;
          case 'settings':
            // Mở hub thiết lập (mẫu in, máy in, cửa hàng…) — không phải màn giao diện.
            final hub = _navItems.indexWhere((n) => n.moduleCode == 'SettingsHub');
            if (hub >= 0) {
              _tryNavigateToIndex(hub);
            } else {
              _tryNavigateToIndex(NavigationNotifier.settings);
            }
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
    const groupOrder = [
      'Tổng quan',
      'Hồ sơ nhân sự',
      'Chấm công',
      'Tài chính',
      'Quản lý Vận hành',
      'Báo cáo',
      'Đại lý',
      'Cài đặt'
    ];
    final l = AppLocalizations.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final authUser = authProvider.user;
    final userRole = authUser?.role ?? '';
    final normalizedRole = userRole.toLowerCase();
    final isSuperAdmin = normalizedRole == 'superadmin';
    final isAgent = normalizedRole == 'agent';
    final bypassPackage =
        StoreRoleHelper.bypassesPackageFilter(userRole);
    final allowedModules = authUser?.allowedModules;
    final permProvider = Provider.of<PermissionProvider>(context);

    // Build grouped items - same filtering as sidebar
    final groupedItems = <String, List<MapEntry<int, NavItem>>>{};
    for (int i = 0; i < _navItems.length; i++) {
      final item = _navItems[i];
      if (item.adminOnly && !isSuperAdmin) continue;
      if (item.requiredRole != null && item.requiredRole != userRole) continue;
      if (isAgent && item.requiredRole != 'Agent') continue;
      if (!PermissionNavigation.isAllowedByPackageOrRole(
        item.moduleCode,
        allowedModules: allowedModules,
        perm: permProvider,
        bypassPackageFilter: bypassPackage,
      )) {
        continue;
      }
      // Lọc theo quyền canView
      if (!permProvider.canViewNav(item.moduleCode)) continue;
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
              border: Border(
                  bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset('assets/logo.png', width: 32, height: 32),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('SBOX HRM'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: HrmPageChrome.primaryNavy,
                        letterSpacing: -0.5,
                      ),
                      overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: const Color(0xFF586064).withValues(alpha: 0.5),
                      size: 22),
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
              children: [
                _buildDrawerQuickActionsSection(),
                ...groupOrder
                  .where((g) => groupedItems.containsKey(g))
                  .map((groupName) {
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
                        tr(groupLabel.toUpperCase()),
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
                          color: isSelected
                              ? Theme.of(context).primaryColor
                              : const Color(0xFF71717A),
                          size: 22,
                        ),
                        title: Text(
                          tr(item.localizedLabel(l)),
                          style: TextStyle(
                            color: isSelected
                                ? Theme.of(context).primaryColor
                                : null,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        selected: isSelected,
                        selectedTileColor: Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.08),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 0),
                        onTap: () {
                          if (_tryNavigateToIndex(index)) {
                            Navigator.pop(context);
                          }
                        },
                      );
                    }),
                  ],
                );
              }).toList(),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(tr(l.logout), style: const TextStyle(color: Colors.red)),
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
      builder: (context) => ScrollableAlertDialog(
        title: Text(tr(l.logout)),
        content: Text(tr(l.logoutConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(l.cancel)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<PermissionProvider>(context, listen: false).clear();
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr(l.logout)),
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
    // Luôn dùng label khai báo trên NavItem — tránh 2 chip cùng moduleCode
    // (cùng quyền) bị _labelMap ghi đè thành cùng một tên.
    return tr(label);
  }

  /// Get localized subtitle
  String? localizedSubtitle(AppLocalizations l) {
    // Ưu tiên subtitle ngắn trên NavItem; _subtitleMap chỉ khi thiếu.
    if (subtitle != null && subtitle!.trim().isNotEmpty) {
      return tr(subtitle!);
    }
    if (_subtitleMap[moduleCode] != null) {
      return _subtitleMap[moduleCode]!(l);
    }
    return null;
  }

  /// Get localized group name
  String localizedGroup(AppLocalizations l) {
    return _groupMap[group] != null ? _groupMap[group]!(l) : tr(group);
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
    'LateEarlyReport': (l) => l.lateEarlyReport,
    'TravelHoursReport': (l) => l.travelHoursReport,
    'AttendanceApproval': (l) => l.attendanceApproval,
    'ScheduleApproval': (l) => l.scheduleApproval,
    'Payroll': (l) => l.payrollSummary,
    'BonusPenalty': (l) => l.bonusPenalty,
    'AdvanceRequests': (l) => l.salaryAdvance,
    'BusinessTripExpense': (l) => l.businessTripExpense,
    'CashTransaction': (l) => l.incomeExpense,
    'PenaltyTickets': (l) => l.penaltyTickets,
    'Asset': (l) => l.assets,
    'Task': (l) => l.tasks,
    'Communication': (l) => l.communication,
    'KPI': (l) => 'KPI',
    'Feedback': (l) => l.feedback,
    'PosProducts': (l) => l.posProducts,
    'PosSell': (l) => l.posSell,
    'PosSaleOrders': (l) => l.posSaleOrders,
    'PosSaleReturns': (l) => l.posSaleReturns,
    'PosPurchaseReceipts': (l) => l.posPurchaseReceipts,
    'PosPurchaseReturns': (l) => l.posPurchaseReturns,
    'PosStockCounts': (l) => l.posStockCounts,
    'PosDamageIssues': (l) => l.posDamageIssues,
    'PosInternalUseIssues': (l) => l.posInternalUseIssues,
    'PosSalesReport': (l) => l.posSalesReport,
    'HkdBooks': (_) => 'Thuế hộ kinh doanh',
    'PenaltyReport': (l) => l.penaltyReport,
    'AttendanceReport': (l) => l.attendanceReport,
    'CashReport': (l) => l.cashReport,
    'AdvanceReport': (l) => l.advanceReport,
    'BusinessTripReport': (l) => l.businessTripReport,
    'LeaveReport': (l) => l.leaveReport,
    'AssetReport': (l) => l.assetReport,
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
    'BusinessTripExpense': (l) => l.businessTripExpenseSubtitle,
    'AssetReport': (l) => l.assetReportSubtitle,
    'Settings': (l) => l.settingsHubSubtitle,
  };

  static final Map<String, String Function(AppLocalizations)> _groupMap = {
    'Tổng quan': (l) => l.groupOverview,
    'Hồ sơ nhân sự': (l) => l.groupHrRecords,
    'Chấm công': (l) => l.groupAttendance,
    'Tài chính': (l) => l.groupFinance,
    'Quản lý Vận hành': (l) => l.groupOperations,
    'POS': (l) => l.groupPos,
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
  final bool bypassPackageFilter;

  const _HomeMenuScreen({
    super.key,
    required this.navItems,
    required this.onItemTap,
    this.allowedModules,
    this.bypassPackageFilter = false,
  });

  static const _groupOrder = [
    'Hồ sơ nhân sự',
    'Chấm công',
    'Tài chính',
    'Quản lý Vận hành',
    'POS',
    'Báo cáo',
    'Cài đặt',
  ];

  static const _groupIcons = {
    'Hồ sơ nhân sự': Icons.people,
    'Chấm công': Icons.access_time_filled,
    'Tài chính': Icons.account_balance,
    'Quản lý Vận hành': Icons.business_center,
    'POS': Icons.point_of_sale,
    'Báo cáo': Icons.assessment,
    'Cài đặt': Icons.settings,
  };

  static const _groupColors = {
    'Hồ sơ nhân sự': HrmPageChrome.primaryNavy,
    'Chấm công': HrmPageChrome.primaryNavy,
    'Tài chính': HrmPageChrome.primaryNavy,
    'Quản lý Vận hành': HrmPageChrome.primaryNavy,
    'POS': HrmPageChrome.primaryNavy,
    'Báo cáo': HrmPageChrome.primaryNavy,
    'Cài đặt': HrmPageChrome.primaryNavy,
  };

  static const _groupDescriptions = {
    'Hồ sơ nhân sự': 'Nhân viên, phòng ban',
    'Chấm công': 'Giờ làm, ca làm',
    'Tài chính': 'Lương, thưởng, ứng',
    'Quản lý Vận hành': 'KPI, truyền thông',
    'POS': 'Bán hàng, kho',
    'Báo cáo': 'Phân tích số liệu',
    'Cài đặt': 'Cấu hình hệ thống',
  };

  @override
  State<_HomeMenuScreen> createState() => _HomeMenuScreenState();
}

class _HomeMenuScreenState extends State<_HomeMenuScreen> {
  String _greeting = '';
  String _greetingIcon = '☀️';
  static double _savedScrollOffset = 0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(initialScrollOffset: _savedScrollOffset);
    _scrollController.addListener(_persistScrollOffset);
    _updateGreeting();
  }

  void _persistScrollOffset() {
    if (_scrollController.hasClients) {
      _savedScrollOffset = _scrollController.offset;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_persistScrollOffset);
    _persistScrollOffset();
    _scrollController.dispose();
    super.dispose();
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

  String _profileSubtitle(User? user) {
    if (user == null) return 'Chi nhánh';
    if (user.department != null && user.department!.trim().isNotEmpty) {
      return user.department!.trim();
    }
    if (user.position != null && user.position!.trim().isNotEmpty) {
      return user.position!.trim();
    }
    if (user.email.isNotEmpty) return user.email;
    return 'Chi nhánh';
  }

  Widget _buildMobileQuickActionsGrid(BuildContext context) {
    final authUser =
        Provider.of<AuthProvider>(context, listen: false).user;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final allowedModules = widget.allowedModules ?? authUser?.allowedModules;
    final role = authUser?.role;
    final allowed = <String>{};
    for (final def in MobileQuickActionsCatalog.items) {
      if (PermissionNavigation.canAccessModule(
        def.moduleCode,
        allowedModules: allowedModules,
        perm: perm,
        role: role,
      )) {
        allowed.add(def.moduleCode);
      }
    }
    final modules = MobileQuickActionsPrefs.layout
        .normalized(allowedModules: allowed)
        .modules
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
    if (modules.isEmpty) return const SizedBox.shrink();

    return PosMobileHubSectionGrid(
      title: 'Truy cập nhanh',
      items: modules
          .map((code) {
            final def = MobileQuickActionsCatalog.map[code];
            if (def == null) return null;
            return PosMobileHubGridItem(
              label: def.label,
              icon: def.icon,
              onTap: () {
                final idx = widget.navItems
                    .indexWhere((n) => n.moduleCode == code);
                if (idx >= 0) widget.onItemTap(idx);
              },
            );
          })
          .whereType<PosMobileHubGridItem>()
          .toList(),
    );
  }

  Widget _buildMobileKiotHome(
    BuildContext context,
    User? user,
    Map<String, List<MapEntry<int, NavItem>>> groupedItems,
  ) {
    final l = AppLocalizations.of(context);
    final groupNames = _HomeMenuScreen._groupOrder
        .where((g) => groupedItems.containsKey(g))
        .toList(growable: false);

    List<PosMobileHubGridItem> itemsFor(String groupName) =>
        groupedItems[groupName]!
            .map(
              (entry) => PosMobileHubGridItem(
                label: entry.value.localizedLabel(l),
                icon: entry.value.activeIcon,
                onTap: () => widget.onItemTap(entry.key),
              ),
            )
            .toList();

    final hPad = kIsWeb ? 20.0 : 12.0;
    final maxContent = kIsWeb ? 1180.0 : double.infinity;

    final scroll = CustomScrollView(
      controller: _scrollController,
      key: const PageStorageKey<String>('home_menu_scroll'),
      cacheExtent: 800,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(hPad, kIsWeb ? 16 : 8, hPad, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              RepaintBoundary(
                child: PosMobileProfileCard(
                  name: user?.fullName ?? 'User',
                  subtitle: _profileSubtitle(user),
                ),
              ),
              const SizedBox(height: 12),
              RepaintBoundary(child: _buildMobileQuickActionsGrid(context)),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 28),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final groupName = groupNames[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == groupNames.length - 1 ? 0 : 12,
                  ),
                  child: RepaintBoundary(
                    child: PosMobileHubSectionGrid(
                      title: NavItem._groupMap[groupName]?.call(l) ??
                          tr(groupName),
                      items: itemsFor(groupName),
                    ),
                  ),
                );
              },
              childCount: groupNames.length,
            ),
          ),
        ),
      ],
    );

    return ColoredBox(
      color: PosTheme.background,
      child: !kIsWeb
          ? scroll
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContent),
                child: scroll,
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final isMobile = MediaQuery.of(context).size.width < 768;
    final padding = isMobile ? 16.0 : 28.0;

    // Group items — chỉ rebuild khi quyền đã tải / đang tải thay đổi.
    return Selector<PermissionProvider, ({bool loaded, bool loading})>(
      selector: (_, p) => (loaded: p.isLoaded, loading: p.isLoading),
      builder: (context, permState, _) {
        final permProvider =
            Provider.of<PermissionProvider>(context, listen: false);
        return _buildHomeMenuBody(
          context,
          user: user,
          isMobile: isMobile,
          padding: padding,
          permProvider: permProvider,
        );
      },
    );
  }

  Widget _buildHomeMenuBody(
    BuildContext context, {
    required User? user,
    required bool isMobile,
    required double padding,
    required PermissionProvider permProvider,
  }) {
    // Group items
    final groupedItems = <String, List<MapEntry<int, NavItem>>>{};
    for (int i = 0; i < widget.navItems.length; i++) {
      final item = widget.navItems[i];
      if (item.group == 'Tổng quan') continue;
      if (item.adminOnly) continue;
      if (item.requiredRole != null) continue;
      if (!PermissionNavigation.isAllowedByPackageOrRole(
        item.moduleCode,
        allowedModules: widget.allowedModules,
        perm: permProvider,
        bypassPackageFilter: widget.bypassPackageFilter,
      )) {
        continue;
      }
      if (!permProvider.canViewNav(item.moduleCode)) continue;
      final group = item.group.isEmpty ? 'Khác' : item.group;
      groupedItems.putIfAbsent(group, () => []);
      groupedItems[group]!.add(MapEntry(i, item));
    }

    // Web + mobile: cùng layout Kiot (profile + lưới section).
    if (isMobile || kIsWeb) {
      return _buildMobileKiotHome(context, user, groupedItems);
    }

    return Container(
      color: const Color(0xFFF1F4F6),
      child: ListView(
        controller: _scrollController,
        key: const PageStorageKey<String>('home_menu_scroll'),
        cacheExtent: 800,
        padding: EdgeInsets.all(padding),
        children: [
          // ═══════════════ QUICK NAV STRIP (trước lưới chức năng) ═══════════════
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _HomeMenuScreen._groupOrder
                  .where((g) => groupedItems.containsKey(g))
                  .map((groupName) {
                final groupColor =
                    _HomeMenuScreen._groupColors[groupName] ?? Colors.grey;
                final groupIcon =
                    _HomeMenuScreen._groupIcons[groupName] ?? Icons.folder;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: Icon(groupIcon, size: 16, color: groupColor),
                    label: Builder(
                      builder: (context) {
                        final l = AppLocalizations.of(context);
                        return Text(
                          tr(NavItem._groupMap[groupName]?.call(l) ?? groupName),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: groupColor),
                        );
                      },
                    ),
                    backgroundColor: groupColor.withValues(alpha: 0.06),
                    side: BorderSide(color: groupColor.withValues(alpha: 0.15)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    onPressed: () {
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

          const SizedBox(height: 20),

          // ═══════════════ HERO GREETING BANNER ═══════════════
          Container(
            padding: EdgeInsets.all(isMobile ? 20 : 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  HrmPageChrome.primaryNavy,
                  HrmPageChrome.primaryNavy.withValues(alpha: 0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.3),
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
                        tr('$_greetingIcon $_greeting,'),
                        style: TextStyle(
                          fontSize: isMobile ? 14 : 16,
                          color: Colors.white.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(user?.fullName ?? 'User'),
                        style: TextStyle(
                          fontSize: isMobile ? 20 : 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tr(_formatTodayDate()),
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
                if (isMobile)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: tr('Cài đặt'),
                        onPressed: () {
                          final idx = widget.navItems.indexWhere(
                              (n) => n.moduleCode == 'SettingsHub');
                          if (idx >= 0) widget.onItemTap(idx);
                        },
                        icon: Icon(
                          Icons.settings_outlined,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Đăng xuất'),
                        onPressed: () async {
                          final l = AppLocalizations.of(context);
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(tr(l.logout)),
                              content: Text(tr(l.logoutConfirm)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: Text(tr(l.cancel)),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red),
                                  child: Text(tr(l.logout)),
                                ),
                              ],
                            ),
                          );
                          if (ok == true && context.mounted) {
                            await Provider.of<AuthProvider>(context,
                                    listen: false)
                                .logout();
                          }
                        },
                        icon: Icon(
                          Icons.logout,
                          color: Colors.red.shade200,
                        ),
                      ),
                    ],
                  )
                else
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

          const SizedBox(height: 28),

          // ═══════════════ FEATURE GROUPS ═══════════════
          ..._HomeMenuScreen._groupOrder
              .where((g) => groupedItems.containsKey(g))
              .map((groupName) {
            final items = groupedItems[groupName]!;
            final groupColor =
                _HomeMenuScreen._groupColors[groupName] ?? Colors.grey;
            final groupIcon =
                _HomeMenuScreen._groupIcons[groupName] ?? Icons.folder;
            final groupDesc =
                _HomeMenuScreen._groupDescriptions[groupName] ?? '';

            return RepaintBoundary(
              child: Padding(
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
                            colors: [
                              groupColor,
                              groupColor.withValues(alpha: 0.7)
                            ],
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
                                  tr(NavItem._groupMap[groupName]?.call(l) ??
                                      groupName),
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
                              tr(groupDesc),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF586064),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: groupColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tr('${items.length}'),
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
                            final itemColor = HrmPageChrome.primaryNavy;
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
                          final itemColor = HrmPageChrome.primaryNavy;
                          final cardWidth = (constraints.maxWidth -
                                  (crossAxisCount - 1) * 10) /
                              crossAxisCount;

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
            ),
            );
          }),
        ],
      ),
    );
  }

  String _formatTodayDate() {
    final now = DateTime.now();
    final weekdays = [
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'CN'
    ];
    final months = [
      'Th01',
      'Th02',
      'Th03',
      'Th04',
      'Th05',
      'Th06',
      'Th07',
      'Th08',
      'Th09',
      'Th10',
      'Th11',
      'Th12'
    ];
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

class _MenuCardState extends State<_MenuCard>
    with SingleTickerProviderStateMixin {
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
                        tr(widget.label),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _isHovered
                              ? widget.color
                              : const Color(0xFF2B3437),
                          letterSpacing: -0.1,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.subtitle != null &&
                          widget.subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          tr(widget.subtitle!),
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
    extends State<_AttendanceNotificationPopup> with TickerProviderStateMixin {
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
                          widthFactor:
                              (1.0 - _progressController.value).clamp(0.0, 1.0),
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
                                        tr(widget.isCheckIn
                                            ? 'CHECK IN'
                                            : 'CHECK OUT'),
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
                                      tr(widget.timeStr),
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
                                  tr(widget.userName),
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
                                        tr(widget.deviceName),
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
                                            tr(widget.verifyType),
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
        return HrmPageChrome.primaryNavy; // Blue
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
                          widthFactor:
                              (1.0 - _progressController.value).clamp(0.0, 1.0),
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
                                        tr(_statusLabel),
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
                                      tr(timeStr),
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
                                  tr(widget.notification.deviceName),
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
                                      tr('SN: ${widget.notification.serialNumber}'),
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
                                          tr(widget.notification.location!),
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
