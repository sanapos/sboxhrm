import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../widgets/hrm_collapsible_overview.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/employee_search_picker.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRole = 'all';
  String _selectedStatus = 'all';
  /// all | missing_or_resigned
  String _selectedHrFilter = 'all';
  bool _showOverviewPanel = true;
  /// Renders two fields side-by-side on desktop, stacked on mobile.
  List<Widget> _buildFieldPair(
      {required bool isMobile, required Widget first, required Widget second}) {
    if (isMobile) {
      return [
        first,
        const SizedBox(height: 12),
        second,
        const SizedBox(height: 12)
      ];
    }
    return [
      Row(children: [
        Expanded(child: first),
        const SizedBox(width: 16),
        Expanded(child: second)
      ]),
      const SizedBox(height: 16),
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getAccounts(),
        _apiService.getEmployeesForSelect(pageSize: 10000),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(results[0]);
        _employees = List<Map<String, dynamic>>.from(results[1]);
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAccounts() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getAccounts(),
        _apiService.getEmployeesForSelect(pageSize: 10000),
      ]);
      if (!mounted) return;
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(results[0]);
        _employees = List<Map<String, dynamic>>.from(results[1]);
      });
    } catch (e) {
      debugPrint('Error loading accounts: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Mã HR đã có tài khoản (theo employeeId trên account + applicationUserId trên hồ sơ).
  Set<String> get _registeredEmployeeIds {
    final ids = <String>{};
    for (final acc in _accounts) {
      final eid = acc['employeeId']?.toString();
      if (eid != null && eid.isNotEmpty) ids.add(eid);
    }
    return ids;
  }

  List<Map<String, dynamic>> get _employeesAvailableForAccount {
    final registered = _registeredEmployeeIds;
    return _employees.where((emp) {
      final id = emp['id']?.toString() ?? '';
      if (id.isEmpty) return false;
      if (registered.contains(id)) return false;
      final appUserId = emp['applicationUserId']?.toString() ?? '';
      if (appUserId.isNotEmpty) return false;
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredAccounts {
    return _accounts.where((account) {
      final fullName = (account['fullName'] ??
              '${account['lastName'] ?? ''} ${account['firstName'] ?? ''}')
          .toString()
          .trim();
      final matchesSearch = _searchQuery.isEmpty ||
          fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (account['userName']
                  ?.toString()
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ??
              false) ||
          (account['email']
                  ?.toString()
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ??
              false);

      final roles = account['roles'] as List<dynamic>? ?? [];
      final role = roles.isNotEmpty ? roles.first.toString() : '';
      final matchesRole = _selectedRole == 'all' || role == _selectedRole;

      final isActive = account['isActive'] as bool? ?? true;
      final matchesStatus = _selectedStatus == 'all' ||
          (_selectedStatus == 'active' && isActive) ||
          (_selectedStatus == 'inactive' && !isActive);

      final hrIssue = account['isEmployeeMissingOrResigned'] == true;
      final matchesHr = _selectedHrFilter == 'all' ||
          (_selectedHrFilter == 'missing_or_resigned' && hrIssue);

      return matchesSearch && matchesRole && matchesStatus && matchesHr;
    }).toList();
  }

  String? _hrIssueLabel(Map<String, dynamic> account) {
    if (account['isEmployeeMissing'] == true) return 'Không còn hồ sơ NS';
    if (account['isEmployeeResigned'] == true) return 'Đã nghỉ việc';
    if (account['isEmployeeMissingOrResigned'] == true) {
      return 'Không còn HS / Nghỉ việc';
    }
    return null;
  }

  int get _totalAccounts => _accounts.length;
  int get _activeAccounts =>
      _accounts.where((a) => a['isActive'] == true).length;
  int get _adminAccounts => _accounts.where((a) {
        final roles = (a['roles'] as List<dynamic>? ?? [])
            .map((r) => r.toString())
            .toList();
        return roles.contains('Admin');
      }).length;
  int get _onlineToday => 0;

  void _clearFilters() {
    setState(() {
      _searchQuery = '';
      _selectedRole = 'all';
      _selectedStatus = 'all';
      _selectedHrFilter = 'all';
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 900;

    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: HrmPageChrome.appBar(
        title: 'Quản lý Tài khoản',
      ),
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: HrmSettingsMobileKit.active(context)
                  ? HrmSettingsMobileKit.pagePadding(context)
                  : EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (HrmSettingsMobileKit.active(context)) ...[
                    HrmSettingsSearchToolbar(
                      search: _buildAccountSearchField(),
                      actions: [
                        if (_perm.canCreate('UserManagement') &&
                            _employeesAvailableForAccount.isNotEmpty)
                          HrmSettingsAddButton(
                            label: 'Đăng ký hàng loạt',
                            icon: Icons.group_add,
                            compact: true,
                            onPressed: () => _showBulkAccountDialog(),
                          ),
                        if (_perm.canCreate('UserManagement'))
                          HrmSettingsAddButton(
                            label: 'Thêm tài khoản',
                            icon: Icons.person_add,
                            compact: true,
                            onPressed: () => _showAccountDialog(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (!HrmSettingsMobileKit.active(context))
                    Row(
                      children: [
                        if (!HrmPageChrome.isEmbedded) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF71717A).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.group,
                              color: Color(0xFF71717A), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Quản lý Tài khoản'),
                                style: TextStyle(
                                  color: HrmPageChrome.primaryNavy,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(tr('Quản lý tài khoản người dùng hệ thống'),
                                style: TextStyle(
                                    color: Color(0xFF71717A), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (_perm.canCreate('UserManagement')) ...[
                        if (_employeesAvailableForAccount.isNotEmpty) ...[
                          if (Responsive.isMobile(context))
                            IconButton(
                              onPressed: () => _showBulkAccountDialog(),
                              icon: const Icon(Icons.group_add,
                                  color: HrmPageChrome.primaryNavy, size: 22),
                              tooltip: tr('Đăng ký hàng loạt'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: () => _showBulkAccountDialog(),
                              icon: const Icon(Icons.group_add, size: 18),
                              label: Text(tr('Đăng ký hàng loạt')),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: HrmPageChrome.primaryNavy,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                              ),
                            ),
                          const SizedBox(width: 8),
                        ],
                        if (Responsive.isMobile(context))
                          IconButton(
                            onPressed: () => _showAccountDialog(),
                            icon: const Icon(Icons.person_add,
                                color: HrmPageChrome.primaryNavy, size: 22),
                            tooltip: tr('Thêm tài khoản'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => _showAccountDialog(),
                            icon: const Icon(Icons.person_add, size: 18),
                            label: Text(tr('Thêm tài khoản')),
                            style: FilledButton.styleFrom(
                              backgroundColor: HrmPageChrome.primaryNavy,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                            ),
                          ),
                      ],
                    ],
                  ),
                  if (!HrmSettingsMobileKit.active(context))
                    const SizedBox(height: 24),

                  HrmCollapsibleOverview(
                    expanded: _showOverviewPanel,
                    onToggle: () => setState(
                        () => _showOverviewPanel = !_showOverviewPanel),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HrmPageChrome.horizontalStatCards(
                    minCardWidth: 128,
                    cards: [
                      _buildStatCard(Icons.group, '$_totalAccounts',
                          'Tổng TK', HrmPageChrome.primaryNavy),
                      _buildStatCard(Icons.check_circle, '$_activeAccounts',
                          'Hoạt động', HrmPageChrome.primaryNavy),
                      _buildStatCard(Icons.admin_panel_settings,
                          '$_adminAccounts', 'Quản trị', HrmPageChrome.primaryNavy),
                      _buildStatCard(Icons.login, '$_onlineToday', 'Online',
                          HrmPageChrome.primaryNavy),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Filter bar — 1 hàng cuộn ngang (thống nhất trang chức năng khác)
                  if (HrmSettingsMobileKit.active(context)) ...[
                    _buildAccountFilterChipBar(),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // Search input
                          SizedBox(
                            width: isWideScreen ? 300 : double.infinity,
                            height: 44,
                            child: TextField(
                              style: const TextStyle(
                                  color: Color(0xFF18181B), fontSize: 14),
                              decoration: InputDecoration(
                                hintText: tr('Tìm theo tên hoặc username...'),
                                hintStyle: const TextStyle(
                                    color: Color(0xFFA1A1AA), fontSize: 14),
                                prefixIcon: const Icon(Icons.search,
                                    color: Color(0xFFA1A1AA), size: 20),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                filled: true,
                                fillColor: const Color(0xFFFAFAFA),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: HrmPageChrome.primaryNavy),
                                ),
                              ),
                              onChanged: (value) =>
                                  setState(() => _searchQuery = value),
                            ),
                          ),
                          // Role dropdown
                          SizedBox(
                            width: isWideScreen ? 200 : double.infinity,
                            height: 44,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedRole,
                              dropdownColor: Colors.white,
                              isExpanded: true,
                              style: const TextStyle(
                                  color: Color(0xFF18181B), fontSize: 14),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.person_outline,
                                    color: Color(0xFF71717A), size: 18),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: HrmPageChrome.primaryNavy),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: [
                                DropdownMenuItem(
                                    value: 'all',
                                    child: Text(tr('Tất cả vai trò'))),
                                DropdownMenuItem(
                                    value: 'Admin',
                                    child: Text(tr('Quản trị viên'))),
                                DropdownMenuItem(
                                    value: 'Director', child: Text(tr('Giám đốc'))),
                                DropdownMenuItem(
                                    value: 'Manager', child: Text(tr('Quản lý'))),
                                DropdownMenuItem(
                                    value: 'DepartmentHead',
                                    child: Text(tr('Trưởng phòng'))),
                                DropdownMenuItem(
                                    value: 'Accountant',
                                    child: Text(tr('Kế toán'))),
                                DropdownMenuItem(
                                    value: 'Cashier',
                                    child: Text(tr('Thu ngân'))),
                                DropdownMenuItem(
                                    value: 'Waiter',
                                    child: Text(tr('Order'))),
                                DropdownMenuItem(
                                    value: 'Employee',
                                    child: Text(tr('Nhân viên'))),
                                DropdownMenuItem(
                                    value: 'User', child: Text(tr('Người dùng'))),
                              ],
                              onChanged: (value) => setState(
                                  () => _selectedRole = value ?? 'all'),
                            ),
                          ),
                          // Status dropdown
                          SizedBox(
                            width: isWideScreen ? 200 : double.infinity,
                            height: 44,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedStatus,
                              dropdownColor: Colors.white,
                              isExpanded: true,
                              style: const TextStyle(
                                  color: Color(0xFF18181B), fontSize: 14),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.toggle_on_outlined,
                                    color: Color(0xFF71717A), size: 18),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: HrmPageChrome.primaryNavy),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: [
                                DropdownMenuItem(
                                    value: 'all',
                                    child: Text(tr('Tất cả trạng thái'))),
                                DropdownMenuItem(
                                    value: 'active',
                                    child: Text(tr('Đang hoạt động'))),
                                DropdownMenuItem(
                                    value: 'inactive',
                                    child: Text(tr('Ngừng hoạt động'))),
                              ],
                              onChanged: (value) => setState(
                                  () => _selectedStatus = value ?? 'all'),
                            ),
                          ),
                          // HR profile filter
                          SizedBox(
                            width: isWideScreen ? 260 : double.infinity,
                            height: 44,
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedHrFilter,
                              dropdownColor: Colors.white,
                              isExpanded: true,
                              style: const TextStyle(
                                  color: Color(0xFF18181B), fontSize: 14),
                              decoration: InputDecoration(
                                prefixIcon: const Icon(
                                    Icons.badge_outlined,
                                    color: Color(0xFF71717A),
                                    size: 18),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE4E4E7)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: HrmPageChrome.primaryNavy),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: [
                                DropdownMenuItem(
                                    value: 'all',
                                    child: Text(tr('Tất cả hồ sơ NS'))),
                                DropdownMenuItem(
                                    value: 'missing_or_resigned',
                                    child: Text(tr('Không còn HS / Nghỉ việc'))),
                              ],
                              onChanged: (value) => setState(
                                  () => _selectedHrFilter = value ?? 'all'),
                            ),
                          ),
                          // Clear filter button
                          OutlinedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off, size: 18),
                            label: Text(tr('Xóa lọc')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF71717A),
                              side: const BorderSide(color: Color(0xFFE4E4E7)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Account table / card list
                  _filteredAccounts.isEmpty
                      ? const Center(
                          child: EmptyState(
                            icon: Icons.manage_accounts,
                            title: 'Không tìm thấy tài khoản',
                            description:
                                'Thử thay đổi bộ lọc hoặc thêm tài khoản mới',
                          ),
                        )
                      : Responsive.isMobile(context)
                          ? _buildMobileAccountList()
                          : Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                        const Color(0xFFF4F4F5)),
                                    dataRowMinHeight: 52,
                                    dataRowMaxHeight: 56,
                                    columnSpacing: 24,
                                    horizontalMargin: 16,
                                    headingTextStyle: const TextStyle(
                                      color: Color(0xFF71717A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    columns: [
                                      DataColumn(label: Text(tr('#'))),
                                      DataColumn(label: Text(tr('Nhân viên'))),
                                      DataColumn(label: Text(tr('Email'))),
                                      DataColumn(label: Text(tr('SĐT'))),
                                      DataColumn(label: Text(tr('Vai trò'))),
                                      DataColumn(label: Text(tr('Trạng thái'))),
                                      DataColumn(label: Text(tr('Đăng nhập cuối'))),
                                      DataColumn(label: Text(tr('Thao tác'))),
                                    ],
                                    rows: List.generate(
                                        _filteredAccounts.length, (index) {
                                      final account = _filteredAccounts[index];
                                      return _buildAccountRow(account, index);
                                    }),
                                  ),
                                ),
                              ),
                            ),
                ],
              ),
            ),
    );
  }

  Widget _buildHrIssueBadge(Map<String, dynamic> account,
      {double fontSize = 10}) {
    final label = _hrIssueLabel(account);
    if (label == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: HrmPageChrome.chipLight.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr(label),
        style: TextStyle(
          color: HrmPageChrome.chipDark,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  DataRow _buildAccountRow(Map<String, dynamic> account, int index) {
    final isActive = account['isActive'] as bool? ?? true;
    final roles = account['roles'] as List<dynamic>? ?? [];
    final role = roles.isNotEmpty ? roles.first.toString() : 'Employee';
    final lastLogin = DateTime.tryParse(account['lastLoginAt'] ?? '');
    final fullName = (account['fullName'] ??
            '${account['lastName'] ?? ''} ${account['firstName'] ?? ''}')
        .toString()
        .trim();
    final initials = fullName
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join();
    final roleInfo = _getRoleDisplayInfo(role);

    return DataRow(
      cells: [
        DataCell(Text(tr('${index + 1}'),
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: (roleInfo['color'] as Color).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                  child: Text(tr(initials),
                      style: TextStyle(
                          color: roleInfo['color'] as Color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(fullName),
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(tr('@${account['userName'] ?? ''}'),
                    style: const TextStyle(
                        color: Color(0xFFA1A1AA), fontSize: 11)),
                _buildHrIssueBadge(account, fontSize: 10),
              ],
            ),
          ],
        )),
        DataCell(Text(tr(account['email'] ?? ''),
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
        DataCell(Text(tr(account['phoneNumber'] ?? ''),
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
        DataCell(HrmBrandChip(label: roleInfo['label'] as String)),
        DataCell(HrmBrandChip(
            label: isActive ? 'Hoạt động' : 'Ngừng hoạt động')),
        DataCell(Text(
          tr(lastLogin != null ? _formatDate(lastLogin) : '—'),
          style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
        )),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_perm.canEdit('UserManagement'))
              IconButton(
                onPressed: () => _showChangePasswordDialog(account),
                icon: const Icon(Icons.lock_reset, size: 18),
                color: HrmPageChrome.primaryNavy,
                tooltip: tr('Đổi mật khẩu'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (_perm.canEdit('UserManagement'))
              IconButton(
                onPressed: () => _showAccountDialog(account: account),
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: const Color(0xFF71717A),
                tooltip: tr('Sửa'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (_perm.canEdit('UserManagement') && !_isSelfOrOwner(account))
              IconButton(
                onPressed: () => _toggleAccountActive(account),
                icon: Icon(
                  isActive
                      ? Icons.person_off_outlined
                      : Icons.person_outline,
                  size: 18,
                ),
                color: isActive
                    ? HrmPageChrome.chipLight
                    : const Color(0xFF22C55E),
                tooltip: tr(isActive ? 'Vô hiệu hóa' : 'Kích hoạt lại'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            if (_perm.canDelete('UserManagement') && !_isSelfOrOwner(account))
              IconButton(
                onPressed: () => _deleteAccount(account),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: const Color(0xFFEF4444),
                tooltip: tr('Xóa'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        )),
      ],
    );
  }

  Widget _buildStatCard(
      IconData icon, String value, String label, Color color) {
    return HrmStatSummaryCard(
      icon: icon,
      value: value,
      label: label,
      color: color,
    );
  }

  /// Một hàng lọc ngang — vai trò / trạng thái / HS, không xếp 3 dòng.
  Widget _buildAccountFilterChipBar() {
    Widget chip(String label, bool selected, VoidCallback onTap) {
      final border = HrmPageChrome.chip.withValues(alpha: 0.45);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? HrmPageChrome.chip : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: selected ? HrmPageChrome.chip : border),
              ),
              child: Text(
                tr(label),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : HrmPageChrome.chip,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget sep() => Container(
          margin: const EdgeInsets.only(right: 8, left: 2),
          width: 1,
          height: 18,
          color: const Color(0xFFE4E4E7),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          chip('Tất cả', _selectedRole == 'all',
              () => setState(() => _selectedRole = 'all')),
          chip('Quản trị', _selectedRole == 'Admin',
              () => setState(() => _selectedRole = 'Admin')),
          chip('Quản lý', _selectedRole == 'Manager',
              () => setState(() => _selectedRole = 'Manager')),
          chip('Nhân viên', _selectedRole == 'Employee',
              () => setState(() => _selectedRole = 'Employee')),
          sep(),
          chip('Đang hoạt động', _selectedStatus == 'active',
              () => setState(() => _selectedStatus = 'active')),
          chip('Ngừng', _selectedStatus == 'inactive',
              () => setState(() => _selectedStatus = 'inactive')),
          if (_selectedStatus != 'all')
            chip('Mọi TT', false,
                () => setState(() => _selectedStatus = 'all')),
          sep(),
          chip(
              'Không còn HS / Nghỉ việc',
              _selectedHrFilter == 'missing_or_resigned',
              () => setState(() => _selectedHrFilter =
                  _selectedHrFilter == 'missing_or_resigned'
                      ? 'all'
                      : 'missing_or_resigned')),
          chip('Xóa lọc', false, _clearFilters),
        ],
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> _getRoleDisplayInfo(String role) {
    switch (role) {
      case 'Admin':
        return {'label': 'Quản trị viên', 'color': HrmPageChrome.chipDark};
      case 'Director':
        return {'label': 'Giám đốc', 'color': HrmPageChrome.chipMid};
      case 'Manager':
        return {'label': 'Quản lý', 'color': HrmPageChrome.primaryNavy};
      case 'DepartmentHead':
        return {'label': 'Trưởng phòng', 'color': HrmPageChrome.chipMid};
      case 'Accountant':
        return {'label': 'Kế toán', 'color': HrmPageChrome.primaryNavy};
      case 'Cashier':
        return {'label': 'Thu ngân', 'color': HrmPageChrome.chip};
      case 'Waiter':
        return {'label': 'Order', 'color': HrmPageChrome.chipMid};
      case 'Employee':
        return {'label': 'Nhân viên', 'color': HrmPageChrome.primaryNavy};
      case 'User':
      default:
        return {'label': 'Người dùng', 'color': const Color(0xFF71717A)};
    }
  }

  Widget _buildAccountSearchField() {
    return TextField(
      style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
      decoration: InputDecoration(
        hintText: tr('Tìm theo tên hoặc username...'),
        hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
        prefixIcon:
            const Icon(Icons.search, color: Color(0xFFA1A1AA), size: 20),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: HrmPageChrome.primaryNavy),
        ),
      ),
      onChanged: (value) => setState(() => _searchQuery = value),
    );
  }

  Widget _buildMobileAccountList() {
    if (HrmSettingsMobileKit.active(context)) {
      return HrmSettingsEntityGrid(
        itemCount: _filteredAccounts.length,
        columns: 2,
        childAspectRatio: 1.35,
        itemBuilder: (ctx, index) =>
            _buildAccountDenseTile(_filteredAccounts[index]),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < _filteredAccounts.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildAccountDenseTile(_filteredAccounts[i]),
        ],
      ],
    );
  }

  Widget _buildAccountDenseTile(Map<String, dynamic> account) {
    final isActive = account['isActive'] as bool? ?? true;
    final roles = account['roles'] as List<dynamic>? ?? [];
    final role = roles.isNotEmpty ? roles.first.toString() : 'Employee';
    final fullName = (account['fullName'] ??
            '${account['lastName'] ?? ''} ${account['firstName'] ?? ''}')
        .toString()
        .trim();
    final initials = fullName
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join();
    final roleInfo = _getRoleDisplayInfo(role);

    return HrmSettingsDenseTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: (roleInfo['color'] as Color).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            tr(initials),
            style: TextStyle(
              color: roleInfo['color'] as Color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      title: fullName,
      subtitle: '@${account['userName'] ?? ''}',
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          HrmBrandChip(label: roleInfo['label'] as String),
          const SizedBox(height: 4),
          HrmBrandChip(label: isActive ? 'Hoạt động' : 'Ngừng hoạt động'),
          _buildHrIssueBadge(account, fontSize: 9),
        ],
      ),
      onTap: () => _showAccountDetailSheet(account),
    );
  }

  void _showAccountDetailSheet(Map<String, dynamic> account) {
    final isActive = account['isActive'] as bool? ?? true;
    final roles = account['roles'] as List<dynamic>? ?? [];
    final role = roles.isNotEmpty ? roles.first.toString() : 'Employee';
    final lastLogin = DateTime.tryParse(account['lastLoginAt'] ?? '');
    final fullName = (account['fullName'] ??
            '${account['lastName'] ?? ''} ${account['firstName'] ?? ''}')
        .toString()
        .trim();
    final initials = fullName
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join();
    final roleInfo = _getRoleDisplayInfo(role);

    showAppSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 20),
              // Avatar + Name
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: (roleInfo['color'] as Color).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                    child: Text(tr(initials),
                        style: TextStyle(
                            color: roleInfo['color'] as Color,
                            fontSize: 20,
                            fontWeight: FontWeight.bold))),
              ),
              const SizedBox(height: 12),
              Text(tr(fullName),
                  style: const TextStyle(
                      color: Color(0xFF18181B),
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Text(tr('@${account['userName'] ?? ''}'),
                  style:
                      const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          (roleInfo['color'] as Color).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tr(roleInfo['label'] as String),
                        style: TextStyle(
                            color: roleInfo['color'] as Color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                          : const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tr(isActive ? 'Hoạt động' : 'Ngừng hoạt động'),
                      style: TextStyle(
                          color: isActive
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (_hrIssueLabel(account) != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: HrmPageChrome.chipLight.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tr(_hrIssueLabel(account)!),
                        style: const TextStyle(
                          color: HrmPageChrome.chipDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFFE4E4E7)),
              const SizedBox(height: 8),
              // Detail rows
              _buildDetailRow(
                  Icons.email_outlined, 'Email', account['email'] ?? '—'),
              _buildDetailRow(Icons.phone_outlined, 'Số điện thoại',
                  account['phoneNumber'] ?? '—'),
              _buildDetailRow(Icons.login, 'Đăng nhập cuối',
                  lastLogin != null ? _formatDate(lastLogin) : '—'),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              // Action buttons
              Row(
                children: [
                  if (_perm.canEdit('UserManagement')) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showChangePasswordDialog(account);
                        },
                        icon: const Icon(Icons.lock_reset, size: 18),
                        label: Text(tr('Đổi MK')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: HrmPageChrome.primaryNavy,
                          side:
                              const BorderSide(color: HrmPageChrome.primaryNavy),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAccountDialog(account: account);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: Text(tr('Sửa')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF71717A),
                          side: const BorderSide(color: Color(0xFFE4E4E7)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (_perm.canEdit('UserManagement') &&
                  !_isSelfOrOwner(account)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _toggleAccountActive(account);
                    },
                    icon: Icon(
                      isActive
                          ? Icons.person_off_outlined
                          : Icons.person_outline,
                      size: 18,
                    ),
                    label: Text(tr(isActive ? 'Vô hiệu hóa' : 'Kích hoạt lại')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isActive
                          ? HrmPageChrome.chipLight
                          : const Color(0xFF22C55E),
                      side: BorderSide(
                        color: isActive
                            ? HrmPageChrome.chipLight
                            : const Color(0xFF22C55E),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
              if (_perm.canDelete('UserManagement') &&
                  !_isSelfOrOwner(account)) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _deleteAccount(account);
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(tr('Xóa')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF71717A)),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: Text(tr(label),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
          ),
          Expanded(
            child: Text(tr(value),
                style: const TextStyle(
                    color: Color(0xFF18181B),
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(Map<String, dynamic> account) {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool showNewPassword = false;
    bool showConfirmPassword = false;
    final String fullName = (account['fullName'] ??
            '${account['lastName'] ?? ''} ${account['firstName'] ?? ''}')
        .toString()
        .trim();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMobile = Responsive.isMobile(context);

          Future<void> onSubmit() async {
            if (newPasswordController.text.isEmpty) {
              appNotification.showWarning(
                  title: 'Thiếu thông tin',
                  message: tr('Vui lòng nhập mật khẩu mới'));
              return;
            }
            if (newPasswordController.text.length < 6) {
              appNotification.showWarning(
                  title: 'Mật khẩu yếu', message: tr('Mật khẩu tối thiểu 6 ký tự'));
              return;
            }
            if (newPasswordController.text != confirmPasswordController.text) {
              appNotification.showWarning(
                  title: 'Không khớp', message: tr('Mật khẩu xác nhận không khớp'));
              return;
            }
            Navigator.pop(context);
            try {
              final response = await _apiService.resetAccountPassword(
                  account['id'], newPasswordController.text);
              if (mounted) {
                if (response['isSuccess'] == true) {
                  appNotification.showSuccess(
                      title: 'Thành công',
                      message: tr('Đã đổi mật khẩu cho $fullName'));
                } else {
                  appNotification.showError(
                      title: 'Lỗi',
                      message: response['message'] ?? 'Lỗi khi đổi mật khẩu');
                }
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(title: 'Lỗi', message: tr('Lỗi: $e'));
              }
            }
          }

          Widget formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isMobile) ...[
                Row(
                  children: [
                    const Icon(Icons.lock_reset,
                        color: HrmPageChrome.primaryNavy, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('Đổi mật khẩu'),
                              style: TextStyle(
                                  color: Color(0xFF18181B),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text(tr(fullName),
                              style: const TextStyle(
                                  color: Color(0xFF71717A), fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Color(0xFF71717A)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              Text(tr('Mật khẩu mới'),
                  style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: newPasswordController,
                obscureText: !showNewPassword,
                style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                decoration: InputDecoration(
                  hintText: tr('Nhập mật khẩu mới (tối thiểu 6 ký tự)'),
                  hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  suffixIcon: IconButton(
                    icon: Icon(
                        showNewPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFFA1A1AA),
                        size: 20),
                    onPressed: () => setDialogState(
                        () => showNewPassword = !showNewPassword),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: HrmPageChrome.primaryNavy)),
                ),
              ),
              const SizedBox(height: 16),
              Text(tr('Xác nhận mật khẩu'),
                  style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: confirmPasswordController,
                obscureText: !showConfirmPassword,
                style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                decoration: InputDecoration(
                  hintText: tr('Nhập lại mật khẩu mới'),
                  hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  suffixIcon: IconButton(
                    icon: Icon(
                        showConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFFA1A1AA),
                        size: 20),
                    onPressed: () => setDialogState(
                        () => showConfirmPassword = !showConfirmPassword),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: HrmPageChrome.primaryNavy)),
                ),
              ),
              if (!isMobile) ...[
                const SizedBox(height: 20),
                const Divider(color: Color(0xFFE4E4E7)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('Hủy'),
                          style: TextStyle(color: Color(0xFF71717A))),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: Text(tr('Đổi mật khẩu')),
                      style: FilledButton.styleFrom(
                        backgroundColor: HrmPageChrome.primaryNavy,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              backgroundColor: Colors.white,
              child: Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF18181B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Đổi mật khẩu'),
                          style: TextStyle(
                              color: Color(0xFF18181B),
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(tr(fullName),
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 12)),
                    ],
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: Text(tr('Lưu')),
                      style: TextButton.styleFrom(
                          foregroundColor: HrmPageChrome.primaryNavy),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: formBody,
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: math
                  .min(420, MediaQuery.of(context).size.width - 32)
                  .toDouble(),
              padding: const EdgeInsets.all(24),
              child: formBody,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showAccountDialog({Map<String, dynamic>? account}) async {
    final isEditing = account != null;
    final roles0 = account?['roles'] as List<dynamic>? ?? [];
    final accountRole =
        roles0.isNotEmpty ? roles0.first.toString() : 'Employee';

    final employeeIdController = TextEditingController(
        text: tr(isEditing ? (account['userName']?.toString() ?? '') : ''));
    final fullNameController = TextEditingController(
        text: tr((account?['fullName'] ??
                '${account?['lastName'] ?? ''} ${account?['firstName'] ?? ''}')
            .toString()
            .trim()));
    final emailController =
        TextEditingController(text: tr(account?['email'] ?? ''));
    final phoneController =
        TextEditingController(text: tr(account?['phoneNumber'] ?? ''));
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String selectedRole = accountRole;
    Map<String, dynamic>? selectedEmployee;
    bool showPassword = false;
    bool showConfirmPassword = false;

    final availableEmployees = _employeesAvailableForAccount;
    final pickerCandidates =
        EmployeePickerItem.fromMaps(availableEmployees);

    // Khu vực POS — gán cho Order/Waiter (rỗng = xem tất cả).
    final posAreas = <Map<String, dynamic>>[];
    final selectedAreaIds = <String>{};
    try {
      final areaRes = await _apiService.getPosServiceAreas();
      if (areaRes['isSuccess'] == true && areaRes['data'] is List) {
        for (final e in (areaRes['data'] as List).whereType<Map>()) {
          posAreas.add(Map<String, dynamic>.from(e));
        }
      }
      if (isEditing) {
        final uid = account['id']?.toString() ?? '';
        if (uid.isNotEmpty) {
          final assignRes = await _apiService.getPosUserServiceAreas(uid);
          if (assignRes['isSuccess'] == true && assignRes['data'] is Map) {
            final data = Map<String, dynamic>.from(assignRes['data'] as Map);
            final ids = data['areaIds'];
            if (ids is List) {
              for (final id in ids) {
                final s = id?.toString() ?? '';
                if (s.isNotEmpty) selectedAreaIds.add(s);
              }
            }
          }
        }
      }
    } catch (_) {}

    // Danh sách các quyền hạn
    final roles = [
      {
        'value': 'Admin',
        'label': 'Quản trị viên',
        'color': HrmPageChrome.chipDark
      },
      {
        'value': 'Director',
        'label': 'Giám đốc',
        'color': HrmPageChrome.chipMid
      },
      {
        'value': 'Manager',
        'label': 'Quản lý',
        'color': HrmPageChrome.chip
      },
      {
        'value': 'DepartmentHead',
        'label': 'Trưởng phòng',
        'color': HrmPageChrome.chipMid
      },
      {
        'value': 'Accountant',
        'label': 'Kế toán',
        'color': HrmPageChrome.primaryNavy
      },
      {
        'value': 'Cashier',
        'label': 'Thu ngân',
        'color': HrmPageChrome.chip
      },
      {
        'value': 'Waiter',
        'label': 'Order',
        'color': HrmPageChrome.chipMid
      },
      {
        'value': 'Employee',
        'label': 'Nhân viên',
        'color': HrmPageChrome.primaryNavy
      },
      {
        'value': 'User',
        'label': 'Người dùng',
        'color': const Color(0xFF71717A)
      },
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMobile = Responsive.isMobile(context);

          Future<void> onSubmit() async {
            if (employeeIdController.text.isEmpty ||
                fullNameController.text.isEmpty ||
                emailController.text.isEmpty) {
              appNotification.showWarning(
                  title: 'Thiếu thông tin',
                  message: tr('Vui lòng điền đầy đủ thông tin'));
              return;
            }
            if (!isEditing && selectedEmployee == null) {
              appNotification.showWarning(
                  title: 'Chưa chọn nhân viên',
                  message: tr('Vui lòng chọn nhân viên từ danh sách'));
              return;
            }
            if (!isEditing) {
              if (passwordController.text.isEmpty) {
                appNotification.showWarning(
                    title: 'Thiếu mật khẩu', message: tr('Vui lòng nhập mật khẩu'));
                return;
              }
              if (passwordController.text != confirmPasswordController.text) {
                appNotification.showWarning(
                    title: 'Mật khẩu không khớp',
                    message: tr('Vui lòng nhập lại mật khẩu'));
                return;
              }
              if (passwordController.text.length < 6) {
                appNotification.showWarning(
                    title: 'Mật khẩu yếu',
                    message: tr('Mật khẩu tối thiểu 6 ký tự'));
                return;
              }
            }
            final nameParts = fullNameController.text.trim().split(' ');
            final lastName = nameParts.length > 1
                ? nameParts.sublist(0, nameParts.length - 1).join(' ')
                : '';
            final firstName = nameParts.isNotEmpty ? nameParts.last : '';
            final data = {
              if (!isEditing && selectedEmployee != null)
                'employeeId': selectedEmployee!['id'].toString(),
              'userName': employeeIdController.text,
              'firstName': firstName,
              'lastName': lastName,
              'email': emailController.text,
              'phoneNumber': phoneController.text,
              'role': selectedRole,
              if (!isEditing) 'password': passwordController.text,
            };
            Navigator.pop(context);
            try {
              dynamic response;
              String? savedUserId =
                  isEditing ? account['id']?.toString() : null;
              if (isEditing) {
                response = await _apiService.updateAccount(account['id'], data);
              } else {
                response = await _apiService.createAccount(data);
              }
              if (response is Map && response['isSuccess'] == true) {
                final d = response['data'];
                if (d is Map && d['id'] != null) {
                  savedUserId = d['id'].toString();
                }
              }
              // Gán khu vực: chỉ áp dụng Waiter/Order (và Employee nếu chọn).
              // Admin/Manager/Cashier luôn xem tất cả — xóa gán nếu có.
              if (savedUserId != null && savedUserId.isNotEmpty) {
                final restrictRoles = {'Waiter', 'Employee', 'User'};
                final areaIds = restrictRoles.contains(selectedRole)
                    ? selectedAreaIds.toList()
                    : <String>[];
                try {
                  await _apiService.setPosUserServiceAreas(savedUserId, areaIds);
                } catch (_) {}
              }
              _loadAccounts();
              if (mounted) {
                if (response is Map && response['isSuccess'] == true) {
                  appNotification.showSuccess(
                      title: 'Thành công',
                      message: isEditing
                          ? 'Đã cập nhật tài khoản'
                          : 'Đã thêm tài khoản');
                } else if (response is Map && response['isSuccess'] == false) {
                  appNotification.showError(
                      title: 'Lỗi',
                      message: response['message'] ?? 'Lỗi khi lưu tài khoản');
                } else {
                  appNotification.showSuccess(
                      title: 'Thành công',
                      message: isEditing
                          ? 'Đã cập nhật tài khoản'
                          : 'Đã thêm tài khoản');
                }
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(title: 'Lỗi', message: tr('Lỗi: $e'));
              }
            }
          }

          Widget formFields = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Form fields
              // Employee selector (only when creating)
              if (!isEditing) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EmployeePickerFormField(
                      labelText: tr('Chọn nhân viên *'),
                      hintText: tr(availableEmployees.isEmpty
                          ? 'Không còn nhân viên chưa có tài khoản'
                          : 'Bấm để tìm và chọn nhân viên...'),
                      enabled: availableEmployees.isNotEmpty,
                      candidates: pickerCandidates,
                      selectedId: selectedEmployee?['id']?.toString(),
                      presentation: EmployeePickerPresentation.bottomSheet,
                      pickerTitle: 'Chọn nhân viên',
                      pickerSubtitle: availableEmployees.isEmpty
                          ? null
                          : '${availableEmployees.length} nhân viên chưa có tài khoản',
                      onChanged: (item) {
                        if (item == null) {
                          setDialogState(() => selectedEmployee = null);
                          return;
                        }
                        final emp = availableEmployees.firstWhere(
                          (e) => e['id'].toString() == item.id,
                          orElse: () => <String, dynamic>{},
                        );
                        if (emp.isEmpty) return;
                        setDialogState(() {
                          selectedEmployee = emp;
                          employeeIdController.text =
                              emp['employeeCode']?.toString() ?? '';
                          fullNameController.text = item.name;
                          emailController.text = emp['companyEmail'] ??
                              emp['personalEmail'] ??
                              '';
                          phoneController.text =
                              emp['phoneNumber']?.toString() ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(availableEmployees.isEmpty
                          ? 'Tất cả nhân viên trong hồ sơ đã có tài khoản'
                          : 'Danh sách gồm nhân viên hồ sơ HR chưa đăng ký tài khoản (${availableEmployees.length})'),
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Row 1: Mã nhân viên + Tên nhân viên
              ..._buildFieldPair(
                isMobile: isMobile,
                first: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tr(isEditing ? 'Tên đăng nhập' : 'Mã nhân viên'),
                            style: const TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(tr(' *'),
                            style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: employeeIdController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: tr(isEditing ? 'username' : 'NV001'),
                        hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: HrmPageChrome.primaryNavy),
                        ),
                      ),
                    ),
                  ],
                ),
                second: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tr('Tên nhân viên'),
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(tr(' *'), style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: fullNameController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: tr('Nguyễn Văn A'),
                        hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: HrmPageChrome.primaryNavy),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(tr('Mã NV được tự động điền khi chọn nhân viên'),
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              const SizedBox(height: 16),

              // Row 2: Email + Số điện thoại
              ..._buildFieldPair(
                isMobile: isMobile,
                first: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tr('Email'),
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(tr(' *'), style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: emailController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: tr('email@example.com'),
                        hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: HrmPageChrome.primaryNavy),
                        ),
                      ),
                    ),
                  ],
                ),
                second: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(tr('Số điện thoại'),
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(tr(' *'), style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: tr('0987654321'),
                        hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: HrmPageChrome.primaryNavy),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Row 3: Quyền hạn
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(tr('Quyền hạn'),
                          style: TextStyle(
                              color: Color(0xFF71717A), fontSize: 13)),
                      Text(tr(' *'), style: TextStyle(color: Color(0xFFEF4444))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    dropdownColor: Colors.white,
                    style:
                        const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.security,
                          color: Color(0xFF71717A), size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: HrmPageChrome.primaryNavy),
                      ),
                    ),
                    items: roles.map<DropdownMenuItem<String>>((role) {
                      return DropdownMenuItem<String>(
                        value: role['value'] as String,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: role['color'] as Color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(tr(role['label'] as String)),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setDialogState(() {
                        selectedRole = value ?? 'Employee';
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(tr('Chọn quyền hạn phù hợp với vai trò của nhân viên'),
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
              if (posAreas.isNotEmpty &&
                  (selectedRole == 'Waiter' ||
                      selectedRole == 'Employee' ||
                      selectedRole == 'User')) ...[
                const SizedBox(height: 16),
                Text(tr('Khu vực bàn được phép'),
                    style: const TextStyle(
                        color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                Text(
                  tr(selectedAreaIds.isEmpty
                      ? 'Chưa chọn = xem tất cả khu vực'
                      : 'Chỉ hiện ${selectedAreaIds.length} khu đã chọn trên sơ đồ'),
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text(tr('Tất cả khu')),
                      selected: selectedAreaIds.isEmpty,
                      onSelected: (_) {
                        setDialogState(() => selectedAreaIds.clear());
                      },
                    ),
                    for (final area in posAreas)
                      FilterChip(
                        label: Text(tr(area['name']?.toString() ?? '')),
                        selected: selectedAreaIds
                            .contains(area['id']?.toString() ?? ''),
                        onSelected: (on) {
                          final id = area['id']?.toString() ?? '';
                          if (id.isEmpty) return;
                          setDialogState(() {
                            if (on) {
                              selectedAreaIds.add(id);
                            } else {
                              selectedAreaIds.remove(id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),

              // Row 4: Mật khẩu + Xác nhận mật khẩu
              if (!isEditing) ...[
                ..._buildFieldPair(
                  isMobile: isMobile,
                  first: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tr('Mật khẩu'),
                              style: TextStyle(
                                  color: Color(0xFF71717A), fontSize: 13)),
                          Text(tr(' *'),
                              style: TextStyle(color: Color(0xFFEF4444))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: passwordController,
                        obscureText: !showPassword,
                        style: const TextStyle(
                            color: Color(0xFF18181B), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: tr('Tối thiểu 6 ký tự'),
                          hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          suffixIcon: IconButton(
                            icon: Icon(
                                showPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: const Color(0xFFA1A1AA),
                                size: 20),
                            onPressed: () => setDialogState(
                                () => showPassword = !showPassword),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: HrmPageChrome.primaryNavy),
                          ),
                        ),
                      ),
                    ],
                  ),
                  second: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(tr('Xác nhận mật khẩu'),
                              style: TextStyle(
                                  color: Color(0xFF71717A), fontSize: 13)),
                          Text(tr(' *'),
                              style: TextStyle(color: Color(0xFFEF4444))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: confirmPasswordController,
                        obscureText: !showConfirmPassword,
                        style: const TextStyle(
                            color: Color(0xFF18181B), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: tr('Nhập lại mật khẩu'),
                          hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          suffixIcon: IconButton(
                            icon: Icon(
                                showConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: const Color(0xFFA1A1AA),
                                size: 20),
                            onPressed: () => setDialogState(() =>
                                showConfirmPassword = !showConfirmPassword),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: HrmPageChrome.primaryNavy),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ],
          );

          if (isMobile) {
            return Dialog.fullscreen(
              backgroundColor: Colors.white,
              child: Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF18181B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text(
                    tr(isEditing ? 'Sửa tài khoản' : 'Đăng ký tài khoản'),
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.save, size: 18),
                      label: Text(tr(isEditing ? 'Cập nhật' : 'Đăng ký')),
                      style: TextButton.styleFrom(
                          foregroundColor: HrmPageChrome.primaryNavy),
                    ),
                  ],
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: formFields,
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: math
                  .min(500, MediaQuery.of(context).size.width - 32)
                  .toDouble(),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr(isEditing ? 'Sửa tài khoản' : 'Đăng ký tài khoản'),
                            style: const TextStyle(
                                color: Color(0xFF18181B),
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon:
                              const Icon(Icons.close, color: Color(0xFF71717A)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    formFields,
                    const Divider(color: Color(0xFFE4E4E7)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr('Hủy'),
                              style: TextStyle(color: Color(0xFF71717A))),
                        ),
                        const Spacer(),
                        Expanded(
                          flex: 3,
                          child: FilledButton.icon(
                            onPressed: onSubmit,
                            icon: const Icon(Icons.person_add, size: 18),
                            label: Text(tr(isEditing ? 'Cập nhật' : 'Đăng ký')),
                            style: FilledButton.styleFrom(
                              backgroundColor: HrmPageChrome.primaryNavy,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _deleteAccount(Map<String, dynamic> account) {
    if (_isSelfOrOwner(account)) {
      appNotification.showWarning(
        title: 'Không thể xóa',
        message: account['isOwner'] == true
            ? 'Không thể xóa tài khoản chủ cửa hàng'
            : 'Bạn không thể xóa tài khoản của chính mình',
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Xác nhận xóa'),
            style: TextStyle(
                color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        content: Text(tr('${tr('Bạn có chắc muốn xóa tài khoản "')}${account['fullName']}"?\n\n'
          'Hệ thống sẽ gỡ liên kết đăng nhập; dữ liệu chấm công/lương gắn hồ sơ nhân sự vẫn được giữ. '
          'Nếu vẫn lỗi ràng buộc, dùng Vô hiệu hóa để giải phóng slot gói.'),
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                Text(tr('Hủy'), style: TextStyle(color: Color(0xFF71717A))),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final response = await _apiService.deleteAccount(account['id']);
                _loadAccounts();
                if (mounted) {
                  if (response['isSuccess'] == true) {
                    appNotification.showSuccess(
                        title: 'Thành công', message: tr('Đã xóa tài khoản'));
                  } else if (response['isSuccess'] == false) {
                    appNotification.showError(
                        title: 'Lỗi',
                        message:
                            response['message'] ?? 'Lỗi khi xóa tài khoản');
                  } else {
                    appNotification.showSuccess(
                        title: 'Thành công', message: tr('Đã xóa tài khoản'));
                  }
                }
              } catch (e) {
                if (mounted) {
                  appNotification.showError(title: 'Lỗi', message: tr('Lỗi: $e'));
                }
              }
            },
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
  }

  bool _isSelfOrOwner(Map<String, dynamic> account) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.id;
    if (currentUserId != null &&
        account['id']?.toString() == currentUserId.toString()) {
      return true;
    }
    return account['isOwner'] == true;
  }

  Future<void> _toggleAccountActive(Map<String, dynamic> account) async {
    if (_isSelfOrOwner(account)) {
      appNotification.showWarning(
        title: 'Không thể đổi trạng thái',
        message: account['isOwner'] == true
            ? 'Không thể vô hiệu hóa tài khoản chủ cửa hàng'
            : 'Bạn không thể đổi trạng thái tài khoản của chính mình',
      );
      return;
    }

    final isActive = account['isActive'] as bool? ?? true;
    final name = (account['fullName'] ?? account['userName'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          tr(isActive ? 'Vô hiệu hóa tài khoản' : 'Kích hoạt lại tài khoản'),
          style: const TextStyle(
              color: Color(0xFF18181B), fontWeight: FontWeight.bold),
        ),
        content: Text(
          tr(isActive
              ? 'Vô hiệu hóa "$name"? Tài khoản không đăng nhập được và giải phóng 1 slot gói dịch vụ. Có thể kích hoạt lại sau.'
              : 'Kích hoạt lại "$name"? Tài khoản sẽ chiếm lại 1 slot gói dịch vụ.'),
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text(tr('Hủy'), style: TextStyle(color: Color(0xFF71717A))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: isActive
                  ? HrmPageChrome.chipLight
                  : const Color(0xFF22C55E),
            ),
            child: Text(tr(isActive ? 'Vô hiệu hóa' : 'Kích hoạt')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response =
          await _apiService.toggleAccountStatus(account['id'], !isActive);
      if (!mounted) return;
      if (response['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: isActive
              ? 'Đã vô hiệu hóa tài khoản'
              : 'Đã kích hoạt lại tài khoản',
        );
        _loadAccounts();
      } else {
        final errors = response['errors'];
        final errMsg = response['message']?.toString();
        final fromErrors = errors is List && errors.isNotEmpty
            ? errors.first.toString()
            : null;
        appNotification.showError(
          title: 'Lỗi',
          message: (errMsg != null && errMsg.isNotEmpty)
              ? errMsg
              : (fromErrors ?? 'Không thể đổi trạng thái tài khoản'),
        );
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: tr('Lỗi: $e'));
      }
    }
  }

  void _showBulkAccountDialog() {
    final availableEmployees = _employeesAvailableForAccount;
    if (availableEmployees.isEmpty) {
      appNotification.showWarning(
        title: 'Không có nhân viên',
        message: tr('Tất cả nhân viên đã có tài khoản'),
      );
      return;
    }

    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final searchController = TextEditingController();
    final selectedIds = <String>{};
    String selectedRole = 'Employee';
    bool showPassword = false;
    bool showConfirmPassword = false;
    bool isSubmitting = false;

    const roles = [
      {'value': 'Waiter', 'label': 'Order'},
      {'value': 'Cashier', 'label': 'Thu ngân'},
      {'value': 'Employee', 'label': 'Nhân viên'},
      {'value': 'User', 'label': 'Người dùng'},
      {'value': 'Accountant', 'label': 'Kế toán'},
      {'value': 'DepartmentHead', 'label': 'Trưởng phòng'},
      {'value': 'Manager', 'label': 'Quản lý'},
    ];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMobile = Responsive.isMobile(context);
          final query = searchController.text.trim().toLowerCase();
          final filtered = availableEmployees.where((emp) {
            if (query.isEmpty) return true;
            final code = emp['employeeCode']?.toString().toLowerCase() ?? '';
            final name =
                '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim().toLowerCase();
            return code.contains(query) || name.contains(query);
          }).toList();
          final filteredIds = filtered
              .map((e) => e['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          final allFilteredSelected = filteredIds.isNotEmpty &&
              filteredIds.every(selectedIds.contains);

          Future<void> onSubmit() async {
            if (selectedIds.isEmpty) {
              appNotification.showWarning(
                title: 'Chưa chọn nhân viên',
                message: tr('Vui lòng chọn ít nhất một nhân viên'),
              );
              return;
            }
            if (passwordController.text.isEmpty) {
              appNotification.showWarning(
                title: 'Thiếu mật khẩu',
                message: tr('Vui lòng nhập mật khẩu chung'),
              );
              return;
            }
            if (passwordController.text != confirmPasswordController.text) {
              appNotification.showWarning(
                title: 'Mật khẩu không khớp',
                message: tr('Vui lòng nhập lại mật khẩu'),
              );
              return;
            }
            if (passwordController.text.length < 6) {
              appNotification.showWarning(
                title: 'Mật khẩu yếu',
                message: tr('Mật khẩu tối thiểu 6 ký tự'),
              );
              return;
            }

            setDialogState(() => isSubmitting = true);
            try {
              final response = await _apiService.createBulkAccounts(
                employeeIds: selectedIds.toList(),
                password: passwordController.text,
                role: selectedRole,
              );
              if (!context.mounted) return;
              Navigator.pop(dialogContext);
              await _loadAccounts();
              if (!mounted) return;

              if (response['isSuccess'] == true) {
                final data = response['data'] as Map<String, dynamic>? ?? {};
                final created = data['created'] ?? 0;
                final failed = data['failed'] ?? 0;
                final skipped = data['skipped'] ?? 0;
                appNotification.showSuccess(
                  title: 'Đăng ký hàng loạt',
                  message: tr('Thành công $created, bỏ qua $skipped, lỗi $failed. Nhân viên đăng nhập bằng email hoặc SĐT có trong hồ sơ (chỉ cần 1 trong 2).'),
                );
              } else {
                appNotification.showError(
                  title: 'Lỗi',
                  message: response['message']?.toString() ??
                      'Không thể đăng ký hàng loạt',
                );
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(title: 'Lỗi', message: '$e');
              }
            } finally {
              if (context.mounted) {
                setDialogState(() => isSubmitting = false);
              }
            }
          }

          Widget buildEmployeeList(double height) {
            return SizedBox(
              height: height,
              child: filtered.isEmpty
                  ? Center(
                      child: Text(tr('Không tìm thấy nhân viên'),
                          style: TextStyle(color: Color(0xFF71717A))),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, index) {
                        final emp = filtered[index];
                        final id = emp['id']?.toString() ?? '';
                        final code = emp['employeeCode']?.toString() ?? '—';
                        final name =
                            '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                                .trim();
                        final email = (emp['companyEmail'] ??
                                emp['personalEmail'] ??
                                '')
                            .toString()
                            .trim();
                        final phone =
                            emp['phoneNumber']?.toString().trim() ?? '';
                        final subtitleParts = <String>[
                          'Mã NV: $code',
                          if (email.isNotEmpty) email,
                          if (phone.isNotEmpty) phone,
                          if (email.isEmpty && phone.isEmpty)
                            '⚠ Thiếu email và SĐT',
                        ];
                        final checked = selectedIds.contains(id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: id.isEmpty
                              ? null
                              : (v) {
                                  setDialogState(() {
                                    if (v == true) {
                                      selectedIds.add(id);
                                    } else {
                                      selectedIds.remove(id);
                                    }
                                  });
                                },
                          title: Text(tr(name.isEmpty ? code : name),
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(tr(subtitleParts.join(' · ')),
                              style: const TextStyle(fontSize: 12)),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
            );
          }

          final formContent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Chọn nhiều nhân viên, dùng chung 1 mật khẩu và 1 quyền. '
                'Mỗi người chỉ cần có email hoặc SĐT trong hồ sơ HR để đăng nhập '
                '(báo lỗi nếu thiếu cả hai). Nhân viên có thể đổi mật khẩu sau khi đăng nhập.'),
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: searchController,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(
                  hintText: tr('Tìm theo tên hoặc mã NV...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: filteredIds.isEmpty
                        ? null
                        : () {
                            setDialogState(() {
                              if (allFilteredSelected) {
                                selectedIds.removeAll(filteredIds);
                              } else {
                                selectedIds.addAll(filteredIds);
                              }
                            });
                          },
                    icon: Icon(allFilteredSelected
                        ? Icons.deselect
                        : Icons.select_all),
                    label: Text(tr(allFilteredSelected
                        ? 'Bỏ chọn'
                        : 'Chọn tất cả (${filtered.length})')),
                  ),
                  const Spacer(),
                  Text(tr('Đã chọn: ${selectedIds.length}'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: HrmPageChrome.primaryNavy)),
                ],
              ),
              buildEmployeeList(isMobile ? 180 : 240),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedRole,
                decoration: InputDecoration(
                  labelText: tr('Quyền hạn chung'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: roles
                    .map((r) => DropdownMenuItem<String>(
                          value: r['value'] as String,
                          child: Text(tr(r['label'] as String)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedRole = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: !showPassword,
                decoration: InputDecoration(
                  labelText: tr('Mật khẩu chung *'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(showPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setDialogState(() => showPassword = !showPassword),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: !showConfirmPassword,
                decoration: InputDecoration(
                  labelText: tr('Nhập lại mật khẩu *'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: Icon(showConfirmPassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setDialogState(
                        () => showConfirmPassword = !showConfirmPassword),
                  ),
                ),
              ),
            ],
          );

          if (isMobile) {
            return Scaffold(
              appBar: AppBar(
                title: Text(tr('Đăng ký hàng loạt')),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed:
                      isSubmitting ? null : () => Navigator.pop(dialogContext),
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting ? null : onSubmit,
                    child: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(tr('Tạo')),
                  ),
                ],
              ),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: formContent,
              ),
            );
          }

          return AlertDialog(
            title: Text(tr('Đăng ký tài khoản hàng loạt')),
            content: SizedBox(width: 520, child: formContent),
            actions: [
              TextButton(
                onPressed:
                    isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: Text(tr('Hủy')),
              ),
              FilledButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(tr('Tạo (${selectedIds.length})')),
              ),
            ],
          );
        },
      ),
    );
  }
}
