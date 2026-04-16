import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 11, vsync: this);
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
            ],
          ),
        ],
      ),
    );
  }
}
