import 'package:flutter/material.dart';
import '../utils/export_permission_guard.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';

import '../widgets/sbox/sbox_ui.dart';
/// Kiểu tham số kỳ của báo cáo.
enum _PeriodKind { range, month, year, none }

class _ReportSpec {
  final String group;
  final String title;
  final String subtitle;
  final String path;
  final _PeriodKind period;
  final List<String> modules; // cần quyền Xem ít nhất một module
  const _ReportSpec(this.group, this.title, this.subtitle, this.path, this.period, this.modules);
}

const _attendanceModules = ['AttendanceReport', 'AttendanceSummary', 'AttendanceByShift', 'Attendance'];

/// Các báo cáo phân tích có sẵn trên máy chủ nhưng trước đây chưa có màn xem.
const _reports = <_ReportSpec>[
  _ReportSpec('Chấm công', 'Tỷ lệ chuyên cần', 'Theo nhân viên trong tháng', '/api/reports/attendance-analytics/compliance', _PeriodKind.month, _attendanceModules),
  _ReportSpec('Chấm công', 'Vắng không phép', 'Từng ngày vắng không có đơn', '/api/reports/attendance-analytics/absence', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Có lịch nhưng không chấm công', 'Theo ngày xếp lịch', '/api/reports/attendance-analytics/no-show', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Chấm công bất thường', 'Quá sớm, quá muộn, chấm nhiều lần', '/api/reports/attendance-analytics/anomalies', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Công tác / check-in điểm', 'Tổng hợp lượt check-in ngoài', '/api/reports/attendance-analytics/field-summary', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Chấm công Mobile / WiFi', 'Mức dùng chấm công điện thoại', '/api/reports/attendance-analytics/mobile-usage', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Nghỉ phép & ca', 'Số ngày phép còn lại', 'Theo nhân viên trong năm', '/api/reports/leave-shift/leave-balance', _PeriodKind.year, ['LeaveReport']),
  _ReportSpec('Nghỉ phép & ca', 'Thời gian duyệt đơn phép', 'Người duyệt nhanh / chậm', '/api/reports/leave-shift/leave-approval-sla', _PeriodKind.range, ['LeaveReport']),
  _ReportSpec('Nghỉ phép & ca', 'Độ phủ ca theo định mức', 'Thiếu / đủ / vượt người mỗi ca', '/api/reports/leave-shift/shift-coverage', _PeriodKind.range, ['LeaveReport', 'WorkSchedule']),
  _ReportSpec('Nghỉ phép & ca', 'Tần suất đổi ca', 'Theo nhân viên', '/api/reports/leave-shift/shift-swaps', _PeriodKind.range, ['LeaveReport']),
  _ReportSpec('Hiệu suất', 'Tổng hợp KPI', 'Theo nhân viên và phòng ban', '/api/reports/performance/kpi-summary', _PeriodKind.month, ['KPI']),
  _ReportSpec('Hiệu suất', 'Sản lượng', 'Theo nhân viên và sản phẩm', '/api/reports/performance/production-output', _PeriodKind.range, ['KPI']),
  _ReportSpec('Hiệu suất', 'Tài sản đang giao', 'Theo trạng thái và người giữ', '/api/reports/performance/asset-assignment', _PeriodKind.none, ['KPI']),
  _ReportSpec('Tổng hợp', 'Báo cáo điều hành tháng', 'Nhân sự, chấm công, chi phí trong tháng', '/api/reports/executive/monthly-summary', _PeriodKind.month, ['Report']),
  _ReportSpec('Khách sạn', 'Sổ khách lưu trú', 'Khách ở trong kỳ — xuất Excel khai báo tạm trú', '/api/pos/stay-guests/register', _PeriodKind.range, ['PosSell']),
  _ReportSpec('Gym / Spa', 'Thẻ tập & gói buổi sắp hết hạn', 'Sắp hết hạn 7 ngày, hết hạn 30 ngày, còn ≤ 2 buổi — gọi nhắc gia hạn', '/api/pos/session-balances/expiring', _PeriodKind.none, ['PosSell']),
  _ReportSpec('Tài chính nhân sự', 'Nợ tiền cơm', 'Theo nhân viên', '/api/reports/finance/meal-debt', _PeriodKind.range, ['Meal']),
];

/// Icon + màu theo nhóm báo cáo.
const _groupStyle = <String, (IconData, Color)>{
  'Chấm công': (Icons.fingerprint_rounded, SboxColors.brand500),
  'Nghỉ phép & ca': (Icons.event_available_rounded, SboxColors.violet),
  'Hiệu suất': (Icons.trending_up_rounded, SboxColors.success),
  'Tổng hợp': (Icons.dashboard_rounded, HrmPageChrome.primaryNavy),
  'Khách sạn': (Icons.hotel_rounded, SboxColors.info),
  'Gym / Spa': (Icons.fitness_center_rounded, SboxColors.warning),
  'Tài chính nhân sự': (Icons.account_balance_wallet_rounded, SboxColors.danger),
};

/// Danh sách báo cáo phân tích (lọc theo quyền) — lưới thẻ theo nhóm, có ô tìm.
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
    final groups = <String, List<_ReportSpec>>{};
    for (final r in visible) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(title: Text(tr('Báo cáo phân tích'))),
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

  Widget _reportTile(BuildContext context, _ReportSpec r) {
    final color = _groupStyle[r.group]?.$2 ?? HrmPageChrome.primaryNavy;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AnalyticsReportViewer(spec: r))),
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
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.insert_chart_outlined_rounded, color: color, size: 20),
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

/// Nhãn tiếng Việt cho khóa hay gặp; khóa lạ hiển thị dạng tách chữ.
const _labels = <String, String>{
  'employeeCode': 'Mã NV', 'employeeName': 'Nhân viên', 'department': 'Phòng ban',
  'date': 'Ngày', 'scheduledDate': 'Ngày xếp lịch', 'dayOfWeek': 'Thứ', 'from': 'Từ ngày', 'to': 'Đến ngày',
  'shiftName': 'Ca', 'status': 'Trạng thái', 'count': 'Số lượng', 'total': 'Tổng', 'amount': 'Số tiền',
  'totalNoShows': 'Tổng lượt vắng', 'workDays': 'Ngày công', 'scheduledDays': 'Ngày có lịch',
  'presentDays': 'Ngày có mặt', 'absentDays': 'Ngày vắng', 'lateCount': 'Số lần trễ', 'lateMinutes': 'Phút trễ',
  'earlyCount': 'Số lần về sớm', 'earlyMinutes': 'Phút về sớm', 'complianceRate': 'Tỷ lệ chuyên cần (%)',
  'minRequired': 'Tối thiểu', 'maxAllowed': 'Tối đa', 'registered': 'Đã xếp', 'gap': 'Còn thiếu',
  'underCount': 'Số ca thiếu', 'okCount': 'Số ca đạt', 'overCount': 'Số ca vượt',
  'entitled': 'Phép được hưởng', 'used': 'Đã dùng', 'remaining': 'Còn lại', 'pending': 'Chờ duyệt',
  'approverName': 'Người duyệt', 'avgHours': 'TB giờ duyệt', 'score': 'Điểm', 'target': 'Mục tiêu',
  'actual': 'Thực tế', 'productName': 'Sản phẩm', 'quantity': 'Số lượng', 'assetName': 'Tài sản',
  'assetCode': 'Mã tài sản', 'assignedTo': 'Người giữ', 'reason': 'Lý do', 'note': 'Ghi chú',
  'items': 'Chi tiết', 'byEmployee': 'Theo nhân viên', 'byDepartment': 'Theo phòng ban',
  'byProduct': 'Theo sản phẩm', 'byStatus': 'Theo trạng thái', 'assignments': 'Đang giao',
  'topPerformers': 'Dẫn đầu', 'approvers': 'Theo người duyệt', 'debt': 'Còn nợ', 'paid': 'Đã trả',
  'customerName': 'Khách hàng', 'phone': 'Điện thoại', 'packageName': 'Thẻ / gói', 'kind': 'Loại',
  'usedSessions': 'Đã dùng', 'remainingSessions': 'Còn lại', 'expiresAt': 'Hết hạn', 'daysLeft': 'Còn (ngày)',
  'lastUsedAt': 'Lần tập cuối', 'renewed': 'Đã gia hạn', 'expiringCount': 'Sắp hết hạn',
  'expiredCount': 'Đã hết hạn', 'lowSessionsCount': 'Sắp hết buổi', 'renewedCount': 'Đã gia hạn',
  // ── Chấm công ──
  'standardDays': 'Ngày công chuẩn', 'lateDays': 'Ngày đi trễ', 'leaveDays': 'Ngày nghỉ phép',
  'avgComplianceRate': 'TB chuyên cần (%)', 'totalEmployees': 'Tổng nhân viên', 'absenceDate': 'Ngày vắng',
  'totalAbsenceRecords': 'Tổng lượt vắng', 'affectedEmployees': 'Nhân viên bị ảnh hưởng',
  'firstPunch': 'Chấm đầu tiên', 'lastPunch': 'Chấm cuối cùng', 'punchCount': 'Số lần chấm', 'issues': 'Bất thường',
  'checkIns': 'Lượt check-in', 'faceGpsCount': 'Khuôn mặt / GPS', 'wifiCount': 'WiFi', 'rejectedCount': 'Bị từ chối',
  'pendingCount': 'Chờ duyệt', 'deviceCount': 'Số thiết bị', 'totalCount': 'Tổng số', 'checkInCount': 'Lượt vào',
  'checkOutCount': 'Lượt ra', 'pin': 'Mã chấm công', 'locationName': 'Địa điểm', 'location': 'Địa điểm',
  // ── Nghỉ phép & ca ──
  'paidEntitlement': 'Phép năm được hưởng', 'paidUsed': 'Phép năm đã dùng', 'paidRemaining': 'Phép năm còn lại',
  'unpaidUsed': 'Nghỉ không lương', 'sickUsed': 'Nghỉ ốm', 'otherUsed': 'Nghỉ khác', 'usagePercent': 'Tỷ lệ đã dùng (%)',
  'year': 'Năm', 'month': 'Tháng', 'approvalDate': 'Ngày duyệt', 'approved': 'Đã duyệt', 'rejected': 'Từ chối',
  'cancelled': 'Đã hủy', 'avgResponseHours': 'TB giờ phản hồi', 'totalRequests': 'Tổng đơn', 'approvalRate': 'Tỷ lệ duyệt (%)',
  'rejectionRate': 'Tỷ lệ từ chối (%)', 'avgResolutionHours': 'TB giờ xử lý', 'minEmployees': 'Tối thiểu (người)',
  'maxEmployees': 'Tối đa (người)', 'totalRequested': 'Tổng yêu cầu', 'totalSwaps': 'Tổng lượt đổi ca',
  'totalApproved': 'Tổng đã duyệt', 'totalRejected': 'Tổng từ chối',
  // ── Hiệu suất / KPI / sản lượng / tài sản ──
  'periodName': 'Kỳ', 'periodStart': 'Bắt đầu kỳ', 'periodEnd': 'Kết thúc kỳ', 'avgCompletion': 'TB hoàn thành (%)',
  'kpiCount': 'Số chỉ tiêu', 'kpiCode': 'Mã KPI', 'kpiName': 'Chỉ tiêu KPI', 'totalScore': 'Tổng điểm',
  'details': 'Chi tiết', 'code': 'Mã', 'name': 'Tên', 'completionPercent': 'Hoàn thành (%)',
  'weightedScore': 'Điểm có trọng số', 'employeeCount': 'Số nhân viên', 'avgScore': 'Điểm TB',
  'totalEntries': 'Tổng lượt nhập', 'totalQuantity': 'Tổng sản lượng', 'totalAmount': 'Tổng tiền',
  'daysWorked': 'Ngày làm', 'avgDailyQuantity': 'TB sản lượng/ngày', 'productCode': 'Mã sản phẩm', 'unit': 'Đơn vị',
  'totalAssets': 'Tổng tài sản', 'assignedCount': 'Đang giao', 'inStockCount': 'Trong kho', 'brokenCount': 'Hỏng',
  'lostCount': 'Mất', 'disposedCount': 'Đã thanh lý', 'totalValue': 'Tổng giá trị', 'brand': 'Thương hiệu',
  'serialNumber': 'Số serial', 'assignedDate': 'Ngày giao', 'currentValue': 'Giá trị hiện tại',
  // ── Điều hành tháng ──
  'headcount': 'Nhân sự', 'attendance': 'Chấm công', 'leave': 'Nghỉ phép', 'payroll': 'Bảng lương', 'finance': 'Tài chính',
  'atMonthStart': 'Đầu tháng', 'atMonthEnd': 'Cuối tháng', 'hired': 'Tuyển mới', 'resigned': 'Nghỉ việc',
  'netChange': 'Tăng / giảm', 'turnoverRatePercent': 'Tỷ lệ nghỉ việc (%)', 'totalPunches': 'Tổng lượt chấm',
  'uniqueManDays': 'Ngày công thực tế', 'avgPunchesPerDay': 'TB lượt chấm/ngày', 'approvedLeaves': 'Đơn phép đã duyệt',
  'pendingLeaves': 'Đơn phép chờ duyệt', 'payslipCount': 'Số phiếu lương', 'totalGross': 'Tổng lương gộp',
  'totalNet': 'Tổng thực lĩnh', 'totalOvertime': 'Tổng tăng ca', 'totalBonus': 'Tổng thưởng',
  'otRatioPercent': 'Tỷ lệ tăng ca (%)', 'penaltyApproved': 'Tiền phạt đã duyệt', 'advanceApproved': 'Tạm ứng đã duyệt',
  'advanceOutstanding': 'Tạm ứng chưa trừ', 'mealCharge': 'Tiền cơm phát sinh', 'mealPayment': 'Tiền cơm đã thu',
  'mealOutstanding': 'Tiền cơm còn nợ',
  // ── Tài chính nhân sự ──
  'totalTickets': 'Tổng phiếu', 'approvedAmount': 'Tiền đã duyệt', 'cancelledAmount': 'Tiền đã hủy', 'byType': 'Theo loại',
  'type': 'Loại', 'avgAmount': 'TB số tiền', 'ticketCount': 'Số phiếu', 'forgotCount': 'Quên chấm', 'otherCount': 'Khác',
  'pendingAmount': 'Tiền chờ duyệt', 'approvedUnpaid': 'Đã duyệt chưa chi', 'paidAmount': 'Đã chi',
  'rejectedAmount': 'Tiền bị từ chối', 'totalPaid': 'Tổng đã chi', 'outstandingDebt': 'Còn nợ', 'totalCases': 'Tổng hồ sơ',
  'pendingAdvanceCases': 'Chờ tạm ứng', 'pendingSettlementCases': 'Chờ quyết toán', 'closedCases': 'Đã đóng',
  'totalAdvanceAmount': 'Tổng tạm ứng', 'totalSettledAmount': 'Tổng quyết toán', 'totalBalanceAmount': 'Tổng chênh lệch',
  'totalWithInvoice': 'Có hóa đơn', 'totalWithoutInvoice': 'Không hóa đơn', 'expenseLineCount': 'Số khoản chi',
  'byCategory': 'Theo khoản mục', 'caseCode': 'Mã hồ sơ', 'title': 'Tiêu đề', 'destination': 'Nơi đến',
  'statusLabel': 'Trạng thái', 'advanceAmount': 'Tạm ứng', 'settledAmount': 'Quyết toán', 'balanceAmount': 'Chênh lệch',
  'tripFromDate': 'Đi từ ngày', 'tripToDate': 'Đến ngày', 'createdAt': 'Ngày tạo', 'advanceIsPaid': 'Đã chi tạm ứng',
  'advanceStatus': 'Trạng thái tạm ứng', 'settlementStatus': 'Trạng thái quyết toán', 'settlementType': 'Hình thức quyết toán',
  'hasUncategorizedExpense': 'Có khoản chưa phân loại', 'totalAdvance': 'Tổng tạm ứng', 'totalSettled': 'Tổng quyết toán',
  'totalBalance': 'Tổng chênh lệch', 'pendingAdvance': 'Chờ tạm ứng', 'pendingSettlement': 'Chờ quyết toán',
  'categoryCode': 'Mã khoản mục', 'categoryName': 'Khoản mục', 'lineCount': 'Số dòng', 'caseCount': 'Số hồ sơ',
  'withInvoiceAmount': 'Có hóa đơn', 'withoutInvoiceAmount': 'Không hóa đơn', 'percentage': 'Tỷ lệ (%)', 'period': 'Kỳ',
  'totalCharge': 'Tổng phát sinh', 'totalPayment': 'Tổng đã trả', 'totalOutstanding': 'Tổng còn nợ',
  'lastTransactionDate': 'Giao dịch gần nhất', 'pendingItems': 'Chờ xử lý', 'summary': 'Tổng quan',
  'paidIncome': 'Đã thu', 'paidExpense': 'Đã chi', 'paidIncomeCount': 'Số phiếu thu', 'paidExpenseCount': 'Số phiếu chi',
  'pendingIncome': 'Thu chờ duyệt', 'pendingExpense': 'Chi chờ duyệt', 'pendingIncomeCount': 'Phiếu thu chờ',
  'pendingExpenseCount': 'Phiếu chi chờ', 'cancelledCount': 'Đã hủy', 'transactionCode': 'Mã phiếu',
  'transactionDate': 'Ngày giao dịch', 'description': 'Diễn giải', 'paymentMethod': 'Hình thức', 'isPaid': 'Đã thanh toán',
  'createdByUserName': 'Người tạo', 'page': 'Trang', 'pageSize': 'Số dòng/trang',
  // ── Khách lưu trú / thẻ tập ──
  'guestName': 'Khách', 'fullName': 'Họ tên', 'idNumber': 'Số giấy tờ', 'idType': 'Loại giấy tờ', 'nationality': 'Quốc tịch',
  'roomName': 'Phòng', 'roomCode': 'Mã phòng', 'checkInAt': 'Nhận phòng', 'checkOutAt': 'Trả phòng', 'birthDate': 'Ngày sinh',
  'gender': 'Giới tính', 'address': 'Địa chỉ', 'totalSessions': 'Tổng buổi', 'startDate': 'Từ ngày', 'endDate': 'Đến ngày',
};

/// Từ điển từng từ để dịch tên cột lạ (không có trong [_labels]) — tránh lộ chữ tiếng Anh.
const _words = <String, String>{
  'total': 'tổng', 'count': 'số lượng', 'amount': 'số tiền', 'avg': 'TB', 'average': 'TB', 'max': 'tối đa',
  'min': 'tối thiểu', 'days': 'ngày', 'day': 'ngày', 'hours': 'giờ', 'hour': 'giờ', 'minutes': 'phút',
  'minute': 'phút', 'date': 'ngày', 'time': 'giờ', 'rate': 'tỷ lệ', 'percent': '%', 'ratio': 'tỷ lệ',
  'employee': 'nhân viên', 'employees': 'nhân viên', 'name': 'tên', 'code': 'mã', 'status': 'trạng thái',
  'late': 'đi trễ', 'early': 'về sớm', 'absent': 'vắng', 'absence': 'vắng', 'present': 'có mặt', 'leave': 'nghỉ phép',
  'leaves': 'đơn nghỉ', 'sick': 'ốm', 'paid': 'đã trả', 'unpaid': 'chưa trả', 'approved': 'đã duyệt',
  'rejected': 'từ chối', 'pending': 'chờ duyệt', 'cancelled': 'đã hủy', 'request': 'yêu cầu', 'requests': 'yêu cầu',
  'shift': 'ca', 'shifts': 'ca', 'swap': 'đổi ca', 'swaps': 'đổi ca', 'punch': 'lượt chấm', 'punches': 'lượt chấm',
  'check': 'chấm', 'in': 'vào', 'out': 'ra', 'device': 'thiết bị', 'devices': 'thiết bị', 'department': 'phòng ban',
  'branch': 'chi nhánh', 'store': 'cửa hàng', 'salary': 'lương', 'gross': 'lương gộp', 'net': 'thực lĩnh',
  'bonus': 'thưởng', 'overtime': 'tăng ca', 'ot': 'tăng ca', 'penalty': 'phạt', 'advance': 'tạm ứng',
  'meal': 'cơm', 'debt': 'nợ', 'outstanding': 'còn nợ', 'charge': 'phát sinh', 'payment': 'đã trả', 'income': 'thu',
  'expense': 'chi', 'cost': 'chi phí', 'price': 'giá', 'value': 'giá trị', 'quantity': 'số lượng', 'qty': 'số lượng',
  'product': 'sản phẩm', 'asset': 'tài sản', 'assets': 'tài sản', 'score': 'điểm', 'target': 'mục tiêu',
  'actual': 'thực tế', 'completion': 'hoàn thành', 'records': 'lượt', 'record': 'lượt', 'entries': 'lượt',
  'first': 'đầu', 'last': 'cuối', 'start': 'bắt đầu', 'end': 'kết thúc', 'from': 'từ', 'to': 'đến', 'new': 'mới',
  'used': 'đã dùng', 'remaining': 'còn lại', 'entitlement': 'được hưởng', 'invoice': 'hóa đơn', 'case': 'hồ sơ',
  'cases': 'hồ sơ', 'category': 'khoản mục', 'type': 'loại', 'items': 'chi tiết', 'by': 'theo', 'per': '/',
  'unique': 'riêng', 'man': 'người', 'month': 'tháng', 'year': 'năm', 'week': 'tuần', 'no': 'không', 'show': 'có mặt',
  'shows': 'lượt', 'mobile': 'di động', 'wifi': 'WiFi', 'face': 'khuôn mặt', 'gps': 'GPS', 'field': 'hiện trường',
  'is': '', 'has': 'có', 'of': '', 'and': 'và', 'with': 'có', 'without': 'không', 'id': 'mã', 'user': 'người dùng',
};

String _label(String key) {
  final k = _labels[key] ?? _labels[key.isEmpty ? key : key[0].toLowerCase() + key.substring(1)];
  // Giá trị % đã có ký hiệu «%» → nhãn bỏ « (%)» cho gọn.
  if (k != null) return k.replaceAll(' (%)', '');
  // Dự phòng: tách camelCase và dịch từng từ.
  final parts = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(RegExp(r'[\s_]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => _words[p.toLowerCase()] ?? p)
      .where((p) => p.isNotEmpty)
      .toList();
  final s = parts.join(' ');
  return s.isEmpty ? key : s[0].toUpperCase() + s.substring(1);
}

/// Giá trị chữ tiếng Anh hay gặp (enum trạng thái) → tiếng Việt.
const _valueVi = <String, String>{
  'pending': 'Chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Từ chối', 'cancelled': 'Đã hủy', 'canceled': 'Đã hủy',
  'completed': 'Hoàn thành', 'active': 'Đang hoạt động', 'inactive': 'Ngưng hoạt động', 'assigned': 'Đang giao',
  'instock': 'Trong kho', 'in_stock': 'Trong kho', 'available': 'Sẵn sàng', 'broken': 'Hỏng', 'lost': 'Mất',
  'disposed': 'Đã thanh lý', 'maintenance': 'Bảo trì', 'under': 'Thiếu người', 'ok': 'Đủ', 'over': 'Vượt',
  'checkin': 'Vào', 'checkout': 'Ra', 'income': 'Thu', 'expense': 'Chi', 'cash': 'Tiền mặt', 'transfer': 'Chuyển khoản',
  'banktransfer': 'Chuyển khoản', 'late': 'Đi trễ', 'early': 'Về sớm', 'forgot': 'Quên chấm', 'other': 'Khác',
  'paid': 'Đã trả', 'unpaid': 'Chưa trả', 'draft': 'Nháp', 'closed': 'Đã đóng', 'open': 'Đang mở',
  'annualleave': 'Phép năm', 'sickleave': 'Nghỉ ốm', 'personalpaid': 'Phép có lương', 'personalunpaid': 'Phép không lương',
  'maternityleave': 'Thai sản', 'compensatoryleave': 'Nghỉ bù', 'holiday': 'Nghỉ lễ', 'male': 'Nam', 'female': 'Nữ',
  'monday': 'Thứ 2', 'tuesday': 'Thứ 3', 'wednesday': 'Thứ 4', 'thursday': 'Thứ 5', 'friday': 'Thứ 6',
  'saturday': 'Thứ 7', 'sunday': 'Chủ nhật', 'true': 'Có', 'false': 'Không',
};

bool _isScalar(dynamic v) => v == null || v is num || v is String || v is bool;

/// Cột dùng làm tên dòng (biểu đồ xếp hạng, cột đầu bảng) — tên người / vật, không dùng mã.
const _nameKeys = [
  'employeeName', 'approverName', 'fullName', 'guestName', 'customerName', 'productName', 'assetName',
  'categoryName', 'shiftName', 'name', 'title', 'department', 'type', 'status',
];

/// Cột mã — gộp dưới tên (dòng phụ), không làm cột riêng / nhãn biểu đồ.
const _codeKeys = {'employeeCode', 'productCode', 'assetCode', 'categoryCode', 'code', 'pin', 'caseCode'};

/// Số liệu chính để xếp hạng, theo thứ tự ưu tiên (số giống nhau cho mọi dòng như «ngày công chuẩn» không xếp hạng).
const _rankKeys = [
  'complianceRate', 'outstandingDebt', 'totalOutstanding', 'paidRemaining', 'usagePercent', 'totalScore',
  'avgCompletion', 'avgScore', 'totalQuantity', 'totalAmount', 'totalVisits', 'totalPunches', 'totalRequested',
  'avgResponseHours', 'ticketCount', 'totalCases', 'balanceAmount', 'currentValue', 'gap', 'count', 'total',
];

/// Số liệu tổng không cần hiện thành thẻ (đã có ở tiêu đề kỳ).
const _hiddenScalars = {'year', 'month', 'page', 'pageSize', 'periodId', 'totalCount'};

/// Tỷ lệ % — xếp hạng thêm chiều «thấp nhất», thanh tính trên mốc 100.
bool _isPercentKey(String k) => RegExp('rate|percent', caseSensitive: false).hasMatch(k);

class _AnalyticsReportViewer extends StatefulWidget {
  final _ReportSpec spec;
  const _AnalyticsReportViewer({required this.spec});

  @override
  State<_AnalyticsReportViewer> createState() => _AnalyticsReportViewerState();
}

class _AnalyticsReportViewerState extends State<_AnalyticsReportViewer> {
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _num = NumberFormat('#,##0.##', 'vi_VN');
  late DateTime _from;
  late DateTime _to;
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _data = const {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  Map<String, String> get _params {
    final iso = DateFormat('yyyy-MM-dd');
    return switch (widget.spec.period) {
      _PeriodKind.range => {'from': iso.format(_from), 'to': iso.format(_to)},
      _PeriodKind.month => {'year': '${_from.year}', 'month': '${_from.month}'},
      _PeriodKind.year => {'year': '${_from.year}'},
      _PeriodKind.none => {},
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getAnalyticsReport(widget.spec.path, _params);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được báo cáo');
      }
    });
  }

  Future<void> _pickPeriod() async {
    if (widget.spec.period == _PeriodKind.range) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 60)),
        initialDateRange: DateTimeRange(start: _from, end: _to),
      );
      if (r == null) return;
      _from = r.start;
      _to = r.end;
    } else {
      final d = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDate: _from,
        helpText: widget.spec.period == _PeriodKind.year ? tr('Chọn năm (ngày bất kỳ)') : tr('Chọn tháng (ngày bất kỳ)'),
      );
      if (d == null) return;
      _from = d;
    }
    await _load();
  }

  String get _periodLabel => switch (widget.spec.period) {
        _PeriodKind.range => '${_dateFmt.format(_from)} – ${_dateFmt.format(_to)}',
        _PeriodKind.month => 'Tháng ${_from.month}/${_from.year}',
        _PeriodKind.year => 'Năm ${_from.year}',
        _PeriodKind.none => 'Hiện tại',
      };

  Future<void> _excel() async {
    if (!ensureCanExport(context, 'AttendanceReport')) return;
    final res = await _api.downloadAnalyticsReportExcel(widget.spec.path, _params);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Không xuất được Excel', message: res['message']?.toString() ?? '');
      return;
    }
    await saveAndOpenFileBytes(
      List<int>.from(res['data'] as List),
      '${widget.spec.title.replaceAll(' ', '_')}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  String _fmt(String key, dynamic v) {
    if (v == null) return '';
    if (v is bool) return v ? tr('Có') : tr('Không');
    if (v is num) return _isPercentKey(key) ? '${_num.format(v)}%' : _num.format(v);
    final s = v.toString();
    final vi = _valueVi[s.trim().toLowerCase()];
    if (vi != null) return vi;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) {
      final d = DateTime.tryParse(s);
      if (d != null) {
        return d.hour == 0 && d.minute == 0
            ? _dateFmt.format(d)
            : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
      }
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final scalars = _data.entries
        .where((e) => _isScalar(e.value) && e.key != 'from' && e.key != 'to' && !_hiddenScalars.contains(e.key))
        .toList();
    final blocks = _data.entries.where((e) => e.value is Map).toList();
    final lists = _data.entries.where((e) => e.value is List && (e.value as List).isNotEmpty).toList();
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: Text(tr(widget.spec.title)),
        actions: [
          IconButton(
            tooltip: tr('Xuất Excel'),
            onPressed: _loading || _error != null ? null : _excel,
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(tooltip: tr('Tải lại'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(tr(widget.spec.subtitle),
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle()),
            ),
            if (widget.spec.period != _PeriodKind.none) ...[
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: _loading ? null : _pickPeriod,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(tr(_periodLabel), style: const TextStyle(fontSize: 12.5)),
              ),
            ],
          ]),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SboxEmptyState(icon: Icons.cloud_off_rounded, title: 'Không tải được báo cáo', message: _error)
          else ...[
            if (scalars.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SboxKpiStrip(items: [
                  for (final e in scalars.take(12))
                    SboxKpi(
                      label: _label(e.key),
                      value: _fmt(e.key, e.value),
                      tone: SboxTone.values[1 + scalars.indexOf(e) % (SboxTone.values.length - 1)],
                    ),
                ]),
              ),
            if (lists.isNotEmpty) ...[
              for (final c in [
                for (final l in lists.take(2)) ..._autoCharts(l.key, (l.value as List).whereType<Map>().toList()),
              ])
                Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
            ],
            for (final b in blocks)
              _kpis((b.value as Map).entries
                  .where((e) => _isScalar(e.value))
                  .map((e) => MapEntry('${e.key}', e.value))
                  .toList(), title: _label(b.key)),
            if (lists.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Lọc theo tên, mã, phòng ban...'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            for (final l in lists) _table(l.key, (l.value as List).whereType<Map>().toList()),
            if (scalars.isEmpty && blocks.isEmpty && lists.isEmpty)
              Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('Không có dữ liệu trong kỳ')))),
          ],
        ],
      ),
    );
  }

  Widget _kpis(List<MapEntry<String, dynamic>> items, {String? title}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text(tr(title), style: SboxType.titleSmStyle()),
            ),
          SboxKpiStrip(items: [
            for (final e in items) SboxKpi(label: _label(e.key), value: _fmt(e.key, e.value)),
          ]),
        ]),
      );

  bool _isDateText(dynamic v) => v is String && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v);

  /// Tên hiển thị của 1 dòng: tên người / vật; trống thì mới dùng mã.
  String? _nameKey(List<Map> rows) {
    for (final k in _nameKeys) {
      if (rows.take(20).any((r) => '${r[k] ?? ''}'.trim().isNotEmpty)) return k;
    }
    return null;
  }

  String? _codeKey(List<Map> rows) =>
      _codeKeys.where((k) => rows.take(20).any((r) => '${r[k] ?? ''}'.trim().isNotEmpty)).firstOrNull;

  String _rowName(Map r, String? nameKey, String? codeKey) {
    final n = nameKey == null ? '' : '${r[nameKey] ?? ''}'.trim();
    if (n.isNotEmpty) return n;
    final c = codeKey == null ? '' : '${r[codeKey] ?? ''}'.trim();
    return c.isEmpty ? '—' : c;
  }

  /// Tự chọn biểu đồ cho một danh sách:
  /// có cột ngày → số lượt theo ngày; có tên → xếp hạng theo số liệu chính (tỷ lệ % thêm «thấp nhất»).
  List<Widget> _autoCharts(String key, List<Map> rows) {
    if (rows.length < 2) return const [];
    final sample = rows.take(30).toList();
    final keys = <String>{for (final r in sample) for (final k in r.keys) '$k'}
        .where((k) => !k.toLowerCase().endsWith('id'))
        .toList();
    bool mostly(String k, bool Function(dynamic) f) => sample.where((r) => f(r[k])).length >= sample.length * 0.7;
    final nums = keys.where((k) => mostly(k, (v) => v is num && v is! bool)).toList();
    // Bỏ số giống hệt nhau ở mọi dòng (vd ngày công chuẩn) — xếp hạng vô nghĩa.
    bool varies(String k) => rows.map((r) => r[k]).toSet().length > 1;
    final dateKey = keys.where((k) => mostly(k, _isDateText)).firstOrNull;
    final nameKey = _nameKey(rows);
    final codeKey = _codeKey(rows);

    // Danh sách từng sự việc theo ngày (vắng, bất thường…) → đếm lượt mỗi ngày.
    if (dateKey != null) {
      final byDay = <String, double>{};
      for (final r in rows) {
        final d = '${r[dateKey]}'.substring(0, 10);
        byDay[d] = (byDay[d] ?? 0) + 1;
      }
      if (byDay.length < 2 || byDay.length > 62) return const [];
      final days = byDay.keys.toList()..sort();
      return [
        SboxChartCard(
          title: 'Số lượt theo ${tr(_label(dateKey)).toLowerCase()}',
          subtitle: key == 'items' ? tr(widget.spec.subtitle) : tr(_label(key)),
          child: SboxBarChart(
            valueFormat: SboxFmt.number,
            axisFormat: (v) => SboxFmt.compact(v),
            labels: [for (final d in days) sboxDayLabel(d)],
            series: [SboxSeries(name: 'Số lượt', values: [for (final d in days) byDay[d]!])],
          ),
        ),
      ];
    }
    if (nameKey == null) return const [];
    final candidates = nums.where(varies).toList();
    if (candidates.isEmpty) return const [];
    final valueKey = _rankKeys.firstWhere(candidates.contains, orElse: () => candidates.first);
    final percent = _isPercentKey(valueKey);
    final money = !percent && RegExp('revenue|amount|salary|profit|net|debt|outstanding|charge|value|price|cost', caseSensitive: false).hasMatch(valueKey);
    String fmtV(num? v) => percent ? '${SboxFmt.number(v)}%' : (money ? SboxFmt.money(v) : SboxFmt.number(v));
    final label = tr(_label(valueKey));
    // «Chi tiết» (khóa items) không nói gì — dùng mô tả báo cáo.
    final sub = key == 'items' ? tr(widget.spec.subtitle) : tr(_label(key));
    // Ít dòng: 1 bảng xếp hạng là đủ; nhiều dòng + tỷ lệ %: thêm «thấp nhất» để thấy ai cần nhắc.
    final both = percent && rows.length > 10;
    final slices = [
      for (final r in rows)
        SboxSlice(_rowName(r, nameKey, codeKey), (r[valueKey] as num?)?.toDouble() ?? 0,
            caption: nameKey == 'department' ? null : ('${r['department'] ?? ''}'.trim().isEmpty ? null : '${r['department']}')),
    ];
    Widget card(String title, {bool low = false}) => SboxChartCard(
          title: title,
          subtitle: sub,
          child: SboxRankList(
            maxItems: 10,
            ascending: low,
            maxValue: percent ? 100 : null,
            color: low ? SboxColors.danger : SboxColors.brand500,
            valueFormat: fmtV,
            items: slices,
          ),
        );
    return [
      card(both ? '$label — cao nhất' : 'Xếp hạng ${label.isEmpty ? '' : label[0].toLowerCase() + label.substring(1)}'),
      if (both) card('$label — thấp nhất', low: true),
    ];
  }

  Widget _table(String key, List<Map> rows) {
    final nameKey = _nameKey(rows);
    final codeKey = _codeKey(rows);
    final hasDept = nameKey != 'department' && rows.take(20).any((r) => '${r['department'] ?? ''}'.trim().isNotEmpty);
    final cols = <String>[];
    for (final r in rows.take(20)) {
      for (final e in r.entries) {
        final k = '${e.key}';
        if (k == nameKey || k == codeKey || (hasDept && k == 'department')) continue;
        if (_isScalar(e.value) && !cols.contains(k) && !k.toLowerCase().endsWith('id')) cols.add(k);
      }
    }
    // Cột số giống hệt nhau ở mọi dòng (vd «Ngày công chuẩn» = 26) đã có ở thẻ trên — bỏ khỏi bảng.
    if (rows.length > 2) {
      cols.removeWhere((c) => rows.every((r) => r[c] is num) && rows.map((r) => r[c]).toSet().length == 1);
    }
    // Số liệu chính lên trước để điện thoại (chỉ hiện 3 cột) thấy ngay.
    final rank = _rankKeys.where(cols.contains).firstOrNull;
    if (rank != null) {
      cols
        ..remove(rank)
        ..insert(0, rank);
    }
    final visible = _search.isEmpty
        ? rows
        : rows.where((r) => r.values.any((v) => '$v'.toLowerCase().contains(_search))).toList();
    bool numericCol(String c) => rows.take(20).any((r) => r[c] is num && r[c] is! bool);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text('${tr(_label(key))} (${visible.length})', style: SboxType.titleSmStyle()),
          ),
          SboxDataTable<Map>(
            rows: visible,
            pageSize: 20,
            emptyTitle: 'Không có dòng phù hợp',
            columns: [
              if (nameKey != null || codeKey != null)
                SboxColumn<Map>(
                  label: _label(nameKey ?? codeKey!),
                  primary: true,
                  flex: 2,
                  minWidth: 180,
                  text: (r) => _rowName(r, nameKey, codeKey),
                  cell: (r) {
                    final sub = [
                      if (codeKey != null && nameKey != null) '${r[codeKey] ?? ''}'.trim(),
                      if (hasDept) '${r['department'] ?? ''}'.trim(),
                    ].where((x) => x.isNotEmpty).join(' · ');
                    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(tr(_rowName(r, nameKey, codeKey)),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.bodyStrong()),
                      if (sub.isNotEmpty)
                        Text(tr(sub), maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle()),
                    ]);
                  },
                  sortValue: (r) => _rowName(r, nameKey, codeKey) as Comparable<Object?>,
                ),
              for (var i = 0; i < cols.length; i++)
                SboxColumn<Map>(
                  label: _label(cols[i]),
                  primary: nameKey == null && codeKey == null && i == 0,
                  numeric: numericCol(cols[i]),
                  minWidth: 110,
                  hideOnMobile: i >= 4,
                  text: (r) => _fmt(cols[i], r[cols[i]]),
                  sortValue: numericCol(cols[i])
                      ? (r) => ((r[cols[i]] as num?) ?? 0) as Comparable<Object?>
                      : (r) => '${r[cols[i]] ?? ''}' as Comparable<Object?>,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
