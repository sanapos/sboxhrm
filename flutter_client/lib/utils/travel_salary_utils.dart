/// Cách tính lương giờ đi đường (theo hồ sơ nhân viên).
enum TravelSalaryMode {
  /// Tắt tính lương đi đường cho NV.
  off,
  fixed,
  basePer8h,
  completionPer8h,
  /// (Lương cơ bản + lương hoàn thành) ÷ công chuẩn ÷ 8h
  basePlusCompletionPer8h,
}

const String travelSalaryModeOff = 'off';
const String travelSalaryModeFixed = 'fixed';
const String travelSalaryModeBasePer8h = 'base_per_8h';
const String travelSalaryModeCompletionPer8h = 'completion_per_8h';
const String travelSalaryModeBasePlusCompletionPer8h =
    'base_plus_completion_per_8h';

TravelSalaryMode parseTravelSalaryMode({Map<String, dynamic>? salarySettings}) {
  final raw = salarySettings?['travelSalaryMode']?.toString().trim().toLowerCase() ??
      salarySettings?['travel_salary_mode']?.toString().trim().toLowerCase() ??
      travelSalaryModeBasePer8h;
  return _parseTravelSalaryModeRaw(raw);
}

TravelSalaryMode parseTravelSalaryModeForEmployee({
  Map<String, dynamic>? benefit,
  Map<String, dynamic>? storeSalarySettings,
}) {
  final employeeRaw = benefit?['travelSalaryMode']?.toString().trim().toLowerCase() ??
      benefit?['TravelSalaryMode']?.toString().trim().toLowerCase();
  if (employeeRaw != null && employeeRaw.isNotEmpty) {
    return _parseTravelSalaryModeRaw(employeeRaw);
  }
  return TravelSalaryMode.basePer8h;
}

/// NV bật tính lương đi đường (không phải mode `off`).
bool isTravelSalaryEnabledForEmployee({Map<String, dynamic>? benefit}) {
  final raw = benefit?['travelSalaryMode']?.toString().trim().toLowerCase() ??
      benefit?['TravelSalaryMode']?.toString().trim().toLowerCase();
  if (raw == null || raw.isEmpty) return true; // tương thích dữ liệu cũ
  return raw != travelSalaryModeOff &&
      raw != 'disabled' &&
      raw != 'none';
}

double parseTravelFixedHourlyRateForEmployee({
  Map<String, dynamic>? benefit,
  Map<String, dynamic>? storeSalarySettings,
}) {
  final employeeRate =
      benefit?['travelFixedHourlyRate'] ?? benefit?['TravelFixedHourlyRate'];
  if (employeeRate != null) {
    if (employeeRate is num) return employeeRate.toDouble();
    final parsed =
        double.tryParse(employeeRate.toString().replaceAll(',', '.'));
    if (parsed != null && parsed > 0) return parsed;
  }
  return 0;
}

TravelSalaryMode _parseTravelSalaryModeRaw(String raw) {
  switch (raw) {
    case travelSalaryModeOff:
    case 'disabled':
    case 'none':
      return TravelSalaryMode.off;
    case travelSalaryModeFixed:
      return TravelSalaryMode.fixed;
    case travelSalaryModeCompletionPer8h:
      return TravelSalaryMode.completionPer8h;
    case travelSalaryModeBasePlusCompletionPer8h:
    case 'base_plus_completion':
    case 'lcb_plus_lht_per_8h':
      return TravelSalaryMode.basePlusCompletionPer8h;
    case travelSalaryModeBasePer8h:
    default:
      return TravelSalaryMode.basePer8h;
  }
}

double parseTravelFixedHourlyRate({Map<String, dynamic>? salarySettings}) {
  final v = salarySettings?['travelFixedHourlyRate'] ??
      salarySettings?['travel_fixed_hourly_rate'];
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString().replaceAll(',', '.') ?? '') ?? 0;
}

String travelSalaryModeLabel(TravelSalaryMode mode) {
  switch (mode) {
    case TravelSalaryMode.off:
      return 'Tắt';
    case TravelSalaryMode.fixed:
      return 'Giờ cố định';
    case TravelSalaryMode.completionPer8h:
      return 'LHT ÷ công chuẩn ÷ 8h';
    case TravelSalaryMode.basePlusCompletionPer8h:
      return '(LCB + LHT) ÷ công chuẩn ÷ 8h';
    case TravelSalaryMode.basePer8h:
      return 'LCB ÷ công chuẩn ÷ 8h';
  }
}

/// Đơn giá giờ đi đường theo phương án đã chọn.
double computeTravelHourlyRate({
  required TravelSalaryMode mode,
  required double travelFixedHourlyRate,
  required double baseSalary,
  required double completionSalary,
  required double standardWorkDays,
  double standardDayHours = 8,
  double workHourlyFallback = 0,
}) {
  if (mode == TravelSalaryMode.off) return 0;

  final days = standardWorkDays > 0 ? standardWorkDays : 26;
  final hours = standardDayHours > 0 ? standardDayHours : 8;
  final perHourDivisor = days * hours;

  switch (mode) {
    case TravelSalaryMode.off:
      return 0;
    case TravelSalaryMode.fixed:
      if (travelFixedHourlyRate > 0) return travelFixedHourlyRate;
      return workHourlyFallback;
    case TravelSalaryMode.completionPer8h:
      if (completionSalary > 0) return completionSalary / perHourDivisor;
      if (baseSalary > 0) return baseSalary / perHourDivisor;
      return workHourlyFallback;
    case TravelSalaryMode.basePlusCompletionPer8h:
      final combined = baseSalary + completionSalary;
      if (combined > 0) return combined / perHourDivisor;
      return workHourlyFallback;
    case TravelSalaryMode.basePer8h:
      if (baseSalary > 0) return baseSalary / perHourDivisor;
      return workHourlyFallback;
  }
}

double computeTravelSalary({
  required double travelHours,
  required TravelSalaryMode mode,
  required double travelFixedHourlyRate,
  required double baseSalary,
  required double completionSalary,
  required double standardWorkDays,
  double standardDayHours = 8,
  double workHourlyFallback = 0,
}) {
  if (travelHours <= 0 || mode == TravelSalaryMode.off) return 0;
  final rate = computeTravelHourlyRate(
    mode: mode,
    travelFixedHourlyRate: travelFixedHourlyRate,
    baseSalary: baseSalary,
    completionSalary: completionSalary,
    standardWorkDays: standardWorkDays,
    standardDayHours: standardDayHours,
    workHourlyFallback: workHourlyFallback,
  );
  return rate * travelHours;
}
