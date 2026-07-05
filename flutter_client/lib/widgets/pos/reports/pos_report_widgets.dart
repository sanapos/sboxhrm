import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/pos_kiot_time_range.dart';
import '../pos_kiot_time_filter.dart';
import '../pos_mobile_widgets.dart';
import '../pos_theme.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Khung màn báo cáo mobile kiểu KiotViet.
class PosReportMobileScaffold extends StatelessWidget {
  const PosReportMobileScaffold({
    super.key,
    required this.title,
    required this.time,
    required this.onTimeChanged,
    required this.body,
    this.onFilterTap,
    this.onRefresh,
  });

  final String title;
  final PosKiotTimeFilterState time;
  final ValueChanged<PosKiotTimeFilterState> onTimeChanged;
  final Widget body;
  final VoidCallback? onFilterTap;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final header = Material(
      color: Colors.white,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onFilterTap != null)
                  IconButton(
                    icon: const Icon(Icons.filter_alt_outlined),
                    onPressed: onFilterTap,
                  ),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: PosKiotTimeFilter(
                state: time,
                dense: true,
                onChanged: onTimeChanged,
              ),
            ),
          ),
        ],
      ),
    );
    return ColoredBox(
      color: const Color(0xFFF3F4F6),
      child: Column(
        children: [
          posNeedsTopSafeArea(context)
              ? SafeArea(bottom: false, child: header)
              : header,
          Expanded(
            child: RefreshIndicator(
              color: _kiotBlue,
              onRefresh: onRefresh ?? () async {},
              child: body,
            ),
          ),
        ],
      ),
    );
  }
}

class PosReportCard extends StatelessWidget {
  const PosReportCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: PosTheme.mobileCardDecoration(),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// Thanh xếp hạng có progress bar (top hàng / nhân viên).
class PosReportRankList extends StatelessWidget {
  const PosReportRankList({
    super.key,
    required this.items,
    required this.labelOf,
    required this.valueOf,
    this.moneyFmt,
    this.allowNegative = false,
  });

  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) labelOf;
  final double Function(Map<String, dynamic>) valueOf;
  final NumberFormat? moneyFmt;
  final bool allowNegative;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Chưa có dữ liệu', style: TextStyle(color: PosTheme.textSecondary));
    }
    final fmt = moneyFmt ?? NumberFormat('#,##0', 'vi_VN');
    final maxVal = items
        .map(valueOf)
        .map((v) => allowNegative ? v.abs() : v.clamp(0.0, double.infinity))
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _RankRow(
            label: labelOf(items[i]),
            value: valueOf(items[i]),
            maxValue: maxVal <= 0 ? 1 : maxVal,
            formatted: fmt.format(valueOf(items[i])),
            allowNegative: allowNegative,
          ),
        ],
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.formatted,
    this.allowNegative = false,
  });

  final String label;
  final double value;
  final double maxValue;
  final String formatted;
  final bool allowNegative;

  @override
  Widget build(BuildContext context) {
    final ratio = (value.abs() / maxValue).clamp(0.0, 1.0);
    final barColor = value < 0 ? Colors.red.shade300 : _kiotBlue.withValues(alpha: 0.35);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatted,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: value < 0 ? Colors.red.shade700 : _kiotBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: Colors.grey.shade200,
            color: barColor,
          ),
        ),
      ],
    );
  }
}

class PosReportInventoryBanner extends StatelessWidget {
  const PosReportInventoryBanner({
    super.key,
    required this.inventoryValue,
    required this.productCount,
    this.moneyFmt,
  });

  final double inventoryValue;
  final int productCount;
  final NumberFormat? moneyFmt;

  @override
  Widget build(BuildContext context) {
    final fmt = moneyFmt ?? NumberFormat('#,##0', 'vi_VN');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kiotBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tồn kho ${fmt.format(inventoryValue)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$productCount sản phẩm',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class PosReportBarChart extends StatelessWidget {
  const PosReportBarChart({
    super.key,
    required this.points,
    this.height = 180,
  });

  final List<({DateTime date, double value})> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Chưa có dữ liệu')),
      );
    }
    final fmt = DateFormat('dd/MM', 'vi_VN');
    final values = points.map((p) => p.value).toList();
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.15).clamp(1000.0, double.infinity);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: minY < 0 ? minY - pad : 0,
          maxY: maxY + pad,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: pad > 0 ? pad : 1000,
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      fmt.format(points[i].date),
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].value,
                    color: points[i].value < 0 ? Colors.red : _kiotBlue,
                    width: points.length <= 7 ? 22 : 12,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class PosReportMultiLineChart extends StatelessWidget {
  const PosReportMultiLineChart({
    super.key,
    required this.points,
    this.height = 200,
  });

  final List<({DateTime date, double revenue, double cogs, double profit})> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Chưa có dữ liệu')),
      );
    }
    final allVals = points.expand((p) => [p.revenue, p.cogs, p.profit]).toList();
    final minY = allVals.reduce((a, b) => a < b ? a : b);
    final maxY = allVals.reduce((a, b) => a > b ? a : b);
    final pad = ((maxY - minY).abs() * 0.1).clamp(500.0, double.infinity);

    List<FlSpot> spots(List<double> vals) =>
        [for (var i = 0; i < vals.length; i++) FlSpot(i.toDouble(), vals[i])];

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: minY - pad,
          maxY: maxY + pad,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Text(
                    DateFormat('dd/MM').format(points[i].date),
                    style: const TextStyle(fontSize: 10),
                  );
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots(points.map((p) => p.revenue).toList()),
              isCurved: true,
              color: Colors.red,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: spots(points.map((p) => p.profit).toList()),
              isCurved: true,
              color: _kiotBlue,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              spots: spots(points.map((p) => p.cogs).toList()),
              isCurved: true,
              color: Colors.amber.shade700,
              barWidth: 2,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class PosReportDonut extends StatelessWidget {
  const PosReportDonut({
    super.key,
    required this.total,
    required this.slices,
    this.size = 160,
    this.moneyFmt,
  });

  final double total;
  final List<({String label, double value, Color color})> slices;
  final double size;
  final NumberFormat? moneyFmt;

  @override
  Widget build(BuildContext context) {
    final fmt = moneyFmt ?? NumberFormat('#,##0', 'vi_VN');
    if (total <= 0 || slices.isEmpty) {
      return SizedBox(
        height: size,
        child: const Center(child: Text('Chưa có dữ liệu')),
      );
    }
    return SizedBox(
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.32,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.value.clamp(0.0, double.infinity),
                    color: s.color,
                    radius: size * 0.22,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Tổng', style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
              Text(
                fmt.format(total),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kiotBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PosReportMetricTiles extends StatelessWidget {
  const PosReportMetricTiles({
    super.key,
    required this.tiles,
    this.moneyFmt,
  });

  final List<({String label, double value, Color color})> tiles;
  final NumberFormat? moneyFmt;

  @override
  Widget build(BuildContext context) {
    final fmt = moneyFmt ?? NumberFormat('#,##0', 'vi_VN');
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tiles[i].color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tiles[i].label,
                    style: TextStyle(fontSize: 11, color: tiles[i].color),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fmt.format(tiles[i].value),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: tiles[i].color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class PosReportBranchFooter extends StatelessWidget {
  const PosReportBranchFooter({super.key, required this.branchName});

  final String branchName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PosTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: _kiotBlue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              branchName.isEmpty ? 'Chi nhánh' : branchName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const Icon(Icons.keyboard_arrow_up, color: PosTheme.textSecondary, size: 20),
        ],
      ),
    );
  }
}
