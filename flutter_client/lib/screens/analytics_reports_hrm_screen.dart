import 'dart:math' as math;
import '../widgets/export_file_icon.dart';
import 'package:zkteco_flutter_client/theme/sbox_tokens.dart';
import 'package:flutter/material.dart';
import '../widgets/reports/report_breakdown_sheet.dart';
import '../utils/export_permission_guard.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import '../utils/report_screen_helpers.dart' show ClientPngExport;
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/sbox/sbox_ui.dart';

import 'analytics_reports_screen.dart';
/// Màn «Phân tích & báo cáo» của SBOX HRM: danh mục báo cáo chấm công, nghỉ phép, lương, hiệu suất.
/// Tách khỏi `analytics_reports_screen.dart` để bản SBOX Bán Hàng chỉ nạp phần xem báo cáo (khách lưu trú,
/// thẻ tập sắp hết hạn) mà không mang theo danh mục HRM (Apple 2.5.19).
const _attendanceModules = ['AttendanceReport', 'AttendanceSummary', 'AttendanceByShift', 'Attendance'];

const _reports = <AnalyticsReportSpec>[
  AnalyticsReportSpec('Chấm công', 'Tỷ lệ chuyên cần', 'Theo nhân viên trong tháng', '/api/reports/attendance-analytics/compliance', PeriodKind.month, _attendanceModules),
  AnalyticsReportSpec('Chấm công', 'Vắng không phép', 'Từng ngày vắng không có đơn', '/api/reports/attendance-analytics/absence', PeriodKind.range, _attendanceModules),
  AnalyticsReportSpec('Chấm công', 'Có lịch nhưng không chấm công', 'Theo ngày xếp lịch', '/api/reports/attendance-analytics/no-show', PeriodKind.range, _attendanceModules),
  AnalyticsReportSpec('Chấm công', 'Chấm công bất thường', 'Quá sớm, quá muộn, chấm nhiều lần', '/api/reports/attendance-analytics/anomalies', PeriodKind.range, _attendanceModules),
  AnalyticsReportSpec('Chấm công', 'Công tác / check-in điểm', 'Tổng hợp lượt check-in ngoài', '/api/reports/attendance-analytics/field-summary', PeriodKind.range, _attendanceModules),
  AnalyticsReportSpec('Chấm công', 'Chấm công Mobile / WiFi', 'Mức dùng chấm công điện thoại', '/api/reports/attendance-analytics/mobile-usage', PeriodKind.range, _attendanceModules),
  AnalyticsReportSpec('Nghỉ phép & ca', 'Số ngày phép còn lại', 'Theo nhân viên trong năm', '/api/reports/leave-shift/leave-balance', PeriodKind.year, ['LeaveReport']),
  AnalyticsReportSpec('Nghỉ phép & ca', 'Thời gian duyệt đơn phép', 'Người duyệt nhanh / chậm', '/api/reports/leave-shift/leave-approval-sla', PeriodKind.range, ['LeaveReport']),
  AnalyticsReportSpec('Nghỉ phép & ca', 'Độ phủ ca theo định mức', 'Thiếu / đủ / vượt người mỗi ca', '/api/reports/leave-shift/shift-coverage', PeriodKind.range, ['LeaveReport', 'WorkSchedule']),
  AnalyticsReportSpec('Nghỉ phép & ca', 'Tần suất đổi ca', 'Theo nhân viên', '/api/reports/leave-shift/shift-swaps', PeriodKind.range, ['LeaveReport']),
  AnalyticsReportSpec('Hiệu suất', 'Tổng hợp KPI', 'Theo nhân viên và phòng ban', '/api/reports/performance/kpi-summary', PeriodKind.month, ['KPI']),
  AnalyticsReportSpec('Hiệu suất', 'Sản lượng', 'Theo nhân viên và sản phẩm', '/api/reports/performance/production-output', PeriodKind.range, ['KPI']),
  AnalyticsReportSpec('Hiệu suất', 'Tài sản đang giao', 'Theo trạng thái và người giữ', '/api/reports/performance/asset-assignment', PeriodKind.none, ['KPI']),
  AnalyticsReportSpec('Tổng hợp', 'Báo cáo điều hành tháng', 'Nhân sự, chấm công, chi phí trong tháng', '/api/reports/executive/monthly-summary', PeriodKind.month, ['Report']),
  AnalyticsReportSpec('Tài chính nhân sự', 'Nợ tiền cơm', 'Theo nhân viên', '/api/reports/finance/meal-debt', PeriodKind.range, ['Meal']),
];
const _groupStyle = <String, (IconData, Color)>{
  'Chấm công': (Icons.fingerprint_rounded, SboxColors.brand500),
  'Nghỉ phép & ca': (Icons.event_available_rounded, SboxColors.violet),
  'Hiệu suất': (Icons.trending_up_rounded, SboxColors.success),
  'Tổng hợp': (Icons.dashboard_rounded, HrmPageChrome.primaryNavy),
  'Tài chính nhân sự': (Icons.account_balance_wallet_rounded, SboxColors.danger),
};
class AnalyticsReportsScreen extends StatefulWidget {
  const AnalyticsReportsScreen({super.key});

  @override
  State<AnalyticsReportsScreen> createState() => _AnalyticsReportsScreenState();
}
class _AnalyticsReportsScreenState extends State<AnalyticsReportsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final q = _q.trim().toLowerCase();
    final visible = _reports
        .where((r) => r.modules.any(perm.canView))
        .where((r) => q.isEmpty || '${r.title} ${r.subtitle} ${r.group}'.toLowerCase().contains(q))
        .toList();
    final groups = <String, List<AnalyticsReportSpec>>{};
    for (final r in visible) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      // Trong khung chính (điện thoại): thanh trên đã ghi tiêu đề — không vẽ AppBar thứ hai.
      appBar: HrmPageChrome.showInPageAppBar(context) ? AppBar(title: Text(tr('Báo cáo phân tích'))) : null,
      body: LayoutBuilder(builder: (context, cons) {
        final cols = cons.maxWidth >= 1100 ? 3 : (cons.maxWidth >= 680 ? 2 : 1);
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: tr('Tìm báo cáo…'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(child: Text(tr(q.isEmpty ? 'Không có báo cáo nào bạn được xem' : 'Không tìm thấy báo cáo'))),
              ),
            for (final g in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Row(children: [
                  Icon(_groupStyle[g.key]?.$1 ?? Icons.insert_chart_outlined,
                      size: 18, color: _groupStyle[g.key]?.$2 ?? HrmPageChrome.primaryNavy),
                  const SizedBox(width: 6),
                  Text(tr(g.key),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: SboxColors.slate900)),
                  const SizedBox(width: 6),
                  Text('${g.value.length}', style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ]),
              ),
              SboxGrid(
                columns: cols,
                spacing: 8,
                children: [for (final r in g.value) _reportTile(context, r)],
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _reportTile(BuildContext context, AnalyticsReportSpec r) {
    final color = _groupStyle[r.group]?.$2 ?? HrmPageChrome.primaryNavy;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnalyticsReportViewer(spec: r))),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SboxColors.slate200),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: SboxColors.isBoss ? SboxColors.iconBox : color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.insert_chart_outlined_rounded, color: SboxColors.isBoss ? SboxColors.iconOnBox : color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(r.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: SboxColors.slate900)),
                const SizedBox(height: 2),
                Text(tr(r.subtitle),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
          ]),
        ),
      ),
    );
  }
}
