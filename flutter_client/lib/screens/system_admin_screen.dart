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
  // Real tab indices (0..14) that are visible to the current user.
  // Other roles (Agent) chỉ thấy một phần.
  late List<int> _visibleIndices;

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
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final role = auth.userRole;
    if (role == 'Agent') {
      // Đại lý chỉ thấy: Tổng quan, Cửa hàng, Người dùng, Thiết bị, License, Thông báo
      _visibleIndices = const [0, 1, 2, 3, 5, 11];
    } else {
      _visibleIndices = List<int>.generate(15, (i) => i);
    }
    _tabController = TabController(length: _visibleIndices.length, vsync: this);
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

  void _navigateToTab(int realIndex) {
    final visible = _visibleIndices.indexOf(realIndex);
    if (visible >= 0) {
      _tabController.animateTo(visible);
    }
  }

  // Build all 15 tab contents; only those whose index is in _visibleIndices are rendered.
  List<Widget> _buildAllTabContents() {
    return [
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
    ];
  }

  List<Map<String, dynamic>> get _storesList =>
      _storesKey.currentState?.stores ?? [];

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 720;
    return Scaffold(
      backgroundColor: AdminHelpers.bgLight,
      body: Column(
        children: [
          isMobile ? _buildMobileHeader() : _buildHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: isMobile
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              children: () {
                final all = _buildAllTabContents();
                return _visibleIndices.map((i) => all[i]).toList();
              }(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- MOBILE LAYOUT ----------------

  static const List<({String label, IconData icon})> _tabMeta = [
    (label: 'Tổng quan', icon: Icons.dashboard_rounded),
    (label: 'Cửa hàng', icon: Icons.store_rounded),
    (label: 'Người dùng', icon: Icons.people_rounded),
    (label: 'Thiết bị', icon: Icons.router_rounded),
    (label: 'Đại lý', icon: Icons.support_agent_rounded),
    (label: 'License', icon: Icons.vpn_key_rounded),
    (label: 'Cài đặt', icon: Icons.settings_rounded),
    (label: 'Database', icon: Icons.storage_rounded),
    (label: 'Nhật ký', icon: Icons.history_rounded),
    (label: 'Gói dịch vụ', icon: Icons.inventory_2_rounded),
    (label: 'KH Kích key', icon: Icons.card_giftcard_rounded),
    (label: 'Thông báo', icon: Icons.campaign_rounded),
    (label: 'Bảo trì', icon: Icons.build_circle_rounded),
    (label: 'Marketing', icon: Icons.local_offer_rounded),
    (label: 'Nội dung & Phản hồi', icon: Icons.description_outlined),
  ];

  int _badgeFor(int i) {
    switch (i) {
      case 1: return _storesKey.currentState?.stores.length ?? 0;
      case 2: return _usersKey.currentState?.users.length ?? 0;
      case 3: return _devicesKey.currentState?.devices.length ?? 0;
      case 4: return _agentsKey.currentState?.agents.length ?? 0;
      case 5: return _licensesKey.currentState?.licenses.length ?? 0;
      case 6: return _settingsKey.currentState?.settings.length ?? 0;
      case 9: return _servicePackagesKey.currentState?.packages.length ?? 0;
      case 10: return _keyPromotionsKey.currentState?.promotions.length ?? 0;
      case 11: return _announcementsKey.currentState?.announcements.length ?? 0;
      case 12: return _maintenanceKey.currentState?.windows.length ?? 0;
      case 13: return (_marketingKey.currentState?.templates.length ?? 0) +
            (_marketingKey.currentState?.campaigns.length ?? 0);
      default: return 0;
    }
  }

  Widget _buildMobileHeader() {
    final health = _dashboardKey.currentState?.healthData;
    final idx = _tabController.index;
    final realIdx = _visibleIndices[idx];
    final meta = _tabMeta[realIdx];
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final email = auth.currentUser?.email ?? 'Admin';
    final isHealthy = health?['status'] == 'Healthy';

    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            // Top row: brand + health + logout
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10)),
                  child:
                      const Icon(Icons.shield, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Quản trị hệ thống',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (health != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isHealthy ? Colors.green : Colors.red)
                          .withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                        isHealthy ? Icons.check_circle : Icons.error_rounded,
                        color: Colors.white,
                        size: 14),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Đăng xuất ($email)',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  onPressed: _handleLogout,
                  icon:
                      const Icon(Icons.logout, color: Colors.white, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Current tab pill + menu button
            Material(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openMobileTabPicker,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(meta.icon, color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          meta.label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${idx + 1}/${_visibleIndices.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.expand_more_rounded,
                          color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMobileTabPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (ctx, scrollCtrl) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Row(
                      children: [
                        Icon(Icons.menu_rounded, color: Color(0xFF334155)),
                        SizedBox(width: 8),
                        Text('Chọn mục quản trị',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollCtrl,
                      itemCount: _visibleIndices.length,
                      itemBuilder: (_, i) {
                        final realIdx = _visibleIndices[i];
                        final m = _tabMeta[realIdx];
                        final isCurrent = i == _tabController.index;
                        final badge = _badgeFor(realIdx);
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(m.icon,
                                color: isCurrent
                                    ? Colors.white
                                    : const Color(0xFF334155),
                                size: 18),
                          ),
                          title: Text(m.label,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isCurrent
                                    ? const Color(0xFF0F172A)
                                    : Colors.black87,
                              )),
                          trailing: badge > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF334155)
                                        .withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text('$badge',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF334155))),
                                )
                              : const Icon(Icons.chevron_right_rounded,
                                  color: Colors.grey),
                          onTap: () => Navigator.of(ctx).pop(realIdx),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (selected != null) {
      _navigateToTab(selected);
    }
  }

  // ---------------- DESKTOP HEADER (unchanged) ----------------

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
            tabs: () {
              final all = <Tab>[
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
              ];
              return _visibleIndices.map((i) => all[i]).toList();
            }(),
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
