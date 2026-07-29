import 'package:flutter/material.dart';

import '../models/hrm.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import 'cash_report_helpers.dart';
import 'salary_profile_load_utils.dart';
import '../l10n/app_tr.dart';

/// Admin/manager xem nhiều NV; nhân viên chỉ xem dữ liệu cá nhân.
bool isTeamReportView({required String? role}) => !isEmployeeUserRole(role);

bool isManagerUserRole(String? role) {
  final r = role?.trim().toLowerCase() ?? '';
  return r == 'admin' ||
      r == 'superadmin' ||
      r == 'manager' ||
      r == 'director';
}

/// Phân tích phản hồi API báo cáo — trả về danh sách map hoặc thông báo lỗi.
({List<Map<String, dynamic>> items, String? error}) parseReportListResponse(
  Map<String, dynamic> response, {
  String listKey = 'items',
}) {
  if (response['isSuccess'] != true) {
    final msg = response['message']?.toString().trim();
    return (items: <Map<String, dynamic>>[], error: msg?.isNotEmpty == true ? msg : 'Không tải được dữ liệu báo cáo');
  }
  final data = response['data'];
  dynamic raw;
  if (data is List) {
    raw = data;
  } else if (data is Map) {
    raw = data[listKey] ?? data['items'] ?? data['Items'];
  }
  if (raw is! List) {
    return (items: <Map<String, dynamic>>[], error: null);
  }
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return (items: out, error: null);
}

/// Phân trang: `data.items` + `data.totalCount`.
({List<Map<String, dynamic>> items, int totalCount, String? error})
    parsePagedReportListResponse(
  Map<String, dynamic> response, {
  String listKey = 'items',
}) {
  final base = parseReportListResponse(response, listKey: listKey);
  if (base.error != null && base.items.isEmpty) {
    return (items: base.items, totalCount: 0, error: base.error);
  }
  final data = response['data'];
  int total = base.items.length;
  if (data is Map) {
    final tc = data['totalCount'] ?? data['TotalCount'] ?? data['total'];
    if (tc is int) {
      total = tc;
    } else if (tc is num) {
      total = tc.toInt();
    }
  }
  return (items: base.items, totalCount: total, error: base.error);
}

/// Nhãn tiếng Việt cho loại phiếu phạt (PascalCase, lowercase, hoặc mã số enum).
String penaltyTypeDisplayLabel(dynamic raw) {
  if (raw == null) return '-';
  if (raw is int) {
    switch (raw) {
      case 1:
        return 'Đi trễ';
      case 2:
        return 'Về sớm';
      case 3:
        return 'Quên chấm công';
      case 4:
        return 'Nghỉ không phép';
      case 5:
        return 'Vi phạm nội quy';
      case 6:
        return 'Tái phạm';
      default:
        return '-';
    }
  }
  final key = raw.toString().trim();
  if (key.isEmpty) return '-';

  switch (key) {
    case 'Late':
      return 'Đi trễ';
    case 'EarlyLeave':
      return 'Về sớm';
    case 'ForgotCheck':
      return 'Quên chấm công';
    case 'UnauthorizedLeave':
      return 'Nghỉ không phép';
    case 'Violation':
      return 'Vi phạm nội quy';
    case 'Repeat':
      return 'Tái phạm';
    case 'Disciplinary':
      return 'Kỷ luật';
    case 'Financial':
    case 'FinancialPenalty':
      return 'Phạt tiền';
    case 'Warning':
      return 'Cảnh báo';
    case 'Absent':
      return 'Vắng mặt';
    default:
      break;
  }

  switch (key.toLowerCase()) {
    case 'late':
      return 'Đi trễ';
    case 'earlyleave':
    case 'earlycheck':
    case 'early':
      return 'Về sớm';
    case 'forgotcheck':
      return 'Quên chấm công';
    case 'unauthorizedleave':
      return 'Nghỉ không phép';
    case 'violation':
      return 'Vi phạm nội quy';
    case 'repeat':
      return 'Tái phạm';
    case 'disciplinary':
      return 'Kỷ luật';
    case 'financial':
    case 'financialpenalty':
      return 'Phạt tiền';
    case 'warning':
      return 'Cảnh báo';
    case 'absent':
      return 'Vắng mặt';
    default:
      return key;
  }
}

/// Nhãn tiếng Việt cho trạng thái phiếu phạt.
String penaltyStatusDisplayLabel(dynamic raw) {
  if (raw == null) return '';
  if (raw is int) {
    switch (raw) {
      case 0:
        return 'Chờ duyệt';
      case 1:
        return 'Đã duyệt';
      case 2:
        return 'Đã hủy';
      case 3:
        return 'Tự động duyệt';
      default:
        return '';
    }
  }
  final key = raw.toString().trim();
  if (key.isEmpty) return '';

  switch (key) {
    case 'Pending':
      return 'Chờ duyệt';
    case 'Approved':
      return 'Đã duyệt';
    case 'AutoApproved':
      return 'Tự động duyệt';
    case 'Cancelled':
    case 'Canceled':
      return 'Đã hủy';
    default:
      break;
  }

  switch (key.toLowerCase()) {
    case 'pending':
      return 'Chờ duyệt';
    case 'approved':
      return 'Đã duyệt';
    case 'autoapproved':
      return 'Tự động duyệt';
    case 'cancelled':
    case 'canceled':
      return 'Đã hủy';
    default:
      return key;
  }
}

bool isApprovedPenaltyStatus(dynamic raw) {
  if (raw is int) return raw == 1 || raw == 3;
  final key = raw?.toString().toLowerCase().trim() ?? '';
  return key == 'approved' || key == 'autoapproved' || key == '1' || key == '3';
}

/// Phiếu hủy / từ chối — không tính vào KPI báo cáo (trừ khi lọc đúng trạng thái đó).
bool isVoidAdvanceRequestStatus(AdvanceRequestStatus s) =>
    s == AdvanceRequestStatus.cancelled ||
    s == AdvanceRequestStatus.rejected;

bool isVoidPenaltyTicketStatus(dynamic raw) {
  if (raw is int) return raw == 2;
  final key = raw?.toString().toLowerCase().trim() ?? '';
  return key == 'cancelled' || key == 'canceled' || key == '2';
}

int normalizeLeaveReportStatus(dynamic s) {
  if (s == null) return 0;
  if (s is int) return s;
  final str = s.toString().toLowerCase();
  if (str == '0' || str == 'pending') return 0;
  if (str == '1' || str == 'approved') return 1;
  if (str == '2' || str == 'rejected') return 2;
  if (str == '3' || str == 'cancelled') return 3;
  return int.tryParse(str) ?? 0;
}

bool isVoidLeaveReportStatus(int s) => s == 2 || s == 3;

List<AdvanceRequest> advanceRowsForReportStats(
  List<AdvanceRequest> rows,
  AdvanceRequestStatus? statusFilter,
) {
  if (statusFilter == AdvanceRequestStatus.cancelled ||
      statusFilter == AdvanceRequestStatus.rejected) {
    return rows;
  }
  return rows.where((r) => !isVoidAdvanceRequestStatus(r.status)).toList();
}

List<Map<String, dynamic>> penaltyRowsForReportStats(
  List<Map<String, dynamic>> rows,
  String? statusFilter,
) {
  if (statusFilter != null) {
    final f = statusFilter.toLowerCase();
    if (f == 'cancelled' || f == 'canceled' || f == '2') return rows;
  }
  return rows.where((t) => !isVoidPenaltyTicketStatus(t['status'])).toList();
}

List<Map<String, dynamic>> leaveRowsForReportStats(
  List<Map<String, dynamic>> rows,
  int? statusFilter,
) {
  if (statusFilter == 2 || statusFilter == 3) return rows;
  return rows
      .where((l) => !isVoidLeaveReportStatus(normalizeLeaveReportStatus(l['status'])))
      .toList();
}

Color penaltyStatusColor(dynamic raw) {
  if (raw is int) {
    switch (raw) {
      case 0:
        return const Color(0xFFF59E0B);
      case 1:
      case 3:
        return const Color(0xFF2563EB);
      case 2:
        return Colors.grey;
      default:
        break;
    }
  }
  final key = raw?.toString().toLowerCase().trim() ?? '';
  if (key == 'pending' || key == '0') return const Color(0xFFF59E0B);
  if (key == 'approved' || key == 'autoapproved' || key == '1' || key == '3') {
    return const Color(0xFF2563EB);
  }
  if (key == 'cancelled' || key == 'canceled' || key == '2') {
    return Colors.grey;
  }
  return const Color(0xFF1E3A5F);
}

Map<String, dynamic> normalizePenaltyTicketRow(Map<String, dynamic> t) {
  final m = Map<String, dynamic>.from(t);
  m['date'] ??= m['violationDate'] ?? m['ViolationDate'];
  m['type'] ??= m['Type'];
  m['status'] ??= m['Status'];
  m['amount'] ??= m['Amount'];
  m['employeeName'] ??= m['EmployeeName'];
  m['departmentName'] ??= m['department'] ?? m['Department'];
  m['note'] ??= m['description'] ?? m['Description'];
  m['penaltyTypeName'] ??= m['type'];
  m['penaltyTypeLabel'] = penaltyTypeDisplayLabel(m['type']);
  m['statusLabel'] = penaltyStatusDisplayLabel(m['status']);
  return m;
}

bool shouldUseCashReportApi({
  required String? role,
  required PermissionProvider perm,
}) {
  // Màn báo cáo luôn dùng API reports (có summary + phiếu chờ ngoài kỳ).
  return perm.canView('CashReport') || isEmployeeUserRole(role);
}

Widget reportLoadErrorBanner(String? message) {
  if (message == null || message.isEmpty) return const SizedBox.shrink();
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 18, color: Color(0xFFDC2626)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            tr(message),
            style: const TextStyle(fontSize: 13, color: Color(0xFF991B1B)),
          ),
        ),
      ],
    ),
  );
}

Future<({List<Map<String, dynamic>> items, int totalCount, String? error})>
    loadPenaltyReportTickets(
  ApiService api, {
  required DateTime from,
  required DateTime to,
  String? statusFilter,
  int page = 1,
  int pageSize = 50,
}) async {
  final r = await api.getPenaltyTickets(
    fromDate: from,
    toDate: to,
    status: statusFilter,
    page: page,
    pageSize: pageSize,
  );
  final parsed = parsePagedReportListResponse(r);
  return (
    items: parsed.items.map(normalizePenaltyTicketRow).toList(),
    totalCount: parsed.totalCount,
    error: parsed.error,
  );
}

CashReportSummary? _parseCashReportSummary(Map<String, dynamic> response) {
  final data = response['data'];
  if (data is! Map) return null;
  final summary = data['summary'] ?? data['Summary'];
  if (summary is Map) {
    return CashReportSummary.fromJson(Map<String, dynamic>.from(summary));
  }
  return null;
}

Future<
    ({
      List<Map<String, dynamic>> items,
      CashReportSummary? summary,
      String? error,
    })> loadCashReportTransactions(
  ApiService api, {
  required DateTime from,
  required DateTime to,
  int? typeFilter,
  required bool useReportApi,
  int pageSize = 500,
}) async {
  final Map<String, dynamic> r;
  if (useReportApi) {
    r = await api.getCashReportTransactions(
      fromDate: from,
      toDate: to,
      type: typeFilter,
      pageSize: pageSize,
    );
  } else {
    r = await api.getCashTransactions(
      fromDate: from,
      toDate: to,
      type: typeFilter,
      pageSize: pageSize,
    );
  }
  final parsed = parseReportListResponse(r);
  final merged = List<Map<String, dynamic>>.from(parsed.items)
    ..retainWhere((row) => cashReportInDateRange(row, from, to));
  // Tổng hợp luôn tính từ danh sách trong kỳ — khớp chip và bảng phiếu.
  final summary = CashReportSummary.fromRows(merged);
  return (items: merged, summary: summary, error: parsed.error);
}
