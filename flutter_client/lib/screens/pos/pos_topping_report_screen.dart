import '../../widgets/export_file_icon.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/pos_report_export.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_health_widgets.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// «Topping»: bao nhiêu % ly có thêm topping, topping bán chạy, doanh thu / lãi topping, món khách hay thêm —
/// cảnh báo topping bán lỗ / hết hàng, gợi ý bán thêm.
class PosToppingReportScreen extends StatefulWidget {
  const PosToppingReportScreen({super.key});

  @override
  State<PosToppingReportScreen> createState() => _PosToppingReportScreenState();
}

class _PosToppingReportScreenState extends State<PosToppingReportScreen> {
  final _api = ApiService();
  final _pngKey = GlobalKey();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _qty = NumberFormat('#,##0.##', 'vi_VN');
  static final _df = DateFormat('yyyy-MM-dd');
  int _days = 7;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _r;

  static const _palette = [
    Color(0xFF2563EB), Color(0xFF16A34A), Color(0xFFD97706), Color(0xFF9333EA),
    Color(0xFFDB2777), Color(0xFF0891B2), Color(0xFF65A30D), Color(0xFF94A3B8),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final today = DateTime.now();
    final res = await _api.getPosToppingsReport(
      from: _df.format(today.subtract(Duration(days: _days - 1))),
      to: _df.format(today),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _r = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  String get _periodLabel {
    final f = DateFormat('dd/MM/yyyy');
    final today = DateTime.now();
    return _days == 1
        ? 'Hôm nay (${f.format(today)})'
        : '$_days ngày (${f.format(today.subtract(Duration(days: _days - 1)))} – ${f.format(today)})';
  }

  static num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      (v as List? ?? const []).whereType<Map>().map(Map<String, dynamic>.from).toList();

  String _m(dynamic v) => '${_money.format(_n(v))} đ';
  String _q(dynamic v) => _qty.format(_n(v));
  String _pct(dynamic v) => '${_q(v)}%';

  static String _actionLevel(String? l) => switch (l) { 'red' => 'high', 'yellow' => 'medium', _ => 'info' };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Topping')),
        actions: [
          IconButton(
            tooltip: tr('Xuất PNG'),
            onPressed: _r == null
                ? null
                : () => unawaited(PosReportExport.png(context: context, key: _pngKey, filePrefix: 'POS_Topping')),
            icon: const ExportFileIcon(ExportFileKind.png),
          ),
          IconButton(
            tooltip: tr('Xuất Excel'),
            onPressed: _r == null ? null : () => unawaited(_exportExcel()),
            icon: const ExportFileIcon(ExportFileKind.excel),
          ),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PosReportPngCapture(
        pngKey: _pngKey,
        title: 'Topping',
        periodLabel: _periodLabel,
        child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (d, label) in const [(1, 'Hôm nay'), (7, '7 ngày'), (30, '30 ngày')])
                  ChoiceChip(
                    label: Text(tr(label)),
                    selected: _days == d,
                    onSelected: (_) {
                      setState(() => _days = d);
                      unawaited(_load());
                    },
                  ),
                Text(tr(_periodLabel), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              PosHealthHero(status: 'none', title: 'Không xem được báo cáo', detail: _error)
            else if (_r != null)
              ..._content(_r!),
          ],
        ),
      ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    await PosReportExport.excel(
      context: context,
      title: 'Topping',
      sheetName: 'Topping',
      filePrefix: 'POS_Topping',
      periodLabel: _periodLabel,
      headers: const ['Topping', 'Số phần', 'Doanh thu', 'Giá vốn', 'Lãi', '% doanh thu topping', 'Tình trạng'],
      rows: [
        for (final t in _maps(_r?['toppings']))
          [
            '${t['name'] ?? ''}', _n(t['qty']), _n(t['revenue']), _n(t['cost']), _n(t['profit']), _n(t['sharePct']),
            '${t['note'] ?? 'Tốt'}',
          ],
      ],
      summaryLines: [
        '${_r?['verdictText'] ?? ''}',
        for (final d in _maps(_r?['dishes']))
          '${d['name']}: ${_q(d['cupsWithTopping'])}/${_q(d['cups'])} ly có topping (${_pct(d['ratePct'])})',
      ],
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final s = Map<String, dynamic>.from(r['summary'] as Map? ?? {});
    final toppings = _maps(r['toppings']);
    final dishes = _maps(r['dishes']);
    final daily = _maps(r['daily']);
    final recs = _maps(r['recommendations']);
    final cups = _n(s['cups']);
    final withT = _n(s['cupsWithTopping']);
    final bad = toppings.where((t) => t['level'] == 'red').length;
    return [
      PosHealthHero(
        status: r['verdict']?.toString(),
        title: r['verdictText']?.toString() ?? '',
        detail: r['verdictDetail']?.toString(),
        note: 'Chỉ tính món cho chọn topping (đã gắn nhóm topping / bật «cho chọn topping»). Đã trừ hàng khách trả.',
      ),
      PosHealthKpiGrid(items: greyKpisIfNoData(cups <= 0, [
        PosHealthKpi('Ly có topping', _pct(s['ratePct']),
            status: s['rateLevel']?.toString(),
            hint: '${_q(withT)} / ${_q(cups)} ly · tốt khi từ 30%', icon: Icons.local_drink_outlined),
        PosHealthKpi('Doanh thu topping', _m(s['toppingRevenue']),
            hint: '${_q(s['portions'])} phần · ≈${_m(s['revenuePerCup'])} / ly', icon: Icons.payments_outlined),
        PosHealthKpi('Lãi topping', _m(s['toppingProfit']),
            status: _n(s['toppingRevenue']) <= 0
                ? 'none'
                : _n(s['marginPct']) >= 50 ? 'green' : _n(s['marginPct']) >= 30 ? 'yellow' : 'red',
            hint: 'Biên lãi ${_pct(s['marginPct'])} · nên từ 50%', icon: Icons.trending_up),
        PosHealthKpi('Topping / ly có thêm', _q(s['avgPerCup']),
            hint: 'Số phần topping bình quân', icon: Icons.add_circle_outline),
        PosHealthKpi('Topping cần xử lý', '$bad loại',
            status: bad > 0 ? 'red' : 'green', hint: 'Bán lỗ / hết hàng', icon: Icons.report_gmailerrorred),
        PosHealthKpi('Nhóm topping', '${_n(s['groupCount'])} nhóm',
            hint: '${_n(s['toppingKinds'])} loại đã bán', icon: Icons.category_outlined),
      ])),
      PosHealthSection(
        title: 'Việc nên làm',
        subtitle: 'Sửa topping bán lỗ / hết hàng trước, rồi tăng tỷ lệ ly có topping.',
        children: [
          PosHealthActionList(
            emptyText: 'Topping đang bán tốt — không có việc gì gấp.',
            items: [
              for (final x in recs)
                PosHealthAction(
                  level: _actionLevel(x['level']?.toString()),
                  title: x['title']?.toString() ?? '',
                  howTo: x['detail']?.toString(),
                ),
            ],
          ),
        ],
      ),
      if (cups > 0)
        PosHealthSection(
          title: 'Bao nhiêu ly có thêm topping',
          subtitle: 'Xanh = ly có topping, xám = ly không thêm.',
          children: [
            PosHealthSegmentBar(
              unit: 'ly',
              height: 20,
              segments: [
                (label: 'Có topping', value: withT.round(), color: PosHealth.green),
                (label: 'Không thêm', value: (cups - withT).round(), color: SboxColors.slate300),
              ],
            ),
          ],
        ),
      if (toppings.isNotEmpty) _toppingShareSection(toppings),
      if (toppings.isNotEmpty) _toppingTable(toppings),
      if (dishes.isNotEmpty) _dishSection(dishes),
      if (daily.length > 1) _dailySection(daily),
      const PosHealthGlossary(entries: [
        ('Ly có topping', 'Số ly (phần món) khách có thêm ít nhất 1 topping ÷ tổng số ly của các món cho chọn topping.'),
        ('Doanh thu topping', 'Tiền topping thu được (đã trừ giảm giá đơn, hàng khách trả).'),
        ('Lãi topping', 'Doanh thu topping − giá vốn topping (giá nhập hoặc nguyên liệu theo định lượng).'),
        ('Bán lỗ', 'Giá vốn cao hơn giá bán thêm — tăng giá topping hoặc giảm định lượng.'),
      ]),
    ];
  }

  Widget _toppingShareSection(List<Map<String, dynamic>> toppings) {
    final top = toppings.take(7).toList();
    final rest = toppings.skip(7).fold<num>(0, (a, t) => a + _n(t['revenue']));
    final segments = [
      for (var i = 0; i < top.length; i++)
        (label: '${top[i]['name']}', value: (_n(top[i]['revenue']) / 1000).round(), color: _palette[i % 7]),
      if (rest > 0) (label: 'Khác', value: (rest / 1000).round(), color: _palette[7]),
    ];
    return PosHealthSection(
      title: 'Topping bán chạy',
      subtitle: 'Phần màu càng dài càng mang về nhiều tiền. Topping ít bán có thể bỏ bớt cho gọn.',
      children: [PosHealthSegmentBar(segments: segments, unit: 'nghìn đ', height: 20)],
    );
  }

  Widget _toppingTable(List<Map<String, dynamic>> toppings) {
    final maxQ = toppings.map((t) => _n(t['qty']).toDouble()).fold<double>(1, math.max);
    return PosHealthSection(
      title: 'Từng topping (${toppings.length})',
      subtitle: 'Thanh = số phần bán. Đỏ = bán lỗ / hết hàng · vàng = lãi thấp / chưa có giá vốn.',
      children: [
        for (final t in toppings)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(tr('${t['name']}'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    if (t['level'] != 'green')
                      PosHealthChip(status: t['level']?.toString(), text: '${t['note'] ?? ''}'),
                  ],
                ),
                const SizedBox(height: 3),
                LayoutBuilder(
                  builder: (_, box) => Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      height: 10,
                      width: math.max(6, box.maxWidth * _n(t['qty']).toDouble() / maxQ),
                      decoration: BoxDecoration(
                        color: PosHealth.color(t['level']?.toString()),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr('${_q(t['qty'])} phần · thu ${_m(t['revenue'])} · vốn ${_m(t['cost'])} · lãi ${_m(t['profit'])}'
                      ' · ${_pct(t['sharePct'])} doanh thu topping'
                      '${t['tracksStock'] == true ? ' · tồn ${_q(t['onHand'])}' : ''}'),
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dishSection(List<Map<String, dynamic>> dishes) {
    return PosHealthSection(
      title: 'Theo món',
      subtitle: 'Món bán nhiều mà ít ai thêm topping = cơ hội mời khách. Màu theo tỷ lệ: xanh ≥ 30%, vàng 15–30%, đỏ < 15%.',
      children: [
        for (final d in dishes.take(15))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(tr('${d['name']}'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Text(tr('${_q(d['cupsWithTopping'])}/${_q(d['cups'])} ly · ${_pct(d['ratePct'])}'),
                      style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
                ]),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (_n(d['ratePct']) / 100).clamp(0, 1).toDouble(),
                    minHeight: 10,
                    backgroundColor: SboxColors.slate200,
                    color: PosHealth.color(_rateLevel(_n(d['ratePct']))),
                  ),
                ),
                if (_n(d['toppingRevenue']) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      tr('Topping thu ${_m(d['toppingRevenue'])} · ${_q(d['toppingsPerCup'])} phần / ly có thêm'),
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static String _rateLevel(num rate) => rate >= 30 ? 'green' : rate >= 15 ? 'yellow' : 'red';

  Widget _dailySection(List<Map<String, dynamic>> daily) {
    return PosHealthSection(
      title: 'Tỷ lệ ly có topping theo ngày',
      subtitle: 'Cột = % ly có topping trong ngày (vạch xanh 30% là mức tốt).',
      children: [
        SizedBox(
          height: 160,
          child: LayoutBuilder(builder: (_, box) {
            final n = daily.length;
            final w = math.max(4.0, math.min(36.0, box.maxWidth / n - 4));
            final labelEvery = (n / 7).ceil();
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20 + 120 * 0.3,
                  child: Container(height: 1, color: PosHealth.green.withOpacity(0.6)),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < n; i++)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Tooltip(
                            message: '${daily[i]['day']}: ${_pct(daily[i]['ratePct'])} · ${_m(daily[i]['revenue'])}',
                            child: Container(
                              width: w,
                              height: math.max(2, 120 * (_n(daily[i]['ratePct']) / 100).clamp(0, 1).toDouble()),
                              decoration: BoxDecoration(
                                color: PosHealth.color(_rateLevel(_n(daily[i]['ratePct']))),
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 20,
                            child: i % labelEvery == 0
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(_dayLabel('${daily[i]['day']}'),
                                        style: const TextStyle(fontSize: 10, color: SboxColors.slate500)),
                                  )
                                : null,
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            );
          }),
        ),
      ],
    );
  }

  static String _dayLabel(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}' : iso;
  }
}
