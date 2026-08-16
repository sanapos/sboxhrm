import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_hub_sidebar_config.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/settings_hub_sidebar_prefs.dart';
import '../utils/permission_navigation.dart';
import '../utils/settings_hub_catalog.dart';
import '../utils/store_role_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../services/api_service.dart';
import '../widgets/settings_hub_sidebar_config_dialog.dart';
import '../widgets/store_agent_support_card.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_theme.dart';

import 'hrm_module_unavailable_screen.dart';
import 'pos_print_templates_screen.dart';
import 'pos/pos_sell_industry_settings_hub_screen.dart';
import 'pos/pos_einvoice_settings_screen.dart';
import 'pos/pos_store_settings_hub_screen.dart';
import 'pos/pos_printer_settings_hub_screen.dart';
import 'pos/pos_resource_floor_screen.dart';
import 'pos/pos_appointment_day_screen.dart';
import 'pos/pos_customer_display_settings_screen.dart';
import 'pos/pos_customers_screen.dart';
import 'pos/pos_accounts_screen.dart';
import 'pos/pos_role_permissions_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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

  /// Clear hub chrome flags without setState when already on menu.
  void _syncHubChrome() {
    SettingsHubScreen.activeSubPageTitle = null;
    SettingsHubScreen.internalBackCallback = null;
  }

  Widget _getScreen(int index) {
    switch (index) {
      case 7:
        return const PosAccountsScreen();
      case 8:
        return const PosRolePermissionsScreen();
      case 15:
        return const PosPrintTemplatesScreen(embeddedInSettings: true);
      case 16:
        return const PosSellIndustrySettingsHubScreen(embeddedInSettings: true);
      case 17:
        return const PosStoreSettingsHubScreen();
      case 26:
        return const PosEInvoiceSettingsScreen();
      case 18:
        return const PosPrinterSettingsHubScreen();
      case 19:
        return const PosResourceFloorScreen(
          manageMode: true,
          embedded: true,
          showAppBar: false,
        );
      case 22:
        return const PosAppointmentDayScreen();
      case 23:
        return const PosCustomerDisplaySettingsScreen(embeddedInSettings: true);
      case 24:
        return const PosCustomersScreen();
      default:
        final label = _labelForIndex(index) ?? 'Thiết lập';
        return HrmModuleUnavailableScreen(title: label);
    }
  }

  @override
  Widget build(BuildContext context) {
    // App POS không có MainLayout AppBar — tự bọc chrome xanh + nút back.
    final needsOwnChrome = Navigator.of(context).canPop() ||
        !HrmPageChrome.usesMainLayoutAppBar;

    if (_selectedIndex != null) {
      _ensureSubPageCallback();
      final body = _getScreen(_selectedIndex!);
      if (!needsOwnChrome) return body;
      return Scaffold(
        backgroundColor: PosTheme.background,
        appBar: AppBar(
          title: Text(tr(SettingsHubScreen.activeSubPageTitle ?? 'Thiết lập POS')),
          backgroundColor: PosTheme.kiotBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => SettingsHubScreen.goBack(context),
          ),
        ),
        body: body,
      );
    }

    _syncHubChrome();
    final home = ColoredBox(
      color: PosTheme.background,
      child: _buildHubHome(),
    );
    if (!needsOwnChrome) return home;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Thiết lập POS')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: home,
    );
  }

  /// Hub kiểu trang chủ: header + lưới nhóm 1 cột (tự tăng số ô theo bề ngang).
  Widget _buildHubHome() {
    final groups = _orderedHubGroups();
    final hPad = kIsWeb ? 20.0 : 12.0;
    final maxContent = kIsWeb ? 1180.0 : double.infinity;

    final scroll = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(hPad, kIsWeb ? 16 : 8, hPad, 48),
      children: [
        _buildSettingsHeaderCard(),
        if (_storeAgentContact != null) ...[
          const SizedBox(height: 12),
          StoreAgentSupportCard.fromMap(_storeAgentContact!),
        ],
        const SizedBox(height: 12),
        if (_sidebarConfigLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          ...groups.expand((g) {
            if (g.items.isEmpty) return <Widget>[];
            return [
              PosMobileHubSectionGrid(
                title: g.title,
                // Tablet 6 cột làm ô quá cao → khó cuộn thấy Máy in / Print Agent.
                crossAxisCount: kIsWeb
                    ? null
                    : (MediaQuery.sizeOf(context).width >= 860 ? 4 : null),
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
    );

    if (!kIsWeb) return scroll;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContent),
        child: scroll,
      ),
    );
  }

  Widget _buildSettingsHeaderCard() {
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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/logo.png',
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => CircleAvatar(
                radius: 26,
                backgroundColor: PosTheme.kiotBlueLight,
                child: const Icon(Icons.point_of_sale_rounded,
                    color: PosTheme.kiotBlue, size: 26),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('SBOX POS'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: PosTheme.kiotBlue,
                  ),
                ),
                Text(
                  tr(user?.fullName ?? 'Thiết lập POS'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  tr(subtitle),
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
              tooltip: tr('Tùy chỉnh module'),
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
      if (item.moduleCode != null &&
          !PermissionNavigation.canNavigate(permProvider, item.moduleCode)) {
        return false;
      }
      return true;
    }).toList();
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
        title: Text(tr('Thiết lập')),
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
              Text(tr(title),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              Text(tr(message),
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
