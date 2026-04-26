import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
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

class SystemAdminScreen extends StatefulWidget {
  const SystemAdminScreen({super.key});

  @override
  State<SystemAdminScreen> createState() => _SystemAdminScreenState();
}

class _SystemAdminScreenState extends State<SystemAdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // GlobalKeys to access child tab states for count badges
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 15, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {}); // Rebuild header badges when tab changes
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminHelpers.bgLight,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: TabBarView(
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
    final maintenanceCount =
        _maintenanceKey.currentState?.windows.length ?? 0;
    final marketingCount =
        (_marketingKey.currentState?.templates.length ?? 0) +
            (_marketingKey.currentState?.campaigns.length ?? 0);

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
                        ? const Color(0xFF1E3A5F).withValues(alpha: 0.3)
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
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
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn có chắc muốn đăng xuất khỏi khu vực quản trị?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đăng xuất', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    await auth.logout();
    // _AdminRouteGuard watches auth state and will rebuild to AdminLoginScreen.
  }
}
