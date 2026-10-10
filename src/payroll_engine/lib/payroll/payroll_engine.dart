// Bộ tính lương dùng chung: app (Tổng hợp lương) và máy chủ (chương trình payroll_engine).
// Đoạn mã chép nguyên từ màn Tổng hợp lương — sửa công thức ở đây, cả app lẫn máy chủ cùng đổi.
// ignore_for_file: unused_field, unnecessary_non_null_assertion
import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/attendance.dart';
import '../models/employee.dart';
import '../models/hr_finance.dart';
import '../payroll_api.dart';
import '../utils/allowance_calculator.dart';
import '../utils/attendance_loading.dart';
import '../utils/overtime_hourly_base_utils.dart';
import '../utils/paid_leave_schedule_utils.dart';
import '../utils/pit_tax_utils.dart';
import '../utils/shift_records_calculator.dart';
import '../utils/standard_work_days_utils.dart';
import '../utils/travel_hours_load_utils.dart';
import '../utils/travel_salary_utils.dart';
import '../utils/work_schedule_load_utils.dart';
import 'payroll_policy.dart';

export 'payroll_policy.dart';

/// Giờ để nhân đơn giá khi lương theo giờ.
///
/// [payHours] là giờ công gốc (không trần 8h, không nhân hệ số lễ).
/// [weekdayInside] / nghỉ / lễ là phần tăng ca đã nằm trong [payHours]
/// nên lương tăng ca chỉ được cộng thêm hệ số, không trả lần hai.
class HourlyPayHours {
  const HourlyPayHours({
    required this.payHours,
    required this.weekdayInside,
    required this.weekendInside,
    required this.holidayInside,
  });

  final double payHours;
  final double weekdayInside;
  final double weekendInside;
  final double holidayInside;

  static HourlyPayHours split(
    List<DailyShiftRecord> records,
    double standardDayHours, {
    /// Lương giờ được trả ngày lễ riêng (Chính sách tính lương) → đi làm ngày lễ chỉ cộng phần hệ số,
    /// tránh 100% lễ + 100% giờ làm + 300% tăng ca.
    bool holidayPremiumOnly = false,
  }) {
    var pay = 0.0;
    var weekday = 0.0;
    var weekend = 0.0;
    var holiday = 0.0;
    for (final r in records) {
      final hours = r.baseWorkHours > 0 ? r.baseWorkHours : r.workHours;
      if (hours <= 0) continue;
      pay += hours;
      final isHoliday = r.status.contains('Tăng ca ngày lễ');
      final isWeekend = r.status.contains('Tăng ca ngày nghỉ');
      if (isHoliday && holidayPremiumOnly) {
        holiday += hours;
        continue;
      }
      if (isWeekend && !isHoliday) {
        // Ngày nghỉ tuần: cả ngày là tăng ca (bảng tổng hợp tính toàn bộ giờ gốc vào OT ngày nghỉ)
        // → phần 1.0 đã nằm trong lương giờ, cột tăng ca chỉ còn phần hệ số. Trước đây chỉ trừ
        // phút OT ghi nhận (thường 0) → trả 100% + 200% = 300% thay vì 200%.
        weekend += hours;
        continue;
      }
      final ot = r.overtimeMinutes / 60.0;
      if (ot <= 0) continue;
      final inside = (isHoliday || isWeekend)
          ? ot
          : () {
              final excess = hours - standardDayHours;
              if (excess <= 0) return 0.0;
              return ot < excess ? ot : excess;
            }();
      if (inside <= 0) continue;
      if (isHoliday) {
        holiday += inside;
      } else if (isWeekend) {
        weekend += inside;
      } else {
        weekday += inside;
      }
    }
    return HourlyPayHours(
      payHours: pay,
      weekdayInside: weekday,
      weekendInside: weekend,
      holidayInside: holiday,
    );
  }
}

/// Nạp dữ liệu kỳ lương (qua [PayrollApi]) và tính bảng lương từng nhân viên.
class PayrollEngine {
  PayrollEngine({
    required this.api,
    this.isEmployeeRole = false,
    Map<int, String>? salaryTypeLabels,
    void Function(String message)? log,
  })  : salaryTypeLabels = salaryTypeLabels ?? defaultSalaryTypeLabels,
        _logger = log;

  /// Nhãn loại lương mặc định (tiếng Việt). App truyền nhãn theo ngôn ngữ đang dùng.
  static const defaultSalaryTypeLabels = {0: 'Giờ', 1: 'Tháng', 2: 'Ngày', 3: 'Ca'};

  final PayrollApi api;

  /// Người xem là nhân viên (chỉ xem lương của mình → dùng API tự phục vụ).
  bool isEmployeeRole;
  Map<int, String> salaryTypeLabels;
  final void Function(String message)? _logger;
  void _log(String m) => _logger?.call(m);

  /// Chấm công màn cha đã tải (tháng đang chọn) — dùng lại nếu bao trùm kỳ lương.
  List<Attendance> parentAttendances = const [];
  DateTime? parentFrom;
  DateTime? parentTo;

  DateTime fromDate = DateTime.now();
  DateTime toDate = DateTime.now();
  int notConfiguredSalaryCount = 0;

  /// Xóa bộ nhớ tạm công theo ca (khi đổi chấm công / chi nhánh).
  void invalidate() {
    cachedShiftRecords = null;
    shiftRecordsByEmpKey = null;
  }

  // ═══ Data ═══
  List<Employee> employees = [];
  List<Map<String, dynamic>> employeeSalaryProfiles = [];
  Map<String, dynamic> insuranceSettings = {};
  // ignore: unused_field
  Map<String, dynamic> salarySettings = {};
  Map<String, dynamic> taxSettings = {};
  List<Map<String, dynamic>> allowanceSettings = [];
  List<Map<String, dynamic>> transactions = [];
  /// Phiếu phạt chấm công (đi trễ/về sớm/…) trong kỳ — tránh trừ trùng với latePenalty.
  List<Map<String, dynamic>> penaltyTickets = [];
  List<Map<String, dynamic>> advanceRequests = [];
  /// Khoản cộng/trừ lương tính sẵn trên server (api/hr-finance/payroll-adjustments).
  /// null = server chưa hỗ trợ / lỗi → dùng cách tính cũ trên máy.
  Map<String, HrFinPayrollAdj>? payrollAdj;
  // ignore: unused_field
  List<Map<String, dynamic>> shifts = [];
  List<Map<String, dynamic>> holidays = [];
  List<Map<String, dynamic>> workSchedules = [];
  Set<String> scheduleDayOffKeys = {};
  Set<String> scheduleWorkDayKeys = {};
  List<Map<String, dynamic>> shiftSalaryLevels = [];
  List<Map<String, dynamic>> employeeTaxDeductions = [];
  List<Map<String, dynamic>> kpiEmployeeTargets = [];

  Map<String, dynamic> commissionSettings = {};
  List<Map<String, dynamic>> productionSummaries = [];
  /// Lương KPI theo NV do server tính (cùng công thức tab Lương KPI). null = server cũ → tính trên app.
  Map<String, double>? kpiPayrollAmounts;

  // Attendance loaded for selected period (from parent screen)
  List<Attendance> periodAttendances = [];

  int dayEndHour = 0;
  int dayEndMinute = 0;
  double minHoursForWorkDay = 0;
  bool decimalWorkDayEnabled = false;
  double standardWorkHours = 8;
  List<DailyShiftRecord>? cachedShiftRecords;
  Map<String, List<DailyShiftRecord>>? shiftRecordsByEmpKey;
  Map<String, double> travelHoursByEmpKey = {};
  TravelSalaryMode travelSalaryMode = TravelSalaryMode.off;
  double travelFixedHourlyRate = 0;

  bool get showTravelPayrollColumns {
    if (travelSalaryMode != TravelSalaryMode.off) return true;
    for (final entry in employeeSalaryProfiles) {
      final raw = entry['profile'];
      if (raw is! Map) continue;
      final profile = Map<String, dynamic>.from(raw);
      final benefit = profile['benefit'];
      final map = benefit is Map
          ? Map<String, dynamic>.from(benefit)
          : profile;
      if (isTravelSalaryEnabledForEmployee(benefit: map)) return true;
    }
    return false;
  }

  // ──────── Data loading ────────
  Future<T> loadWithTimeout<T>(Future<T> future, T fallback,
      {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await future.timeout(timeout);
    } catch (e) {
      _log('Payroll load timeout/error: $e');
      return fallback;
    }
  }

  static String normEmpId(String id) => id.toLowerCase().trim();

  /// Hồ sơ lương thật (có bảng lương) — không phải hồ sơ rỗng máy chủ trả cho NV chưa gán.
  static bool isRealSalaryProfile(Object? profile) {
    if (profile is! Map) return false;
    final b = profile['benefit'] ?? profile['Benefit'];
    return b is Map && b.isNotEmpty;
  }

  bool hasSalaryProfile(Employee e) {
    if (salaryTimeline[normEmpId(e.id)]?.isNotEmpty == true) return true;
    final sp = employeeSalaryProfiles
        .where((x) => x['employeeId'] == e.id)
        .firstOrNull;
    return isRealSalaryProfile(sp?['profile']);
  }

  void putSalaryProfile(
    Map<String, dynamic> profileMap,
    String employeeId,
    Map<String, dynamic> profile,
  ) {
    final key = normEmpId(employeeId);
    if (key.isEmpty) return;
    profileMap[key] = profile;
    final fromProfile = profile['employeeId']?.toString() ?? '';
    if (fromProfile.isNotEmpty) {
      profileMap[normEmpId(fromProfile)] = profile;
    }
  }

  /// Tải map employeeId → hồ sơ lương (batch cho quản lý; NV dùng /api/benefits/me).
  Future<Map<String, dynamic>> loadSalaryProfileMap(
    List<Employee> employees, {
    bool preferSelfServiceApi = false,
  }) async {
    final profileMap = <String, dynamic>{};

    if (preferSelfServiceApi) {
      final meProfile = await loadWithTimeout(
        api.getMyEmployeeSalaryProfile(),
        null,
      );
      if (meProfile != null && employees.isNotEmpty) {
        putSalaryProfile(profileMap, employees.first.id, meProfile);
      }
    }

    if (profileMap.isEmpty) {
      final allProfiles = await loadWithTimeout(
        api.getEmployeeSalaryProfiles(),
        <dynamic>[],
      );
      for (final p in allProfiles) {
        if (p is Map<String, dynamic>) {
          final eid = (p['employeeId'] ?? p['EmployeeId'])?.toString() ?? '';
          if (eid.isNotEmpty) putSalaryProfile(profileMap, eid, p);
        }
      }
    }

    for (final emp in employees) {
      final key = normEmpId(emp.id);
      if (key.isNotEmpty && profileMap.containsKey(key)) continue;
      final profile = await api.getEmployeeSalaryProfile(emp.id);
      if (profile != null) {
        putSalaryProfile(profileMap, emp.id, profile);
      }
    }

    return profileMap;
  }


  /// Tiền phép năm trả trong kỳ (Phép năm › Trả tiền / Chốt năm): mã NV (thường) → số tiền.
  Map<String, double> leavePayouts = {};

  Future<void> loadLeavePayouts() async {
    leavePayouts = {};
    final res = await loadWithTimeout(
      api.getAnnualLeavePayouts(fromDate, toDate),
      <String, dynamic>{},
    );
    if (res['isSuccess'] != true || res['data'] is! List) return;
    for (final x in (res['data'] as List).whereType<Map>()) {
      leavePayouts[normEmpId('${x['employeeId']}')] = toDouble(x['amount']);
    }
  }

  /// Lịch sử hồ sơ lương trong kỳ: mã NV (thường) → các đoạn.
  Map<String, List<SalarySeg>> salaryTimeline = {};

  Future<void> loadSalaryTimeline() async {
    salaryTimeline = {};
    final res = await loadWithTimeout(
      api.getSalaryTimeline(fromDate, toDate),
      <String, dynamic>{},
    );
    if (res['isSuccess'] != true || res['data'] is! List) return;
    for (final t in (res['data'] as List).whereType<Map>()) {
      final segs = <SalarySeg>[];
      for (final s in (t['segments'] as List? ?? const []).whereType<Map>()) {
        final b = s['benefit'];
        final from = DateTime.tryParse('${s['from']}');
        final to = DateTime.tryParse('${s['to']}');
        if (b is! Map || from == null || to == null) continue;
        segs.add(SalarySeg(
          benefit: Map<String, dynamic>.from(b),
          from: DateTime(from.year, from.month, from.day),
          to: DateTime(to.year, to.month, to.day),
        ));
      }
      if (segs.isNotEmpty) salaryTimeline[normEmpId('${t['employeeId']}')] = segs;
    }
  }


  /// Màn cha tải đúng 1 tháng (picker 8/2026). Kỳ lọc tab («Tháng trước»,
  /// tuần, tùy chọn…) có thể lệch → phải tải log riêng cho kỳ đó.
  bool parentAttendancesCoverPeriod(DateTime fromDay, DateTime toEnd) {
    final pf = parentFrom, pt = parentTo;
    // Máy chủ: không có màn cha → luôn tự tải chấm công của kỳ.
    if (pf == null || pt == null) return false;
    final pFrom = DateTime(
      pf.year,
      pf.month,
      pf.day,
    );
    final pTo = DateTime(
      pt.year,
      pt.month,
      pt.day,
      23,
      59,
      59,
    );
    return !fromDay.isBefore(pFrom) && !toEnd.isAfter(pTo);
  }

  Future<void> loadPeriodAttendances() async {
    final fromDay = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final toEnd = DateTime(
      toDate.year,
      toDate.month,
      toDate.day,
      23,
      59,
      59,
    );

    List<Attendance> filterParent() => parentAttendances.where((a) {
          final t = a.attendanceTime;
          return !t.isBefore(fromDay) && !t.isAfter(toEnd);
        }).toList();

    // Ca đêm tan sau giờ chốt ngày: màn cha không tải sáng hôm sau ngày cuối kỳ → tự tải (khung rộng hơn).
    final needsWiderWindow = overnightFetchCutoffMinutes() > dayEndHour * 60 + dayEndMinute;
    if (!needsWiderWindow && parentAttendancesCoverPeriod(fromDay, toEnd)) {
      periodAttendances = filterParent();
      return;
    }

    // Kỳ lệch tháng màn cha (vd. chọn «Tháng trước» khi picker đang tháng hiện tại).
    try {
      final bootstrap = await loadAttendancesFor(fromDay, toEnd);
      periodAttendances = bootstrap.attendances;
      if (dayEndHour == 0 && dayEndMinute == 0) {
        dayEndHour = bootstrap.dayEndHour;
        dayEndMinute = bootstrap.dayEndMinute;
      }
    } catch (e) {
      _log('Payroll period attendances reload failed: $e');
      periodAttendances = filterParent();
    }
  }

  /// Mốc muộn nhất (phút) mà giờ ra ca qua đêm còn thuộc ngày trước — theo mọi ca qua đêm đang dùng.
  int overnightFetchCutoffMinutes() {
    var m = 0;
    for (final sh in shifts) {
      if (sh['isActive'] == false || isOvertimeShiftTemplate(sh) || !isOvernightShiftTemplate(sh)) continue;
      final c = overnightShiftCutoffMinutes(sh);
      if (c > m) m = c;
    }
    return m;
  }

  /// Chính sách tính lương của cửa hàng (theo luật / tùy chỉnh) — đọc từ thiết lập lương.
  PayrollPolicy get policy => PayrollPolicy.fromSalarySettings(salarySettings);

  /// Đơn nghỉ đã duyệt trong kỳ (phép năm, việc riêng có lương, không lương, ốm BHXH…).
  List<Map<String, dynamic>> approvedLeaves = [];

  /// (mã NV → ngày → (công được trả, có đơn nghỉ)) — dựng một lần mỗi kỳ.
  Map<String, Map<String, ({double paid, bool any})>>? _leaveDays;

  Future<void> loadApprovedLeaves() async {
    approvedLeaves = [];
    _leaveDays = null;
    try {
      String ymd(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final items = await loadLeavesForPeriod(api, fromDate: ymd(fromDate), toDate: ymd(toDate), status: 'Approved');
      approvedLeaves = [
        for (final l in items)
          if (l is Map) Map<String, dynamic>.from(l),
      ];
    } catch (e) {
      _log('Error loading approved leaves: $e');
    }
  }

  /// Ngày nghỉ được TRẢ LƯƠNG: đơn «DN trả lương» (phép năm, việc riêng có lương, nghỉ bù…)
  /// hoặc đơn bật «vẫn tính công». Không lương / ốm BHXH / thai sản (BHXH chi trả) → không trả.
  static bool isPaidLeave(Map<String, dynamic> lv) {
    if (lv['countAsWork'] == true) return true;
    final src = '${lv['paymentSource'] ?? 0}'.toLowerCase();
    return src == '0' || src == 'employerpaid';
  }

  ({double paid, bool any}) leaveOn(Employee? emp, DateTime day) {
    if (emp == null) return (paid: 0, any: false);
    final map = _leaveDays ??= _buildLeaveDays();
    final key = '${day.year}-${day.month}-${day.day}';
    return map[emp.id.toLowerCase()]?[key] ??
        map['u:${(emp.applicationUserId ?? '').toLowerCase()}']?[key] ??
        (paid: 0, any: false);
  }

  Map<String, Map<String, ({double paid, bool any})>> _buildLeaveDays() {
    final out = <String, Map<String, ({double paid, bool any})>>{};
    for (final lv in approvedLeaves) {
      final st = '${lv['status'] ?? ''}'.toLowerCase();
      if (st != 'approved' && st != '1') continue;
      final start = DateTime.tryParse('${lv['startDate'] ?? ''}');
      final end = DateTime.tryParse('${lv['endDate'] ?? ''}') ?? start;
      if (start == null || end == null) continue;
      final credit = isPaidLeave(lv) ? (lv['isHalfShift'] == true ? 0.5 : 1.0) : 0.0;
      final keys = <String>[
        if ('${lv['employeeId'] ?? ''}'.isNotEmpty) '${lv['employeeId']}'.toLowerCase(),
        if ('${lv['employeeUserId'] ?? ''}'.isNotEmpty) 'u:${'${lv['employeeUserId']}'.toLowerCase()}',
      ];
      for (var d = DateTime(start.year, start.month, start.day);
          !d.isAfter(DateTime(end.year, end.month, end.day));
          d = d.add(const Duration(days: 1))) {
        final dk = '${d.year}-${d.month}-${d.day}';
        for (final k in keys) {
          final prev = out[k]?[dk];
          (out[k] ??= {})[dk] = (paid: (prev?.paid ?? 0) > credit ? prev!.paid : credit, any: true);
        }
      }
    }
    return out;
  }

  /// Như màn cha (loadAttendanceBootstrap): máy chấm của cửa hàng + giờ chốt ngày → log chấm công.
  /// Nhân viên xem lương của mình: không lọc theo máy (API tự giới hạn theo người đăng nhập).
  Future<({List<Attendance> attendances, int dayEndHour, int dayEndMinute})> loadAttendancesFor(
      DateTime from, DateTime to) async {
    List<dynamic> devicesRaw = const [];
    if (!isEmployeeRole) {
      try {
        devicesRaw = await api.getDevices(storeOnly: true);
      } catch (_) {}
    }
    final deviceIds = <String>[
      for (final d in devicesRaw)
        if (d is Map && (d['id'] ?? d['Id']) != null) '${d['id'] ?? d['Id']}',
    ];
    var endHour = 0, endMinute = 0;
    try {
      final r = await api.getAppSetting('day_end_time');
      if (r['isSuccess'] == true && r['data'] is Map) {
        final parts = ((r['data'] as Map)['value']?.toString() ?? '').split(':');
        if (parts.length >= 2) {
          endHour = int.tryParse(parts[0]) ?? 0;
          endMinute = int.tryParse(parts[1]) ?? 0;
        }
      }
    } catch (_) {}
    // Khung tải: lùi theo mốc ca đêm (giờ ra sáng hôm sau ngày cuối kỳ) — chỉ ảnh hưởng phạm vi tải,
    // ngày công vẫn xác định theo ca + giờ chốt ngày.
    final fetchEnd = overnightFetchCutoffMinutes() > endHour * 60 + endMinute
        ? overnightFetchCutoffMinutes()
        : endHour * 60 + endMinute;
    final atts = await loadAttendancesForPeriod(
      api,
      deviceIds: deviceIds,
      fromDate: from,
      toDate: to,
      dayEndHour: fetchEnd ~/ 60,
      dayEndMinute: fetchEnd % 60,
    );
    return (attendances: atts, dayEndHour: endHour, dayEndMinute: endMinute);
  }

  Future<void> loadTravelMobileRecords() async {
    travelHoursByEmpKey = {};
    try {
      final maps = await loadTravelHoursMaps(
        api: api,
        fromDate: fromDate,
        toDate: toDate,
        employeesList: employees
            .map((e) => {
                  'id': e.id,
                  'employeeCode': e.employeeCode,
                  'applicationUserId': e.applicationUserId,
                  'pin': e.pin,
                })
            .toList(),
      );
      travelHoursByEmpKey = maps.byEmployeeKey;
    } catch (e) {
      _log('Error loading travel mobile records: $e');
    }
  }

  double travelHoursForEmployee(Employee? emp) {
    if (emp == null) return 0;
    final id = emp.id.trim();
    if (id.isNotEmpty) {
      final byId = travelHoursByEmpKey[id];
      if (byId != null && byId > 0) return byId;
    }
    final code = emp.employeeCode.trim();
    if (code.isNotEmpty) {
      final byCode = travelHoursByEmpKey[code];
      if (byCode != null && byCode > 0) return byCode;
    }
    final pin = (emp.pin ?? '').trim();
    if (pin.isNotEmpty) {
      final byPin = travelHoursByEmpKey[pin];
      if (byPin != null && byPin > 0) return byPin;
    }
    final uid = (emp.applicationUserId ?? '').trim();
    if (uid.isNotEmpty) {
      final byUid = travelHoursByEmpKey[uid];
      if (byUid != null && byUid > 0) return byUid;
    }
    return 0;
  }

  /// Nạp toàn bộ dữ liệu kỳ [fromDate]–[toDate] (gán trước khi gọi).
  Future<void> loadPayrollData() async {
    cachedShiftRecords = null;
    shiftRecordsByEmpKey = null;
    travelHoursByEmpKey = {};
    try {
      try {
        final dayEndResult =
            await loadWithTimeout(api.getAppSetting('day_end_time'), {});
        if (dayEndResult['isSuccess'] == true && dayEndResult['data'] is Map) {
          final value = (dayEndResult['data'] as Map)['value']?.toString() ?? '';
          final parts = value.split(':');
          if (parts.length >= 2) {
            dayEndHour = int.tryParse(parts[0]) ?? 0;
            dayEndMinute = int.tryParse(parts[1]) ?? 0;
          }
        }
      } catch (_) {}
      // Load employees (paged API — request large page)
      final empList = await loadWithTimeout(
        api.getEmployees(pageSize: 1000),
        <dynamic>[],
      );
      employees = empList
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();

      // Hồ sơ lương: batch API chỉ manager+; NV dùng /api/benefits/me.
      employeeSalaryProfiles = [];
      // Đang làm + đã nghỉ việc trong/sau đầu kỳ (vẫn phải trả lương những ngày đã làm).
      final periodStart = DateTime(fromDate.year, fromDate.month, fromDate.day);
      final activeEmployees = employees
          .where((e) =>
              e.isActive ||
              (e.resignationDate != null && !e.resignationDate!.isBefore(periodStart)))
          .toList(growable: false);
      final profileMap = await loadSalaryProfileMap(
        activeEmployees,
        preferSelfServiceApi: isEmployeeRole,
      );
      employees = activeEmployees;
      for (final emp in employees) {
        employeeSalaryProfiles.add({
          'employeeId': emp.id,
          'employeeCode': emp.employeeCode,
          'profile': profileMap[normEmpId(emp.id)],
        });
      }

      // Load settings in parallel (each call capped — tránh quay mãi)
      final results = await Future.wait([
        loadWithTimeout(api.getInsuranceSettings(), {}),
        loadWithTimeout(api.getSalarySettings(), {}),
        // (mức phạt cài đặt — không còn dùng cho lương; giữ chỗ để thứ tự kết quả không đổi)
        Future<Map<String, dynamic>>.value(<String, dynamic>{}),
        loadWithTimeout(
          api.getTransactions(
            fromDate: fromDate,
            toDate: DateTime(
                toDate.year, toDate.month, toDate.day, 23, 59, 59),
            pageSize: 2000,
          ),
          <String, dynamic>{},
        ),
        loadWithTimeout(
          api.getAdvanceRequests(fromDate: fromDate, toDate: toDate),
          <String, dynamic>{},
        ),
        loadWithTimeout(api.getShifts(), <dynamic>[]),
        loadWithTimeout(api.getAllowanceSettings(), <dynamic>[]),
        loadWithTimeout(
            api.getHolidaySettings(fromDate.year), <dynamic>[]),
        loadWithTimeout(
          // Tải đủ mọi trang lịch (một trang 1.000 dòng không đủ cho cửa hàng đông NV).
          loadAllWorkSchedulesResponse(
            api,
            fromDate: fromDate,
            toDate: toDate,
          ),
          <String, dynamic>{},
          // Nhiều trang lịch → cho thêm thời gian (hết giờ sẽ mất ngày nghỉ theo lịch).
          timeout: const Duration(seconds: 45),
        ),
        loadWithTimeout(
          api.getPenaltyTickets(
            fromDate: fromDate,
            toDate: toDate,
            pageSize: 2000,
          ),
          <String, dynamic>{},
        ),
        loadWithTimeout(
          api.getHrFinPayrollAdjustments(fromDate, toDate),
          <String, dynamic>{},
        ),
      ]);

      insuranceSettings = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic>
          : {};
      salarySettings = results[1] is Map<String, dynamic>
          ? results[1] as Map<String, dynamic>
          : {};
      minHoursForWorkDay = parseMinHoursForWorkDay(
        salarySettings: salarySettings,
      );
      decimalWorkDayEnabled = parseDecimalWorkDayEnabled(
        salarySettings: salarySettings,
      );
      standardWorkHours = parseStandardWorkHours(
        salarySettings: salarySettings,
      );
      travelSalaryMode = parseTravelSalaryMode(salarySettings: salarySettings);
      travelFixedHourlyRate =
          parseTravelFixedHourlyRate(salarySettings: salarySettings);
      // results[2] (mức phạt cài đặt) không dùng cho lương nữa — phạt chỉ lấy từ phiếu phạt.

      final txnResult = results[3] as Map<String, dynamic>;
      transactions = extractList(txnResult['items'] ?? txnResult['data']);

      final advResult = results[4] as Map<String, dynamic>;
      advanceRequests = extractList(advResult['items'] ?? advResult['data']);

      shifts = extractList(results[5]);
      shiftById = null;
      allowanceSettings = extractList(results[6]);
      holidays = extractList(results[7]);
      workSchedules = extractWorkScheduleItems(
        results[8] is Map<String, dynamic>
            ? results[8] as Map<String, dynamic>
            : <String, dynamic>{},
      );
      final ticketResult = results[9] as Map<String, dynamic>;
      penaltyTickets =
          extractList(ticketResult['items'] ?? ticketResult['data']);
      final adjResult = results[10] is Map<String, dynamic>
          ? results[10] as Map<String, dynamic>
          : <String, dynamic>{};
      payrollAdj = adjResult['isSuccess'] == true && adjResult['data'] is List
          ? {
              for (final a in (adjResult['data'] as List).whereType<Map>())
                normEmpId('${a['employeeId']}'):
                    HrFinPayrollAdj.fromJson(Map<String, dynamic>.from(a)),
            }
          : null;
      final codeToGuid = <String, String>{
        for (final e in employees)
          if (e.employeeCode.isNotEmpty) e.employeeCode: e.id,
      };
      scheduleDayOffKeys = buildScheduleDayOffKeys(
        workSchedules,
        employeeCodeToGuid: codeToGuid,
      );
      scheduleWorkDayKeys = buildScheduleWorkDayKeys(
        workSchedules,
        employeeCodeToGuid: codeToGuid,
      );

      // Optional settings (timeout — tránh quay mãi khi API chậm/treo)
      final taxRes = await loadWithTimeout(
        api.getTaxSettings(),
        <String, dynamic>{},
      );
      taxSettings =
          taxRes is Map<String, dynamic> ? taxRes : <String, dynamic>{};
      final levels = await loadWithTimeout(
        api.getShiftSalaryLevels(),
        <String, dynamic>{},
      );
      if (levels['data'] is List) {
        shiftSalaryLevels = (levels['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        shiftSalaryLevels = [];
      }
      final deductions = await loadWithTimeout(
        api.getEmployeeTaxDeductions(),
        <dynamic>[],
      );
      employeeTaxDeductions = deductions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      commissionSettings = await loadWithTimeout(
        api.getCommissionSettings(),
        <String, dynamic>{},
      );
      final periodsRes = await loadWithTimeout(
        api.getKpiPeriods(),
        <String, dynamic>{'isSuccess': false},
      );
      if (periodsRes['isSuccess'] == true) {
        final periods =
            List<Map<String, dynamic>>.from(periodsRes['data'] ?? []);
        String? matchPeriodId;
        for (final p in periods) {
          final pStart = DateTime.tryParse(p['periodStart']?.toString() ?? '');
          final pEnd = DateTime.tryParse(p['periodEnd']?.toString() ?? '');
          if (pStart != null &&
              pEnd != null &&
              !fromDate.isAfter(pEnd) &&
              !toDate.isBefore(pStart)) {
            matchPeriodId = p['id']?.toString();
            break;
          }
        }
        if (matchPeriodId != null) {
          final targetsRes = await loadWithTimeout(
            api.getKpiEmployeeTargets(periodId: matchPeriodId),
            <String, dynamic>{'isSuccess': false},
          );
          if (targetsRes['isSuccess'] == true) {
            kpiEmployeeTargets =
                List<Map<String, dynamic>>.from(targetsRes['data'] ?? []);
          }
        }
      } else {
        kpiEmployeeTargets = [];
      }

      final prodRes = await loadWithTimeout(
        api.getProductionSummary(
          fromDate: fromDate,
          toDate: toDate,
        ),
        <String, dynamic>{'isSuccess': false},
      );
      if (prodRes['isSuccess'] == true) {
        productionSummaries =
            List<Map<String, dynamic>>.from(prodRes['data'] ?? []);
      } else {
        productionSummaries = [];
      }

      final kpiPayRes = await loadWithTimeout(
        api.getKpiSalaryForPayroll(from: fromDate, to: toDate),
        <String, dynamic>{'isSuccess': false},
      );
      if (kpiPayRes['isSuccess'] == true && kpiPayRes['data'] is Map) {
        final items = (kpiPayRes['data'] as Map)['items'];
        kpiPayrollAmounts = {
          if (items is List)
            for (final it in items.whereType<Map>())
              (it['employeeId'] ?? '').toString(): toDouble(it['amount']),
        };
      } else {
        kpiPayrollAmounts = null;
      }

      await loadSalaryTimeline();
      await loadApprovedLeaves();
      // Đếm sau khi có lịch sử hồ sơ lương: NV đổi / hết hồ sơ giữa kỳ vẫn tính là đã cài.
      notConfiguredSalaryCount =
          employees.where((e) => !hasSalaryProfile(e)).length;
      await loadLeavePayouts();
      await loadPeriodAttendances();
      await loadTravelMobileRecords();
    } catch (e) {
      _log('Error loading payroll data: $e');
    }
  }

  // ──────── Helper: safely extract list from dynamic response ────────
  List<Map<String, dynamic>> extractList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map) {
      // Might be {items: [...], totalCount: ...}
      final items = data['items'] ?? data['data'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  List<Map<String, dynamic>> salaryProfilesForShiftCalc() {
    final out = <Map<String, dynamic>>[];
    for (final entry in employeeSalaryProfiles) {
      final raw = entry['profile'];
      if (raw is! Map) continue;
      final profile = Map<String, dynamic>.from(raw);
      final benefit = profile['benefit'];
      if (benefit is Map) {
        final b = Map<String, dynamic>.from(benefit);
        profile['shiftsPerDay'] = b['shiftsPerDay'];
        profile['weeklyOffDays'] = b['weeklyOffDays'];
        profile['paidLeaveType'] = b['paidLeaveType'] ?? profile['paidLeaveType'];
        profile['holidayMultiplier'] = b['holidayMultiplier'] ??
            toDouble(salarySettings['weekendRate'], 2.0);
        profile['holidayOvertimeType'] = b['holidayOvertimeType'];
        profile['applyLateEarlyOnRestDayOt'] =
            b['applyLateEarlyOnRestDayOt'] ?? true;
        profile['restDayOtHoursOnly'] = b['restDayOtHoursOnly'] ?? false;
        profile['otRateWeekday'] =
            b['otRateWeekday'] ?? b['OTRateWeekday'] ?? b['oTRateWeekday'];
        profile['otRateWeekend'] =
            b['otRateWeekend'] ?? b['OTRateWeekend'] ?? b['oTRateWeekend'];
        profile['otRateHoliday'] =
            b['otRateHoliday'] ?? b['OTRateHoliday'] ?? b['oTRateHoliday'];
        // Bắt buộc lift — free2/once đọc từ profile['attendanceMode'].
        profile['attendanceMode'] =
            b['attendanceMode'] ?? profile['attendanceMode'];
        profile['description'] = b['description'] ?? profile['description'];
      }
      final empId = entry['employeeId']?.toString() ?? '';
      final empCode = entry['employeeCode']?.toString() ?? '';
      profile['employees'] = [
        {'id': empId, 'employeeCode': empCode},
      ];
      out.add(profile);
    }
    return out;
  }

  void ensureShiftRecordsCache() {
    if (cachedShiftRecords != null) return;
    final attendances =
        periodAttendances.isNotEmpty ? periodAttendances : parentAttendances;
    cachedShiftRecords = computeDailyShiftRecords(
      attendances: attendances,
      fromDate: fromDate,
      toDate: toDate,
      shiftTemplates: shifts,
      shiftSalaryLevels: shiftSalaryLevels,
      salaryProfiles: salaryProfilesForShiftCalc(),
      holidays: holidays,
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
      minHoursForWorkDay: minHoursForWorkDay,
      decimalWorkDayEnabled: decimalWorkDayEnabled,
      standardWorkHours: standardWorkHours,
      scheduleDayOffKeys: scheduleDayOffKeys,
    );
    shiftRecordsByEmpKey = {};
    for (final r in cachedShiftRecords!) {
      for (final key in {r.employeeCode, r.employeeId}) {
        if (key.isEmpty || key == '-') continue;
        shiftRecordsByEmpKey!.putIfAbsent(key, () => []).add(r);
      }
    }
  }

  List<DailyShiftRecord> shiftRecordsForEmployee(String empCode) {
    ensureShiftRecordsCache();
    final keys = <String>{empCode};
    final emp = findEmployee(empCode);
    if (emp != null) {
      keys.add(emp.id);
      keys.add(emp.employeeCode);
    }
    final list = <DailyShiftRecord>[];
    final seenDates = <String>{};
    for (final k in keys) {
      for (final r in shiftRecordsByEmpKey?[k] ?? const []) {
        final dk = '${r.employeeCode}|${DateFormat('yyyy-MM-dd').format(r.date)}';
        if (seenDates.add(dk)) list.add(r);
      }
    }
    return list;
  }

  /// Bản chụp chấm công kỳ lương — lưu độc lập khi chốt phiếu lương.
  Map<String, dynamic> buildAttendanceSnapshot(
      String empCode, Map<String, dynamic> row) {
    final shiftRecords = shiftRecordsForEmployee(empCode)
      ..sort((a, b) => a.date.compareTo(b.date));

    final attendances = (periodAttendances.isNotEmpty
            ? periodAttendances
            : parentAttendances)
        .where((a) => resolveAttEmployeeCode(a) == empCode)
        .toList()
      ..sort((a, b) => a.attendanceTime.compareTo(b.attendanceTime));

    String fmtTime(DateTime dt) =>
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return {
      'periodStart': DateTime(fromDate.year, fromDate.month, fromDate.day)
          .toIso8601String(),
      'periodEnd': DateTime(
              toDate.year, toDate.month, toDate.day, 23, 59, 59)
          .toIso8601String(),
      'employeeCode': empCode,
      'employeeName': row['name']?.toString() ?? '',
      'summary': {
        'workDays': row['workDays'],
        'standardDays': row['standardDays'],
        'paidLeaveDays': row['paidLeaveDays'],
        'absentDays': row['absentDays'],
        'totalHours': row['totalHours'],
        'standardHours': row['standardHours'],
        'otTotalHours': row['otTotalHours'],
        'lateCount': row['lateCount'],
        'lateMinutes': row['lateMinutes'],
        'earlyCount': row['earlyCount'],
        'earlyMinutes': row['earlyMinutes'],
        'travelHours': row['travelHours'],
        'travelSalary': row['travelSalary'],
      },
      'dailyRecords': shiftRecords.map((r) {
        final punches = r.punchTimes;
        return {
          'date': DateFormat('yyyy-MM-dd').format(r.date),
          'dayOfWeek': r.dayOfWeek,
          'shiftNames': r.shiftNames,
          'checkIn': punches.isNotEmpty ? fmtTime(punches.first) : null,
          'checkOut': punches.length > 1 ? fmtTime(punches.last) : null,
          'punchTimes':
              punches.map((t) => t.toIso8601String()).toList(growable: false),
          'workHours': r.workHours,
          'workCount': r.workCount,
          'lateMinutes': r.lateMinutes,
          'earlyMinutes': r.earlyMinutes,
          'overtimeMinutes': r.overtimeMinutes,
          'status': r.status,
        };
      }).toList(),
      'attendanceLogs': attendances
          .map((a) => {
                'id': a.id,
                'time': a.attendanceTime.toIso8601String(),
                'state': a.attendanceState,
                'stateLabel': a.attendanceState == 1 ? 'Ra' : 'Vào',
                'deviceName': a.deviceName ?? '',
                'verifyMode': a.verifyMode,
                'note': a.note,
                'locationName': a.locationName,
              })
          .toList(),
    };
  }

  // ──────── Helper: check if a date is holiday ────────
  bool isHoliday(DateTime date) {
    for (final h in holidays) {
      final hDate =
          h['date'] != null ? DateTime.tryParse(h['date'].toString()) : null;
      if (hDate == null) continue;
      final isRecurring = h['isRecurring'] == true;
      final dateMatch = isRecurring
          ? hDate.month == date.month && hDate.day == date.day
          : hDate.year == date.year &&
              hDate.month == date.month &&
              hDate.day == date.day;
      if (dateMatch) return true;
    }
    return false;
  }

  bool isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  /// Công chuẩn lịch (tháng − nghỉ có lương). Dùng khi mode Auto.
  double calcStandardWorkDays(
    String paidLeaveType,
    String paidDayOff, {
    String? employeeCode,
    String? employeeGuid,
  }) {
    int? scheduleOff;
    if (isSchedulePaidLeaveType(paidLeaveType) &&
        (employeeCode != null || employeeGuid != null)) {
      scheduleOff = countScheduleDayOffsInMonth(
        workSchedules,
        employeeCode: employeeCode ?? '',
        year: fromDate.year,
        month: fromDate.month,
        employeeGuid: employeeGuid,
      );
    }
    return calcCalendarStandardWorkDays(
      year: fromDate.year,
      month: fromDate.month,
      paidLeaveType: paidLeaveType,
      paidDayOff: paidDayOff,
      scheduleDayOffCount: scheduleOff,
    );
  }

  // ──────── Resolution helpers ────────
  String resolveAttEmployeeCode(Attendance att) {
    if (att.employeeId != null && att.employeeId!.isNotEmpty) {
      final emp = employees.where((e) => e.id == att.employeeId).firstOrNull;
      if (emp != null) return emp.employeeCode;
      final emp2 =
          employees.where((e) => e.employeeCode == att.employeeId).firstOrNull;
      if (emp2 != null) return emp2.employeeCode;
      return att.employeeId!;
    }
    if (att.pin != null && att.pin!.isNotEmpty) {
      final emp = employees
          .where((e) => e.pin == att.pin || e.employeeCode == att.pin)
          .firstOrNull;
      if (emp != null) return emp.employeeCode;
      return att.pin!;
    }
    return '-';
  }

  // _resolveAttEmployeeName used via calcEmployeePayroll
  String resolveAttEmployeeName(Attendance att) {
    final code = resolveAttEmployeeCode(att);
    final emp = employees.where((e) => e.employeeCode == code).firstOrNull;
    if (emp != null) return emp.fullName;
    if (att.employeeName != null && att.employeeName!.isNotEmpty) {
      return att.employeeName!;
    }
    if (att.deviceUserName != null && att.deviceUserName!.isNotEmpty) {
      return att.deviceUserName!;
    }
    return '-';
  }

  Employee? findEmployee(String code) {
    return employees
        .where((e) => e.employeeCode == code || e.id == code)
        .firstOrNull;
  }

  // ──────── Insurance salary calculation ────────
  // Returns raw salary before cap (for BHXH and BHTN which have different caps)
  double getInsuranceSalaryRaw(String socialInsType, double baseSalary,
      double completionSalary, double customInsuranceSalary) {
    switch (socialInsType) {
      case '0':
        return 0; // Không đóng
      case '1':
        return baseSalary;
      case '2':
        return baseSalary + completionSalary;
      case '3':
        final region = toInt(insuranceSettings['defaultRegion'], 1);
        switch (region) {
          case 1:
            return toDouble(insuranceSettings['minSalaryRegion1'], 4960000);
          case 2:
            return toDouble(insuranceSettings['minSalaryRegion2'], 4410000);
          case 3:
            return toDouble(insuranceSettings['minSalaryRegion3'], 3860000);
          case 4:
            return toDouble(insuranceSettings['minSalaryRegion4'], 3450000);
          default:
            return toDouble(insuranceSettings['minSalaryRegion1'], 4960000);
        }
      case '4':
        return customInsuranceSalary;
      default:
        return 0;
    }
  }

  double calculateInsuranceSalary(String socialInsType, double baseSalary,
      double completionSalary, double customInsuranceSalary) {
    final maxIns =
        toDouble(insuranceSettings['maxInsuranceSalary'], 46800000);
    final raw = getInsuranceSalaryRaw(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    // Áp dụng mức trần BHXH (20x lương cơ sở)
    return raw > maxIns ? maxIns : raw;
  }

  /// BHTN cap = 20 × regional minimum salary (different from BHXH cap)
  double calculateBhtnInsuranceSalary(String socialInsType, double baseSalary,
      double completionSalary, double customInsuranceSalary) {
    final raw = getInsuranceSalaryRaw(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    if (raw == 0) return 0;
    // BHTN cap = 20 × lương tối thiểu vùng (theo luật Việc làm 2013)
    final region = toInt(insuranceSettings['defaultRegion'], 1);
    double regionMin;
    switch (region) {
      case 1:
        regionMin = toDouble(insuranceSettings['minSalaryRegion1'], 4960000);
        break;
      case 2:
        regionMin = toDouble(insuranceSettings['minSalaryRegion2'], 4410000);
        break;
      case 3:
        regionMin = toDouble(insuranceSettings['minSalaryRegion3'], 3860000);
        break;
      case 4:
        regionMin = toDouble(insuranceSettings['minSalaryRegion4'], 3450000);
        break;
      default:
        regionMin = toDouble(insuranceSettings['minSalaryRegion1'], 4960000);
    }
    final maxBhtn = regionMin * 20;
    return raw > maxBhtn ? maxBhtn : raw;
  }

  // ──────── Safe numeric parsing helpers ────────
  static double toDouble(dynamic v, [double d = 0]) {
    if (v == null) return d;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? d;
    return d;
  }

  static int toInt(dynamic v, [int d = 0]) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? d;
    return d;
  }

  static double benefitField(Map<String, dynamic>? benefit, String key) {
    if (benefit == null) return 0;
    final pascal = key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';
    return toDouble(benefit[key] ?? benefit[pascal]);
  }

  /// Đọc phụ cấp từ danh mục — cùng thuật toán màn Thiết lập lương.
  /// PC cố định / theo ngày = mức cấu hình; Tổng PC kỳ = thực nhận theo công/giờ.
  Map<String, Map<String, dynamic>>? shiftById;

  /// Ca đã chấm đủ → phút làm trong khung ca / thời lượng ca (cho điều kiện phụ cấp).
  List<AllowanceWorkUnit> allowanceUnits(List<DailyShiftPair> pairs) {
    final byId = shiftById ??= {
      for (final s in shifts)
        if (s['id'] != null) '${s['id']}'.toLowerCase(): s,
    };
    final out = <AllowanceWorkUnit>[];
    for (final p in pairs) {
      final shift = p.shiftTemplateId == null ? null : byId[p.shiftTemplateId!.toLowerCase()];
      final m = shiftWindowMinutes(p, shift);
      if (m == null) continue;
      out.add(AllowanceWorkUnit(
        dayKey: AllowanceWorkUnit.keyOf(p.date),
        shiftId: p.shiftTemplateId,
        shiftName: p.shiftName,
        workedMinutes: m.worked,
        requiredMinutes: m.required,
      ));
    }
    return out;
  }

  ({
    double fixedAllowance,
    double dailyAllowanceRate,
    double hourlyAllowanceRate,
    double shiftAllowance,
    double dailyAllowance,
    double dailyDays,
    int shiftCount,
    List<String> misses,
    double total,
  }) _calcEmployeeAllowances({
    required String? employeeId,
    required double totalWorkHours,
    required List<DailyShiftPair> shiftPairs,
    required Map<String, double> allowanceDays,
    required int standardDayMinutes,
    required double shiftLevelAllowance,
  }) {
    final empId = employeeId ?? '';
    final fixedTotal = AllowanceCalculator.sumForEmployee(
      allowances: allowanceSettings,
      employeeId: empId,
      allowanceType: 0,
    );
    final dailyRateTotal = AllowanceCalculator.sumForEmployee(
      allowances: allowanceSettings,
      employeeId: empId,
      allowanceType: 1,
    );
    final hourlyRateTotal = AllowanceCalculator.sumForEmployee(
      allowances: allowanceSettings,
      employeeId: empId,
      allowanceType: 2,
    );
    // Theo ngày / theo ca: chỉ ngày / ca làm đủ thời gian trong ca (nếu khoản có điều kiện).
    final earned = AllowanceCalculator.earnedWithRules(
      allowances: allowanceSettings,
      employeeId: empId,
      units: allowanceUnits(shiftPairs),
      eligibleDays: allowanceDays,
      standardDayMinutes: standardDayMinutes,
    );

    final total = shiftLevelAllowance +
        fixedTotal +
        earned.daily +
        hourlyRateTotal * totalWorkHours +
        earned.shift;
    return (
      fixedAllowance: fixedTotal,
      dailyAllowanceRate: dailyRateTotal,
      hourlyAllowanceRate: hourlyRateTotal,
      shiftAllowance: earned.shift,
      dailyAllowance: earned.daily,
      dailyDays: earned.dailyDays,
      shiftCount: earned.shiftCount,
      misses: [for (final m in earned.misses) m.label],
      total: total,
    );
  }

  /// Parse SalaryRateType: backend sends string enum ("Hourly","Monthly","Daily","Shift") or int
  static int parseRateType(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      switch (v) {
        case 'Hourly':
          return 0;
        case 'Monthly':
          return 1;
        case 'Daily':
          return 2;
        case 'Shift':
          return 3;
        default:
          return int.tryParse(v) ?? 1;
      }
    }
    return 1; // default Monthly
  }

  // ──────── Salary calculation per employee ────────
  /// Tiền lương của một đoạn [segFrom, segTo] theo một hồ sơ lương.
  /// Kỳ lương có thay đổi lương giữa kỳ được tách nhiều đoạn rồi cộng lại.
  SegPay calcSegmentPay({
    required Employee? emp,
    required String empCode,
    required List<Attendance> empAttendances,
    required Map<String, dynamic>? benefit,
    required DateTime segFrom,
    required DateTime segTo,
    required double travelHours,
    double? billableOverride,
    bool wholePeriod = true,
  }) {
    final double baseSalary = benefitField(benefit, 'rate');
    final int rateType = parseRateType(benefit?['rateType'] ?? benefit?['RateType']);
    final double completionSalary = benefitField(benefit, 'completionSalary');
    final String socialInsType =
        (benefit?['socialInsuranceType'] ?? 0).toString();
    final double customInsuranceSalary = toDouble(benefit?['insuranceSalary']);
    final bool hasHealthInsurance = benefit?['hasHealthInsurance'] == true;

    // Overtime settings
    final int holidayOtType = toInt(benefit?['holidayOvertimeType'], 1);
    final double holidayOtDailyRate =
        toDouble(benefit?['holidayOvertimeDailyRate']);
    final int hourlyOtType = toInt(benefit?['hourlyOvertimeType'], 1);
    final double hourlyOtFixedRate =
        toDouble(benefit?['hourlyOvertimeFixedRate']);

    // Shift salary
    final int shiftSalaryType = toInt(benefit?['shiftSalaryType']);
    final double fixedShiftRate = toDouble(benefit?['fixedShiftRate']);

    // Paid leave settings
    final String paidDayOff = benefit?['weeklyOffDays']?.toString() ?? '';
    final String paidLeaveType =
        benefit?['paidLeaveType']?.toString() ?? 'sunday';

    // Scheduled check-in/check-out from benefit
    final String? checkInStr = benefit?['checkIn']?.toString();
    final String? checkOutStr = benefit?['checkOut']?.toString();
    int scheduledInHour = 8, scheduledInMin = 0;
    int scheduledOutHour = 17, scheduledOutMin = 0;
    if (checkInStr != null && checkInStr.contains(':')) {
      final parts = checkInStr.split(':');
      scheduledInHour = int.tryParse(parts[0]) ?? 8;
      scheduledInMin = int.tryParse(parts[1]) ?? 0;
    }
    if (checkOutStr != null && checkOutStr.contains(':')) {
      final parts = checkOutStr.split(':');
      scheduledOutHour = int.tryParse(parts[0]) ?? 17;
      scheduledOutMin = int.tryParse(parts[1]) ?? 0;
    }

    // Standard hours per day
    final double standardDayHours =
        toDouble(benefit?['standardHoursPerDay'], 8.0);

    // Salary type label
    String salaryTypeLabel;
    switch (rateType) {
      case 0:
        salaryTypeLabel = salaryTypeLabels[0] ?? 'Giờ';
        break;
      case 1:
        salaryTypeLabel = salaryTypeLabels[1] ?? 'Tháng';
        break;
      case 2:
        salaryTypeLabel = salaryTypeLabels[2] ?? 'Ngày';
        break;
      case 3:
        salaryTypeLabel = salaryTypeLabels[3] ?? 'Ca';
        break;
      default:
        salaryTypeLabel = salaryTypeLabels[1] ?? 'Tháng';
    }

    // ═══ Chấm công: cùng nguồn & thuật toán tab "Tổng hợp theo ca" ═══
    final segStart = DateTime(segFrom.year, segFrom.month, segFrom.day);
    final segEnd = DateTime(segTo.year, segTo.month, segTo.day);
    final shiftRecords = wholePeriod
        ? shiftRecordsForEmployee(empCode)
        : shiftRecordsForEmployee(empCode).where((r) {
          final d = DateTime(r.date.year, r.date.month, r.date.day);
          return !d.isBefore(segStart) && !d.isAfter(segEnd);
        })
        .toList();
    final shiftPairs = computeDailyShiftPairs(
      attendances: empAttendances,
      fromDate: segFrom,
      toDate: segTo,
      shiftTemplates: shifts,
      shiftSalaryLevels: shiftSalaryLevels,
      salaryProfiles: salaryProfilesForShiftCalc(),
      dayEndHour: dayEndHour,
      dayEndMinute: dayEndMinute,
      scheduleDayOffKeys: scheduleDayOffKeys,
    );
    final attStats = aggregatePayrollStatsFromShiftRecords(
      records: shiftRecords,
      standardDayHours: standardDayHours,
      shiftPairs: shiftPairs,
    );
    // Phụ cấp theo ngày: ngày có công (bỏ ngày chỉ tăng ca), công gốc chưa nhân hệ số lễ/nghỉ.
    final allowanceDays = <String, double>{
      for (final r in shiftRecords)
        if (r.baseWorkCount > 0 && !r.status.contains('Tăng ca ngày'))
          AllowanceWorkUnit.keyOf(r.date): r.baseWorkCount.clamp(0, 1).toDouble(),
    };

    final totalWorkHours = attStats.totalWorkHours;
    final standardHours = attStats.standardHours;
    final otHoursWeekday = attStats.otHoursWeekday;
    double otHoursWeekend = attStats.otHoursWeekend;
    final otHoursHoliday = attStats.otHoursHoliday;
    final workDays = attStats.workDays;
    final lateCount = attStats.lateCount;
    final lateMinutes = attStats.lateMinutes;
    final earlyCount = attStats.earlyCount;
    final earlyMinutes = attStats.earlyMinutes;
    final totalShifts = attStats.totalShifts;
    final overnightShifts = attStats.overnightShifts;

    final daysWithWork = <String>{
      for (final r in shiftRecords)
        if (r.workCount > 0) DateFormat('yyyy-MM-dd').format(r.date),
    };

    int paidLeaveDays = 0;
    int absentDays = 0;
    final nowTs = DateTime.now();
    final todayStart = DateTime(nowTs.year, nowTs.month, nowTs.day);
    final joinDay = emp?.joinDate == null
        ? null
        : DateTime(emp!.joinDate!.year, emp.joinDate!.month, emp.joinDate!.day);
    final resignDay = emp?.resignationDate == null
        ? null
        : DateTime(emp!.resignationDate!.year, emp.resignationDate!.month, emp.resignationDate!.day);

    // Ngày lễ rơi vào ngày làm việc + ngày nghỉ có lương đã duyệt (chưa chấm công ngày đó).
    // Điều 112–113 BLLĐ: nghỉ lễ / phép năm hưởng nguyên lương — trước đây lương tháng bị trừ những ngày này.
    int holidayPaidDays = 0;
    int holidayIdleDays = 0;
    double leavePaidDays = 0;
    bool employed(DateTime d) =>
        (joinDay == null || !d.isBefore(joinDay)) && (resignDay == null || !d.isAfter(resignDay));

    // Count paid leave and absent days
    for (var d = segFrom;
        !d.isAfter(segTo);
        d = d.add(const Duration(days: 1))) {
      final key = DateFormat('yyyy-MM-dd').format(d);
      final holiday = isHoliday(d);
      var flexWeekend = false;

      bool isPaidOff = false;
      switch (paidLeaveType) {
        case 'sunday':
          isPaidOff = d.weekday == DateTime.sunday;
          break;
        case 'saturday':
          isPaidOff = d.weekday == DateTime.saturday;
          break;
        case 'sat-sun':
          isPaidOff =
              d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
          break;
        case 'sat-afternoon-sun':
          isPaidOff = d.weekday == DateTime.sunday;
          // Saturday afternoon is counted as 0.5 in standardWorkDays calculation
          break;
        case 'schedule':
          isPaidOff = scheduleKeyHit(
            scheduleDayOffKeys,
            d,
            [empCode, if (emp != null) emp.id],
          );
          break;
        case 'off-1':
        case 'off-2':
        case 'off-3':
        case 'off-4':
          // Không có thứ nghỉ cố định — bỏ qua T7/CN (tránh phạt vắng ảo).
          flexWeekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
          isPaidOff = false;
          break;
        default:
          // Fallback: use weeklyOffDays (không mặc định CN khi trống).
          final weekly = paidDayOff.trim();
          if (weekly.isEmpty) {
            isPaidOff = false;
          } else {
            isPaidOff =
                (weekly.contains('Sunday') && d.weekday == DateTime.sunday) ||
                    (weekly.contains('Saturday') &&
                        d.weekday == DateTime.saturday);
          }
      }

      if (holiday) {
        // Lễ trùng ngày nghỉ tuần: không cộng (luật cho nghỉ bù ngày làm việc kế tiếp — cửa hàng tự xếp).
        if (!isPaidOff && employed(d) && !d.isAfter(todayStart)) {
          holidayPaidDays++;
          if (!daysWithWork.contains(key)) holidayIdleDays++;
        }
        continue;
      }
      if (flexWeekend) continue;
      final leave = isPaidOff ? (paid: 0.0, any: false) : leaveOn(emp, d);
      if (!isPaidOff && leave.paid > 0 && !daysWithWork.contains(key) && employed(d) && !d.isAfter(todayStart)) {
        leavePaidDays += leave.paid;
      }

      if (isPaidOff) {
        paidLeaveDays++;
      } else if (!daysWithWork.contains(key) &&
          !leave.any &&
          d.isBefore(todayStart) &&
          employed(d)) {
        // Theo lịch: chỉ đếm vắng khi có xếp ca làm và không chấm.
        if (isSchedulePaidLeaveType(paidLeaveType)) {
          final onWorkDay = scheduleKeyHit(
            scheduleWorkDayKeys,
            d,
            [empCode, if (emp != null) emp.id],
          );
          if (!onWorkDay) continue;
        }
        absentDays++;
      }
    }

    // ═══ Công chuẩn & công tính lương (theo thiết lập NV) ═══
    final scheduleOffCount = isSchedulePaidLeaveType(paidLeaveType)
        ? countScheduleDayOffsInMonth(
            workSchedules,
            employeeCode: empCode,
            year: fromDate.year,
            month: fromDate.month,
            employeeGuid: emp?.id,
          )
        : null;
    // Ngày lễ + nghỉ có lương được trả như ngày công cho loại lương trong phạm vi Chính sách tính lương
    // (mặc định: lương tháng + lương ngày; theo luật: mọi loại).
    final pol = policy;
    final holidayCovered = pol.holidayPayScope.covers(rateType);
    final leaveCovered = pol.paidLeavePayScope.covers(rateType);
    final double holidayCredit = holidayCovered ? holidayPaidDays.toDouble() : 0;
    final double leaveCredit = leaveCovered ? leavePaidDays : 0;
    final double paidDaysCredit = holidayCredit + leaveCredit;
    final double daysWithPay = daysWithWork.length + (holidayCovered ? holidayIdleDays : 0) + leaveCredit;
    final resolvedStd = resolveStandardWorkDays(
      benefit: benefit,
      year: fromDate.year,
      month: fromDate.month,
      rawWorkDays: workDays + paidDaysCredit,
      paidLeaveType: paidLeaveType,
      paidDayOff: paidDayOff,
      scheduleDayOffCount: scheduleOffCount,
    );
    final double standardWorkDays = resolvedStd.divisor;
    double billableWorkDays = billableOverride ?? resolvedStd.billableWorkDays;

    // "Nghỉ N ngày bất kỳ/tháng" (off-1..off-4): không có thứ nghỉ cố định nên
    // không tính "Tăng ca ngày nghỉ" theo ngày (xem sửa weeklyOffDays khi lưu).
    // Thay vào đó: nếu công thực tế trong tháng VƯỢT công chuẩn (đã dùng ít hơn
    // N ngày nghỉ được phép) → phần công vượt được trả theo đơn giá "Tăng ca
    // ngày nghỉ" (x2), không trả theo đơn giá công thường (tránh trả thiếu).
    // Chỉ áp dụng cho lương tháng (rateType==1) — nơi công chuẩn thực sự giới
    // hạn lương thường; lương ngày/giờ/ca đã trả đủ theo công thực tế nên
    // cộng thêm OT ở đây sẽ bị trả trùng.
    if (wholePeriod &&
        rateType == 1 &&
        const ['off-1', 'off-2', 'off-3', 'off-4'].contains(paidLeaveType) &&
        resolvedStd.mode == EmployeeStandardWorkMode.monthMinusPaidLeave &&
        workDays + paidDaysCredit > standardWorkDays) {
      final excessWorkDays = workDays + paidDaysCredit - standardWorkDays;
      otHoursWeekend += excessWorkDays * standardDayHours;
      billableWorkDays = standardWorkDays;
    }

    // ═══ Salary calculation ═══
    double workSalary = 0;
    double hourlyRate = 0;
    double shiftLevelAllowance = 0;
    var hourlyPaidHours = totalWorkHours;
    var hourlyOtInsideHours = 0.0;

    switch (rateType) {
      case 0: // Hourly — giờ công thực tế × đơn giá, không trần giờ chuẩn/ngày
        hourlyRate = baseSalary;
        final split = HourlyPayHours.split(shiftRecords, standardDayHours, holidayPremiumOnly: holidayCovered);
        var paid = split.payHours;
        var dropFromBase = 0.0;
        if (hourlyOtType == 0) {
          dropFromBase += split.weekdayInside;
          if (holidayOtType != 0) {
            dropFromBase += split.weekendInside + split.holidayInside;
          }
        }
        if (holidayOtType == 0) {
          dropFromBase += split.weekendInside + split.holidayInside;
        }
        paid = double.parse(
          (paid - dropFromBase).clamp(0.0, double.infinity).toStringAsFixed(1),
        );
        hourlyPaidHours = paid;
        if (hourlyOtType == 1) {
          hourlyOtInsideHours = split.weekdayInside;
          if (holidayOtType != 0) {
            hourlyOtInsideHours += split.weekendInside + split.holidayInside;
          }
        }
        // Ngày lễ / nghỉ có lương (nếu chính sách trả cho lương giờ): giờ chuẩn / ngày × đơn giá.
        workSalary = (baseSalary * paid + paidDaysCredit * standardDayHours * baseSalary).roundToDouble();
        break;
      case 1: // Monthly
        // dailyRate = Rate / công chuẩn; workSalary = dailyRate × công tính lương
        hourlyRate = standardWorkDays > 0
            ? baseSalary / standardWorkDays / standardDayHours
            : 0;
        workSalary = standardWorkDays > 0
            ? (baseSalary / standardWorkDays) * billableWorkDays
            : 0;
        break;
      case 2: // Daily
        hourlyRate = baseSalary / standardDayHours;
        workSalary = baseSalary * (workDays + paidDaysCredit);
        break;
      case 3: // Shift-based
        if (shiftSalaryType == 0) {
          workSalary = applyOvernightShiftCoefficient(
            workSalary: fixedShiftRate * totalShifts,
            totalShifts: totalShifts,
            overnightShifts: overnightShifts,
            coefficient: pol.wholeShiftCoefficient,
          );
          hourlyRate = fixedShiftRate / standardDayHours;
          workSalary += paidDaysCredit * fixedShiftRate;
        } else {
          // Per-pair theo shiftTemplateId (nhiều mức lương ca).
          final shiftTotals = calcShiftBasedPayrollFromPairs(
            shiftPairs: shiftPairs,
            shiftSalaryLevels: shiftSalaryLevels,
            employeeGuid: emp?.id ?? '',
            fallbackFixedShiftRate: fixedShiftRate,
            standardDayHours: standardDayHours,
            totalWorkHours: totalWorkHours,
            nightCoefficient: pol.wholeShiftCoefficient,
            shiftById: shiftById ??= {
              for (final s in shifts)
                if (s['id'] != null) '${s['id']}'.toLowerCase(): s,
            },
          );
          workSalary = shiftTotals.workSalary;
          shiftLevelAllowance = shiftTotals.shiftAllowance;
          hourlyRate = shiftTotals.hourlyRate > 0
              ? shiftTotals.hourlyRate
              : (standardDayHours > 0
                  ? fixedShiftRate / standardDayHours
                  : 0);
          workSalary += paidDaysCredit * hourlyRate * standardDayHours;
        }
        break;
    }

    // Lương hoàn thành theo công (monthly only) — cùng công tính lương với LCB.
    double completionSalaryEarned = 0;
    if (rateType == 1 && completionSalary > 0 && standardWorkDays > 0) {
      completionSalaryEarned =
          (completionSalary / standardWorkDays) * billableWorkDays;
    }

    // ═══ OT salary — hệ số: Benefit.otRate* ?? store salary settings ?? 1.5/2/3 ═══
    final storeOtWeekday = toDouble(salarySettings['overtimeRate'], 1.5);
    final storeOtWeekend = toDouble(salarySettings['weekendRate'], 2.0);
    final storeOtHoliday = toDouble(salarySettings['holidayRate'], 3.0);
    final benefitOtWeekday = toDouble(
      benefit?['otRateWeekday'] ??
          benefit?['OTRateWeekday'] ??
          benefit?['oTRateWeekday'],
    );
    final benefitOtWeekend = toDouble(
      benefit?['otRateWeekend'] ??
          benefit?['OTRateWeekend'] ??
          benefit?['oTRateWeekend'],
    );
    final benefitOtHoliday = toDouble(
      benefit?['otRateHoliday'] ??
          benefit?['OTRateHoliday'] ??
          benefit?['oTRateHoliday'],
    );
    // Chính sách «theo luật»: hệ số không thấp hơn 1,5 / 2 / 3 (được cao hơn).
    final otRateWeekday =
        pol.otWeekday(benefitOtWeekday > 0 ? benefitOtWeekday : storeOtWeekday);
    // Ưu tiên hệ số cửa hàng khi NV không ghi đè OTRate* — đổi ở «Hệ số TC» áp dụng ngay.
    final otRateWeekend =
        pol.otRestDay(benefitOtWeekend > 0 ? benefitOtWeekend : storeOtWeekend);
    final otRateHoliday =
        pol.otHoliday(benefitOtHoliday > 0 ? benefitOtHoliday : storeOtHoliday);

    double otSalary = 0;
    if (hourlyOtType == 0) {
      // Đơn giá giờ cố định — trừ giờ đã trả theo đơn giá ngày (nếu có).
      var fixedHourHours = otHoursWeekday;
      if (holidayOtType != 0) {
        fixedHourHours += otHoursWeekend + otHoursHoliday;
      }
      otSalary = fixedHourHours * hourlyOtFixedRate;
    } else if (hourlyOtType == 1) {
      final otHourlyBaseMode = parseOvertimeHourlyBaseMode(
        benefit?['overtimeHourlyBaseMode'] ??
            benefit?['OvertimeHourlyBaseMode'],
      );
      final otHourlyRate = rateType == 1
          ? computeOvertimeHourlyRate(
              mode: otHourlyBaseMode,
              baseSalary: baseSalary,
              completionSalary: completionSalary,
              standardWorkDays: standardWorkDays,
              standardDayHours: standardDayHours,
              fallbackHourlyRate: hourlyRate,
            )
          : hourlyRate;
      otSalary += otHoursWeekday * otHourlyRate * otRateWeekday;
      // Ngày nghỉ: theo luật → × weekendRate; cố định ngày → không nhân giờ ở đây.
      if (holidayOtType != 0) {
        otSalary += otHoursWeekend * otHourlyRate * otRateWeekend;
      }
      // Ngày lễ: theo luật → × holidayRate; cố định ngày → không nhân giờ lần nữa.
      if (holidayOtType != 0) {
        otSalary += otHoursHoliday * otHourlyRate * otRateHoliday;
      }
    }

    double holidayDaySalary = 0;
    if (holidayOtType == 0) {
      // «Cố định ngày» cho tăng ca ngày nghỉ / ngày lễ.
      final restAndHolidayHours = otHoursWeekend + otHoursHoliday;
      if (restAndHolidayHours > 0 && standardDayHours > 0) {
        final days = (restAndHolidayHours / standardDayHours).ceil();
        holidayDaySalary = holidayOtDailyRate * days;
      }
    }
    otSalary += holidayDaySalary;
    if (rateType == 3 && hourlyOtType == 1 && holidayOtType != 0) {
      // Lương ca: ca làm ngày nghỉ tuần đã được trả theo đơn giá ca (100%) → cột tăng ca chỉ phần hệ số.
      final restDayHours = shiftRecords
          .where((r) =>
              (r.status.contains('Tăng ca ngày nghỉ') && !r.status.contains('Tăng ca ngày lễ')) ||
              (holidayCovered && r.status.contains('Tăng ca ngày lễ')))
          .fold<double>(0, (a, r) => a + r.baseWorkHours);
      if (restDayHours > 0) {
        otSalary -= restDayHours * hourlyRate;
        if (otSalary < 0) otSalary = 0;
      }
    }
    if (rateType == 0 && hourlyOtInsideHours > 0) {
      // 1.0 đã nằm trong lương giờ; cột tăng ca chỉ còn phần hệ số.
      otSalary -= hourlyOtInsideHours * hourlyRate;
      if (otSalary < 0) otSalary = 0;
    }

    // ═══ Phụ cấp làm đêm (Chính sách tính lương) ═══
    // Theo giờ: giờ thực làm trong 22:00–06:00 × đơn giá giờ × %. Cả ca: ca «Qua đêm» × giờ làm × %.
    // Lương ca tính «cả ca» đã nằm trong đơn giá ca (hệ số) — không cộng lần nữa.
    double nightHours = 0;
    double nightPremium = 0;
    if (pol.nightAppliesTo(rateType) && !(rateType == 3 && pol.nightBasis == NightBasis.wholeShift)) {
      for (final pr in shiftPairs.where((p) => p.checkOut != null)) {
        nightHours += pol.nightBasis == NightBasis.nightHours
            ? nightWorkHours(pr)
            : (pr.isOvernight ? dailyShiftPairWorkHours(pr) : 0);
      }
      final nightRate = rateType == 0 ? baseSalary : hourlyRate;
      nightPremium = (nightHours * nightRate * pol.nightPremiumPercent / 100).roundToDouble();
    }

    final travelMode = parseTravelSalaryModeForEmployee(
      benefit: benefit,
    );
    final travelFixedRate = parseTravelFixedHourlyRateForEmployee(
      benefit: benefit,
    );
    final double travelSalary = computeTravelSalary(
      travelHours: travelHours,
      mode: travelMode,
      travelFixedHourlyRate: travelFixedRate,
      baseSalary: baseSalary,
      completionSalary: completionSalary,
      standardWorkDays: standardWorkDays,
      standardDayHours: standardDayHours,
      workHourlyFallback: hourlyRate,
    );


    return SegPay(
      benefit: benefit,
      from: segFrom,
      to: segTo,
      baseSalary: baseSalary,
      rateType: rateType,
      completionSalary: completionSalary,
      socialInsType: socialInsType,
      customInsuranceSalary: customInsuranceSalary,
      hasHealthInsurance: hasHealthInsurance,
      salaryTypeLabel: salaryTypeLabel,
      shiftPairs: shiftPairs,
      totalWorkHours: totalWorkHours,
      standardHours: standardHours,
      otHoursWeekday: otHoursWeekday,
      otHoursWeekend: otHoursWeekend,
      otHoursHoliday: otHoursHoliday,
      workDays: workDays,
      lateCount: lateCount,
      lateMinutes: lateMinutes,
      earlyCount: earlyCount,
      earlyMinutes: earlyMinutes,
      totalShifts: totalShifts,
      overnightShifts: overnightShifts,
      paidLeaveDays: paidLeaveDays,
      absentDays: absentDays,
      holidayPaidDays: holidayPaidDays,
      leavePaidDays: leavePaidDays,
      paidDaysCredit: paidDaysCredit,
      daysWithPay: daysWithPay,
      nightHours: nightHours,
      nightPremium: nightPremium,
      standardWorkDays: standardWorkDays,
      billableWorkDays: billableWorkDays,
      scheduleOffCount: scheduleOffCount,
      paidLeaveType: paidLeaveType,
      paidDayOff: paidDayOff,
      workSalary: workSalary,
      hourlyRate: hourlyRate,
      shiftLevelAllowance: shiftLevelAllowance,
      hourlyPaidHours: hourlyPaidHours,
      completionSalaryEarned: completionSalaryEarned,
      otSalary: otSalary,
      travelHours: travelHours,
      travelSalary: travelSalary,
      allowanceDays: allowanceDays,
      standardDayMinutes: (standardDayHours * 60).round(),
    );
  }

  /// Các đoạn hồ sơ lương của nhân viên trong kỳ (từ server). Rỗng = dùng hồ sơ hiện hành.
  List<SalarySeg> salarySegmentsFor(Employee? emp) {
    if (emp == null) return const [];
    return salaryTimeline[normEmpId(emp.id)] ?? const [];
  }

  Map<String, dynamic> calcEmployeePayroll(
      String empCode, List<Attendance> empAttendances) {
    final emp = findEmployee(empCode);
    final empName = emp?.fullName ?? empCode;

    // Salary profile
    Map<String, dynamic>? profile;
    if (emp != null) {
      final sp = employeeSalaryProfiles
          .where((e) =>
              e['employeeId'] == emp.id ||
              e['employeeCode'] == emp.employeeCode)
          .firstOrNull;
      profile = sp?['profile'] as Map<String, dynamic>?;
    }

    Map<String, dynamic>? benefit;
    if (profile != null) {
      final rawBenefit = profile['benefit'] ?? profile['Benefit'];
      if (rawBenefit is Map) {
        benefit = Map<String, dynamic>.from(rawBenefit);
      }
    }
    // ═══ Lương theo hồ sơ hiệu lực từng ngày (đổi lương giữa kỳ → tách đoạn) ═══
    final travelHoursAll =
        showTravelPayrollColumns ? travelHoursForEmployee(emp) : 0.0;
    final segs = salarySegmentsFor(emp);
    late final SegPay pay;
    var parts = <SegPay>[];
    if (segs.length <= 1) {
      pay = calcSegmentPay(
        emp: emp,
        empCode: empCode,
        empAttendances: empAttendances,
        benefit: segs.isEmpty ? benefit : segs.first.benefit,
        segFrom: fromDate,
        segTo: toDate,
        travelHours: travelHoursAll,
      );
      parts = [pay];
    } else {
      // Lượt 1: công thực tế từng đoạn → chia công tính lương cả tháng theo tỷ lệ công.
      final raw = [
        for (final sg in segs)
          calcSegmentPay(
            emp: emp,
            empCode: empCode,
            empAttendances: empAttendances,
            benefit: sg.benefit,
            segFrom: sg.from,
            segTo: sg.to,
            travelHours: 0,
            wholePeriod: false,
          ),
      ];
      final rawTotal = raw.fold<double>(0, (a, p) => a + p.workDays + p.paidDaysCredit);
      final last = raw.last;
      final billableAll = resolveStandardWorkDays(
        benefit: last.benefit,
        year: fromDate.year,
        month: fromDate.month,
        rawWorkDays: rawTotal,
        paidLeaveType: last.paidLeaveType,
        paidDayOff: last.paidDayOff,
        scheduleDayOffCount: last.scheduleOffCount,
      ).billableWorkDays;
      final periodDays = toDate.difference(fromDate).inDays + 1;
      for (var k = 0; k < segs.length; k++) {
        final sg = segs[k];
        final share = rawTotal > 0
            ? (raw[k].workDays + raw[k].paidDaysCredit) / rawTotal
            : (sg.to.difference(sg.from).inDays + 1) / (periodDays <= 0 ? 1 : periodDays);
        parts.add(calcSegmentPay(
          emp: emp,
          empCode: empCode,
          empAttendances: empAttendances,
          benefit: sg.benefit,
          segFrom: sg.from,
          segTo: sg.to,
          travelHours: k == segs.length - 1 ? travelHoursAll : 0,
          billableOverride: raw[k].rateType == 1 ? billableAll * share : null,
          wholePeriod: false,
        ));
      }
      pay = SegPay.combine(parts);
    }
    benefit = pay.benefit;
    final double baseSalary = pay.baseSalary;
    final int rateType = pay.rateType;
    final double completionSalary = pay.completionSalary;
    final String socialInsType = pay.socialInsType;
    final double customInsuranceSalary = pay.customInsuranceSalary;
    final bool hasHealthInsurance = pay.hasHealthInsurance;
    final String salaryTypeLabel = parts.length > 1
        ? '${pay.salaryTypeLabel} (đổi lương ${DateFormat('dd/MM').format(parts.last.from)})'
        : pay.salaryTypeLabel;
    final shiftPairs = pay.shiftPairs;
    final totalWorkHours = pay.totalWorkHours;
    final standardHours = pay.standardHours;
    final otHoursWeekday = pay.otHoursWeekday;
    final otHoursWeekend = pay.otHoursWeekend;
    final otHoursHoliday = pay.otHoursHoliday;
    final workDays = pay.workDays;
    final lateCount = pay.lateCount;
    final lateMinutes = pay.lateMinutes;
    final earlyCount = pay.earlyCount;
    final earlyMinutes = pay.earlyMinutes;
    final totalShifts = pay.totalShifts;
    final overnightShifts = pay.overnightShifts;
    final paidLeaveDays = pay.paidLeaveDays;
    final absentDays = pay.absentDays;
    final double standardWorkDays = pay.standardWorkDays;
    final double workSalary = pay.workSalary;
    final double shiftLevelAllowance = pay.shiftLevelAllowance;
    final hourlyPaidHours = pay.hourlyPaidHours;
    final double completionSalaryEarned = pay.completionSalaryEarned;
    final double otSalary = pay.otSalary;
    final double travelHours = pay.travelHours;
    final double travelSalary = pay.travelSalary;

    // ═══ Allowances ═══
    final allowanceBreakdown = _calcEmployeeAllowances(
      employeeId: emp?.id,
      totalWorkHours: totalWorkHours,
      shiftPairs: shiftPairs,
      allowanceDays: pay.allowanceDays,
      standardDayMinutes: pay.standardDayMinutes,
      shiftLevelAllowance: shiftLevelAllowance,
    );
    final totalAllowance = allowanceBreakdown.total;
    final fixedAllowancePaid = allowanceBreakdown.fixedAllowance;
    final dailyAllowanceRate = allowanceBreakdown.dailyAllowanceRate;

    // ═══ Bonuses & penalties from transactions ═══
    double bonusTotal = 0;
    double penaltyTotal = 0;
    final empId = emp?.id;
    for (final tx in transactions) {
      // Match by employeeId or employeeUserId (backward compatibility)
      final txEmpId = tx['employeeId']?.toString();
      final txEmpUserId = tx['employeeUserId']?.toString();
      final myIds = {empCode, if (empId != null && empId.isNotEmpty) empId};
      if (!myIds.contains(txEmpId) && !myIds.contains(txEmpUserId)) {
        continue;
      }
      final txType = tx['type']?.toString().toLowerCase() ?? '';
      final amount = toDouble(tx['amount']);
      final status = tx['status']?.toString().toLowerCase() ?? '';
      // Chỉ trừ/cộng phiếu đã duyệt (không lấy Pending).
      if (status != 'approved' && status != 'completed') continue;
      // Bỏ qua thưởng/phạt đã chi tiền mặt; giữ thưởng chi vào lương (PaymentMethod=Salary)
      final txPaymentMethod = tx['paymentMethod']?.toString() ?? '';
      final isCashPaid =
          txPaymentMethod.isNotEmpty && txPaymentMethod != 'Salary';
      if (isCashPaid) continue;
      if (txType == 'bonus' || txType == 'reward' || txType == 'thưởng') {
        bonusTotal += amount;
      } else if (txType == 'penalty' || txType == 'fine' || txType == 'phạt') {
        penaltyTotal += amount.abs(); // Ensure positive for deduction
      }
    }

    // ═══ Phạt đi trễ / về sớm / vắng: CHỈ từ phiếu phạt «trừ vào lương» đã duyệt ═══
    // Không tự tính theo mức phạt cài đặt — ngày nào không lập phiếu thì không trừ.
    // Phiếu chờ duyệt chưa trừ; đã duyệt / tự duyệt mới trừ (hủy = không trừ).
    double latePenaltyTotal = 0;
    for (final t in penaltyTickets) {
      // Mọi loại phiếu (trễ, sớm, vắng, quên chấm, vi phạm, tái phạm) — phiếu «trừ lương».
      final st = t['status']?.toString() ?? '';
      if (st != 'Approved' && st != 'AutoApproved') continue;
      // Phiếu thu tiền mặt (có phiếu thu sổ quỹ) → không trừ lương.
      if (t['collectionMethod']?.toString() == 'Cash') continue;
      final tid = t['employeeId']?.toString() ?? '';
      if (tid.isEmpty || (tid != empId && tid != empCode)) continue;
      latePenaltyTotal += toDouble(t['amount']).abs();
    }

    // Nguồn chung từ server (cùng quy tắc với Tài chính nhân sự): ưu tiên khi có.
    final adj = payrollAdj == null || empId == null ? null : (payrollAdj![normEmpId(empId)]);
    if (payrollAdj != null && empId != null) {
      bonusTotal = adj?.bonus ?? 0;
      penaltyTotal = adj?.penalty ?? 0;
      latePenaltyTotal = adj?.ticketPenalty ?? 0;
    }

    // ═══ Insurance (BHXH, BHYT, BHTN, Đoàn phí) ═══
    // Use correct field names from InsuranceSetting entity (camelCase from C#)
    final double bhxhRate =
        toDouble(insuranceSettings['bhxhEmployeeRate'], 8);
    final double bhytRate =
        toDouble(insuranceSettings['bhytEmployeeRate'], 1.5);
    final double bhtnRate =
        toDouble(insuranceSettings['bhtnEmployeeRate'], 1);
    final double unionFeeRate =
        // Đoàn phí chỉ đoàn viên công đoàn đóng — mặc định 0% (cửa hàng tự bật trong Thiết lập bảo hiểm).
        toDouble(insuranceSettings['unionFeeEmployeeRate'], 0);

    final double insuranceSalary = calculateInsuranceSalary(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    // BHTN uses different cap (20x regional min salary, not 20x base salary)
    final double bhtnInsuranceSalary = calculateBhtnInsuranceSalary(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);

    // If socialInsType == '0' (chưa đóng BHXH), insuranceSalary = 0 => all = 0
    // Otherwise: mức đóng × hệ số tổng NLĐ đóng
    // Luật BHXH: tháng không làm việc và không hưởng lương từ 14 ngày làm việc trở lên → không đóng
    // BHXH / BHYT / BHTN tháng đó (mới vào giữa tháng, nghỉ không lương dài…). Chỉ xét khi kỳ là trọn
    // một tháng đã kết thúc — xem giữa tháng thì các ngày chưa tới không bị tính là «không làm».
    final today = DateTime.now();
    final monthEnded = !DateTime(toDate.year, toDate.month, toDate.day).isAfter(DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1)));
    final fullMonth = fromDate.day == 1 &&
        fromDate.year == toDate.year &&
        fromDate.month == toDate.month &&
        toDate.day == DateTime(toDate.year, toDate.month + 1, 0).day;
    final double unpaidWorkDays = (standardWorkDays - pay.daysWithPay).clamp(0, 31).toDouble();
    final insuranceSkipped =
        policy.bhxh14DayRule && fullMonth && monthEnded && socialInsType != '0' && unpaidWorkDays >= 14;
    final double insFactor = insuranceSkipped ? 0 : 1;

    final double bhxhPart = insFactor * insuranceSalary * bhxhRate / 100;
    final double bhytPart = insFactor * (hasHealthInsurance ? 0 : insuranceSalary * bhytRate / 100);
    final double bhtnPart = insFactor * bhtnInsuranceSalary * bhtnRate / 100;
    final double unionFeePart = insFactor * insuranceSalary * unionFeeRate / 100;
    final double totalInsurance = bhxhPart + bhytPart + bhtnPart + unionFeePart;

    // ═══ KPI / hoa hồng / lương sản phẩm (tính trước thuế — đều là thu nhập chịu thuế TNCN) ═══
    final kpiRow = kpiSalaryFor(emp);
    final double kpiSalaryAmount = kpiRow;
    final double salesAmount = salesFor(emp);
    final double commissionAmount = calculateCommission(salesAmount);
    final double productionAmount = productionFor(emp, empCode);
    final double leavePayout =
        empId == null ? 0 : (leavePayouts[normEmpId(empId)] ?? 0);

    // ═══ Tax (PIT – Vietnamese progressive) ═══
    // Trước đây bỏ sót lương công tác, hoa hồng, KPI, lương sản phẩm → thu nhập chịu thuế bị thấp.
    final double grossIncome = workSalary +
        completionSalaryEarned +
        otSalary +
        pay.nightPremium +
        travelSalary +
        totalAllowance +
        bonusTotal +
        commissionAmount +
        kpiSalaryAmount +
        productionAmount +
        leavePayout;
    final double taxableIncome = grossIncome - totalInsurance;
    double pit = 0;
    final double personalDeduction =
        toDouble(taxSettings['personalDeduction'], PitTaxDefaults.personalDeduction);
    final double dependentDeduction =
        toDouble(taxSettings['dependentDeduction'], PitTaxDefaults.dependentDeduction);

    // Get dependents from employee tax deductions
    int dependents = 0;
    if (emp != null) {
      final empTaxDed = employeeTaxDeductions
          .where((d) =>
              d['employeeId']?.toString() == emp.id ||
              d['employeeUserId']?.toString() == emp.id)
          .firstOrNull;
      if (empTaxDed != null) {
        dependents = toInt(empTaxDed['numberOfDependents']);
      }
    }

    final double taxable =
        taxableIncome - personalDeduction - (dependentDeduction * dependents);
    if (taxable > 0) {
      pit = calculatePIT(taxable);
    }

    // ═══ Advance (filter by PaidDate within period) ═══
    double advanceTotal = 0;
    for (final req in advanceRequests) {
      final reqEmpId =
          req['employeeId']?.toString() ?? req['employeeUserId']?.toString();
      if (reqEmpId != empId && reqEmpId != empCode) continue;
      final status = req['status'];
      final isPaid = req['isPaid'] == true;
      if ((status == 1 || status == 'Approved') && isPaid) {
        // Filter by payment date
        final paidDateStr = req['paidDate']?.toString();
        if (paidDateStr == null) continue;
        final paidDate = DateTime.tryParse(paidDateStr);
        if (paidDate == null) continue;
        final paidDay = DateTime(paidDate.year, paidDate.month, paidDate.day);
        final fromDay = DateTime(fromDate.year, fromDate.month, fromDate.day);
        final toDay = DateTime(toDate.year, toDate.month, toDate.day);
        if (paidDay.isBefore(fromDay) || paidDay.isAfter(toDay)) continue;
        // Trừ lương theo số tiền THỰC TẾ đã duyệt/chi (có thể thấp hơn số
        // tiền yêu cầu ban đầu nếu quản lý duyệt một phần).
        advanceTotal +=
            toDouble(req['approvedAmount'] ?? req['amount']);
      }
    }
    // Ứng lương trừ theo kỳ (ForMonth) + trả góp — tính trên server.
    if (payrollAdj != null && empId != null) advanceTotal = adj?.advance ?? 0;

    // ═══ Total deductions ═══
    final double totalDeduction =
        penaltyTotal + latePenaltyTotal + totalInsurance + pit + advanceTotal;

    // ═══ Net salary ═══
    final double totalSalary = workSalary +
        completionSalaryEarned +
        otSalary +
        pay.nightPremium +
        travelSalary +
        totalAllowance +
        bonusTotal +
        commissionAmount +
        kpiSalaryAmount +
        productionAmount +
        leavePayout;
    final double netSalary = totalSalary - totalDeduction;

    // ═══ Salary by type ═══
    double byKind(int k) => parts.where((p) => p.rateType == k).fold<double>(0, (a, p) => a + p.workSalary);
    final double dailySalary = byKind(2);
    final double shiftSalary = byKind(3);
    final double hourlySalary = byKind(0);
    final double otTotalHours =
        otHoursWeekday + otHoursWeekend + otHoursHoliday;

    final salaryProfileId =
        (benefit?['id'] ?? benefit?['Id'])?.toString() ?? '';

    final noProfile = benefit == null && segs.isEmpty;
    return {
      'code': empCode,
      'name': empName,
      'noSalaryProfile': noProfile,
      'employeeUserId': emp?.applicationUserId ?? '',
      'employeeId': emp?.id ?? '',
      'salaryProfileId': salaryProfileId,
      'salaryChanged': parts.length > 1,
      'salarySegments': [
        for (final p in parts)
          {
            'from': p.from.toIso8601String(),
            'to': p.to.toIso8601String(),
            'salaryType': p.salaryTypeLabel,
            'rateType': p.rateType,
            'baseSalary': p.baseSalary,
            'workDays': p.workDays,
            'workSalary': p.workSalary + p.completionSalaryEarned,
          },
      ],
      'department': emp?.department ?? '',
      'position': emp?.position ?? '',
      'salaryType': noProfile ? 'Chưa có bảng lương' : salaryTypeLabel,
      'rateType': rateType,
      'standardDays': standardWorkDays,
      'workDays': workDays,
      'totalShifts': totalShifts,
      'overnightShifts': overnightShifts,
      'paidLeaveDays': paidLeaveDays,
      'totalHours': rateType == 0 ? hourlyPaidHours : totalWorkHours,
      'standardHours': standardHours,
      'otTotalHours': otTotalHours,
      'otHoursWeekday': otHoursWeekday,
      'otHoursWeekend': otHoursWeekend,
      'otHoursHoliday': otHoursHoliday,
      'lateCount': lateCount,
      'lateMinutes': lateMinutes,
      'earlyCount': earlyCount,
      'earlyMinutes': earlyMinutes,
      'absentDays': absentDays,
      'holidayPaidDays': pay.holidayPaidDays,
      'leavePaidDays': pay.leavePaidDays,
      'paidDaysCredit': pay.paidDaysCredit,
      'unpaidWorkDays': unpaidWorkDays,
      'insuranceSkipped': insuranceSkipped,
      'nightHours': pay.nightHours,
      'nightPremium': pay.nightPremium,
      'payrollPolicy': policy.isLaw ? 'law' : 'custom',
      'baseSalary': baseSalary,
      // Cột bảng = số đã tính theo công (khớp Tổng lương). Mức cấu hình xem chi tiết.
      'completionSalary': completionSalaryEarned,
      'completionSalaryConfigured': completionSalary,
      'completionSalaryEarned': completionSalaryEarned,
      'dailySalary': dailySalary,
      'shiftSalary': shiftSalary,
      'hourlySalary': hourlySalary,
      'workSalary': workSalary,
      'otSalary': otSalary,
      'travelHours': travelHours,
      'travelSalary': travelSalary,
      'allowanceFixed': fixedAllowancePaid,
      'allowanceDaily': dailyAllowanceRate,
      'allowanceShift': allowanceBreakdown.shiftAllowance,
      'allowanceDailyEarned': allowanceBreakdown.dailyAllowance,
      'allowanceDays': allowanceBreakdown.dailyDays,
      'allowanceShiftCount': allowanceBreakdown.shiftCount,
      'allowanceMisses': allowanceBreakdown.misses,
      'mealAllowance': fixedAllowancePaid,
      'responsibilityAllowance': dailyAllowanceRate,
      'otherAllowance': 0,
      'totalAllowance': totalAllowance,
      'bonus': bonusTotal,
      'penalty': penaltyTotal + latePenaltyTotal,
      'penaltyTransactions': penaltyTotal,
      'kpiSalary': kpiSalaryAmount,
      'productionAmount': productionAmount,
      'leavePayout': leavePayout,
      'commission': commissionAmount,
      'latePenalty': latePenaltyTotal,
      'bhxh': totalInsurance,
      'bhxhPart': bhxhPart,
      'bhytPart': bhytPart,
      'bhtnPart': bhtnPart,
      'unionFeePart': unionFeePart,
      'insuranceSalary': insuranceSalary,
      'totalInsurance': totalInsurance,
      'taxableIncome': taxable > 0 ? taxable : 0,
      'pit': pit,
      'totalSalary': totalSalary,
      'advance': advanceTotal,
      'totalDeduction': totalDeduction,
      'netSalary': netSalary,
    };
  }

  double kpiSalaryFor(Employee? emp) {
    if (kpiPayrollAmounts != null) {
      // Server: gộp mọi chỉ tiêu của NV, ưu tiên lương KPI đã duyệt, kỳ trả vào tháng kết thúc kỳ.
      return kpiPayrollAmounts![emp?.id ?? ''] ?? 0;
    }
    final kpiTarget = kpiEmployeeTargets.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['employeeId']?.toString() == emp?.id,
          orElse: () => null,
        );
    if (kpiTarget == null) return 0;
    final tgt = ((kpiTarget['targetValue'] ?? 0) as num).toDouble();
    final act = ((kpiTarget['actualValue'] ?? 0) as num).toDouble();
    final pct = tgt > 0 ? act / tgt * 100 : 0.0;
    final cs = ((kpiTarget['completionSalary'] ?? 0) as num).toDouble();
    final salaryHT = pct >= 100 ? cs : 0.0;
    final penaltyBonus = kpiCalcPenaltyBonus(kpiTarget);
    final totalTierBonus =
        kpiCalcTierBonuses(kpiTarget).fold<double>(0, (s, b) => s + toDouble(b['bonus']));
    return salaryHT + penaltyBonus + totalTierBonus;
  }

  double salesFor(Employee? emp) {
    final t = kpiEmployeeTargets.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['employeeId']?.toString() == emp?.id && t?['criteriaType'] == 0,
          orElse: () => null,
        );
    return t == null ? 0 : toDouble(t['actualValue']);
  }

  double productionFor(Employee? emp, String empCode) {
    final s = productionSummaries.cast<Map<String, dynamic>?>().firstWhere(
          (s) => s?['employeeId']?.toString() == emp?.id || s?['employeeCode']?.toString() == empCode,
          orElse: () => null,
        );
    return s == null ? 0 : toDouble(s['totalAmount']);
  }

  // ──────── Commission calculation ────────
  double calculateCommission(double sales) {
    if (sales <= 0 || commissionSettings.isEmpty) return 0;
    final type = commissionSettings['commissionType'] ?? 'flat';
    final flatRate = toDouble(commissionSettings['flatRate']);
    final threshold = toDouble(commissionSettings['minSalesThreshold']);
    final maxCap = toDouble(commissionSettings['maxCommissionCap']);

    double commission = 0;
    switch (type) {
      case 'flat':
        commission = sales * flatRate / 100;
        break;
      case 'tiered':
        final tiers = commissionSettings['tiers'] as List? ?? [];
        for (final tier in tiers) {
          final min = toDouble(tier['minSales']);
          final max = toDouble(tier['maxSales'], double.infinity);
          final rate = toDouble(tier['rate']);
          if (sales <= min) continue;
          final inBand = (sales > max ? max : sales) - min;
          if (inBand > 0) commission += inBand * rate / 100;
        }
        break;
      case 'threshold':
        if (sales > threshold) {
          commission = (sales - threshold) * flatRate / 100;
        }
        break;
    }
    if (maxCap > 0 && commission > maxCap) commission = maxCap;
    return commission;
  }

  // ──────── PIT calculation (biểu thuế từ thiết lập cửa hàng) ────────
  double calculatePIT(double taxableIncome) {
    return calculateProgressivePit(taxableIncome, taxSettings);
  }

  // ──────── KPI Tier/Penalty calculation helpers ────────
  List<Map<String, dynamic>> kpiParseTiers(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty && list.first.containsKey('milestonePercent')) {
        final sorted = list
          ..sort((a, b) => ((a['milestonePercent'] ?? 0) as num)
              .compareTo((b['milestonePercent'] ?? 0) as num));
        final migrated = <Map<String, dynamic>>[];
        for (int i = 0; i < sorted.length; i++) {
          final from = (sorted[i]['milestonePercent'] as num?)?.toDouble() ?? 0;
          final to = i + 1 < sorted.length
              ? (sorted[i + 1]['milestonePercent'] as num?)?.toDouble() ?? -1
              : -1.0;
          migrated.add({
            'fromPct': from,
            'toPct': to,
            'rate': sorted[i]['bonusAmount'] ?? 0,
            'rateType': 0
          });
        }
        return migrated;
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> kpiParsePenaltyTiers(String? json) {
    if (json == null || json.isEmpty || json == 'null') return [];
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  double kpiCalcPenaltyBonus(Map<String, dynamic> target) {
    final pTiers =
        kpiParsePenaltyTiers(target['penaltyTiersJson']?.toString());
    if (pTiers.isEmpty) return 0;
    final tgt = ((target['targetValue'] ?? 0) as num).toDouble();
    final act = ((target['actualValue'] ?? 0) as num).toDouble();
    final pct = tgt > 0 ? act / tgt * 100 : 0.0;
    if (pct >= 100) return 0;
    for (final tier in pTiers) {
      final fromPct = ((tier['fromPct'] ?? 0) as num).toDouble();
      final toPct = ((tier['toPct'] ?? 100) as num).toDouble();
      final rate = ((tier['rate'] ?? 0) as num).toDouble();
      if (pct >= fromPct && pct < toPct) return rate;
    }
    return 0;
  }

  List<Map<String, dynamic>> kpiCalcTierBonuses(Map<String, dynamic> target) {
    final tiers = kpiParseTiers(target['bonusTiersJson']?.toString());
    final tgt = ((target['targetValue'] ?? 0) as num).toDouble();
    final act = ((target['actualValue'] ?? 0) as num).toDouble();
    final pct = tgt > 0 ? act / tgt * 100 : 0.0;
    final cs = ((target['completionSalary'] ?? 0) as num).toDouble();
    return tiers.map((tier) {
      final fromPct = ((tier['fromPct'] ?? 0) as num).toDouble();
      final toPct = ((tier['toPct'] ?? -1) as num).toDouble();
      final rate = ((tier['rate'] ?? 0) as num).toDouble();
      final rateType = ((tier['rateType'] ?? 0) as num).toInt();
      double bonus = 0;
      if (pct >= 100 && pct > fromPct) {
        if (rateType == 2) {
          bonus = rate;
        } else if (rateType == 3) {
          bonus = cs * rate / 100;
        } else {
          final fromVal = tgt * fromPct / 100;
          final toVal = toPct < 0 ? act : tgt * toPct / 100;
          final inBand = (act < toVal ? act : toVal) - fromVal;
          if (inBand > 0) {
            bonus = rateType == 1 ? inBand * rate / 100 : inBand * rate;
          }
        }
      }
      return {
        'fromPct': fromPct,
        'toPct': toPct,
        'rate': rate,
        'rateType': rateType,
        'bonus': bonus
      };
    }).toList();
  }

  /// Cảnh báo cấu hình làm SAI công / lương — hiện trên bảng lương để cửa hàng sửa.
  ///
  /// Ca kết thúc qua nửa đêm nhưng loại ca không phải «Qua đêm» (vd «Full 08:00–04:00» loại Hành chính):
  /// hệ thống không coi là ca qua đêm → giờ ra sau giờ chốt ngày bị tính sang hôm sau → thiếu công.
  /// (Ca loại «Qua đêm» đã tự ghép giờ ra sáng hôm sau, không phụ thuộc giờ chốt ngày.)
  List<String> configWarnings() {
    int? minutes(Object? v) {
      final p = '${v ?? ''}'.split(':');
      if (p.length < 2) return null;
      final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
      return h == null || m == null ? null : h * 60 + m;
    }

    String hhmm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final dayEnd = dayEndHour * 60 + dayEndMinute;
    final usedNames = <String>{};
    final usedIds = <String>{};
    for (final entry in employeeSalaryProfiles) {
      final raw = entry['profile'];
      final benefit = raw is Map ? (raw['benefit'] ?? raw['Benefit']) : null;
      final desc = benefit is Map ? '${benefit['description'] ?? ''}' : '';
      final m = RegExp(r'shifts:([^|]*)').firstMatch(desc);
      if (m != null) {
        usedNames.addAll(m.group(1)!.split(',').map((x) => x.trim().toLowerCase()).where((x) => x.isNotEmpty));
      }
    }
    for (final w in workSchedules) {
      final id = '${w['shiftId'] ?? w['shiftTemplateId'] ?? ''}'.toLowerCase();
      if (id.isNotEmpty) usedIds.add(id);
    }
    final out = <String>[];
    for (final sh in shifts) {
      if (sh['isActive'] == false) continue;
      final start = minutes(sh['startTime']), end = minutes(sh['endTime']);
      if (start == null || end == null || end >= start) continue; // không qua đêm
      if (isOvernightShiftTemplate(sh) || isOvertimeShiftTemplate(sh)) continue;
      final name = '${sh['name'] ?? ''}'.trim();
      final used = usedNames.contains(name.toLowerCase()) || usedIds.contains('${sh['id']}'.toLowerCase());
      if (!used || dayEnd >= end) continue;
      out.add('Ca «$name» ${hhmm(start)}–${hhmm(end)} kết thúc qua ngày hôm sau nhưng loại ca chưa đặt «Qua đêm»: '
          'giờ ra sau ${hhmm(dayEnd)} bị tính sang hôm sau nên nhân viên ca này bị thiếu công. '
          'Vào Thiết lập ca, đổi loại ca thành «Qua đêm».');
    }
    return out;
  }

  /// Dòng bảng lương cho mọi nhân viên (lọc theo [includeEmployee], ví dụ chi nhánh).
  /// Chưa sắp xếp / tìm kiếm — việc của màn hình.
  List<Map<String, dynamic>> computeRows({bool Function(Employee e)? includeEmployee}) {
    ensureShiftRecordsCache();
    final pool = includeEmployee == null ? employees : employees.where(includeEmployee).toList();
    final poolCodes = includeEmployee == null ? null : pool.map((e) => e.employeeCode).toSet();
    final attendances = periodAttendances.isNotEmpty ? periodAttendances : parentAttendances;
    final grouped = <String, List<Attendance>>{};
    for (final att in attendances) {
      final code = resolveAttEmployeeCode(att);
      if (code == '-') continue;
      if (poolCodes != null && !poolCodes.contains(code)) continue;
      grouped.putIfAbsent(code, () => []).add(att);
    }
    for (final emp in pool) {
      if (!grouped.containsKey(emp.employeeCode)) grouped[emp.employeeCode] = [];
    }
    return [for (final entry in grouped.entries) calcEmployeePayroll(entry.key, entry.value)];
  }
}

/// Một đoạn hồ sơ lương trong kỳ.
class SalarySeg {
  const SalarySeg({required this.benefit, required this.from, required this.to});
  final Map<String, dynamic> benefit;
  final DateTime from;
  final DateTime to;
}

/// Kết quả tính lương của một đoạn (một hồ sơ lương).
class SegPay {
  SegPay({
    required this.benefit,
    required this.from,
    required this.to,
    required this.baseSalary,
    required this.rateType,
    required this.completionSalary,
    required this.socialInsType,
    required this.customInsuranceSalary,
    required this.hasHealthInsurance,
    required this.salaryTypeLabel,
    required this.shiftPairs,
    required this.totalWorkHours,
    required this.standardHours,
    required this.otHoursWeekday,
    required this.otHoursWeekend,
    required this.otHoursHoliday,
    required this.workDays,
    required this.lateCount,
    required this.lateMinutes,
    required this.earlyCount,
    required this.earlyMinutes,
    required this.totalShifts,
    required this.overnightShifts,
    required this.paidLeaveDays,
    required this.absentDays,
    required this.standardWorkDays,
    required this.billableWorkDays,
    required this.scheduleOffCount,
    required this.paidLeaveType,
    required this.paidDayOff,
    required this.workSalary,
    required this.hourlyRate,
    required this.shiftLevelAllowance,
    required this.hourlyPaidHours,
    required this.completionSalaryEarned,
    required this.otSalary,
    required this.travelHours,
    required this.travelSalary,
    this.allowanceDays = const {},
    this.standardDayMinutes = 480,
    this.holidayPaidDays = 0,
    this.leavePaidDays = 0,
    this.paidDaysCredit = 0,
    this.daysWithPay = 0,
    this.nightHours = 0,
    this.nightPremium = 0,
  });

  /// Giờ làm đêm được phụ cấp và tiền phụ cấp làm đêm (ngoài đơn giá lương ca).
  final double nightHours;
  final double nightPremium;

  /// Ngày có hưởng lương (đi làm, kể cả nghỉ tuần / lễ; + lễ / nghỉ có lương được trả) — quy tắc BHXH 14 ngày.
  final double daysWithPay;

  /// Ngày lễ rơi vào ngày làm việc (được trả lương).
  final int holidayPaidDays;

  /// Ngày nghỉ có lương đã duyệt (phép năm, việc riêng có lương, «vẫn tính công»).
  final double leavePaidDays;

  /// Số ngày lễ + nghỉ có lương thực sự cộng vào lương (lương tháng / lương ngày).
  final double paidDaysCredit;

  final Map<String, dynamic>? benefit;
  final DateTime from;
  final DateTime to;
  final double baseSalary;
  final int rateType;
  final double completionSalary;
  final String socialInsType;
  final double customInsuranceSalary;
  final bool hasHealthInsurance;
  final String salaryTypeLabel;
  final List<DailyShiftPair> shiftPairs;
  final double totalWorkHours;
  final double standardHours;
  final double otHoursWeekday;
  final double otHoursWeekend;
  final double otHoursHoliday;
  final double workDays;
  final int lateCount;
  final int lateMinutes;
  final int earlyCount;
  final int earlyMinutes;
  final int totalShifts;
  final int overnightShifts;
  final int paidLeaveDays;
  final int absentDays;
  final double standardWorkDays;
  final double billableWorkDays;
  final int? scheduleOffCount;
  final String paidLeaveType;
  final String paidDayOff;
  final double workSalary;
  final double hourlyRate;
  final double shiftLevelAllowance;
  final double hourlyPaidHours;
  final double completionSalaryEarned;
  final double otSalary;
  final double travelHours;
  final double travelSalary;
  /// Ngày có công (yyyy-MM-dd → công gốc, chưa nhân hệ số lễ) — phụ cấp theo ngày.
  final Map<String, double> allowanceDays;
  /// Giờ chuẩn / ngày (phút) — thay thời lượng ca khi NV không có ca.
  final int standardDayMinutes;

  /// Cộng các đoạn; thông tin hồ sơ (loại lương, BHXH, công chuẩn) lấy theo đoạn cuối kỳ.
  static SegPay combine(List<SegPay> p) {
    final last = p.last;
    double sum(double Function(SegPay) f) => p.fold<double>(0, (a, x) => a + f(x));
    int isum(int Function(SegPay) f) => p.fold<int>(0, (a, x) => a + f(x));
    return SegPay(
      benefit: last.benefit,
      from: p.first.from,
      to: last.to,
      baseSalary: last.baseSalary,
      rateType: last.rateType,
      completionSalary: last.completionSalary,
      socialInsType: last.socialInsType,
      customInsuranceSalary: last.customInsuranceSalary,
      hasHealthInsurance: last.hasHealthInsurance,
      salaryTypeLabel: last.salaryTypeLabel,
      shiftPairs: [for (final x in p) ...x.shiftPairs],
      totalWorkHours: sum((x) => x.totalWorkHours),
      standardHours: sum((x) => x.standardHours),
      otHoursWeekday: sum((x) => x.otHoursWeekday),
      otHoursWeekend: sum((x) => x.otHoursWeekend),
      otHoursHoliday: sum((x) => x.otHoursHoliday),
      workDays: sum((x) => x.workDays),
      lateCount: isum((x) => x.lateCount),
      lateMinutes: isum((x) => x.lateMinutes),
      earlyCount: isum((x) => x.earlyCount),
      earlyMinutes: isum((x) => x.earlyMinutes),
      totalShifts: isum((x) => x.totalShifts),
      overnightShifts: isum((x) => x.overnightShifts),
      paidLeaveDays: isum((x) => x.paidLeaveDays),
      absentDays: isum((x) => x.absentDays),
      holidayPaidDays: isum((x) => x.holidayPaidDays),
      leavePaidDays: sum((x) => x.leavePaidDays),
      paidDaysCredit: sum((x) => x.paidDaysCredit),
      daysWithPay: sum((x) => x.daysWithPay),
      nightHours: sum((x) => x.nightHours),
      nightPremium: sum((x) => x.nightPremium),
      standardWorkDays: last.standardWorkDays,
      billableWorkDays: sum((x) => x.billableWorkDays),
      scheduleOffCount: last.scheduleOffCount,
      paidLeaveType: last.paidLeaveType,
      paidDayOff: last.paidDayOff,
      workSalary: sum((x) => x.workSalary),
      hourlyRate: last.hourlyRate,
      shiftLevelAllowance: sum((x) => x.shiftLevelAllowance),
      hourlyPaidHours: sum((x) => x.hourlyPaidHours),
      completionSalaryEarned: sum((x) => x.completionSalaryEarned),
      otSalary: sum((x) => x.otSalary),
      travelHours: sum((x) => x.travelHours),
      travelSalary: sum((x) => x.travelSalary),
      allowanceDays: {for (final x in p) ...x.allowanceDays},
      standardDayMinutes: last.standardDayMinutes,
    );
  }
}
