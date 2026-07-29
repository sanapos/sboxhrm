import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _theme = Color(0xFF0EA5E9);

/// Quản lý loại chi phí công tác (thêm / sửa tên / xóa).
class BusinessTripCategoriesScreen extends StatefulWidget {
  const BusinessTripCategoriesScreen({super.key});

  @override
  State<BusinessTripCategoriesScreen> createState() =>
      _BusinessTripCategoriesScreenState();
}

class _BusinessTripCategoriesScreenState
    extends State<BusinessTripCategoriesScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  bool get _canEdit =>
      Provider.of<PermissionProvider>(context, listen: false)
          .canEdit('BusinessTripExpense');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getBusinessTripExpenseCategories();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      _items = (res['data'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort((a, b) => ((a['sortOrder'] as num?)?.toInt() ?? 0)
            .compareTo((b['sortOrder'] as num?)?.toInt() ?? 0));
    }
    setState(() => _loading = false);
  }

  Future<void> _seed() async {
    final res = await _api.seedBusinessTripExpenseCategories();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(
        title: 'Đã khởi tạo',
        message: tr('Đã bổ sung các loại chi phí mẫu còn thiếu'),
      );
      await _load();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không khởi tạo được',
      );
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    if (!_canEdit) {
      appNotification.showWarning(
        title: 'Không có quyền',
        message: tr('Chỉ quản lý mới được thêm/sửa loại chi phí'),
      );
      return;
    }
    final codeCtrl = TextEditingController(text: tr(item?['code']?.toString() ?? ''));
    final nameCtrl = TextEditingController(text: tr(item?['name']?.toString() ?? ''));
    final sortCtrl = TextEditingController(
        text: tr(((item?['sortOrder'] as num?)?.toInt() ?? (_items.length + 1))
            .toString()));
    var requiresInvoice = item?['requiresInvoice'] == true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr(item == null ? 'Thêm loại chi phí' : 'Sửa loại chi phí')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  enabled: item == null,
                  decoration: InputDecoration(
                    labelText: tr('Mã *'),
                    hintText: tr('VD: AN, XE, KS'),
                  ),
                ),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: tr('Tên hiển thị *')),
                ),
                TextField(
                  controller: sortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr('Thứ tự')),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Bắt buộc hóa đơn')),
                  value: requiresInvoice,
                  onChanged: (v) => setDlg(() => requiresInvoice = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Hủy'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );

    final code = codeCtrl.text.trim().toUpperCase();
    final name = nameCtrl.text.trim();
    final sort = int.tryParse(sortCtrl.text.trim()) ?? 0;
    codeCtrl.dispose();
    nameCtrl.dispose();
    sortCtrl.dispose();
    if (ok != true) return;
    if (code.isEmpty || name.isEmpty) {
      appNotification.showError(
          title: 'Thiếu thông tin', message: tr('Nhập mã và tên loại chi phí'));
      return;
    }

    final res = await _api.upsertBusinessTripExpenseCategory(
      {
        'code': code,
        'name': name,
        'requiresInvoice': requiresInvoice,
        'sortOrder': sort,
      },
      id: item?['id']?.toString(),
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã lưu', message: name);
      await _load();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được',
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    if (!_canEdit) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa loại chi phí?')),
        content: Text(tr('${tr('Ẩn "')}${item['name']}" khỏi danh sách chọn khi nhập chi phí.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final id = item['id']?.toString();
    if (id == null) return;
    final res = await _api.deleteBusinessTripExpenseCategory(id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã xóa', message: item['name']?.toString() ?? '');
      await _load();
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không xóa được',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(tr('Loại chi phí công tác')),
        backgroundColor: _theme,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('Khởi tạo mẫu còn thiếu'),
            onPressed: _seed,
            icon: const Icon(Icons.playlist_add),
          ),
          if (_canEdit)
            IconButton(
              tooltip: tr('Thêm loại'),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              backgroundColor: _theme,
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(tr('Thêm loại')),
            )
          : null,
      body: _loading
          ? const LoadingWidget()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    elevation: 0,
                    color: _theme.withValues(alpha: 0.06),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: _theme.withValues(alpha: 0.2)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        tr('Tại đây thêm/sửa/xóa tên loại chi phí (Tiền ăn, xe, nhà nghỉ…). '
                        'Nhân viên sẽ chọn các loại này khi nhập số tiền và phân loại hóa đơn.'),
                        style: TextStyle(fontSize: 13, height: 1.35),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_items.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text(tr('Chưa có loại chi phí. Bấm + hoặc khởi tạo mẫu.'))),
                    )
                  else
                    ..._items.map((item) {
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _theme.withValues(alpha: 0.12),
                            child: Icon(
                              item['requiresInvoice'] == true
                                  ? Icons.receipt_long
                                  : Icons.payments_outlined,
                              color: _theme,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            tr(item['name']?.toString() ?? ''),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(tr('${tr('Mã: ')}${item['code']}'
                            '${item['requiresInvoice'] == true ? ' · Bắt buộc HĐ' : ''}'),
                          ),
                          trailing: _canEdit
                              ? PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _edit(item);
                                    if (v == 'delete') _delete(item);
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                        value: 'edit', child: Text(tr('Sửa tên'))),
                                    PopupMenuItem(
                                        value: 'delete',
                                        child: Text(tr('Xóa'),
                                            style: TextStyle(color: Colors.red))),
                                  ],
                                )
                              : null,
                          onTap: _canEdit ? () => _edit(item) : null,
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
