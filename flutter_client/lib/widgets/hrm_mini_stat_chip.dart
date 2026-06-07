import 'package:flutter/material.dart';

/// Một mục thống kê nhanh dùng cho [HrmStatBar].
class HrmStatItem {
  const HrmStatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback? onTap;
}

/// Thanh chip "tổng kết nhanh" THỐNG NHẤT cho mọi màn:
/// - Màn rộng (>= [wideBreakpoint]): các chip chia ĐỀU theo [Expanded].
/// - Màn hẹp: cuộn ngang, mỗi chip rộng tối thiểu [minCardWidth].
/// Mỗi chip dùng [HrmStatSummaryCard] để đồng nhất kích thước/typography.
class HrmStatBar extends StatelessWidget {
  const HrmStatBar({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 4),
    this.gap = 10,
    this.minCardWidth = 124,
    this.wideBreakpoint = 560,
    this.valueFontSize = 20,
  });

  final List<HrmStatItem> items;
  final EdgeInsetsGeometry padding;
  final double gap;
  final double minCardWidth;
  final double wideBreakpoint;
  final double valueFontSize;

  Widget _card(HrmStatItem it) {
    final card = HrmStatSummaryCard(
      icon: it.icon,
      value: it.value,
      label: it.label,
      color: it.color,
      valueFontSize: valueFontSize,
    );
    if (it.onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: it.onTap,
      child: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= wideBreakpoint;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: _card(items[i])),
                ],
              ],
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(width: minCardWidth, child: _card(items[i])),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Compact stat chip for HRM setup toolbars: icon → value → label (vertical).
class HrmMiniStatChip extends StatelessWidget {
  const HrmMiniStatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.minWidth = 72,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                height: 1.15,
                color: color.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Larger stat card for HRM setup summary rows (e.g. phụ cấp, lương).
class HrmStatSummaryCard extends StatelessWidget {
  const HrmStatSummaryCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.valueFontSize = 20,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final double valueFontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF71717A),
              fontSize: 11,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
