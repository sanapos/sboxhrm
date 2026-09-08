import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/permission_role_options.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';

/// Tài khoản cửa hàng trên POS — tạo / xem / sửa, đổi mật khẩu, gán khu vực bàn.
class PosAccountsScreen extends StatefulWidget {
  const PosAccountsScreen({super.key});

  @override
  State<PosAccountsScreen> createState() => _PosAccountsScreenState();
}

class _PosAccountsScreenState extends State<PosAccountsScreen> {
  final _api = ApiService();
  bool _loading = true;
  String _query = '';
  List<Map<String, dynamic>> _accounts = [];
  List<PermissionRoleOption> _roleOptions = PermissionRoleOptions.fallback;

  /// Vai trò làm sơ đồ: gán khu thì chỉ thấy bàn khu đó.
  static const _areaRoles = {'Cashier', 'Waiter', 'Employee', 'User'};

  String _roleLabel(String role) {
    for (final r in _roleOptions) {
      if (r.name.toLowerCase() == role.toLowerCase()) return r.displayName;
    }
    return PermissionRoleOptions.displayNameOf(role);
  }

  List<String> get _roleNames =>
      _roleOptions.map((e) => e.name).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.getAccounts(),
        _api.getRoles(),
      ]);
      if (!mounted) return;
      final raw = results[0] as List;
      final parsed = PermissionRoleOptions.parse(results[1] as List);
      setState(() {
        _accounts = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (parsed.isNotEmpty) _roleOptions = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Không tải tài khoản',
        message: '$e',
      );
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _accounts;
    return _accounts.where((a) {
      final blob = [
        a['email'],
        a['userName'],
        a['fullName'],
        a['firstName'],
        a['lastName'],
        a['role'],
        a['roles'],
      ].map((e) => '${e ?? ''}'.toLowerCase()).join(' ');
      return blob.contains(q);
    }).toList();
  }

  String _displayName(Map<String, dynamic> a) {
    final full = (a['fullName'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    final last = (a['lastName'] ?? '').toString().trim();
    final first = (a['firstName'] ?? '').toString().trim();
    final joined = [last, first].where((e) => e.isNotEmpty).join(' ');
    if (joined.isNotEmpty) return joined;
    return (a['email'] ?? a['userName'] ?? 'Tài khoản').toString();
  }

  String _roleOf(Map<String, dynamic> a) {
    final roles = a['roles'];
    return (a['role'] ??
            (roles is List && roles.isNotEmpty ? roles.first : ''))
        .toString();
  }

  bool _isActive(Map<String, dynamic> a) {
    final v = a['isActive'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = '${v ?? ''}'.toLowerCase();
    if (s == 'false' || s == '0') return false;
    return true;
  }

  ({String first, String last}) _nameParts(String full, String fallback) {
    final parts = full.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return (first: fallback, last: '');
    if (parts.length == 1) return (first: parts.first, last: '');
    return (
      first: parts.last,
      last: parts.sublist(0, parts.length - 1).join(' '),
    );
  }

  Future<List<Map<String, dynamic>>> _loadAreas() async {
    try {
      final res = await _api.getPosServiceAreas();
      final data = res['data'];
      final list = data is List
          ? data
          : (data is Map
              ? (data['items'] ?? data['areas'] ?? data['data'])
              : null);
      if (list is! List) return [];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Set<String>> _loadAssignedAreaIds(String userId) async {
    if (userId.isEmpty) return {};
    try {
      final res = await _api.getPosUserServiceAreas(userId);
      if (res['isSuccess'] != true || res['data'] is! Map) return {};
      final data = Map<String, dynamic>.from(res['data'] as Map);
      final ids = data['areaIds'];
      if (ids is! List) return {};
      return ids.map((e) => '$e').where((e) => e.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAreas(String userId, String role, Set<String> areaIds) async {
    if (userId.isEmpty) return;
    final ids = _areaRoles.contains(role) ? areaIds.toList() : <String>[];
    try {
      await _api.setPosUserServiceAreas(userId, ids);
    } catch (_) {}
  }

  Future<void> _openEditor({Map<String, dynamic>? account}) async {
    final isEditing = account != null;
    final areas = await _loadAreas();
    final assigned = isEditing
        ? await _loadAssignedAreaIds('${account['id'] ?? ''}')
        : <String>{};
    if (!mounted) return;

    final nameCtrl = TextEditingController(
      text: isEditing ? _displayName(account) : '',
    );
    final emailCtrl = TextEditingController(
      text: isEditing ? '${account['email'] ?? ''}' : '',
    );
    final userCtrl = TextEditingController(
      text: isEditing ? '${account['userName'] ?? ''}' : '',
    );
    final phoneCtrl = TextEditingController(
      text: isEditing ? '${account['phoneNumber'] ?? ''}' : '',
    );
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var role = isEditing ? _roleOf(account) : 'Cashier';
    if (!_roleNames.any((n) => n.toLowerCase() == role.toLowerCase())) {
      role = _roleNames.contains('Cashier')
          ? 'Cashier'
          : (_roleNames.isNotEmpty ? _roleNames.first : 'Cashier');
    }
    var active = isEditing ? _isActive(account) : true;
    var showPass = false;
    final selectedAreaIds = {...assigned};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return AlertDialog(
              title: Text(
                tr(isEditing ? 'Xem / sửa tài khoản' : 'Tạo tài khoản'),
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(labelText: tr('Họ tên')),
                      ),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(labelText: tr('Email')),
                      ),
                      TextField(
                        controller: userCtrl,
                        decoration: InputDecoration(
                          labelText: tr('Tên đăng nhập'),
                        ),
                      ),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: tr('Số điện thoại'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(isEditing
                            ? 'Đặt lại mật khẩu nhân viên'
                            : 'Mật khẩu'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextField(
                        controller: passCtrl,
                        obscureText: !showPass,
                        decoration: InputDecoration(
                          labelText: tr(isEditing
                              ? 'Mật khẩu mới (để trống nếu giữ nguyên)'
                              : 'Mật khẩu (≥ 6 ký tự)'),
                          suffixIcon: IconButton(
                            icon: Icon(
                              showPass
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () =>
                                setModal(() => showPass = !showPass),
                          ),
                        ),
                      ),
                      TextField(
                        controller: confirmCtrl,
                        obscureText: !showPass,
                        decoration: InputDecoration(
                          labelText: tr('Xác nhận mật khẩu'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: InputDecoration(labelText: tr('Vai trò')),
                        items: [
                          for (final r in _roleOptions)
                            DropdownMenuItem(
                              value: r.name,
                              child: Text(tr(r.displayName)),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setModal(() => role = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr('Khu vực làm việc (sơ đồ bàn)'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr(areas.isEmpty
                            ? 'Chưa có khu vực — thêm nhóm bàn ở sơ đồ POS. Không chọn = xem tất cả.'
                            : (selectedAreaIds.isEmpty
                                ? 'Chưa chọn = xem tất cả khu vực'
                                : 'Chỉ hiện bàn thuộc ${selectedAreaIds.length} khu đã chọn')),
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
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
                              setModal(() => selectedAreaIds.clear());
                            },
                          ),
                          for (final area in areas)
                            FilterChip(
                              label: Text(
                                '${area['name'] ?? area['Name'] ?? area['code'] ?? area['Code'] ?? ''}',
                              ),
                              selected: selectedAreaIds.contains(
                                '${area['id'] ?? area['Id'] ?? ''}',
                              ),
                              onSelected: (on) {
                                final id = '${area['id'] ?? area['Id'] ?? ''}';
                                if (id.isEmpty) return;
                                setModal(() {
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
                      if (isEditing)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr('Đang hoạt động')),
                          value: active,
                          onChanged: (v) => setModal(() => active = v),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Hủy')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(tr(isEditing ? 'Lưu' : 'Tạo')),
                ),
              ],
            );
          },
        );
      },
    );
    final email = emailCtrl.text.trim();
    final userName = userCtrl.text.trim().isEmpty
        ? email.split('@').first
        : userCtrl.text.trim();
    final full = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final parts = _nameParts(full, userName);
    final pass = passCtrl.text;
    final confirm = confirmCtrl.text;
    final areaSnapshot = {...selectedAreaIds};
    nameCtrl.dispose();
    emailCtrl.dispose();
    userCtrl.dispose();
    phoneCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    if (ok != true) return;

    if (email.isEmpty || userName.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu thông tin',
        message: tr('Cần họ tên, email và tên đăng nhập'),
      );
      return;
    }
    if (full.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu thông tin',
        message: tr('Cần họ tên'),
      );
      return;
    }
    if (!isEditing && pass.length < 6) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu thông tin',
        message: tr('Cần email và mật khẩu từ 6 ký tự'),
      );
      return;
    }
    if (pass.isNotEmpty && pass.length < 6) {
      NotificationOverlayManager().showWarning(
        title: 'Mật khẩu yếu',
        message: tr('Mật khẩu tối thiểu 6 ký tự'),
      );
      return;
    }
    if (pass.isNotEmpty && pass != confirm) {
      NotificationOverlayManager().showWarning(
        title: 'Mật khẩu không khớp',
        message: tr('Vui lòng nhập lại mật khẩu'),
      );
      return;
    }

    if (!isEditing) {
      final res = await _api.createAccount({
        'userName': userName,
        'firstName': parts.first,
        'lastName': parts.last,
        'email': email,
        'phoneNumber': phone,
        'role': role,
        'password': pass,
      });
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final id = (res['data'] is Map) ? '${res['data']['id'] ?? ''}' : '';
        if (id.isNotEmpty) {
          await _api.toggleAccountStatus(id, true);
          await _saveAreas(id, role, areaSnapshot);
        }
        NotificationOverlayManager().showSuccess(
          title: 'Đã tạo tài khoản',
          message: '$email · $role',
        );
        await _load();
      } else {
        NotificationOverlayManager().showError(
          title: 'Không tạo được',
          message: '${res['message'] ?? res}',
        );
      }
      return;
    }

    final editing = account!;
    final id = '${editing['id'] ?? ''}';
    if (id.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Không sửa được',
        message: tr('Thiếu mã tài khoản'),
      );
      return;
    }
    final res = await _api.updateAccount(id, {
      'userName': userName,
      'firstName': parts.first,
      'lastName': parts.last,
      'email': email,
      'phoneNumber': phone,
      'role': role,
    });
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: '${res['message'] ?? res}',
      );
      return;
    }
    if (pass.length >= 6) {
      final pwd = await _api.resetAccountPassword(id, pass);
      if (pwd['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Đã lưu thông tin, lỗi mật khẩu',
          message: '${pwd['message'] ?? pwd}',
        );
        await _load();
        return;
      }
    }
    if (_isActive(editing) != active) {
      await _api.toggleAccountStatus(id, active);
    }
    await _saveAreas(id, role, areaSnapshot);
    NotificationOverlayManager().showSuccess(
      title: 'Đã cập nhật tài khoản',
      message: '$email · $role',
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final me = Provider.of<AuthProvider>(context).user?.email ?? '';
    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      hintText: tr('Tìm email, tên, vai trò'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: PosTheme.border),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.kiotBlue,
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(tr('Tạo tài khoản')),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(child: Text(tr('Chưa có tài khoản')))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final a = _filtered[i];
                          final email = (a['email'] ?? '').toString();
                          final role = _roleOf(a);
                          final mine = email.isNotEmpty &&
                              email.toLowerCase() == me.toLowerCase();
                          final active = _isActive(a);
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              onTap: () => _openEditor(account: a),
                              leading: CircleAvatar(
                                backgroundColor: active
                                    ? PosTheme.kiotBlueLight
                                    : const Color(0xFFE4E4E7),
                                child: Text(
                                  _displayName(a).isEmpty
                                      ? '?'
                                      : _displayName(a)[0].toUpperCase(),
                                  style: TextStyle(
                                    color: active
                                        ? PosTheme.kiotBlue
                                        : const Color(0xFF71717A),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(
                                _displayName(a),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  email,
                                  _roleLabel(role),
                                  if (!active) tr('ngừng'),
                                  if (mine) tr('đang đăng nhập'),
                                ]
                                    .where((e) => e.toString().isNotEmpty)
                                    .join(' · '),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
