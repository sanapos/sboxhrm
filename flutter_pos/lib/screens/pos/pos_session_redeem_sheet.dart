import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Lịch sử mua + sổ buổi / trừ buổi lúc bán.
Future<bool?> showPosSessionRedeemSheet(
  BuildContext context, {
  required String customerId,
  required String customerName,
  String? saleOrderId,
  List<Map<String, dynamic>> sellers = const [],
  bool requireStaff = false,
  bool enableRedeem = true,
  int initialTab = 0,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PosCustomerSessionSheet(
      customerId: customerId,
      customerName: customerName,
      saleOrderId: saleOrderId,
      sellers: sellers,
      requireStaff: requireStaff,
      enableRedeem: enableRedeem,
      initialTab: initialTab,
    ),
  );
}

class _PosCustomerSessionSheet extends StatefulWidget {
  const _PosCustomerSessionSheet({
    required this.customerId,
    required this.customerName,
    this.saleOrderId,
    required this.sellers,
    required this.requireStaff,
    required this.enableRedeem,
    required this.initialTab,
  });

  final String customerId;
  final String customerName;
  final String? saleOrderId;
  final List<Map<String, dynamic>> sellers;
  final bool requireStaff;
  final bool enableRedeem;
  final int initialTab;

  @override
  State<_PosCustomerSessionSheet> createState() =>
      _PosCustomerSessionSheetState();
}

class _PosCustomerSessionSheetState extends State<_PosCustomerSessionSheet>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _day = DateFormat('dd/MM/yyyy');
  final _dayTime = DateFormat('dd/MM/yyyy HH:mm');
  final _noteCtrl = TextEditingController();

  late final TabController _tabs;
  bool _loading = true;
  bool _redeeming = false;
  String? _error;
  List<PosSessionBalanceDto> _balances = [];
  List<PosSessionTxnDto> _txns = [];
  List<PosSessionOrderDto> _orders = [];
  String? _selectedBalanceId;
  String? _employeeId;
  DateTime _usedAt = DateTime.now();
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosCustomerSessionHistory(widget.customerId);
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _error = res['message']?.toString() ?? 'Không tải được lịch sử khách';
        _loading = false;
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final balances = ((data['balances'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => PosSessionBalanceDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final txns = ((data['transactions'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => PosSessionTxnDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final orders = ((data['orders'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => PosSessionOrderDto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    final active = balances.where((b) => b.remainingSessions > 0).toList();
    setState(() {
      _balances = balances;
      _txns = txns;
      _orders = orders;
      _selectedBalanceId = active.isNotEmpty
          ? active.first.id
          : (balances.isNotEmpty ? balances.first.id : null);
      _loading = false;
    });
  }

  List<({String id, String name})> get _sellerOpts {
    final out = <({String id, String name})>[];
    for (final e in widget.sellers) {
      final id = (e['id'] ?? e['employeeId'] ?? '').toString();
      if (id.isEmpty) continue;
      final name = (e['name'] ??
              e['fullName'] ??
              e['employeeName'] ??
              e['displayName'] ??
              '')
          .toString()
          .trim();
      out.add((id: id, name: name.isEmpty ? id : name));
    }
    return out;
  }

  Future<void> _pickUsedDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _usedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 400)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    setState(() {
      _usedAt = DateTime(d.year, d.month, d.day, _usedAt.hour, _usedAt.minute);
    });
  }

  Future<void> _redeem() async {
    if (_redeeming) return;
    PosSessionBalanceDto? b;
    for (final x in _balances) {
      if (x.id == _selectedBalanceId && x.remainingSessions > 0) {
        b = x;
        break;
      }
    }
    if (b == null) {
      NotificationOverlayManager().showError(
        title: 'Chưa chọn gói',
        message: tr('Chọn gói còn buổi để trừ'),
      );
      return;
    }
    if (widget.requireStaff && (_employeeId == null || _employeeId!.isEmpty)) {
      NotificationOverlayManager().showError(
        title: 'Thiếu nhân viên',
        message: tr('Chọn nhân viên làm buổi này'),
      );
      return;
    }
    setState(() => _redeeming = true);
    final res = await _api.redeemPosSessionBalance({
      'balanceId': b.id,
      'sessions': 1,
      if (widget.saleOrderId != null && widget.saleOrderId!.isNotEmpty)
        'saleOrderId': widget.saleOrderId,
      if (_employeeId != null && _employeeId!.isNotEmpty) 'employeeId': _employeeId,
      'usedAt': _usedAt.toUtc().toIso8601String(),
      'note': _noteCtrl.text.trim().isEmpty
          ? 'Trừ buổi tại quầy'
          : _noteCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _redeeming = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không trừ được buổi',
        message: res['message']?.toString() ?? 'Lỗi',
      );
      return;
    }
    _changed = true;
    _noteCtrl.clear();
    NotificationOverlayManager().showSuccess(
      title: 'Đã trừ 1 buổi',
      message: tr('${b.packageName} · ${_day.format(_usedAt)}'),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final remain = _balances.fold<int>(0, (s, b) => s + b.remainingSessions);
    final used = _balances.fold<int>(0, (s, b) => s + b.usedSessions);
    return SafeArea(
      child: SizedBox(
        height: h * 0.88,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(widget.customerName),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: tr('Tải lại'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, _changed),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              Text(
                remain + used == 0
                    ? tr('Lịch sử mua hàng và gói buổi của khách')
                    : tr('Còn $remain buổi · đã dùng $used'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabs,
                labelColor: PosTheme.kiotBlue,
                indicatorColor: PosTheme.kiotBlue,
                tabs: [
                  Tab(text: tr('Gói buổi')),
                  Tab(text: tr('Đơn mua')),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(tr(_error!), textAlign: TextAlign.center),
                                TextButton(
                                    onPressed: _load, child: Text(tr('Thử lại'))),
                              ],
                            ),
                          )
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              _buildPacksTab(),
                              _buildOrdersTab(),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPacksTab() {
    if (_balances.isEmpty) {
      return Center(
        child: Text(
          tr('Chưa có gói buổi.\nBán liệu trình / combo có số buổi (gắn khách) để cộng sổ.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade700, height: 1.4),
        ),
      );
    }
    final active = _balances.where((b) => b.remainingSessions > 0).toList();
    final sellers = _sellerOpts;
    return ListView(
      children: [
        if (widget.enableRedeem && active.isNotEmpty) ...[
          Text(tr('Trừ buổi hôm nay'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: active.any((b) => b.id == _selectedBalanceId)
                ? _selectedBalanceId
                : active.first.id,
            decoration: PosTheme.inputDecoration(label: 'Gói còn buổi'),
            items: [
              for (final b in active)
                DropdownMenuItem(
                  value: b.id,
                  child: Text(tr('${b.packageName} · còn ${b.remainingSessions}/${b.totalSessions}')),
                ),
            ],
            onChanged: (v) => setState(() => _selectedBalanceId = v),
          ),
          const SizedBox(height: 8),
          if (sellers.isNotEmpty)
            DropdownButtonFormField<String?>(
              value: sellers.any((s) => s.id == _employeeId) ? _employeeId : null,
              decoration: PosTheme.inputDecoration(
                label: widget.requireStaff
                    ? 'Nhân viên làm *'
                    : 'Nhân viên làm',
              ),
              items: [
                if (!widget.requireStaff)
                  DropdownMenuItem(value: null, child: Text(tr('Không chọn'))),
                for (final s in sellers)
                  DropdownMenuItem(value: s.id, child: Text(tr(s.name))),
              ],
              onChanged: (v) => setState(() => _employeeId = v),
            )
          else
            Text(tr('Chưa có danh sách nhân viên — trừ buổi vẫn ghi ngày.'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickUsedDate,
            child: InputDecorator(
              decoration: PosTheme.inputDecoration(label: 'Ngày sử dụng'),
              child: Text(tr(_day.format(_usedAt))),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            decoration: PosTheme.inputDecoration(label: 'Ghi chú (tuỳ chọn)'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _redeeming ? null : _redeem,
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            child: Text(tr(_redeeming ? 'Đang trừ...' : 'Trừ 1 buổi')),
          ),
          const SizedBox(height: 16),
        ],
        Text(tr('Chi tiết từng ngày'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        const SizedBox(height: 8),
        for (final b in _balances) _packCard(b),
        if (_txns.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(tr('Chưa có lần sử dụng'),
                style: TextStyle(color: Colors.grey.shade600)),
          ),
      ],
    );
  }

  Widget _packCard(PosSessionBalanceDto b) {
    final rows = _txns.where((t) => t.balanceId == b.id).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: PosTheme.border),
      ),
      child: ExpansionTile(
        initiallyExpanded: b.remainingSessions > 0,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(tr(b.packageName),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          tr('Còn ${b.remainingSessions}/${b.totalSessions} · đã dùng ${b.usedSessions}'
              '${b.expiresAt != null ? ' · HSD ${_day.format(b.expiresAt!.toLocal())}' : ''}'),
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(tr('Chưa có giao dịch'),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            )
          else
            for (final t in rows) _txnTile(t),
        ],
      ),
    );
  }

  Widget _txnTile(PosSessionTxnDto t) {
    final when = (t.usedAt ?? t.at).toLocal();
    final label = t.isPurchase
        ? 'Mua +${t.sessionDelta} buổi'
        : t.isRedeem
            ? 'Dùng ${t.sessionDelta.abs()} buổi'
            : '${t.transactionType} ${t.sessionDelta}';
    return ListTile(
      dense: true,
      leading: Icon(
        t.isPurchase ? Icons.add_card_outlined : Icons.event_available_outlined,
        color: t.isPurchase ? PosTheme.kiotBlue : const Color(0xFF16A34A),
        size: 20,
      ),
      title: Text(tr(label), style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        [
          _dayTime.format(when),
          if ((t.employeeName ?? '').trim().isNotEmpty) t.employeeName!,
          if ((t.orderNo ?? '').isNotEmpty) t.orderNo,
          if ((t.note ?? '').isNotEmpty) t.note,
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Text(tr('còn ${t.remainingAfter}'),
          style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
    );
  }

  Widget _buildOrdersTab() {
    if (_orders.isEmpty) {
      return Center(
        child: Text(tr('Chưa có đơn bán gắn khách này'),
            style: TextStyle(color: Colors.grey.shade700)),
      );
    }
    return ListView.separated(
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final o = _orders[i];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: PosTheme.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr(o.orderNo),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(tr(_money.format(o.total)),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (o.saleDate != null) _dayTime.format(o.saleDate!.toLocal()),
                    o.status,
                    if (o.paidAmount < o.total)
                      'nợ ${_money.format(o.total - o.paidAmount)}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (o.items.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(o.items.join('\n'),
                      style: const TextStyle(fontSize: 13, height: 1.35)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
