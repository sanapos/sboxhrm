import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_hub_sidebar_config.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/settings_hub_sidebar_prefs.dart';
import '../utils/permission_navigation.dart';
import '../utils/settings_hub_catalog.dart';
import '../utils/store_role_helper.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../services/api_service.dart';
import '../widgets/settings_hub_sidebar_config_dialog.dart';
import '../widgets/store_agent_support_card.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_theme.dart';
import '../models/user.dart';

import 'account_management_screen.dart';
import 'ai_settings_screen.dart';
import 'allowance_settings_screen.dart';

import 'holiday_settings_screen.dart';
import 'insurance_settings_screen.dart';
import 'mobile_attendance_settings_screen.dart';

import 'penalty_settings_screen.dart';
import 'role_permissions_screen.dart';
import 'shift_settings_screen.dart';
import 'system_settings_screen.dart';
import 'tax_settings_screen.dart';
import 'device_management_settings_screen.dart';

import 'product_salary_settings_screen.dart';
import 'branch_management_screen.dart';
import 'staffing_quota_settings_screen.dart';
import 'pos_print_templates_screen.dart';

class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  /// Static callback for main_layout to handle internal back navigation.
  /// When a sub-screen is active, this resets to the hub menu instead of leaving HRM setup.
  static VoidCallback? internalBackCallback;

  /// Title of the active sub-page (for main_layout AppBar / top bar).
  static String? activeSubPageTitle;

  /// True when a sub-settings page is open — main_layout already shows one back button.
  static bool get isEmbeddedSubPage => internalBackCallback != null;

  /// Pending sub-screen index to open when navigating to settings hub.
  /// Set value to trigger navigation, even if already on settings hub.
  static final ValueNotifier<int?> pendingSubIndex = ValueNotifier<int?>(null);

  /// Navigate back from a settings sub-screen.
  /// Uses internalBackCallback if available, otherwise Navigator.maybePop.
  static void goBack(BuildContext context) {
    final cb = internalBackCallback;
    if (cb != null) {
      cb();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  int? _selectedIndex;
  Map<String, dynamic>? _storeAgentContact;
  SettingsHubSidebarConfig? _sidebarConfig;
  bool _sidebarConfigLoading = true;

  bool get _isSuperAdmin {
    final role =
        (Provider.of<AuthProvider>(context, listen: false).currentUser?.role ??
                '')
            .toLowerCase();
    return role == 'superadmin';
  }

  @override
  void initState() {
    super.initState();
    SettingsHubSidebarPrefs.setCache(null);
    // Consume pending sub-index if set before navigation
    final pending = SettingsHubScreen.pendingSubIndex.value;
    if (pending != null) {
      _selectedIndex = pending;
      SettingsHubScreen.activeSubPageTitle = _labelForIndex(pending);
      SettingsHubScreen.internalBackCallback = _closeSubPage;
      SettingsHubScreen.pendingSubIndex.value = null;
    }
    // Listen for future external navigation requests
    SettingsHubScreen.pendingSubIndex.addListener(_onPendingSubIndex);
    _loadStoreAgentContact();
    _loadSidebarConfig();
  }

  Future<void> _loadSidebarConfig() async {
    final config = await SettingsHubSidebarPrefs.load();
    if (!mounted) return;
    setState(() {
      _sidebarConfig = config;
      _sidebarConfigLoading = false;
    });
  }

  Future<void> _loadStoreAgentContact() async {
    if (_isSuperAdmin) return;
    try {
      final res = await ApiService().getStoreAgentContact();
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] != null) {
        setState(() =>
            _storeAgentContact = Map<String, dynamic>.from(res['data'] as Map));
      }
    } catch (_) {}
  }

  void _onPendingSubIndex() {
    final idx = SettingsHubScreen.pendingSubIndex.value;
    if (idx != null && mounted) {
      _openSubPage(idx);
      SettingsHubScreen.pendingSubIndex.value = null;
    }
  }

  @override
  void dispose() {
    SettingsHubScreen.pendingSubIndex.removeListener(_onPendingSubIndex);
    SettingsHubScreen.internalBackCallback = null;
    SettingsHubScreen.activeSubPageTitle = null;
    super.dispose();
  }

  String? _labelForIndex(int index) =>
      SettingsHubCatalog.byIndex(index)?.label;

  bool _canCustomizeSidebar() {
    final role =
        (Provider.of<AuthProvider>(context, listen: false).currentUser?.role ??
                '')
            .toLowerCase();
    if (role == 'superadmin' || role == 'admin') return true;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    return perm.canEdit('SystemSettings');
  }

  List<SettingsHubItemDef> _permittedHubItems() {
    return _filterItems(SettingsHubCatalog.allItems);
  }

  List<SettingsHubItemDef> _orderedHubItems() {
    return SettingsHubCatalog.applyConfig(
      _permittedHubItems(),
      _sidebarConfig,
    );
  }

  List<({String title, IconData icon, Color accent, List<SettingsHubItemDef> items})>
      _orderedHubGroups() {
    final ordered = _orderedHubItems();
    final grouped = SettingsHubCatalog.groupOrderedItems(ordered);
    return [
      for (final g in grouped)
        (
          title: g.title,
          icon: _groupIcon(g.title),
          accent: _groupAccent(g.title),
          items: g.items,
        ),
    ];
  }

  IconData _groupIcon(String title) => switch (title) {
        'Chấm công & Ca' => Icons.schedule,
        'Chính sách lương' => Icons.payments,
        'Quản trị hệ thống' => Icons.admin_panel_settings,
        'POS / Bán hàng' => Icons.point_of_sale,
        'Tích hợp' => Icons.hub,
        _ => Icons.folder_outlined,
      };

  Color _groupAccent(String title) => switch (title) {
        'POS / Bán hàng' => const Color(0xFF2563EB),
        'Chính sách lương' => HrmPageChrome.primaryNavy,
        _ => HrmPageChrome.primaryNavy,
      };

  Future<void> _openSidebarConfigDialog() async {
    final permitted = _permittedHubItems();
    if (permitted.isEmpty) return;
    final initial = _sidebarConfig ??
        SettingsHubSidebarConfig.defaults(SettingsHubCatalog.defaultOrder);
    final saved = await SettingsHubSidebarConfigDialog.show(
      context,
      initialConfig: initial,
      permittedItems: permitted,
      onSave: SettingsHubSidebarPrefs.save,
    );
    if (!mounted || saved == null) return;
    setState(() => _sidebarConfig = saved);
    final visibleIds = SettingsHubCatalog.applyConfig(permitted, saved)
        .map((e) => e.index)
        .toSet();
    if (_selectedIndex != null && !visibleIds.contains(_selectedIndex)) {
      _closeSubPage();
    }
  }

  void _openSubPage(int index) {
    setState(() {
      _selectedIndex = index;
      SettingsHubScreen.activeSubPageTitle = _labelForIndex(index);
      SettingsHubScreen.internalBackCallback = _closeSubPage;
    });
  }

  void _closeSubPage() {
    if (!mounted) {
      _selectedIndex = null;
      SettingsHubScreen.activeSubPageTitle = null;
      SettingsHubScreen.internalBackCallback = null;
      return;
    }
    setState(() {
      _selectedIndex = null;
      SettingsHubScreen.activeSubPageTitle = null;
      SettingsHubScreen.internalBackCallback = null;
    });
  }

  void _ensureSubPageCallback() {
    final index = _selectedIndex;
    if (index == null) return;
    SettingsHubScreen.activeSubPageTitle = _labelForIndex(index);
    SettingsHubScreen.internalBackCallback ??= _closeSubPage;
  }

  static const _bgColor = Color(0xFFFAFAFA);
  static const _textDark = Color(0xFF0F172A);
  static const _textMuted = Color(0xFF71717A);
  static const _borderColor = Color(0xFFE4E4E7);

  Widget _getScreen(int index) {
    switch (index) {
      case 0:
        return const ShiftSettingsScreen();
      case 1:
        return const MobileAttendanceSettingsScreen();
      case 2:
        return const HolidaySettingsScreen();
      case 3:
        return const AllowanceSettingsScreen();
      case 4:
        return const PenaltySettingsScreen();
      case 5:
        return const InsuranceSettingsScreen();
      case 6:
        return const TaxSettingsScreen();
      case 7:
        return const AccountManagementScreen();
      case 8:
        return const RolePermissionsScreen();
      case 9:
        return const SystemSettingsScreen();
      case 13:
        return const BranchManagementScreen();
      case 10:
        return const ProductSalarySettingsScreen();
      case 11:
        return const AiSettingsScreen();
      case 12:
        return const DeviceManagementSettingsScreen();
      case 14:
        return const StaffingQuotaSettingsScreen();
      case 15:
        return const PosPrintTemplatesScreen(embeddedInSettings: true);
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      if (_selectedIndex != null) {
        _ensureSubPageCallback();
        return _getScreen(_selectedIndex!);
      }
      _closeSubPage();
      return ColoredBox(
        color: PosTheme.background,
        child: _buildMobileHome(),
      );
    }

    if (_selectedIndex != null) {
      _ensureSubPageCallback();
    } else {
      _closeSubPage();
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 272, child: _buildDesktopSidebar()),
          Expanded(
            child: _selectedIndex != null
                ? _getScreen(_selectedIndex!)
                : _buildDesktopWelcome(),
          ),
        ],
      ),
    );
  }

  // ===== MOBILE HOME (lưới KiotViet) =====
  Widget _buildMobileHome() {
    final groups = _orderedHubGroups();

    return ColoredBox(
      color: PosTheme.background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          _buildMobileSettingsHeaderCard(),
          if (_storeAgentContact != null) ...[
            const SizedBox(height: 12),
            StoreAgentSupportCard.fromMap(_storeAgentContact!),
          ],
          const SizedBox(height: 12),
          ...groups.expand((g) {
            if (g.items.isEmpty) return <Widget>[];
            return [
              PosMobileHubSectionGrid(
                title: g.title,
                items: g.items
                    .map(
                      (item) => PosMobileHubGridItem(
                        label: item.label,
                        icon: item.icon,
                        onTap: () => _openSubPage(item.index),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
            ];
          }),
        ],
      ),
    );
  }

  Widget _buildMobileSettingsHeaderCard() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final subtitle = user?.department?.trim().isNotEmpty == true
        ? user!.department!.trim()
        : (user?.position?.trim().isNotEmpty == true
            ? user!.position!.trim()
            : 'Quản lý cấu hình hệ thống');

    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: PosTheme.kiotBlueLight,
            child: const Icon(Icons.tune_rounded,
                color: PosTheme.kiotBlue, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.fullName ?? 'Thiết lập HRM',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: PosTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (_canCustomizeSidebar())
            IconButton(
              tooltip: 'Tùy chỉnh menu',
              onPressed:
                  _sidebarConfigLoading ? null : _openSidebarConfigDialog,
              icon: const Icon(Icons.dashboard_customize_outlined,
                  color: PosTheme.kiotBlue),
            ),
        ],
      ),
    );
  }

  List<SettingsHubItemDef> _filterItems(List<SettingsHubItemDef> items) {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final role = (authUser?.role ?? '').toLowerCase();
    final isSuperAdmin = role == 'superadmin';
    final bypassPackage = StoreRoleHelper.bypassesPackageFilter(authUser?.role);
    if (isSuperAdmin) return items;
    final permProvider =
        Provider.of<PermissionProvider>(context, listen: false);
    final allowedModules = authUser?.allowedModules;
    return items.where((item) {
      if (!PermissionNavigation.isAllowedByPackageOrRole(
        item.moduleCode,
        allowedModules: allowedModules,
        perm: permProvider,
        bypassPackageFilter: bypassPackage,
      )) {
        return false;
      }
      // Lọc theo quyền canView
      if (item.moduleCode != null && !permProvider.canView(item.moduleCode!)) {
        return false;
      }
      return true;
    }).toList();
  }

  // ===== DESKTOP SIDEBAR =====
  Widget _buildDesktopSidebar() {
    final groups = _orderedHubGroups();
    final canCustomize = _canCustomizeSidebar();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: _borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 12, 14),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.tune_rounded,
                      color: HrmPageChrome.primaryNavy, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Thiết lập HRM',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                ),
                if (canCustomize)
                  IconButton(
                    tooltip: 'Tùy chỉnh menu',
                    onPressed:
                        _sidebarConfigLoading ? null : _openSidebarConfigDialog,
                    icon: const Icon(Icons.dashboard_customize_outlined, size: 20),
                    color: HrmPageChrome.primaryNavy,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
          Expanded(
            child: _sidebarConfigLoading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                    children: [
                      for (final g in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                          child: Text(
                            g.title.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: g.accent,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        for (final item in g.items)
                          _buildDesktopSidebarItem(item),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebarItem(SettingsHubItemDef item) {
    final selected = _selectedIndex == item.index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected
            ? item.accent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _openSubPage(item.index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(color: item.accent.withValues(alpha: 0.35))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 18,
                  color: selected ? item.accent : const Color(0xFF64748B),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? item.accent : _textDark,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopWelcome() {
    final groups = _orderedHubGroups();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverviewHeader(),
          if (_storeAgentContact != null) ...[
            const SizedBox(height: 16),
            StoreAgentSupportCard.fromMap(_storeAgentContact!),
          ],
          const SizedBox(height: 28),
          for (final g in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _buildGroupSection(g.title, g.icon, g.accent, g.items),
            ),
        ],
      ),
    );
  }

  Widget _buildOverviewHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F172A),
            HrmPageChrome.primaryNavy,
            HrmPageChrome.primaryNavy,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Color(0x180F172A), blurRadius: 20, offset: Offset(0, 10))
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999)),
                  child: const Text('HRM Settings Center',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Trung tâm thiết lập hệ thống HRM',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quản lý toàn bộ cấu hình ca làm việc, chính sách lương, quản trị hệ thống và tích hợp.',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                      height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final g in _orderedHubGroups())
                _buildStatBadge(
                    g.icon, '${g.items.length}', _shortGroupLabel(g.title)),
            ],
          ),
        ],
      ),
    );
  }

  String _shortGroupLabel(String title) {
    if (title.contains('/')) return title.split('/').first.trim();
    final words = title.split(' ');
    return words.length > 2 ? words.first : title;
  }

  Widget _buildStatBadge(IconData icon, String count, String label) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 8),
          Text(count,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildGroupSection(
    String title,
    IconData icon,
    Color accent,
    List<SettingsHubItemDef> items,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textDark)),
            const Spacer(),
            Text('${items.length} mục',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: items.map((item) => _buildShortcutCard(item)).toList(),
        ),
      ],
    );
  }

  Widget _buildShortcutCard(SettingsHubItemDef item) {
    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => _openSubPage(item.index),
          borderRadius: BorderRadius.circular(16),
          hoverColor: item.accent.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      item.accent,
                      item.accent.withValues(alpha: 0.7)
                    ]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _textDark)),
                      const SizedBox(height: 3),
                      Text(item.desc,
                          style: const TextStyle(
                              fontSize: 11, color: _textMuted, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right,
                    size: 18, color: item.accent.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsAccessDeniedScreen extends StatelessWidget {
  final String title;
  final String message;

  const _SettingsAccessDeniedScreen({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Thiet lap HRM'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF18181B),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded,
                  size: 56, color: Color(0xFF94A3B8)),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 14, color: Color(0xFF64748B))),
            ],
          ),
        ),
      ),
    );
  }
}
