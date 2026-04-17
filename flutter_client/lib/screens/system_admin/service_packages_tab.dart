import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';

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
          ElevatedButton.icon(
            onPressed: () => _showCreateEditDialog(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tạo gói mới'),
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
            decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.inventory_2, color: Color(0xFF1E3A5F), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('$maxUsers users \u00b7 $maxDevices TB \u00b7 ${days}d', style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(isActive ? 'H\u0110' : 'T\u1eaft', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isActive ? Colors.green : Colors.grey)),
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
            child: Text(pkg['name'] ?? 'N/A',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          AdminHelpers.statusChip(
              isActive ? 'Hoạt động' : 'Tắt',
              isActive ? AdminHelpers.success : Colors.grey),
        ]),
        subtitle: Row(children: [
          Icon(Icons.people, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text('${pkg['maxUsers']} users',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(width: 12),
          Icon(Icons.router, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text('${pkg['maxDevices']} thiết bị',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(width: 12),
          Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text('${pkg['defaultDurationDays']} ngày',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(width: 12),
          Icon(Icons.store, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text('$storeCount CH',
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ]),
        children: [
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
                  Text('Chức năng: ${modules.length}/$totalModules',
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
              OutlinedButton.icon(
                onPressed: () => _showCreateEditDialog(pkg),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('Sửa', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AdminHelpers.info,
                    side: BorderSide(
                        color: AdminHelpers.info.withValues(alpha: 0.3))),
              ),
              OutlinedButton.icon(
                onPressed: () => _togglePackageStatus(pkg),
                icon: Icon(isActive ? Icons.pause : Icons.play_arrow,
                    size: 14),
                label: Text(isActive ? 'Tắt' : 'Bật',
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
              if (storeCount == 0)
                OutlinedButton.icon(
                  onPressed: () => _deletePackage(pkg),
                  icon: const Icon(Icons.delete, size: 14),
                  label:
                      const Text('Xóa', style: TextStyle(fontSize: 12)),
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

  // ═══════════════════════ CREATE / EDIT DIALOG ═══════════════════════
  Future<void> _showCreateEditDialog(Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final nameCtrl =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final descCtrl = TextEditingController(
        text: existing?['description']?.toString() ?? '');
    final daysCtrl = TextEditingController(
        text: (existing?['defaultDurationDays'] ?? 30).toString());
    final usersCtrl = TextEditingController(
        text: (existing?['maxUsers'] ?? 10).toString());
    final devicesCtrl = TextEditingController(
        text: (existing?['maxDevices'] ?? 2).toString());

    final selectedModules = <String>{};
    if (existing != null) {
      selectedModules
          .addAll(List<String>.from(existing['allowedModules'] ?? []));
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final grouped = _groupedModules;
          return AlertDialog(
            title: Row(children: [
              Icon(isEdit ? Icons.edit : Icons.add_circle,
                  color: AdminHelpers.primary, size: 24),
              const SizedBox(width: 8),
              Text(isEdit ? 'Sửa gói dịch vụ' : 'Tạo gói dịch vụ mới',
                  style: const TextStyle(fontSize: 17)),
            ]),
            content: SizedBox(
              width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 600,
              height: 500,
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
                              usersCtrl, 'Max Users', Icons.people)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: AdminHelpers.dialogField(
                              devicesCtrl, 'Max Devices', Icons.router)),
                    ]),
                    const SizedBox(height: 20),
                    // Module selection
                    Row(children: [
                      const Text('Chọn chức năng',
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
                            selectedModules.length ==
                                    _availableModules.length
                                ? 'Bỏ chọn tất cả'
                                : 'Chọn tất cả',
                            style: const TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      AdminHelpers.statusChip(
                          '${selectedModules.length}/${_availableModules.length}',
                          AdminHelpers.primary),
                    ]),
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
                                  Text(catName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13)),
                                  const Spacer(),
                                  Text(
                                      '${catCodes.where((c) => selectedModules.contains(c)).length}/${catCodes.length}',
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
                                          module['displayName'] ?? code,
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
                  child: const Text('Hủy')),
              ElevatedButton.icon(
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
                label: Text(isEdit ? 'Lưu' : 'Tạo'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AdminHelpers.primary),
              ),
            ],
          );
        },
      ),
    );

    if (result != true || !mounted) return;

    final data = {
      'name': nameCtrl.text.trim(),
      'description': descCtrl.text.trim(),
      'defaultDurationDays': int.tryParse(daysCtrl.text) ?? 30,
      'maxUsers': int.tryParse(usersCtrl.text) ?? 10,
      'maxDevices': int.tryParse(devicesCtrl.text) ?? 2,
      'allowedModules': selectedModules.toList(),
      if (isEdit) 'isActive': existing['isActive'] ?? true,
    };

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
    final data = {
      'name': pkg['name'],
      'description': pkg['description'],
      'defaultDurationDays': pkg['defaultDurationDays'],
      'maxUsers': pkg['maxUsers'],
      'maxDevices': pkg['maxDevices'],
      'allowedModules': List<String>.from(pkg['allowedModules'] ?? []),
      'isActive': !isActive,
    };

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
