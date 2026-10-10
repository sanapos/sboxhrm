import 'payroll_engine.dart';

/// Yêu cầu chốt lương (gửi API `FinalizePayroll`) dựng từ các dòng bảng lương.
/// Dùng chung: app (chốt kiểu cũ) và máy chủ (chốt bằng số máy chủ tự tính).
class PayrollFinalizeBatch {
  PayrollFinalizeBatch({required this.request, required this.skipped});

  /// `{year, month, periodStart, periodEnd, overwriteExisting, items}`.
  final Map<String, dynamic> request;

  /// Tên / mã NV bỏ qua vì thiếu hồ sơ nhân viên hoặc bảng lương.
  final List<String> skipped;

  List<dynamic> get items => request['items'] as List<dynamic>;
}

PayrollFinalizeBatch buildPayrollFinalizeBatch(
  PayrollEngine engine,
  List<Map<String, dynamic>> rows, {
  bool overwriteExisting = true,
}) {
  final items = <Map<String, dynamic>>[];
  final skipped = <String>[];

  for (final row in rows) {
    final code = row['code']?.toString() ?? '';
    final emp = engine.findEmployee(code);
    final userId = row['employeeUserId']?.toString() ?? emp?.applicationUserId ?? '';
    final employeeId = emp?.id ?? row['employeeId']?.toString() ?? '';
    final profileId = row['salaryProfileId']?.toString() ?? '';
    if (employeeId.isEmpty || profileId.isEmpty) {
      skipped.add(row['name']?.toString() ?? code);
      continue;
    }
    final penalty = PayrollEngine.toDouble(row['penalty']);
    final advance = PayrollEngine.toDouble(row['advance']);
    final unionFee = PayrollEngine.toDouble(row['unionFeePart']);
    final rateType = PayrollEngine.toInt(row['rateType'], 1);
    final regularUnits = switch (rateType) {
      0 => PayrollEngine.toDouble(row['totalHours']),
      3 => PayrollEngine.toDouble(row['totalShifts']),
      // Lương tháng / ngày: công đi làm + ngày lễ / nghỉ có lương được trả.
      _ => PayrollEngine.toDouble(row['workDays']) + PayrollEngine.toDouble(row['paidDaysCredit']),
    };
    final item = <String, dynamic>{
      'employeeId': employeeId,
      'salaryProfileId': profileId,
      'regularWorkUnits': regularUnits,
      'overtimeUnits': PayrollEngine.toDouble(row['otTotalHours']),
      'baseSalary': PayrollEngine.toDouble(row['baseSalary']),
      'overtimePay': PayrollEngine.toDouble(row['otSalary']),
      // Tiền phép năm chưa nghỉ không có field riêng trên Payslip — gom vào thưởng.
      'bonus': PayrollEngine.toDouble(row['bonus']) + PayrollEngine.toDouble(row['leavePayout']),
      'leavePayout': PayrollEngine.toDouble(row['leavePayout']),
      // Đoàn phí không có field riêng trên Payslip — gom vào deductions.
      'deductions': penalty + advance + unionFee,
      'allowances': PayrollEngine.toDouble(row['totalAllowance']),
      'socialInsurance': PayrollEngine.toDouble(row['bhxhPart']),
      'healthInsurance': PayrollEngine.toDouble(row['bhytPart']),
      'unemploymentInsurance': PayrollEngine.toDouble(row['bhtnPart']),
      'tax': PayrollEngine.toDouble(row['pit']),
      'grossSalary': PayrollEngine.toDouble(row['totalSalary']),
      'netSalary': PayrollEngine.toDouble(row['netSalary']),
      'travelHours': PayrollEngine.toDouble(row['travelHours']),
      'travelSalary': PayrollEngine.toDouble(row['travelSalary']),
    };
    if (userId.isNotEmpty) item['employeeUserId'] = userId;
    item['attendanceSnapshot'] = engine.buildAttendanceSnapshot(code, row);
    items.add(item);
  }

  final from = engine.fromDate, to = engine.toDate;
  return PayrollFinalizeBatch(
    request: {
      'year': to.year,
      'month': to.month,
      'periodStart': DateTime(from.year, from.month, from.day).toIso8601String(),
      'periodEnd': DateTime(to.year, to.month, to.day, 23, 59, 59).toIso8601String(),
      'overwriteExisting': overwriteExisting,
      'items': items,
    },
    skipped: skipped,
  );
}
