import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../widgets/notification_overlay.dart';
import '../utils/pos_kiot_time_range.dart';
import '../widgets/pos/pos_list_filters.dart';
import '../widgets/sbox/sbox_ui.dart';
import 'pos_sale_return_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Danh sách phiếu trả hàng bán.
class PosSaleReturnListScreen extends StatefulWidget {
  const PosSaleReturnListScreen({super.key});

  @override
  State<PosSaleReturnListScreen> createState() => _PosSaleReturnListScreenState();
}

class _PosSaleReturnListScreenState extends State<PosSaleReturnListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  List<_ReturnRow> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 40;
  PosKiotTimeFilterState _timeFilter = PosKiotTimeFilterState.thisMonth();
  Timer? _debounce;

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
    final res = await _api.getPosSaleReturnHistory(
      search: _searchCtrl.text,
      from: _timeFilter.from,
      to: _timeFilter.to,
      page: _page,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      _total = (data['total'] as num?)?.toInt() ?? 0;
      final items = data['items'];
      if (items is List) {
        _items = items
            .map((e) => _ReturnRow.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } else {
      _items = [];
      _total = 0;
    }
    setState(() => _loading = false);
  }

  Future<void> _openReturn(_ReturnRow row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PosSaleReturnScreen(orderId: row.orderId),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _voidReturn(_ReturnRow row) async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canApprove('PosSaleReturns') &&
        !perm.canApprove('PosSell') &&
        !perm.canEdit('PosProducts')) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy phiếu trả hàng')),
        content: Text(tr('Hủy phiếu ${row.returnNo} trên HĐ ${row.orderNo}?\nTrừ lại kho và cập nhật đơn hàng.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Hủy trả')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.cancelPosSaleReturn(row.orderId, row.returnNo);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã hủy trả hàng',
        message: row.returnNo,
      );
      await _load();
      ScreenRefreshNotifier.refreshPosAfterStockChange();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không hủy được',
      );
    }
  }

  Future<void> _newReturn() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PosSaleReturnScreen()),
    );
    if (mounted) await _load();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _page = 1;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canReturn = perm.canApprove('PosSaleReturns') ||
        perm.canApprove('PosSell') ||
        perm.canEdit('PosProducts');
    if (!perm.canView('PosSaleReturns') &&
        !perm.canView('PosSell') &&
        !perm.canView('PosProducts')) {
      return const Scaffold(
        body: SboxEmptyState(icon: Icons.lock_outline, title: 'Không có quyền xem trả hàng'),
      );
    }

    TextStyle? struck(_ReturnRow r) =>
        r.isVoided ? const TextStyle(decoration: TextDecoration.lineThrough, color: SboxColors.textMuted) : null;

    return Scaffold(
      backgroundColor: SboxColors.page,
      body: SboxReportLayout(
        onRefresh: _load,
        filters: SboxFilterBar(
          searchHint: 'Tìm mã trả, mã HĐ, tên khách…',
          searchController: _searchCtrl,
          onSearch: _onSearchChanged,
          filters: [
            PosTimeRangeChip(
              state: _timeFilter,
              onChanged: (v) {
                setState(() {
                  _timeFilter = v;
                  _page = 1;
                });
                _load();
              },
            ),
          ],
          actions: [
            if (canReturn) SboxButton(label: 'Trả hàng mới', icon: Icons.add, onPressed: _newReturn),
          ],
        ),
        table: SboxCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SboxDataTable<_ReturnRow>(
              loading: _loading,
              paginate: false,
              rows: _items,
              onRowTap: _openReturn,
              emptyTitle: 'Chưa có phiếu trả hàng',
              emptyMessage: 'Đổi khoảng thời gian, hoặc bấm « Trả hàng mới » để tạo phiếu trả.',
              rowActions: canReturn
                  ? (r) => r.isVoided
                      ? const SizedBox.shrink()
                      : IconButton(
                          tooltip: tr('Hủy phiếu trả'),
                          icon: const Icon(Icons.cancel_outlined, size: 18, color: SboxColors.dangerText),
                          onPressed: () => _voidReturn(r),
                        )
                  : null,
              columns: [
                SboxColumn(
                  label: 'Mã trả',
                  primary: true,
                  minWidth: 140,
                  cell: (r) => Text(r.returnNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (struck(r) ?? const TextStyle(color: SboxColors.primary))
                          .copyWith(fontWeight: SboxType.semibold)),
                ),
                SboxColumn(label: 'Hóa đơn', minWidth: 130, text: (r) => r.orderNo),
                SboxColumn(label: 'Thời gian', minWidth: 140, text: (r) => r.createdAt != null ? _dateFmt.format(r.createdAt!.toLocal()) : '—'),
                SboxColumn(label: 'Khách hàng', flex: 2, minWidth: 160, text: (r) => r.customerName ?? 'Khách lẻ'),
                SboxColumn(label: 'Hoàn qua', minWidth: 120, hideOnMobile: true, text: (r) => r.refundPaymentMethod ?? '—'),
                SboxColumn(
                  label: 'Tiền hoàn',
                  numeric: true,
                  minWidth: 120,
                  cell: (r) => Text(SboxFmt.money(r.refundAmount),
                      textAlign: TextAlign.right,
                      style: (struck(r) ?? const TextStyle()).copyWith(fontWeight: SboxType.semibold)),
                ),
                SboxColumn(
                  label: 'Trạng thái',
                  minWidth: 110,
                  cell: (r) => Align(
                    alignment: Alignment.centerLeft,
                    child: SboxStatusChip(
                      label: r.isVoided ? 'Đã hủy' : 'Đã trả',
                      tone: r.isVoided ? SboxTone.neutral : SboxTone.success,
                    ),
                  ),
                ),
              ],
            ),
            if (_total > _pageSize)
              SboxPager(
                page: _page,
                pageSize: _pageSize,
                total: _total,
                onPage: (p) {
                  setState(() => _page = p);
                  _load();
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _ReturnRow {
  _ReturnRow({
    required this.returnNo,
    required this.orderId,
    required this.orderNo,
    required this.refundAmount,
    this.refundPaymentMethod,
    this.createdAt,
    this.customerName,
    this.isVoided = false,
  });

  final String returnNo;
  final String orderId;
  final String orderNo;
  final double refundAmount;
  final String? refundPaymentMethod;
  final DateTime? createdAt;
  final String? customerName;
  final bool isVoided;

  factory _ReturnRow.fromJson(Map<String, dynamic> j) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return _ReturnRow(
      returnNo: (j['returnNo'] ?? j['ReturnNo'] ?? '').toString(),
      orderId: (j['orderId'] ?? j['OrderId'] ?? '').toString(),
      orderNo: (j['orderNo'] ?? j['OrderNo'] ?? '').toString(),
      refundAmount: n(j['refundAmount'] ?? j['RefundAmount']),
      refundPaymentMethod: j['refundPaymentMethod']?.toString() ??
          j['RefundPaymentMethod']?.toString(),
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'].toString())
          : null,
      customerName: j['customerName']?.toString() ?? j['CustomerName']?.toString(),
      isVoided: j['isVoided'] == true || j['IsVoided'] == true,
    );
  }
}
