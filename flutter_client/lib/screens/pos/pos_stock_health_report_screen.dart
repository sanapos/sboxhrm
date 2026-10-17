import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/api_datetime.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../utils/pos_report_open.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'pos_reorder_suggestions_screen.dart';

/// Sức khỏe kho: cháy hàng / bán chậm / chết tồn theo tốc độ bán (số ngày tồn còn đủ bán).
class PosStockHealthReportScreen extends StatefulWidget {
  const PosStockHealthReportScreen({super.key});

  @override
  State<PosStockHealthReportScreen> createState() =>
      _PosStockHealthReportScreenState();
}

class _PosStockHealthReportScreenState extends State<PosStockHealthReportScreen> {
  final _pngKey = GlobalKey();
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _qtyFmt = NumberFormat('#,##0.###', 'vi_VN');
  // 30 ngày gần nhất: «Tháng này» vào đầu tháng gần như chưa có bán → mọi hàng thành «chết tồn».
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.last30Days);
  String _mode = 'all';
  /// Đủ bán quá số ngày này (hoặc chưa bán lại quá số ngày này) → «bán chậm»; chưa bán và nhập trước đó → «chết tồn».
  int _idleDays = 60;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosStockHealthReport(
      from: _time.from,
      to: _time.to,
      mode: _mode,
      idleDays: _idleDays,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
        _error = null;
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  static String _statusVi(String? s) => switch (s) {
        'hot' => 'Cháy hàng',
        'slow' => 'Bán chậm',
        'dead' => 'Chết tồn',
        'new' => 'Mới về',
        _ => 'Ổn định',
      };

  static SboxTone _statusTone(String? s) => switch (s) {
        'hot' => SboxTone.danger,
        'slow' => SboxTone.warning,
        'dead' => SboxTone.neutral,
        'new' => SboxTone.brand,
        _ => SboxTone.success,
      };

  List<Map<String, dynamic>> get _items => ((_data?['items'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  String _qty(dynamic v, [dynamic unit]) {
    final u = '${unit ?? ''}'.trim();
    return '${_qtyFmt.format(_n(v))}${u.isEmpty ? '' : ' $u'}';
  }

  String _cover(dynamic v) {
    if (v == null) return '—';
    final d = _n(v);
    if (d >= 999) return '> 999 ngày';
    return '${d < 10 ? d.toStringAsFixed(1) : d.round()} ngày';
  }

  String _date(dynamic raw) {
    final d = parseApiUtcDateTime(raw);
    return d == null ? '—' : _dateFmt.format(d);
  }

  void _setMode(String m) {
    setState(() => _mode = m);
    _load();
  }

  Future<void> _exportExcel() async {
    final items = _items;
    await PosReportExport.excel(
      context: context,
      title: 'Báo cáo sức khỏe kho',
      sheetName: 'Suc khoe kho',
      filePrefix: 'POS_SucKhoeKho',
      periodLabel: _time.exportLabel,
      filterLabel: '${_modeLabels[_mode]} · chậm khi đủ bán ≥ $_idleDays ngày',
      headers: const ['Mã hàng', 'Hàng hóa', 'ĐVT', 'Tồn', 'Bán trong kỳ', 'Bán TB/ngày', 'Đủ bán (ngày)', 'Giá trị tồn',
        'Doanh thu', 'Bán gần nhất', 'Nhập gần nhất', 'Tình trạng'],
      rows: [
        for (final r in items)
          [
            r['productCode'] ?? '',
            r['name'] ?? '',
            r['baseUnitName'] ?? '',
            _n(r['onHandQty']),
            _n(r['qtySold']),
            _n(r['avgDailyQty']),
            r['coverDays'] == null ? '' : _n(r['coverDays']),
            _n(r['stockValue']),
            _n(r['revenue']),
            _date(r['lastSoldAt']),
            _date(r['lastInboundAt']),
            _statusVi(r['status']?.toString()),
          ],
      ],
    );
  }

  static const _modeLabels = {
    'all': 'Cần xử lý',
    'hot': 'Cháy hàng',
    'slow': 'Bán chậm',
    'dead': 'Chết tồn',
    'new': 'Mới về chưa bán',
  };

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final d = _data ?? const <String, dynamic>{};
    final hot = _n(d['hotCount']), slow = _n(d['slowCount']), dead = _n(d['deadCount']), fresh = _n(d['newCount']);
    final total = _n(d['total']).toInt();
    final periodDays = _n(d['periodDays']).toInt();
    final hotDays = _n(d['hotDays']).toInt();

    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Cháy hàng', value: SboxFmt.number(hot), icon: Icons.local_fire_department_outlined, tone: SboxTone.danger,
            note: 'Hết / dưới tối thiểu / đủ bán < ${hotDays > 0 ? hotDays : 7} ngày', onTap: () => _setMode('hot')),
        SboxKpi(label: 'Bán chậm', value: SboxFmt.number(slow), icon: Icons.hourglass_bottom_rounded, tone: SboxTone.warning,
            note: '${SboxFmt.money(_n(d['slowValue']))} · đủ bán ≥ $_idleDays ngày', onTap: () => _setMode('slow')),
        SboxKpi(label: 'Chết tồn', value: SboxFmt.number(dead), icon: Icons.block_outlined, tone: SboxTone.neutral,
            note: '${SboxFmt.money(_n(d['deadValue']))} · không bán trong kỳ', onTap: () => _setMode('dead')),
        SboxKpi(label: 'Mới về chưa bán', value: SboxFmt.number(fresh), icon: Icons.fiber_new_outlined, tone: SboxTone.brand,
            note: 'Nhập trong $_idleDays ngày — chưa tính chết tồn', onTap: () => _setMode('new')),
      ],
      charts: [
        SboxChartCard(
          title: 'Vốn nằm trong kho theo tình trạng',
          child: SboxDonutChart(slices: [
            SboxSlice('Cháy hàng', _n(d['hotValue']), color: SboxColors.danger),
            SboxSlice('Bán chậm', _n(d['slowValue']), color: SboxColors.warning),
            SboxSlice('Chết tồn', _n(d['deadValue']), color: SboxColors.slate500),
            SboxSlice('Mới về', _n(d['newValue']), color: SboxColors.brand500),
          ]),
        ),
        SboxChartCard(
          title: _mode == 'hot' ? 'Sắp hết sớm nhất' : 'Vốn đọng lớn nhất',
          subtitle: _modeLabels[_mode],
          child: SboxRankList(
            color: _mode == 'hot' ? SboxColors.danger : SboxColors.violet,
            valueFormat: _mode == 'hot' ? (v) => '${SboxFmt.number(v)} đã bán' : SboxFmt.money,
            items: [
              for (final r in _mode == 'hot'
                  ? items
                  : ([...items]..sort((a, b) => _n(b['stockValue']).compareTo(_n(a['stockValue'])))))
                SboxSlice(r['name']?.toString() ?? '—', _mode == 'hot' ? _n(r['qtySold']) : _n(r['stockValue']),
                    caption: 'Tồn ${_qty(r['onHandQty'], r['baseUnitName'])} · đủ bán ${_cover(r['coverDays'])}'),
            ],
          ),
        ),
      ],
    );

    final table = SboxCard(
      padding: EdgeInsets.zero,
      child: SboxDataTable<Map<String, dynamic>>(
        rows: items,
        paginate: true,
        pageSize: 30,
        onRowTap: (r) => PosReportOpen.productMenu(context,
            id: '${r['id'] ?? r['productId'] ?? ''}', name: '${r['name'] ?? ''}', from: _time.from, to: _time.to),
        emptyTitle: _mode == 'all' ? 'Kho ổn — không có hàng cần xử lý' : 'Không có hàng trong nhóm này',
        columns: [
          SboxColumn(
            label: 'Hàng hóa',
            primary: true,
            flex: 3,
            minWidth: 220,
            cell: (r) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
              Text(
                [r['productCode'], r['categoryName']].where((x) => '${x ?? ''}'.trim().isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SboxType.smallStyle(SboxColors.textMuted),
              ),
            ]),
          ),
          SboxColumn(label: 'Tồn', numeric: true, minWidth: 90, text: (r) => _qty(r['onHandQty'], r['baseUnitName']),
              sortValue: (r) => _n(r['onHandQty'])),
          SboxColumn(label: 'Bán trong kỳ', numeric: true, minWidth: 100, text: (r) => _qty(r['qtySold']),
              sortValue: (r) => _n(r['qtySold'])),
          SboxColumn(label: 'Đủ bán', numeric: true, minWidth: 100, text: (r) => _cover(r['coverDays']),
              sortValue: (r) => r['coverDays'] == null ? double.infinity : _n(r['coverDays'])),
          SboxColumn(label: 'Giá trị tồn', numeric: true, minWidth: 120, text: (r) => SboxFmt.money(_n(r['stockValue'])),
              sortValue: (r) => _n(r['stockValue'])),
          SboxColumn(label: 'Bán gần nhất', minWidth: 110, hideOnMobile: true, text: (r) => _date(r['lastSoldAt'])),
          SboxColumn(label: 'Nhập gần nhất', minWidth: 110, hideOnMobile: true, text: (r) => _date(r['lastInboundAt'])),
          SboxColumn(
            label: 'Tình trạng',
            minWidth: 110,
            cell: (r) => Align(
              alignment: Alignment.centerLeft,
              child: SboxStatusChip(label: _statusVi('${r['status']}'), tone: _statusTone('${r['status']}')),
            ),
          ),
        ],
      ),
    );

    return PosReportMobileScaffold(
      pngKey: _pngKey,
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_SucKhoeKho',
      )),
      onExportExcel: items.isEmpty ? null : () => unawaited(_exportExcel()),
      title: 'Sức khỏe kho',
      exportModule: 'PosReportStock',
      time: _time,
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading && _data == null
          ? ListView(children: const [
              SizedBox(height: 240, child: Center(child: CircularProgressIndicator(color: PosTheme.kiotBlue))),
            ])
          : _error != null && _data == null
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Center(child: Text(tr(_error!), style: SboxType.bodyStyle(SboxColors.dangerText))),
                  const SizedBox(height: 8),
                  Center(child: SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh, onPressed: _load)),
                ])
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    if (_loading) const LinearProgressIndicator(color: PosTheme.kiotBlue, minHeight: 2),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final e in [
                          ('all', 'Cần xử lý ${(hot + slow + dead).toInt()}'),
                          ('hot', 'Cháy ${hot.toInt()}'),
                          ('slow', 'Chậm ${slow.toInt()}'),
                          ('dead', 'Chết tồn ${dead.toInt()}'),
                          ('new', 'Mới về ${fresh.toInt()}'),
                        ])
                          FilterChip(
                            label: Text(tr(e.$2)),
                            selected: _mode == e.$1,
                            onSelected: (_) => _setMode(e.$1),
                          ),
                        SboxFilterChip<int>(
                          label: 'Chậm khi đủ bán ≥',
                          value: _idleDays,
                          options: const {30: '30 ngày', 60: '60 ngày', 90: '90 ngày', 180: '180 ngày'},
                          onChanged: (v) {
                            setState(() => _idleDays = v);
                            _load();
                          },
                        ),
                        if (_mode == 'hot' && hot > 0)
                          SboxButton.secondary(
                            label: 'Gợi ý nhập hàng',
                            icon: Icons.add_shopping_cart_outlined,
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const PosReorderSuggestionsScreen()),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('Tốc độ bán tính trên ${periodDays > 0 ? periodDays : 30} ngày của kỳ · «đủ bán» = tồn ÷ lượng bán TB mỗi ngày'
                          '${total > items.length ? ' · hiện ${items.length}/$total mặt hàng (Excel cũng giới hạn như vậy)' : ''}'),
                      style: SboxType.smallStyle(SboxColors.textMuted),
                    ),
                    const SizedBox(height: 10),
                    insight,
                    table,
                  ],
                ),
    );
  }
}
