import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:provider/provider.dart';
import '../models/hrm.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/admin_navigation.dart';
import '../utils/notification_display_utils.dart';
import '../utils/notification_navigation.dart';
import '../utils/pending_notification_launch.dart';
import '../widgets/notification_overlay.dart';
import 'notifications_screen.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import '../widgets/admin/admin_mobile_widgets.dart';
import '../widgets/hrm_page_chrome.dart';
import 'system_admin/system_admin_helpers.dart';
import 'system_admin/agent_profile_tab.dart';
import 'system_admin/dashboard_tab.dart';
import 'system_admin/stores_tab.dart';
import 'system_admin/users_tab.dart';
import 'system_admin/devices_tab.dart';
import 'system_admin/agents_tab.dart';
import 'system_admin/licenses_tab.dart';
import 'system_admin/settings_tab.dart';
import 'system_admin/database_tab.dart';
import 'system_admin/audit_tab.dart';
import 'system_admin/seo_articles_tab.dart';
import 'system_admin/v2/sa_packages_v2.dart';
import 'system_admin/v2/sa_stores_v2.dart';
import 'system_admin/v2/sa_ops_v2.dart';
import 'system_admin/key_promotions_tab.dart';
import 'system_admin/announcements_tab.dart';
import 'system_admin/maintenance_tab.dart';
import 'system_admin/marketing_tab.dart';
import 'system_admin/content_pages_tab.dart';
import 'system_admin/consultation_requests_tab.dart';
import 'system_admin/landing_content_tab.dart';
import 'system_admin/server_ops_tab.dart';
import 'system_admin/pos_sample_catalog_tab.dart';
import 'system_admin/notification_credits_tab.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
class SystemAdminScreen extends StatefulWidget {
  final bool agentMode;

  const SystemAdminScreen({super.key, this.agentMode = false});

  @override
  State<SystemAdminScreen> createState() => _SystemAdminScreenState();
}

class _SystemAdminScreenState extends State<SystemAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  final _dashboardKey = GlobalKey<DashboardTabState>();
  final _storesKey = GlobalKey<StoresTabState>();
  final _usersKey = GlobalKey<UsersTabState>();
  final _devicesKey = GlobalKey<DevicesTabState>();
  final _agentsKey = GlobalKey<AgentsTabState>();
  final _licensesKey = GlobalKey<LicensesTabState>();
  final _agentProfileKey = GlobalKey<AgentProfileTabState>();
  final _settingsKey = GlobalKey<SettingsTabState>();
  final _databaseKey = GlobalKey<DatabaseTabState>();
  final _auditKey = GlobalKey<AuditTabState>();
  final _servicePackagesKey = GlobalKey<PackagesV2TabState>();
  final _keyPromotionsKey = GlobalKey<KeyPromotionsTabState>();
  final _announcementsKey = GlobalKey<AnnouncementsTabState>();
  final _maintenanceKey = GlobalKey<MaintenanceTabState>();
  final _marketingKey = GlobalKey<MarketingTabState>();
  final _contentPagesKey = GlobalKey<ContentPagesTabState>();
  final _consultationRequestsKey = GlobalKey<ConsultationRequestsTabState>();
  final _landingContentKey = GlobalKey<LandingContentTabState>();
  final _serverOpsKey = GlobalKey<ServerOpsTabState>();
  final _posSampleCatalogKey = GlobalKey<PosSampleCatalogTabState>();
  final _notificationCreditsKey = GlobalKey<NotificationCreditsTabState>();

  final _apiService = ApiService();
  final _signalRService = SignalRService();
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  bool _isConnectingSignalR = false;
  int _unreadNotificationsCount = 0;
  VoidCallback? _adminTabListener;
  String? _agentDisplayName;
  String? _agentCode;

  static const _tabLabels = [
    'Tổng quan',
    'Cửa hàng',
    'Tài khoản',
    'Thiết bị',
    'Đại lý',
    'Key kích hoạt',
    'Tình trạng & cài đặt',
    'Database',
    'Nhật ký',
    'Gói dịch vụ',
    'Khuyến mãi key',
    'Thông báo hệ thống',
    'Bảo trì',
    'Marketing',
    'Trang nội dung & góp ý',
    'Lead tư vấn',
    'Trang chủ (Landing)',
    'Catalog mẫu POS',
    'Lượt CK Tingee',
    'Máy chủ',
    'Bài viết SEO',
  ];

  static const _agentTabLabels = [
    'Tổng quan',
    'Cửa hàng',
    'Người dùng',
    'Thiết bị',
    'License',
    'Hồ sơ',
  ];

  int get _tabCount => widget.agentMode ? _agentTabLabels.length : _tabLabels.length;

  List<String> get _visibleTabLabels =>
      widget.agentMode ? _agentTabLabels : _tabLabels;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    AdminNavigationNotifier.systemAdminReady.value = true;
    _adminTabListener = _onAdminNavTabRequested;
    AdminNavigationNotifier.systemAdminTab.addListener(_adminTabListener!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = Provider.of<AuthProvider>(context, listen: false);
      Provider.of<PermissionProvider>(context, listen: false)
          .loadPermissions(role: auth.userRole);
    });
    _loadNotificationCount();
    _connectSignalR();
    PendingNotificationLaunch.scheduleConsume(
      adminPortalMode: true,
      agentMode: widget.agentMode,
    );
    if (widget.agentMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _agentProfileKey.currentState?.loadProfile();
      });
    }
  }

  @override
  void dispose() {
    if (_adminTabListener != null) {
      AdminNavigationNotifier.systemAdminTab.removeListener(_adminTabListener!);
    }
    AdminNavigationNotifier.systemAdminReady.value = false;
    _notificationSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _onAdminNavTabRequested() {
    final tab = AdminNavigationNotifier.systemAdminTab.value;
    if (tab == null || !mounted) return;
    if (tab >= 0 && tab < _tabCount && _tabController.index != tab) {
      _tabController.animateTo(tab);
    }
    AdminNavigationNotifier.systemAdminTab.value = null;
  }

  Future<void> _connectSignalR() async {
    if (_isConnectingSignalR) return;
    _isConnectingSignalR = true;
    try {
      await _notificationSubscription?.cancel();
      if (!mounted) return;

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final token = await authProvider.getValidToken();
      await _signalRService.connect(
        null,
        token,
        () => authProvider.getValidToken(),
      );

      if (!mounted) return;
      final userId = authProvider.user?.id;
      if (userId != null && userId.isNotEmpty) {
        await _signalRService.joinUserGroup(userId);
      }

      _notificationSubscription =
          _signalRService.onNewNotification.listen(_handleNewNotification);
    } catch (e) {
      debugPrint('Error connecting SignalR in SystemAdminScreen: $e');
    } finally {
      _isConnectingSignalR = false;
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
      debugPrint('Error loading admin notification count: $e');
    }
  }

  NotificationType _parseNotificationType(dynamic typeValue) {
    if (typeValue is NotificationType) return typeValue;
    final raw = typeValue?.toString() ?? '0';
    final index = int.tryParse(raw) ?? 0;
    if (index >= 0 && index < NotificationType.values.length) {
      return NotificationType.values[index];
    }
    return NotificationType.info;
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    if (!mounted) return;
    _loadNotificationCount();

    final display = resolveNotificationDisplay(data);
    final title = display.title;
    final message = display.body;
    final type = _parseNotificationType(data['type'] ?? 0);
    final relatedEntityType = data['relatedEntityType'] as String?;
    final notificationId = data['id']?.toString();
    final actionUrl = data['actionUrl']?.toString();
    final relatedEntityId = data['relatedEntityId']?.toString();

    NotificationOverlayManager().show(
      title: title,
      message: message,
      type: type,
      relatedEntityType: relatedEntityType,
      duration: const Duration(seconds: 4),
      onTap: () {
        if (notificationId != null && notificationId.isNotEmpty) {
          _apiService.markNotificationAsRead(notificationId).then((_) {
            _loadNotificationCount();
          });
        }
        navigateFromNotification(
          relatedEntityType: relatedEntityType,
          relatedEntityId: relatedEntityId ?? notificationId,
          title: title,
          categoryCode: data['categoryCode']?.toString(),
          actionUrl: actionUrl,
          adminPortalMode: true,
          agentMode: widget.agentMode,
        );
      },
    );
  }

  void _openNotificationsInbox() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          adminPortalMode: true,
          agentMode: widget.agentMode,
        ),
      ),
    )
        .then((_) {
      _loadNotificationCount();
      ScreenRefreshNotifier.refreshNotificationCount();
    });
  }

  Widget _buildNotificationBell() {
    return IconButton(
      tooltip: tr('Thông báo'),
      onPressed: _openNotificationsInbox,
      icon: Badge(
        isLabelVisible: _unreadNotificationsCount > 0,
        label: Text(
          tr(_unreadNotificationsCount > 99 ? '99+' : '$_unreadNotificationsCount'),
        ),
        child: const Icon(Icons.notifications_outlined, color: Colors.white),
      ),
    );
  }

  void _onAgentProfileLoaded(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _agentDisplayName = data['name']?.toString();
      _agentCode = data['code']?.toString();
    });
  }

  void _onAgentDashboardLoaded() {
    final dash = _dashboardKey.currentState?.dashboardData;
    final name = dash?['agentName']?.toString();
    final code = dash?['agentCode']?.toString();
    if (!mounted) return;
    if (name != null && name.isNotEmpty) {
      setState(() {
        _agentDisplayName ??= name;
        if (code != null && code.isNotEmpty) _agentCode = code;
      });
    }
  }

  String _agentRoleLabel() {
    final name = _agentDisplayName;
    final code = _agentCode;
    if (name != null && name.isNotEmpty) {
      if (code != null && code.isNotEmpty) {
        return '$name · $code';
      }
      return name;
    }
    return 'Đại lý';
  }

  void _navigateToTab(int index) {
    _tabController.animateTo(index);
  }

  int _dashCount(String key) =>
      _dashboardKey.currentState?.dashboardData?[key] as int? ?? 0;

  int _tabStoreCount() {
    final state = _storesKey.currentState;
    if (state != null) return state.stores.length;
    return _dashCount('totalStores');
  }

  int _tabUserCount() {
    final state = _usersKey.currentState;
    if (state != null) return state.users.length;
    return _dashCount('totalUsers');
  }

  int _tabDeviceCount() {
    final state = _devicesKey.currentState;
    if (state != null) return state.devices.length;
    return _dashCount('totalDevices');
  }

  int _tabLicenseCount() {
    final state = _licensesKey.currentState;
    if (state != null) return state.licenses.length;
    return _dashCount('totalLicenseKeys');
  }

  List<Map<String, dynamic>> get _storesList =>
      _storesKey.currentState?.stores ?? [];

  List<AdminNavItem> _navItems() {
    if (widget.agentMode) {
      return [
        AdminNavItem(
            index: 0,
            icon: Icons.dashboard,
            label: 'Tổng quan',
            group: 'Quản lý',
            count: _dashboardKey.currentState != null ? 1 : null),
        AdminNavItem(
            index: 1,
            icon: Icons.store,
            label: 'Cửa hàng',
            group: 'Quản lý',
            count: _tabStoreCount()),
        AdminNavItem(
            index: 2,
            icon: Icons.people,
            label: 'Người dùng',
            group: 'Quản lý',
            count: _tabUserCount()),
        AdminNavItem(
            index: 3,
            icon: Icons.router,
            label: 'Thiết bị',
            group: 'Quản lý',
            count: _tabDeviceCount()),
        AdminNavItem(
            index: 4,
            icon: Icons.vpn_key,
            label: 'License',
            group: 'Quản lý',
            count: _tabLicenseCount()),
        const AdminNavItem(
            index: 5,
            icon: Icons.account_circle,
            label: 'Hồ sơ',
            group: 'Tài khoản'),
      ];
    }

    return [
      const AdminNavItem(
          index: 0, icon: Icons.dashboard, label: 'Tổng quan', group: 'Tổng quan'),
      // ── Khách hàng
      AdminNavItem(index: 1, icon: Icons.store, label: 'Cửa hàng', group: 'Khách hàng', count: _tabStoreCount()),
      AdminNavItem(index: 2, icon: Icons.people, label: 'Tài khoản', group: 'Khách hàng', count: _tabUserCount()),
      AdminNavItem(index: 3, icon: Icons.router, label: 'Thiết bị', group: 'Khách hàng', count: _tabDeviceCount()),
      AdminNavItem(
          index: 15,
          icon: Icons.support_agent_rounded,
          label: 'Lead tư vấn',
          group: 'Khách hàng',
          count: _consultationRequestsKey.currentState?.items.length),
      // ── Kinh doanh
      AdminNavItem(
          index: 9,
          icon: Icons.inventory,
          label: 'Gói dịch vụ',
          group: 'Kinh doanh',
          count: _servicePackagesKey.currentState?.packages.length),
      AdminNavItem(index: 5, icon: Icons.vpn_key, label: 'Key kích hoạt', group: 'Kinh doanh', count: _tabLicenseCount()),
      AdminNavItem(
          index: 10,
          icon: Icons.card_giftcard,
          label: 'Khuyến mãi key',
          group: 'Kinh doanh',
          count: _keyPromotionsKey.currentState?.promotions.length),
      AdminNavItem(
          index: 4,
          icon: Icons.handshake_outlined,
          label: 'Đại lý',
          group: 'Kinh doanh',
          count: _agentsKey.currentState?.agents.length),
      const AdminNavItem(index: 18, icon: Icons.account_balance_wallet, label: 'Lượt CK Tingee', group: 'Kinh doanh'),
      // ── Trang chủ & nội dung
      const AdminNavItem(index: 16, icon: Icons.web_rounded, label: 'Trang chủ (Landing)', group: 'Trang chủ & nội dung'),
      const AdminNavItem(index: 14, icon: Icons.description_outlined, label: 'Trang nội dung & góp ý', group: 'Trang chủ & nội dung'),
      const AdminNavItem(index: 20, icon: Icons.article_outlined, label: 'Bài viết SEO', group: 'Trang chủ & nội dung'),
      AdminNavItem(
          index: 11,
          icon: Icons.campaign,
          label: 'Thông báo hệ thống',
          group: 'Trang chủ & nội dung',
          count: _announcementsKey.currentState?.announcements.length),
      AdminNavItem(
          index: 13,
          icon: Icons.local_offer,
          label: 'Marketing',
          group: 'Trang chủ & nội dung',
          count: (_marketingKey.currentState?.templates.length ?? 0) + (_marketingKey.currentState?.campaigns.length ?? 0)),
      const AdminNavItem(index: 17, icon: Icons.restaurant_menu, label: 'Catalog mẫu POS', group: 'Trang chủ & nội dung'),
      // ── Hệ thống
      AdminNavItem(
          index: 6,
          icon: Icons.monitor_heart_outlined,
          label: 'Tình trạng & cài đặt',
          group: 'Hệ thống',
          count: _settingsKey.currentState?.settings.length),
      AdminNavItem(
          index: 12,
          icon: Icons.build_circle,
          label: 'Bảo trì',
          group: 'Hệ thống',
          count: _maintenanceKey.currentState?.windows.length),
      const AdminNavItem(index: 19, icon: Icons.dns, label: 'Máy chủ', group: 'Hệ thống'),
      const AdminNavItem(index: 7, icon: Icons.storage, label: 'Database', group: 'Hệ thống'),
      const AdminNavItem(index: 8, icon: Icons.history, label: 'Nhật ký', group: 'Hệ thống'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mobile = adminUseMobileLayout(context);
    final role = Provider.of<AuthProvider>(context).userRole;
    final roleLabel = widget.agentMode
        ? _agentRoleLabel()
        : (role.isNotEmpty ? role : 'SuperAdmin');

    return NotificationOverlay(
      extraTopInset: mobile ? 52 : 0,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AdminHelpers.bgLight,
        drawer: mobile
            ? AdminMobileDrawer(
                items: _navItems(),
                currentIndex: _tabController.index,
                onSelect: _navigateToTab,
                healthStatus: _dashboardKey.currentState?.healthData?['status']
                    ?.toString(),
                onLogout: _handleLogout,
                roleLabel: roleLabel,
              )
            : null,
        body: Column(
          children: [
            mobile ? _buildMobileHeader(roleLabel) : _buildDesktopHeader(),
            Expanded(
              child: mobile || widget.agentMode
                  ? _buildTabViews()
                  : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _AdminSideNav(
                        items: _navItems(),
                        current: _tabController.index,
                        onSelect: _navigateToTab,
                      ),
                      Expanded(child: _buildTabViews()),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabViews() {
    final dashboard = DashboardTab(
      key: _dashboardKey,
      agentMode: widget.agentMode,
      onLoaded: () {
        if (mounted) {
          if (widget.agentMode) _onAgentDashboardLoaded();
          setState(() {});
        }
      },
      onNavigateToStores: () => _navigateToTab(1),
      onNavigateToUsers: () => _navigateToTab(2),
      onNavigateToDevices: () => _navigateToTab(3),
      onNavigateToAgents: widget.agentMode ? null : () => _navigateToTab(4),
      onNavigateToLicenses: () => _navigateToTab(widget.agentMode ? 4 : 5),
    );

    if (widget.agentMode) {
      return TabBarView(
        controller: _tabController,
        children: [
          dashboard,
          StoresTab(key: _storesKey, agentMode: true),
          UsersTab(key: _usersKey, agentMode: true),
          DevicesTab(key: _devicesKey, stores: _storesList, agentMode: true),
          LicensesTab(key: _licensesKey, agentMode: true),
          AgentProfileTab(
            key: _agentProfileKey,
            onProfileLoaded: _onAgentProfileLoaded,
          ),
        ],
      );
    }

    return TabBarView(
      controller: _tabController,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        dashboard,
        StoresHubV2(legacy: StoresTab(key: _storesKey)),
        UsersTab(key: _usersKey),
        DevicesTab(key: _devicesKey, stores: _storesList),
        SaHubSwitch(views: [('Hiệu quả đại lý', const AgentsV2View()), ('Quản lý đại lý', AgentsTab(key: _agentsKey))]),
        SaHubSwitch(views: [('Kho key', const KeysV2View()), ('Tạo / giao key', LicensesTab(key: _licensesKey))]),
        SaHubSwitch(views: [
          ('Tình trạng hệ thống', SystemStatusView(onNavigate: (t) => _navigateToTab(const {
                'database': 7, 'server': 19, 'maintenance': 12, 'audit': 8, 'stores': 1, 'licenses': 5,
              }[t] ?? 0))),
          ('Tham số hệ thống', SettingsTab(key: _settingsKey)),
        ]),
        DatabaseTab(key: _databaseKey, stores: _storesList),
        AuditTab(key: _auditKey),
        PackagesV2Tab(key: _servicePackagesKey),
        KeyPromotionsTab(key: _keyPromotionsKey),
        AnnouncementsTab(key: _announcementsKey),
        MaintenanceTab(key: _maintenanceKey),
        MarketingTab(key: _marketingKey),
        ContentPagesTab(key: _contentPagesKey),
        ConsultationRequestsTab(key: _consultationRequestsKey),
        LandingContentTab(key: _landingContentKey),
        PosSampleCatalogTab(key: _posSampleCatalogKey),
        NotificationCreditsTab(key: _notificationCreditsKey),
        ServerOpsTab(key: _serverOpsKey),
        const SeoArticlesTab(),
      ],
    );
  }

  Widget _buildMobileHeader(String roleLabel) {
    final idx = _tabController.index.clamp(0, _visibleTabLabels.length - 1);
    final health = _dashboardKey.currentState?.healthData;

    return Material(
      color: SboxColors.slate900,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu, color: Colors.white),
                tooltip: tr('Menu'),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(_visibleTabLabels[idx]),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      tr(roleLabel),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (health != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    health['status'] == 'Healthy'
                        ? Icons.check_circle
                        : Icons.error,
                    color: health['status'] == 'Healthy'
                        ? Colors.greenAccent
                        : Colors.redAccent,
                    size: 20,
                  ),
                ),
              _buildNotificationBell(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHeader() {
    final health = _dashboardKey.currentState?.healthData;
    final storeCount = _tabStoreCount();
    final userCount = _tabUserCount();
    final deviceCount = _tabDeviceCount();
    final agentCount = _agentsKey.currentState?.agents.length ?? 0;
    final licenseCount = _tabLicenseCount();
    final settingCount = _settingsKey.currentState?.settings.length ?? 0;
    final packageCount = _servicePackagesKey.currentState?.packages.length ?? 0;
    final promoCount = _keyPromotionsKey.currentState?.promotions.length ?? 0;
    final announcementCount =
        _announcementsKey.currentState?.announcements.length ?? 0;
    final maintenanceCount = _maintenanceKey.currentState?.windows.length ?? 0;
    final marketingCount = (_marketingKey.currentState?.templates.length ?? 0) +
        (_marketingKey.currentState?.campaigns.length ?? 0);
    final consultationCount =
        _consultationRequestsKey.currentState?.items.length ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      decoration: const BoxDecoration(
        gradient:
            LinearGradient(colors: [SboxColors.slate900, SboxColors.slate700]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.shield, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Quản trị hệ thống'),
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    Text(
                      tr(widget.agentMode
                          ? '${_agentDisplayName ?? 'Đại lý'} — Quản lý cửa hàng trong phạm vi được gán'
                          : 'SuperAdmin — Quản lý toàn bộ hệ thống'),
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
              if (health != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: health['status'] == 'Healthy'
                        ? HrmPageChrome.primaryNavy.withValues(alpha: 0.3)
                        : Colors.red.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        health['status'] == 'Healthy'
                            ? Icons.check_circle
                            : Icons.error,
                        color: Colors.white,
                        size: 14),
                    const SizedBox(width: 4),
                    Text(tr(health['status']?.toString() ?? 'N/A'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              const SizedBox(width: 8),
              _buildNotificationBell(),
              const SizedBox(width: 8),
              _buildLogoutButton(),
            ],
          ),
          if (!widget.agentMode) const SizedBox(height: 16),
          if (widget.agentMode) const SizedBox(height: 16),
          if (widget.agentMode)
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: widget.agentMode
                ? [
                    Tab(
                        icon: Icon(Icons.dashboard, size: 18),
                        text: tr('Tổng quan')),
                    Tab(
                        icon: const Icon(Icons.store, size: 18),
                        text: tr('Cửa hàng ($storeCount)')),
                    Tab(
                        icon: const Icon(Icons.people, size: 18),
                        text: tr('Người dùng ($userCount)')),
                    Tab(
                        icon: const Icon(Icons.router, size: 18),
                        text: tr('Thiết bị ($deviceCount)')),
                    Tab(
                        icon: const Icon(Icons.vpn_key, size: 18),
                        text: tr('License ($licenseCount)')),
                    Tab(
                        icon: Icon(Icons.account_circle, size: 18),
                        text: tr('Hồ sơ')),
                  ]
                : [
              Tab(
                  icon: Icon(Icons.dashboard, size: 18), text: tr('Tổng quan')),
              Tab(
                  icon: const Icon(Icons.store, size: 18),
                  text: tr('Cửa hàng ($storeCount)')),
              Tab(
                  icon: const Icon(Icons.people, size: 18),
                  text: tr('Người dùng ($userCount)')),
              Tab(
                  icon: const Icon(Icons.router, size: 18),
                  text: tr('Thiết bị ($deviceCount)')),
              Tab(
                  icon: const Icon(Icons.support_agent, size: 18),
                  text: tr('Đại lý ($agentCount)')),
              Tab(
                  icon: const Icon(Icons.vpn_key, size: 18),
                  text: tr('License ($licenseCount)')),
              Tab(
                  icon: const Icon(Icons.settings, size: 18),
                  text: tr('Cài đặt ($settingCount)')),
              Tab(icon: Icon(Icons.storage, size: 18), text: tr('Database')),
              Tab(icon: Icon(Icons.history, size: 18), text: tr('Nhật ký')),
              Tab(
                  icon: const Icon(Icons.inventory, size: 18),
                  text: tr('Gói DV ($packageCount)')),
              Tab(
                  icon: const Icon(Icons.card_giftcard, size: 18),
                  text: tr('KH Kích key ($promoCount)')),
              Tab(
                  icon: const Icon(Icons.campaign, size: 18),
                  text: tr('Thông báo ($announcementCount)')),
              Tab(
                  icon: const Icon(Icons.build_circle, size: 18),
                  text: tr('Bảo trì ($maintenanceCount)')),
              Tab(
                  icon: const Icon(Icons.local_offer, size: 18),
                  text: tr('Marketing ($marketingCount)')),
              Tab(
                  icon: Icon(Icons.description_outlined, size: 18),
                  text: tr('Nội dung & Phản hồi')),
              Tab(
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  text: tr('Lead tư vấn ($consultationCount)')),
              Tab(
                  icon: Icon(Icons.web_rounded, size: 18),
                  text: tr('Landing Page')),
              Tab(
                  icon: Icon(Icons.restaurant_menu, size: 18),
                  text: tr('Catalog mẫu POS')),
              Tab(
                  icon: Icon(Icons.account_balance_wallet, size: 18),
                  text: tr('Lượt CK Tingee')),
              Tab(icon: Icon(Icons.dns, size: 18), text: tr('Máy chủ')),
              Tab(icon: Icon(Icons.article_outlined, size: 18), text: tr('Bài viết SEO')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userLabel = auth.currentUser?.email ?? 'Admin';
    return Tooltip(
      message: tr('Đăng xuất ($userLabel)'),
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _handleLogout,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.logout, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text(tr('Đăng xuất'),
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Đăng xuất?')),
        content:
            Text(tr('Bạn có chắc muốn đăng xuất khỏi khu vực quản trị?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Huỷ')),
          ),
          FilledButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                Text(tr('Đăng xuất'), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/admin', (_) => false);
  }
}

/// Thanh điều hướng trái theo nhóm (Super Admin trên máy tính).
class _AdminSideNav extends StatelessWidget {
  const _AdminSideNav({required this.items, required this.current, required this.onSelect});
  final List<AdminNavItem> items;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? group;
    for (final it in items) {
      if (it.group != group) {
        group = it.group;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
          child: Text(tr(group).toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: SboxColors.slate400)),
        ));
      }
      final sel = it.index == current;
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: sel ? SboxColors.brand50 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelect(it.index),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                Icon(it.icon, size: 18, color: sel ? SboxColors.brand600 : SboxColors.slate500),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr(it.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? SboxColors.brand800 : SboxColors.slate700)),
                ),
                if ((it.count ?? 0) > 0)
                  Text('${it.count}', style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ));
    }
    return Container(
      width: 236,
      decoration: const BoxDecoration(color: SboxColors.white, border: Border(right: BorderSide(color: SboxColors.border))),
      child: ListView(padding: const EdgeInsets.only(bottom: 16), children: children),
    );
  }
}
