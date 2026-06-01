import 'package:flutter/material.dart';

/// Gợi ý thống nhất cho danh sách compact trong Thiết lập HRM.
const String kHrmTapToViewHint = 'Chạm để xem chi tiết';
const String kHrmTapToEditHint = 'Chạm để xem / chỉnh sửa';
const Color kHrmTapHintColor = Color(0xFF1E3A5F);

Widget hrmListTapHint([String text = kHrmTapToViewHint]) {
  return Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      color: kHrmTapHintColor,
    ),
  );
}

/// Hàng danh sách gọn: tiêu đề + 1 dòng phụ + gợi ý chạm (tuỳ chọn).
class HrmCompactListTile extends StatelessWidget {
  const HrmCompactListTile({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.tapHint,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final String? tapHint;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF18181B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (tapHint != null && tapHint!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  hrmListTapHint(tapHint!),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );
  }
}
