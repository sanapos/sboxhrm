import 'package:flutter/material.dart';
import '../widgets/hrm_page_chrome.dart';

/// Banner / empty state khi báo cáo lương không có dữ liệu vì NV chưa thiết lập bảng lương.
class ReportSalarySetupBanner extends StatelessWidget {
  final int notConfiguredCount;
  final VoidCallback? onOpenSalarySettings;
  final bool dense;

  const ReportSalarySetupBanner({
    super.key,
    required this.notConfiguredCount,
    this.onOpenSalarySettings,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    if (notConfiguredCount <= 0) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.fromLTRB(dense ? 8 : 12, dense ? 6 : 10, dense ? 8 : 12, 0),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: dense ? 18 : 22, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$notConfiguredCount nhân viên chưa thiết lập lương',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: dense ? 12 : 13,
                    color: const Color(0xFF9A3412),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Báo cáo lương chỉ hiển thị nhân viên đã gán bảng lương. '
                  'Vào Hồ sơ nhân sự → Thiết lập lương để cấu hình trước khi xem báo cáo.',
                  style: TextStyle(
                    fontSize: dense ? 11 : 12,
                    color: const Color(0xFFC2410C),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (onOpenSalarySettings != null) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onOpenSalarySettings,
              style: TextButton.styleFrom(
                foregroundColor: HrmPageChrome.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Thiết lập lương', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Empty state đầy đủ khi không còn NV nào đủ điều kiện (chưa thiết lập lương).
class ReportSalarySetupEmptyState extends StatelessWidget {
  final int notConfiguredCount;
  final VoidCallback? onOpenSalarySettings;

  const ReportSalarySetupEmptyState({
    super.key,
    required this.notConfiguredCount,
    this.onOpenSalarySettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text(
              'Chưa có dữ liệu tổng hợp lương',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              notConfiguredCount > 0
                  ? 'Có $notConfiguredCount nhân viên đang hoạt động nhưng chưa được gán bảng lương. '
                      'Hãy thiết lập lương trước — sau đó báo cáo mới tính được lương và xuất Excel.'
                  : 'Không có nhân viên phù hợp bộ lọc hoặc khoảng thời gian đã chọn.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.4),
              textAlign: TextAlign.center,
            ),
            if (onOpenSalarySettings != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onOpenSalarySettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Mở Thiết lập lương'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
