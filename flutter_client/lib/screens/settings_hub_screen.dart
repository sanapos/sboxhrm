import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../config/sbox_app_variant.dart';
import '../models/settings_hub_sidebar_config.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../services/settings_hub_sidebar_prefs.dart';
import '../utils/permission_navigation.dart';
import '../utils/settings_hub_catalog.dart';
import '../utils/store_role_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';
import '../widgets/settings_hub_sidebar_config_dialog.dart';
import '../widgets/store_agent_support_card.dart';
import 'account_management_screen.dart';
import 'annual_leave/al_policy.dart';
import 'ai_settings_screen.dart';
import 'allowance_settings_screen.dart';
import 'branch_management_screen.dart';
import 'device_management_settings_screen.dart';
import 'gateway/zk_gateway_list_screen.dart';
import 'holiday_settings_screen.dart';
import 'insurance_settings_screen.dart';
import 'mobile_attendance_settings_screen.dart';
import 'notification_settings_screen.dart';
import 'penalty_settings_screen.dart';
import 'pos/pos_customer_display_settings_screen.dart';
import 'pos/pos_einvoice_settings_screen.dart';
import 'pos/pos_payment_gateway_settings_screen.dart';
import 'pos/pos_cancel_return_settings_screen.dart';
import 'pos/pos_loyalty_settings_screen.dart';
import 'pos/pos_printers_tabs_screen.dart';
import 'pos/pos_qr_table_order_screen.dart';
import 'pos/pos_resource_floor_screen.dart';
import 'pos/pos_sell_industry_settings_screen.dart';
import 'pos/pos_shipping_settings_screen.dart';
import 'pos/pos_store_settings_hub_screen.dart';
import 'pos_print_templates_screen.dart';
import 'product_salary_settings_screen.dart';
import 'role_permissions_screen.dart';
import 'shift_settings_screen.dart';
import 'staffing_quota_settings_screen.dart';
import 'store_access_devices_screen.dart';
import 'system_settings_screen.dart';
import 'tax_settings_screen.dart';

/// Thiết lập SBOX: tìm kiếm, tình trạng từng mục (chưa cấu hình / cần chú ý), mở gần đây,
/// nhóm theo nghiệp vụ. Máy tính: menu nhóm bên trái + nội dung bên phải. Điện thoại: danh sách.
class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  /// MainLayout lắng nghe để hiện tiêu đề + nút back khi mở trang con.
  static final ValueNotifier<int> chromeEpoch = ValueNotifier(0);

  static VoidCallback? _internalBackCallback;
  static String? _activeSubPageTitle;

  /// Callback cho main_layout: đang ở trang con thì «Quay lại» về trang Thiết lập thay vì rời hẳn.
  static VoidCallback? get internalBackCallback => _internalBackCallback;
  static set internalBackCallback(VoidCallback? value) {
    final changed = (_internalBackCallback == null) != (value == null);
    _internalBackCallback = value;
    if (changed) _bumpChrome();
  }

  /// Tiêu đề trang con đang mở (cho thanh trên của main_layout).
  static String? get activeSubPageTitle => _activeSubPageTitle;
  static set activeSubPageTitle(String? value) {
    if (_activeSubPageTitle == value) return;
    _activeSubPageTitle = value;
    _bumpChrome();
  }

  static void _bumpChrome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      chromeEpoch.value++;
    });
  }

  /// Đang mở trang con — main_layout đã có 1 nút back.
  static bool get isEmbeddedSubPage => internalBackCallback != null;

  /// Test: thay danh sách mục được phép (bỏ qua quyền / gói dịch vụ).
  @visibleForTesting
  static List<SettingsHubItemDef>? debugPermittedItems;

  /// Mở thẳng một mục khi điều hướng tới Thiết lập (đặt giá trị kể cả khi đang ở Thiết lập).
  static final ValueNotifier<int?> pendingSubIndex = ValueNotifier<int?>(null);

  /// Mở thẳng một mục theo mã chữ cố định (vd `printers`, `printTemplates`, `device`).
  /// Gọi trước khi điều hướng tới Thiết lập SBOX. Trả về false nếu mã không tồn tại.
  static bool openCode(String code) {
    final item = SettingsHubCatalog.byCode(code);
    if (item == null) return false;
    pendingSubIndex.value = item.index;
    return true;
  }

  /// Quay lại từ trang con Thiết lập.
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
  static const _recentKey = 'settings_hub_recent';

  int? _selectedIndex;
  Map<String, dynamic>? _storeAgentContact;
  SettingsHubSidebarConfig? _sidebarConfig;
  bool _sidebarConfigLoading = true;
  Map<String, Map<String, dynamic>> _health = {};
  List<int> _recent = [];
  String _q = '';
  final _search = TextEditingController();

  bool get _isSuperAdmin =>
      (Provider.of<AuthProvider>(context, listen: false).currentUser?.role ?? '').toLowerCase() == 'superadmin';

  @override
  void initState() {
    super.initState();
    SettingsHubSidebarPrefs.setCache(null);
    final pending = SettingsHubScreen.pendingSubIndex.value;
    if (pending != null) {
      _selectedIndex = pending;
      SettingsHubScreen.activeSubPageTitle = _labelForIndex(pending);
      SettingsHubScreen.internalBackCallback = _requestClose;
      SettingsHubScreen.pendingSubIndex.value = null;
    }
    SettingsHubScreen.pendingSubIndex.addListener(_onPendingSubIndex);
    _loadStoreAgentContact();
    _loadSidebarConfig();
    _loadHealth();
    _loadRecent();
  }

  @override
  void dispose() {
    SettingsHubScreen.pendingSubIndex.removeListener(_onPendingSubIndex);
    SettingsHubScreen.internalBackCallback = null;
    SettingsHubScreen.activeSubPageTitle = null;
    _search.dispose();
    super.dispose();
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
        setState(() => _storeAgentContact = Map<String, dynamic>.from(res['data'] as Map));
      }
    } catch (_) {}
  }

  Future<void> _loadHealth() async {
    if (_isSuperAdmin) return;
    try {
      final r = await ApiService().getSettingsHealth();
      if (!mounted || r['isSuccess'] != true || r['data'] is! List) return;
      setState(() => _health = {
            for (final x in (r['data'] as List).whereType<Map>()) '${x['key']}': Map<String, dynamic>.from(x),
          });
    } catch (_) {}
  }

  Future<void> _loadRecent() async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = p.getStringList(_recentKey) ?? const [];
      if (!mounted) return;
      setState(() => _recent = list
          .map(int.tryParse)
          .whereType<int>()
          .map(SettingsHubCatalog.canonicalIndex)
          .toSet()
          .toList());
    } catch (_) {}
  }

  Future<void> _remember(int index) async {
    final i = SettingsHubCatalog.canonicalIndex(index);
    _recent = [i, ..._recent.where((x) => x != i)].take(6).toList();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_recentKey, _recent.map((e) => '$e').toList());
    } catch (_) {}
  }

  void _onPendingSubIndex() {
    final idx = SettingsHubScreen.pendingSubIndex.value;
    if (idx != null && mounted) {
      _openSubPage(idx);
      SettingsHubScreen.pendingSubIndex.value = null;
    }
  }

  String? _labelForIndex(int index) => SettingsHubCatalog.byIndex(index)?.label;

  bool _canCustomizeSidebar() {
    final role = (Provider.of<AuthProvider>(context, listen: false).currentUser?.role ?? '').toLowerCase();
    if (role == 'superadmin' || role == 'admin') return true;
    return Provider.of<PermissionProvider>(context, listen: false).canEdit('SystemSettings');
  }

  /// POS độc lập: Super Admin thấy bộ POS rút gọn; cửa hàng thấy mọi mục gói đã chọn.
  List<SettingsHubItemDef> _catalogItems() {
    final role = (Provider.of<AuthProvider>(context, listen: false).user?.role ?? '').toLowerCase();
    if (SboxAppVariant.standalonePos && role == 'superadmin') return SettingsHubCatalog.itemsForCurrentApp;
    return SettingsHubCatalog.allItems;
  }

  List<SettingsHubItemDef> _permittedHubItems() => SettingsHubScreen.debugPermittedItems ?? _filterItems(_catalogItems());

  List<SettingsHubItemDef> _orderedHubItems() => SettingsHubCatalog.applyConfig(_permittedHubItems(), _sidebarConfig);

  bool _isPermitted(int index) {
    final i = SettingsHubCatalog.canonicalIndex(index);
    return _permittedHubItems().any((x) => x.index == i);
  }

  Future<void> _openSidebarConfigDialog() async {
    final permitted = _permittedHubItems();
    if (permitted.isEmpty) return;
    final initial = _sidebarConfig ?? SettingsHubSidebarConfig.defaults(SettingsHubCatalog.defaultOrder);
    final saved = await SettingsHubSidebarConfigDialog.show(
      context,
      initialConfig: initial,
      permittedItems: permitted,
      onSave: SettingsHubSidebarPrefs.save,
    );
    if (!mounted || saved == null) return;
    setState(() => _sidebarConfig = saved);
    final visibleIds = SettingsHubCatalog.applyConfig(permitted, saved).map((e) => e.index).toSet();
    if (_selectedIndex != null && !visibleIds.contains(_selectedIndex)) _closeSubPage();
  }

  void _openSubPage(int index) {
    setState(() {
      _selectedIndex = index;
      SettingsHubScreen.activeSubPageTitle = _labelForIndex(index);
      SettingsHubScreen.internalBackCallback = _requestClose;
    });
    _remember(index);
  }

  /// Đóng trang con — hỏi trước nếu trang còn thay đổi chưa lưu.
  Future<void> _requestClose() async {
    if (await SettingsLeaveGuard.canLeave()) _closeSubPage();
  }

  /// Chuyển sang mục khác từ menu trái — hỏi trước nếu trang hiện tại chưa lưu.
  Future<void> _requestOpen(int index) async {
    if (_selectedIndex == index) return;
    if (await SettingsLeaveGuard.canLeave()) _openSubPage(index);
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
    _loadHealth();
  }

  void _ensureSubPageCallback() {
    final index = _selectedIndex;
    if (index == null) return;
    SettingsHubScreen.activeSubPageTitle = _labelForIndex(index);
    SettingsHubScreen.internalBackCallback ??= _requestClose;
  }

  void _syncHubChrome() {
    SettingsHubScreen.activeSubPageTitle = null;
    SettingsHubScreen.internalBackCallback = null;
  }

  Widget _getScreen(int index) {
    // Mở thẳng (lối tắt, thông báo) cũng phải đúng quyền / gói dịch vụ.
    if (!_isPermitted(index)) {
      return const _SettingsAccessDeniedScreen(
        title: 'Không có quyền truy cập',
        message: 'Tài khoản của bạn chưa được cấp quyền mục thiết lập này, hoặc gói dịch vụ chưa có chức năng này.',
      );
    }
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
      case 10:
        return const ProductSalarySettingsScreen();
      case 11:
        return const AiSettingsScreen();
      case 12:
        return const DeviceManagementSettingsScreen();
      case 13:
        return const BranchManagementScreen();
      case 14:
        return const StaffingQuotaSettingsScreen();
      case 15:
        return const PosPrintTemplatesScreen(embeddedInSettings: true);
      case 16:
        return const PosSellIndustrySettingsScreen(embeddedInSettings: true);
      case 17:
        return const PosStoreSettingsHubScreen();
      case 18:
        return const PosPrintersTabsScreen();
      case 19:
        return const PosResourceFloorScreen(manageMode: true, embedded: true, showAppBar: false);
      case 21:
        return const NotificationSettingsScreen();
      case 23:
        return const PosCustomerDisplaySettingsScreen(embeddedInSettings: true);
      case 25:
        return const ZkGatewayListScreen();
      case 26:
        return const PosEInvoiceSettingsScreen();
      case 27:
        return const PosShippingSettingsScreen();
      case 28:
        return const PosPaymentGatewaySettingsScreen();
      case 29:
        return const PosPrintersTabsScreen(cloudFirst: true);
      case 30:
        return const StoreAccessDevicesScreen();
      case 31:
        return const AnnualLeavePolicyScreen();
      case 32:
        return const PosQrTableOrderScreen();
      case 33:
        return const PosLoyaltySettingsScreen();
      case 34:
        return const PosCancelReturnSettingsScreen();
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Chỉ tự vẽ thanh tiêu đề khi shell (MainLayout) không có thanh tiêu đề trên cùng route.
    final ownChrome = !HrmShellChrome.isVisible(context);
    final wide = MediaQuery.of(context).size.width >= 1100;
    final sub = _selectedIndex;
    if (sub != null) _ensureSubPageCallback();
    if (sub == null) _syncHubChrome();

    Widget content;
    if (wide) {
      content = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 290, child: _sideNav()),
        const VerticalDivider(width: 1, color: SboxColors.border),
        Expanded(child: sub == null ? _home(wide) : _getScreen(sub)),
      ]);
    } else {
      content = sub == null ? _home(wide) : _getScreen(sub);
    }
    content = ColoredBox(color: PosTheme.background, child: content);
    if (!ownChrome) return content;
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr(sub == null ? 'Thiết lập SBOX' : (SettingsHubScreen.activeSubPageTitle ?? 'Thiết lập SBOX'))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: sub == null ? () => Navigator.maybePop(context) : _requestClose,
        ),
      ),
      body: content,
    );
  }

  // ─── Tình trạng ────────────────────────────────────────────────

  Map<String, dynamic>? _healthOf(SettingsHubItemDef i) => i.healthKey == null ? null : _health[i.healthKey];

  (SboxTone, IconData)? _toneOf(String? status) => switch (status) {
        'todo' => (SboxTone.warning, Icons.radio_button_unchecked_rounded),
        'warn' => (SboxTone.danger, Icons.error_outline_rounded),
        'ok' => (SboxTone.success, Icons.check_circle_rounded),
        'info' => (SboxTone.neutral, Icons.info_outline_rounded),
        _ => null,
      };

  Widget? _statusChip(SettingsHubItemDef i) {
    final h = _healthOf(i);
    final t = _toneOf(h?['status']?.toString());
    if (h == null || t == null) return null;
    return SboxStatusChip(label: '${h['text'] ?? ''}', tone: t.$1, icon: t.$2);
  }

  // ─── Menu bên trái (máy tính) ──────────────────────────────────

  Widget _sideNav() {
    final ordered = _orderedHubItems();
    final groups = SettingsHubCatalog.groupOrderedItems(SettingsHubCatalog.search(ordered, _q));
    return Material(
      color: SboxColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Trang tổng quan đã có ô tìm kiếm lớn; chỉ hiện ô này khi đang mở một trang con.
        if (_selectedIndex != null)
          Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 8), child: _searchField(dense: true))
        else
          const SizedBox(height: 10),
        Expanded(
          child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
            _navTile(
              icon: Icons.space_dashboard_outlined,
              label: 'Tổng quan thiết lập',
              selected: _selectedIndex == null,
              onTap: _requestClose,
            ),
            for (final g in groups) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
                child: Text(tr(g.title).toUpperCase(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: SboxColors.slate400, letterSpacing: 0.4)),
              ),
              for (final i in g.items)
                _navTile(
                  icon: i.icon,
                  label: i.label,
                  selected: _selectedIndex != null && SettingsHubCatalog.canonicalIndex(_selectedIndex!) == i.index,
                  status: _healthOf(i)?['status']?.toString(),
                  onTap: () => _requestOpen(i.index),
                ),
            ],
          ]),
        ),
        if (_canCustomizeSidebar())
          Padding(
            padding: const EdgeInsets.all(10),
            child: TextButton.icon(
              onPressed: _sidebarConfigLoading ? null : _openSidebarConfigDialog,
              icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
              label: Text(tr('Sắp xếp / ẩn mục')),
            ),
          ),
      ]),
    );
  }

  Widget _navTile({required IconData icon, required String label, required bool selected, required VoidCallback onTap, String? status}) {
    final dot = switch (status) {
      'todo' => SboxColors.warning,
      'warn' => SboxColors.danger,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? SboxColors.brand50 : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(icon, size: 19, color: selected ? SboxColors.brand700 : SboxColors.slate500),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr(label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected ? SboxColors.brand700 : SboxColors.slate800)),
              ),
              if (dot != null) Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _searchField({bool dense = false}) => TextField(
        controller: _search,
        onChanged: (v) => setState(() => _q = v),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _q.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() {
                    _q = '';
                    _search.clear();
                  }),
                ),
          hintText: tr(dense ? 'Tìm thiết lập' : 'Tìm thiết lập: VAT, BHXH, máy in, ca đêm…'),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SboxColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: SboxColors.border)),
        ),
      );

  // ─── Trang tổng quan ───────────────────────────────────────────

  Widget _home(bool wide) {
    final ordered = _orderedHubItems();
    final hPad = wide ? 28.0 : 12.0;
    final children = <Widget>[
      _header(wide),
      if (_storeAgentContact != null) ...[
        const SizedBox(height: 12),
        StoreAgentSupportCard.fromMap(_storeAgentContact!),
      ],
      const SizedBox(height: 14),
    ];
    if (_sidebarConfigLoading) {
      children.add(const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator(strokeWidth: 2))));
    } else if (_q.trim().isNotEmpty) {
      final found = SettingsHubCatalog.search(ordered, _q);
      children.add(found.isEmpty
          ? SboxEmptyState(icon: Icons.search_off_rounded, title: 'Không tìm thấy thiết lập', message: 'Thử từ khóa khác, ví dụ: VAT, BHXH, máy in.')
          : _grid(found, wide));
    } else {
      final todo = _checklist(ordered);
      if (todo != null) children.addAll([todo, const SizedBox(height: 14)]);
      final recent = _recent.map((i) => ordered.where((x) => x.index == i).firstOrNull).whereType<SettingsHubItemDef>().toList();
      if (recent.isNotEmpty) children.addAll([_recentRow(recent), const SizedBox(height: 14)]);
      for (final g in SettingsHubCatalog.groupOrderedItems(ordered)) {
        final meta = SettingsHubCatalog.groupOf(g.title);
        children.addAll([
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 0, 8),
            child: Row(children: [
              Icon(meta.icon, size: 18, color: meta.color),
              const SizedBox(width: 8),
              Text(tr(g.title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SboxColors.slate800)),
            ]),
          ),
          _grid(g.items, wide),
          const SizedBox(height: 10),
        ]);
      }
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, wide ? 20 : 10, hPad, 32),
      children: [
        Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1180), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
      ],
    );
  }

  Widget _header(bool wide) {
    final title = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(tr('Thiết lập SBOX'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
      Text(tr('Mọi cấu hình của cửa hàng: bán hàng, thanh toán, in ấn, nhân sự, lương, người dùng'), style: const TextStyle(color: SboxColors.slate500)),
    ]);
    final customize = _canCustomizeSidebar() && !wide
        ? IconButton(
            tooltip: tr('Sắp xếp / ẩn mục'),
            onPressed: _sidebarConfigLoading ? null : _openSidebarConfigDialog,
            icon: const Icon(Icons.dashboard_customize_outlined, color: SboxColors.brand600),
          )
        : null;
    if (wide) {
      return Row(children: [Expanded(child: title), SizedBox(width: 420, child: _searchField())]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Expanded(child: title), if (customize != null) customize]),
      const SizedBox(height: 10),
      _searchField(),
    ]);
  }

  /// «Việc cần làm»: mục chưa cấu hình / cần chú ý + tiến độ.
  Widget? _checklist(List<SettingsHubItemDef> items) {
    final tracked = items.where((i) => _healthOf(i) != null).toList();
    if (tracked.isEmpty) return null;
    final pending = tracked.where((i) => ['todo', 'warn'].contains(_healthOf(i)!['status'])).toList()
      ..sort((a, b) => (_healthOf(a)!['status'] == 'warn' ? 0 : 1).compareTo(_healthOf(b)!['status'] == 'warn' ? 0 : 1));
    final done = tracked.length - pending.length;
    return SboxCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(pending.isEmpty ? Icons.verified_rounded : Icons.checklist_rounded,
              color: pending.isEmpty ? SboxColors.success : SboxColors.brand600),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr(pending.isEmpty ? 'Các thiết lập chính đã sẵn sàng' : 'Việc cần làm (${pending.length})'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          Text('$done/${tracked.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.slate600)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: tracked.isEmpty ? 0 : done / tracked.length,
            minHeight: 6,
            backgroundColor: SboxColors.slate100,
            color: SboxColors.success,
          ),
        ),
        for (final i in pending.take(6))
          InkWell(
            onTap: () => _openSubPage(i.index),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(i.icon, size: 20, color: SboxColors.slate500),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(tr(i.label), style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (_statusChip(i) != null) _statusChip(i)!,
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _recentRow(List<SettingsHubItemDef> recent) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Mở gần đây'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: SboxColors.slate500)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in recent)
            ActionChip(
              avatar: Icon(i.icon, size: 17, color: SboxColors.brand600),
              label: Text(tr(i.label)),
              onPressed: () => _openSubPage(i.index),
            ),
        ]),
      ]);

  Widget _grid(List<SettingsHubItemDef> items, bool wide) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth >= 1000 ? 3 : (box.maxWidth >= 620 ? 2 : 1);
        final w = (box.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [for (final i in items) SizedBox(width: w, child: _card(i))]);
      });

  Widget _card(SettingsHubItemDef i) {
    final g = SettingsHubCatalog.groupOf(i.groupTitle);
    final chip = _statusChip(i);
    return SboxCard(
      onTap: () => _openSubPage(i.index),
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: g.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
          child: Icon(i.icon, color: g.color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(i.label), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: SboxColors.slate900)),
            const SizedBox(height: 2),
            Text(tr(i.desc), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
            if (chip != null) ...[const SizedBox(height: 8), chip],
          ]),
        ),
      ]),
    );
  }

  // ─── Quyền / gói dịch vụ ───────────────────────────────────────

  List<SettingsHubItemDef> _filterItems(List<SettingsHubItemDef> items) {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final role = (authUser?.role ?? '').toLowerCase();
    if (role == 'superadmin') return items;
    final bypassPackage = StoreRoleHelper.bypassesPackageFilter(authUser?.role);
    final permProvider = Provider.of<PermissionProvider>(context, listen: false);
    final allowedModules = authUser?.allowedModules;
    bool allowed(String? code) =>
        PermissionNavigation.isAllowedByPackageOrRole(
          code,
          allowedModules: allowedModules,
          perm: permProvider,
          bypassPackageFilter: bypassPackage,
        ) &&
        (code == null || permProvider.canViewExact(code));
    return items.where((item) {
      // Mục có mã thay thế (Máy in = thiết bị hoặc cloud): đủ một mã là thấy; từng tab tự lọc quyền.
      if (item.altModuleCodes.isNotEmpty) {
        return [item.moduleCode, ...item.altModuleCodes].any(allowed);
      }
      if (!PermissionNavigation.isAllowedByPackageOrRole(
        item.moduleCode,
        allowedModules: allowedModules,
        perm: permProvider,
        bypassPackageFilter: bypassPackage,
      )) {
        return false;
      }
      if (item.packageModule != null &&
          !PermissionNavigation.isAllowedByPackageOrRole(
            item.packageModule,
            allowedModules: allowedModules,
            perm: permProvider,
            bypassPackageFilter: bypassPackage,
          )) {
        return false;
      }
      // Tick đúng chức năng trên Phân quyền — không suy từ PosSell.
      if (item.moduleCode != null && !permProvider.canViewExact(item.moduleCode!)) return false;
      return true;
    }).toList();
  }
}

class _SettingsAccessDeniedScreen extends StatelessWidget {
  const _SettingsAccessDeniedScreen({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline_rounded, size: 56, color: SboxColors.slate400),
          const SizedBox(height: 12),
          Text(tr(title), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
          const SizedBox(height: 8),
          Text(tr(message), textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: SboxColors.slate500)),
        ]),
      ),
    );
  }
}
