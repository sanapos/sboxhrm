import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => UsersTabState();
}

class UsersTabState extends State<UsersTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = false;

  final _searchCtrl = TextEditingController();
  String? _roleFilter;
  String? _storeFilter;
  final Map<String, String> _resetPasswords = {};

  static const _allRoles = [
    'SuperAdmin',
    'Admin',
    'Manager',
    'Employee',
    'User',
    'Agent'
  ];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get users => _users;

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getSystemUsers();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        _users = AdminHelpers.extractList(res['data']);
        _applyFilters();
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      debugPrint('UsersTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilters() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredUsers = _users.where((u) {
        final name = (u['fullName'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final store = (u['storeName'] ?? '').toString().toLowerCase();
        final matchSearch = query.isEmpty ||
            name.contains(query) ||
            email.contains(query) ||
            store.contains(query);

        final role = (u['role'] ?? '').toString();
        final matchRole =
            _roleFilter == null || role == _roleFilter;

        final storeId = u['storeId']?.toString();
        final matchStore = _storeFilter == null ||
            (_storeFilter == '_none' && storeId == null) ||
            storeId == _storeFilter;

        return matchSearch && matchRole && matchStore;
      }).toList();
    });
  }

  /// Group users by store
  Map<String, List<Map<String, dynamic>>> get _groupedUsers {
    final groups = <String, List<Map<String, dynamic>>>{};
    // "Không thuộc cửa hàng" group for SuperAdmin/Agent
    const noStoreKey = '__no_store__';

    for (final u in _filteredUsers) {
      final storeId = u['storeId']?.toString();
      final key = storeId ?? noStoreKey;
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(u);
    }

    // Sort: no-store group first, then by store name
    final sorted = <String, List<Map<String, dynamic>>>{};
    if (groups.containsKey(noStoreKey)) {
      sorted[noStoreKey] = groups.remove(noStoreKey)!;
    }
    final storeEntries = groups.entries.toList()
      ..sort((a, b) {
        final nameA =
            (a.value.first['storeName'] ?? '').toString().toLowerCase();
        final nameB =
            (b.value.first['storeName'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    for (final e in storeEntries) {
      sorted[e.key] = e.value;
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final grouped = _groupedUsers;

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _filteredUsers.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.people,
                  _searchCtrl.text.isNotEmpty
                      ? 'Không tìm thấy người dùng'
                      : 'Chưa có người dùng')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: grouped.length,
                  itemBuilder: (ctx, i) {
                    final entry = grouped.entries.elementAt(i);
                    return _buildStoreGroup(entry.key, entry.value);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final roleMap = <String, int>{};
    for (final u in _users) {
      final r = (u['role'] ?? 'Unknown').toString();
      roleMap[r] = (roleMap[r] ?? 0) + 1;
    }

    // Unique stores
    final storeMap = <String, String>{};
    for (final u in _users) {
      final sid = u['storeId']?.toString();
      final sname = u['storeName']?.toString();
      if (sid != null && sname != null) {
        storeMap[sid] = sname;
      }
    }
    final hasNoStore = _users.any((u) => u['storeId'] == null);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          AdminHelpers.searchBar(
            controller: _searchCtrl,
            hint: 'Tìm theo tên, email, cửa hàng...',
            onChanged: _applyFilters,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildDropdown<String?>(
                value: _roleFilter,
                hint: 'Vai trò',
                items: [
                  _dropItem(null, 'Tất cả'),
                  ..._allRoles
                      .where((r) => roleMap.containsKey(r))
                      .map((r) => _dropItem(r, '$r (${roleMap[r]})'))
                ],
                onChanged: (v) {
                  _roleFilter = v;
                  _applyFilters();
                },
              ),
              _buildDropdown<String?>(
                value: _storeFilter,
                hint: 'Cửa hàng',
                items: [
                  _dropItem(null, 'Tất cả'),
                  if (hasNoStore) _dropItem('_none', 'Không thuộc CH'),
                  ...storeMap.entries
                      .map((e) => _dropItem(e.key, e.value)),
                ],
                onChanged: (v) {
                  _storeFilter = v;
                  _applyFilters();
                },
              ),
              ElevatedButton.icon(
                onPressed: _showCreateSuperAdminDialog,
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Tạo SuperAdmin'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AdminHelpers.primaryDark,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              AdminHelpers.countBadge(
                  'Tổng', _users.length, AdminHelpers.primary),
              const SizedBox(width: 8),
              ...roleMap.entries.map((e) {
                final color = _roleColor(e.key);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdminHelpers.countBadge(e.key, e.value, color),
                );
              }),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  DropdownMenuItem<String?> _dropItem(String? value, String label) {
    return DropdownMenuItem(
        value: value,
        child: Text(label, style: const TextStyle(fontSize: 13)));
  }

  // ═══════════════════════ STORE GROUP ═══════════════════════
  Widget _buildStoreGroup(
      String storeKey, List<Map<String, dynamic>> users) {
    final isNoStore = storeKey == '__no_store__';
    final storeName =
        isNoStore ? 'Hệ thống (không thuộc cửa hàng)' : users.first['storeName']?.toString() ?? 'N/A';
    final storeCode = isNoStore ? '' : users.first['storeCode']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNoStore
              ? AdminHelpers.primaryDark.withValues(alpha: 0.3)
              : AdminHelpers.primary.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: isNoStore
                ? AdminHelpers.primaryDark.withValues(alpha: 0.1)
                : AdminHelpers.primary.withValues(alpha: 0.1),
            child: Icon(
              isNoStore ? Icons.shield : Icons.store,
              color: isNoStore ? AdminHelpers.primaryDark : AdminHelpers.primary,
              size: 20,
            ),
          ),
          title: Row(children: [
            Text(storeName,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            if (storeCode.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('($storeCode)',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ]),
          subtitle: Text('${users.length} tài khoản',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          children: [
            const Divider(height: 24),
            if (MediaQuery.of(context).size.width < 600)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(users.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: _buildUserDeckItem(users[i]),
                  ),
                )),
              )
            else
              ...users.map((u) => _buildUserTile(u)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDeckItem(Map<String, dynamic> user) {
    final email = user['email'] ?? 'N/A';
    final fullName = user['fullName'] ?? '';
    final role = user['role']?.toString() ?? 'Unknown';
    final isActive = user['isActive'] as bool? ?? true;

    return InkWell(
      onTap: () => _showEditUserDialog(user),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _roleColor(role).withValues(alpha: 0.15),
            child: Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?', style: TextStyle(color: _roleColor(role), fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fullName.isNotEmpty ? fullName : email, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([email, role].join(' \u00b7 '), style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (!isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Text('T\u1eaft', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.red)),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  // ═══════════════════════ USER TILE ═══════════════════════
  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final email = user['email'] ?? 'N/A';
    final fullName = user['fullName'] ?? '';
    final role = user['role']?.toString() ?? 'Unknown';
    final isActive = user['isActive'] as bool? ?? true;
    final lastLogin = user['lastLoginAt'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Avatar + Name + Role chips
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _roleColor(role).withValues(alpha: 0.15),
                child: Text(
                    fullName.isNotEmpty
                        ? fullName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: _roleColor(role),
                      fontWeight: FontWeight.bold,
                    )),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                            fullName.isNotEmpty ? fullName : email,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                      ),
                      const SizedBox(width: 6),
                      AdminHelpers.statusChip(role, _roleColor(role)),
                      if (!isActive) ...[
                        const SizedBox(width: 4),
                        AdminHelpers.statusChip(
                            'Ngưng HĐ', AdminHelpers.danger),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.email,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(email,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600])),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: email));
                          AdminHelpers.showSuccess(
                              context, 'Đã copy email');
                        },
                        child: Icon(Icons.copy,
                            size: 14, color: Colors.grey[400]),
                      ),
                    ]),
                    if (lastLogin != null)
                      Text(
                          'Đăng nhập cuối: ${AdminHelpers.formatDateTime(lastLogin)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Password + Actions
          Row(
            children: [
              const SizedBox(width: 46),
              // Password area
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.vpn_key,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _resetPasswords.containsKey(userId)
                          ? SelectableText(
                              _resetPasswords[userId]!,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600))
                          : Text('••••••••',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[500])),
                    ),
                    if (_resetPasswords.containsKey(userId))
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: _resetPasswords[userId]!));
                          AdminHelpers.showSuccess(
                              context, 'Đã copy mật khẩu');
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.copy,
                              size: 14,
                              color: AdminHelpers.primary),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Row 3: Action buttons
          Row(
            children: [
              const SizedBox(width: 46),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _actionBtn(Icons.lock_reset, 'Đặt lại MK',
                        AdminHelpers.warning,
                        () => _resetPassword(userId, email)),
                    _actionBtn(Icons.edit, 'Sửa thông tin',
                        AdminHelpers.primary,
                        () => _showEditUserDialog(user)),
                    _actionBtn(Icons.admin_panel_settings, 'Đổi quyền',
                        AdminHelpers.info,
                        () => _showChangeRoleDialog(user)),
                    _actionBtn(Icons.delete_outline, 'Xóa TK',
                        AdminHelpers.danger,
                        () => _deleteUser(userId, email)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Color _roleColor(String role) {
    return switch (role.toLowerCase()) {
      'superadmin' => AdminHelpers.primaryDark,
      'admin' => AdminHelpers.info,
      'manager' => const Color(0xFF7C3AED),
      'agent' => AdminHelpers.warning,
      'employee' => AdminHelpers.success,
      _ => AdminHelpers.primary,
    };
  }

  // ═══════════════════════ RESET PASSWORD ═══════════════════════
  Future<void> _resetPassword(String userId, String email) async {
    final newPass = await AdminHelpers.showInputDialog(
      context,
      'Đặt lại mật khẩu',
      'Nhập mật khẩu mới cho $email',
    );
    if (newPass == null || newPass.isEmpty) return;

    final res = await _apiService.updateUserCredentials(
      userId,
      newPassword: newPass,
    );

    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _resetPasswords[userId] = newPass;
      });
      AdminHelpers.showSuccess(context, 'Đã đặt lại mật khẩu cho $email');
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ DELETE USER ═══════════════════════
  Future<void> _deleteUser(String userId, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa tài khoản'),
        content: Text('Bạn có chắc muốn xóa tài khoản "$email"?\n\nHành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminHelpers.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res = await _apiService.deleteSystemUser(userId);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã xóa tài khoản $email');
      loadData();
    } else {
      AdminHelpers.showError(context, res['message'] ?? 'Lỗi xóa tài khoản');
    }
  }

  // ═══════════════════════ CHANGE ROLE ═══════════════════════
  Future<void> _showChangeRoleDialog(Map<String, dynamic> user) async {
    final userId = user['id']?.toString() ?? '';
    final currentRole = user['role']?.toString() ?? 'User';
    final name = user['fullName'] ?? user['email'] ?? 'N/A';
    String selectedRole = currentRole;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.admin_panel_settings,
                color: AdminHelpers.info, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text('Đổi quyền — $name',
                    style: const TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _allRoles.map((role) {
                final isSelected = selectedRole == role;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected
                          ? _roleColor(role)
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    color: isSelected
                        ? _roleColor(role).withValues(alpha: 0.05)
                        : null,
                  ),
                  child: ListTile(
                    dense: true,
                    onTap: () =>
                        setDlgState(() => selectedRole = role),
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected
                          ? _roleColor(role)
                          : Colors.grey,
                      size: 20,
                    ),
                    title: Text(role,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _roleColor(role),
                        )),
                    subtitle: Text(_roleDescription(role),
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600])),
                    trailing: currentRole == role
                        ? const Chip(
                            label: Text('Hiện tại',
                                style: TextStyle(fontSize: 10)),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            ElevatedButton.icon(
              onPressed: selectedRole != currentRole
                  ? () => Navigator.pop(ctx, selectedRole)
                  : null,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Lưu'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primary),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final res = await _apiService.updateUserRole(userId, result);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(
          context, 'Đã đổi quyền $name thành $result');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  String _roleDescription(String role) {
    return switch (role) {
      'SuperAdmin' => 'Quản trị toàn hệ thống',
      'Admin' => 'Quản trị cửa hàng',
      'Manager' => 'Quản lý nhân viên, chấm công',
      'Employee' => 'Xem thông tin cá nhân',
      'User' => 'Người dùng cơ bản',
      'Agent' => 'Đại lý quản lý nhiều cửa hàng',
      _ => '',
    };
  }

  // ═══════════════════════ EDIT USER INFO ═══════════════════════
  void _showEditUserDialog(Map<String, dynamic> user) {
    final fullNameCtrl =
        TextEditingController(text: user['fullName']?.toString() ?? '');
    final emailCtrl =
        TextEditingController(text: user['email']?.toString() ?? '');
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.edit, color: AdminHelpers.primary, size: 22),
          SizedBox(width: 8),
          Text('Cập nhật thông tin', style: TextStyle(fontSize: 17)),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AdminHelpers.dialogField(
                fullNameCtrl, 'Họ tên', Icons.person),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                emailCtrl, 'Email', Icons.email),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                passwordCtrl,
                'Mật khẩu mới (để trống nếu giữ nguyên)',
                Icons.lock,
                obscureText: true),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final res = await _apiService.updateUserCredentials(
                user['id']?.toString() ?? '',
                newEmail: emailCtrl.text.trim(),
                newPassword: passwordCtrl.text.trim().isEmpty
                    ? null
                    : passwordCtrl.text,
                fullName: fullNameCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                loadData();
                if (mounted) {
                  AdminHelpers.showSuccess(
                      context, 'Cập nhật user thành công');
                }
              } else {
                if (mounted) AdminHelpers.showApiError(context, res);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    ).then((_) {
      fullNameCtrl.dispose();
      emailCtrl.dispose();
      passwordCtrl.dispose();
    });
  }

  // ═══════════════════════ CREATE SUPERADMIN ═══════════════════════
  void _showCreateSuperAdminDialog() {
    final fullNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.person_add,
              color: AdminHelpers.primaryDark, size: 22),
          SizedBox(width: 8),
          Text('Tạo SuperAdmin', style: TextStyle(fontSize: 17)),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AdminHelpers.dialogField(
                fullNameCtrl, 'Họ tên', Icons.person),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                emailCtrl, 'Email', Icons.email),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                passwordCtrl, 'Mật khẩu', Icons.lock,
                obscureText: true),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final res = await _apiService.createSuperAdmin(
                email: emailCtrl.text.trim(),
                password: passwordCtrl.text,
                fullName: fullNameCtrl.text.trim(),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                loadData();
                if (mounted) {
                  AdminHelpers.showSuccess(
                      context, 'Tạo SuperAdmin thành công');
                }
              } else {
                if (mounted) AdminHelpers.showApiError(context, res);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primaryDark,
                foregroundColor: Colors.white),
            child: const Text('Tạo'),
          ),
        ],
      ),
    ).then((_) {
      fullNameCtrl.dispose();
      emailCtrl.dispose();
      passwordCtrl.dispose();
    });
  }
}
