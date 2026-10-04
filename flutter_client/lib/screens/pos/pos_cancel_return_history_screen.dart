import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/pos/pos_list_filters.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import '../../widgets/reports/hrm_report_widgets.dart' show ReportKpiItem, ReportDashboard, SboxTone;
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/sbox/sbox_report.dart';

/// Lịch sử hủy món / hủy đơn / trả hàng — lọc thao tác & trước/sau tạm tính.
class PosCancelReturnHistoryScreen extends StatefulWidget {
  const PosCancelReturnHistoryScreen({super.key});

  @override
  State<PosCancelReturnHistoryScreen> createState() =>
      _PosCancelReturnHistoryScreenState();
}

enum _ActionFilter { all, kitchenVoid, saleCancel, saleReturn }

enum _BillPhaseFilter { all, before, after }

class _PosCancelReturnHistoryScreenState
    extends State<PosCancelReturnHistoryScreen> {
  final _api = ApiService();
  final _fmt = DateFormat('dd/MM/yyyy HH:mm:ss');
  final _dayFmt = DateFormat('dd/MM/yyyy');
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _qty = NumberFormat('#,##0.###', 'vi_VN');
  final _actorCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  _ActionFilter _action = _ActionFilter.all;
  _BillPhaseFilter _phase = _BillPhaseFilter.all;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _actorCtrl.dispose();
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _actionTypeParam => switch (_action) {
        _ActionFilter.kitchenVoid => 'KitchenVoid',
        _ActionFilter.saleCancel => 'SaleCancel',
        _ActionFilter.saleReturn => 'SaleReturn',
        _ActionFilter.all => null,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final fromUtc = DateTime(_from.year, _from.month, _from.day).toUtc();
    final toUtc = DateTime(_to.year, _to.month, _to.day, 23, 59, 59).toUtc();
    final res = await _api.getPosCancelReturnAudits(
      from: fromUtc,
      to: toUtc,
      actionType: _actionTypeParam,
      afterBillOnly: _phase == _BillPhaseFilter.after ? true : null,
      beforeBillOnly: _phase == _BillPhaseFilter.before ? true : null,
      actor: _actorCtrl.text.trim().isEmpty ? null : _actorCtrl.text.trim(),
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      take: 400,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được lịch sử';
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
    });
  }

  String _actionLabel(String? t) => switch (t) {
        'KitchenVoid' => 'Hủy món bếp',
        'SaleCancel' => 'Hủy đơn',
        'SaleReturn' => 'Trả hàng',
        _ => t ?? '—',
      };

  Color _actionColor(String? t) => switch (t) {
        'KitchenVoid' => SboxColors.warningText,
        'SaleCancel' => SboxColors.danger,
        'SaleReturn' => SboxColors.brand600,
        _ => PosTheme.textSecondary,
      };

  void _setRange(int days) {
    final now = DateTime.now();
    setState(() {
      _to = DateTime(now.year, now.month, now.day);
      _from = _to.subtract(Duration(days: days - 1));
    });
    unawaited(_load());
  }

  // ── Dashboard ──

  List<ReportKpiItem> _kpis() {
    int count(String t) => _items.where((m) => m['actionType'] == t).length;
    double amt(Iterable<Map<String, dynamic>> xs) =>
        xs.fold(0.0, (s, m) => s + ((m['amount'] as num?)?.toDouble() ?? 0));
    final total = amt(_items);
    final after = _items.where((m) => m['afterProvisionalBill'] == true).toList();
    String sub(String t) => '${_money.format(amt(_items.where((m) => m['actionType'] == t)))}đ';
    return [
      ReportKpiItem(
        label: 'Tổng lượt hủy / trả',
        value: '${_items.length}',
        note: '${_money.format(total)}đ',
        icon: Icons.receipt_long_outlined,
        color: SboxColors.brand600,
      ),
      ReportKpiItem(
        label: 'Hủy món bếp',
        value: '${count('KitchenVoid')}',
        note: sub('KitchenVoid'),
        icon: Icons.soup_kitchen_outlined,
        color: SboxColors.warning,
        onTap: () => _quickAction(_ActionFilter.kitchenVoid),
      ),
      ReportKpiItem(
        label: 'Hủy đơn',
        value: '${count('SaleCancel')}',
        note: sub('SaleCancel'),
        icon: Icons.cancel_outlined,
        color: SboxColors.danger,
        onTap: () => _quickAction(_ActionFilter.saleCancel),
      ),
      ReportKpiItem(
        label: 'Trả hàng',
        value: '${count('SaleReturn')}',
        note: sub('SaleReturn'),
        icon: Icons.assignment_return_outlined,
        color: SboxColors.brand500,
        onTap: () => _quickAction(_ActionFilter.saleReturn),
      ),
      ReportKpiItem(
        label: 'Sau tạm tính',
        value: '${after.length}',
        note: after.isEmpty ? 'Không có — tốt' : '${_money.format(amt(after))}đ · cần kiểm soát',
        icon: Icons.policy_outlined,
        color: SboxColors.danger,
        tone: after.isEmpty ? SboxTone.success : SboxTone.danger,
        onTap: () {
          setState(() => _phase = _phase == _BillPhaseFilter.after ? _BillPhaseFilter.all : _BillPhaseFilter.after);
          unawaited(_load());
        },
      ),
    ];
  }

  void _quickAction(_ActionFilter a) {
    setState(() => _action = _action == a ? _ActionFilter.all : a);
    unawaited(_load());
  }

  List<Widget> _charts() {
    if (_items.isEmpty) return const [];
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    final days = <DateTime>[];
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      days.add(d);
    }
    final byDay = <String, Map<DateTime, double>>{
      'KitchenVoid': {for (final d in days) d: 0},
      'SaleCancel': {for (final d in days) d: 0},
      'SaleReturn': {for (final d in days) d: 0},
    };
    final byActor = <String, double>{};
    final actorCnt = <String, int>{};
    final byProduct = <String, double>{};
    final byReason = <String, double>{};
    for (final m in _items) {
      final t = m['actionType']?.toString() ?? '';
      final occ = DateTime.tryParse(m['occurredAt']?.toString() ?? '')?.toLocal();
      final amount = (m['amount'] as num?)?.toDouble() ?? 0;
      if (occ != null) {
        final k = DateTime(occ.year, occ.month, occ.day);
        final series = byDay[t];
        if (series != null && series.containsKey(k)) series[k] = series[k]! + 1;
      }
      final actor = (m['actor'] ?? '').toString().trim();
      if (actor.isNotEmpty) {
        byActor[actor] = (byActor[actor] ?? 0) + amount;
        actorCnt[actor] = (actorCnt[actor] ?? 0) + 1;
      }
      final p = (m['productName'] ?? '').toString().trim();
      if (p.isNotEmpty) byProduct[p] = (byProduct[p] ?? 0) + ((m['qty'] as num?)?.toDouble() ?? 1);
      final r = (m['reason'] ?? '').toString().trim();
      byReason[r.isEmpty ? 'Không ghi lý do' : r] = (byReason[r.isEmpty ? 'Không ghi lý do' : r] ?? 0) + 1;
    }
    return [
      if (days.length > 1 && days.length <= 62)
        SboxChartCard(
          title: 'Số lượt theo ngày',
          wide: true,
          child: SboxBarChart(
            stacked: true,
            valueFormat: (v) => '${SboxFmt.number(v)} lượt',
            axisFormat: (v) => SboxFmt.number(v),
            labels: [for (final d in days) sboxDayLabel(d)],
            series: [
              SboxSeries(name: 'Hủy món bếp', values: [for (final d in days) byDay['KitchenVoid']![d]!], color: SboxColors.warning),
              SboxSeries(name: 'Hủy đơn', values: [for (final d in days) byDay['SaleCancel']![d]!], color: SboxColors.danger),
              SboxSeries(name: 'Trả hàng', values: [for (final d in days) byDay['SaleReturn']![d]!], color: SboxColors.brand500),
            ],
          ),
        ),
      if (byActor.isNotEmpty)
        SboxChartCard(
          title: 'Người hủy / trả nhiều nhất',
          subtitle: 'Theo số tiền',
          child: SboxRankList(
            color: SboxColors.danger,
            valueFormat: (v) => SboxFmt.money(v),
            items: [for (final e in byActor.entries) SboxSlice(e.key, e.value, caption: '${actorCnt[e.key]} lượt')],
          ),
        ),
      if (byProduct.isNotEmpty)
        SboxChartCard(
          title: 'Món / hàng bị hủy nhiều nhất',
          subtitle: 'Theo số lượng',
          child: SboxRankList(
            color: SboxColors.warning,
            valueFormat: (v) => _qty.format(v ?? 0),
            items: [for (final e in byProduct.entries) SboxSlice(e.key, e.value)],
          ),
        ),
      SboxChartCard(
        title: 'Lý do thường gặp',
        child: SboxRankList(
          color: SboxColors.slate500,
          valueFormat: (v) => '${SboxFmt.number(v)} lượt',
          items: [for (final e in byReason.entries) SboxSlice(e.key, e.value)],
        ),
      ),
    ];
  }

  Widget _filters() {
    final spanDays = DateTime(_to.year, _to.month, _to.day).difference(DateTime(_from.year, _from.month, _from.day)).inDays + 1;
    final endsToday = DateUtils.isSameDay(_to, DateTime.now());
    final rangeKey = !endsToday
        ? 'custom'
        : spanDays == 1
            ? '1'
            : spanDays == 7
                ? '7'
                : spanDays == 30
                    ? '30'
                    : 'custom';
    // Một hàng kiểu HRM: tìm · thời gian · thao tác · tạm tính · lọc thêm (người hủy) — không còn nút «Lọc».
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: SboxFilterBar(
        searchHint: 'Mã đơn / bàn / lý do',
        searchController: _searchCtrl,
        onSearch: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), () => unawaited(_load()));
        },
        filters: [
          SboxFilterChip<String>(
            label: 'Thời gian',
            value: rangeKey,
            options: {
              '1': 'Hôm nay',
              '7': '7 ngày',
              '30': '30 ngày',
              'custom': rangeKey == 'custom' ? '${_dayFmt.format(_from)} – ${_dayFmt.format(_to)}' : 'Chọn ngày…',
            },
            onChanged: (v) async {
              if (v != 'custom') return _setRange(int.parse(v));
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: DateTimeRange(start: _from, end: _to),
              );
              if (r == null) return;
              setState(() {
                _from = r.start;
                _to = r.end;
              });
              unawaited(_load());
            },
          ),
          SboxFilterChip<_ActionFilter>(
            label: 'Thao tác',
            value: _action,
            options: const {
              _ActionFilter.all: 'Tất cả',
              _ActionFilter.kitchenVoid: 'Hủy món bếp',
              _ActionFilter.saleCancel: 'Hủy đơn',
              _ActionFilter.saleReturn: 'Trả hàng',
            },
            onChanged: (v) {
              setState(() => _action = v);
              unawaited(_load());
            },
          ),
          SboxFilterChip<_BillPhaseFilter>(
            label: 'Tạm tính',
            value: _phase,
            options: const {
              _BillPhaseFilter.all: 'Trước + sau',
              _BillPhaseFilter.after: 'Chỉ sau tạm tính',
              _BillPhaseFilter.before: 'Chỉ trước tạm tính',
            },
            onChanged: (v) {
              setState(() => _phase = v);
              unawaited(_load());
            },
          ),
          PosMoreFiltersButton(
            activeCount: _actorCtrl.text.trim().isEmpty ? 0 : 1,
            onApply: () => unawaited(_load()),
            onClear: () {
              _actorCtrl.clear();
              unawaited(_load());
            },
            fields: () => [PosFilterField(label: 'Người hủy / trả', controller: _actorCtrl, hint: 'Tên hoặc email nhân viên')],
          ),
        ],
      ),
    );
  }

  Timer? _debounce;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Lịch sử hủy / trả')),
        backgroundColor: Colors.white,
        foregroundColor: SboxColors.text,
        elevation: 0.5,
        actions: [
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _filters(),
            const Divider(height: 1),
            if (_loading)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr(_error!))))
            else ...[
              ReportDashboard(
                storageKey: 'pos_cancel_return',
                subtitle: '${_dayFmt.format(_from)} – ${_dayFmt.format(_to)}${_items.length >= 400 ? ' · 400 bản ghi gần nhất' : ''}',
                kpis: _kpis(),
                charts: _charts(),
              ),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Text(tr('Không có lượt hủy / trả nào trong kỳ'))),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text(tr('Chi tiết (${_items.length})'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                for (final m in _items)
                  Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 6), child: _tile(m)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> m) {
    final action = m['actionType']?.toString();
    final after = m['afterProvisionalBill'] == true;
    final occurred = DateTime.tryParse(m['occurredAt']?.toString() ?? '');
    final amount = (m['amount'] as num?)?.toDouble() ?? 0;
    final qty = (m['qty'] as num?)?.toDouble() ?? 0;
    final product = m['productName']?.toString() ?? '';
    final reason = m['reason']?.toString() ?? '';
    final note = m['detailNote']?.toString() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _actionColor(action).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr(_actionLabel(action)),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _actionColor(action),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: after
                        ? const Color(0xFFFFEDD5)
                        : SboxColors.successSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr(after ? 'Sau tạm tính' : 'Trước tạm tính'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: after
                          ? const Color(0xFFC2410C)
                          : SboxColors.successText,
                    ),
                  ),
                ),
                const Spacer(),
                if (amount > 0)
                  Text(
                    tr('${_money.format(amount)}đ'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr([
                if ((m['orderNo'] ?? '').toString().isNotEmpty) m['orderNo'],
                if ((m['resourceName'] ?? '').toString().isNotEmpty)
                  m['resourceName'],
              ].whereType<Object>().join(' · ')),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (product.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                tr(qty > 0 ? '$product × ${_qty.format(qty)}' : product),
                style: const TextStyle(
                    fontSize: 13, color: PosTheme.textSecondary),
              ),
            ],
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tr('Lý do: $reason'),
                  style: const TextStyle(fontSize: 13)),
            ],
            if (note.isNotEmpty)
              Text(tr('Ghi chú: $note'),
                  style: const TextStyle(
                      fontSize: 12, color: PosTheme.textSecondary)),
            const SizedBox(height: 6),
            Text(
              tr([
                if (occurred != null) _fmt.format(occurred.toLocal()),
                if ((m['actor'] ?? '').toString().isNotEmpty) m['actor'],
                if ((m['deviceName'] ?? '').toString().isNotEmpty)
                  m['deviceName'],
              ].whereType<Object>().join(' · ')),
              style: const TextStyle(
                  fontSize: 11, color: PosTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
