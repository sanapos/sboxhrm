import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';

/// Tài khoản cửa hàng trên POS (A6) — tạo / xem thu ngân để phân quyền báo cáo.
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

  static const _roles = [
    'Cashier',
    'Manager',
    'Waiter',
    'Employee',
    'Admin',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.getAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
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

  Future<void> _openCreate() async {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var role = 'Cashier';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return AlertDialog(
              title: Text(tr('Tạo tài khoản')),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: tr('Họ tên'),
                        ),
                      ),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: tr('Email'),
                        ),
                      ),
                      TextField(
                        controller: userCtrl,
                        decoration: InputDecoration(
                          labelText: tr('Tên đăng nhập'),
                        ),
                      ),
                      TextField(
                        controller: passCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: tr('Mật khẩu (≥ 6 ký tự)'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: InputDecoration(labelText: tr('Vai trò')),
                        items: [
                          for (final r in _roles)
                            DropdownMenuItem(value: r, child: Text(tr(r))),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setModal(() => role = v);
                        },
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
                  child: Text(tr('Tạo')),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final email = emailCtrl.text.trim();
    final userName = userCtrl.text.trim().isEmpty
        ? email.split('@').first
        : userCtrl.text.trim();
    final full = nameCtrl.text.trim();
    final parts = full.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final first = parts.isEmpty ? userName : parts.last;
    final last = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : '';
    if (email.isEmpty || passCtrl.text.length < 6) {
      NotificationOverlayManager().showWarning(
        title: 'Thiếu thông tin',
        message: tr('Cần email và mật khẩu từ 6 ký tự'),
      );
      return;
    }
    final res = await _api.createAccount({
      'userName': userName,
      'firstName': first,
      'lastName': last,
      'email': email,
      'role': role,
      'password': passCtrl.text,
    });
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final id = (res['data'] is Map) ? '${res['data']['id'] ?? ''}' : '';
      if (id.isNotEmpty) {
        await _api.toggleAccountStatus(id, true);
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
                  onPressed: _openCreate,
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
                          final roles = a['roles'];
                          final role = (a['role'] ??
                                  (roles is List && roles.isNotEmpty
                                      ? roles.first
                                      : ''))
                              .toString();
                          final mine = email.isNotEmpty &&
                              email.toLowerCase() == me.toLowerCase();
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: PosTheme.kiotBlueLight,
                                child: Text(
                                  _displayName(a).isEmpty
                                      ? '?'
                                      : _displayName(a)[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: PosTheme.kiotBlue,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              title: Text(
                                tr(_displayName(a)),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                tr('$email · $role${mine ? ' · đang đăng nhập' : ''}'),
                              ),
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
