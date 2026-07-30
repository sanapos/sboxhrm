import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import 'pos/pos_theme.dart';

/// Thanh «Tổng quan & bộ lọc» — mặc định mở, bấm để ẩn/hiện nội dung.
class HrmCollapsibleOverview extends StatelessWidget {
  const HrmCollapsibleOverview({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.title = 'Tổng quan & bộ lọc',
    this.trailing,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = PosTheme.kiotBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr(title),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: accent,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    trailing!,
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: accent,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          child,
        ],
      ],
    );
  }
}
