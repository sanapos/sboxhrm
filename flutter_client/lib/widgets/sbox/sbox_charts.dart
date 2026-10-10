import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';

/// SBOX Design — biểu đồ dùng chung cho Tổng quan & Báo cáo.
/// Quy tắc: tối đa 5 màu/biểu đồ, trục số rút gọn (tr / tỷ), chạm để xem số đầy đủ.

// ─── Định dạng số ──────────────────────────────────────────────────

abstract final class SboxFmt {
  static final _int = NumberFormat('#,##0', 'vi_VN');
  static final _dec1 = NumberFormat('#,##0.#', 'vi_VN');

  /// 12.500.000 ₫
  static String money(num? v) => '${_int.format(v ?? 0)} ₫';

  /// 12.500.000
  static String number(num? v) => _int.format(v ?? 0);

  /// Một chữ số thập phân khi cần (2,5 ngày; 1,5 giờ) — [number] làm tròn số nguyên.
  static String decimal(num? v) => _dec1.format(v ?? 0);

  /// Rút gọn cho trục / thẻ: 950k · 12,5 tr · 1,2 tỷ.
  static String compact(num? v) {
    final x = (v ?? 0).toDouble();
    final a = x.abs();
    final sign = x < 0 ? '-' : '';
    if (a >= 1e9) return '$sign${_dec1.format(a / 1e9)} tỷ';
    if (a >= 1e6) return '$sign${_dec1.format(a / 1e6)} tr';
    if (a >= 1e3) return '$sign${_int.format(a / 1e3)}k';
    return '$sign${_dec1.format(a)}';
  }

  /// 12,5%
  static String pct(num? v) => '${_dec1.format(v ?? 0)}%';
}

/// Bảng màu chuỗi dữ liệu (thứ tự dùng cố định để các báo cáo đồng nhất).
abstract final class SboxChartColors {
  static const series = <Color>[
    SboxColors.brand500,
    SboxColors.success,
    SboxColors.warning,
    SboxColors.violet,
    SboxColors.danger,
    SboxColors.slate400,
    SboxColors.brand300,
  ];
  static Color at(int i) => series[i % series.length];
  static const grid = Color(0xFFEDF1F5);
  static const axis = SboxColors.slate500;
  static const tooltipBg = SboxColors.slate900;
}

/// Một chuỗi số liệu cho biểu đồ cột / đường.
class SboxSeries {
  const SboxSeries({required this.name, required this.values, this.color});
  final String name;
  final List<double> values;
  final Color? color;
}

/// Một phần cho biểu đồ tròn / danh sách xếp hạng.
class SboxSlice {
  const SboxSlice(this.label, this.value, {this.color, this.caption});
  final String label;
  final double value;
  final Color? color;
  /// Chữ phụ bên phải (vd «12 đơn»).
  final String? caption;
}

typedef SboxValueFormat = String Function(double v);

String _defaultFmt(double v) => SboxFmt.compact(v);

// ─── Chú thích ─────────────────────────────────────────────────────

class SboxLegend extends StatelessWidget {
  const SboxLegend({super.key, required this.items});
  final List<({String label, Color color})> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: SboxSpace.md, runSpacing: SboxSpace.xs, children: [
      for (final it in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: it.color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(tr(it.label), style: SboxType.captionStyle(SboxColors.textSecondary)),
        ]),
    ]);
  }
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.height});
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.insert_chart_outlined_rounded, size: 32, color: SboxColors.slate300),
            const SizedBox(height: SboxSpace.xs),
            Text(tr('Chưa có dữ liệu trong kỳ'), style: SboxType.smallStyle(SboxColors.textMuted)),
          ]),
        ),
      );
}

double _niceMax(double v) {
  if (v <= 0) return 1;
  final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
  final f = v / exp;
  final nf = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 2.5 ? 2.5 : (f <= 5 ? 5 : 10)));
  return nf * exp;
}

/// Nhãn trục X: tự thưa bớt khi quá nhiều điểm.
Widget _bottomLabel(List<String> labels, double v, {required int maxLabels}) {
  final i = v.round();
  if ((v - i).abs() > 0.01 || i < 0 || i >= labels.length) return const SizedBox.shrink();
  final step = math.max(1, (labels.length / maxLabels).ceil());
  // Nhãn cuối chỉ ép hiện khi không sát nhãn trước (tránh hai nhãn đè nhau).
  final lastFar = i == labels.length - 1 && (labels.length - 1) % step >= (step / 2).ceil();
  if (i % step != 0 && !lastFar) return const SizedBox.shrink();
  // Tên dài (tên hàng) không tràn sang cột bên cạnh: giới hạn trong ô, cắt «…», di chuột xem đủ.
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Tooltip(
      message: labels[i],
      child: SizedBox(
        width: 54.0 * step,
        child: Text(labels[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: SboxChartColors.axis, height: 1)),
      ),
    ),
  );
}

FlTitlesData _titles({
  required List<String> labels,
  required SboxValueFormat axisFormat,
  required int maxLabels,
  double? interval,
}) =>
    FlTitlesData(
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          interval: interval,
          getTitlesWidget: (v, meta) {
            if (v == meta.max && meta.max != meta.min && v != 0 && interval == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(axisFormat(v),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, color: SboxChartColors.axis, height: 1)),
            );
          },
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: 1,
          getTitlesWidget: (v, _) => _bottomLabel(labels, v, maxLabels: maxLabels),
        ),
      ),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    );

FlGridData get _grid => FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => const FlLine(color: SboxChartColors.grid, strokeWidth: 1),
    );

const _tooltipText = TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4);
const _tooltipLabel = TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w500, height: 1.4);

// ─── Biểu đồ cột (nhóm hoặc chồng) ─────────────────────────────────

class SboxBarChart extends StatelessWidget {
  const SboxBarChart({
    super.key,
    required this.labels,
    required this.series,
    this.stacked = false,
    this.height = 240,
    this.valueFormat = SboxFmt.money,
    this.axisFormat = _defaultFmt,
    this.showLegend = true,
    this.maxLabels = 10,
  });

  final List<String> labels;
  final List<SboxSeries> series;
  final bool stacked;
  final double height;
  /// Định dạng số trong tooltip.
  final String Function(num? v) valueFormat;
  final SboxValueFormat axisFormat;
  final bool showLegend;
  final int maxLabels;

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    final hasData = n > 0 && series.any((s) => s.values.any((v) => v != 0));
    if (!hasData) return _ChartEmpty(height: height);
    Color colorOf(int si) => series[si].color ?? SboxChartColors.at(si);
    double at(SboxSeries s, int i) => i < s.values.length ? s.values[i] : 0;

    var maxY = 0.0;
    var minY = 0.0;
    for (var i = 0; i < n; i++) {
      if (stacked) {
        var pos = 0.0, neg = 0.0;
        for (final s in series) {
          final v = at(s, i);
          v >= 0 ? pos += v : neg += v;
        }
        maxY = math.max(maxY, pos);
        minY = math.min(minY, neg);
      } else {
        for (final s in series) {
          maxY = math.max(maxY, at(s, i));
          minY = math.min(minY, at(s, i));
        }
      }
    }
    final top = _niceMax(maxY);
    final bottom = minY < 0 ? -_niceMax(-minY) : 0.0;

    return LayoutBuilder(builder: (context, cons) {
      final groupW = (cons.maxWidth - 60) / math.max(1, n);
      final rodsPerGroup = stacked ? 1 : series.length;
      final rodW = (groupW * 0.62 / rodsPerGroup).clamp(3.0, 28.0);
      final chart = SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: top,
            minY: bottom,
            alignment: BarChartAlignment.spaceAround,
            gridData: _grid,
            borderData: FlBorderData(show: false),
            titlesData: _titles(labels: labels, axisFormat: axisFormat, maxLabels: math.max(3, (cons.maxWidth / 56).floor()).clamp(3, maxLabels)),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => SboxChartColors.tooltipBg,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, gi, rod, ri) {
                  final i = group.x;
                  if (stacked) {
                    final lines = <TextSpan>[];
                    for (var si = 0; si < series.length; si++) {
                      lines.add(TextSpan(text: '\n${tr(series[si].name)}: ', style: _tooltipLabel));
                      lines.add(TextSpan(text: valueFormat(at(series[si], i)), style: _tooltipText));
                    }
                    return BarTooltipItem(labels[i], _tooltipLabel, children: lines, textAlign: TextAlign.left);
                  }
                  return BarTooltipItem('${labels[i]}\n', _tooltipLabel,
                      children: [
                        if (series.length > 1) TextSpan(text: '${tr(series[ri].name)}: ', style: _tooltipLabel),
                        TextSpan(text: valueFormat(rod.toY), style: _tooltipText),
                      ],
                      textAlign: TextAlign.left);
                },
              ),
            ),
            barGroups: [
              for (var i = 0; i < n; i++)
                BarChartGroupData(
                  x: i,
                  barsSpace: 2,
                  barRods: stacked
                      ? [_stackRod(i, at, colorOf, rodW)]
                      : [
                          for (var si = 0; si < series.length; si++)
                            BarChartRodData(
                              toY: at(series[si], i),
                              color: at(series[si], i) < 0 ? SboxColors.danger : colorOf(si),
                              width: rodW,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(at(series[si], i) >= 0 ? 4 : 0),
                                bottom: Radius.circular(at(series[si], i) < 0 ? 4 : 0),
                              ),
                            ),
                        ],
                ),
            ],
          ),
        ),
      );
      if (!showLegend || series.length < 2) return chart;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SboxLegend(items: [for (var si = 0; si < series.length; si++) (label: series[si].name, color: colorOf(si))]),
        const SizedBox(height: SboxSpace.sm),
        chart,
      ]);
    });
  }

  BarChartRodData _stackRod(int i, double Function(SboxSeries, int) at, Color Function(int) colorOf, double w) {
    var acc = 0.0;
    final items = <BarChartRodStackItem>[];
    for (var si = 0; si < series.length; si++) {
      final v = math.max(0.0, at(series[si], i));
      if (v == 0) continue;
      items.add(BarChartRodStackItem(acc, acc + v, colorOf(si)));
      acc += v;
    }
    return BarChartRodData(
      toY: acc,
      width: w,
      color: Colors.transparent,
      rodStackItems: items,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
    );
  }
}

// ─── Biểu đồ đường (xu hướng, so sánh kỳ) ──────────────────────────

class SboxLineChart extends StatelessWidget {
  const SboxLineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 240,
    this.valueFormat = SboxFmt.money,
    this.axisFormat = _defaultFmt,
    this.area = true,
    this.showLegend = true,
    this.dashedSeries = const {},
    this.maxY,
    this.maxLabels = 10,
  });

  final List<String> labels;
  final List<SboxSeries> series;
  final double height;
  final String Function(num? v) valueFormat;
  final SboxValueFormat axisFormat;
  /// Tô nền dưới chuỗi đầu tiên.
  final bool area;
  final bool showLegend;
  /// Chỉ số chuỗi vẽ nét đứt (vd «kỳ trước»).
  final Set<int> dashedSeries;
  /// Cố định trục (vd 100 cho tỷ lệ %).
  final double? maxY;
  final int maxLabels;

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    final hasData = n > 0 && series.any((s) => s.values.any((v) => v != 0));
    if (!hasData) return _ChartEmpty(height: height);
    Color colorOf(int si) => series[si].color ?? SboxChartColors.at(si);
    var hi = 0.0, lo = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        hi = math.max(hi, v);
        lo = math.min(lo, v);
      }
    }
    final top = maxY ?? _niceMax(hi);
    final bottom = lo < 0 ? -_niceMax(-lo) : 0.0;

    return LayoutBuilder(builder: (context, cons) {
      final chart = SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, n - 1).toDouble(),
            minY: bottom,
            maxY: top,
            gridData: _grid,
            borderData: FlBorderData(show: false),
            titlesData: _titles(labels: labels, axisFormat: axisFormat, maxLabels: math.max(3, (cons.maxWidth / 56).floor()).clamp(3, maxLabels)),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => SboxChartColors.tooltipBg,
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => [
                  for (var k = 0; k < spots.length; k++)
                    LineTooltipItem(
                      k == 0 ? '${labels[spots[k].x.round().clamp(0, n - 1)]}\n' : '',
                      _tooltipLabel,
                      children: [
                        if (series.length > 1) TextSpan(text: '${tr(series[spots[k].barIndex].name)}: ', style: _tooltipLabel),
                        TextSpan(text: valueFormat(spots[k].y), style: _tooltipText),
                      ],
                      textAlign: TextAlign.left,
                    ),
                ],
              ),
            ),
            lineBarsData: [
              for (var si = 0; si < series.length; si++)
                LineChartBarData(
                  spots: [for (var i = 0; i < math.min(n, series[si].values.length); i++) FlSpot(i.toDouble(), series[si].values[i])],
                  isCurved: true,
                  preventCurveOverShooting: true,
                  curveSmoothness: 0.25,
                  color: colorOf(si),
                  barWidth: dashedSeries.contains(si) ? 2 : 2.5,
                  dashArray: dashedSeries.contains(si) ? const [5, 4] : null,
                  dotData: FlDotData(show: n <= 12 && !dashedSeries.contains(si)),
                  belowBarData: BarAreaData(
                    show: area && si == 0,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [colorOf(si).withValues(alpha: 0.18), colorOf(si).withValues(alpha: 0.0)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      if (!showLegend || series.length < 2) return chart;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SboxLegend(items: [for (var si = 0; si < series.length; si++) (label: series[si].name, color: colorOf(si))]),
        const SizedBox(height: SboxSpace.sm),
        chart,
      ]);
    });
  }
}

// ─── Biểu đồ tròn (cơ cấu) ─────────────────────────────────────────

class SboxDonutChart extends StatelessWidget {
  const SboxDonutChart({
    super.key,
    required this.slices,
    this.centerLabel,
    this.centerValue,
    this.valueFormat = SboxFmt.money,
    this.size = 168,
    this.maxSlices = 5,
  });

  final List<SboxSlice> slices;
  final String? centerLabel;
  final String? centerValue;
  final String Function(num? v) valueFormat;
  final double size;
  /// Gộp phần nhỏ vào «Khác» cho dễ đọc.
  final int maxSlices;

  List<SboxSlice> get _merged {
    final list = slices.where((s) => s.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    if (list.length <= maxSlices) return list;
    final head = list.take(maxSlices - 1).toList();
    final rest = list.skip(maxSlices - 1).fold<double>(0, (s, x) => s + x.value);
    return [...head, SboxSlice('Khác', rest, color: SboxColors.slate300)];
  }

  @override
  Widget build(BuildContext context) {
    final data = _merged;
    final total = data.fold<double>(0, (s, x) => s + x.value);
    if (total <= 0) return _ChartEmpty(height: size);
    Color colorOf(int i) => data[i].color ?? SboxChartColors.at(i);

    final donut = SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: size * 0.32,
          startDegreeOffset: -90,
          sections: [
            for (var i = 0; i < data.length; i++)
              PieChartSectionData(value: data[i].value, color: colorOf(i), radius: size * 0.16, showTitle: false),
          ],
        )),
        if (centerValue != null || centerLabel != null)
          Column(mainAxisSize: MainAxisSize.min, children: [
            if (centerValue != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size * 0.6),
                child: FittedBox(child: Text(centerValue!, style: SboxType.moneyStyle(size: SboxType.titleSm))),
              ),
            if (centerLabel != null) Text(tr(centerLabel!), style: SboxType.captionStyle()),
          ]),
      ]),
    );

    final legend = Column(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < data.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: colorOf(i), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: SboxSpace.sm),
            Expanded(
              child: Text(tr(data[i].label), maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text)),
            ),
            const SizedBox(width: SboxSpace.sm),
            Text(SboxFmt.pct(data[i].value / total * 100), style: SboxType.captionStyle()),
            const SizedBox(width: SboxSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96),
              child: Text(valueFormat(data[i].value),
                  textAlign: TextAlign.right, maxLines: 1, style: SboxType.moneyStyle(size: SboxType.small)),
            ),
          ]),
        ),
    ]);

    return LayoutBuilder(builder: (context, cons) {
      if (cons.maxWidth < size + 240) {
        return Column(children: [donut, const SizedBox(height: SboxSpace.md), legend]);
      }
      return Row(children: [donut, const SizedBox(width: SboxSpace.xl), Expanded(child: legend)]);
    });
  }
}

// ─── Xếp hạng (thanh ngang) — Top sản phẩm, Top nhân viên… ──────────

class SboxRankList extends StatelessWidget {
  const SboxRankList({
    super.key,
    required this.items,
    this.valueFormat = SboxFmt.money,
    this.color = SboxColors.brand500,
    this.maxItems = 5,
    this.emptyHeight = 120,
    this.ascending = false,
    this.maxValue,
  });

  final List<SboxSlice> items;
  final String Function(num? v) valueFormat;
  final Color color;
  final int maxItems;
  final double emptyHeight;

  /// Xếp từ thấp lên (vd «chuyên cần thấp nhất») — giữ cả giá trị 0.
  final bool ascending;

  /// Mốc 100% của thanh (vd 100 cho tỷ lệ %); mặc định = giá trị lớn nhất.
  final double? maxValue;

  @override
  Widget build(BuildContext context) {
    final list = items.where((s) => ascending || s.value != 0).toList()
      ..sort((a, b) => ascending ? a.value.compareTo(b.value) : b.value.compareTo(a.value));
    final shown = list.take(maxItems).toList();
    if (shown.isEmpty) return _ChartEmpty(height: emptyHeight);
    final peak = maxValue ?? shown.fold<double>(0, (a, e) => math.max(a, e.value.toDouble()));
    final top = peak <= 0 ? 1.0 : peak;
    return Column(children: [
      for (var i = 0; i < shown.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(
                width: 20,
                child: Text('${i + 1}', style: SboxType.captionStyle(i < 3 ? SboxColors.brand700 : SboxColors.textMuted)),
              ),
              Expanded(
                child: Text(tr(shown[i].label), maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text)),
              ),
              if (shown[i].caption != null) ...[
                Text(tr(shown[i].caption!), style: SboxType.captionStyle()),
                const SizedBox(width: SboxSpace.sm),
              ],
              Text(valueFormat(shown[i].value), style: SboxType.moneyStyle(size: SboxType.small)),
            ]),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: ClipRRect(
                borderRadius: SboxRadius.pillAll,
                child: LinearProgressIndicator(
                  value: (shown[i].value / top).clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: SboxColors.slate100,
                  valueColor: AlwaysStoppedAnimation(shown[i].color ?? color),
                ),
              ),
            ),
          ]),
        ),
    ]);
  }
}

// ─── Thanh tiến độ tỷ lệ (vd Có mặt / Vắng / Trễ) ──────────────────

class SboxRatioBar extends StatelessWidget {
  const SboxRatioBar({super.key, required this.parts, this.height = 10});
  final List<SboxSlice> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = parts.fold<double>(0, (s, p) => s + math.max(0, p.value));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: SboxRadius.pillAll,
        child: SizedBox(
          height: height,
          child: total <= 0
              ? Container(color: SboxColors.slate100)
              : Row(children: [
                  for (var i = 0; i < parts.length; i++)
                    if (parts[i].value > 0)
                      Expanded(
                        flex: math.max(1, (parts[i].value / total * 1000).round()),
                        child: Container(color: parts[i].color ?? SboxChartColors.at(i)),
                      ),
                ]),
        ),
      ),
      const SizedBox(height: SboxSpace.sm),
      SboxLegend(items: [
        for (var i = 0; i < parts.length; i++)
          (label: '${parts[i].label} ${SboxFmt.number(parts[i].value)}', color: parts[i].color ?? SboxChartColors.at(i)),
      ]),
    ]);
  }
}
