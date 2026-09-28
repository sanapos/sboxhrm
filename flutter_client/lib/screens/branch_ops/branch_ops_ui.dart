import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

final _money = NumberFormat('#,##0', 'vi_VN');

/// 12.500.000đ
String bMoney(num? v) => '${_money.format(v ?? 0)}đ';

/// 12,5 tr / 850 N — cho ô KPI hẹp.
String bMoneyShort(num? v) {
  final x = (v ?? 0).toDouble();
  final a = x.abs();
  if (a >= 1e9) return '${(x / 1e9).toStringAsFixed(2).replaceAll('.', ',')} tỷ';
  if (a >= 1e6) return '${(x / 1e6).toStringAsFixed(1).replaceAll('.', ',')} tr';
  if (a >= 1e3) return '${(x / 1e3).toStringAsFixed(0)} N';
  return x.toStringAsFixed(0);
}

String bQty(num? v) {
  final x = (v ?? 0).toDouble();
  return x == x.roundToDouble() ? _money.format(x) : x.toStringAsFixed(2).replaceAll('.', ',');
}

double bNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

/// Kỳ báo cáo: 7 ngày / 30 ngày / tháng này / tháng trước / tùy chọn.
class BranchPeriod {
  BranchPeriod(this.from, this.to, this.label);
  final DateTime from;
  final DateTime to;
  final String label;

  static BranchPeriod last(int days) {
    final t = _today();
    return BranchPeriod(t.subtract(Duration(days: days - 1)), t, '$days ngày');
  }

  static BranchPeriod thisMonth() {
    final t = _today();
    return BranchPeriod(DateTime(t.year, t.month, 1), t, 'Tháng này');
  }

  static BranchPeriod lastMonth() {
    final t = _today();
    return BranchPeriod(DateTime(t.year, t.month - 1, 1), DateTime(t.year, t.month, 0), 'Tháng trước');
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String get rangeText => '${DateFormat('dd/MM').format(from)} – ${DateFormat('dd/MM/yyyy').format(to)}';
}

class BranchPeriodBar extends StatelessWidget {
  const BranchPeriodBar({super.key, required this.value, required this.onChanged});
  final BranchPeriod value;
  final ValueChanged<BranchPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = [BranchPeriod.last(7), BranchPeriod.thisMonth(), BranchPeriod.last(30), BranchPeriod.lastMonth()];
    Widget chip(BranchPeriod p) {
      final sel = p.label == value.label;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          visualDensity: VisualDensity.compact,
          label: Text(tr(p.label), style: const TextStyle(fontSize: 12.5)),
          selected: sel,
          onSelected: (_) => onChanged(p),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final p in presets) chip(p),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: () async {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2023),
              lastDate: DateTime.now(),
              initialDateRange: DateTimeRange(start: value.from, end: value.to),
            );
            if (r != null) onChanged(BranchPeriod(r.start, r.end, 'Tùy chọn'));
          },
          icon: const Icon(Icons.date_range_rounded, size: 16),
          label: Text(value.rangeText, style: const TextStyle(fontSize: 12.5)),
        ),
      ]),
    );
  }
}

/// Trạng thái phiếu chuyển kho.
Color transferStatusColor(int status) => switch (status) {
      0 => SboxColors.slate500,
      1 => SboxColors.warning,
      2 => SboxColors.success,
      _ => SboxColors.danger,
    };

class TransferStatusChip extends StatelessWidget {
  const TransferStatusChip({super.key, required this.status, required this.label});
  final int status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = transferStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Text(tr(label), style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// Khung trắng bo góc cho các khối nội dung.
class BranchBox extends StatelessWidget {
  const BranchBox({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SboxColors.slate200),
      ),
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Row(children: [
            Expanded(
              child: Text(tr(title!),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
            ),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 10),
        ],
        child,
      ]),
    );
  }
}
