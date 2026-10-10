/// Nguồn dữ liệu cho bộ tính lương.
///
/// App: `ApiService` (đã có sẵn các hàm này). Máy chủ: [HttpPayrollApi] gọi đúng các API đó
/// bằng quyền của người đang xem → cùng dữ liệu, cùng công thức, cùng kết quả.
/// Các hàm trả về đúng dạng như `ApiService` (map đã chuẩn hóa `isSuccess` / `data`).
abstract class PayrollApi {
  Future<Map<String, dynamic>> getAppSetting(String key);

  Future<List<dynamic>> getEmployees({
    int? page,
    int? pageSize,
    String? branchId,
    bool includeChildBranches = true,
    bool excludeResigned = false,
  });

  Future<List<dynamic>> getEmployeeSalaryProfiles();

  Future<Map<String, dynamic>?> getEmployeeSalaryProfile(String employeeId);

  Future<Map<String, dynamic>?> getMyEmployeeSalaryProfile();

  Future<Map<String, dynamic>> getInsuranceSettings();

  Future<Map<String, dynamic>> getSalarySettings();

  Future<Map<String, dynamic>> getTaxSettings();

  Future<List<dynamic>> getEmployeeTaxDeductions();

  Future<Map<String, dynamic>> getTransactions({
    DateTime? fromDate,
    DateTime? toDate,
    String? type,
    int page = 1,
    int pageSize = 100,
  });

  Future<Map<String, dynamic>> getAdvanceRequests({
    int page = 1,
    int pageSize = 50,
    String? employeeUserId,
    int? status,
    DateTime? fromDate,
    DateTime? toDate,
  });

  Future<List<dynamic>> getShifts();

  Future<List<dynamic>> getAllowanceSettings();

  Future<List<dynamic>> getHolidaySettings(int year);

  Future<Map<String, dynamic>> getWorkSchedules({
    int page = 1,
    int pageSize = 50,
    String? employeeUserId,
    String? employeeId,
    String? shiftId,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isDayOff,
  });

  Future<Map<String, dynamic>> getMyWorkSchedules({
    DateTime? fromDate,
    DateTime? toDate,
    int pageSize = 50,
  });

  Future<Map<String, dynamic>> getPenaltyTickets({
    int page = 1,
    int pageSize = 20,
    String? employeeId,
    String? status,
    String? type,
    DateTime? fromDate,
    DateTime? toDate,
  });

  Future<Map<String, dynamic>> getHrFinPayrollAdjustments(DateTime from, DateTime to);

  Future<Map<String, dynamic>> getShiftSalaryLevels();

  Future<Map<String, dynamic>> getCommissionSettings();

  Future<Map<String, dynamic>> getKpiPeriods();

  Future<Map<String, dynamic>> getKpiEmployeeTargets({String? periodId});

  Future<Map<String, dynamic>> getProductionSummary({
    required DateTime fromDate,
    required DateTime toDate,
    String? employeeId,
    String? productGroupId,
  });

  Future<Map<String, dynamic>> getKpiSalaryForPayroll({
    required DateTime from,
    required DateTime to,
  });

  Future<Map<String, dynamic>> getSalaryTimeline(DateTime from, DateTime to);

  Future<Map<String, dynamic>> getAnnualLeavePayouts(DateTime from, DateTime to);

  Future<Map<String, dynamic>> getMobileAttendanceHistory({
    String? employeeId,
    DateTime? fromDate,
    DateTime? toDate,
    String? status,
    String? punchTypes,
    int? pageSize,
  });

  Future<List<dynamic>> getDevices({bool storeOnly = false});

  /// Trả về `{items, totalCount, pageNumber, pageSize}` (đã bóc `data`).
  Future<Map<String, dynamic>> getAttendances({
    List<String>? deviceIds,
    DateTime? fromDate,
    DateTime? toDate,
    int page = 1,
    int pageSize = 20,
  });

  Future<Map<String, dynamic>> getAllLeaves({
    int? page,
    int? pageSize,
    String? status,
    String? fromDate,
    String? toDate,
    String? employeeId,
  });
}
