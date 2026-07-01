import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/admin/admin_mobile_widgets.dart';
import '../widgets/hrm_page_chrome.dart';
import 'system_admin/system_admin_helpers.dart';
import 'system_admin/dashboard_tab.dart';
import 'system_admin/stores_tab.dart';
import 'system_admin/users_tab.dart';
import 'system_admin/devices_tab.dart';
import 'system_admin/agents_tab.dart';
import 'system_admin/licenses_tab.dart';
import 'system_admin/settings_tab.dart';
import 'system_admin/database_tab.dart';
import 'system_admin/audit_tab.dart';
import 'system_admin/service_packages_tab.dart';
import 'system_admin/key_promotions_tab.dart';
import 'system_admin/announcements_tab.dart';
import 'system_admin/maintenance_tab.dart';
import 'system_admin/marketing_tab.dart';
import 'system_admin/content_pages_tab.dart';
import 'system_admin/consultation_requests_tab.dart';
import 'system_admin/landing_content_tab.dart';

class SystemAdminScreen extends StatefulWidget {
  const SystemAdminScreen({super.key});

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
  final _settingsKey = GlobalKey<SettingsTabState>();
  final _databaseKey = GlobalKey<DatabaseTabState>();
  final _auditKey = GlobalKey<AuditTabState>();
  final _servicePackagesKey = GlobalKey<ServicePackagesTabState>();
  final _keyPromotionsKey = GlobalKey<KeyPromotionsTabState>();
  final _announcementsKey = GlobalKey<AnnouncementsTabState>();
  final _maintenanceKey = GlobalKey<MaintenanceTabState>();
  final _marketingKey = GlobalKey<MarketingTabState>();
  final _contentPagesKey = GlobalKey<ContentPagesTabState>();
  final _consultationRequestsKey = GlobalKey<ConsultationRequestsTabState>();
  final _landingContentKey = GlobalKey<LandingContentTabState>();

  static const _tabLabels = [
    'Tổng quan',
    'Cửa hàng',
    'Người dùng',
    'Thiết bị',
    'Đại lý',
    'License',
    'Cài đặt',
    'Database',
    'Nhật ký',
    'Gói DV',
    'KH Kích key',
    'Thông báo',
    'Bảo trì',
    'Marketing',
    'Nội dung & Phản hồi',
    'Lead tư vấn',
    'Landing Page',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToTab(int index) {
    _tabController.animateTo(index);
  }

  List<Map<String, dynamic>> get _storesList =>
      _storesKey.currentState?.stores ?? [];

  List<AdminNavItem> _navItems() {
    return [
      const AdminNavItem(
          index: 0, icon: Icons.dashboard, label: 'Tổng quan', group: 'Tổng quan'),
      AdminNavItem(
          index: 1,
          icon: Icons.store,
          label: 'Cửa hàng',
          group: 'Quản lý',
          count: _storesKey.currentState?.stores.length),
      AdminNavItem(
          index: 2,
          icon: Icons.people,
          label: 'Người dùng',
          group: 'Quản lý',
          count: _usersKey.currentState?.users.length),
      AdminNavItem(
          index: 3,
          icon: Icons.router,
          label: 'Thiết bị',
          group: 'Quản lý',
          count: _devicesKey.currentState?.devices.length),
      AdminNavItem(
          index: 4,
          icon: Icons.support_agent,
          label: 'Đại lý',
          group: 'Quản lý',
          count: _agentsKey.currentState?.agents.length),
      AdminNavItem(
          index: 5,
          icon: Icons.vpn_key,
          label: 'License',
          group: 'Quản lý',
          count: _licensesKey.currentState?.licenses.length),
      AdminNavItem(
          index: 6,
          icon: Icons.settings,
          label: 'Cài đặt',
          group: 'Hệ thống',
          count: _settingsKey.currentState?.settings.length),
      const AdminNavItem(
          index: 7, icon: Icons.storage, label: 'Database', group: 'Hệ thống'),
      const AdminNavItem(
          index: 8, icon: Icons.history, label: 'Nhật ký', group: 'Hệ thống'),
      AdminNavItem(
          index: 9,
          icon: Icons.inventory,
          label: 'Gói DV',
          group: 'Hệ thống',
          count: _servicePackagesKey.currentState?.packages.length),
      AdminNavItem(
          index: 10,
          icon: Icons.card_giftcard,
          label: 'KH Kích key',
          group: 'Hệ thống',
          count: _keyPromotionsKey.currentState?.promotions.length),
      AdminNavItem(
          index: 11,
          icon: Icons.campaign,
          label: 'Thông báo',
          group: 'Nội dung',
          count: _announcementsKey.currentState?.announcements.length),
      AdminNavItem(
          index: 12,
          icon: Icons.build_circle,
          label: 'Bảo trì',
          group: 'Nội dung',
          count: _maintenanceKey.currentState?.windows.length),
      AdminNavItem(
          index: 13,
          icon: Icons.local_offer,
          label: 'Marketing',
          group: 'Nội dung',
          count: (_marketingKey.currentState?.templates.length ?? 0) +
              (_marketingKey.currentState?.campaigns.length ?? 0)),
      const AdminNavItem(
          index: 14,
          icon: Icons.description_outlined,
          label: 'Nội dung & Phản hồi',
          group: 'Nội dung'),
      AdminNavItem(
          index: 15,
          icon: Icons.support_agent_rounded,
          label: 'Lead tư vấn',
          group: 'Nội dung',
          count: _consultationRequestsKey.currentState?.items.length),
      const AdminNavItem(
          index: 16,
          icon: Icons.web_rounded,
          label: 'Landing Page',
          group: 'Nội dung'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mobile = adminUseMobileLayout(context);

    return Scaffold(
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
            )
          : null,
      body: Column(
        children: [
          mobile ? _buildMobileHeader() : _buildDesktopHeader(),
          Expanded(child: _buildTabViews()),
        ],
      ),
    );
  }

  Widget _buildTabViews() {
    return TabBarView(
      controller: _tabController,
      children: [
        DashboardTab(
          key: _dashboardKey,
          onNavigateToStores: () => _navigateToTab(1),
          onNavigateToUsers: () => _navigateToTab(2),
          onNavigateToDevices: () => _navigateToTab(3),
          onNavigateToAgents: () => _navigateToTab(4),
          onNavigateToLicenses: () => _navigateToTab(5),
        ),
        StoresTab(key: _storesKey),
        UsersTab(key: _usersKey),
        DevicesTab(key: _devicesKey, stores: _storesList),
        AgentsTab(key: _agentsKey),
        LicensesTab(key: _licensesKey),
        SettingsTab(key: _settingsKey),
        DatabaseTab(key: _databaseKey, stores: _storesList),
        AuditTab(key: _auditKey),
        ServicePackagesTab(key: _servicePackagesKey),
        KeyPromotionsTab(key: _keyPromotionsKey),
        AnnouncementsTab(key: _announcementsKey),
        MaintenanceTab(key: _maintenanceKey),
        MarketingTab(key: _marketingKey),
        ContentPagesTab(key: _contentPagesKey),
        ConsultationRequestsTab(key: _consultationRequestsKey),
        LandingContentTab(key: _landingContentKey),
      ],
    );
  }

  Widget _buildMobileHeader() {
    final idx = _tabController.index.clamp(0, _tabLabels.length - 1);
    final health = _dashboardKey.currentState?.healthData;

    return Material(
      color: const Color(0xFF0F172A),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu, color: Colors.white),
                tooltip: 'Menu',
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tabLabels[idx],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'SuperAdmin',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopHeader() {
    final health = _dashboardKey.currentState?.healthData;
    final storeCount = _storesKey.currentState?.stores.length ?? 0;
    final userCount = _usersKey.currentState?.users.length ?? 0;
    final deviceCount = _devicesKey.currentState?.devices.length ?? 0;
    final agentCount = _agentsKey.currentState?.agents.length ?? 0;
    final licenseCount = _licensesKey.currentState?.licenses.length ?? 0;
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
            LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF334155)]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.shield, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quản trị hệ thống',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold)),
                    Text('SuperAdmin — Quản lý toàn bộ hệ thống',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
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
                    Text(health['status']?.toString() ?? 'N/A',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              const SizedBox(width: 12),
              _buildLogoutButton(),
            ],
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(
                  icon: Icon(Icons.dashboard, size: 18), text: 'Tổng quan'),
              Tab(
                  icon: const Icon(Icons.store, size: 18),
                  text: 'Cửa hàng ($storeCount)'),
              Tab(
                  icon: const Icon(Icons.people, size: 18),
                  text: 'Người dùng ($userCount)'),
              Tab(
                  icon: const Icon(Icons.router, size: 18),
                  text: 'Thiết bị ($deviceCount)'),
              Tab(
                  icon: const Icon(Icons.support_agent, size: 18),
                  text: 'Đại lý ($agentCount)'),
              Tab(
                  icon: const Icon(Icons.vpn_key, size: 18),
                  text: 'License ($licenseCount)'),
              Tab(
                  icon: const Icon(Icons.settings, size: 18),
                  text: 'Cài đặt ($settingCount)'),
              const Tab(icon: Icon(Icons.storage, size: 18), text: 'Database'),
              const Tab(icon: Icon(Icons.history, size: 18), text: 'Nhật ký'),
              Tab(
                  icon: const Icon(Icons.inventory, size: 18),
                  text: 'Gói DV ($packageCount)'),
              Tab(
                  icon: const Icon(Icons.card_giftcard, size: 18),
                  text: 'KH Kích key ($promoCount)'),
              Tab(
                  icon: const Icon(Icons.campaign, size: 18),
                  text: 'Thông báo ($announcementCount)'),
              Tab(
                  icon: const Icon(Icons.build_circle, size: 18),
                  text: 'Bảo trì ($maintenanceCount)'),
              Tab(
                  icon: const Icon(Icons.local_offer, size: 18),
                  text: 'Marketing ($marketingCount)'),
              const Tab(
                  icon: Icon(Icons.description_outlined, size: 18),
                  text: 'Nội dung & Phản hồi'),
              Tab(
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  text: 'Lead tư vấn ($consultationCount)'),
              const Tab(
                  icon: Icon(Icons.web_rounded, size: 18),
                  text: 'Landing Page'),
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
      message: 'Đăng xuất ($userLabel)',
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _handleLogout,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.logout, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text('Đăng xuất',
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
        title: const Text('Đăng xuất?'),
        content:
            const Text('Bạn có chắc muốn đăng xuất khỏi khu vực quản trị?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Đăng xuất', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.logout();
  }
}
