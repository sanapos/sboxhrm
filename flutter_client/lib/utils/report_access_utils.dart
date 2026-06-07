import 'package:flutter/material.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import 'salary_profile_load_utils.dart';

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
    raw = data[listKey] ?? data['items'];
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
    final tc = data['totalCount'] ?? data['total'];
    if (tc is int) {
      total = tc;
    } else if (tc is num) {
      total = tc.toInt();
    }
  }
  return (items: base.items, totalCount: total, error: base.error);
}

Map<String, dynamic> normalizePenaltyTicketRow(Map<String, dynamic> t) {
  final m = Map<String, dynamic>.from(t);
  m['date'] ??= m['violationDate'];
  m['penaltyTypeName'] ??= m['type'];
  m['note'] ??= m['description'];
  m['departmentName'] ??= m['department'];
  return m;
}

bool shouldUseCashReportApi({
  required String? role,
  required PermissionProvider perm,
}) {
  if (isEmployeeUserRole(role)) return true;
  return perm.canView('CashReport') && !perm.canView('CashTransaction');
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
            message,
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

Future<({List<Map<String, dynamic>> items, String? error})> loadCashReportTransactions(
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
  return parseReportListResponse(r);
}
