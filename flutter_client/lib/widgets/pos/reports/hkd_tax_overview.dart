import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../../theme/sbox_tokens.dart';
import 'pos_health_widgets.dart';

/// Số tiền dễ đọc cho người không chuyên: «1,5 tỷ», «640 triệu», «850.000 đ» (cách «đ» như các báo cáo khác).
String hkdMoneyShort(num? v) {
  final x = (v ?? 0).toDouble();
  final a = x.abs();
  final sign = x < 0 ? '-' : '';
  if (a >= 1e9) return '$sign${NumberFormat('#,##0.##', 'vi_VN').format(a / 1e9)} tỷ';
  if (a >= 1e6) return '$sign${NumberFormat('#,##0.#', 'vi_VN').format(a / 1e6)} triệu';
  return '$sign${NumberFormat('#,##0', 'vi_VN').format(a)} đ';
}

String _groupLabel(int g) => switch (g) {
      1 => 'Nhóm 1 · dưới 1 tỷ',
      3 => 'Nhóm 3 · trên 3 tỷ',
      _ => 'Nhóm 2 · 1–3 tỷ',
    };

num _n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

/// Tổng quan thuế hộ kinh doanh (dữ liệu từ /api/hkd/overview): kết luận màu, thanh doanh thu so với ngưỡng,
/// chỉ số, doanh thu theo tháng (tất cả / đã xuất HĐ), việc nên làm, tỷ lệ theo ngành, giải thích từ ngữ.
class HkdTaxOverview extends StatelessWidget {
  const HkdTaxOverview({
    super.key,
    required this.data,
    required this.basis,
    required this.onBasisChanged,
    this.onPickPreset,
  });

  final Map<String, dynamic> data;

  /// `all` | `invoice`.
  final String basis;
  final ValueChanged<String> onBasisChanged;

  /// Bấm 1 ngành gợi ý → điền tỷ lệ GTGT / TNCN vào hồ sơ. null = chỉ xem.
  final void Function(String industry, double vat, double pit)? onPickPreset;

  @override
  Widget build(BuildContext context) {
    final year = _n(data['year']).toInt();
    final isCurrent = data['isCurrentYear'] == true;
    final ytd = _n(data['ytd']);
    final estimate = _n(data['annualEstimate']);
    final suggested = _n(data['suggestedGroup']).toInt();
    final configured = _n(data['configuredGroup']).toInt();
    final coverage = data['invoiceCoveragePct'] as num?;
    final tax = Map<String, dynamic>.from(data['tax'] as Map? ?? const {});
    final quarter = Map<String, dynamic>.from(data['quarter'] as Map? ?? const {});
    final actions = [for (final a in (data['actions'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
    final presets = [for (final p in (data['ratePresets'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)];
    final vatPct = _n(data['vatPercent']);
    final pitPct = _n(data['pitPercent']);
    final byInvoice = basis == 'invoice';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(tr('Tính doanh thu theo:'), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
            for (final (id, label) in const [('all', 'Tất cả đơn bán'), ('invoice', 'Hóa đơn VAT đã xuất')])
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                label: Text(tr(label), style: const TextStyle(fontSize: 12)),
                selected: basis == id,
                onSelected: (_) => onBasisChanged(id),
              ),
          ]),
        ),
        PosHealthHero(
          status: data['verdict']?.toString(),
          title: data['verdictText']?.toString() ?? '',
          detail: data['verdictDetail']?.toString(),
          note: 'Từ 2026: doanh thu dưới 1 tỷ/năm không phải nộp thuế GTGT, TNCN (trước đây 500 triệu). '
              'Số thuế là ước tính để chuẩn bị tiền — số chính thức theo tờ khai với chi cục thuế.',
        ),
        PosHealthSection(
          title: 'Doanh thu năm $year so với ngưỡng thuế',
          subtitle: byInvoice
              ? 'Chỉ tính đơn đã xuất hóa đơn điện tử, theo ngày lập hóa đơn.'
              : 'Tính mọi đơn bán đã hoàn thành (gồm VAT, phụ thu, phí giao hàng), trừ hàng trả lại.',
          children: [
            HkdThresholdBar(
              ytd: ytd.toDouble(),
              estimate: isCurrent ? estimate.toDouble() : null,
              exemptBelow: _n(data['exemptBelow'] ?? 1e9).toDouble(),
              incomeAbove: _n(data['incomeMethodAbove'] ?? 3e9).toDouble(),
            ),
          ],
        ),
        PosHealthKpiGrid(items: [
          PosHealthKpi(isCurrent ? 'Đã bán từ đầu năm' : 'Doanh thu cả năm', hkdMoneyShort(ytd),
              hint: 'Năm trước: ${hkdMoneyShort(data['priorYear'] as num?)}', icon: Icons.storefront_outlined),
          if (isCurrent)
            PosHealthKpi('Dự kiến cả năm', hkdMoneyShort(estimate),
                hint: 'Theo nhịp bán ${_n(data['daysElapsed'])} ngày qua', icon: Icons.trending_up),
          PosHealthKpi('Nhóm nên khai', _groupLabel(suggested),
              status: suggested == configured ? 'green' : (suggested > configured ? 'red' : 'yellow'),
              hint: suggested == configured ? 'Khớp hồ sơ' : 'Hồ sơ đang khai: ${_groupLabel(configured)}',
              icon: Icons.fact_check_outlined),
          PosHealthKpi(isCurrent ? 'Thuế ước tính từ đầu năm' : 'Thuế ước tính cả năm',
              suggested == 1 ? '0 đ' : hkdMoneyShort(tax['total'] as num?),
              status: suggested >= 2 && vatPct <= 0 && pitPct <= 0 ? 'red' : null,
              hint: suggested == 1
                  ? 'Dưới ngưỡng — chưa phải nộp'
                  : suggested == 3
                      ? 'GTGT $vatPct% · TNCN tính trên thu nhập (sổ S2c)'
                      : 'GTGT $vatPct% + TNCN $pitPct% doanh thu',
              icon: Icons.request_quote_outlined),
          PosHealthKpi('Quý ${_n(quarter['number'])}: doanh thu / thuế',
              '${hkdMoneyShort(quarter['revenue'] as num?)} / ${suggested == 1 ? '0 đ' : hkdMoneyShort(quarter['total'] as num?)}',
              hint: 'Hộ nộp theo quý: tờ khai hạn ngày cuối tháng đầu quý sau', icon: Icons.event_note_outlined),
          PosHealthKpi('Doanh thu đã xuất hóa đơn', coverage == null ? '—' : '${NumberFormat('#,##0.#', 'vi_VN').format(coverage)}%',
              status: coverage == null || suggested == 1 ? null : PosHealth.level(100 - coverage, 5, 20),
              hint: '${hkdMoneyShort(data['ytdInvoiced'] as num?)} / ${hkdMoneyShort(data['ytdAll'] as num?)}',
              icon: Icons.receipt_long_outlined),
        ]),
        PosHealthSection(
          title: 'Việc nên làm',
          subtitle: 'Việc «Làm ngay» có thể dẫn tới truy thu, phạt — nên xử lý trước kỳ kê khai.',
          children: [
            PosHealthActionList(
              emptyText: 'Không có việc gì cần làm — hồ sơ thuế đang khớp doanh thu.',
              items: [
                for (final a in actions)
                  PosHealthAction(
                    level: a['level']?.toString() ?? 'info',
                    title: a['title']?.toString() ?? '',
                    detail: a['detail']?.toString(),
                    howTo: a['howTo']?.toString(),
                  ),
              ],
            ),
          ],
        ),
        HkdMonthlyChart(months: [for (final m in (data['months'] as List? ?? const [])) Map<String, dynamic>.from(m as Map)]),
        if (presets.isNotEmpty)
          PosHealthExpandable(
            title: 'Tỷ lệ % thuế theo ngành nghề',
            subtitle: onPickPreset == null
                ? 'Áp dụng cho hộ doanh thu 1–3 tỷ/năm'
                : 'Bấm ngành của bạn để điền tỷ lệ vào hồ sơ (nhớ bấm «Lưu hồ sơ»)',
            icon: Icons.percent,
            children: [
              for (final p in presets)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(p['industry']?.toString() ?? '')),
                  subtitle: Text(tr('GTGT ${_n(p['vat'])}% · TNCN ${_n(p['pit'])}% · cộng ${_n(p['vat']) + _n(p['pit'])}% doanh thu')),
                  trailing: onPickPreset == null ? null : const Icon(Icons.edit_note, color: SboxColors.slate500),
                  onTap: onPickPreset == null
                      ? null
                      : () => onPickPreset!(p['industry']?.toString() ?? '', _n(p['vat']).toDouble(), _n(p['pit']).toDouble()),
                ),
            ],
          ),
        const PosHealthGlossary(entries: [
          ('Doanh thu tính thuế', 'Tổng tiền khách trả (gồm VAT, phụ thu, phí giao hàng), trừ hàng bị trả lại.'),
          ('Nhóm 1 — dưới 1 tỷ', 'Không phải nộp thuế GTGT, TNCN. Chỉ cần ghi sổ doanh thu S1a-HKD.'),
          ('Nhóm 2 — 1 đến 3 tỷ', 'Nộp GTGT và TNCN = doanh thu × tỷ lệ % của ngành. Sổ S2a-HKD, S2e-HKD.'),
          ('Nhóm 3 — trên 3 tỷ', 'GTGT theo % doanh thu; TNCN tính trên thu nhập = doanh thu trừ chi phí. Sổ S2b đến S2e.'),
          ('GTGT / TNCN', 'Thuế giá trị gia tăng / thuế thu nhập cá nhân của chủ hộ.'),
          ('Hóa đơn VAT đã xuất', 'Hóa đơn điện tử đã gửi cơ quan thuế. Hộ doanh thu từ 1 tỷ phải dùng hóa đơn điện tử từ máy tính tiền.'),
        ]),
      ],
    );
  }
}

/// Thanh ngang: vùng xanh (dưới 1 tỷ) / vàng (1–3 tỷ) / đỏ (trên 3 tỷ), phần đã bán tô đậm, vạch «dự kiến cả năm».
class HkdThresholdBar extends StatelessWidget {
  const HkdThresholdBar({
    super.key,
    required this.ytd,
    required this.exemptBelow,
    required this.incomeAbove,
    this.estimate,
  });

  final double ytd;
  final double? estimate;
  final double exemptBelow;
  final double incomeAbove;

  Color _zone(double v) => v < exemptBelow ? PosHealth.green : (v <= incomeAbove ? PosHealth.yellow : PosHealth.red);

  @override
  Widget build(BuildContext context) {
    final maxV = math.max(incomeAbove * 1.2, math.max(ytd, estimate ?? 0) * 1.08);
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      double x(double v) => (v / maxV).clamp(0.0, 1.0) * w;
      const barTop = 22.0;
      const barH = 18.0;
      final est = estimate;
      return SizedBox(
        height: 86,
        child: Stack(clipBehavior: Clip.none, children: [
          // Vùng ngưỡng (nhạt).
          Positioned(
            left: 0,
            top: barTop,
            width: w,
            height: barH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(barH / 2),
              child: Row(children: [
                SizedBox(width: x(exemptBelow), child: Container(color: PosHealth.green.withValues(alpha: 0.15))),
                SizedBox(width: x(incomeAbove) - x(exemptBelow), child: Container(color: PosHealth.yellow.withValues(alpha: 0.15))),
                Expanded(child: Container(color: PosHealth.red.withValues(alpha: 0.13))),
              ]),
            ),
          ),
          // Đã bán.
          Positioned(
            left: 0,
            top: barTop,
            width: math.max(x(ytd), barH),
            height: barH,
            child: Container(
              decoration: BoxDecoration(color: _zone(ytd), borderRadius: BorderRadius.circular(barH / 2)),
            ),
          ),
          // Mốc ngưỡng.
          for (final (v, label) in [(exemptBelow, '1 tỷ'), (incomeAbove, '3 tỷ')]) ...[
            Positioned(left: x(v) - 1, top: barTop - 4, width: 2, height: barH + 8, child: Container(color: SboxColors.slate500)),
            Positioned(
              left: x(v) - 30,
              top: barTop + barH + 6,
              width: 60,
              child: Text(tr(label),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SboxColors.slate600)),
            ),
          ],
          // Dự kiến cả năm.
          if (est != null && est > ytd)
            Positioned(
              left: x(est) - 1.5,
              top: barTop - 2,
              width: 3,
              height: barH + 4,
              child: Container(color: _zone(est)),
            ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${tr('Đã bán')} ', style: const TextStyle(color: SboxColors.slate600)),
                TextSpan(text: hkdMoneyShort(ytd), style: TextStyle(fontWeight: FontWeight.w800, color: _zone(ytd))),
                if (est != null && est > ytd) ...[
                  TextSpan(text: '  ·  ${tr('dự kiến cả năm')} ', style: const TextStyle(color: SboxColors.slate600)),
                  TextSpan(text: hkdMoneyShort(est), style: TextStyle(fontWeight: FontWeight.w800, color: _zone(est))),
                ],
              ]),
              style: const TextStyle(fontSize: 12.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: barTop + barH + 24,
            child: const PosHealthLegend(items: [
              ('Dưới 1 tỷ: không nộp thuế', PosHealth.green),
              ('1–3 tỷ: thuế % doanh thu', PosHealth.yellow),
              ('Trên 3 tỷ: thuế trên thu nhập', PosHealth.red),
            ]),
          ),
        ]),
      );
    });
  }
}

/// Doanh thu 12 tháng: cột nhạt = tất cả đơn bán, cột đậm = đã xuất hóa đơn.
class HkdMonthlyChart extends StatelessWidget {
  const HkdMonthlyChart({super.key, required this.months});

  final List<Map<String, dynamic>> months;

  @override
  Widget build(BuildContext context) {
    final maxV = months.fold<double>(0, (a, m) => math.max(a, math.max(_n(m['all']).toDouble(), _n(m['invoiced']).toDouble())));
    return PosHealthSection(
      title: 'Doanh thu theo tháng',
      subtitle: 'Cột xám = tất cả đơn bán, cột xanh = phần đã xuất hóa đơn. Hai cột chênh nhiều = còn nhiều đơn chưa xuất hóa đơn.',
      children: [
        const PosHealthLegend(items: [('Tất cả đơn bán', SboxColors.slate300), ('Đã xuất hóa đơn', SboxColors.brand500)]),
        const SizedBox(height: 10),
        if (maxV <= 0)
          Text(tr('Chưa có doanh thu trong năm.'), style: const TextStyle(color: SboxColors.slate500))
        else
          SizedBox(
            height: 190,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                minY: 0,
                maxY: maxV * 1.15,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFE8ECF0), strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (g, _, rod, i) => BarTooltipItem(
                      'T${g.x + 1} · ${i == 0 ? tr('tất cả') : tr('đã xuất HĐ')}\n${hkdMoneyShort(rod.toY)}',
                      const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (v, meta) => v == meta.max
                          ? const SizedBox.shrink()
                          : Text(hkdMoneyShort(v), style: const TextStyle(fontSize: 9, color: SboxColors.slate500)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 18,
                      getTitlesWidget: (v, _) => Text('T${v.toInt() + 1}',
                          style: const TextStyle(fontSize: 10, color: SboxColors.slate500)),
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                barGroups: [
                  for (var i = 0; i < months.length; i++)
                    BarChartGroupData(x: i, barsSpace: 2, barRods: [
                      BarChartRodData(
                        toY: _n(months[i]['all']).toDouble(),
                        color: SboxColors.slate300,
                        width: 7,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                      BarChartRodData(
                        toY: _n(months[i]['invoiced']).toDouble(),
                        color: SboxColors.brand500,
                        width: 7,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                      ),
                    ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
