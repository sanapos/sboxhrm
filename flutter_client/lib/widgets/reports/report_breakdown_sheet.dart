import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../sbox/sbox_ui.dart';

/// Một dòng trong bảng chi tiết của thẻ số liệu (vd một nhân viên: 3 phiếu · 150.000 đ).
class ReportBreakdownRow {
  const ReportBreakdownRow({
    required this.label,
    required this.value,
    this.caption,
    this.valueText,
    this.onTap,
  });

  final String label;
  final num value;
  /// Dòng phụ (vd «3 phiếu · Bếp»).
  final String? caption;
  /// Chữ hiện bên phải; bỏ trống → [valueFormat] của bảng.
  final String? valueText;
  final VoidCallback? onTap;
}

/// Gom bản ghi theo [keyOf] (thường là tên nhân viên): cộng [valueOf], đếm số bản ghi.
/// [captionOf] nhận (số bản ghi, các bản ghi của nhóm) → dòng phụ.
List<ReportBreakdownRow> reportGroupBreakdown<T>(
  Iterable<T> items, {
  required String Function(T) keyOf,
  num Function(T)? valueOf,
  String Function(int count, List<T> group)? captionOf,
  String Function(num value, int count)? valueTextOf,
}) {
  final groups = <String, List<T>>{};
  for (final t in items) {
    final k = keyOf(t).trim();
    groups.putIfAbsent(k.isEmpty ? '—' : k, () => []).add(t);
  }
  final rows = <ReportBreakdownRow>[];
  groups.forEach((k, g) {
    final v = valueOf == null ? g.length : g.fold<num>(0, (s, t) => s + valueOf(t));
    rows.add(ReportBreakdownRow(
      label: k,
      value: v,
      caption: captionOf?.call(g.length, g),
      valueText: valueTextOf?.call(v, g.length),
    ));
  });
  rows.sort((a, b) => b.value.compareTo(a.value));
  return rows;
}

/// Bảng chi tiết khi bấm một thẻ số liệu trên báo cáo: tổng + danh sách xếp theo giá trị.
Future<void> showReportBreakdownSheet(
  BuildContext context, {
  required String title,
  required List<ReportBreakdownRow> rows,
  String? subtitle,
  String Function(num v)? valueFormat,
  String emptyText = 'Không có dữ liệu trong kỳ',
  /// Nút cuối bảng (vd «Lọc danh sách theo mục này»).
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => ReportBreakdownSheet(
      title: title,
      subtitle: subtitle,
      rows: rows,
      valueFormat: valueFormat,
      emptyText: emptyText,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              Navigator.pop(ctx);
              onAction();
            },
    ),
  );
}

class ReportBreakdownSheet extends StatelessWidget {
  const ReportBreakdownSheet({
    super.key,
    required this.title,
    required this.rows,
    this.subtitle,
    this.valueFormat,
    this.emptyText = 'Không có dữ liệu trong kỳ',
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final List<ReportBreakdownRow> rows;
  final String Function(num v)? valueFormat;
  final String emptyText;
  final String? actionLabel;
  final VoidCallback? onAction;

  String _fmt(ReportBreakdownRow r) => r.valueText ?? (valueFormat ?? (v) => SboxFmt.number(v))(r.value);

  @override
  Widget build(BuildContext context) {
    final maxV = rows.fold<num>(0, (m, r) => r.value > m ? r.value : m);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: rows.length > 6 ? 0.7 : 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.lg, SboxSpace.sm, SboxSpace.sm),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: SboxType.titleStyle()),
                if (subtitle != null && subtitle!.isNotEmpty) Text(tr(subtitle!), style: SboxType.captionStyle()),
              ]),
            ),
            IconButton(
              tooltip: tr('Đóng'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text(tr(emptyText), style: SboxType.bodyStyle(SboxColors.textMuted)))
              : ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.sm, SboxSpace.lg, SboxSpace.xl),
                  itemCount: rows.length + (actionLabel != null && onAction != null ? 1 : 0),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == rows.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: SboxSpace.md),
                        child: SboxButton.ghost(label: actionLabel!, icon: Icons.filter_alt_rounded, onPressed: onAction),
                      );
                    }
                    final r = rows[i];
                    final ratio = maxV <= 0 ? 0.0 : (r.value / maxV).clamp(0, 1).toDouble();
                    return InkWell(
                      onTap: r.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: SboxSpace.sm),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Row(children: [
                            SizedBox(
                              width: 26,
                              child: Text('${i + 1}', style: SboxType.captionStyle(SboxColors.textMuted)),
                            ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(r.label, style: SboxType.bodyStyle(), maxLines: 2, overflow: TextOverflow.ellipsis),
                                if (r.caption != null && r.caption!.isNotEmpty)
                                  Text(tr(r.caption!), style: SboxType.captionStyle()),
                              ]),
                            ),
                            const SizedBox(width: SboxSpace.sm),
                            Text(_fmt(r), style: SboxType.titleSmStyle()),
                          ]),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 26),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: ratio,
                                minHeight: 4,
                                backgroundColor: SboxColors.slate100,
                                color: SboxColors.primary,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
