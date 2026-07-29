import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Ô thống kê bấm được — áp dụng bộ lọc và highlight khi đang chọn.
class TappableStatCard extends StatelessWidget {
  const TappableStatCard({
    super.key,
    required this.child,
    this.onTap,
    this.selected = false,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(borderRadius),
            border: selected
                ? Border.all(color: const Color(0xFF1E3A5F), width: 2)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: selected ? 0.08 : 0.05),
                blurRadius: selected ? 14 : 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Banner nhỏ: đang lọc theo ô tổng kết + nút xóa lọc.
class SummaryFilterBanner extends StatelessWidget {
  const SummaryFilterBanner({
    super.key,
    required this.label,
    required this.filteredCount,
    required this.totalCount,
    required this.onClear,
  });

  final String label;
  final int filteredCount;
  final int totalCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 18, color: Color(0xFF1E3A5F)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('$label · $filteredCount/$totalCount'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A5F),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(tr('Xóa lọc')),
          ),
        ],
      ),
    );
  }
}
