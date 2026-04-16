import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _users = [];
  List<String> _availableRoles = [];
  String _searchQuery = '';
  int _currentPage = 1;
  final int _pageSize = 20;
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getUsers(),
        _apiService.getAvailableRoles(),
      ]);
      setState(() {
        if (results[0]['isSuccess'] == true) _users = List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
        if (results[1]['isSuccess'] == true) _availableRoles = List<String>.from(results[1]['data'] ?? []);
      });
    } catch (e) {
      debugPrint('Error loading users: $e');
    }
    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    final q = _searchQuery.toLowerCase();
    return _users.where((u) {
      final name = (u['userName'] ?? u['fullName'] ?? u['email'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList();
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin': return const Color(0xFFDC2626);
      case 'manager': return const Color(0xFF0F2340);
      case 'hr': return const Color(0xFF0F2340);
      case 'user': case 'employee': return const Color(0xFF1E3A5F);
      default: return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildUserList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = Responsive.isMobile(context);
    final activeCount = _users.where((u) => u['isLocked'] != true && u['lockoutEnabled'] != true).length;
    final lockedCount = _users.where((u) => u['isLocked'] == true || u['lockoutEnabled'] == true).length;
    final searchField = SizedBox(
      width: isMobile ? double.infinity : 280,
      child: TextField(
        onChanged: (v) => setState(() { _searchQuery = v; _currentPage = 1; }),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Tìm kiếm...',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(Icons.search, color: Colors.white70, size: 20),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 20, isMobile ? 16 : 24, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF18181B), Color(0xFF52525B)]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.admin_panel_settings, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quản lý tài khoản', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    Text('Phân quyền, khóa/mở khóa tài khoản', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isMobile) ...[
            Row(
              children: [
                _buildStatChip(Icons.people, '${_users.length}', 'Tổng'),
                const SizedBox(width: 10),
                _buildStatChip(Icons.check_circle_outline, '$activeCount', 'Hoạt động'),
                const SizedBox(width: 10),
                _buildStatChip(Icons.lock_outline, '$lockedCount', 'Bị khóa'),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                  child: Stack(
                    children: [
                      Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, color: Colors.white, size: 22),
                      if (_searchQuery.isNotEmpty)
                        Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                    ],
                  ),
                ),
              ],
            ),
            if (_showMobileFilters) ...[            const SizedBox(height: 10),
            searchField,
            ],
          ] else
            Row(
              children: [
                _buildStatChip(Icons.people, '${_users.length}', 'Tổng'),
                const SizedBox(width: 10),
                _buildStatChip(Icons.check_circle_outline, '$activeCount', 'Hoạt động'),
                const SizedBox(width: 10),
                _buildStatChip(Icons.lock_outline, '$lockedCount', 'Bị khóa'),
                const Spacer(),
                searchField,
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 6),
        Text('$value $label', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildUserList() {
    final filtered = _filteredUsers;
    if (filtered.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.person_search, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(_searchQuery.isNotEmpty ? 'Không tìm thấy tài khoản' : 'Chưa có tài khoản', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ]),
      );
    }
    final totalCount = filtered.length;
    final isMobile = Responsive.isMobile(context);
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = isMobile ? 0 : (page - 1) * _pageSize;
    final endIndex = isMobile ? totalCount : (page * _pageSize).clamp(0, totalCount);
    final paginatedUsers = filtered.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: paginatedUsers.length,
            itemBuilder: (ctx, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildUserDeckItem(paginatedUsers[i]),
              ),
            ),
          ),
        ),
        if (!isMobile)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Hiển thị ${startIndex + 1}-$endIndex / $totalCount',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    onPressed: page > 1 ? () => setState(() => _currentPage--) : null,
                    visualDensity: VisualDensity.compact,
                  ),
                  Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    onPressed: page < totalPages ? () => setState(() => _currentPage++) : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserDeckItem(Map<String, dynamic> user) {
    final isLocked = user['isLocked'] == true || user['lockoutEnabled'] == true;
    final role = user['role'] ?? user['roles']?.toString() ?? 'User';
    final roleColor = _getRoleColor(role);

    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: roleColor.withValues(alpha: 0.1),
                  child: Text(
                    (user['userName'] ?? user['fullName'] ?? 'U').toString().substring(0, 1).toUpperCase(),
                    style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                if (isLocked)
                  Positioned(
                    right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.lock, color: Colors.white, size: 9),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(user['fullName'] ?? user['userName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(role, style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (user['email'] != null) user['email'],
                      isLocked ? 'Bị khóa' : 'Hoạt động',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 18),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'role', child: Row(children: [Icon(Icons.security, size: 16), SizedBox(width: 8), Text('Đổi vai trò')])),
                PopupMenuItem(
                  value: isLocked ? 'unlock' : 'lock',
                  child: Row(children: [
                    Icon(isLocked ? Icons.lock_open : Icons.lock, size: 16, color: isLocked ? Colors.green : Colors.orange),
                    const SizedBox(width: 8),
                    Text(isLocked ? 'Mở khóa' : 'Khóa'),
                  ]),
                ),
                const PopupMenuItem(value: 'reset', child: Row(children: [Icon(Icons.password, size: 16, color: Colors.blue), SizedBox(width: 8), Text('Đặt lại mật khẩu')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Xóa', style: TextStyle(color: Colors.red))])),
              ],
              onSelected: (v) => _handleAction(v, user),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(String action, Map<String, dynamic> user) async {
    final userId = user['id']?.toString() ?? '';
    switch (action) {
      case 'role':
        _showChangeRoleDialog(user);
        break;
      case 'lock':
        final confirm = await _confirmAction('Khóa tài khoản', 'Khóa "${user['fullName'] ?? user['userName']}"?');
        if (confirm) {
          try { await _apiService.lockUser(userId); _loadData(); } catch (e) { debugPrint('Error: $e'); }
        }
        break;
      case 'unlock':
        try { await _apiService.unlockUser(userId); _loadData(); } catch (e) { debugPrint('Error: $e'); }
        break;
      case 'reset':
        _showResetPasswordDialog(user);
        break;
      case 'delete':
        final confirm = await _confirmAction('Xóa tài khoản', 'Xóa "${user['fullName'] ?? user['userName']}"? Hành động này không thể hoàn tác.');
        if (confirm) {
          try {
            final result = await _apiService.deleteUser(userId);
            if (mounted) {
              if (result['isSuccess'] == true) {
                NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa tài khoản thành công');
              } else {
                NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi xóa tài khoản');
              }
            }
            _loadData();
          } catch (e) {
            if (mounted) {
              NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
            }
          }
        }
        break;
    }
  }

  Future<bool> _confirmAction(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Xác nhận')),
        ],
      ),
    ) ?? false;
  }

  void _showChangeRoleDialog(Map<String, dynamic> user) {
    String? selectedRole = user['role'] ?? user['roles']?.toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi vai trò'),
        content: SizedBox(
          width: 350,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Tài khoản: ${user['fullName'] ?? user['userName']}', style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _availableRoles.contains(selectedRole) ? selectedRole : null,
              decoration: InputDecoration(labelText: 'Vai trò', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              items: _availableRoles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => selectedRole = v,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (selectedRole != null) {
                try {
                  await _apiService.changeUserRole(user['id']?.toString() ?? '', selectedRole!);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadData();
                } catch (e) {
                  debugPrint('Error: $e');
                }
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showResetPasswordDialog(Map<String, dynamic> user) {
    final pwdCtrl = TextEditingController();
    bool obscure = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Đặt lại mật khẩu'),
          content: SizedBox(
            width: 350,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Tài khoản: ${user['fullName'] ?? user['userName']}', style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 16),
              TextField(
                controller: pwdCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu mới',
                  prefixIcon: const Icon(Icons.lock, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                if (pwdCtrl.text.isNotEmpty) {
                  try {
                    final result = await _apiService.resetUserPassword(user['id']?.toString() ?? '', newPassword: pwdCtrl.text);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      if (result['isSuccess'] == true) {
                        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã đặt lại mật khẩu');
                      } else {
                        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
                      }
                    }
                  } catch (e) {
                    debugPrint('Error: $e');
                  }
                }
              },
              child: const Text('Đặt lại'),
            ),
          ],
        ),
      ),
    );
  }
}
