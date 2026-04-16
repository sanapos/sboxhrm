import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';

class KeyPromotionsTab extends StatefulWidget {
  const KeyPromotionsTab({super.key});

  @override
  State<KeyPromotionsTab> createState() => KeyPromotionsTabState();
}

class KeyPromotionsTabState extends State<KeyPromotionsTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _promotions = [];
  List<Map<String, dynamic>> _packages = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get promotions => _promotions;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getKeyPromotions(),
        _apiService.getServicePackages(),
      ]);
      if (!mounted) return;
      if (results[0]['isSuccess'] == true) {
        _promotions =
            List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
      }
      if (results[1]['isSuccess'] == true) {
        _packages =
            List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
      }
    } catch (e) {
      debugPrint('KeyPromotionsTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _fmtDate(String? s) {
    if (s == null) return '—';
    final d = DateTime.tryParse(s);
    return d == null ? s : DateFormat('dd/MM/yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _promotions.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.card_giftcard, 'Chưa có chương trình kích hoạt nào')
              : MediaQuery.of(context).size.width < 600
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _promotions.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: _buildPromoDeckItem(_promotions[i]),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _promotions.length,
                    itemBuilder: (ctx, i) => _buildPromotionCard(_promotions[i]),
                  ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final active = _promotions.where((p) => p['isActive'] == true).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        children: [
          AdminHelpers.countBadge(
              'Tổng CT', _promotions.length, AdminHelpers.info),
          AdminHelpers.countBadge('Đang hoạt động', active, AdminHelpers.success),
          ElevatedButton.icon(
            onPressed: () => _showCreateEditDialog(null),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tạo CT mới'),
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

  Widget _buildPromoDeckItem(Map<String, dynamic> promo) {
    final isActive = promo['isActive'] == true;
    final name = promo['name']?.toString() ?? '';
    final pkg = promo['servicePackageName']?.toString() ?? '';
    final endDate = DateTime.tryParse(promo['endDate'] ?? '');
    final isExpired = endDate != null && endDate.isBefore(DateTime.now());

    return InkWell(
      onTap: () => _showCreateEditDialog(promo),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.card_giftcard, color: Colors.amber, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([pkg, if (endDate != null) '\u0110\u1ebfn ${endDate.day}/${endDate.month}/${endDate.year}'].join(' \u00b7 '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isExpired ? Colors.red.withValues(alpha: 0.1) : isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(isExpired ? 'H\u1ebft h\u1ea1n' : isActive ? 'H\u0110' : 'T\u1eaft', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isExpired ? Colors.red : isActive ? Colors.green : Colors.grey)),
          ),
        ]),
      ),
    );
  }

  Widget _buildPromotionCard(Map<String, dynamic> promo) {
    final isActive = promo['isActive'] == true;
    final endDate = DateTime.tryParse(promo['endDate'] ?? '');
    final isExpired = endDate != null && endDate.isBefore(DateTime.now());

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AdminHelpers.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.card_giftcard,
                      color: AdminHelpers.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(promo['name'] ?? '',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                          'Gói: ${promo['servicePackageName'] ?? 'N/A'}',
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isExpired
                        ? Colors.red.withValues(alpha: 0.1)
                        : isActive
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isExpired ? 'Hết hạn' : isActive ? 'Hoạt động' : 'Tắt',
                    style: TextStyle(
                      color: isExpired
                          ? Colors.red
                          : isActive
                              ? Colors.green
                              : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') _showCreateEditDialog(promo);
                    if (v == 'delete') _confirmDelete(promo);
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'edit', child: Text('Chỉnh sửa')),
                    const PopupMenuItem(
                        value: 'delete',
                        child: Text('Xóa', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ],
            ),
            const Divider(height: 32),
            Row(
              children: [
                _infoChip(Icons.calendar_today, 'Từ', _fmtDate(promo['startDate']?.toString())),
                const SizedBox(width: 16),
                _infoChip(Icons.event, 'Đến', _fmtDate(promo['endDate']?.toString())),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _bonusChip('1 key', promo['bonus1Key']),
                _bonusChip('2 keys', promo['bonus2Keys']),
                _bonusChip('3 keys', promo['bonus3Keys']),
                _bonusChip('4 keys', promo['bonus4Keys']),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ],
    );
  }

  Widget _bonusChip(String label, dynamic days) {
    final d = days is int ? days : int.tryParse(days?.toString() ?? '') ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: d > 0
            ? AdminHelpers.primary.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: d > 0
              ? AdminHelpers.primary.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Text('$label: +$d ngày',
          style: TextStyle(
            color: d > 0 ? AdminHelpers.primary : Colors.grey,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          )),
    );
  }

  void _confirmDelete(Map<String, dynamic> promo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa chương trình "${promo['name']}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await _apiService.deleteKeyPromotion(promo['id'].toString());
              if (res['isSuccess'] == true) {
                loadData();
                if (mounted) {
                  NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa chương trình');
                }
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showCreateEditDialog(Map<String, dynamic>? promo) {
    final isEdit = promo != null;
    final nameCtrl = TextEditingController(text: promo?['name'] ?? '');
    final bonus1Ctrl = TextEditingController(text: (promo?['bonus1Key'] ?? 0).toString());
    final bonus2Ctrl = TextEditingController(text: (promo?['bonus2Keys'] ?? 0).toString());
    final bonus3Ctrl = TextEditingController(text: (promo?['bonus3Keys'] ?? 0).toString());
    final bonus4Ctrl = TextEditingController(text: (promo?['bonus4Keys'] ?? 0).toString());

    String? selectedPackageId = promo?['servicePackageId']?.toString();
    DateTime startDate = DateTime.tryParse(promo?['startDate'] ?? '') ?? DateTime.now();
    DateTime endDate = DateTime.tryParse(promo?['endDate'] ?? '') ??
        DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(isEdit ? 'Sửa chương trình' : 'Tạo chương trình mới'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tên chương trình',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPackageId,
                    decoration: const InputDecoration(
                      labelText: 'Gói dịch vụ',
                      border: OutlineInputBorder(),
                    ),
                    items: _packages
                        .map((p) => DropdownMenuItem<String>(
                              value: p['id']?.toString(),
                              child: Text(p['name'] ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setDlg(() => selectedPackageId = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: startDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) setDlg(() => startDate = d);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Ngày bắt đầu',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_today, size: 18),
                            ),
                            child: Text(DateFormat('dd/MM/yyyy').format(startDate)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: ctx,
                              initialDate: endDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (d != null) setDlg(() => endDate = d);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Ngày kết thúc',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.event, size: 18),
                            ),
                            child: Text(DateFormat('dd/MM/yyyy').format(endDate)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Số ngày thưởng theo số key kích hoạt:',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: bonus1Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '1 key',
                            border: OutlineInputBorder(),
                            suffixText: 'ngày',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: bonus2Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '2 keys',
                            border: OutlineInputBorder(),
                            suffixText: 'ngày',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: bonus3Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '3 keys',
                            border: OutlineInputBorder(),
                            suffixText: 'ngày',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: bonus4Ctrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '4 keys',
                            border: OutlineInputBorder(),
                            suffixText: 'ngày',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty || selectedPackageId == null) {
                  NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập đầy đủ thông tin');
                  return;
                }
                final data = {
                  'name': nameCtrl.text,
                  'servicePackageId': selectedPackageId,
                  'startDate': startDate.toIso8601String(),
                  'endDate': endDate.toIso8601String(),
                  'bonus1Key': int.tryParse(bonus1Ctrl.text) ?? 0,
                  'bonus2Keys': int.tryParse(bonus2Ctrl.text) ?? 0,
                  'bonus3Keys': int.tryParse(bonus3Ctrl.text) ?? 0,
                  'bonus4Keys': int.tryParse(bonus4Ctrl.text) ?? 0,
                };
                final res = isEdit
                    ? await _apiService.updateKeyPromotion(promo['id'].toString(), data)
                    : await _apiService.createKeyPromotion(data);
                if (res['isSuccess'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  loadData();
                } else {
                  if (mounted) {
                    NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(isEdit ? 'Cập nhật' : 'Tạo mới'),
            ),
          ],
        ),
      ),
    );
  }
}
