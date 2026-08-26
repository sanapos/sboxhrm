import 'package:flutter/material.dart';

import 'hrm_page_chrome.dart';
import '../l10n/app_tr.dart';

/// Một mục thống kê nhanh dùng cho [HrmStatBar].
class HrmStatItem {
  const HrmStatItem({
    required this.icon,
    required this.value,
    required this.label,
    this.color = HrmPageChrome.chip,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;
}

/// Thanh chip thống kê — chia đều chiều ngang, chiều cao gọn.
class HrmStatBar extends StatelessWidget {
  const HrmStatBar({
    super.key,
    required this.items,
    this.padding = const EdgeInsets.fromLTRB(12, 6, 12, 4),
    this.gap = 6,
    this.minCardWidth = 120,
    this.wideBreakpoint = 560,
    this.valueFontSize = 14,
  });

  final List<HrmStatItem> items;
  final EdgeInsetsGeometry padding;
  final double gap;
  final double minCardWidth;
  final double wideBreakpoint;
  final double valueFontSize;

  Widget _card(HrmStatItem it, {int index = 0}) {
    final accent = HrmPageChrome.chipShade(index);
    final card = HrmStatSummaryCard(
      icon: it.icon,
      value: it.value,
      label: it.label,
      subtitle: it.subtitle,
      color: accent,
      valueFontSize: valueFontSize,
    );
    if (it.onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
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
          final n = items.length;
          final minRowWidth = n * 96.0 + gap * (n - 1);
          final oneRow = n <= 1 ||
              constraints.maxWidth >= minRowWidth ||
              constraints.maxWidth >= wideBreakpoint ||
              n <= 5 && constraints.maxWidth >= 480;
          if (oneRow) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    Expanded(child: _card(items[i], index: i)),
                  ],
                ],
              ),
            );
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < n; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(
                        width: minCardWidth,
                        child: _card(items[i], index: i)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Chip trạng thái / nhãn — nền trắng, viền xanh, thấp gọn.
class HrmBrandChip extends StatelessWidget {
  const HrmBrandChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.dense = true,
    this.onDeleted,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool dense;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final border =
        selected ? HrmPageChrome.chip : HrmPageChrome.chip.withValues(alpha: 0.5);
    final fg = HrmPageChrome.chipDark;
    final padH = dense ? 7.0 : 9.0;
    final padV = dense ? 1.0 : 2.0;
    final fontSize = dense ? 11.0 : 12.0;
    final iconSize = dense ? 11.0 : 13.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: selected ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize, color: fg),
            SizedBox(width: dense ? 3 : 4),
          ],
          Text(
            tr(label),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.15,
            ),
          ),
          if (onDeleted != null) ...[
            const SizedBox(width: 2),
            InkWell(
              onTap: onDeleted,
              child: Icon(Icons.close, size: iconSize, color: fg),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact stat chip — nền trắng, viền xanh, căn giữa, thấp.
class HrmMiniStatChip extends StatelessWidget {
  const HrmMiniStatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = HrmPageChrome.chip,
    this.minWidth = 72,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final accent = HrmPageChrome.chip;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: accent, size: 16),
            const SizedBox(height: 3),
            Text(
              tr(value),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: HrmPageChrome.chipDark,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            Text(
              tr(label),
              style: const TextStyle(
                fontSize: 10,
                height: 1.15,
                color: HrmPageChrome.textMuted,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Thẻ KPI — nền trắng, viền xanh, layout ngang gọn (thấp hơn).
class HrmStatSummaryCard extends StatelessWidget {
  const HrmStatSummaryCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.color = HrmPageChrome.chip,
    this.subtitle,
    this.valueFontSize = 15,
    this.selected = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final String? subtitle;
  final double valueFontSize;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = HrmPageChrome.chip;
    final border =
        selected ? accent : accent.withValues(alpha: 0.45);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: selected ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(label),
                  style: const TextStyle(
                    color: HrmPageChrome.textMuted,
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 1),
                SizedBox(
                  width: double.infinity,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      tr(value),
                      style: TextStyle(
                        color: HrmPageChrome.chipDark,
                        fontSize: valueFontSize,
                        fontWeight: FontWeight.bold,
                        height: 1.05,
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  Text(
                    tr(subtitle!),
                    style: TextStyle(
                      color: HrmPageChrome.textMuted.withValues(alpha: 0.9),
                      fontSize: 9,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
