import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';
import '../../widgets/hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class ServicePackagesTab extends StatefulWidget {
  const ServicePackagesTab({super.key});

  @override
  State<ServicePackagesTab> createState() => ServicePackagesTabState();
}

class ServicePackagesTabState extends State<ServicePackagesTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _availableModules = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  List<Map<String, dynamic>> get packages => _packages;

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getServicePackages(),
        _apiService.getAvailableModules(),
      ]);
      if (!mounted) return;
      if (results[0]['isSuccess'] == true) {
        _packages =
            List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
      }
      if (results[1]['isSuccess'] == true) {
        _availableModules =
            List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
      }
    } catch (e) {
      debugPrint('ServicePackagesTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Group modules by category
  Map<String, List<Map<String, dynamic>>> get _groupedModules {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final m in _availableModules) {
      final cat = m['category']?.toString() ?? 'Khác';
      grouped.putIfAbsent(cat, () => []).add(m);
    }
    return grouped;
  }

  /// Khớp PosPackageDefaults.SellModules (backend).
  static const List<String> _posSellPreset = [
    'PosProducts',
    'PosSell',
    'PosPrintTemplates',
    'PosSaleOrders',
    'PosSaleReturns',
    'PosSalesReport',
    'PosReportRevenue',
    'PosReportSoldGoods',
    'PosReportStock',
    'PosReportPurchases',
    'PosReportPayment',
    'PosReportDebt',
    'PosReportExpiry',
    'PosReportProfit',
    'PosReportExpense',
    'PosReportEndOfDay',
    'PosReportStaffRevenue',
    'PosReportCashbook',
    'PosReportPnl',
    'PosReportVoucher',
    'PosCustomers',
    'PosBooking',
    'PosWarranty',
    'PosCustomerDisplay',
    'PosEInvoice',
    'PosKds',
    'PosQrOrder',
    'PosCashierShift',
    'PosPrinters',
  ];

  /// Khớp PosPackageDefaults.SellWarehouseModules / FullModules.
  static const List<String> _posSellWarehousePreset = [
    'PosProducts',
    'PosSell',
    'PosPrintTemplates',
    'PosSaleOrders',
    'PosSaleReturns',
    'PosPurchaseReceipts',
    'PosPurchaseReturns',
    'PosStockCounts',
    'PosDamageIssues',
    'PosInternalUseIssues',
    'PosSalesReport',
    'PosReportRevenue',
    'PosReportSoldGoods',
    'PosReportStock',
    'PosReportPurchases',
    'PosReportPayment',
    'PosReportDebt',
    'PosReportExpiry',
    'PosReportProfit',
    'PosReportExpense',
    'PosReportEndOfDay',
    'PosReportStaffRevenue',
    'PosReportCashbook',
    'PosReportPnl',
    'PosReportVoucher',
    'PosCustomers',
    'PosBooking',
    'PosWarranty',
    'PosCustomerDisplay',
    'PosEInvoice',
    'PosKds',
    'PosQrOrder',
    'PosCashierShift',
    'PosPrinters',
  ];

  static const List<String> _posFullPreset = _posSellWarehousePreset;

  static const List<(String, String)> _fcmCategories = [
    ('attendance', 'Chấm công'),
    ('travel_attendance', 'Chấm đi đường'),
    ('leave', 'Nghỉ phép'),
    ('overtime', 'Tăng ca'),
    ('payroll', 'Lương'),
    ('task', 'Công việc'),
    ('approval', 'Phê duyệt'),
    ('device', 'Thiết bị'),
    ('hr', 'Nhân sự'),
    ('system', 'Hệ thống'),
    ('kpi', 'KPI'),
    ('internal_comm', 'Truyền thông'),
    ('transaction', 'Thu chi'),
    ('penalty', 'Phiếu phạt'),
    ('meal', 'Suất ăn'),
    ('business_trip', 'Công tác'),
    ('pos', 'POS'),
    ('shift', 'Ca làm việc'),
  ];

  String _limitText(dynamic v) {
    final n = v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    return n <= 0 ? '∞' : n.toString();
  }

  bool _pkgBool(Map<String, dynamic> pkg, String key, {bool fallback = true}) {
    final v = pkg[key];
    if (v == null) return fallback;
    if (v is bool) return v;
    return v.toString().toLowerCase() != 'false';
  }

  Map<String, dynamic> _packagePayload({
    required String name,
    required String description,
    required int days,
    required int maxUsers,
    required int maxDevices,
    required int maxAccessDevices,
    required int maxBranches,
    required bool allowWeb,
    required bool allowMobile,
    required bool allowFcm,
    required List<String> modules,
    required List<String> fcmCategories,
    required bool isActive,
  }) {
    return {
      'name': name,
      'description': description,
      'defaultDurationDays': days,
      'maxUsers': maxUsers,
      'maxDevices': maxDevices,
      'maxAccessDevices': maxAccessDevices,
      'maxBranches': maxBranches,
      'allowWeb': allowWeb,
      'allowMobile': allowMobile,
      'allowFcm': allowFcm,
      'allowedFcmCategories': fcmCategories,
      'allowedModules': modules,
      'isActive': isActive,
    };
  }

  Widget _posPresetChip(
    void Function(void Function()) setDialogState,
    Set<String> selectedModules, {
    required String label,
    required List<String> codes,
  }) {
    final available = _availableModules
        .map((m) => m['code']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet();
    final apply = codes.where(available.contains).toList();
    final active = apply.isNotEmpty && apply.every(selectedModules.contains);
    return ActionChip(
      label: Text(tr(label), style: const TextStyle(fontSize: 12)),
      avatar: Icon(
        active ? Icons.check_circle : Icons.point_of_sale_outlined,
        size: 16,
        color: active ? AdminHelpers.primary : Colors.grey.shade600,
      ),
      onPressed: apply.isEmpty
          ? null
          : () {
              setDialogState(() {
                // Chỉ thay nhóm POS — giữ module HRM đã chọn.
                selectedModules.removeWhere((c) => c.startsWith('Pos'));
                selectedModules.addAll(apply);
              });
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _packages.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.inventory_2, 'Chưa có gói dịch vụ nào')
              : MediaQuery.of(context).size.width < 600
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _packages.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: _buildPkgDeckItem(_packages[i]),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _packages.length,
                    itemBuilder: (ctx, i) => _buildPackageCard(_packages[i]),
                  ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        children: [
          AdminHelpers.countBadge(
              'Tổng gói', _packages.length, AdminHelpers.info),
          AdminHelpers.countBadge(
              'Hoạt động',
              _packages.where((p) => p['isActive'] == true).length,
              AdminHelpers.success),
          FilledButton.icon(
            onPressed: () => _showCreateEditDialog(null),
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('Tạo gói mới')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AdminHelpers.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPkgDeckItem(Map<String, dynamic> pkg) {
    final isActive = pkg['isActive'] == true;
    final name = pkg['name']?.toString() ?? '';
    final maxUsers = pkg['maxUsers'] ?? 0;
    final maxDevices = pkg['maxDevices'] ?? 0;
    final days = pkg['defaultDurationDays'] ?? 0;

    return InkWell(
      onTap: () => _showCreateEditDialog(pkg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.inventory_2, color: HrmPageChrome.primaryNavy, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(name), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                tr('${_limitText(maxUsers)} TK · ${_limitText(maxDevices)} MCC · ${_limitText(pkg['maxAccessDevices'])} TB · ${days}d'),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(tr(isActive ? 'H\u0110' : 'T\u1eaft'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isActive ? Colors.green : Colors.grey)),
          ),
        ]),
      ),
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> pkg) {
    final isActive = pkg['isActive'] == true;
    final modules = List<String>.from(pkg['allowedModules'] ?? []);
    final storeCount = pkg['storeCount'] ?? 0;
    final totalModules = _availableModules.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AdminHelpers.cardDecoration(
        borderColor: isActive ? AdminHelpers.primary : Colors.grey,
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        leading: CircleAvatar(
          backgroundColor: (isActive ? AdminHelpers.primary : Colors.grey)
              .withValues(alpha: 0.1),
          child: Icon(Icons.inventory_2,
              color: isActive ? AdminHelpers.primary : Colors.grey, size: 22),
        ),
        title: Row(children: [
          Expanded(
            child: Text(tr(pkg['name'] ?? 'N/A'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          AdminHelpers.statusChip(
              isActive ? 'Hoạt động' : 'Tắt',
              isActive ? AdminHelpers.success : Colors.grey),
        ]),
        subtitle: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _pkgLimitChip(Icons.people, '${_limitText(pkg['maxUsers'])} tài khoản'),
            _pkgLimitChip(Icons.fingerprint, '${_limitText(pkg['maxDevices'])} máy CC'),
            _pkgLimitChip(Icons.devices, '${_limitText(pkg['maxAccessDevices'])} TB truy cập'),
            _pkgLimitChip(Icons.account_tree, '${_limitText(pkg['maxBranches'])} chi nhánh'),
            _pkgLimitChip(Icons.calendar_today, '${pkg['defaultDurationDays']} ngày'),
            _pkgLimitChip(Icons.store, '$storeCount CH'),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                AdminHelpers.statusChip(
                    _pkgBool(pkg, 'allowWeb') ? 'Web' : 'Không web',
                    _pkgBool(pkg, 'allowWeb')
                        ? AdminHelpers.success
                        : Colors.grey),
                AdminHelpers.statusChip(
                    _pkgBool(pkg, 'allowMobile') ? 'Mobile/POS' : 'Không mobile',
                    _pkgBool(pkg, 'allowMobile')
                        ? AdminHelpers.success
                        : Colors.grey),
                AdminHelpers.statusChip(
                    _pkgBool(pkg, 'allowFcm') ? 'FCM' : 'Không FCM',
                    _pkgBool(pkg, 'allowFcm')
                        ? AdminHelpers.info
                        : Colors.grey),
              ],
            ),
          ),
          // Module list
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminHelpers.surfaceBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.check_circle, size: 16, color: AdminHelpers.success),
                  const SizedBox(width: 6),
                  Text(tr('Chức năng: ${modules.length}/$totalModules'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: modules.map((code) {
                    final module = _availableModules.firstWhere(
                        (m) => m['code'] == code,
                        orElse: () => {'displayName': code});
                    return AdminHelpers.statusChip(
                        module['displayName'] ?? code,
                        AdminHelpers.primary);
                  }).toList(),
                ),
              ],
            ),
          ),
          if (pkg['description'] != null &&
              pkg['description'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            AdminHelpers.infoRow(
                Icons.info_outline, pkg['description']),
          ],
          AdminHelpers.infoRow(Icons.calendar_today,
              'Tạo lúc: ${AdminHelpers.formatDateTime(pkg['createdAt'])}'),
          const Divider(height: 24),
          // Action buttons
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (context.systemAdminCanEdit) ...[
                OutlinedButton.icon(
                  onPressed: () => _showCreateEditDialog(pkg),
                  icon: const Icon(Icons.edit, size: 14),
                  label: Text(tr('Sửa'), style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AdminHelpers.info,
                      side: BorderSide(
                          color: AdminHelpers.info.withValues(alpha: 0.3))),
                ),
                OutlinedButton.icon(
                  onPressed: () => _togglePackageStatus(pkg),
                icon: Icon(isActive ? Icons.pause : Icons.play_arrow,
                    size: 14),
                label: Text(tr(isActive ? 'Tắt' : 'Bật'),
                    style: const TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor:
                        isActive ? AdminHelpers.warning : AdminHelpers.success,
                    side: BorderSide(
                        color: (isActive
                                ? AdminHelpers.warning
                                : AdminHelpers.success)
                            .withValues(alpha: 0.3))),
                ),
              ],
              if (storeCount == 0 && context.systemAdminCanDelete)
                OutlinedButton.icon(
                  onPressed: () => _deletePackage(pkg),
                  icon: const Icon(Icons.delete, size: 14),
                  label:
                      Text(tr('Xóa'), style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AdminHelpers.danger,
                      side: BorderSide(
                          color:
                              AdminHelpers.danger.withValues(alpha: 0.3))),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pkgLimitChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(tr(text), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // ═══════════════════════ CREATE / EDIT DIALOG ═══════════════════════
  Future<void> _showCreateEditDialog(Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final nameCtrl =
        TextEditingController(text: tr(existing?['name']?.toString() ?? ''));
    final descCtrl = TextEditingController(
        text: tr(existing?['description']?.toString() ?? ''));
    final daysCtrl = TextEditingController(
        text: tr((existing?['defaultDurationDays'] ?? 30).toString()));
    final usersCtrl = TextEditingController(
        text: (existing?['maxUsers'] ?? 10).toString());
    final devicesCtrl = TextEditingController(
        text: (existing?['maxDevices'] ?? 2).toString());
    final accessDevicesCtrl = TextEditingController(
        text: (existing?['maxAccessDevices'] ?? 0).toString());
    final branchesCtrl = TextEditingController(
        text: (existing?['maxBranches'] ?? 0).toString());

    final selectedModules = <String>{};
    final selectedFcm = <String>{};
    var allowWeb = existing == null || _pkgBool(existing, 'allowWeb');
    var allowMobile = existing == null || _pkgBool(existing, 'allowMobile');
    var allowFcm = existing == null || _pkgBool(existing, 'allowFcm');
    if (existing != null) {
      selectedModules
          .addAll(List<String>.from(existing['allowedModules'] ?? []));
      selectedFcm.addAll(
          List<String>.from(existing['allowedFcmCategories'] ?? []));
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final grouped = _groupedModules;
          return ScrollableAlertDialog(
            title: Row(children: [
              Icon(isEdit ? Icons.edit : Icons.add_circle,
                  color: AdminHelpers.primary, size: 24),
              const SizedBox(width: 8),
              Text(tr(isEdit ? 'Sửa gói dịch vụ' : 'Tạo gói dịch vụ mới'),
                  style: const TextStyle(fontSize: 17)),
            ]),
            content: SizedBox(
              width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 600,
              height: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Basic info
                    AdminHelpers.dialogField(
                        nameCtrl, 'Tên gói dịch vụ', Icons.label),
                    const SizedBox(height: 12),
                    AdminHelpers.dialogField(
                        descCtrl, 'Mô tả', Icons.description),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: AdminHelpers.dialogField(
                              daysCtrl, 'Số ngày', Icons.calendar_today)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: AdminHelpers.dialogField(
                              usersCtrl, 'Tài khoản', Icons.people)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: AdminHelpers.dialogField(
                              devicesCtrl, 'Máy chấm công', Icons.fingerprint)),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: AdminHelpers.dialogField(
                              accessDevicesCtrl, 'Thiết bị truy cập', Icons.devices)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: AdminHelpers.dialogField(
                              branchesCtrl, 'Chi nhánh', Icons.account_tree)),
                    ]),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 8),
                      child: Text(
                        tr('0 = không giới hạn (tài khoản, máy CC, thiết bị truy cập, chi nhánh)'),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Cho phép trình duyệt web'),
                          style: const TextStyle(fontSize: 13)),
                      value: allowWeb,
                      onChanged: (v) => setDialogState(() => allowWeb = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Cho phép mobile / POS'),
                          style: const TextStyle(fontSize: 13)),
                      value: allowMobile,
                      onChanged: (v) => setDialogState(() => allowMobile = v),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Thông báo đẩy FCM'),
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        tr('Tắt = chỉ thông báo trong app (SignalR), không đẩy điện thoại'),
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      value: allowFcm,
                      onChanged: (v) => setDialogState(() => allowFcm = v),
                    ),
                    if (allowFcm) ...[
                      const SizedBox(height: 4),
                      Text(tr('Nhóm FCM được phép (không chọn = tất cả)'),
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final c in _fcmCategories)
                            FilterChip(
                              label: Text(tr(c.$2),
                                  style: const TextStyle(fontSize: 12)),
                              selected: selectedFcm.contains(c.$1),
                              onSelected: (v) {
                                setDialogState(() {
                                  if (v) {
                                    selectedFcm.add(c.$1);
                                  } else {
                                    selectedFcm.remove(c.$1);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    // Module selection
                    Row(children: [
                      Text(tr('Chọn chức năng'),
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setDialogState(() {
                            if (selectedModules.length ==
                                _availableModules.length) {
                              selectedModules.clear();
                            } else {
                              selectedModules.addAll(_availableModules.map(
                                  (m) => m['code']?.toString() ?? ''));
                            }
                          });
                        },
                        child: Text(
                            tr(selectedModules.length ==
                                    _availableModules.length
                                ? 'Bỏ chọn tất cả'
                                : 'Chọn tất cả'),
                            style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      AdminHelpers.statusChip(
                          '${selectedModules.length}/${_availableModules.length}',
                          AdminHelpers.primary),
                    ]),
                    const SizedBox(height: 8),
                    Text(tr('Preset POS'),
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _posPresetChip(
                          setDialogState,
                          selectedModules,
                          label: 'POS bán hàng',
                          codes: _posSellPreset,
                        ),
                        _posPresetChip(
                          setDialogState,
                          selectedModules,
                          label: 'POS + kho',
                          codes: _posSellWarehousePreset,
                        ),
                        _posPresetChip(
                          setDialogState,
                          selectedModules,
                          label: 'POS đầy đủ',
                          codes: _posFullPreset,
                        ),
                      ],
                    ),
                    const Divider(),
                    // Module categories
                    ...grouped.entries.map((entry) {
                      final catName = entry.key;
                      final catModules = entry.value;
                      final catCodes = catModules
                          .map((m) => m['code']?.toString() ?? '')
                          .toList();
                      final allSelected = catCodes
                          .every((c) => selectedModules.contains(c));

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AdminHelpers.surfaceBg,
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            // Category header with select all
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  if (allSelected) {
                                    selectedModules.removeAll(catCodes);
                                  } else {
                                    selectedModules.addAll(catCodes);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(children: [
                                  Icon(
                                      allSelected
                                          ? Icons.check_box
                                          : Icons
                                              .check_box_outline_blank,
                                      size: 20,
                                      color: allSelected
                                          ? AdminHelpers.primary
                                          : Colors.grey),
                                  const SizedBox(width: 8),
                                  Text(tr(catName),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  const Spacer(),
                                  Text(
                                      tr('${catCodes.where((c) => selectedModules.contains(c)).length}/${catCodes.length}'),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500])),
                                ]),
                              ),
                            ),
                            // Module checkboxes
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 16, right: 8, bottom: 8),
                              child: Wrap(
                                spacing: 0,
                                runSpacing: 0,
                                children:
                                    catModules.map((module) {
                                  final code =
                                      module['code']?.toString() ?? '';
                                  final isChecked =
                                      selectedModules.contains(code);
                                  return SizedBox(
                                    width: 180,
                                    child: CheckboxListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      visualDensity:
                                          VisualDensity.compact,
                                      title: Text(
                                          tr(module['displayName'] ?? code),
                                          style: const TextStyle(
                                              fontSize: 12)),
                                      value: isChecked,
                                      activeColor: AdminHelpers.primary,
                                      onChanged: (v) {
                                        setDialogState(() {
                                          if (v == true) {
                                            selectedModules.add(code);
                                          } else {
                                            selectedModules.remove(code);
                                          }
                                        });
                                      },
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Hủy'))),
              FilledButton.icon(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty) {
                    AdminHelpers.showError(ctx, 'Vui lòng nhập tên gói');
                    return;
                  }
                  if (selectedModules.isEmpty) {
                    AdminHelpers.showError(
                        ctx, 'Vui lòng chọn ít nhất 1 chức năng');
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                icon: Icon(isEdit ? Icons.save : Icons.add, size: 16),
                label: Text(tr(isEdit ? 'Lưu' : 'Tạo')),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AdminHelpers.primary),
              ),
            ],
          );
        },
      ),
    );

    if (result != true || !mounted) return;

    final data = _packagePayload(
      name: nameCtrl.text.trim(),
      description: descCtrl.text.trim(),
      days: int.tryParse(daysCtrl.text) ?? 30,
      maxUsers: int.tryParse(usersCtrl.text) ?? 10,
      maxDevices: int.tryParse(devicesCtrl.text) ?? 2,
      maxAccessDevices: int.tryParse(accessDevicesCtrl.text) ?? 0,
      maxBranches: int.tryParse(branchesCtrl.text) ?? 0,
      allowWeb: allowWeb,
      allowMobile: allowMobile,
      allowFcm: allowFcm,
      modules: selectedModules.toList(),
      fcmCategories: selectedFcm.toList(),
      isActive: isEdit ? (existing['isActive'] ?? true) == true : true,
    );
    if (!isEdit) data.remove('isActive');

    final res = isEdit
        ? await _apiService.updateServicePackage(
            existing['id']?.toString() ?? '', data)
        : await _apiService.createServicePackage(data);

    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context,
          isEdit ? 'Đã cập nhật gói dịch vụ' : 'Đã tạo gói dịch vụ mới');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ TOGGLE STATUS ═══════════════════════
  Future<void> _togglePackageStatus(Map<String, dynamic> pkg) async {
    final isActive = pkg['isActive'] == true;
    final data = _packagePayload(
      name: pkg['name']?.toString() ?? '',
      description: pkg['description']?.toString() ?? '',
      days: pkg['defaultDurationDays'] is int
          ? pkg['defaultDurationDays'] as int
          : int.tryParse(pkg['defaultDurationDays']?.toString() ?? '') ?? 30,
      maxUsers: pkg['maxUsers'] is int
          ? pkg['maxUsers'] as int
          : int.tryParse(pkg['maxUsers']?.toString() ?? '') ?? 10,
      maxDevices: pkg['maxDevices'] is int
          ? pkg['maxDevices'] as int
          : int.tryParse(pkg['maxDevices']?.toString() ?? '') ?? 2,
      maxAccessDevices: pkg['maxAccessDevices'] is int
          ? pkg['maxAccessDevices'] as int
          : int.tryParse(pkg['maxAccessDevices']?.toString() ?? '') ?? 0,
      maxBranches: pkg['maxBranches'] is int
          ? pkg['maxBranches'] as int
          : int.tryParse(pkg['maxBranches']?.toString() ?? '') ?? 0,
      allowWeb: _pkgBool(pkg, 'allowWeb'),
      allowMobile: _pkgBool(pkg, 'allowMobile'),
      allowFcm: _pkgBool(pkg, 'allowFcm'),
      modules: List<String>.from(pkg['allowedModules'] ?? []),
      fcmCategories: List<String>.from(pkg['allowedFcmCategories'] ?? []),
      isActive: !isActive,
    );

    final res = await _apiService.updateServicePackage(
        pkg['id']?.toString() ?? '', data);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(
          context, isActive ? 'Đã tắt gói dịch vụ' : 'Đã bật gói dịch vụ');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ DELETE PACKAGE ═══════════════════════
  Future<void> _deletePackage(Map<String, dynamic> pkg) async {
    final name = pkg['name'] ?? 'N/A';
    final confirmed = await AdminHelpers.showConfirmDialog(
        context, 'Xóa gói dịch vụ', 'Bạn chắc chắn muốn xóa gói "$name"?');

    if (confirmed != true || !mounted) return;

    final res = await _apiService
        .deleteServicePackage(pkg['id']?.toString() ?? '');
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã xóa gói "$name"');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }
}
