import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

class ProductSalarySettingsScreen extends StatefulWidget {
  const ProductSalarySettingsScreen({super.key});
  @override
  State<ProductSalarySettingsScreen> createState() =>
      _ProductSalarySettingsScreenState();
}

class _ProductSalarySettingsScreenState
    extends State<ProductSalarySettingsScreen> {
  final ApiService _apiService = ApiService();
  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getProductGroups(),
        _apiService.getProductItems(),
      ]);
      final groupsRes = results[0];
      final itemsRes = results[1];
      if (groupsRes['isSuccess'] == true) {
        _groups = List<Map<String, dynamic>>.from(groupsRes['data'] ?? []);
      }
      if (itemsRes['isSuccess'] == true) {
        _items = List<Map<String, dynamic>>.from(itemsRes['data'] ?? []);
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_selectedGroupId == null) return _items;
    return _items
        .where((i) => i['productGroupId'] == _selectedGroupId)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Container(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.precision_manufacturing,
                      color: Color(0xFF0F2340), size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Lương sản phẩm',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A))),
                  ),
                  FilledButton.icon(
                    onPressed: _showAddGroupDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm nhóm SP'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F2340),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _groups.isEmpty ? null : _showAddItemDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm sản phẩm'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A5F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Quản lý nhóm sản phẩm, sản phẩm và đơn giá theo bậc',
                style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
              ),
            ],
          ),
        ),

        // Group chips
        if (_groups.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildGroupChip(null, 'Tất cả'),
                ..._groups.map((g) => _buildGroupChip(
                    g['id']?.toString(), g['name'] ?? '')),
              ],
            ),
          ),

        // Product list
        Expanded(
          child: _filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        _groups.isEmpty
                            ? 'Chưa có nhóm sản phẩm.\nHãy thêm nhóm sản phẩm trước.'
                            : 'Chưa có sản phẩm nào.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredItems.length,
                  itemBuilder: (ctx, i) => _buildItemCard(_filteredItems[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildGroupChip(String? groupId, String label) {
    final selected = _selectedGroupId == groupId;
    return FilterChip(
      selected: selected,
      label: Text(label),
      selectedColor: const Color(0xFF0F2340),
      labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFF334155),
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
      checkmarkColor: Colors.white,
      onSelected: (_) => setState(() => _selectedGroupId = groupId),
      side: BorderSide(
          color: selected ? const Color(0xFF0F2340) : const Color(0xFFCBD5E1)),
      onDeleted: groupId == null
          ? null
          : () => _showEditGroupDialog(
              _groups.firstWhere((g) => g['id']?.toString() == groupId)),
      deleteIcon: groupId == null
          ? null
          : const Icon(Icons.edit, size: 16, color: Color(0xFF71717A)),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final priceTiers =
        List<Map<String, dynamic>>.from(item['priceTiers'] ?? []);
    final groupName = item['productGroupName'] ?? item['groupName'] ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F2340).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(item['code'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF0F2340))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(item['name'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: Color(0xFF0F172A))),
                ),
                if (groupName.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(groupName,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B))),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: const Color(0xFF64748B),
                  onPressed: () => _showEditItemDialog(item),
                  tooltip: 'Sửa',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: const Color(0xFFEF4444),
                  onPressed: () => _confirmDeleteItem(item),
                  tooltip: 'Xóa',
                ),
              ],
            ),
            if (item['unit'] != null && (item['unit'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Đơn vị: ${item['unit']}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF71717A))),
              ),
            const SizedBox(height: 12),
            // Price tiers table
            if (priceTiers.isNotEmpty) ...[
              const Text('Bảng đơn giá theo bậc',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF334155))),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(1.5),
                  },
                  children: [
                    const TableRow(
                      decoration: BoxDecoration(
                        color: Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(7)),
                      ),
                      children: [
                        Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Bậc',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Color(0xFF475569)))),
                        Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Số lượng',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Color(0xFF475569)))),
                        Padding(
                            padding: EdgeInsets.all(10),
                            child: Text('Đơn giá (đ)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Color(0xFF475569)))),
                      ],
                    ),
                    ...priceTiers.asMap().entries.map((entry) {
                      final tier = entry.value;
                      final min = tier['minQuantity'] ?? 0;
                      final max = tier['maxQuantity'];
                      final price = (tier['unitPrice'] ?? 0).toDouble();
                      final range = max == null || max == 0
                          ? 'Từ $min+'
                          : '$min - $max';
                      return TableRow(
                        decoration: const BoxDecoration(
                          border: Border(
                              top: BorderSide(color: Color(0xFFE4E4E7))),
                        ),
                        children: [
                          Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                  'Bậc ${tier['tierLevel'] ?? entry.key + 1}',
                                  style: const TextStyle(fontSize: 13))),
                          Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(range,
                                  style: const TextStyle(fontSize: 13))),
                          Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                  '${_currencyFormat.format(price)} đ',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF059669)))),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ] else
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Color(0xFFF59E0B)),
                    SizedBox(width: 8),
                    Text('Chưa thiết lập đơn giá',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFFF59E0B))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════ DIALOGS ═══════════

  void _showAddGroupDialog() {
    final nameCtl = TextEditingController();
    final descCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm nhóm sản phẩm'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(
                    labelText: 'Tên nhóm *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtl,
                decoration: const InputDecoration(
                    labelText: 'Mô tả', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (nameCtl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final res = await _apiService.createProductGroup({
                'name': nameCtl.text.trim(),
                'description': descCtl.text.trim(),
                'sortOrder': _groups.length,
              });
              if (res['isSuccess'] == true) {
                appNotification.showSuccess(title: 'Thành công', message: 'Đã thêm nhóm sản phẩm');
                _loadData();
              } else {
                appNotification.showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi');
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showEditGroupDialog(Map<String, dynamic> group) {
    final nameCtl = TextEditingController(text: group['name'] ?? '');
    final descCtl = TextEditingController(text: group['description'] ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa nhóm sản phẩm'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                decoration: const InputDecoration(
                    labelText: 'Tên nhóm *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtl,
                decoration: const InputDecoration(
                    labelText: 'Mô tả', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Xác nhận xóa'),
                  content: Text(
                      'Xóa nhóm "${group['name']}"? Các sản phẩm trong nhóm cũng sẽ bị xóa.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Hủy')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        child: const Text('Xóa')),
                  ],
                ),
              );
              if (confirm == true) {
                final res = await _apiService
                    .deleteProductGroup(group['id'].toString());
                if (res['isSuccess'] == true) {
                  appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa nhóm');
                  if (_selectedGroupId == group['id']?.toString()) {
                    _selectedGroupId = null;
                  }
                  _loadData();
                }
              }
            },
            child: const Text('Xóa nhóm',
                style: TextStyle(color: Colors.red)),
          ),
          const Spacer(),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (nameCtl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              final res = await _apiService.updateProductGroup(
                  group['id'].toString(), {
                'name': nameCtl.text.trim(),
                'description': descCtl.text.trim(),
              });
              if (res['isSuccess'] == true) {
                appNotification.showSuccess(title: 'Thành công', message: 'Đã cập nhật nhóm');
                _loadData();
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showAddItemDialog() {
    _showItemDialog(null);
  }

  void _showEditItemDialog(Map<String, dynamic> item) {
    _showItemDialog(item);
  }

  void _showItemDialog(Map<String, dynamic>? item) {
    final isEdit = item != null;
    final codeCtl = TextEditingController(text: item?['code'] ?? '');
    final nameCtl = TextEditingController(text: item?['name'] ?? '');
    final unitCtl = TextEditingController(text: item?['unit'] ?? '');
    final descCtl = TextEditingController(text: item?['description'] ?? '');
    String? selectedGroupId =
        item?['productGroupId']?.toString() ?? _selectedGroupId;

    // Price tiers
    final existingTiers =
        List<Map<String, dynamic>>.from(item?['priceTiers'] ?? []);
    final tiers = existingTiers.isEmpty
        ? [
            {'minQuantity': 0, 'maxQuantity': null, 'unitPrice': 0.0, 'tierLevel': 1}
          ]
        : existingTiers
            .map((t) => Map<String, dynamic>.from(t))
            .toList();

    // Persistent controllers for price tiers
    final minCtls = <TextEditingController>[];
    final maxCtls = <TextEditingController>[];
    final priceCtls = <TextEditingController>[];
    for (var t in tiers) {
      minCtls.add(TextEditingController(text: '${t['minQuantity'] ?? 0}'));
      maxCtls.add(TextEditingController(text: t['maxQuantity']?.toString() ?? ''));
      final p = t['unitPrice'];
      priceCtls.add(TextEditingController(text: p is double ? '${p.toInt()}' : '${p ?? 0}'));
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(isEdit ? 'Sửa sản phẩm' : 'Thêm sản phẩm'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedGroupId,
                    decoration: const InputDecoration(
                        labelText: 'Nhóm sản phẩm *',
                        border: OutlineInputBorder()),
                    items: _groups
                        .map((g) => DropdownMenuItem(
                            value: g['id']?.toString(),
                            child: Text(g['name'] ?? '')))
                        .toList(),
                    onChanged: (v) =>
                        setDlgState(() => selectedGroupId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: codeCtl,
                          decoration: const InputDecoration(
                              labelText: 'Mã SP *',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: nameCtl,
                          decoration: const InputDecoration(
                              labelText: 'Tên sản phẩm *',
                              border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: unitCtl,
                          decoration: const InputDecoration(
                              labelText: 'Đơn vị (cái, kg...)',
                              border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: descCtl,
                          decoration: const InputDecoration(
                              labelText: 'Mô tả',
                              border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text('Bảng đơn giá theo bậc',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          setDlgState(() {
                            tiers.add({
                              'minQuantity': 0,
                              'maxQuantity': null,
                              'unitPrice': 0.0,
                              'tierLevel': tiers.length + 1,
                            });
                            minCtls.add(TextEditingController(text: '0'));
                            maxCtls.add(TextEditingController(text: ''));
                            priceCtls.add(TextEditingController(text: '0'));
                          });
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Thêm bậc'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...tiers.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final tier = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 40,
                            child: Text('Bậc ${idx + 1}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: minCtls[idx],
                              decoration: const InputDecoration(
                                  labelText: 'Từ SL',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) =>
                                  tier['minQuantity'] = int.tryParse(v) ?? 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: maxCtls[idx],
                              decoration: const InputDecoration(
                                  labelText: 'Đến SL',
                                  hintText: '∞',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => tier['maxQuantity'] =
                                  v.isEmpty ? null : int.tryParse(v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: priceCtls[idx],
                              decoration: const InputDecoration(
                                  labelText: 'Đơn giá (đ)',
                                  border: OutlineInputBorder(),
                                  isDense: true),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => tier['unitPrice'] =
                                  double.tryParse(v) ?? 0,
                            ),
                          ),
                          if (tiers.length > 1)
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20, color: Colors.red),
                              onPressed: () {
                                setDlgState(() {
                                  tiers.removeAt(idx);
                                  minCtls.removeAt(idx);
                                  maxCtls.removeAt(idx);
                                  priceCtls.removeAt(idx);
                                });
                              },
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton(
              onPressed: () async {
                if (codeCtl.text.trim().isEmpty ||
                    nameCtl.text.trim().isEmpty ||
                    selectedGroupId == null) {
                  return;
                }
                Navigator.pop(ctx);
                // Sync controller values to tier data
                for (int i = 0; i < tiers.length; i++) {
                  tiers[i]['minQuantity'] = int.tryParse(minCtls[i].text) ?? 0;
                  tiers[i]['maxQuantity'] = maxCtls[i].text.isEmpty ? null : int.tryParse(maxCtls[i].text);
                  tiers[i]['unitPrice'] = double.tryParse(priceCtls[i].text) ?? 0;
                }
                final data = {
                  'code': codeCtl.text.trim(),
                  'name': nameCtl.text.trim(),
                  'unit': unitCtl.text.trim(),
                  'description': descCtl.text.trim(),
                  'productGroupId': selectedGroupId,
                  'priceTiers': tiers
                      .asMap()
                      .entries
                      .map((e) => {
                            'tierLevel': e.key + 1,
                            'minQuantity': e.value['minQuantity'] ?? 0,
                            'maxQuantity': e.value['maxQuantity'],
                            'unitPrice': e.value['unitPrice'] ?? 0,
                          })
                      .toList(),
                };
                final res = isEdit
                    ? await _apiService.updateProductItem(
                        item['id'].toString(), data)
                    : await _apiService.createProductItem(data);
                if (res['isSuccess'] == true) {
                  appNotification.showSuccess(title: 'Thành công',
                      message: isEdit ? 'Đã cập nhật sản phẩm' : 'Đã thêm sản phẩm');
                  _loadData();
                } else {
                  appNotification.showError(
                      title: 'Lỗi', message: res['message'] ?? 'Lỗi');
                }
              },
              child: Text(isEdit ? 'Lưu' : 'Thêm'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa sản phẩm "${item['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (confirm == true) {
      final res = await _apiService.deleteProductItem(item['id'].toString());
      if (res['isSuccess'] == true) {
        appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa sản phẩm');
        _loadData();
      }
    }
  }
}
