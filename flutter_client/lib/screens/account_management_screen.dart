import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({super.key});

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _employees = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRole = 'all';
  String _selectedStatus = 'all';
  bool _showMobileFilters = false;

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
        _apiService.getEmployees(),
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
      final accounts = await _apiService.getAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = List<Map<String, dynamic>>.from(accounts);
      });
    } catch (e) {
      debugPrint('Error loading accounts: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

      return matchesSearch && matchesRole && matchesStatus;
    }).toList();
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
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Quản lý Tài khoản',
            style: TextStyle(
                color: Color(0xFF18181B),
                fontWeight: FontWeight.bold,
                fontSize: 18),
            overflow: TextOverflow.ellipsis,
            maxLines: 1),
        leading: Responsive.isMobile(context)
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
                onPressed: () => SettingsHubScreen.goBack(context),
              ),
        actions: [
          if (Responsive.isMobile(context))
            IconButton(
              onPressed: () =>
                  setState(() => _showMobileFilters = !_showMobileFilters),
              icon: Stack(
                children: [
                  Icon(
                      _showMobileFilters
                          ? Icons.filter_alt
                          : Icons.filter_alt_outlined,
                      color: const Color(0xFF18181B)),
                  if (_searchQuery.isNotEmpty ||
                      _selectedRole != 'all' ||
                      _selectedStatus != 'all')
                    Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: Colors.orangeAccent,
                                shape: BoxShape.circle))),
                ],
              ),
              tooltip: 'Bộ lọc',
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with title and add button
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF71717A).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.group,
                            color: Color(0xFF71717A), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Quản lý Tài khoản',
                              style: TextStyle(
                                color: Color(0xFF1E3A5F),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Quản lý tài khoản người dùng hệ thống',
                              style: TextStyle(
                                  color: Color(0xFF71717A), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      if (Responsive.isMobile(context))
                        IconButton(
                          onPressed: () => _showAccountDialog(),
                          icon: const Icon(Icons.person_add,
                              color: Color(0xFF0F2340), size: 22),
                          tooltip: 'Thêm tài khoản',
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: () => _showAccountDialog(),
                          icon: const Icon(Icons.person_add, size: 18),
                          label: const Text('Thêm tài khoản'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F2340),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Statistics cards
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 800) {
                        return Row(
                          children: [
                            Expanded(
                                child: _buildStatCard(
                                    Icons.group,
                                    '$_totalAccounts',
                                    'Tổng tài khoản',
                                    const Color(0xFF1E3A5F))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildStatCard(
                                    Icons.check_circle,
                                    '$_activeAccounts',
                                    'Đang hoạt động',
                                    const Color(0xFF1E3A5F))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildStatCard(
                                    Icons.admin_panel_settings,
                                    '$_adminAccounts',
                                    'Quản trị viên',
                                    const Color(0xFF0F2340))),
                            const SizedBox(width: 16),
                            Expanded(
                                child: _buildStatCard(
                                    Icons.login,
                                    '$_onlineToday',
                                    'Online hôm nay',
                                    const Color(0xFF0F2340))),
                          ],
                        );
                      } else if (constraints.maxWidth >= 350) {
                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.group,
                                        '$_totalAccounts',
                                        'Tổng tài khoản',
                                        const Color(0xFF1E3A5F))),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.check_circle,
                                        '$_activeAccounts',
                                        'Đang hoạt động',
                                        const Color(0xFF1E3A5F))),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.admin_panel_settings,
                                        '$_adminAccounts',
                                        'Quản trị viên',
                                        const Color(0xFF0F2340))),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: _buildStatCard(
                                        Icons.login,
                                        '$_onlineToday',
                                        'Online hôm nay',
                                        const Color(0xFF0F2340))),
                              ],
                            ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildStatCard(Icons.group, '$_totalAccounts',
                                'Tổng tài khoản', const Color(0xFF1E3A5F)),
                            const SizedBox(height: 8),
                            _buildStatCard(
                                Icons.check_circle,
                                '$_activeAccounts',
                                'Đang hoạt động',
                                const Color(0xFF1E3A5F)),
                            const SizedBox(height: 8),
                            _buildStatCard(
                                Icons.admin_panel_settings,
                                '$_adminAccounts',
                                'Quản trị viên',
                                const Color(0xFF0F2340)),
                            const SizedBox(height: 8),
                            _buildStatCard(Icons.login, '$_onlineToday',
                                'Online hôm nay', const Color(0xFF0F2340)),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  // Filter bar
                  if (!Responsive.isMobile(context) || _showMobileFilters)
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
                                hintText: 'Tìm theo tên hoặc username...',
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
                                      color: Color(0xFF1E3A5F)),
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
                                      color: Color(0xFF1E3A5F)),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'all',
                                    child: Text('Tất cả vai trò')),
                                DropdownMenuItem(
                                    value: 'Admin',
                                    child: Text('Quản trị viên')),
                                DropdownMenuItem(
                                    value: 'Director', child: Text('Giám đốc')),
                                DropdownMenuItem(
                                    value: 'Manager', child: Text('Quản lý')),
                                DropdownMenuItem(
                                    value: 'DepartmentHead',
                                    child: Text('Trưởng phòng')),
                                DropdownMenuItem(
                                    value: 'Accountant',
                                    child: Text('Kế toán')),
                                DropdownMenuItem(
                                    value: 'Employee',
                                    child: Text('Nhân viên')),
                                DropdownMenuItem(
                                    value: 'User', child: Text('Người dùng')),
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
                                      color: Color(0xFF1E3A5F)),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'all',
                                    child: Text('Tất cả trạng thái')),
                                DropdownMenuItem(
                                    value: 'active',
                                    child: Text('Đang hoạt động')),
                                DropdownMenuItem(
                                    value: 'inactive', child: Text('Đã khóa')),
                              ],
                              onChanged: (value) => setState(
                                  () => _selectedStatus = value ?? 'all'),
                            ),
                          ),
                          // Clear filter button
                          OutlinedButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.filter_alt_off, size: 18),
                            label: const Text('Xóa lọc'),
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
                                    columns: const [
                                      DataColumn(label: Text('#')),
                                      DataColumn(label: Text('Nhân viên')),
                                      DataColumn(label: Text('Email')),
                                      DataColumn(label: Text('SĐT')),
                                      DataColumn(label: Text('Vai trò')),
                                      DataColumn(label: Text('Trạng thái')),
                                      DataColumn(label: Text('Đăng nhập cuối')),
                                      DataColumn(label: Text('Thao tác')),
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
        DataCell(Text('${index + 1}',
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
                  child: Text(initials,
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
                Text(fullName,
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text('@${account['userName'] ?? ''}',
                    style: const TextStyle(
                        color: Color(0xFFA1A1AA), fontSize: 11)),
              ],
            ),
          ],
        )),
        DataCell(Text(account['email'] ?? '',
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
        DataCell(Text(account['phoneNumber'] ?? '',
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: (roleInfo['color'] as Color).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(roleInfo['label'] as String,
              style: TextStyle(
                  color: roleInfo['color'] as Color,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
        )),
        DataCell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                : const Color(0xFFEF4444).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            isActive ? 'Hoạt động' : 'Đã khóa',
            style: TextStyle(
                color: isActive
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        )),
        DataCell(Text(
          lastLogin != null ? _formatDate(lastLogin) : '—',
          style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
        )),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _showChangePasswordDialog(account),
              icon: const Icon(Icons.lock_reset, size: 18),
              color: const Color(0xFF1E3A5F),
              tooltip: 'Đổi mật khẩu',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              onPressed: () => _showAccountDialog(account: account),
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: const Color(0xFF71717A),
              tooltip: 'Sửa',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              onPressed: () => _deleteAccount(account),
              icon: const Icon(Icons.delete_outline, size: 18),
              color: const Color(0xFFEF4444),
              tooltip: 'Xóa',
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF18181B),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style:
                      const TextStyle(color: Color(0xFF71717A), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
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
        return {'label': 'Quản trị viên', 'color': const Color(0xFFEF4444)};
      case 'Director':
        return {'label': 'Giám đốc', 'color': const Color(0xFF7C3AED)};
      case 'Manager':
        return {'label': 'Quản lý', 'color': const Color(0xFF0F2340)};
      case 'DepartmentHead':
        return {'label': 'Trưởng phòng', 'color': const Color(0xFF2563EB)};
      case 'Accountant':
        return {'label': 'Kế toán', 'color': const Color(0xFF1E3A5F)};
      case 'Employee':
        return {'label': 'Nhân viên', 'color': const Color(0xFF1E3A5F)};
      case 'User':
      default:
        return {'label': 'Người dùng', 'color': const Color(0xFF71717A)};
    }
  }

  Widget _buildMobileAccountList() {
    return Column(
      children: List.generate(_filteredAccounts.length, (index) {
        final account = _filteredAccounts[index];
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

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showAccountDetailSheet(account),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (roleInfo['color'] as Color)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                          child: Text(initials,
                              style: TextStyle(
                                  color: roleInfo['color'] as Color,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fullName,
                              style: const TextStyle(
                                  color: Color(0xFF18181B),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('@${account['userName'] ?? ''}',
                              style: const TextStyle(
                                  color: Color(0xFFA1A1AA), fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (roleInfo['color'] as Color)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(roleInfo['label'] as String,
                              style: TextStyle(
                                  color: roleInfo['color'] as Color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500)),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                                : const Color(0xFFEF4444)
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isActive ? 'Hoạt động' : 'Đã khóa',
                            style: TextStyle(
                                color: isActive
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFEF4444),
                                fontSize: 10,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        color: Color(0xFFA1A1AA), size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
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

    showModalBottomSheet(
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
                    child: Text(initials,
                        style: TextStyle(
                            color: roleInfo['color'] as Color,
                            fontSize: 20,
                            fontWeight: FontWeight.bold))),
              ),
              const SizedBox(height: 12),
              Text(fullName,
                  style: const TextStyle(
                      color: Color(0xFF18181B),
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              Text('@${account['userName'] ?? ''}',
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
                    child: Text(roleInfo['label'] as String,
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
                      isActive ? 'Hoạt động' : 'Đã khóa',
                      style: TextStyle(
                          color: isActive
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
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
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showChangePasswordDialog(account);
                      },
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Đổi MK'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: const BorderSide(color: Color(0xFF1E3A5F)),
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
                      label: const Text('Sửa'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF71717A),
                        side: const BorderSide(color: Color(0xFFE4E4E7)),
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
                        _deleteAccount(account);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Xóa'),
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
              ),
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
            child: Text(label,
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
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
                  message: 'Vui lòng nhập mật khẩu mới');
              return;
            }
            if (newPasswordController.text.length < 6) {
              appNotification.showWarning(
                  title: 'Mật khẩu yếu', message: 'Mật khẩu tối thiểu 6 ký tự');
              return;
            }
            if (newPasswordController.text != confirmPasswordController.text) {
              appNotification.showWarning(
                  title: 'Không khớp', message: 'Mật khẩu xác nhận không khớp');
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
                      message: 'Đã đổi mật khẩu cho $fullName');
                } else {
                  appNotification.showError(
                      title: 'Lỗi',
                      message: response['message'] ?? 'Lỗi khi đổi mật khẩu');
                }
              }
            } catch (e) {
              if (mounted) {
                appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
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
                        color: Color(0xFF1E3A5F), size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Đổi mật khẩu',
                              style: TextStyle(
                                  color: Color(0xFF18181B),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text(fullName,
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
              const Text('Mật khẩu mới',
                  style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: newPasswordController,
                obscureText: !showNewPassword,
                style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Nhập mật khẩu mới (tối thiểu 6 ký tự)',
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
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Xác nhận mật khẩu',
                  style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: confirmPasswordController,
                obscureText: !showConfirmPassword,
                style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Nhập lại mật khẩu mới',
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
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F))),
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
                      child: const Text('Hủy',
                          style: TextStyle(color: Color(0xFF71717A))),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Đổi mật khẩu'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
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
                      const Text('Đổi mật khẩu',
                          style: TextStyle(
                              color: Color(0xFF18181B),
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      Text(fullName,
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 12)),
                    ],
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Lưu'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF1E3A5F)),
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

  void _showAccountDialog({Map<String, dynamic>? account}) {
    final isEditing = account != null;
    final roles0 = account?['roles'] as List<dynamic>? ?? [];
    final accountRole =
        roles0.isNotEmpty ? roles0.first.toString() : 'Employee';

    final employeeIdController = TextEditingController(
        text: isEditing ? (account['userName']?.toString() ?? '') : '');
    final fullNameController = TextEditingController(
        text: (account?['fullName'] ??
                '${account?['lastName'] ?? ''} ${account?['firstName'] ?? ''}')
            .toString()
            .trim());
    final emailController =
        TextEditingController(text: account?['email'] ?? '');
    final phoneController =
        TextEditingController(text: account?['phoneNumber'] ?? '');
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    String selectedRole = accountRole;
    Map<String, dynamic>? selectedEmployee;
    bool showPassword = false;
    bool showConfirmPassword = false;

    // Lọc nhân viên chưa có tài khoản
    final availableEmployees =
        _employees.where((emp) => emp['applicationUserId'] == null).toList();

    // Danh sách các quyền hạn
    final roles = [
      {
        'value': 'Admin',
        'label': 'Quản trị viên',
        'color': const Color(0xFFEF4444)
      },
      {
        'value': 'Director',
        'label': 'Giám đốc',
        'color': const Color(0xFF7C3AED)
      },
      {
        'value': 'Manager',
        'label': 'Quản lý',
        'color': const Color(0xFF0F2340)
      },
      {
        'value': 'DepartmentHead',
        'label': 'Trưởng phòng',
        'color': const Color(0xFF2563EB)
      },
      {
        'value': 'Accountant',
        'label': 'Kế toán',
        'color': const Color(0xFF1E3A5F)
      },
      {
        'value': 'Employee',
        'label': 'Nhân viên',
        'color': const Color(0xFF1E3A5F)
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
                  message: 'Vui lòng điền đầy đủ thông tin');
              return;
            }
            if (!isEditing && selectedEmployee == null) {
              appNotification.showWarning(
                  title: 'Chưa chọn nhân viên',
                  message: 'Vui lòng chọn nhân viên từ danh sách');
              return;
            }
            if (!isEditing) {
              if (passwordController.text.isEmpty) {
                appNotification.showWarning(
                    title: 'Thiếu mật khẩu', message: 'Vui lòng nhập mật khẩu');
                return;
              }
              if (passwordController.text != confirmPasswordController.text) {
                appNotification.showWarning(
                    title: 'Mật khẩu không khớp',
                    message: 'Vui lòng nhập lại mật khẩu');
                return;
              }
              if (passwordController.text.length < 6) {
                appNotification.showWarning(
                    title: 'Mật khẩu yếu',
                    message: 'Mật khẩu tối thiểu 6 ký tự');
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
              if (isEditing) {
                response = await _apiService.updateAccount(account['id'], data);
              } else {
                response = await _apiService.createAccount(data);
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
                appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
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
                    const Row(
                      children: [
                        Text('Chọn nhân viên',
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(' *', style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      dropdownColor: Colors.white,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      isExpanded: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_search,
                            color: Color(0xFF71717A), size: 18),
                        hintText: availableEmployees.isEmpty
                            ? 'Không có nhân viên khả dụng'
                            : 'Chọn nhân viên từ danh sách...',
                        hintStyle: const TextStyle(
                            color: Color(0xFFA1A1AA), fontSize: 14),
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
                              const BorderSide(color: Color(0xFF0F2340)),
                        ),
                      ),
                      items: availableEmployees
                          .map<DropdownMenuItem<String>>((emp) {
                        final empName =
                            '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                                .trim();
                        final empCode = emp['employeeCode'] ?? '';
                        return DropdownMenuItem<String>(
                          value: emp['id'].toString(),
                          child: Text('$empCode - $empName',
                              overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final emp = availableEmployees.firstWhere(
                            (e) => e['id'].toString() == value,
                            orElse: () => {});
                        if (emp.isNotEmpty) {
                          setDialogState(() {
                            selectedEmployee = emp;
                            employeeIdController.text =
                                emp['employeeCode'] ?? '';
                            fullNameController.text =
                                '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                                    .trim();
                            emailController.text = emp['companyEmail'] ??
                                emp['personalEmail'] ??
                                '';
                            phoneController.text = emp['phoneNumber'] ?? '';
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Chọn nhân viên để tự động điền thông tin',
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
                        Text(isEditing ? 'Tên đăng nhập' : 'Mã nhân viên',
                            style: const TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        const Text(' *',
                            style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: employeeIdController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: isEditing ? 'username' : 'NV001',
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
                              const BorderSide(color: Color(0xFF0F2340)),
                        ),
                      ),
                    ),
                  ],
                ),
                second: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text('Tên nhân viên',
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(' *', style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: fullNameController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Nguyễn Văn A',
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
                              const BorderSide(color: Color(0xFF0F2340)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mã NV được tự động điền khi chọn nhân viên',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
              const SizedBox(height: 16),

              // Row 2: Email + Số điện thoại
              ..._buildFieldPair(
                isMobile: isMobile,
                first: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text('Email',
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(' *', style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: emailController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'email@example.com',
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
                              const BorderSide(color: Color(0xFF0F2340)),
                        ),
                      ),
                    ),
                  ],
                ),
                second: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text('Số điện thoại',
                            style: TextStyle(
                                color: Color(0xFF71717A), fontSize: 13)),
                        Text(' *', style: TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: phoneController,
                      style: const TextStyle(
                          color: Color(0xFF18181B), fontSize: 14),
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: '0987654321',
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
                              const BorderSide(color: Color(0xFF0F2340)),
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
                  const Row(
                    children: [
                      Text('Quyền hạn',
                          style: TextStyle(
                              color: Color(0xFF71717A), fontSize: 13)),
                      Text(' *', style: TextStyle(color: Color(0xFFEF4444))),
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
                        borderSide: const BorderSide(color: Color(0xFF0F2340)),
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
                            Text(role['label'] as String),
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
                  Text(
                    'Chọn quyền hạn phù hợp với vai trò của nhân viên',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Row 4: Mật khẩu + Xác nhận mật khẩu
              if (!isEditing) ...[
                ..._buildFieldPair(
                  isMobile: isMobile,
                  first: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text('Mật khẩu',
                              style: TextStyle(
                                  color: Color(0xFF71717A), fontSize: 13)),
                          Text(' *',
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
                          hintText: 'Tối thiểu 6 ký tự',
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
                                const BorderSide(color: Color(0xFF0F2340)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  second: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text('Xác nhận mật khẩu',
                              style: TextStyle(
                                  color: Color(0xFF71717A), fontSize: 13)),
                          Text(' *',
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
                          hintText: 'Nhập lại mật khẩu',
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
                                const BorderSide(color: Color(0xFF0F2340)),
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
                    isEditing ? 'Sửa tài khoản' : 'Đăng ký tài khoản',
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.save, size: 18),
                      label: Text(isEditing ? 'Cập nhật' : 'Đăng ký'),
                      style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0F2340)),
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
                            isEditing ? 'Sửa tài khoản' : 'Đăng ký tài khoản',
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
                          child: const Text('Hủy',
                              style: TextStyle(color: Color(0xFF71717A))),
                        ),
                        const Spacer(),
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            onPressed: onSubmit,
                            icon: const Icon(Icons.person_add, size: 18),
                            label: Text(isEditing ? 'Cập nhật' : 'Đăng ký'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0F2340),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
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
    // Prevent deleting own account
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.user?.id;
    if (currentUserId != null &&
        account['id']?.toString() == currentUserId.toString()) {
      appNotification.showWarning(
        title: 'Không thể xóa',
        message: 'Bạn không thể xóa tài khoản của chính mình',
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa',
            style: TextStyle(
                color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        content: Text(
          'Bạn có chắc muốn xóa tài khoản "${account['fullName']}"? Hành động này không thể hoàn tác.',
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final response = await _apiService.deleteAccount(account['id']);
                _loadAccounts();
                if (mounted) {
                  if (response['isSuccess'] == true) {
                    appNotification.showSuccess(
                        title: 'Thành công', message: 'Đã xóa tài khoản');
                  } else if (response['isSuccess'] == false) {
                    appNotification.showError(
                        title: 'Lỗi',
                        message:
                            response['message'] ?? 'Lỗi khi xóa tài khoản');
                  } else {
                    appNotification.showSuccess(
                        title: 'Thành công', message: 'Đã xóa tài khoản');
                  }
                }
              } catch (e) {
                if (mounted) {
                  appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
