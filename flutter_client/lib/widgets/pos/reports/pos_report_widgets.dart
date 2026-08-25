import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../utils/media_query_safe_padding.dart';
import '../../../utils/pos_kiot_time_range.dart';
import '../pos_kiot_time_filter.dart';
import '../pos_mobile_widgets.dart';
import '../pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;
const _ink = Color(0xFF2B3437);
const _muted = Color(0xFF586064);
const _hint = Color(0xFF8A9199);
const _pageBg = Color(0xFFF1F4F6);
const _rose = Color(0xFFB42318);
const _teal = Color(0xFF0F766E);
const _cogs = Color(0xFFCA8A04);

final _dotFmt = NumberFormat('#,##0', 'vi_VN');

String posReportMoneyOf(num value, [NumberFormat? fmt]) {
  if (fmt != null && value.abs() < 1000000) return fmt.format(value);
  return posReportMoney(value);
}

/// Rút gọn tiền trên T1: `363.642.719` → `363,6 tr` để không vỡ hàng.
String posReportMoney(num value) {
  final v = value.toDouble();
  final sign = v < 0 ? '-' : '';
  final abs = v.abs();
  if (abs >= 1000000000) {
    final n = abs / 1000000000;
    return '$sign${_oneDec(n)} tỷ';
  }
  if (abs >= 1000000) {
    final n = abs / 1000000;
    return '$sign${_oneDec(n)} tr';
  }
  return '$sign${_dotFmt.format(abs.round())}';
}

String posReportAxis(double v) {
  final sign = v < 0 ? '-' : '';
  final abs = v.abs();
  if (abs >= 1000000000) {
    return '$sign${_oneDec(abs / 1000000000)}tỷ';
  }
  if (abs >= 1000000) {
    return '$sign${_oneDec(abs / 1000000)}tr';
  }
  if (abs >= 1000) {
    return '$sign${(abs / 1000).toStringAsFixed(0)}k';
  }
  return '$sign${abs.toStringAsFixed(0)}';
}

String _oneDec(double n) {
  if (n >= 100) return n.toStringAsFixed(0);
  final s = n.toStringAsFixed(n >= 10 ? 1 : 1);
  return s.replaceAll('.', ',').replaceAll(RegExp(r',0$'), '');
}

Color posReportSignedColor(num value, {Color positive = _ink}) {
  return value < 0 ? _rose : positive;
}

/// Số tiền 1 dòng, tự co để không tràn / vỡ glyph.
class PosReportMoneyLabel extends StatelessWidget {
  const PosReportMoneyLabel(
    this.value, {
    super.key,
    this.prefix = '',
    this.color,
    this.fontSize = 13,
    this.fontWeight = FontWeight.w700,
    this.align = Alignment.centerRight,
    this.maxWidth = 120,
    this.format,
  });

  final num value;
  final String prefix;
  final Color? color;
  final double fontSize;
  final FontWeight fontWeight;
  final Alignment align;
  final double maxWidth;
  final NumberFormat? format;

  @override
  Widget build(BuildContext context) {
    final text = '$prefix${posReportMoneyOf(value, format)}';
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color ?? posReportSignedColor(value),
            height: 1.15,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class PosReportEmpty extends StatelessWidget {
  const PosReportEmpty({
    super.key,
    this.message = 'Chưa có dữ liệu',
    this.height = 40,
  });

  final String message;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text(
          tr(message),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _hint,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

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
    this.showTimeFilter = true,
    this.filterBar,
    this.onExportExcel,
    this.onExportPng,
    this.pngKey,
  });

  final String title;
  final PosKiotTimeFilterState time;
  final ValueChanged<PosKiotTimeFilterState> onTimeChanged;
  final Widget body;
  final VoidCallback? onFilterTap;
  final Future<void> Function()? onRefresh;
  final bool showTimeFilter;
  final Widget? filterBar;
  final VoidCallback? onExportExcel;
  final VoidCallback? onExportPng;
  final GlobalKey? pngKey;

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
                  icon: const Icon(Icons.arrow_back, color: _ink),
                  onPressed: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      tr(title),
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                ),
                if (onExportPng != null)
                  IconButton(
                    tooltip: tr('Xuất PNG'),
                    icon: const Icon(Icons.image_outlined, color: _muted),
                    onPressed: onExportPng,
                  ),
                if (onExportExcel != null)
                  IconButton(
                    tooltip: tr('Xuất Excel'),
                    icon: const Icon(Icons.file_download_outlined, color: _muted),
                    onPressed: onExportExcel,
                  ),
                if (onFilterTap != null)
                  IconButton(
                    tooltip: tr('Bộ lọc'),
                    icon: const Icon(Icons.filter_alt_outlined, color: _muted),
                    onPressed: onFilterTap,
                  ),
              ],
            ),
          ),
          if (showTimeFilter)
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
          if (filterBar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: filterBar,
            ),
        ],
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.05,
      child: ColoredBox(
        color: _pageBg,
        child: Column(
          children: [
            posNeedsTopSafeArea(context)
                ? withFallbackTopInset(
                    context,
                    SafeArea(bottom: false, child: header),
                  )
                : withFallbackTopInset(context, header),
            Expanded(
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _ink,
                  height: 1.25,
                  letterSpacing: -0.1,
                ),
                child: RefreshIndicator(
                  color: _kiotBlue,
                  onRefresh: onRefresh ?? () async {},
                  child: pngKey == null
                      ? body
                      : RepaintBoundary(key: pngKey, child: body),
                ),
              ),
            ),
          ],
        ),
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
                          tr(title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            tr(subtitle!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: _muted,
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

class PosReportChipBar extends StatelessWidget {
  const PosReportChipBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (var i = 0; i < labels.length; i++)
          Material(
            color: selected == i
                ? _kiotBlue.withOpacity(0.12)
                : const Color(0xFFF3F5F7),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: () => onSelected(i),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  tr(labels[i]),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        selected == i ? FontWeight.w600 : FontWeight.w500,
                    color: selected == i ? _kiotBlue : _muted,
                  ),
                ),
              ),
            ),
          ),
      ],
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
    this.onItemTap,
  });

  final List<Map<String, dynamic>> items;
  final String Function(Map<String, dynamic>) labelOf;
  final double Function(Map<String, dynamic>) valueOf;
  final NumberFormat? moneyFmt;
  final bool allowNegative;
  final void Function(Map<String, dynamic> item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const PosReportEmpty();
    }
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
            moneyFmt: moneyFmt,
            onTap: onItemTap == null ? null : () => onItemTap!(items[i]),
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
    this.moneyFmt,
    this.onTap,
  });

  final String label;
  final double value;
  final double maxValue;
  final NumberFormat? moneyFmt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = (value.abs() / maxValue).clamp(0.0, 1.0);
    final barColor = value < 0 ? const Color(0xFFE4A0A0) : _kiotBlue.withOpacity(0.35);
    final row = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: _ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            PosReportMoneyLabel(
              value,
              format: moneyFmt,
              color: value < 0 ? _rose : _ink,
              fontSize: 13,
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Icon(Icons.chevron_right, size: 18, color: _hint),
              ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 4,
            backgroundColor: const Color(0xFFEEF1F4),
            color: barColor,
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: row,
      ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: _kiotBlue,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Tồn kho'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                posReportMoneyOf(inventoryValue, moneyFmt),
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            tr('$productCount sản phẩm'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.88),
              fontSize: 12,
            ),
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
      return PosReportEmpty(height: height);
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
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0xFFE8ECF0),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, _) => Text(
                  posReportAxis(v),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 9, color: _hint, height: 1),
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
                      style: const TextStyle(fontSize: 9, color: _hint),
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
                    color: points[i].value < 0
                        ? const Color(0xFFE4A0A0)
                        : _kiotBlue,
                    width: points.length <= 7 ? 22 : 12,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(3)),
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

  final List<({DateTime date, double revenue, double cogs, double profit})>
      points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return PosReportEmpty(height: height);
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
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0xFFE8ECF0),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, _) => Text(
                  posReportAxis(v),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 9, color: _hint, height: 1),
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
                    style: const TextStyle(fontSize: 9, color: _hint),
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
              color: _teal,
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
              color: _cogs,
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
    if (total <= 0 || slices.isEmpty) {
      return PosReportEmpty(height: size);
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
          SizedBox(
            width: size * 0.52,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Tổng'),
                  style: const TextStyle(fontSize: 11, color: _hint),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    posReportMoneyOf(total, moneyFmt),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
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
    this.onTileTap,
  });

  final List<({String label, double value, Color color})> tiles;
  final NumberFormat? moneyFmt;
  final void Function(int index)? onTileTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTileTap == null ? null : () => onTileTap!(i),
                borderRadius: BorderRadius.circular(8),
                child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F9FB),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: tiles[i].color, width: 3),
                  top: const BorderSide(color: Color(0xFFE8ECF0)),
                  right: const BorderSide(color: Color(0xFFE8ECF0)),
                  bottom: const BorderSide(color: Color(0xFFE8ECF0)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(tiles[i].label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                              posReportMoneyOf(tiles[i].value, moneyFmt),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                          height: 1.15,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
                ),
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
        color: const Color(0xFFF7F9FB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: _kiotBlue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr(branchName.isEmpty ? 'Chi nhánh' : branchName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _ink,
              ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_up, color: _hint, size: 20),
        ],
      ),
    );
  }
}

/// Dòng báo cáo có thể bấm để mở phiếu / danh sách.
class PosReportNavRow extends StatelessWidget {
  const PosReportNavRow({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          children: [
            Expanded(child: child),
            const Icon(Icons.chevron_right, size: 18, color: _hint),
          ],
        ),
      ),
    );
  }
}
