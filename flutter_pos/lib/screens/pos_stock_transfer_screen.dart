import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/pos_stock_transfer_print.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos_barcode_scanner.dart';
import '../widgets/pos/pos_master_detail_layout.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/sbox/sbox_ui.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

final _dt = DateFormat('HH:mm dd/MM/yyyy');
final _qtyFmt = NumberFormat('#,##0.###', 'vi');

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
String _qty(Object? v) => _qtyFmt.format(_num(v));

/// Chi nhánh người dùng được thao tác (GET /api/branch-ops/context).
class _BranchCtx {
  _BranchCtx(Map<String, dynamic> d)
      : usesBranches = d['usesBranches'] == true,
        currentId = d['currentBranchId']?.toString(),
        headquarterId = d['headquarterBranchId']?.toString(),
        canSeeAll = d['canSeeAllBranches'] == true,
        branches = [
          for (final b in (d['branches'] as List? ?? const []))
            if ((b as Map)['isActive'] != false)
              (
                id: b['id'].toString(),
                name: b['name']?.toString() ?? '',
                hq: b['isHeadquarter'] == true,
              ),
        ];

  final bool usesBranches;
  final String? currentId;
  final String? headquarterId;
  final bool canSeeAll;
  final List<({String id, String name, bool hq})> branches;

  bool canUse(String? id) => canSeeAll || branches.any((b) => b.id == id);
}

const _statusTabs = [(null, 'Tất cả'), (0, 'Nháp'), (1, 'Đang chuyển'), (2, 'Đã nhận'), (3, 'Đã hủy')];

Widget _statusChip(int status, String label) {
  final (bg, fg) = switch (status) {
    0 => (SboxColors.slate100, SboxColors.slate700),
    1 => (SboxColors.warningSoft, SboxColors.warningText),
    2 => (SboxColors.successSoft, SboxColors.successText),
    _ => (SboxColors.dangerSoft, SboxColors.dangerText),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
    child: Text(tr(label), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
  );
}

/// Chuyển kho giữa chi nhánh — danh sách phiếu bên trái · chi tiết / tạo phiếu bên phải
/// (màn hẹp: mở trang riêng). Tổng tồn cửa hàng không đổi.
class PosStockTransferScreen extends StatefulWidget {
  const PosStockTransferScreen({super.key});

  @override
  State<PosStockTransferScreen> createState() => _PosStockTransferScreenState();
}

class _PosStockTransferScreenState extends State<PosStockTransferScreen> {
  final _api = ApiService();
  _BranchCtx? _ctx;
  int? _status;
  String? _branchId;
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Tìm ngay trên danh sách đã tải (mã phiếu, chi nhánh, ghi chú, tên hàng).
  List<Map<String, dynamic>> get _visible {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    bool hit(Object? v) => '${v ?? ''}'.toLowerCase().contains(q);
    return [
      for (final t in _items)
        if (hit(t['transferNo']) ||
            hit(t['fromBranchName']) ||
            hit(t['toBranchName']) ||
            hit(t['note']) ||
            (t['lines'] as List? ?? const [])
                .any((l) => hit((l as Map)['productName']) || hit(l['sku'])))
          t,
    ];
  }

  /// Cột phải (màn rộng): phiếu đang xem, hoặc form tạo khi [_creating].
  String? _selectedId;
  bool _creating = false;
  int _panelSeq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final r = await _api.getBranchContext();
    if (!mounted) return;
    setState(() => _ctx = _BranchCtx(
        r['isSuccess'] == true && r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : const {}));
    if (_ctx!.usesBranches) {
      await _load();
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getStockTransfers(status: _status, branchId: _branchId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = r['isSuccess'] == true && r['data'] is List
          ? [for (final x in r['data'] as List) Map<String, dynamic>.from(x as Map)]
          : [];
      if (_selectedId != null && !_items.any((t) => t['id'].toString() == _selectedId)) {
        _selectedId = null;
      }
    });
  }

  Map<String, dynamic>? get _selected {
    for (final t in _items) {
      if (t['id'].toString() == _selectedId) return t;
    }
    return null;
  }

  bool _isMd(BuildContext context) =>
      !posUseMobileList(context) && MediaQuery.sizeOf(context).width >= 1100;

  void _openCreate() {
    final ctx = _ctx;
    if (ctx == null) return;
    if (_isMd(context)) {
      setState(() {
        _creating = true;
        _selectedId = null;
        _panelSeq++;
      });
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(tr('Tạo phiếu chuyển kho'))),
        body: _TransferCreatePanel(
          ctx: ctx,
          onDone: (id) {
            Navigator.pop(context);
            _load();
          },
        ),
      ),
    ));
  }

  void _openDetail(Map<String, dynamic> t) {
    if (_isMd(context)) {
      setState(() {
        _creating = false;
        _selectedId = t['id'].toString();
        _panelSeq++;
      });
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(t['transferNo']?.toString() ?? '')),
        body: _TransferDetailPanel(
          transfer: t,
          ctx: _ctx!,
          onChanged: () {
            Navigator.pop(context);
            _load();
          },
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = context.watch<PermissionProvider>().canCreate('PosProducts');
    final ctx = _ctx;
    final md = _isMd(context);
    Widget body;
    if (ctx == null) {
      body = const LoadingWidget();
    } else if (!ctx.usesBranches || ctx.branches.length < 2) {
      body = const SboxEmptyState(
        icon: Icons.store_mall_directory_outlined,
        title: 'Cửa hàng chưa có nhiều chi nhánh',
        message: 'Chuyển kho dùng để chuyển hàng giữa các chi nhánh. '
            'Thêm chi nhánh trong Thiết lập SBOX để dùng chức năng này.',
      );
    } else if (md) {
      body = PosMasterDetailLayout(
        prefsKey: 'stock_transfers',
        initialFraction: 0.36,
        minMasterWidth: 380,
        master: Material(color: Colors.white, child: _buildList()),
        detail: _buildDetailPane(ctx),
      );
    } else {
      body = _buildList();
    }
    return Scaffold(
      backgroundColor: SboxColors.page,
      body: posMobileSafeBody(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PosModuleToolbar(activeModule: 'PosStockTransfers'),
            if (ctx != null && ctx.usesBranches && ctx.branches.length >= 2)
              Material(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 280,
                        height: 44,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: tr('Tìm mã phiếu, chi nhánh, hàng…'),
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildBranchFilter(ctx),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            for (final f in _statusTabs)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(tr(f.$2)),
                                  selected: _status == f.$1,
                                  onSelected: (_) {
                                    setState(() => _status = f.$1);
                                    _load();
                                  },
                                ),
                              ),
                          ]),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Làm mới'),
                        icon: const Icon(Icons.refresh),
                        onPressed: _load,
                      ),
                      if (canCreate) ...[
                        const SizedBox(width: 8),
                        SboxButton(label: 'Tạo phiếu chuyển', icon: Icons.add, onPressed: _openCreate),
                      ],
                    ],
                  ),
                ),
              ),
            const Divider(height: 1, color: PosTheme.border),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _buildBranchFilter(_BranchCtx ctx) {
    String? name;
    for (final b in ctx.branches) {
      if (b.id == _branchId) name = b.name;
    }
    final on = _branchId != null;
    return PopupMenuButton<String>(
      tooltip: tr('Lọc theo chi nhánh'),
      onSelected: (v) {
        setState(() => _branchId = v.isEmpty ? null : v);
        _load();
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(tr('Mọi chi nhánh'))),
        for (final b in ctx.branches)
          PopupMenuItem(
            value: b.id,
            child: Row(children: [
              Expanded(child: Text(tr('${b.name}${b.hq ? ' (trụ sở)' : ''}'))),
              if (b.id == _branchId) const Icon(Icons.check, size: 18, color: PosTheme.kiotBlue),
            ]),
          ),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? PosTheme.kiotBlueLight : null,
          border: Border.all(color: on ? PosTheme.kiotBlue : PosTheme.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.store_outlined, size: 18, color: on ? PosTheme.kiotBlue : PosTheme.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              tr(name ?? 'Mọi chi nhánh'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w600, color: on ? PosTheme.kiotBlue : PosTheme.textPrimary),
            ),
          ),
          const Icon(Icons.expand_more, size: 18),
        ]),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const LoadingWidget();
    final items = _visible;
    if (items.isEmpty && _items.isNotEmpty) {
      return Center(
        child: Text(tr('Không có phiếu khớp «${_searchCtrl.text.trim()}»'),
            style: const TextStyle(color: PosTheme.textSecondary)),
      );
    }
    if (items.isEmpty) {
      return const SboxEmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'Chưa có phiếu chuyển kho',
        message: 'Chuyển hàng từ chi nhánh dư sang chi nhánh thiếu — tổng tồn cửa hàng không đổi.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) => _buildRow(items[i]),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> t) {
    final selected = t['id'].toString() == _selectedId;
    final status = (t['status'] as num?)?.toInt() ?? 0;
    final created = parseApiUtcDateTime(t['createdAt']);
    final cancelled = status == 3;
    return Material(
      color: selected ? PosTheme.kiotBlueLight : Colors.white,
      child: InkWell(
        onTap: () => _openDetail(t),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: selected ? PosTheme.kiotBlue : Colors.transparent, width: 3),
              bottom: const BorderSide(color: PosTheme.border),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(
                    t['transferNo']?.toString() ?? '',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: cancelled ? Colors.red.shade700 : PosTheme.textPrimary,
                      decoration: cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                _statusChip(status, t['statusLabel']?.toString() ?? ''),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Flexible(
                  child: Text(tr(t['fromBranchName']?.toString() ?? ''),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded, size: 16, color: PosTheme.kiotBlue),
                ),
                Flexible(
                  child: Text(tr(t['toBranchName']?.toString() ?? ''),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 3),
              Text(
                tr([
                  if (created != null) _dt.format(created.toLocal()),
                  '${(t['lines'] as List? ?? const []).length} mặt hàng · SL ${_qty(t['totalQty'])}',
                ].join(' · ')),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPane(_BranchCtx ctx) {
    if (_creating) {
      return _TransferCreatePanel(
        key: ValueKey('create-$_panelSeq'),
        ctx: ctx,
        onClose: () => setState(() => _creating = false),
        onDone: (id) async {
          setState(() {
            _creating = false;
            _selectedId = id;
          });
          await _load();
        },
      );
    }
    final t = _selected;
    if (t == null) {
      return ColoredBox(
        color: SboxColors.slate50,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_shipping_outlined, size: 56, color: SboxColors.slate400),
              const SizedBox(height: 12),
              Text(tr('Chọn phiếu chuyển bên trái'),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(tr('Hàng trong phiếu và thao tác (gửi hàng, nhận hàng, hủy) hiện ở đây'),
                  style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
            ],
          ),
        ),
      );
    }
    return _TransferDetailPanel(
      key: ValueKey('detail-${t['id']}-$_panelSeq'),
      transfer: t,
      ctx: ctx,
      onClose: () => setState(() => _selectedId = null),
      onChanged: _load,
    );
  }
}

/// Thanh đầu cột phải: tiêu đề + nút đóng (chỉ khi nhúng màn rộng).
Widget _paneHeader({required Widget title, VoidCallback? onClose}) {
  return Material(
    color: Colors.white,
    child: Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: PosTheme.border))),
      padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
      child: Row(children: [
        Expanded(child: title),
        if (onClose != null)
          IconButton(tooltip: tr('Đóng'), icon: const Icon(Icons.close), onPressed: onClose),
      ]),
    ),
  );
}

/// Thanh nút ghim đáy.
Widget _paneFooter(List<Widget> children) {
  return Material(
    color: Colors.white,
    child: Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: PosTheme.border))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(top: false, child: Row(children: children)),
    ),
  );
}

Widget _box({String? title, Widget? trailing, required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: PosTheme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Row(children: [
            Expanded(
              child: Text(tr(title), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 10),
        ],
        child,
      ],
    ),
  );
}

// ─────────────────────────── Chi tiết phiếu ───────────────────────────

class _TransferDetailPanel extends StatefulWidget {
  const _TransferDetailPanel({
    super.key,
    required this.transfer,
    required this.ctx,
    required this.onChanged,
    this.onClose,
  });

  final Map<String, dynamic> transfer;
  final _BranchCtx ctx;
  final VoidCallback onChanged;
  final VoidCallback? onClose;

  @override
  State<_TransferDetailPanel> createState() => _TransferDetailPanelState();
}

class _TransferDetailPanelState extends State<_TransferDetailPanel> {
  final _api = ApiService();
  final Map<String, TextEditingController> _recv = {};
  bool _busy = false;

  Map<String, dynamic> get _t => widget.transfer;

  List<Map<String, dynamic>> get _lines =>
      [for (final l in (_t['lines'] as List? ?? const [])) Map<String, dynamic>.from(l as Map)];

  @override
  void dispose() {
    for (final c in _recv.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String okMsg) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: okMsg, message: _t['transferNo']?.toString() ?? '');
      widget.onChanged();
    } else {
      NotificationOverlayManager()
          .showError(title: 'Không thực hiện được', message: r['message']?.toString() ?? '');
    }
  }

  Future<void> _cancel(int status) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy phiếu ${_t['transferNo']}?')),
        content: Text(tr(status == 1
            ? 'Hàng đang chuyển sẽ trả về kho đi.'
            : 'Phiếu nháp sẽ bị hủy.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Hủy phiếu')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _api.cancelStockTransfer(_t['id'].toString()), 'Đã hủy phiếu');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (_t['status'] as num?)?.toInt() ?? 0;
    final ctx = widget.ctx;
    final canSend = status == 0 && ctx.canUse(_t['fromBranchId']?.toString());
    final canReceive = status == 1 && ctx.canUse(_t['toBranchId']?.toString());
    final canCancel = (status == 0 || status == 1) && ctx.canUse(_t['fromBranchId']?.toString());
    final events = [
      ('Tạo', _t['createdAt'], _t['createdByName']),
      ('Gửi', _t['sentAt'], _t['sentByName']),
      ('Nhận', _t['receivedAt'], _t['receivedByName']),
    ];
    return ColoredBox(
      color: SboxColors.slate50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paneHeader(
            onClose: widget.onClose,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(_t['transferNo']?.toString() ?? '',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: PosTheme.kiotBlue)),
                  const SizedBox(width: 10),
                  _statusChip(status, _t['statusLabel']?.toString() ?? ''),
                ]),
                const SizedBox(height: 2),
                Text(tr('${_t['fromBranchName']} → ${_t['toBranchName']}'),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _box(
                  child: Wrap(spacing: 24, runSpacing: 6, children: [
                    for (final e in events)
                      if (e.$2 != null)
                        Text(
                          tr('${e.$1}: ${_dt.format(parseApiUtcDateTime(e.$2)!)}'
                              '${e.$3 != null ? ' · ${e.$3}' : ''}'),
                          style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
                        ),
                    if ((_t['note'] ?? '').toString().isNotEmpty)
                      Text(tr('Ghi chú: ${_t['note']}'), style: const TextStyle(fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 12),
                _box(
                  title: 'Hàng chuyển (${_lines.length})',
                  trailing: Text(tr('Tổng SL ${_qty(_t['totalQty'])}'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final l in _lines)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Color(0xFFF0F2F5)))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(tr(l['productName']?.toString() ?? ''),
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                tr('${l['sku'] ?? ''} · gửi ${_qty(l['qty'])} ${l['unit'] ?? ''}'
                                    '${l['receivedQty'] != null ? ' · nhận ${_qty(l['receivedQty'])}' : ''}'),
                                style: const TextStyle(fontSize: 12.5, color: PosTheme.textSecondary),
                              ),
                            ]),
                          ),
                          if (canReceive)
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: _recv.putIfAbsent(
                                    l['id'].toString(), () => TextEditingController(text: _qty(l['qty']))),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.right,
                                decoration: InputDecoration(
                                  isDense: true,
                                  labelText: tr('Thực nhận'),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            )
                          else
                            Text(_qty(l['qty']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    if (canReceive)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(tr('Nhận thiếu → phần thiếu tự trả về kho đi.'),
                            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                      ),
                  ]),
                ),
              ],
            ),
          ),
          _paneFooter([
              OutlinedButton.icon(
                onPressed: () => printPosStockTransfer(context: context, transfer: _t),
                icon: const Icon(Icons.print, size: 18),
                label: Text(tr('In phiếu')),
              ),
              const SizedBox(width: 8),
              if (canCancel)
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _cancel(status),
                  style: OutlinedButton.styleFrom(foregroundColor: SboxColors.danger),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text(tr(status == 1 ? 'Hủy & trả hàng về kho đi' : 'Hủy phiếu')),
                ),
              const Spacer(),
              if (canSend)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => _api.sendStockTransfer(_t['id'].toString()), 'Đã gửi hàng'),
                  icon: const Icon(Icons.local_shipping_rounded, size: 18),
                  label: Text(tr('Gửi hàng')),
                ),
              if (canReceive)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => _api.receiveStockTransfer(_t['id'].toString(), lines: [
                                for (final l in _lines)
                                  {
                                    'lineId': l['id'],
                                    'receivedQty': double.tryParse((_recv[l['id'].toString()]?.text ?? '')
                                            .replaceAll('.', '')
                                            .replaceAll(',', '.')) ??
                                        _num(l['qty']),
                                  },
                              ]),
                          'Đã nhận hàng'),
                  icon: const Icon(Icons.inventory_rounded, size: 18),
                  label: Text(tr('Xác nhận đã nhận')),
                ),
            ]),
        ],
      ),
    );
  }
}

// ─────────────────────────── Tạo phiếu ───────────────────────────

class _Line {
  _Line(this.productId, this.name, this.code, this.unit, this.available, double qty)
      : _value = qty,
        ctrl = TextEditingController(text: _qty(qty));
  final String productId;
  final String name;
  final String code;
  final String unit;
  double available;
  double _value;

  /// Ô gõ số lượng — đồng bộ với nút +/−.
  final TextEditingController ctrl;

  double get qty => _value;
  set qty(double v) {
    _value = v < 0 ? 0 : v;
    ctrl.text = _qty(_value);
  }

  void setFromText(String t) {
    _value = double.tryParse(t.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  }
}

class _TransferCreatePanel extends StatefulWidget {
  const _TransferCreatePanel({super.key, required this.ctx, required this.onDone, this.onClose});

  final _BranchCtx ctx;

  /// Lưu xong → id phiếu mới.
  final ValueChanged<String?> onDone;
  final VoidCallback? onClose;

  @override
  State<_TransferCreatePanel> createState() => _TransferCreatePanelState();
}

class _TransferCreatePanelState extends State<_TransferCreatePanel> {
  final _api = ApiService();
  final _note = TextEditingController();
  final _search = TextEditingController();
  Timer? _debounce;
  String? _from;
  String? _to;
  final List<_Line> _lines = [];
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.ctx;
    // Kho đi mặc định: chi nhánh đang thao tác, không có thì trụ sở.
    _from = c.currentId ?? c.headquarterId ?? c.branches.first.id;
    if (!c.branches.any((b) => b.id == _from)) _from = c.branches.first.id;
    _to = c.branches.firstWhere((b) => b.id != _from, orElse: () => c.branches.first).id;
    _doSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    _search.dispose();
    for (final l in _lines) {
      l.ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _doSearch() async {
    if (_from == null) return;
    setState(() => _searching = true);
    final r = await _api.getBranchStock(branchId: _from, search: _search.text, filter: 'instock', pageSize: 30);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = [
        for (final x in ((r['data'] as Map?)?['items'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)
      ];
    });
  }

  /// Đổi kho đi → cập nhật số tồn có thể chuyển của các dòng đã chọn.
  Future<void> _refreshAvailability() async {
    if (_from == null || _lines.isEmpty) return;
    final r = await _api.getBranchStock(branchId: _from, pageSize: 500);
    if (!mounted) return;
    final map = {
      for (final x in ((r['data'] as Map?)?['items'] as List? ?? const []))
        (x as Map)['productId'].toString(): _num(x['qty'])
    };
    setState(() {
      for (final l in _lines) {
        l.available = map[l.productId] ?? 0;
      }
    });
  }

  /// Máy quét (gõ mã + Enter vào ô tìm) hoặc camera: tìm đúng mã / mã vạch ở kho đi rồi thêm 1.
  Future<void> _addByCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || _from == null) return;
    final r = await _api.getBranchStock(branchId: _from, search: code, filter: 'instock', pageSize: 10);
    if (!mounted) return;
    final items = [
      for (final x in ((r['data'] as Map?)?['items'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)
    ];
    final lc = code.toLowerCase();
    final exact = items.where((it) => '${it['productCode']}'.toLowerCase() == lc).toList();
    final pick = exact.isNotEmpty ? exact.first : (items.length == 1 ? items.first : null);
    if (pick == null) {
      NotificationOverlayManager().showWarning(
        title: items.isEmpty ? 'Không tìm thấy hàng' : 'Nhiều hàng khớp',
        message: tr(items.isEmpty
            ? '«$code» không có hoặc đã hết ở kho đi'
            : 'Chọn hàng trong danh sách bên dưới'),
      );
      _search.text = code;
      _doSearch();
      return;
    }
    _add(pick);
    _search.clear();
    _doSearch();
  }

  Future<void> _scanCamera() async {
    final code = await scanBarcodeWithCamera(context);
    if (code != null && mounted) await _addByCode(code);
  }

  void _add(Map<String, dynamic> it) {
    final id = it['productId'].toString();
    final exist = _lines.where((l) => l.productId == id).toList();
    setState(() {
      if (exist.isNotEmpty) {
        exist.first.qty += 1;
      } else {
        _lines.add(_Line(id, it['name']?.toString() ?? '', it['productCode']?.toString() ?? '',
            it['unit']?.toString() ?? '', _num(it['qty']), 1));
      }
    });
  }

  Future<void> _save(bool sendNow) async {
    if (_from == null || _to == null || _from == _to) {
      NotificationOverlayManager().showWarning(title: 'Chọn kho', message: tr('Chọn kho đi và kho đến khác nhau'));
      return;
    }
    final lines = _lines.where((l) => l.qty > 0).toList();
    if (lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Chưa có hàng', message: tr('Thêm hàng cần chuyển'));
      return;
    }
    final over = lines.where((l) => l.qty > l.available).toList();
    if (sendNow && over.isNotEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Vượt tồn kho đi', message: tr('«${over.first.name}» chỉ còn ${_qty(over.first.available)}'));
      return;
    }
    setState(() => _saving = true);
    final r = await _api.createStockTransfer({
      'fromBranchId': _from,
      'toBranchId': _to,
      'note': _note.text.trim(),
      'sendNow': sendNow,
      'lines': [
        for (final l in lines) {'productId': l.productId, 'variantId': null, 'qty': l.qty},
      ],
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      final data = r['data'] as Map?;
      NotificationOverlayManager().showSuccess(
          title: sendNow ? 'Đã gửi hàng' : 'Đã lưu nháp', message: data?['transferNo']?.toString() ?? '');
      widget.onDone(data?['id']?.toString());
    } else {
      NotificationOverlayManager().showError(title: 'Không tạo được phiếu', message: r['message']?.toString() ?? '');
    }
  }

  Widget _branchPick(String label, String? value, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: tr(label), isDense: true, border: const OutlineInputBorder()),
      items: [
        for (final b in widget.ctx.branches)
          DropdownMenuItem(value: b.id, child: Text(tr('${b.name}${b.hq ? ' (trụ sở)' : ''}'))),
      ],
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalQty = _lines.fold<double>(0, (a, l) => a + l.qty);
    return ColoredBox(
      color: SboxColors.slate50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.onClose != null)
            _paneHeader(
              onClose: widget.onClose,
              title: Text(tr('Tạo phiếu chuyển kho'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: PosTheme.kiotBlue)),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _box(
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        child: _branchPick('Kho đi', _from, (v) {
                          setState(() => _from = v);
                          _refreshAvailability();
                          _doSearch();
                        }),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.arrow_forward_rounded, color: PosTheme.kiotBlue),
                      ),
                      Expanded(child: _branchPick('Kho đến', _to, (v) => setState(() => _to = v))),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: tr('Ghi chú (tùy chọn)'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                _box(
                  title: 'Hàng chuyển (${_lines.length})',
                  trailing: Text(tr('Tổng SL ${_qty(totalQty)}'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  child: _lines.isEmpty
                      ? Text(tr('Chọn hàng từ danh sách «Thêm hàng từ kho đi» bên dưới'),
                          style: const TextStyle(color: PosTheme.textSecondary))
                      : Column(children: [
                          for (final l in _lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(tr(l.name), style: const TextStyle(fontWeight: FontWeight.w600)),
                                    Text(tr('${l.code} · kho đi còn ${_qty(l.available)} ${l.unit}'),
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: l.qty > l.available ? SboxColors.danger : PosTheme.textSecondary)),
                                  ]),
                                ),
                                IconButton(
                                  onPressed: () => setState(() => l.qty = l.qty - 1),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: TextField(
                                    controller: l.ctrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                                    ),
                                    onChanged: (t) => setState(() => l.setFromText(t)),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setState(() => l.qty += 1),
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                                IconButton(
                                  tooltip: tr('Bỏ dòng'),
                                  onPressed: () => setState(() {
                                    _lines.remove(l);
                                    l.ctrl.dispose();
                                  }),
                                  icon: const Icon(Icons.delete_outline, color: SboxColors.danger),
                                ),
                              ]),
                            ),
                        ]),
                ),
                const SizedBox(height: 12),
                _box(
                  title: 'Thêm hàng từ kho đi',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _search,
                      onChanged: (_) {
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 350), _doSearch);
                      },
                      onSubmitted: _addByCode,
                      decoration: InputDecoration(
                        isDense: true,
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: tr('Tìm hoặc quét mã vạch hàng ở kho đi…'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: tr('Quét mã vạch bằng camera'),
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: _scanCamera,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_searching)
                      const Padding(
                          padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                    else if (_results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(tr('Không có hàng còn tồn phù hợp'),
                            style: const TextStyle(color: PosTheme.textSecondary)),
                      )
                    else
                      for (final it in _results)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr(it['name']?.toString() ?? ''),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(tr('${it['productCode'] ?? ''} · còn ${_qty(it['qty'])} ${it['unit'] ?? ''}')),
                          trailing: const Icon(Icons.add_circle_rounded, color: PosTheme.kiotBlue),
                          onTap: () => _add(it),
                        ),
                    const SizedBox(height: 4),
                    Text(tr('Hàng có nhiều biến thể (size, màu…) được chuyển theo tổng số lượng của mặt hàng.'),
                        style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                  ]),
                ),
              ],
            ),
          ),
          _paneFooter([
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => _save(false),
                child: Text(tr('Lưu nháp')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _saving ? null : () => _save(true),
                icon: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.local_shipping_rounded),
                label: Text(tr('Gửi hàng ngay')),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
