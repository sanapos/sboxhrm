import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/permission_role_options.dart';
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
  List<PermissionRoleOption> _roles = [];
  List<Map<String, dynamic>> _permissions = [];

  static const _posModules = <({String code, String label, String group})>[
    (code: 'PosSell', label: 'Bán hàng (màn bán)', group: 'Menu bán hàng'),
    (code: 'PosSaleOrders', label: 'Đơn hàng', group: 'Menu bán hàng'),
    (code: 'PosProducts', label: 'Thêm hàng hóa / catalog mẫu', group: 'Menu bán hàng'),
    (code: 'PosSaleReturns', label: 'Trả hàng', group: 'Menu bán hàng'),
    (code: 'PosCashierShift', label: 'Ca thu ngân', group: 'Menu bán hàng'),
    (code: 'PosKds', label: 'Màn hình bếp (KDS)', group: 'Menu bán hàng'),
    (code: 'PosQrOrder', label: 'QR order bàn', group: 'Menu bán hàng'),
    (code: 'PosCustomers', label: 'Khách hàng', group: 'Menu bán hàng'),
    (code: 'PosPurchaseReceipts', label: 'Nhập hàng', group: 'Kho'),
    (code: 'PosPurchaseReturns', label: 'Trả hàng nhập', group: 'Kho'),
    (code: 'PosStockCounts', label: 'Kiểm kho', group: 'Kho'),
    (code: 'PosDamageIssues', label: 'Xuất hủy', group: 'Kho'),
    (code: 'PosInternalUseIssues', label: 'Dùng nội bộ', group: 'Kho'),
    (code: 'CashTransaction', label: 'Phiếu thu / phiếu chi', group: 'Menu bán hàng'),
    (code: 'PosSalesReport', label: 'Báo cáo POS / cuối ngày', group: 'Menu bán hàng'),
    (code: 'SettingsHub', label: 'Trung tâm (ngành hàng, cửa hàng, sơ đồ bàn, cổng CK)', group: 'Thiết lập POS'),
    (code: 'PosPrinters', label: 'Máy in thiết bị', group: 'Thiết lập POS'),
    (code: 'PosStorePrinters', label: 'Máy in cloud', group: 'Thiết lập POS'),
    (code: 'PosPrintTemplates', label: 'Mẫu in', group: 'Thiết lập POS'),
    (code: 'PosEInvoice', label: 'Hóa đơn điện tử', group: 'Thiết lập POS'),
    (code: 'PosShipping', label: 'Đơn vị giao hàng', group: 'Thiết lập POS'),
    (code: 'PosCustomerDisplay', label: 'Màn hình phụ', group: 'Thiết lập POS'),
    (code: 'UserManagement', label: 'Tài khoản', group: 'Thiết lập POS'),
    (code: 'Role', label: 'Phân quyền', group: 'Thiết lập POS'),
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
    (code: 'PosReportStaffCommission', label: 'Hoa hồng nhân viên', group: 'Báo cáo'),
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
      var options = PermissionRoleOptions.parse(raw);
      if (options.isEmpty) options = PermissionRoleOptions.fallback;
      if (!mounted) return;
      setState(() {
        _roles = options;
        _loading = false;
      });
      final pick = options.any((r) => r.name == 'Cashier')
          ? 'Cashier'
          : options.first.name;
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

  static const _caps = <String, Set<String>>{
    'PosSell': {'canView', 'canCreate', 'canEdit', 'canApprove'},
    'PosSaleOrders': {'canView', 'canEdit', 'canDelete'},
    'PosProducts': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PosSaleReturns': {'canView', 'canApprove'},
    'PosCashierShift': {'canView', 'canCreate'},
    'PosKds': {'canView', 'canCreate'},
    'PosQrOrder': {'canView', 'canEdit', 'canApprove'},
    'PosCustomers': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PosPurchaseReceipts': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PosPurchaseReturns': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PosStockCounts': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PosDamageIssues': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PosInternalUseIssues': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'CashTransaction': {'canView', 'canCreate', 'canEdit', 'canDelete', 'canApprove'},
    'SettingsHub': {'canView', 'canEdit'},
    'PosPrinters': {'canView', 'canEdit'},
    'PosStorePrinters': {'canView', 'canEdit'},
    'PosPrintTemplates': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'PosEInvoice': {'canView', 'canEdit', 'canApprove'},
    'PosShipping': {'canView', 'canCreate', 'canEdit'},
    'PosCustomerDisplay': {'canView', 'canCreate', 'canEdit'},
    'UserManagement': {'canView', 'canCreate', 'canEdit', 'canDelete'},
    'Role': {'canView', 'canCreate', 'canEdit', 'canDelete'},
  };

  static const _colActions = <(String key, String label)>[
    ('canView', 'Xem'),
    ('canCreate', 'Order'),
    ('canEdit', 'Sửa'),
    ('canDelete', 'Xóa'),
    ('canApprove', 'Duyệt'),
  ];

  bool _supports(String code, String action) {
    if (code.startsWith('PosReport') ||
        code == 'PosSalesReport' ||
        code == 'HkdBooks') {
      return action == 'canView';
    }
    return _caps[code]?.contains(action) ?? action == 'canView';
  }

  bool _flag(String code, String action) {
    final p = _perm(code);
    if (p == null) return false;
    final pascal = action[0].toUpperCase() + action.substring(1);
    return p[action] == true || p[pascal] == true;
  }

  bool _view(String code) => _flag(code, 'canView');

  Map<String, dynamic> _ensurePerm(String code) {
    var p = _perm(code);
    if (p != null) return p;
    p = {
      'module': code,
      'canView': false,
      'canCreate': false,
      'canEdit': false,
      'canDelete': false,
      'canExport': false,
      'canApprove': false,
    };
    _permissions.add(p);
    return p;
  }

  void _setFlag(String code, String action, bool on) {
    setState(() {
      final p = _ensurePerm(code);
      void write(String key, bool v) {
        p[key] = v;
        p[key[0].toUpperCase() + key.substring(1)] = v;
      }

      if (action == 'canView' && !on) {
        write('canView', false);
        write('canCreate', false);
        write('canEdit', false);
        write('canDelete', false);
        write('canApprove', false);
        write('canExport', false);
        return;
      }
      if (on) write('canView', true);
      write(action, on);
      if (code.startsWith('PosReport') || code == 'PosSalesReport') {
        write('canExport', on);
      }
      if (code == 'PosSaleOrders' && action == 'canEdit') {
        write('canDelete', on);
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
                            selected: r.name == _role,
                            selectedTileColor: PosTheme.kiotBlueLight,
                            title: Text(tr(r.displayName)),
                            onTap: () => _selectRole(r.name),
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
                                  tr('Admin không chỉnh sửa — chọn Cashier / Waiter để giới hạn menu và thiết lập.'),
                                  style: const TextStyle(color: PosTheme.textSecondary),
                                ),
                              )
                            else
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  tr('Xem = mở menu. Order = gọi món / mở ca / bump bếp. Sửa = sửa đơn / cấu hình. Xóa = xóa đơn / phiếu. Duyệt = thanh toán / trả hàng / HĐĐT / đơn online. Thu ngân: Xem + Order + Duyệt bán hàng — không tick Sửa thiết lập POS.'),
                                  style: const TextStyle(
                                    color: PosTheme.textSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  const Spacer(),
                                  for (final col in _colActions)
                                    SizedBox(
                                      width: 44,
                                      child: Text(
                                        tr(col.$2),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
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
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          tr(m.label),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      for (final col in _colActions)
                                        SizedBox(
                                          width: 44,
                                          child: _supports(m.code, col.$1)
                                              ? Checkbox(
                                                  value: _flag(m.code, col.$1),
                                                  onChanged: _roleLocked
                                                      ? null
                                                      : (v) => _setFlag(
                                                            m.code,
                                                            col.$1,
                                                            v ?? false,
                                                          ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                    ],
                                  ),
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
