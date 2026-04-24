import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import '../utils/file_saver.dart' as file_saver;

/// Service client cho 29 endpoint "Báo cáo HR nâng cao" (Cluster 1..8).
///
/// - JSON getters trả `{isSuccess, data?, message?}`.
/// - Excel getters tự mở/lưu file, trả `{isSuccess, message?}`.
class AdvancedReportsService {
  static final AdvancedReportsService _instance =
      AdvancedReportsService._internal();
  factory AdvancedReportsService() => _instance;
  AdvancedReportsService._internal();

  static String get _baseUrl => getApiBaseUrl();
  static const Duration _timeout = Duration(seconds: 30);

  Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ─────────── Internal HTTP helpers ─────────────────────────────────────

  Future<Map<String, dynamic>> _getJson(
      String path, Map<String, dynamic>? query) async {
    try {
      final uri = Uri.parse('$_baseUrl$path')
          .replace(queryParameters: _normalizeQuery(query));
      final res = await http
          .get(uri, headers: await _headers())
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          return {
            'isSuccess': decoded['isSuccess'] ?? decoded['success'] ?? true,
            'data': decoded['data'] ?? decoded['result'] ?? decoded,
            'message': decoded['message'],
          };
        }
        return {'isSuccess': true, 'data': decoded};
      }
      return {
        'isSuccess': false,
        'message': 'HTTP ${res.statusCode}: ${res.reasonPhrase ?? ''}',
      };
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi kết nối: $e'};
    }
  }

  Future<Map<String, dynamic>> _downloadExcel(
      String path, Map<String, dynamic>? query, String fileName) async {
    try {
      final q = Map<String, dynamic>.from(query ?? {});
      q['format'] = 'excel';
      final uri =
          Uri.parse('$_baseUrl$path').replace(queryParameters: _normalizeQuery(q));
      final res = await http
          .get(uri, headers: await _headers())
          .timeout(const Duration(seconds: 120));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await file_saver.saveFileBytes(
          res.bodyBytes,
          fileName,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        return {'isSuccess': true};
      }
      return {
        'isSuccess': false,
        'message': 'Export failed (HTTP ${res.statusCode})',
      };
    } catch (e) {
      return {'isSuccess': false, 'message': 'Lỗi tải Excel: $e'};
    }
  }

  Map<String, String>? _normalizeQuery(Map<String, dynamic>? q) {
    if (q == null || q.isEmpty) return null;
    final out = <String, String>{};
    q.forEach((k, v) {
      if (v == null) return;
      if (v is DateTime) {
        out[k] = v.toIso8601String().split('T').first;
      } else {
        out[k] = v.toString();
      }
    });
    return out.isEmpty ? null : out;
  }

  // ═══════════════════ Cluster 1 — Attendance analytics ═══════════════════
  Future<Map<String, dynamic>> compliance(
          {int? year, int? month, String? department, String? employeeCode}) =>
      _getJson('/api/reports/attendance-analytics/compliance', {
        'year': year,
        'month': month,
        'department': department,
        'employeeCode': employeeCode,
      });
  Future<Map<String, dynamic>> complianceExcel(
          {int? year, int? month, String? department, String? employeeCode}) =>
      _downloadExcel(
        '/api/reports/attendance-analytics/compliance',
        {
          'year': year,
          'month': month,
          'department': department,
          'employeeCode': employeeCode
        },
        'compliance-${year ?? ""}-${month ?? ""}.xlsx',
      );

  Future<Map<String, dynamic>> absence(
          {DateTime? from, DateTime? to, String? department}) =>
      _getJson('/api/reports/attendance-analytics/absence',
          {'from': from, 'to': to, 'department': department});
  Future<Map<String, dynamic>> absenceExcel(
          {DateTime? from, DateTime? to, String? department}) =>
      _downloadExcel('/api/reports/attendance-analytics/absence',
          {'from': from, 'to': to, 'department': department}, 'absence.xlsx');

  Future<Map<String, dynamic>> noShow(
          {DateTime? from, DateTime? to, String? department}) =>
      _getJson('/api/reports/attendance-analytics/no-show',
          {'from': from, 'to': to, 'department': department});
  Future<Map<String, dynamic>> noShowExcel(
          {DateTime? from, DateTime? to, String? department}) =>
      _downloadExcel('/api/reports/attendance-analytics/no-show',
          {'from': from, 'to': to, 'department': department}, 'no-show.xlsx');

  Future<Map<String, dynamic>> anomalies({
    DateTime? from,
    DateTime? to,
    String? department,
    int? maxPunchesPerDay,
    int? earlyArrivalMinutes,
    int? lateDepartureMinutes,
  }) =>
      _getJson('/api/reports/attendance-analytics/anomalies', {
        'from': from,
        'to': to,
        'department': department,
        'maxPunchesPerDay': maxPunchesPerDay,
        'earlyArrivalMinutes': earlyArrivalMinutes,
        'lateDepartureMinutes': lateDepartureMinutes,
      });
  Future<Map<String, dynamic>> anomaliesExcel({
    DateTime? from,
    DateTime? to,
    String? department,
    int? maxPunchesPerDay,
    int? earlyArrivalMinutes,
    int? lateDepartureMinutes,
  }) =>
      _downloadExcel(
          '/api/reports/attendance-analytics/anomalies',
          {
            'from': from,
            'to': to,
            'department': department,
            'maxPunchesPerDay': maxPunchesPerDay,
            'earlyArrivalMinutes': earlyArrivalMinutes,
            'lateDepartureMinutes': lateDepartureMinutes,
          },
          'anomalies.xlsx');

  Future<Map<String, dynamic>> fieldSummary(
          {DateTime? from, DateTime? to, String? employeeCode}) =>
      _getJson('/api/reports/attendance-analytics/field-summary',
          {'from': from, 'to': to, 'employeeCode': employeeCode});
  Future<Map<String, dynamic>> fieldSummaryExcel(
          {DateTime? from, DateTime? to, String? employeeCode}) =>
      _downloadExcel(
          '/api/reports/attendance-analytics/field-summary',
          {'from': from, 'to': to, 'employeeCode': employeeCode},
          'field-summary.xlsx');

  Future<Map<String, dynamic>> mobileUsage({DateTime? from, DateTime? to}) =>
      _getJson('/api/reports/attendance-analytics/mobile-usage',
          {'from': from, 'to': to});
  Future<Map<String, dynamic>> mobileUsageExcel(
          {DateTime? from, DateTime? to}) =>
      _downloadExcel('/api/reports/attendance-analytics/mobile-usage',
          {'from': from, 'to': to}, 'mobile-usage.xlsx');

  // ═══════════════════ Cluster 2 — Leave / Shift ═══════════════════
  Future<Map<String, dynamic>> leaveBalance({int? year, String? department}) =>
      _getJson('/api/reports/leave-shift/leave-balance',
          {'year': year, 'department': department});
  Future<Map<String, dynamic>> leaveBalanceExcel(
          {int? year, String? department}) =>
      _downloadExcel(
          '/api/reports/leave-shift/leave-balance',
          {'year': year, 'department': department},
          'leave-balance-${year ?? ""}.xlsx');

  Future<Map<String, dynamic>> leaveApprovalSla(
          {DateTime? from, DateTime? to}) =>
      _getJson('/api/reports/leave-shift/leave-approval-sla',
          {'from': from, 'to': to});
  Future<Map<String, dynamic>> leaveApprovalSlaExcel(
          {DateTime? from, DateTime? to}) =>
      _downloadExcel('/api/reports/leave-shift/leave-approval-sla',
          {'from': from, 'to': to}, 'leave-approval-sla.xlsx');

  Future<Map<String, dynamic>> shiftCoverage(
          {DateTime? from, DateTime? to, String? department}) =>
      _getJson('/api/reports/leave-shift/shift-coverage',
          {'from': from, 'to': to, 'department': department});
  Future<Map<String, dynamic>> shiftCoverageExcel(
          {DateTime? from, DateTime? to, String? department}) =>
      _downloadExcel(
          '/api/reports/leave-shift/shift-coverage',
          {'from': from, 'to': to, 'department': department},
          'shift-coverage.xlsx');

  Future<Map<String, dynamic>> shiftSwaps({DateTime? from, DateTime? to}) =>
      _getJson('/api/reports/leave-shift/shift-swaps',
          {'from': from, 'to': to});
  Future<Map<String, dynamic>> shiftSwapsExcel(
          {DateTime? from, DateTime? to}) =>
      _downloadExcel('/api/reports/leave-shift/shift-swaps',
          {'from': from, 'to': to}, 'shift-swaps.xlsx');

  // ═══════════════════ Cluster 3+4 — HR ═══════════════════
  Future<Map<String, dynamic>> headcountMovement(
          {int? year, String? department}) =>
      _getJson('/api/reports/hr/headcount-movement',
          {'year': year, 'department': department});
  Future<Map<String, dynamic>> headcountMovementExcel(
          {int? year, String? department}) =>
      _downloadExcel(
          '/api/reports/hr/headcount-movement',
          {'year': year, 'department': department},
          'headcount-movement-${year ?? ""}.xlsx');

  Future<Map<String, dynamic>> turnover({int? year, String? groupBy}) =>
      _getJson('/api/reports/hr/turnover',
          {'year': year, 'groupBy': groupBy});
  Future<Map<String, dynamic>> turnoverExcel({int? year, String? groupBy}) =>
      _downloadExcel('/api/reports/hr/turnover',
          {'year': year, 'groupBy': groupBy}, 'turnover-${year ?? ""}.xlsx');

  Future<Map<String, dynamic>> tenureDistribution({String? department}) =>
      _getJson(
          '/api/reports/hr/tenure-distribution', {'department': department});
  Future<Map<String, dynamic>> tenureDistributionExcel({String? department}) =>
      _downloadExcel('/api/reports/hr/tenure-distribution',
          {'department': department}, 'tenure-distribution.xlsx');

  Future<Map<String, dynamic>> demographics({String? department}) =>
      _getJson('/api/reports/hr/demographics', {'department': department});
  Future<Map<String, dynamic>> demographicsExcel({String? department}) =>
      _downloadExcel('/api/reports/hr/demographics',
          {'department': department}, 'demographics.xlsx');

  Future<Map<String, dynamic>> contractExpiry(
          {int days = 90, String? department}) =>
      _getJson('/api/reports/hr/contract-expiry',
          {'days': days, 'department': department});
  Future<Map<String, dynamic>> contractExpiryExcel(
          {int days = 90, String? department}) =>
      _downloadExcel('/api/reports/hr/contract-expiry',
          {'days': days, 'department': department},
          'contract-expiry-${days}d.xlsx');

  Future<Map<String, dynamic>> birthdays({int days = 30, String? department}) =>
      _getJson('/api/reports/hr/birthdays',
          {'days': days, 'department': department});
  Future<Map<String, dynamic>> birthdaysExcel(
          {int days = 30, String? department}) =>
      _downloadExcel('/api/reports/hr/birthdays',
          {'days': days, 'department': department}, 'birthdays-${days}d.xlsx');

  Future<Map<String, dynamic>> retirement({int years = 5}) =>
      _getJson('/api/reports/hr/retirement', {'years': years});
  Future<Map<String, dynamic>> retirementExcel({int years = 5}) =>
      _downloadExcel('/api/reports/hr/retirement', {'years': years},
          'retirement-${years}y.xlsx');

  Future<Map<String, dynamic>> orgHeadcount() =>
      _getJson('/api/reports/hr/org-headcount', null);
  Future<Map<String, dynamic>> orgHeadcountExcel() => _downloadExcel(
      '/api/reports/hr/org-headcount', null, 'org-headcount.xlsx');

  // ═══════════════════ Cluster 5 — Payroll ═══════════════════
  Future<Map<String, dynamic>> payrollCostByDepartment(
          {int? year, int? month, String? department}) =>
      _getJson('/api/reports/payroll/cost-by-department',
          {'year': year, 'month': month, 'department': department});
  Future<Map<String, dynamic>> payrollCostByDepartmentExcel(
          {int? year, int? month, String? department}) =>
      _downloadExcel(
          '/api/reports/payroll/cost-by-department',
          {'year': year, 'month': month, 'department': department},
          'payroll-cost-${year ?? ""}-${month ?? ""}.xlsx');

  Future<Map<String, dynamic>> otCostRatio({int? year, String? department}) =>
      _getJson('/api/reports/payroll/ot-cost-ratio',
          {'year': year, 'department': department});
  Future<Map<String, dynamic>> otCostRatioExcel(
          {int? year, String? department}) =>
      _downloadExcel(
          '/api/reports/payroll/ot-cost-ratio',
          {'year': year, 'department': department},
          'ot-cost-ratio-${year ?? ""}.xlsx');

  Future<Map<String, dynamic>> bonusAllowance({int? year, int? month}) =>
      _getJson('/api/reports/payroll/bonus-allowance',
          {'year': year, 'month': month});
  Future<Map<String, dynamic>> bonusAllowanceExcel({int? year, int? month}) =>
      _downloadExcel('/api/reports/payroll/bonus-allowance',
          {'year': year, 'month': month}, 'bonus-allowance.xlsx');

  Future<Map<String, dynamic>> payslipStatusDistribution(
          {int? year, int? month}) =>
      _getJson('/api/reports/payroll/status-distribution',
          {'year': year, 'month': month});
  Future<Map<String, dynamic>> payslipStatusDistributionExcel(
          {int? year, int? month}) =>
      _downloadExcel('/api/reports/payroll/status-distribution',
          {'year': year, 'month': month}, 'payslip-status.xlsx');

  // ═══════════════════ Cluster 6 — Finance ═══════════════════
  Future<Map<String, dynamic>> penaltySummary({
    DateTime? from,
    DateTime? to,
    String? department,
    String? type,
  }) =>
      _getJson('/api/reports/finance/penalty-summary', {
        'from': from,
        'to': to,
        'department': department,
        'type': type,
      });
  Future<Map<String, dynamic>> penaltySummaryExcel({
    DateTime? from,
    DateTime? to,
    String? department,
    String? type,
  }) =>
      _downloadExcel(
          '/api/reports/finance/penalty-summary',
          {'from': from, 'to': to, 'department': department, 'type': type},
          'penalty-summary.xlsx');

  Future<Map<String, dynamic>> advanceDebt({
    DateTime? from,
    DateTime? to,
    String? department,
    String? status,
  }) =>
      _getJson('/api/reports/finance/advance-debt', {
        'from': from,
        'to': to,
        'department': department,
        'status': status,
      });
  Future<Map<String, dynamic>> advanceDebtExcel({
    DateTime? from,
    DateTime? to,
    String? department,
    String? status,
  }) =>
      _downloadExcel(
          '/api/reports/finance/advance-debt',
          {'from': from, 'to': to, 'department': department, 'status': status},
          'advance-debt.xlsx');

  Future<Map<String, dynamic>> mealDebt(
          {String? period, DateTime? from, DateTime? to}) =>
      _getJson('/api/reports/finance/meal-debt',
          {'period': period, 'from': from, 'to': to});
  Future<Map<String, dynamic>> mealDebtExcel(
          {String? period, DateTime? from, DateTime? to}) =>
      _downloadExcel('/api/reports/finance/meal-debt',
          {'period': period, 'from': from, 'to': to}, 'meal-debt.xlsx');

  // ═══════════════════ Cluster 7 — Performance ═══════════════════
  Future<Map<String, dynamic>> kpiSummary({
    String? periodId,
    int? year,
    int? month,
    String? department,
  }) =>
      _getJson('/api/reports/performance/kpi-summary', {
        'periodId': periodId,
        'year': year,
        'month': month,
        'department': department,
      });
  Future<Map<String, dynamic>> kpiSummaryExcel({
    String? periodId,
    int? year,
    int? month,
    String? department,
  }) =>
      _downloadExcel(
          '/api/reports/performance/kpi-summary',
          {
            'periodId': periodId,
            'year': year,
            'month': month,
            'department': department,
          },
          'kpi-summary.xlsx');

  Future<Map<String, dynamic>> productionOutput({
    DateTime? from,
    DateTime? to,
    String? department,
    String? productId,
  }) =>
      _getJson('/api/reports/performance/production-output', {
        'from': from,
        'to': to,
        'department': department,
        'productId': productId,
      });
  Future<Map<String, dynamic>> productionOutputExcel({
    DateTime? from,
    DateTime? to,
    String? department,
    String? productId,
  }) =>
      _downloadExcel(
          '/api/reports/performance/production-output',
          {
            'from': from,
            'to': to,
            'department': department,
            'productId': productId,
          },
          'production-output.xlsx');

  Future<Map<String, dynamic>> assetAssignment(
          {String? status, String? department}) =>
      _getJson('/api/reports/performance/asset-assignment',
          {'status': status, 'department': department});
  Future<Map<String, dynamic>> assetAssignmentExcel(
          {String? status, String? department}) =>
      _downloadExcel('/api/reports/performance/asset-assignment',
          {'status': status, 'department': department}, 'asset-assignment.xlsx');

  // ═══════════════════ Cluster 8 — Executive ═══════════════════
  Future<Map<String, dynamic>> executiveMonthlySummary(
          {int? year, int? month}) =>
      _getJson('/api/reports/executive/monthly-summary',
          {'year': year, 'month': month});
  Future<Map<String, dynamic>> executiveMonthlySummaryExcel(
          {int? year, int? month}) =>
      _downloadExcel(
          '/api/reports/executive/monthly-summary',
          {'year': year, 'month': month},
          'executive-summary-${year ?? ""}-${month ?? ""}.xlsx');
}
