import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pos_purchase.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_supplier_form_dialog.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Danh sách / quản lý nhà cung cấp (nợ, lịch sử, ngưng HD).
class PosSupplierListScreen extends StatefulWidget {
  const PosSupplierListScreen({super.key});

  @override
  State<PosSupplierListScreen> createState() => _PosSupplierListScreenState();
}

class _PosSupplierListScreenState extends State<PosSupplierListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  bool _loading = true;
  bool _activeOnly = true;
  List<PosSupplierFull> _items = [];
  int _total = 0;
  double _sumDebt = 0;
  double _sumPurchase = 0;

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
    final res = await _api.getPosPurchaseSuppliers(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      activeOnly: _activeOnly ? true : false,
      pageSize: 200,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map;
      final list = (data['items'] as List? ?? [])
          .map((e) => PosSupplierFull.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
      setState(() {
        _items = list;
        _total = (data['total'] as num?)?.toInt() ?? list.length;
        _sumDebt = (data['sumDebt'] as num?)?.toDouble() ?? 0;
        _sumPurchase = (data['sumPurchase'] as num?)?.toDouble() ?? 0;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tải được NCC',
      );
    }
  }

  Future<void> _addOrEdit({PosSupplierFull? existing}) async {
    final saved = await PosSupplierFormDialog.open(
      context,
      supplier: existing,
    );
    if (saved != null) await _load();
  }

  Future<void> _toggleActive(PosSupplierFull s) async {
    final res = s.isActive
        ? await _api.deactivatePosPurchaseSupplier(s.id)
        : await _api.activatePosPurchaseSupplier(s.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: s.isActive ? 'Đã ngừng NCC' : 'Đã kích hoạt',
        message: s.name,
      );
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? '',
      );
    }
  }

  Future<void> _delete(PosSupplierFull s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa nhà cung cấp?')),
        content: Text(tr('Xóa «${s.name}»?\nNếu đã có phiếu nhập sẽ không xóa được.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deletePosPurchaseSupplier(s.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã xóa', message: s.name);
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không xóa được',
        message: res['message']?.toString() ?? '',
      );
    }
  }

  Future<void> _showHistory(PosSupplierFull s) async {
    final res = await _api.getPosPurchaseSupplierHistory(s.id);
    if (!mounted) return;
    final items = res['isSuccess'] == true && res['data'] is List
        ? (res['data'] as List)
        : const [];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.6,
          child: Column(
            children: [
              ListTile(
                title: Text(tr('Lịch sử — ${s.name}'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('${items.length} chứng từ gần nhất')),
              ),
              const Divider(height: 1),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text(tr('Chưa có phiếu nhập/trả')))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final m = Map<String, dynamic>.from(items[i] as Map);
                          final type =
                              (m['docType'] ?? m['DocType'] ?? '').toString();
                          final no = (m['docNo'] ?? m['DocNo'] ?? '').toString();
                          final amount =
                              (m['amount'] ?? m['Amount'] as num?)?.toDouble() ??
                                  0;
                          final status =
                              (m['status'] ?? m['Status'] ?? '').toString();
                          final dateRaw = m['date'] ?? m['Date'];
                          final date = dateRaw != null
                              ? DateTime.tryParse(dateRaw.toString())
                              : null;
                          final isReturn = type.toLowerCase().contains('return');
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isReturn
                                  ? Icons.reply_outlined
                                  : Icons.shopping_cart_outlined,
                              color: isReturn
                                  ? Colors.orange
                                  : PosTheme.kiotBlue,
                            ),
                            title: Text(tr(no)),
                            subtitle: Text(tr(
                                '${isReturn ? 'Trả NCC' : 'Nhập'} · $status'
                                '${date != null ? ' · ${DateFormat('dd/MM/yyyy').format(date.toLocal())}' : ''}')),
                            trailing: Text(
                              tr('${_moneyFmt.format(amount)}đ'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Nhà cung cấp')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: tr('Thêm NCC'),
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: tr('Tìm mã, tên, SĐT…'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _load,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilterChip(
                        label: Text(tr('Đang hoạt động')),
                        selected: _activeOnly,
                        onSelected: (v) {
                          setState(() => _activeOnly = v);
                          _load();
                        },
                      ),
                      const Spacer(),
                      Text(
                        tr('$_total NCC · Nợ ${_moneyFmt.format(_sumDebt)}'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr('Tổng mua: ${_moneyFmt.format(_sumPurchase)}đ'),
                      style: const TextStyle(
                          fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: LoadingWidget())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tr('Chưa có nhà cung cấp'),
                                style: const TextStyle(
                                    color: PosTheme.textSecondary)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () => _addOrEdit(),
                              icon: const Icon(Icons.add_business_outlined),
                              label: Text(tr('Thêm NCC')),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final s = _items[i];
                          return ListTile(
                            tileColor: Colors.white,
                            leading: CircleAvatar(
                              backgroundColor: s.isActive
                                  ? PosTheme.kiotBlueLight
                                  : Colors.grey.shade200,
                              child: Text(
                                s.name.isNotEmpty
                                    ? s.name[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: s.isActive
                                      ? PosTheme.kiotBlue
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            title: Text(
                              tr(s.name),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: s.isActive
                                    ? null
                                    : PosTheme.textSecondary,
                              ),
                            ),
                            subtitle: Text(tr(
                                '${s.supplierCode}'
                                '${s.phone != null && s.phone!.isNotEmpty ? ' · ${s.phone}' : ''}'
                                '${s.currentDebt > 0 ? ' · Nợ ${_moneyFmt.format(s.currentDebt)}' : ''}')),
                            trailing: PopupMenuButton<String>(
                              onSelected: (a) async {
                                switch (a) {
                                  case 'edit':
                                    await _addOrEdit(existing: s);
                                  case 'history':
                                    await _showHistory(s);
                                  case 'toggle':
                                    await _toggleActive(s);
                                  case 'delete':
                                    await _delete(s);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'edit',
                                    child: Text(tr('Sửa'))),
                                PopupMenuItem(
                                    value: 'history',
                                    child: Text(tr('Lịch sử'))),
                                PopupMenuItem(
                                  value: 'toggle',
                                  child: Text(tr(s.isActive
                                      ? 'Ngừng hoạt động'
                                      : 'Kích hoạt')),
                                ),
                                PopupMenuItem(
                                    value: 'delete',
                                    child: Text(tr('Xóa'),
                                        style: const TextStyle(
                                            color: Colors.red))),
                              ],
                            ),
                            onTap: () => _showHistory(s),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        backgroundColor: HrmPageChrome.primaryNavy,
        icon: const Icon(Icons.add),
        label: Text(tr('Thêm NCC')),
      ),
    );
  }
}
