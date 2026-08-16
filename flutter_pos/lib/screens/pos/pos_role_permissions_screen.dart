import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';

/// Phân quyền POS trên A6 — tập trung module bán hàng và 14 báo cáo.
class PosRolePermissionsScreen extends StatefulWidget {
  const PosRolePermissionsScreen({super.key});

  @override
  State<PosRolePermissionsScreen> createState() =>
      _PosRolePermissionsScreenState();
}

class _PosRolePermissionsScreenState extends State<PosRolePermissionsScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  String? _role;
  List<String> _roles = [];
  List<Map<String, dynamic>> _permissions = [];

  static const _posModules = <({String code, String label, String group})>[
    (code: 'PosSell', label: 'Bán hàng', group: 'Bán hàng'),
    (code: 'PosProducts', label: 'Hàng hóa', group: 'Bán hàng'),
    (code: 'PosSaleOrders', label: 'Hóa đơn', group: 'Bán hàng'),
    (code: 'PosSaleReturns', label: 'Trả hàng', group: 'Bán hàng'),
    (code: 'SettingsHub', label: 'Thiết lập POS', group: 'Bán hàng'),
    (code: 'UserManagement', label: 'Tài khoản', group: 'Bán hàng'),
    (code: 'Role', label: 'Phân quyền', group: 'Bán hàng'),
    (code: 'PosSalesReport', label: 'Hub báo cáo', group: 'Báo cáo'),
    (code: 'PosReportRevenue', label: 'Doanh thu', group: 'Báo cáo'),
    (code: 'PosReportSoldGoods', label: 'Hàng hóa bán ra', group: 'Báo cáo'),
    (code: 'PosReportStock', label: 'Tồn kho', group: 'Báo cáo'),
    (code: 'PosReportPurchases', label: 'Nhập hàng', group: 'Báo cáo'),
    (code: 'PosReportPayment', label: 'PTTT', group: 'Báo cáo'),
    (code: 'PosReportDebt', label: 'Công nợ', group: 'Báo cáo'),
    (code: 'PosReportExpiry', label: 'Hàng hết hạn', group: 'Báo cáo'),
    (code: 'PosReportProfit', label: 'Lợi nhuận', group: 'Báo cáo'),
    (code: 'PosReportExpense', label: 'Chi phí', group: 'Báo cáo'),
    (code: 'PosReportEndOfDay', label: 'Cuối ngày', group: 'Báo cáo'),
    (code: 'PosReportStaffRevenue', label: 'Doanh thu theo NV', group: 'Báo cáo'),
    (code: 'PosReportCashbook', label: 'Sổ quỹ', group: 'Báo cáo'),
    (code: 'PosReportPnl', label: 'Kết quả KD', group: 'Báo cáo'),
    (code: 'PosReportVoucher', label: 'Voucher', group: 'Báo cáo'),
    (code: 'HkdBooks', label: 'Thuế hộ kinh doanh', group: 'Báo cáo'),
  ];

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    setState(() => _loading = true);
    try {
      final raw = await _api.getRoles();
      final names = <String>{};
      for (final e in raw) {
        if (e is String && e.trim().isNotEmpty) {
          names.add(e.trim());
        } else if (e is Map) {
          final n = (e['roleName'] ?? e['RoleName'] ?? e['name'] ?? e['Name'] ?? '')
              .toString()
              .trim();
          if (n.isNotEmpty) names.add(n);
        }
      }
      if (names.isEmpty) {
        names.addAll(['Admin', 'Manager', 'Cashier', 'Waiter', 'Employee']);
      }
      if (!mounted) return;
      setState(() {
        _roles = names.toList()..sort();
        _loading = false;
      });
      final pick = _roles.contains('Cashier') ? 'Cashier' : _roles.first;
      await _selectRole(pick);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Không tải vai trò',
        message: '$e',
      );
    }
  }

  Future<void> _selectRole(String role) async {
    setState(() {
      _role = role;
      _loading = true;
    });
    final data = await _api.getRolePermissions(role);
    final perms = <Map<String, dynamic>>[];
    final src = data['permissions'] ?? data['Permissions'];
    if (src is List) {
      for (final e in src) {
        if (e is Map) perms.add(Map<String, dynamic>.from(e));
      }
    }
    for (final m in _posModules) {
      if (perms.any((p) => '${p['module'] ?? p['Module']}' == m.code)) continue;
      perms.add({
        'module': m.code,
        'canView': false,
        'canCreate': false,
        'canEdit': false,
        'canDelete': false,
        'canExport': false,
        'canApprove': false,
      });
    }
    if (!mounted) return;
    setState(() {
      _permissions = perms;
      _loading = false;
    });
  }

  Map<String, dynamic>? _perm(String code) {
    for (final p in _permissions) {
      if ('${p['module'] ?? p['Module']}' == code) return p;
    }
    return null;
  }

  bool _view(String code) {
    final p = _perm(code);
    if (p == null) return false;
    return p['canView'] == true || p['CanView'] == true;
  }

  void _setView(String code, bool on) {
    setState(() {
      var p = _perm(code);
      if (p == null) {
        p = {
          'module': code,
          'canView': on,
          'canCreate': false,
          'canEdit': false,
          'canDelete': false,
          'canExport': on,
          'canApprove': false,
        };
        _permissions.add(p);
      } else {
        p['canView'] = on;
        p['CanView'] = on;
        if (code.startsWith('PosReport') || code == 'PosSalesReport') {
          p['canExport'] = on;
        }
        if (code == 'PosSell' && on) {
          p['canCreate'] = true;
          p['canApprove'] = true;
        }
      }
    });
  }

  bool get _roleLocked =>
      (_role ?? '').toLowerCase() == 'admin' ||
      (_role ?? '').toLowerCase() == 'superadmin';

  Future<void> _save() async {
    final role = _role;
    if (role == null) return;
    if (_roleLocked) {
      NotificationOverlayManager().showWarning(
        title: 'Không sửa Admin',
        message: tr('Quyền Admin luôn đủ mọi module'),
      );
      return;
    }
    setState(() => _saving = true);
    final posCodes = _posModules.map((m) => m.code).toSet();
    final payload = _permissions
        .where((p) => posCodes.contains('${p['module'] ?? p['Module']}'))
        .map((p) {
      final code = '${p['module'] ?? p['Module']}';
      return {
        'module': code,
        'canView': p['canView'] == true || p['CanView'] == true,
        'canCreate': p['canCreate'] == true || p['CanCreate'] == true,
        'canEdit': p['canEdit'] == true || p['CanEdit'] == true,
        'canDelete': p['canDelete'] == true || p['CanDelete'] == true,
        'canExport': p['canExport'] == true || p['CanExport'] == true,
        'canApprove': p['canApprove'] == true || p['CanApprove'] == true,
      };
    }).toList();
    final res = await _api.saveRolePermissions({
      'roleName': role,
      'permissions': payload,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã lưu phân quyền',
        message: role,
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: '${res['message'] ?? res}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<({String code, String label, String group})>>{};
    for (final m in _posModules) {
      groups.putIfAbsent(m.group, () => []).add(m);
    }
    return ColoredBox(
      color: PosTheme.background,
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Material(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      tr('Vai trò'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final r in _roles)
                          ListTile(
                            selected: r == _role,
                            selectedTileColor: PosTheme.kiotBlueLight,
                            title: Text(tr(r)),
                            onTap: () => _selectRole(r),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Material(
              color: PosTheme.background,
              child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr('Quyền POS · ${_role ?? ''}'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: (_saving || _roleLocked) ? null : _save,
                              style: FilledButton.styleFrom(
                                backgroundColor: PosTheme.kiotBlue,
                              ),
                              icon: _saving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(tr('Lưu')),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            if (_roleLocked)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  tr('Admin không chỉnh sửa — chọn Cashier để giới hạn báo cáo.'),
                                  style: const TextStyle(color: PosTheme.textSecondary),
                                ),
                              ),
                            for (final g in groups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 4),
                                child: Text(
                                  tr(g.key),
                                  style: const TextStyle(
                                    color: PosTheme.kiotBlue,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              for (final m in g.value)
                                SwitchListTile(
                                  value: _view(m.code),
                                  onChanged: _roleLocked
                                      ? null
                                      : (v) => _setView(m.code, v),
                                  title: Text(tr(m.label)),
                                  dense: true,
                                ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
