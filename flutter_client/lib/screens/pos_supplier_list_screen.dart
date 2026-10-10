import 'dart:async';
import '../utils/api_datetime.dart';

import 'package:flutter/material.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../providers/permission_provider.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../models/pos_purchase.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_debt_statement.dart';
import '../widgets/pos/pos_supplier_debt_pay_dialog.dart';
import '../widgets/pos/pos_supplier_form_dialog.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
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
    _debounce?.cancel();
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
                    ? Center(child: Text(tr('Chưa có phiếu nhập / trả / thanh toán')))
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
                              ? parseApiUtcDateTime(dateRaw.toString())
                              : null;
                          final isReturn = type.toLowerCase().contains('return');
                          // Lần trả tiền NCC (giảm công nợ) — trạng thái = hình thức thanh toán.
                          final isPayment = type.toLowerCase() == 'payment';
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              isPayment
                                  ? Icons.payments_outlined
                                  : isReturn
                                      ? Icons.reply_outlined
                                      : Icons.shopping_cart_outlined,
                              color: isPayment
                                  ? Colors.green
                                  : isReturn
                                      ? Colors.orange
                                      : PosTheme.kiotBlue,
                            ),
                            title: Text(tr(no)),
                            subtitle: Text(tr(
                                '${isPayment ? 'Trả tiền NCC' : isReturn ? 'Trả hàng NCC' : 'Nhập'} · $status'
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

  Future<void> _showStatement(PosSupplierFull s) => showPosDebtStatementPage(
        context,
        title: s.name,
        subtitle: '${s.supplierCode} · Đang nợ ${SboxFmt.money(s.currentDebt)}',
        loader: (from, to) => _api.getPosSupplierStatement(s.id, from, to),
        increaseLabel: 'Nhập nợ',
        decreaseLabel: 'Đã trả / trả hàng',
      );

  Future<void> _payAll(PosSupplierFull s) async {
    final ok = await showPosSupplierPayAllDialog(context,
        supplierId: s.id, supplierName: s.name, currentDebt: s.currentDebt);
    if (ok == true) await _load();
  }

  Timer? _debounce;

  @override
  Widget build(BuildContext context) {
    // Nhà cung cấp thuộc module Hàng hóa (API /pos/purchase/suppliers).
    final perm = context.watch<PermissionProvider>();
    final canCreate = perm.canCreate('PosProducts');
    final canEdit = perm.canEdit('PosProducts');
    final canDelete = perm.canDelete('PosProducts');
    final canPay = perm.canEdit('PosPurchaseReceipts');
    final indebted = _items.where((x) => x.currentDebt > 0).length;
    return Scaffold(
      backgroundColor: SboxColors.page,
      // Trong khung chính thanh trên đã ghi tên màn — chỉ hiện thanh riêng khi mở thành trang con.
      appBar: HrmPageChrome.hideInPageTitle(context)
          ? null
          : AppBar(
              title: Text(tr('Nhà cung cấp')),
              backgroundColor: Colors.white,
              foregroundColor: SboxColors.text,
              surfaceTintColor: Colors.white,
              elevation: 0.5,
            ),
      body: SboxReportLayout(
        onRefresh: _load,
        filters: SboxFilterBar(
          searchHint: 'Tìm mã, tên, SĐT…',
          searchController: _searchCtrl,
          onSearch: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), _load);
          },
          filters: [
            SboxFilterChip<bool>(
              label: 'Trạng thái',
              value: _activeOnly,
              options: const {true: 'Đang hoạt động', false: 'Tất cả'},
              onChanged: (v) {
                setState(() => _activeOnly = v);
                _load();
              },
            ),
          ],
          actions: [
            if (canCreate) SboxButton(label: 'Thêm NCC', icon: Icons.add_business_outlined, onPressed: () => _addOrEdit()),
          ],
        ),
        kpis: [
          SboxKpi(label: 'Nhà cung cấp', value: SboxFmt.number(_total), icon: Icons.local_shipping_outlined),
          SboxKpi(label: 'Tổng mua', value: SboxFmt.money(_sumPurchase), icon: Icons.shopping_cart_outlined, tone: SboxTone.brand),
          SboxKpi(
            label: 'Đang nợ NCC',
            value: SboxFmt.money(_sumDebt),
            icon: Icons.account_balance_wallet_outlined,
            tone: _sumDebt > 0 ? SboxTone.danger : SboxTone.neutral,
            note: indebted > 0 ? '$indebted nhà cung cấp' : null,
          ),
        ],
        maxKpiColumns: 3,
        table: SboxCard(
          padding: EdgeInsets.zero,
          child: SboxDataTable<PosSupplierFull>(
            loading: _loading,
            rows: _items,
            pageSize: 50,
            onRowTap: _showHistory,
            emptyTitle: 'Chưa có nhà cung cấp',
            emptyMessage: canCreate ? 'Thêm NCC để theo dõi nhập hàng và công nợ.' : null,
            rowActions: (s) => PopupMenuButton<String>(
              tooltip: tr('Thao tác'),
              icon: const Icon(Icons.more_horiz, color: SboxColors.slate500),
              onSelected: (a) async {
                switch (a) {
                  case 'edit':
                    await _addOrEdit(existing: s);
                  case 'history':
                    await _showHistory(s);
                  case 'statement':
                    await _showStatement(s);
                  case 'pay':
                    await _payAll(s);
                  case 'toggle':
                    await _toggleActive(s);
                  case 'delete':
                    await _delete(s);
                }
              },
              itemBuilder: (_) => [
                if (canEdit) PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                PopupMenuItem(value: 'history', child: Text(tr('Lịch sử nhập / trả'))),
                PopupMenuItem(value: 'statement', child: Text(tr('Sổ đối chiếu công nợ'))),
                if (canPay && s.currentDebt > 0) PopupMenuItem(value: 'pay', child: Text(tr('Trả nợ'))),
                if (canEdit)
                  PopupMenuItem(value: 'toggle', child: Text(tr(s.isActive ? 'Ngừng hoạt động' : 'Kích hoạt'))),
                if (canDelete)
                  PopupMenuItem(value: 'delete', child: Text(tr('Xóa'), style: const TextStyle(color: Colors.red))),
              ],
            ),
            columns: [
              SboxColumn(
                label: 'Nhà cung cấp',
                primary: true,
                flex: 3,
                minWidth: 220,
                cell: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (s.isActive ? SboxType.bodyStyle() : SboxType.bodyStyle(SboxColors.textMuted)).copyWith(fontWeight: SboxType.semibold)),
                  Text(s.supplierCode, style: SboxType.smallStyle(SboxColors.textMuted)),
                ]),
                sortValue: (s) => s.name.toLowerCase(),
              ),
              SboxColumn(label: 'Điện thoại', minWidth: 130, text: (s) => (s.phone ?? '').isEmpty ? '—' : s.phone!),
              SboxColumn(label: 'Tổng mua', numeric: true, minWidth: 130, text: (s) => SboxFmt.money(s.totalPurchase), sortValue: (s) => s.totalPurchase),
              SboxColumn(
                label: 'Công nợ',
                numeric: true,
                minWidth: 120,
                cell: (s) => Text(s.currentDebt > 0 ? SboxFmt.money(s.currentDebt) : '—',
                    textAlign: TextAlign.right,
                    style: s.currentDebt > 0
                        ? SboxType.bodyStyle(SboxColors.dangerText).copyWith(fontWeight: SboxType.semibold)
                        : SboxType.bodyStyle(SboxColors.textMuted)),
                sortValue: (s) => s.currentDebt,
              ),
              SboxColumn(
                label: 'Trạng thái',
                minWidth: 120,
                hideOnMobile: true,
                cell: (s) => Align(
                  alignment: Alignment.centerLeft,
                  child: SboxStatusChip(
                    label: s.isActive ? 'Hoạt động' : 'Ngừng',
                    tone: s.isActive ? SboxTone.success : SboxTone.neutral,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
