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

/// «Nguyên vật liệu»: mỗi nguyên liệu đã dùng bao nhiêu theo định lượng (cho món nào, tốn bao nhiêu),
/// còn đủ dùng mấy ngày, nhập / hủy trong kỳ, món bán mà chưa khai định lượng — kết luận xanh / vàng / đỏ.
class PosMaterialReportScreen extends StatefulWidget {
  const PosMaterialReportScreen({super.key});

  @override
  State<PosMaterialReportScreen> createState() => _PosMaterialReportScreenState();
}

class _PosMaterialReportScreenState extends State<PosMaterialReportScreen> {
  final _api = ApiService();
  final _pngKey = GlobalKey();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _qty = NumberFormat('#,##0.##', 'vi_VN');
  static final _df = DateFormat('yyyy-MM-dd');
  int _days = 7;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _r;
  String _filter = 'all'; // all / alert / used

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
    final res = await _api.getPosMaterialsReport(
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
  String _q(dynamic v, [String unit = '']) => '${_qty.format(_n(v))}${unit.isEmpty ? '' : ' $unit'}';

  static String _actionLevel(String? l) => switch (l) { 'red' => 'high', 'yellow' => 'medium', _ => 'info' };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Nguyên vật liệu')),
        actions: [
          IconButton(
            tooltip: tr('Xuất PNG'),
            onPressed: _r == null
                ? null
                : () => unawaited(PosReportExport.png(context: context, key: _pngKey, filePrefix: 'POS_NguyenVatLieu')),
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
        title: 'Nguyên vật liệu',
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
      title: 'Nguyên vật liệu',
      sheetName: 'NVL',
      filePrefix: 'POS_NguyenVatLieu',
      periodLabel: _periodLabel,
      headers: const ['Mã', 'Nguyên liệu', 'ĐVT', 'Tồn hiện tại', 'Đã dùng', 'Tiền đã dùng', 'Dùng / ngày', 'Còn đủ (ngày)',
        'Nhập trong kỳ', 'Hủy / thiếu', 'Tình trạng', 'Dùng nhiều cho'],
      rows: [
        for (final m in _maps(_r?['materials']))
          [
            '${m['code'] ?? ''}', '${m['name'] ?? ''}', '${m['unit'] ?? ''}', _n(m['onHand']), _n(m['usedQty']),
            _n(m['usedValue']), _n(m['avgPerDay']), m['daysLeft'] == null ? '' : _n(m['daysLeft']),
            _n(m['receivedQty']), _n(m['wastedQty']), '${m['levelText'] ?? ''}',
            _maps(m['dishes']).map((d) => '${d['name']} (${_q(d['qty'])})').join('; '),
          ],
      ],
      summaryLines: ['${_r?['verdictText'] ?? ''}'],
    );
  }

  List<Widget> _content(Map<String, dynamic> r) {
    final s = Map<String, dynamic>.from(r['summary'] as Map? ?? {});
    final materials = _maps(r['materials']);
    final recs = _maps(r['recommendations']);
    final daily = _maps(r['daily']);
    final topDishes = _maps(r['topDishes']);
    final noRecipe = _maps(r['noRecipeDishes']);
    final red = _n(s['redCount']).toInt();
    final yellow = _n(s['yellowCount']).toInt();
    final shown = materials.where((m) {
      return switch (_filter) {
        'alert' => m['level'] == 'red' || m['level'] == 'yellow',
        'used' => _n(m['usedQty']) > 0,
        _ => true,
      };
    }).toList();
    return [
      PosHealthHero(
        status: r['verdict']?.toString(),
        title: r['verdictText']?.toString() ?? '',
        detail: r['verdictDetail']?.toString(),
        note: 'Số «còn đủ dùng» tính theo mức dùng bình quân của kỳ đang xem — chọn 30 ngày để ước chính xác hơn.',
      ),
      PosHealthKpiGrid(items: greyKpisIfNoData(_n(s['materialCount']) == 0, [
        PosHealthKpi('Hết / sắp hết', '$red loại',
            status: red > 0 ? 'red' : 'green', hint: 'Đã hết hoặc đủ dưới 2 ngày', icon: Icons.warning_amber_rounded),
        PosHealthKpi('Cần nhập trong tuần', '$yellow loại',
            status: yellow > 0 ? 'yellow' : 'green', hint: 'Đủ dưới 5 ngày / dưới tồn tối thiểu', icon: Icons.event_note_outlined),
        PosHealthKpi('Tiền nguyên liệu đã dùng', _m(s['usedValue']),
            hint: '~${_m(s['usedPerDay'])} / ngày · ${_n(s['usedCount'])} loại', icon: Icons.payments_outlined),
        PosHealthKpi('Hủy / kiểm kê thiếu', _m(s['wastedValue']),
            status: _n(s['usedValue']) > 0 && _n(s['wastedValue']) / _n(s['usedValue']) > 0.05 ? 'yellow' : 'green',
            hint: 'Nên dưới 5% tiền đã dùng', icon: Icons.delete_outline),
        PosHealthKpi('Âm kho', '${_n(s['negativeCount'])} loại',
            status: _n(s['negativeCount']) > 0 ? 'yellow' : 'green', hint: 'Cần kiểm kê lại', icon: Icons.exposure_neg_1),
        PosHealthKpi('Món chưa khai định lượng', '${_n(s['noRecipeDishCount'])} món',
            status: _n(s['noRecipeDishCount']) > 0 ? 'yellow' : 'green',
            hint: 'Bán ra không trừ nguyên liệu', icon: Icons.rule_outlined),
      ])),
      PosHealthSection(
        title: 'Việc nên làm',
        subtitle: 'Nhập hàng kịp trước khi hết, chỉnh định lượng / kiểm kê khi số không khớp.',
        children: [
          PosHealthActionList(
            emptyText: 'Nguyên liệu đủ dùng — không có việc gì gấp.',
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
      if (materials.any((m) => m['daysLeft'] != null)) _daysLeftSection(materials),
      if (topDishes.isNotEmpty) _topDishesSection(topDishes),
      if (daily.isNotEmpty) _dailySection(daily),
      PosHealthSection(
        title: 'Từng nguyên liệu (${materials.length})',
        subtitle: 'Đỏ / vàng xếp đầu. Bấm để xem dùng cho món nào.',
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final (v, label) in const [('all', 'Tất cả'), ('alert', 'Cần nhập'), ('used', 'Có dùng')])
                ChoiceChip(
                  label: Text(tr(label)),
                  selected: _filter == v,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = v),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Text(tr('Không có nguyên liệu phù hợp.'), style: const TextStyle(color: SboxColors.slate500)),
          for (final m in shown.take(200)) _materialCard(m),
        ],
      ),
      if (noRecipe.isNotEmpty)
        PosHealthSection(
          title: 'Món bán ra mà chưa khai định lượng',
          subtitle: 'Món pha chế / chế biến nên khai định lượng để trừ đúng nguyên liệu (tồn món đang âm).',
          children: [
            for (final d in noRecipe)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  const Icon(Icons.error_rounded, size: 16, color: PosHealth.yellow),
                  const SizedBox(width: 6),
                  Expanded(child: Text(tr('${d['name']}'), style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text(tr('bán ${_q(d['soldQty'])} · tồn ${_q(d['onHand'])}'),
                      style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
                ]),
              ),
          ],
        ),
      const PosHealthGlossary(entries: [
        ('Định lượng', 'Lượng nguyên liệu cho 1 món (vd 1 ly trà sữa = 30 g bột trà + 100 ml sữa). Bán món là kho tự trừ nguyên liệu.'),
        ('Đã dùng', 'Tổng nguyên liệu bị trừ do bán món trong kỳ, đã cộng lại phần hủy đơn / khách trả.'),
        ('Còn đủ dùng', 'Tồn hiện tại ÷ lượng dùng bình quân mỗi ngày của kỳ đang xem.'),
        ('Hủy / kiểm kê thiếu', 'Nguyên liệu xuất hủy hoặc kiểm kho thấy thiếu — hao hụt, hư hỏng, định lượng khai thiếu.'),
        ('Âm kho', 'Hệ thống trừ nhiều hơn số đã nhập — thường do quên ghi phiếu nhập hoặc định lượng khai thừa.'),
      ]),
    ];
  }

  Widget _daysLeftSection(List<Map<String, dynamic>> materials) {
    final rows = materials.where((m) => m['daysLeft'] != null).take(12).toList();
    const cap = 14.0;
    return PosHealthSection(
      title: 'Còn đủ dùng bao nhiêu ngày',
      subtitle: 'Thanh càng ngắn càng gấp. Đỏ < 2 ngày · vàng < 5 ngày · xanh đủ dùng (thanh tối đa 14 ngày).',
      children: [
        for (final m in rows)
          _bar(
            label: '${m['name']}',
            trailing: '${_q(m['daysLeft'])} ngày · còn ${_q(m['onHand'], '${m['unit'] ?? ''}')}',
            fraction: math.min(cap, _n(m['daysLeft']).toDouble()) / cap,
            color: PosHealth.color(m['level']?.toString()),
          ),
        const SizedBox(height: 4),
        const PosHealthLegend(items: [
          ('Sắp hết', PosHealth.red),
          ('Nên nhập', PosHealth.yellow),
          ('Đủ dùng', PosHealth.green),
        ]),
      ],
    );
  }

  Widget _topDishesSection(List<Map<String, dynamic>> dishes) {
    final maxV = dishes.map((d) => _n(d['value']).toDouble()).fold<double>(1, math.max);
    return PosHealthSection(
      title: 'Món tốn nguyên liệu nhất',
      subtitle: 'Tiền nguyên liệu đã dùng theo món / topping — món đứng đầu nên xem lại định lượng và giá bán.',
      children: [
        for (final d in dishes)
          _bar(
            label: '${d['name']}',
            trailing: _m(d['value']),
            fraction: _n(d['value']).toDouble() / maxV,
            color: PosTheme.kiotBlue,
          ),
      ],
    );
  }

  Widget _dailySection(List<Map<String, dynamic>> daily) {
    final maxV = daily.map((d) => _n(d['value']).toDouble()).fold<double>(1, math.max);
    return PosHealthSection(
      title: 'Tiền nguyên liệu dùng theo ngày',
      subtitle: 'Ngày cột cao = bán nhiều (hoặc định lượng bất thường).',
      children: [
        SizedBox(
          height: 150,
          child: LayoutBuilder(builder: (_, box) {
            final n = daily.length;
            final w = math.max(4.0, math.min(36.0, box.maxWidth / n - 4));
            final labelEvery = (n / 7).ceil();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < n; i++)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: '${daily[i]['day']}: ${_m(daily[i]['value'])}',
                        child: Container(
                          width: w,
                          height: math.max(2, 110 * _n(daily[i]['value']).toDouble() / maxV),
                          decoration: BoxDecoration(
                            color: PosTheme.kiotBlue.withOpacity(0.85),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 16,
                        child: i % labelEvery == 0
                            ? Text(_dayLabel('${daily[i]['day']}'),
                                style: const TextStyle(fontSize: 10, color: SboxColors.slate500))
                            : null,
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

  Widget _bar({required String label, required String trailing, required double fraction, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(tr(label),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Text(tr(trailing), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
          ]),
          const SizedBox(height: 3),
          LayoutBuilder(
            builder: (_, box) => Align(
              alignment: Alignment.centerLeft,
              child: Container(
                height: 10,
                width: math.max(6, box.maxWidth * fraction.clamp(0, 1)),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _materialCard(Map<String, dynamic> m) {
    final level = m['level']?.toString();
    final c = PosHealth.color(level);
    final unit = '${m['unit'] ?? ''}';
    final dishes = _maps(m['dishes']);
    // Material (không phải Container có màu nền): ExpansionTile vẽ hiệu ứng bấm lên Material gần nhất.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
      color: Color.alphaBlend(c.withOpacity(0.04), Colors.white),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.withOpacity(0.4)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          title: Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(tr('${m['name']}'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
              PosHealthChip(status: level, text: '${m['levelText'] ?? ''}'),
            ],
          ),
          subtitle: Text(
            tr('Tồn ${_q(m['onHand'], unit)} · đã dùng ${_q(m['usedQty'], unit)} (${_m(m['usedValue'])})'
                '${m['daysLeft'] == null ? '' : ' · đủ ~${_q(m['daysLeft'])} ngày'}'),
            style: TextStyle(fontSize: 12.5, color: level == 'red' || level == 'yellow' ? c : SboxColors.slate600),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                tr('Dùng ~${_q(m['avgPerDay'], unit)}/ngày · nhập trong kỳ ${_q(m['receivedQty'], unit)}'
                    '${_n(m['wastedQty']) > 0 ? ' · hủy/thiếu ${_q(m['wastedQty'], unit)} (${_m(m['wastedValue'])})' : ''}'
                    '${_n(m['minStock']) > 0 ? ' · tồn tối thiểu ${_q(m['minStock'], unit)}' : ''}'),
                style: const TextStyle(fontSize: 12.5, color: SboxColors.slate700, height: 1.35),
              ),
            ),
            if (dishes.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final d in dishes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(children: [
                    const Icon(Icons.subdirectory_arrow_right, size: 14, color: SboxColors.slate500),
                    const SizedBox(width: 4),
                    Expanded(child: Text(tr('${d['name']}'), style: const TextStyle(fontSize: 12.5))),
                    Text(tr('${_q(d['qty'], unit)} · ${_m(d['value'])}'),
                        style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
                  ]),
                ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}
