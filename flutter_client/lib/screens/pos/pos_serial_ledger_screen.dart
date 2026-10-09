import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';

/// Sổ seri máy: tìm theo seri / mã thẻ / IMEI / tên hàng, lọc theo trạng thái, xem vòng đời từng máy
/// (nhập kho → bán → bảo hành).
class PosSerialLedgerScreen extends StatefulWidget {
  const PosSerialLedgerScreen({super.key});

  @override
  State<PosSerialLedgerScreen> createState() => _PosSerialLedgerScreenState();
}

class _PosSerialLedgerScreenState extends State<PosSerialLedgerScreen> {
  final _api = ApiService();
  final _searchCtl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _status = ''; // '' = tất cả
  final List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _counts = {};
  int _page = 1;
  int _total = 0;
  bool _loading = true;
  bool _more = false;
  String? _error;

  static const _statuses = <String, (String, Color)>{
    '': ('Tất cả', SboxColors.slate600),
    'InStock': ('Trong kho', SboxColors.success),
    'Sold': ('Đã bán', SboxColors.brand600),
    'Removed': ('Đã xuất', SboxColors.slate500),
    'Missing': ('Thiếu', SboxColors.danger),
  };

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300 && !_more && !_loading && _items.length < _total) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      _page = 1;
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _more = true);
    }
    final r = await _api.getPosSerialLedger(search: _searchCtl.text, status: _status, page: _page);
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _more = false;
        _error = r['message']?.toString() ?? 'Không tải được sổ seri';
      });
      return;
    }
    final d = Map<String, dynamic>.from(r['data'] as Map);
    final rows = [
      for (final x in (d['items'] as List? ?? const []))
        if (x is Map) Map<String, dynamic>.from(x),
    ];
    setState(() {
      if (reset) _items.clear();
      _items.addAll(rows);
      _counts = Map<String, dynamic>.from((d['counts'] as Map?) ?? const {});
      _total = _n(d['total']);
      _page += 1;
      _loading = false;
      _more = false;
    });
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
  }

  String _d(dynamic v) {
    final d = parseApiUtcDateTime(v?.toString())?.toLocal();
    if (d == null) return '';
    String p(int x) => x.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)}/${d.year}';
  }

  Color _color(String? s) => _statuses[s ?? '']?.$2 ?? SboxColors.slate500;
  String _label(String? s) => _statuses[s ?? '']?.$1 ?? '$s';

  int _countFor(String key) => switch (key) {
        '' => _n(_counts['inStock']) + _n(_counts['sold']) + _n(_counts['removed']) + _n(_counts['missing']),
        'InStock' => _n(_counts['inStock']),
        'Sold' => _n(_counts['sold']),
        'Removed' => _n(_counts['removed']),
        'Missing' => _n(_counts['missing']),
        _ => 0,
      };

  Future<void> _detail(Map<String, dynamic> row) async {
    final r = await _api.getPosSerialDetail(row['id'].toString());
    if (!mounted || r['isSuccess'] != true) return;
    final d = Map<String, dynamic>.from(r['data'] as Map);
    final product = d['product'] as Map?;
    final receipt = d['receipt'] as Map?;
    final order = d['order'] as Map?;
    final warranties = [
      for (final w in (d['warranties'] as List? ?? const []))
        if (w is Map) Map<String, dynamic>.from(w),
    ];
    Widget line(IconData icon, String title, String sub, {Color? color}) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: color ?? SboxColors.slate500),
          title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: sub.isEmpty ? null : Text(tr(sub)),
        );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(tr('${d['serialNumber']}'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(tr('${product?['name'] ?? ''}'), style: const TextStyle(color: SboxColors.slate600)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                _pill(_label(d['status']?.toString()), _color(d['status']?.toString())),
                if ((d['tagCode']?.toString() ?? '').isNotEmpty) _pill('Thẻ ${d['tagCode']}', SboxColors.violet),
                if ((d['imei']?.toString() ?? '').isNotEmpty) _pill('IMEI ${d['imei']}', SboxColors.slate500),
              ]),
              const Divider(height: 24),
              line(Icons.move_to_inbox_rounded, 'Nhập kho',
                  receipt == null ? 'Không có phiếu nhập (nhập tay / dữ liệu cũ)' : '${receipt['receiptNo']} · ${_d(receipt['importDate'])}${receipt['supplierName'] != null ? ' · ${receipt['supplierName']}' : ''}'),
              if (order != null)
                line(Icons.sell_rounded, 'Bán cho khách',
                    '${order['orderNo']} · ${_d(order['saleDate'])}${order['customerName'] != null ? ' · ${order['customerName']}' : ''}',
                    color: SboxColors.brand600),
              for (final w in warranties)
                line(Icons.verified_outlined, 'Bảo hành · ${w['status']}',
                    '${w['warrantyMonths']} tháng · hết ${_d(w['warrantyExpiry'])}${(w['note']?.toString() ?? '').isNotEmpty ? ' · ${w['note']}' : ''}'),
              if ((d['note']?.toString() ?? '').isNotEmpty) line(Icons.notes_rounded, 'Ghi chú', '${d['note']}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(tr(t), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(title: Text(tr('Sổ seri máy'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _searchCtl,
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: tr('Tìm seri, mã thẻ, IMEI, tên hàng…'),
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchCtl.clear();
                        _load(reset: true);
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            for (final e in _statuses.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(tr('${e.value.$1} (${_countFor(e.key)})')),
                  selected: _status == e.key,
                  onSelected: (_) {
                    _status = e.key;
                    _load(reset: true);
                  },
                ),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)))
                  : _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              tr('Chưa có seri nào.\nSeri xuất hiện khi nhập hàng bắt buộc seri vào kho.'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: SboxColors.slate500),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: () => _load(reset: true),
                          child: ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            itemCount: _items.length + (_items.length < _total ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= _items.length) {
                                return const Padding(
                                    padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                              }
                              final x = _items[i];
                              final st = x['status']?.toString();
                              final sub = [
                                if (x['receiptNo'] != null) 'Nhập ${x['receiptNo']}',
                                if (x['orderNo'] != null) 'Bán ${x['orderNo']}',
                                if (x['customerName'] != null) '${x['customerName']}',
                                if ((x['tagCode']?.toString() ?? '').isNotEmpty) 'Thẻ ${x['tagCode']}',
                                if (x['inTransit'] == true) 'Đang chuyển kho'
                                else if ((x['branchName']?.toString() ?? '').isNotEmpty) '${x['branchName']}',
                              ].join(' · ');
                              return Card(
                                elevation: 0,
                                margin: const EdgeInsets.only(bottom: 6),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(color: SboxColors.slate200)),
                                child: ListTile(
                                  onTap: () => _detail(x),
                                  title: Text(tr('${x['serialNumber']}'),
                                      style: const TextStyle(fontWeight: FontWeight.w800)),
                                  subtitle: Text(tr('${x['productName'] ?? ''}${sub.isEmpty ? '' : '\n$sub'}'),
                                      maxLines: 3, overflow: TextOverflow.ellipsis),
                                  isThreeLine: sub.isNotEmpty,
                                  trailing: _pill(_label(st), _color(st)),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ]),
    );
  }
}
