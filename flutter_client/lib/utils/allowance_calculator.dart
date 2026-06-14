import 'dart:convert';

/// Tính phụ cấp NV từ danh mục — dùng chung Thiết lập lương & Tổng hợp lương.
class AllowanceCalculator {
  AllowanceCalculator._();

  /// API trả Type dạng "Fixed"/"Daily" (JsonStringEnumConverter) hoặc int 0..3.
  static int parseType(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final s = value?.toString().toLowerCase() ?? '';
    switch (s) {
      case 'daily':
      case '1':
        return 1;
      case 'hourly':
      case '2':
        return 2;
      case 'perevent':
      case 'per_event':
      case '3':
        return 3;
      case 'fixed':
      case '0':
      default:
        return 0;
    }
  }

  /// null employeeIds = áp dụng tất cả NV; danh sách rỗng = không gán ai.
  static bool isAssignedToEmployee(
    Map<String, dynamic> allowance,
    String employeeId, {
    String? employeeCode,
  }) {
    if (employeeId.isEmpty) return false;
    final raw = allowance['employeeIds'];
    if (raw == null) return true;

    List<String> ids = [];
    if (raw is List) {
      ids = raw.map((e) => e.toString()).toList();
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          ids = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    if (ids.isEmpty) return false;
    final key = employeeId.toLowerCase();
    if (ids.any((id) => id.toLowerCase() == key)) return true;
    if (employeeCode != null && employeeCode.isNotEmpty) {
      final codeKey = employeeCode.toLowerCase();
      if (ids.any((id) => id.toLowerCase() == codeKey)) return true;
    }
    return false;
  }

  static double _amount(Map<String, dynamic> allowance) {
    final amount = allowance['amount'];
    if (amount is num) return amount.toDouble();
    if (amount is String) return double.tryParse(amount) ?? 0;
    return 0;
  }

  /// Tổng mức phụ cấp theo loại (0=cố định, 1=theo ngày, 2=theo giờ).
  static double sumForEmployee({
    required List<Map<String, dynamic>> allowances,
    required String employeeId,
    required int allowanceType,
    bool requireActive = true,
    String? employeeCode,
    Map<String, dynamic>? benefitFallback,
  }) {
    if (employeeId.isEmpty) return 0;
    var total = 0.0;
    for (final a in allowances) {
      if (requireActive && a['isActive'] == false) continue;
      if (parseType(a['type']) != allowanceType) continue;
      if (!isAssignedToEmployee(a, employeeId, employeeCode: employeeCode)) {
        continue;
      }
      final val = _amount(a);
      if (val > 0) total += val;
    }
    if (total > 0 || benefitFallback == null) return total;
    if (allowanceType == 0) {
      return (benefitFallback['mealAllowance'] as num?)?.toDouble() ?? 0;
    }
    if (allowanceType == 1) {
      return (benefitFallback['responsibilityAllowance'] as num?)?.toDouble() ??
          0;
    }
    return total;
  }
}
