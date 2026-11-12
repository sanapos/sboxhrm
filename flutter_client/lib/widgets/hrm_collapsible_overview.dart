import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import '../config/sbox_app_variant.dart';
import '../l10n/app_tr.dart';
import 'pos/pos_theme.dart';

import '../theme/sbox_tokens.dart';
/// Trạng thái mở sẵn của khung «Tổng quan & bộ lọc». SBOX BOSS trên điện thoại thu gọn:
/// mở sẵn thì các ô số chiếm gần hai màn, chủ phải cuộn mãi mới thấy danh sách.
bool get hrmOverviewDefaultOpen {
  if (!SboxAppVariant.bossApp) return true;
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return true;
  final v = views.first;
  return v.physicalSize.shortestSide / v.devicePixelRatio >= 600;
}

/// Thanh «Tổng quan & bộ lọc» — bấm để ẩn/hiện. [subtitle] hiện khi đang thu.
class HrmCollapsibleOverview extends StatelessWidget {
  const HrmCollapsibleOverview({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.title = 'Tổng quan & bộ lọc',
    this.subtitle,
    this.trailing,
    this.showHeader = true,
  });

  /// false: chỉ hiện nội dung (vd điện thoại, bộ lọc ngắn — không cần thanh gập / mở).
  final bool showHeader;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    if (!showHeader) return child;
    final accent = PosTheme.kiotBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          // BOSS: thẻ trắng trên nền ngà, không thành dải xám.
          color: SboxColors.isBoss ? SboxColors.white : accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(title),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: accent,
                          ),
                        ),
                        if (!expanded &&
                            subtitle != null &&
                            subtitle!.trim().isNotEmpty)
                          Text(
                            tr(subtitle!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: SboxColors.slate500,
                            ),
                          ),
                      ],
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
