import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/page_top_actions.dart';
import 'branch_ops_ui.dart';

final _dt = DateFormat('HH:mm dd/MM');

/// Chuyển kho giữa chi nhánh: danh sách phiếu + tạo / gửi / nhận / hủy.
class StockTransferScreen extends StatefulWidget {
  const StockTransferScreen({
    super.key,
    this.branchId,
    this.embedded = false,
    this.prefillProduct,
    this.prefillToBranchId,
  });

  /// Chỉ phiếu liên quan chi nhánh này (tab trong chi tiết chi nhánh).
  final String? branchId;
  final bool embedded;

  /// Mở sẵn màn tạo phiếu với 1 mặt hàng (từ Kho chi nhánh).
  final Map<String, dynamic>? prefillProduct;
  final String? prefillToBranchId;

  @override
  State<StockTransferScreen> createState() => _StockTransferScreenState();
}

class _StockTransferScreenState extends State<StockTransferScreen> {
  final _api = ApiService();
  int? _status;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.prefillProduct != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCreate(
            prefill: widget.prefillProduct,
            toBranchId: widget.prefillToBranchId,
          ));
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getStockTransfers(status: _status, branchId: widget.branchId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = r['isSuccess'] == true && r['data'] is List
          ? [for (final x in r['data'] as List) Map<String, dynamic>.from(x as Map)]
          : [];
    });
  }

  Future<void> _openCreate({Map<String, dynamic>? prefill, String? toBranchId}) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _CreateTransferPage(prefill: prefill, toBranchId: toBranchId),
    ));
    if (ok == true) _load();
  }

  Future<void> _openDetail(Map<String, dynamic> t) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TransferDetailSheet(transfer: t),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(widget.embedded ? 0 : 14, 12, widget.embedded ? 0 : 14, 90),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final f in const [(null, 'Tất cả'), (0, 'Nháp'), (1, 'Đang chuyển'), (2, 'Đã nhận'), (3, 'Đã hủy')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
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
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_items.isEmpty)
            BranchBox(
              child: Column(children: [
                const Icon(Icons.local_shipping_outlined, size: 40, color: SboxColors.slate300),
                const SizedBox(height: 8),
                Text(tr('Chưa có phiếu chuyển kho'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(tr('Chuyển hàng từ chi nhánh dư sang chi nhánh thiếu — tổng tồn cửa hàng không đổi.'),
                    textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500, fontSize: 12.5)),
              ]),
            )
          else
            for (final t in _items) _card(t),
        ],
      ),
    );
    final fab = FloatingActionButton.extended(
      onPressed: () => _openCreate(),
      icon: const Icon(Icons.add),
      label: Text(tr('Tạo phiếu chuyển')),
    );
    if (widget.embedded) {
      return Stack(children: [list, Positioned(right: 0, bottom: 12, child: fab)]);
    }
    final inShell = HrmPageChrome.hideInPageTitle(context);
    final scaffold = Scaffold(
      backgroundColor: SboxColors.slate50,
      // Trong khung chính thanh trên đã có tiêu đề — không lặp.
      appBar: inShell ? null : AppBar(title: Text(tr('Chuyển kho chi nhánh'))),
      floatingActionButton: inShell ? null : fab,
      body: list,
    );
    if (!inShell) return scaffold;
    // Trong khung chính: dùng nút nổi chung của app (điện thoại) / thanh trên (máy tính).
    return RegisterPageTopActions(
      actions: [
        HrmTopBarAction(
          icon: Icons.add,
          label: 'Tạo phiếu chuyển',
          primary: true,
          showLabel: true,
          onPressed: () => _openCreate(),
        ),
        HrmTopBarAction(icon: Icons.refresh, label: 'Làm mới', onPressed: _load),
      ],
      child: scaffold,
    );
  }

  Widget _card(Map<String, dynamic> t) {
    final status = (t['status'] as num?)?.toInt() ?? 0;
    final created = DateTime.tryParse('${t['createdAt']}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(t),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(t['transferNo']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              TransferStatusChip(status: status, label: t['statusLabel']?.toString() ?? ''),
              const Spacer(),
              if (created != null)
                Text(_dt.format(created.toLocal()), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Flexible(child: Text(tr(t['fromBranchName']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.w600))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: SboxColors.brand500),
              ),
              Flexible(child: Text(tr(t['toBranchName']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 4),
            Text(
              tr('${(t['lines'] as List? ?? const []).length} mặt hàng · ${bQty(t['totalQty'])} đơn vị'
                  '${(t['note'] ?? '').toString().isNotEmpty ? ' · ${t['note']}' : ''}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────── Chi tiết phiếu ───────────────────────────

class _TransferDetailSheet extends StatefulWidget {
  const _TransferDetailSheet({required this.transfer});
  final Map<String, dynamic> transfer;

  @override
  State<_TransferDetailSheet> createState() => _TransferDetailSheetState();
}

class _TransferDetailSheetState extends State<_TransferDetailSheet> {
  final _api = ApiService();
  late final Map<String, dynamic> _t = widget.transfer;
  final Map<String, TextEditingController> _recv = {};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _recv.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _lines => [for (final l in (_t['lines'] as List? ?? const [])) Map<String, dynamic>.from(l as Map)];

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String okMsg) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: okMsg, message: _t['transferNo']?.toString() ?? '');
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Không thực hiện được', message: r['message']?.toString() ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (_t['status'] as num?)?.toInt() ?? 0;
    final s = BranchSession.instance;
    bool canUse(String? id) => s.canSeeAll || s.branches.any((b) => b.id == id);
    final canSend = status == 0 && canUse(_t['fromBranchId']?.toString());
    final canReceive = status == 1 && canUse(_t['toBranchId']?.toString());
    final canCancel = (status == 0 || status == 1) && canUse(_t['fromBranchId']?.toString());
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(_t['transferNo']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              TransferStatusChip(status: status, label: _t['statusLabel']?.toString() ?? ''),
            ]),
            const SizedBox(height: 6),
            Text(tr('${_t['fromBranchName']} → ${_t['toBranchName']}'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 2, children: [
              for (final e in [
                ('Tạo', _t['createdAt'], _t['createdByName']),
                ('Gửi', _t['sentAt'], _t['sentByName']),
                ('Nhận', _t['receivedAt'], _t['receivedByName']),
              ])
                if (e.$2 != null)
                  Text(
                    tr('${e.$1}: ${_dt.format(DateTime.parse('${e.$2}').toLocal())}${e.$3 != null ? ' · ${e.$3}' : ''}'),
                    style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500),
                  ),
            ]),
            if ((_t['note'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(tr('Ghi chú: ${_t['note']}'), style: const TextStyle(fontSize: 12.5)),
            ],
            const Divider(height: 22),
            for (final l in _lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l['productName']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(tr('${l['sku'] ?? ''} · gửi ${bQty(l['qty'])} ${l['unit'] ?? ''}'
                          '${l['receivedQty'] != null ? ' · nhận ${bQty(l['receivedQty'])}' : ''}'),
                          style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                    ]),
                  ),
                  if (canReceive)
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _recv.putIfAbsent(
                            l['id'].toString(), () => TextEditingController(text: bQty(l['qty']))),
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
                    Text(bQty(l['qty']), style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            if (canReceive)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('Nhận thiếu → phần thiếu tự trả về kho đi.'),
                    style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
              ),
            const SizedBox(height: 6),
            Row(children: [
              if (canCancel)
                TextButton.icon(
                  onPressed: _busy ? null : () => _run(() => _api.cancelStockTransfer(_t['id'].toString()), 'Đã hủy phiếu'),
                  style: TextButton.styleFrom(foregroundColor: SboxColors.danger),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(tr(status == 1 ? 'Hủy & trả hàng về kho đi' : 'Hủy phiếu')),
                ),
              const Spacer(),
              if (canSend)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _run(() => _api.sendStockTransfer(_t['id'].toString()), 'Đã gửi hàng'),
                  icon: const Icon(Icons.local_shipping_rounded),
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
                                    'receivedQty': double.tryParse(
                                            (_recv[l['id'].toString()]?.text ?? '').replaceAll('.', '').replaceAll(',', '.')) ??
                                        bNum(l['qty']),
                                  },
                              ]),
                          'Đã nhận hàng'),
                  icon: const Icon(Icons.inventory_rounded),
                  label: Text(tr('Xác nhận đã nhận')),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────── Tạo phiếu ───────────────────────────

class _CreateTransferPage extends StatefulWidget {
  const _CreateTransferPage({this.prefill, this.toBranchId});
  final Map<String, dynamic>? prefill;
  final String? toBranchId;

  @override
  State<_CreateTransferPage> createState() => _CreateTransferPageState();
}

class _Line {
  _Line(this.productId, this.name, this.unit, this.available, this.qty);
  final String productId;
  final String name;
  final String unit;
  double available;
  double qty;
}

class _CreateTransferPageState extends State<_CreateTransferPage> {
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
    final s = BranchSession.instance;
    _to = widget.toBranchId;
    // Kho đi mặc định: trụ sở (nếu kho đến là chi nhánh khác) hoặc chi nhánh đang thao tác.
    _from = (s.headquarterId != null && s.headquarterId != _to && s.branches.any((b) => b.id == s.headquarterId))
        ? s.headquarterId
        : s.writeBranchId;
    if (_from == _to) {
      _from = s.branches.firstWhere((b) => b.id != _to, orElse: () => s.branches.first).id;
    }
    final p = widget.prefill;
    if (p != null) {
      _lines.add(_Line(p['productId'].toString(), p['name']?.toString() ?? '', p['unit']?.toString() ?? '', 0, 1));
      _refreshAvailability();
    }
    _doSearch();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _note.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    if (_from == null) return;
    setState(() => _searching = true);
    final r = await _api.getBranchStock(branchId: _from, search: _search.text, filter: 'instock', pageSize: 30);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = [for (final x in ((r['data'] as Map?)?['items'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
    });
  }

  /// Đổi kho đi → cập nhật số tồn có thể chuyển của các dòng.
  Future<void> _refreshAvailability() async {
    if (_from == null) return;
    final r = await _api.getBranchStock(branchId: _from, pageSize: 500);
    if (!mounted) return;
    final map = {
      for (final x in ((r['data'] as Map?)?['items'] as List? ?? const []))
        (x as Map)['productId'].toString(): bNum(x['qty'])
    };
    setState(() {
      for (final l in _lines) {
        l.available = map[l.productId] ?? 0;
      }
    });
  }

  void _add(Map<String, dynamic> it) {
    final id = it['productId'].toString();
    final exist = _lines.where((l) => l.productId == id).toList();
    setState(() {
      if (exist.isNotEmpty) {
        exist.first.qty += 1;
      } else {
        _lines.add(_Line(id, it['name']?.toString() ?? '', it['unit']?.toString() ?? '', bNum(it['qty']), 1));
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
          title: 'Vượt tồn kho đi', message: tr('«${over.first.name}» chỉ còn ${bQty(over.first.available)}'));
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
      NotificationOverlayManager().showSuccess(
          title: sendNow ? 'Đã gửi hàng' : 'Đã lưu nháp', message: (r['data'] as Map?)?['transferNo']?.toString() ?? '');
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Không tạo được phiếu', message: r['message']?.toString() ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = BranchSession.instance;
    DropdownButtonFormField<String> branchPick(String label, String? value, ValueChanged<String?> onChanged) =>
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: tr(label), isDense: true, border: const OutlineInputBorder()),
          items: [
            for (final b in s.branches)
              DropdownMenuItem(value: b.id, child: Text(tr('${b.name}${b.isHeadquarter ? ' (trụ sở)' : ''}'))),
          ],
          onChanged: onChanged,
        );
    final totalQty = _lines.fold<double>(0, (a, l) => a + l.qty);
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(title: Text(tr('Tạo phiếu chuyển kho'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 110),
        children: [
          BranchBox(
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: branchPick('Kho đi', _from, (v) {
                    setState(() => _from = v);
                    _refreshAvailability();
                    _doSearch();
                  }),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: SboxColors.brand500),
                ),
                Expanded(child: branchPick('Kho đến', _to, (v) => setState(() => _to = v))),
              ]),
              const SizedBox(height: 10),
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
          BranchBox(
            title: 'Hàng chuyển (${_lines.length})',
            trailing: Text(tr('Tổng ${bQty(totalQty)}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            child: _lines.isEmpty
                ? Text(tr('Chọn hàng từ danh sách bên dưới'), style: const TextStyle(color: SboxColors.slate500))
                : Column(children: [
                    for (final l in _lines)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(l.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(tr('Kho đi còn ${bQty(l.available)} ${l.unit}'),
                                  style: TextStyle(
                                      fontSize: 12, color: l.qty > l.available ? SboxColors.danger : SboxColors.slate500)),
                            ]),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => l.qty = (l.qty - 1).clamp(0, double.infinity)),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(bQty(l.qty), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => l.qty += 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _lines.remove(l)),
                            icon: const Icon(Icons.delete_outline, color: SboxColors.danger),
                          ),
                        ]),
                      ),
                  ]),
          ),
          const SizedBox(height: 12),
          BranchBox(
            title: 'Thêm hàng từ kho đi',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _search,
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _doSearch);
                },
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Tìm hàng còn tồn ở kho đi…'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              if (_searching)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              else if (_results.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(tr('Không có hàng còn tồn phù hợp'), style: const TextStyle(color: SboxColors.slate500)),
                )
              else
                for (final it in _results)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(it['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(tr('${it['productCode'] ?? ''} · còn ${bQty(it['qty'])} ${it['unit'] ?? ''}')),
                    trailing: IconButton(
                      onPressed: () => _add(it),
                      icon: const Icon(Icons.add_circle_rounded, color: SboxColors.brand500),
                    ),
                    onTap: () => _add(it),
                  ),
              const SizedBox(height: 4),
              Text(tr('Hàng có nhiều biến thể (size, màu…) được chuyển theo tổng số lượng của mặt hàng.'),
                  style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
            ]),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(children: [
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
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.local_shipping_rounded),
                label: Text(tr('Gửi hàng ngay')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
