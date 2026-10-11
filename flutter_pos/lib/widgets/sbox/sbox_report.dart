import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import 'sbox_basics.dart';

/// SBOX Design — khung Tổng quan / Báo cáo:
///   Bộ lọc kỳ  →  Dải KPI (so với kỳ trước)  →  Biểu đồ  →  Bảng tổng hợp.
/// Máy tính: KPI 4–6 cột, biểu đồ 2 cột. Điện thoại: KPI 2 cột, biểu đồ 1 cột, bảng → thẻ.

// ─── Kỳ báo cáo + kỳ so sánh ───────────────────────────────────────

enum SboxPeriod { today, yesterday, last7, thisMonth, lastMonth, last30 }

extension SboxPeriodX on SboxPeriod {
  String get label => switch (this) {
        SboxPeriod.today => 'Hôm nay',
        SboxPeriod.yesterday => 'Hôm qua',
        SboxPeriod.last7 => '7 ngày',
        SboxPeriod.thisMonth => 'Tháng này',
        SboxPeriod.lastMonth => 'Tháng trước',
        SboxPeriod.last30 => '30 ngày',
      };

  /// Nhãn kỳ so sánh cho dòng «+12% so với …».
  String get compareLabel => switch (this) {
        SboxPeriod.today => 'hôm qua',
        SboxPeriod.yesterday => 'hôm kia',
        SboxPeriod.last7 => '7 ngày trước',
        SboxPeriod.thisMonth => 'cùng kỳ tháng trước',
        SboxPeriod.lastMonth => 'tháng trước nữa',
        SboxPeriod.last30 => '30 ngày trước',
      };

  /// Số ngày cho xu hướng chấm công (API attendance-trends).
  int get trendDays => switch (this) {
        SboxPeriod.today || SboxPeriod.yesterday || SboxPeriod.last7 => 7,
        _ => 30,
      };

  /// [from, to] theo giờ địa phương (to = cuối ngày).
  (DateTime, DateTime) range([DateTime? now]) {
    final n = now ?? DateTime.now();
    final d0 = DateTime(n.year, n.month, n.day);
    DateTime end(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
    return switch (this) {
      SboxPeriod.today => (d0, end(d0)),
      SboxPeriod.yesterday => (d0.subtract(const Duration(days: 1)), end(d0.subtract(const Duration(days: 1)))),
      SboxPeriod.last7 => (d0.subtract(const Duration(days: 6)), end(d0)),
      SboxPeriod.thisMonth => (DateTime(n.year, n.month, 1), end(d0)),
      SboxPeriod.lastMonth => (DateTime(n.year, n.month - 1, 1), end(DateTime(n.year, n.month, 0))),
      SboxPeriod.last30 => (d0.subtract(const Duration(days: 29)), end(d0)),
    };
  }

  /// Kỳ trước cùng độ dài (tháng này → cùng số ngày của tháng trước).
  (DateTime, DateTime) previousRange([DateTime? now]) {
    final (f, t) = range(now);
    DateTime end(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59);
    switch (this) {
      case SboxPeriod.thisMonth:
        final pf = DateTime(f.year, f.month - 1, 1);
        final lastDay = DateTime(f.year, f.month, 0).day;
        return (pf, end(DateTime(pf.year, pf.month, math.min(t.day, lastDay))));
      case SboxPeriod.lastMonth:
        return (DateTime(f.year, f.month - 1, 1), end(DateTime(f.year, f.month, 0)));
      default:
        final days = DateTime(t.year, t.month, t.day).difference(DateTime(f.year, f.month, f.day)).inDays + 1;
        final pt = f.subtract(const Duration(days: 1));
        return (DateTime(pt.year, pt.month, pt.day).subtract(Duration(days: days - 1)), end(pt));
    }
  }
}

/// Thanh chọn kỳ: chip trên máy tính, cuộn ngang trên điện thoại.
class SboxPeriodBar extends StatelessWidget {
  const SboxPeriodBar({super.key, required this.value, required this.onChanged, this.options = SboxPeriod.values, this.trailing});
  final SboxPeriod value;
  final ValueChanged<SboxPeriod> onChanged;
  final List<SboxPeriod> options;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final p in options)
          Padding(
            padding: const EdgeInsets.only(right: SboxSpace.sm),
            child: _PeriodChip(label: p.label, selected: p == value, onTap: () => onChanged(p)),
          ),
      ]),
    );
    if (trailing == null) return chips;
    return Row(children: [Expanded(child: chips), const SizedBox(width: SboxSpace.sm), trailing!]);
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SboxColors.brand600 : SboxColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: SboxRadius.pillAll,
        side: BorderSide(color: selected ? SboxColors.brand600 : SboxColors.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(tr(label),
              style: SboxType.captionStyle(selected ? SboxColors.onPrimary : SboxColors.textSecondary)
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }
}

// ─── KPI ───────────────────────────────────────────────────────────

class SboxKpi {
  const SboxKpi({
    required this.label,
    required this.value,
    this.icon,
    this.tone = SboxTone.brand,
    this.current,
    this.previous,
    this.higherIsBetter = true,
    this.compareLabel,
    this.note,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final SboxTone tone;
  /// Số kỳ này / kỳ trước — để tính % thay đổi.
  final num? current;
  final num? previous;
  /// Chi phí, số người đi trễ… tăng là xấu → false.
  final bool higherIsBetter;
  final String? compareLabel;
  /// Dòng phụ khi không có so sánh (vd «12/15 nhân viên»).
  final String? note;
  final VoidCallback? onTap;

  ({String text, bool? good, bool up})? get delta {
    if (current == null || previous == null) return note == null ? null : (text: note!, good: null, up: true);
    final c = current!.toDouble(), p = previous!.toDouble();
    final vs = compareLabel == null ? '' : ' so với $compareLabel';
    if (p == 0) {
      if (c == 0) return (text: 'Không đổi$vs', good: null, up: true);
      return (text: 'Mới phát sinh$vs', good: higherIsBetter ? c > 0 : c < 0, up: c > 0);
    }
    final pct = (c - p) / p.abs() * 100;
    if (pct.abs() < 0.05) return (text: 'Không đổi$vs', good: null, up: true);
    final s = '${pct > 0 ? '+' : ''}${pct.abs() >= 100 ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1)}%$vs'.replaceAll('.', ',');
    final up = pct > 0;
    return (text: s, good: higherIsBetter ? up : !up, up: up);
  }
}

/// Dải KPI: điện thoại 2 cột, máy tính bảng 3, máy tính tối đa 6.
/// Hàng số liệu gọn cho điện thoại: 3–4 số trên 1 hàng, không lẻ thẻ / không cuộn ngang.
class SboxStatRow extends StatelessWidget {
  const SboxStatRow({super.key, required this.items});
  final List<SboxKpi> items;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: SboxSpace.sm),
        Expanded(
          child: Material(
            color: SboxColors.surface,
            shape: RoundedRectangleBorder(borderRadius: SboxRadius.mdAll, side: const BorderSide(color: SboxColors.border)),
            child: InkWell(
              customBorder: RoundedRectangleBorder(borderRadius: SboxRadius.mdAll),
              onTap: items[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(items[i].value,
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: items[i].tone.solid)),
                  ),
                  Text(tr(items[i].label),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, height: 1.2, color: SboxColors.textMuted)),
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
  }
}

class SboxKpiStrip extends StatelessWidget {
  const SboxKpiStrip({super.key, required this.items, this.maxColumns = 6});
  final List<SboxKpi> items;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      // Điện thoại: chia cột sao cho không có thẻ lẻ rớt xuống hàng (3 số → 3 cột, 6 số → 2×3…).
      final n = items.length;
      final cols = w < SboxBreakpoints.mobile
          ? (n <= 3 ? math.max(1, n) : (n.isEven ? 2 : (n % 3 == 0 ? 3 : 2)))
          : math.min(maxColumns, math.min(items.length, math.max(3, (w / 220).floor())));
      return SboxGrid(
        columns: cols,
        spacing: w < SboxBreakpoints.mobile ? SboxSpace.sm : SboxSpace.md,
        // Điện thoại 3 cột: bỏ biểu tượng để nhãn đủ chỗ, không xuống dòng.
        children: [for (final k in items) _KpiTile(k: k, compact: w < SboxBreakpoints.mobile, showIcon: !(w < SboxBreakpoints.mobile && cols >= 3))],
      );
    });
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.k, required this.compact, this.showIcon = true});
  final SboxKpi k;
  final bool compact;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final d = k.delta;
    final dColor = d?.good == null ? SboxColors.textMuted : (d!.good! ? SboxColors.successText : SboxColors.dangerText);
    return SboxCard(
      onTap: k.onTap,
      padding: EdgeInsets.all(compact ? SboxSpace.md : SboxSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (k.icon != null && showIcon) ...[
            Container(
              width: compact ? 26 : 30,
              height: compact ? 26 : 30,
              decoration: BoxDecoration(color: k.tone.bg, borderRadius: SboxRadius.smAll),
              child: Icon(k.icon, size: compact ? 15 : 17, color: k.tone.solid),
            ),
            const SizedBox(width: SboxSpace.sm),
          ],
          Expanded(
            child: Text(tr(k.label), maxLines: compact ? 2 : 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.textMuted)),
          ),
        ]),
        SizedBox(height: compact ? SboxSpace.sm : SboxSpace.md),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(k.value, style: SboxType.moneyStyle(size: compact ? SboxType.title : SboxType.headline)),
        ),
        const SizedBox(height: SboxSpace.xs),
        Row(children: [
          if (d?.good != null) ...[
            Icon(d!.up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13, color: dColor),
            const SizedBox(width: 2),
          ],
          Expanded(
            child: Text(d == null ? ' ' : tr(d.text),
                // Điện thoại: ghi chú dài (vd «Đã chi … · Chờ chi …») được 2 dòng thay vì bị cắt.
                maxLines: compact ? 2 : 1, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle(dColor)),
          ),
        ]),
      ]),
    );
  }
}

// ─── Lưới co giãn ──────────────────────────────────────────────────

/// Lưới [columns] cột, các ô trong cùng hàng cao bằng nhau.
class SboxGrid extends StatelessWidget {
  const SboxGrid({super.key, required this.columns, required this.children, this.spacing = SboxSpace.md});
  final int columns;
  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        if (c > 0) cells.add(SizedBox(width: spacing));
        cells.add(Expanded(child: i + c < children.length ? children[i + c] : const SizedBox.shrink()));
      }
      if (rows.isNotEmpty) rows.add(SizedBox(height: spacing));
      rows.add(IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

// ─── Thẻ biểu đồ ───────────────────────────────────────────────────

class SboxChartCard extends StatelessWidget {
  const SboxChartCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.onMore,
    this.wide = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  /// Hiện nút «Xem chi tiết» ở góc phải.
  final VoidCallback? onMore;
  /// Chiếm cả hàng trong [SboxReportLayout].
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return SboxCard(
      title: title,
      subtitle: subtitle,
      trailing: trailing ??
          (onMore == null
              ? null
              : TextButton(
                  onPressed: onMore,
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(tr('Chi tiết'), style: SboxType.captionStyle(SboxColors.brand700).copyWith(fontWeight: FontWeight.w600)),
                )),
      child: child,
    );
  }
}

/// Xếp thẻ biểu đồ: [twoCol] → 2 thẻ/hàng (thẻ `wide` chiếm cả hàng).
List<Widget> sboxChartRows(List<Widget> charts, {required bool twoCol, required double gap}) {
  final rows = <Widget>[];
  Widget? pending;
  for (final c in charts) {
    final wide = c is SboxChartCard && c.wide;
    if (!twoCol || wide) {
      if (pending != null) {
        rows.add(pending);
        pending = null;
      }
      rows.add(c);
      continue;
    }
    if (pending == null) {
      pending = c;
    } else {
      // Biểu đồ dùng LayoutBuilder → không đo IntrinsicHeight được; căn đỉnh.
      rows.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: pending),
        SizedBox(width: gap),
        Expanded(child: c),
      ]));
      pending = null;
    }
  }
  if (pending != null) rows.add(pending);
  return rows;
}

/// Khối «KPI + biểu đồ» chèn lên đầu một báo cáo sẵn có (phần bảng/danh sách giữ bên dưới).
class SboxInsightPanel extends StatelessWidget {
  const SboxInsightPanel({super.key, this.kpis = const [], this.charts = const [], this.maxKpiColumns = 6, this.bottomGap = SboxSpace.md});
  final List<SboxKpi> kpis;
  final List<Widget> charts;
  final int maxKpiColumns;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final gap = w < SboxBreakpoints.mobile ? SboxSpace.md : SboxSpace.lg;
      final blocks = <Widget>[
        if (kpis.isNotEmpty) SboxKpiStrip(items: kpis, maxColumns: maxKpiColumns),
        ...sboxChartRows(charts, twoCol: w >= 900, gap: gap),
      ];
      return Padding(
        padding: EdgeInsets.only(bottom: bottomGap),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < blocks.length; i++) ...[if (i > 0) SizedBox(height: gap), blocks[i]],
        ]),
      );
    });
  }
}

/// Kỳ trước cùng độ dài với [from]–[to] (dùng cho % so sánh trong báo cáo).
(DateTime, DateTime)? sboxPreviousRange(DateTime? from, DateTime? to) {
  if (from == null || to == null) return null;
  final f = DateTime(from.year, from.month, from.day);
  final t = DateTime(to.year, to.month, to.day);
  final days = t.difference(f).inDays + 1;
  if (days <= 0) return null;
  // Trọn tháng → so với trọn tháng trước.
  final lastDay = DateTime(t.year, t.month + 1, 0).day;
  if (f.day == 1 && t.day == lastDay && f.month == t.month && f.year == t.year) {
    return (DateTime(f.year, f.month - 1, 1), DateTime(f.year, f.month, 0, 23, 59, 59));
  }
  final pt = f.subtract(const Duration(days: 1));
  return (pt.subtract(Duration(days: days - 1)), DateTime(pt.year, pt.month, pt.day, 23, 59, 59));
}

/// Nhãn ngày ngắn dd/MM cho trục biểu đồ.
String sboxDayLabel(dynamic iso) {
  final d = iso is DateTime ? iso : DateTime.tryParse('${iso ?? ''}');
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Khung trang báo cáo / tổng quan.
class SboxReportLayout extends StatelessWidget {
  const SboxReportLayout({
    super.key,
    this.header,
    this.filters,
    this.kpis = const [],
    this.charts = const [],
    this.table,
    this.tableTitle,
    this.tableActions,
    this.onRefresh,
    this.maxKpiColumns = 6,
    this.children = const [],
  });

  final Widget? header;
  final Widget? filters;
  final List<SboxKpi> kpis;
  /// [SboxChartCard] (wide → cả hàng). Máy tính: 2 cột; điện thoại: 1 cột.
  final List<Widget> charts;
  /// Bảng tổng hợp (thường là SboxDataTable — tự thành thẻ trên điện thoại).
  final Widget? table;
  final String? tableTitle;
  final Widget? tableActions;
  final Future<void> Function()? onRefresh;
  final int maxKpiColumns;
  /// Khối thêm sau biểu đồ, trước bảng.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final list = LayoutBuilder(builder: (context, cons) {
      final w = cons.maxWidth;
      final pad = SboxSpace.pagePadding(w);
      final gap = w < SboxBreakpoints.mobile ? SboxSpace.md : SboxSpace.lg;
      final twoCol = w >= 900;
      final chartRows = sboxChartRows(charts, twoCol: twoCol, gap: gap);

      final blocks = <Widget>[
        if (header != null) header!,
        if (filters != null) filters!,
        if (kpis.isNotEmpty) SboxKpiStrip(items: kpis, maxColumns: maxKpiColumns),
        ...chartRows,
        ...children,
        if (table != null)
          tableTitle == null
              ? table!
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: SboxSpace.sm),
                    child: Row(children: [
                      Expanded(child: Text(tr(tableTitle!), style: SboxType.titleSmStyle())),
                      if (tableActions != null) tableActions!,
                    ]),
                  ),
                  table!,
                ]),
      ];
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + SboxSpace.xl),
        itemCount: blocks.length,
        separatorBuilder: (_, __) => SizedBox(height: gap),
        itemBuilder: (_, i) => blocks[i],
      );
    });
    final body = ColoredBox(color: SboxColors.page, child: list);
    return onRefresh == null ? body : RefreshIndicator(onRefresh: onRefresh!, child: body);
  }
}

// ─── Việc cần xử lý ────────────────────────────────────────────────

class SboxTodoItem {
  const SboxTodoItem({required this.label, required this.count, this.tone = SboxTone.warning, this.icon, this.onTap});
  final String label;
  final int count;
  final SboxTone tone;
  final IconData? icon;
  final VoidCallback? onTap;
}

/// Danh sách việc chờ xử lý (chỉ hiện mục có số > 0).
class SboxTodoList extends StatelessWidget {
  const SboxTodoList({super.key, required this.items});
  final List<SboxTodoItem> items;

  @override
  Widget build(BuildContext context) {
    final shown = items.where((e) => e.count > 0).toList();
    if (shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SboxSpace.lg),
        child: Row(children: [
          const Icon(Icons.check_circle_rounded, color: SboxColors.success, size: 20),
          const SizedBox(width: SboxSpace.sm),
          Expanded(child: Text(tr('Không có việc tồn đọng — mọi thứ đã được xử lý'), style: SboxType.smallStyle())),
        ]),
      );
    }
    return Column(children: [
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) const Divider(height: 1, color: SboxColors.divider),
        InkWell(
          onTap: shown[i].onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: shown[i].tone.bg, borderRadius: SboxRadius.smAll),
                child: Icon(shown[i].icon ?? Icons.pending_actions_rounded, size: 17, color: shown[i].tone.solid),
              ),
              const SizedBox(width: SboxSpace.md),
              Expanded(child: Text(tr(shown[i].label), style: SboxType.smallStyle(SboxColors.text))),
              Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: shown[i].tone.bg, borderRadius: SboxRadius.pillAll),
                child: Text('${shown[i].count}',
                    textAlign: TextAlign.center, style: SboxType.captionStyle(shown[i].tone.fg).copyWith(fontWeight: FontWeight.w700)),
              ),
              if (shown[i].onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: SboxColors.slate400),
            ]),
          ),
        ),
      ],
    ]);
  }
}
