import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_theme.dart';

/// Danh sách phiếu hủy món đã báo bếp — đối soát / chống gian lận sau tạm tính.
class PosKitchenVoidListScreen extends StatefulWidget {
  const PosKitchenVoidListScreen({super.key});

  @override
  State<PosKitchenVoidListScreen> createState() =>
      _PosKitchenVoidListScreenState();
}

enum _BillPhaseFilter { all, before, after }

class _PosKitchenVoidListScreenState extends State<PosKitchenVoidListScreen> {
  final _api = ApiService();
  final _fmt = DateFormat('dd/MM HH:mm');
  final _dayFmt = DateFormat('dd/MM/yyyy');
  final _qtyFmt = NumberFormat('#,##0.###', 'vi_VN');
  final _staffCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  int _afterBillCount = 0;
  int _beforeBillCount = 0;

  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  _BillPhaseFilter _phase = _BillPhaseFilter.all;
  String? _resourceId;
  List<PosServiceResourceDto> _resources = [];

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _staffCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final res = await _api.getPosServiceResources();
    if (res['isSuccess'] == true && res['data'] is List) {
      final list = <PosServiceResourceDto>[];
      for (final e in res['data'] as List) {
        if (e is Map) {
          list.add(PosServiceResourceDto.fromJson(Map<String, dynamic>.from(e)));
        }
      }
      list.sort((a, b) => a.name.compareTo(b.name));
      _resources = list;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final fromUtc = DateTime(_from.year, _from.month, _from.day).toUtc();
    final toUtc = DateTime(_to.year, _to.month, _to.day, 23, 59, 59).toUtc();
    final res = await _api.getPosKitchenVoids(
      from: fromUtc,
      to: toUtc,
      afterBillOnly: _phase == _BillPhaseFilter.after ? true : null,
      beforeBillOnly: _phase == _BillPhaseFilter.before ? true : null,
      resourceId: _resourceId,
      voidedBy: _staffCtrl.text.trim().isEmpty ? null : _staffCtrl.text.trim(),
      take: 400,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được phiếu hủy';
      });
      return;
    }
    final data = res['data'] as Map;
    final raw = data['items'] ?? data['Items'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }
    setState(() {
      _loading = false;
      _items = list;
      _afterBillCount = (data['afterBillCount'] as num?)?.toInt() ??
          list.where((e) => e['afterBillRequested'] == true).length;
      _beforeBillCount = (data['beforeBillCount'] as num?)?.toInt() ??
          list.where((e) => e['afterBillRequested'] != true).length;
    });
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() => _from = d);
    await _load();
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() => _to = d);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: const Text('Phiếu hủy bếp'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.date_range, size: 16),
                        label: Text('Từ ${_dayFmt.format(_from)}'),
                        onPressed: _pickFrom,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.event, size: 16),
                        label: Text('Đến ${_dayFmt.format(_to)}'),
                        onPressed: _pickTo,
                      ),
                      ChoiceChip(
                        label: Text('Tất cả'),
                        selected: _phase == _BillPhaseFilter.all,
                        onSelected: (_) {
                          setState(() => _phase = _BillPhaseFilter.all);
                          _load();
                        },
                      ),
                      ChoiceChip(
                        label: Text('Trước TT ($_beforeBillCount)'),
                        selected: _phase == _BillPhaseFilter.before,
                        onSelected: (_) {
                          setState(() => _phase = _BillPhaseFilter.before);
                          _load();
                        },
                      ),
                      ChoiceChip(
                        label: Text('Sau TT ($_afterBillCount)'),
                        selected: _phase == _BillPhaseFilter.after,
                        onSelected: (_) {
                          setState(() => _phase = _BillPhaseFilter.after);
                          _load();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _resourceId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Bàn',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Tất cả bàn'),
                            ),
                            ..._resources.map(
                              (r) => DropdownMenuItem(
                                value: r.id,
                                child: Text('${r.name} (${r.code})'),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() => _resourceId = v);
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _staffCtrl,
                          decoration: InputDecoration(
                            labelText: 'Nhân viên',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.search, size: 18),
                              onPressed: _load,
                            ),
                          ),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _items.isEmpty
                        ? const Center(child: Text('Chưa có phiếu hủy'))
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final e = _items[i];
                              final after =
                                  e['afterBillRequested'] == true ||
                                      e['AfterBillRequested'] == true;
                              final qty =
                                  (e['qty'] ?? e['Qty'] as num?)?.toDouble() ??
                                      0;
                              final atRaw =
                                  (e['voidedAt'] ?? e['VoidedAt'])?.toString();
                              final at = atRaw != null
                                  ? DateTime.tryParse(atRaw)?.toLocal()
                                  : null;
                              return Material(
                                color: after
                                    ? const Color(0xFFFFF1F2)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                child: ListTile(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: BorderSide(
                                      color: after
                                          ? const Color(0xFFFECACA)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                  ),
                                  title: Text(
                                    '${e['productName'] ?? e['ProductName'] ?? ''} × ${_qtyFmt.format(qty)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text([
                                    if ((e['resourceName'] ??
                                            e['ResourceName'] ??
                                            '')
                                        .toString()
                                        .isNotEmpty)
                                      '${e['resourceName'] ?? e['ResourceName']}',
                                    if ((e['orderNo'] ?? e['OrderNo'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      '${e['orderNo'] ?? e['OrderNo']}',
                                    if (at != null) _fmt.format(at),
                                    if ((e['voidedBy'] ?? e['VoidedBy'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      '${e['voidedBy'] ?? e['VoidedBy']}',
                                    after ? '⚠ Sau tạm tính' : 'Trước tạm tính',
                                  ].join(' · ')),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
