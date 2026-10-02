import '../../utils/overtime_hourly_base_utils.dart';
import '../../utils/shift_records_calculator.dart';
import '../../utils/standard_work_days_utils.dart';
import '../../utils/travel_salary_utils.dart';

/// Loại lương (khớp SalaryRateType ở server).
enum SalaryKind { hourly, monthly, daily, shift }

extension SalaryKindX on SalaryKind {
  int get code => switch (this) { SalaryKind.hourly => 0, SalaryKind.monthly => 1, SalaryKind.daily => 2, SalaryKind.shift => 3 };
  String get label => switch (this) {
        SalaryKind.monthly => 'Lương tháng',
        SalaryKind.daily => 'Lương ngày',
        SalaryKind.shift => 'Lương ca',
        SalaryKind.hourly => 'Lương giờ',
      };
  String get unit => switch (this) {
        SalaryKind.monthly => '/tháng',
        SalaryKind.daily => '/ngày',
        SalaryKind.shift => '/ca',
        SalaryKind.hourly => '/giờ',
      };
  static SalaryKind parse(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return switch (s) {
      '0' || 'Hourly' => SalaryKind.hourly,
      '2' || 'Daily' => SalaryKind.daily,
      '3' || 'Shift' => SalaryKind.shift,
      _ => SalaryKind.monthly,
    };
  }
}

/// Cách đóng BHXH. Lương tháng có thêm «theo lương cơ bản» / «cơ bản + hoàn thành».
enum InsuranceKind { none, base, basePlusCompletion, regionMin, custom }

extension InsuranceKindX on InsuranceKind {
  int get code => index;
  String get label => switch (this) {
        InsuranceKind.none => 'Không đóng BHXH',
        InsuranceKind.base => 'Theo lương cơ bản',
        InsuranceKind.basePlusCompletion => 'Lương cơ bản + hoàn thành',
        InsuranceKind.regionMin => 'Lương tối thiểu vùng',
        InsuranceKind.custom => 'Mức khác',
      };
  static InsuranceKind parse(dynamic v) {
    final i = v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return i >= 0 && i < InsuranceKind.values.length ? InsuranceKind.values[i] : InsuranceKind.none;
  }
}

/// Ngày nghỉ hưởng lương.
const paidLeaveOptions = <(String, String)>[
  ('sunday', 'Chủ nhật'),
  ('saturday', 'Thứ bảy'),
  ('sat-sun', 'Thứ bảy & Chủ nhật'),
  ('sat-afternoon-sun', 'Chiều thứ bảy & Chủ nhật'),
  ('schedule', 'Theo lịch phân ca'),
  ('off-1', 'Nghỉ 1 ngày/tháng'),
  ('off-2', 'Nghỉ 2 ngày/tháng'),
  ('off-3', 'Nghỉ 3 ngày/tháng'),
  ('off-4', 'Nghỉ 4 ngày/tháng'),
];

/// Cách chấm công.
const attendanceOptions = <(String, String, String)>[
  ('both', 'Chấm vào và ra', 'Tính trễ, sớm, tăng ca theo ca'),
  ('checkin', 'Chỉ chấm vào', 'Đủ ca; trễ theo giờ vào, giờ ra lấy hết ca'),
  ('checkout', 'Chỉ chấm ra', 'Đủ ca; giờ vào lấy đầu ca, tính về sớm'),
  ('any', 'Chấm bất kỳ trong ca', 'Có một lần chấm trong ca là đủ công'),
  (kFreeTwoPunchAttendanceMode, 'Chấm 2 lần trong ngày', 'Không theo ca, không tính trễ/sớm/tăng ca'),
  (kFullDayShiftAttendanceMode, 'Ca nguyên ngày', 'Vào 6h sáng, ra trước 6h sáng hôm sau = 1 công'),
  ('none', 'Không chấm công', 'Đủ công theo lịch'),
];

String paidLeaveLabel(String v) => paidLeaveOptions.firstWhere((o) => o.$1 == v, orElse: () => (v, v)).$2;
String attendanceLabel(String v) => attendanceOptions.firstWhere((o) => o.$1 == v, orElse: () => (v, v, '')).$2;

num? _n(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  return num.tryParse('$v'.trim().replaceAll(',', '.'));
}

String _descField(String? description, String key) {
  if (description == null || description.isEmpty) return '';
  for (final part in description.split('|')) {
    final i = part.indexOf(':');
    if (i > 0 && part.substring(0, i).trim() == key) return part.substring(i + 1).trim();
  }
  return '';
}

/// Bản nháp hồ sơ lương đang sửa — đọc từ benefit của server, ghi lại giữ nguyên các trường không có trên form.
class SalaryDraft {
  SalaryDraft();

  SalaryKind kind = SalaryKind.monthly;
  double base = 0; // lương tháng / giờ
  double completion = 0; // lương hoàn thành (tháng)
  double daily = 0; // lương ngày
  int shiftType = 0; // 0 = cố định mỗi ca, 1 = theo bậc lương ca
  double perShift = 0;

  int holidayOtType = 1; // 0 = cố định ngày, 1 = hệ số theo luật
  double holidayOtDaily = 0;
  int hourlyOtType = 1; // 0 = cố định giờ, 1 = theo luật, 2 = không tính
  double hourlyOtFixed = 0;
  String otBase = OvertimeHourlyBaseModes.base;
  bool lateEarlyOnRestDayOt = true;
  bool restDayOtHoursOnly = false;

  InsuranceKind insurance = InsuranceKind.none;
  double insuranceCustom = 0;

  String paidLeave = 'sunday';
  String attendance = 'both';
  List<String> shifts = [];
  int shiftsPerDay = 1;
  double hoursPerDay = 8;

  bool fixedStdDays = false;
  int stdDays = 26;
  bool deductBelowStd = true;
  bool addAboveStd = true;

  int paidLeaveDays = 12;
  int unpaidLeaveDays = 0;

  TravelSalaryMode travel = TravelSalaryMode.off;
  double travelFixed = 0;

  /// Benefit gốc (để giữ trường không có trên form).
  Map<String, dynamic> original = {};

  bool get isNew => original.isEmpty;

  /// Bảo hiểm khả dụng theo loại lương.
  List<InsuranceKind> get insuranceChoices => kind == SalaryKind.monthly
      ? InsuranceKind.values
      : const [InsuranceKind.none, InsuranceKind.regionMin, InsuranceKind.custom];

  /// Số tiền chính theo loại lương.
  double get mainRate => switch (kind) {
        SalaryKind.monthly || SalaryKind.hourly => base,
        SalaryKind.daily => daily,
        SalaryKind.shift => shiftType == 0 ? perShift : 0,
      };

  factory SalaryDraft.fromBenefit(Map<String, dynamic>? b, {double defaultHours = 8}) {
    final d = SalaryDraft();
    if (b == null || b.isEmpty) {
      d.hoursPerDay = defaultHours;
      return d;
    }
    d.original = Map<String, dynamic>.from(b);
    d.kind = SalaryKindX.parse(b['rateType']);
    final rate = _n(b['rate'])?.toDouble() ?? 0;
    d.base = (d.kind == SalaryKind.monthly || d.kind == SalaryKind.hourly) ? rate : 0;
    d.completion = _n(b['completionSalary'])?.toDouble() ?? 0;
    d.daily = _n(b['dailyFixedRate'])?.toDouble() ?? (d.kind == SalaryKind.daily ? rate : 0);
    if (d.kind == SalaryKind.daily && d.daily == 0) d.daily = rate;
    d.shiftType = _n(b['shiftSalaryType'])?.toInt() ?? 0;
    d.perShift = _n(b['fixedShiftRate'])?.toDouble() ?? 0;
    d.holidayOtType = _n(b['holidayOvertimeType'])?.toInt() ?? 1;
    d.holidayOtDaily = _n(b['holidayOvertimeDailyRate'])?.toDouble() ?? 0;
    d.hourlyOtType = _n(b['hourlyOvertimeType'])?.toInt() ?? 1;
    d.hourlyOtFixed = _n(b['hourlyOvertimeFixedRate'])?.toDouble() ?? 0;
    d.otBase = parseOvertimeHourlyBaseMode(b['overtimeHourlyBaseMode']);
    d.lateEarlyOnRestDayOt = b['applyLateEarlyOnRestDayOt'] != false;
    d.restDayOtHoursOnly = b['restDayOtHoursOnly'] == true;
    d.insurance = InsuranceKindX.parse(b['socialInsuranceType']);
    if (!d.insuranceChoices.contains(d.insurance)) d.insurance = InsuranceKind.none;
    d.insuranceCustom = _n(b['insuranceSalary'])?.toDouble() ?? 0;

    var pl = '${b['paidLeaveType'] ?? ''}';
    if (!paidLeaveOptions.any((o) => o.$1 == pl)) {
      final old = '${b['weeklyOffDays'] ?? ''}';
      pl = old.contains('Saturday') && old.contains('Sunday')
          ? 'sat-sun'
          : old.contains('Saturday')
              ? 'saturday'
              : 'sunday';
    }
    d.paidLeave = pl;
    var att = '${b['attendanceMode'] ?? 'both'}';
    if (att == kOncePerShiftAttendanceMode) att = kCheckInOnlyAttendanceMode;
    d.attendance = attendanceOptions.any((o) => o.$1 == att) ? att : 'both';
    final desc = b['description']?.toString();
    final sh = _descField(desc, 'shifts');
    d.shifts = sh.isEmpty ? [] : sh.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    d.shiftsPerDay = (_n(b['shiftsPerDay'])?.toInt() ?? 1).clamp(1, 4);
    d.hoursPerDay = parseHoursPerWorkDay(benefit: b, fallbackHours: defaultHours);

    d.fixedStdDays = parseEmployeeStandardWorkMode(b) == EmployeeStandardWorkMode.fixedDays;
    d.stdDays = parseFixedStandardWorkDays(b);
    d.deductBelowStd = parseDeductIfBelowFixedStandard(b);
    d.addAboveStd = parseAddIfAboveFixedStandard(b);
    d.paidLeaveDays = _n(b['paidLeaveDays'])?.toInt() ?? (d.kind == SalaryKind.monthly ? 12 : 0);
    d.unpaidLeaveDays = _n(b['unpaidLeaveDays'])?.toInt() ?? 0;

    d.travel = isTravelSalaryEnabledForEmployee(benefit: b) ? parseTravelSalaryModeForEmployee(benefit: b) : TravelSalaryMode.off;
    d.travelFixed = parseTravelFixedHourlyRateForEmployee(benefit: b);
    return d;
  }

  /// Lỗi nhập liệu (null = hợp lệ).
  String? validate() {
    switch (kind) {
      case SalaryKind.monthly:
        if (base <= 0) return 'Nhập lương cơ bản.';
      case SalaryKind.hourly:
        if (base <= 0) return 'Nhập lương theo giờ.';
      case SalaryKind.daily:
        if (daily <= 0) return 'Nhập lương ngày.';
      case SalaryKind.shift:
        if (shiftType == 0 && perShift <= 0) return 'Nhập tiền lương mỗi ca.';
    }
    if (holidayOtType == 0 && kind != SalaryKind.hourly && holidayOtDaily <= 0) return 'Nhập tiền công một ngày tăng ca ngày nghỉ.';
    if (hourlyOtType == 0 && hourlyOtFixed <= 0) return 'Nhập tiền một giờ tăng ca.';
    if (insurance == InsuranceKind.custom && insuranceCustom <= 0) return 'Nhập mức lương đóng BHXH.';
    if (hoursPerDay <= 0 || hoursPerDay > 24) return 'Giờ một công phải từ 0 đến 24.';
    if (fixedStdDays && (stdDays < 1 || stdDays > 31)) return 'Số công cố định từ 1 đến 31.';
    if (travel == TravelSalaryMode.fixed && travelFixed <= 0) return 'Nhập đơn giá giờ đi đường.';
    return null;
  }

  /// Lương đóng BHXH (chưa áp trần).
  double insuranceSalaryRaw(Map<String, dynamic> ins) {
    double region() {
      final r = _n(ins['defaultRegion'])?.toInt() ?? 1;
      const fallback = {1: 4960000.0, 2: 4410000.0, 3: 3860000.0, 4: 3450000.0};
      return _n(ins['minSalaryRegion$r'])?.toDouble() ?? fallback[r] ?? 4960000;
    }

    return switch (insurance) {
      InsuranceKind.none => 0,
      InsuranceKind.base => base,
      InsuranceKind.basePlusCompletion => base + completion,
      InsuranceKind.regionMin => region(),
      InsuranceKind.custom => insuranceCustom,
    };
  }

  /// Lương đóng BHXH sau áp trần (20 × lương cơ sở).
  double insuranceSalary(Map<String, dynamic> ins) {
    final raw = insuranceSalaryRaw(ins);
    final cap = _n(ins['maxInsuranceSalary'])?.toDouble() ?? 46800000;
    return raw > cap ? cap : raw;
  }

  String get weeklyOffDays => switch (paidLeave) {
        'saturday' => 'Saturday',
        'sat-sun' || 'sat-afternoon-sun' => 'Saturday,Sunday',
        'sunday' => 'Sunday',
        _ => '', // nghỉ theo lịch / số ngày mỗi tháng: không cố định thứ
      };

  /// Dữ liệu gửi server — bắt đầu từ benefit gốc để không xóa mất trường không có trên form.
  Map<String, dynamic> toBenefit({
    required String name,
    required double fixedAllowanceTotal,
    required double dailyAllowanceTotal,
    required Map<String, dynamic> insuranceSettings,
    required double storeWeekendRate,
  }) {
    final out = <String, dynamic>{...original}
      ..remove('id')
      ..remove('createdAt')
      ..remove('updatedAt')
      ..remove('createdBy')
      ..remove('updatedBy')
      ..remove('storeId');
    String num0(double v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    final desc = [
      'attendanceType:$attendance',
      if (shifts.isNotEmpty) 'shifts:${shifts.join(', ')}',
      'shiftsPerDay:$shiftsPerDay',
      'hoursPerWorkDay:${num0(hoursPerDay)}',
    ].join('|');
    out.addAll({
      'name': name,
      'description': desc,
      'rateType': kind.code,
      // Lương ca theo bậc: server cần rate > 0 để qua kiểm tra.
      'rate': kind == SalaryKind.shift && shiftType == 1 ? 1 : mainRate,
      'currency': original['currency'] ?? 'VND',
      'mealAllowance': fixedAllowanceTotal,
      'responsibilityAllowance': dailyAllowanceTotal,
      'weeklyOffDays': weeklyOffDays,
      'completionSalary': kind == SalaryKind.monthly ? completion : (original['completionSalary'] ?? 0),
      'holidayOvertimeType': holidayOtType,
      'holidayOvertimeDailyRate': holidayOtDaily,
      'applyLateEarlyOnRestDayOt': lateEarlyOnRestDayOt,
      'restDayOtHoursOnly': restDayOtHoursOnly,
      'overtimeHourlyBaseMode': otBase,
      'hourlyOvertimeType': hourlyOtType,
      'hourlyOvertimeFixedRate': hourlyOtFixed,
      'holidayMultiplier': holidayOtType == 1 ? storeWeekendRate : (_n(original['holidayMultiplier']) ?? 2.0),
      'socialInsuranceType': insurance.code,
      'insuranceSalary': insuranceSalary(insuranceSettings),
      'dailyFixedRate': daily,
      'shiftSalaryType': shiftType,
      'fixedShiftRate': perShift,
      'shiftsPerDay': shiftsPerDay,
      'attendanceMode': attendance,
      'paidLeaveType': paidLeave,
      'standardWorkMode': fixedStdDays ? standardWorkModeFixedCustom : standardWorkModeAuto,
      'fixedStandardWorkDays': stdDays.clamp(1, 31),
      'deductIfBelowFixedStandard': deductBelowStd,
      'addIfAboveFixedStandard': addAboveStd,
      'travelSalaryMode': switch (travel) {
        TravelSalaryMode.off => travelSalaryModeOff,
        TravelSalaryMode.fixed => travelSalaryModeFixed,
        TravelSalaryMode.basePer8h => travelSalaryModeBasePer8h,
        TravelSalaryMode.completionPer8h => travelSalaryModeCompletionPer8h,
        TravelSalaryMode.basePlusCompletionPer8h => travelSalaryModeBasePlusCompletionPer8h,
      },
      'travelFixedHourlyRate': travel == TravelSalaryMode.fixed ? travelFixed : null,
      'isActive': true,
    });
    if (kind == SalaryKind.monthly) {
      out['paidLeaveDays'] = paidLeaveDays;
      out['unpaidLeaveDays'] = unpaidLeaveDays;
    }
    return out;
  }

  /// Ước tính một tháng đủ công (chưa tính tăng ca, phạt, thuế).
  SalaryEstimate estimate({
    required double fixedAllowance,
    required double dailyAllowance,
    required double storeStdDays,
    required Map<String, dynamic> insuranceSettings,
  }) {
    final days = fixedStdDays ? stdDays.toDouble() : storeStdDays;
    final main = switch (kind) {
      SalaryKind.monthly => base + completion,
      SalaryKind.daily => daily * days,
      SalaryKind.hourly => base * hoursPerDay * days,
      SalaryKind.shift => shiftType == 0 ? perShift * shiftsPerDay * days : 0.0,
    };
    final allowances = fixedAllowance + dailyAllowance * days;
    final ins = insuranceSalary(insuranceSettings) * 0.105;
    return SalaryEstimate(days: days, main: main, allowances: allowances, insurance: ins);
  }

  /// Bản sao cho nhân viên khác (bỏ hồ sơ gốc — tạo mới).
  SalaryDraft copy() {
    final c = SalaryDraft.fromBenefit(original.isEmpty ? null : original, defaultHours: hoursPerDay)
      ..kind = kind
      ..base = base
      ..completion = completion
      ..daily = daily
      ..shiftType = shiftType
      ..perShift = perShift
      ..holidayOtType = holidayOtType
      ..holidayOtDaily = holidayOtDaily
      ..hourlyOtType = hourlyOtType
      ..hourlyOtFixed = hourlyOtFixed
      ..otBase = otBase
      ..lateEarlyOnRestDayOt = lateEarlyOnRestDayOt
      ..restDayOtHoursOnly = restDayOtHoursOnly
      ..insurance = insurance
      ..insuranceCustom = insuranceCustom
      ..paidLeave = paidLeave
      ..attendance = attendance
      ..shifts = [...shifts]
      ..shiftsPerDay = shiftsPerDay
      ..hoursPerDay = hoursPerDay
      ..fixedStdDays = fixedStdDays
      ..stdDays = stdDays
      ..deductBelowStd = deductBelowStd
      ..addAboveStd = addAboveStd
      ..paidLeaveDays = paidLeaveDays
      ..unpaidLeaveDays = unpaidLeaveDays
      ..travel = travel
      ..travelFixed = travelFixed;
    return c;
  }
}

class SalaryEstimate {
  const SalaryEstimate({required this.days, required this.main, required this.allowances, required this.insurance});
  final double days;
  final double main;
  final double allowances;
  final double insurance;
  double get gross => main + allowances;
  double get net => gross - insurance;
}

/// Tên hồ sơ lương — kèm mã NV để hai người trùng họ tên không bị báo trùng.
String salaryProfileName(String fullName, String code) {
  final n = fullName.trim();
  final c = code.trim();
  if (c.isEmpty) return 'Lương $n';
  return 'Lương $n ($c)';
}
