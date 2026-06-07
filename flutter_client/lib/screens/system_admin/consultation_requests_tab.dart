import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../utils/file_saver.dart' as file_saver;
import 'system_admin_helpers.dart';

class ConsultationRequestsTab extends StatefulWidget {
  const ConsultationRequestsTab({super.key});

  @override
  State<ConsultationRequestsTab> createState() =>
      ConsultationRequestsTabState();
}

class ConsultationRequestsTabState extends State<ConsultationRequestsTab> {
  final _api = ApiService();
  final _df = DateFormat('dd/MM/yyyy HH:mm');
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  bool _loading = false;
  String _statusFilter = '';

  List<Map<String, dynamic>> get items => _items;

  static const _statusColors = {
    'New': Color(0xFFEF4444),
    'Contacted': Color(0xFFF59E0B),
    'Qualified': Color(0xFF2563EB),
    'Closed': Color(0xFF10B981),
    'Spam': Color(0xFF71717A),
  };

  static const _statusLabels = {
    'New': 'Mới',
    'Contacted': 'Đã liên hệ',
    'Qualified': 'Tiềm năng',
    'Closed': 'Đã đóng',
    'Spam': 'Spam',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.adminGetConsultationRequests(
      status: _statusFilter.isEmpty ? null : _statusFilter,
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      pageSize: 100,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>? ?? {};
      _items = List<Map<String, dynamic>>.from(data['items'] as List? ?? []);
      _total = (data['total'] as num?)?.toInt() ?? _items.length;
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lead tư vấn ($_total)',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: (_loading || _items.isEmpty) ? null : _exportExcel,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Xuất Excel'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (_) => _load(),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên, SĐT, công ty, gói quan tâm',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              _load();
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Lọc'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('Tất cả', ''),
                _filterChip('Mới', 'New'),
                _filterChip('Đã liên hệ', 'Contacted'),
                _filterChip('Tiềm năng', 'Qualified'),
                _filterChip('Đã đóng', 'Closed'),
                _filterChip('Spam', 'Spam'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator())),
          if (!_loading && _items.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Chưa có lead tư vấn',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          if (!_loading && _items.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) => _buildItem(_items[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String status) {
    final selected = _statusFilter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _statusFilter = status);
          _load();
        },
        selectedColor: AdminHelpers.primary.withValues(alpha: 0.12),
      ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final status = item['status'] as String? ?? 'New';
    final statusColor = _statusColors[status] ?? Colors.grey;
    final createdAt = _tryParseDate(item['createdAt'] as String?);
    final company = (item['company'] as String?)?.trim();
    final province = (item['province'] as String?)?.trim();
    final interestedPlan = (item['interestedPlan'] as String?)?.trim();

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: statusColor.withValues(alpha: 0.12),
        child: Icon(Icons.support_agent, color: statusColor, size: 20),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item['name'] as String? ?? 'Ẩn danh',
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _statusLabels[status] ?? status,
              style: TextStyle(
                  fontSize: 11,
                  color: statusColor,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            item['phone'] as String? ?? '',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          if ((company?.isNotEmpty ?? false) ||
              (province?.isNotEmpty ?? false) ||
              (interestedPlan?.isNotEmpty ?? false))
            Text(
              [
                if (company?.isNotEmpty ?? false) company,
                if (province?.isNotEmpty ?? false) province,
                if (interestedPlan?.isNotEmpty ?? false) interestedPlan,
              ].join(' • '),
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.public, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(item['source'] as String? ?? 'LandingPage',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              const Spacer(),
              if (createdAt != null)
                Text(_df.format(createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ],
      ),
      trailing: (context.systemAdminCanEdit || context.systemAdminCanDelete)
          ? PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  if (context.systemAdminCanDelete) await _delete(item);
                  return;
                }
                if (context.systemAdminCanEdit) {
                  await _quickUpdateStatus(item['id'] as String, value);
                }
              },
              itemBuilder: (_) => [
                if (context.systemAdminCanEdit) ...[
                  const PopupMenuItem(
                      value: 'Contacted', child: Text('Đã liên hệ')),
                  const PopupMenuItem(
                      value: 'Qualified', child: Text('Tiềm năng')),
                  const PopupMenuItem(
                      value: 'Closed', child: Text('Đã đóng')),
                  const PopupMenuItem(
                      value: 'Spam', child: Text('Đánh dấu spam')),
                ],
                if (context.systemAdminCanEdit &&
                    context.systemAdminCanDelete)
                  const PopupMenuDivider(),
                if (context.systemAdminCanDelete)
                  const PopupMenuItem(
                      value: 'delete', child: Text('Xoá lead')),
              ],
            )
          : null,
      onTap: () => _showDetail(item),
    );
  }

  Future<void> _callCustomer(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$normalized');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Không mở được ứng dụng gọi điện')),
    );
  }

  Future<void> _openZalo(String phone) async {
    final normalized = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://zalo.me/$normalized');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Không mở được Zalo cho số này')),
    );
  }

  Future<void> _exportExcel() async {
    final excel = excel_pkg.Excel.createExcel();
    final sheet = excel['Leads'];
    sheet.appendRow([
      excel_pkg.TextCellValue('Họ tên'),
      excel_pkg.TextCellValue('Số điện thoại'),
      excel_pkg.TextCellValue('Tỉnh / thành'),
      excel_pkg.TextCellValue('Công ty'),
      excel_pkg.TextCellValue('Gói quan tâm'),
      excel_pkg.TextCellValue('Trạng thái'),
      excel_pkg.TextCellValue('Nguồn'),
      excel_pkg.TextCellValue('Ghi chú khách'),
      excel_pkg.TextCellValue('Ghi chú xử lý'),
      excel_pkg.TextCellValue('Ngày tạo'),
    ]);

    for (final item in _items) {
      final createdAt = _tryParseDate(item['createdAt'] as String?);
      sheet.appendRow([
        excel_pkg.TextCellValue((item['name'] as String?) ?? ''),
        excel_pkg.TextCellValue((item['phone'] as String?) ?? ''),
        excel_pkg.TextCellValue((item['province'] as String?) ?? ''),
        excel_pkg.TextCellValue((item['company'] as String?) ?? ''),
        excel_pkg.TextCellValue((item['interestedPlan'] as String?) ?? ''),
        excel_pkg.TextCellValue(
            _statusLabels[item['status']] ?? (item['status'] as String? ?? '')),
        excel_pkg.TextCellValue((item['source'] as String?) ?? ''),
        excel_pkg.TextCellValue((item['notes'] as String?) ?? ''),
        excel_pkg.TextCellValue((item['adminNote'] as String?) ?? ''),
        excel_pkg.TextCellValue(createdAt != null ? _df.format(createdAt) : ''),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể tạo file Excel')),
      );
      return;
    }

    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    await file_saver.saveFileBytes(
      bytes,
      'consultation-leads-$stamp.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã xuất Excel danh sách lead')),
    );
  }

  DateTime? _tryParseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _quickUpdateStatus(String id, String status) async {
    final res =
        await _api.adminUpdateConsultationRequest(id, {'status': status});
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Đã cập nhật trạng thái'),
            backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ScrollableAlertDialog(
        title: const Text('Xoá lead?'),
        content: Text('Xoá yêu cầu tư vấn của ${item['name'] ?? ''}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Huỷ')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xoá', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.adminDeleteConsultationRequest(item['id'] as String);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Đã xoá lead'), backgroundColor: Colors.green),
      );
    }
  }

  void _showDetail(Map<String, dynamic> item) {
    final noteCtrl =
        TextEditingController(text: item['adminNote'] as String? ?? '');
    var selectedStatus = item['status'] as String? ?? 'New';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => ScrollableAlertDialog(
          title: Text(item['name'] as String? ?? 'Chi tiết lead'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('SĐT', item['phone'] as String? ?? ''),
                  if ((item['province'] as String?)?.isNotEmpty ?? false)
                    _detailRow('Tỉnh / thành', item['province'] as String),
                  if ((item['company'] as String?)?.isNotEmpty ?? false)
                    _detailRow('Công ty', item['company'] as String),
                  if ((item['interestedPlan'] as String?)?.isNotEmpty ?? false)
                    _detailRow(
                        'Gói quan tâm', item['interestedPlan'] as String),
                  _detailRow(
                      'Nguồn', item['source'] as String? ?? 'LandingPage'),
                  if ((item['clientIp'] as String?)?.isNotEmpty ?? false)
                    _detailRow('IP', item['clientIp'] as String),
                  if ((item['createdAt'] as String?)?.isNotEmpty ?? false)
                    _detailRow(
                        'Tạo lúc',
                        _df.format(
                            _tryParseDate(item['createdAt'] as String?) ??
                                DateTime.now())),
                  if ((item['notes'] as String?)?.isNotEmpty ?? false) ...[
                    const SizedBox(height: 8),
                    const Text('Ghi chú khách để lại',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Text(item['notes'] as String),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Trạng thái',
                      border: OutlineInputBorder(),
                    ),
                    items: _statusLabels.entries
                        .map((entry) => DropdownMenuItem(
                            value: entry.key, child: Text(entry.value)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => selectedStatus = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    minLines: 4,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú xử lý',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            _callCustomer(item['phone'] as String? ?? ''),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('Gọi điện'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            _openZalo(item['phone'] as String? ?? ''),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Nhắn Zalo'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Đóng')),
            FilledButton.icon(
              onPressed: () async {
                final res = await _api.adminUpdateConsultationRequest(
                  item['id'] as String,
                  {
                    'status': selectedStatus,
                    'adminNote': noteCtrl.text.trim().isEmpty
                        ? null
                        : noteCtrl.text.trim(),
                  },
                );
                if (!mounted) return;
                if (res['isSuccess'] == true) {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                  await _load();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Đã lưu xử lý lead'),
                        backgroundColor: Colors.green),
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text('$label:',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
