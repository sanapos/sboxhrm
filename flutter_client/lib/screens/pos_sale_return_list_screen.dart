import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_theme.dart';
import 'pos_sale_return_screen.dart';

/// Danh sách phiếu trả hàng bán.
class PosSaleReturnListScreen extends StatefulWidget {
  const PosSaleReturnListScreen({super.key});

  @override
  State<PosSaleReturnListScreen> createState() => _PosSaleReturnListScreenState();
}

class _PosSaleReturnListScreenState extends State<PosSaleReturnListScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  bool _loading = true;
  List<_ReturnRow> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 40;

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
    final res = await _api.getPosSaleReturnHistory(
      search: _searchCtrl.text,
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy phiếu trả hàng'),
        content: Text(
            'Hủy phiếu ${row.returnNo} trên HĐ ${row.orderNo}?\nTrừ lại kho và cập nhật đơn hàng.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Không')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy trả'),
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
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không hủy được',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canEdit = perm.canEdit('PosSell') || perm.canEdit('PosProducts');
    if (!perm.canView('PosSell') && !perm.canView('PosProducts')) {
      return const Scaffold(
        body: Center(child: Text('Không có quyền xem trả hàng')),
      );
    }

    final mobile = posUseMobileList(context);
    final pages = (_total / _pageSize).ceil().clamp(1, 9999);

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: const Text('Danh sách trả hàng'),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PosSaleReturnScreen()),
          );
          if (mounted) await _load();
        },
        backgroundColor: PosTheme.kiotBlue,
        icon: const Icon(Icons.add),
        label: const Text('Trả hàng mới'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Tìm mã trả, HĐ, khách…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onSubmitted: (_) {
                      _page = 1;
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    _page = 1;
                    _load();
                  },
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$_total phiếu trả hàng',
                style: const TextStyle(
                  fontSize: 12,
                  color: PosTheme.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(child: Text('Chưa có phiếu trả hàng'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final r = _items[i];
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _openReturn(r),
                              child: Padding(
                                padding: EdgeInsets.all(mobile ? 12 : 14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            r.returnNo,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: r.isVoided
                                                  ? PosTheme.textSecondary
                                                  : PosTheme.kiotBlue,
                                              decoration: r.isVoided
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (r.isVoided)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text('Đã hủy',
                                                style: TextStyle(fontSize: 10)),
                                          )
                                        else if (canEdit)
                                          IconButton(
                                            visualDensity:
                                                VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(
                                                minWidth: 32, minHeight: 32),
                                            tooltip: 'Hủy phiếu trả',
                                            icon: const Icon(
                                                Icons.cancel_outlined,
                                                size: 18,
                                                color: Colors.red),
                                            onPressed: () => _voidReturn(r),
                                          ),
                                        Text(
                                          _moneyFmt.format(r.refundAmount),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: r.isVoided
                                                ? PosTheme.textSecondary
                                                : null,
                                            decoration: r.isVoided
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'HĐ ${r.orderNo} · ${r.customerName ?? 'Khách lẻ'}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${r.createdAt != null ? _dateFmt.format(r.createdAt!.toLocal()) : '—'}'
                                      '${r.refundPaymentMethod != null ? ' · ${r.refundPaymentMethod}' : ''}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: PosTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_total > _pageSize)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _page <= 1
                        ? null
                        : () {
                            _page--;
                            _load();
                          },
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('Trang $_page / $pages'),
                  IconButton(
                    onPressed: _page >= pages
                        ? null
                        : () {
                            _page++;
                            _load();
                          },
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
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
