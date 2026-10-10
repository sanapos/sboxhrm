/// Cách lấy đơn giá giờ trước khi nhân hệ số tăng ca (theo luật).
class OvertimeHourlyBaseModes {
  static const base = 'base';
  static const completion = 'completion';
  static const basePlusCompletion = 'base_plus_completion';

  static const defaults = base;
}

String parseOvertimeHourlyBaseMode(dynamic raw) {
  final s = raw?.toString().trim().toLowerCase() ?? '';
  switch (s) {
    case OvertimeHourlyBaseModes.completion:
    case 'ht':
    case '1':
      return OvertimeHourlyBaseModes.completion;
    case OvertimeHourlyBaseModes.basePlusCompletion:
    case 'base+completion':
    case 'base_completion':
    case '2':
      return OvertimeHourlyBaseModes.basePlusCompletion;
    case OvertimeHourlyBaseModes.base:
    case 'lcb':
    case '0':
    case '':
      return OvertimeHourlyBaseModes.base;
    default:
      return OvertimeHourlyBaseModes.base;
  }
}

String overtimeHourlyBaseModeLabel(String mode) {
  switch (parseOvertimeHourlyBaseMode(mode)) {
    case OvertimeHourlyBaseModes.completion:
      return 'Lương hoàn thành';
    case OvertimeHourlyBaseModes.basePlusCompletion:
      return 'Lương cơ bản + hoàn thành';
    default:
      return 'Lương cơ bản';
  }
}

/// Đơn giá giờ dùng nhân hệ số OT (LCB / HT / LCB+HT).
double computeOvertimeHourlyRate({
  required String mode,
  required double baseSalary,
  required double completionSalary,
  required double standardWorkDays,
  required double standardDayHours,
  /// Fallback khi không chia được (vd. lương giờ: rate đã là VNĐ/giờ).
  double fallbackHourlyRate = 0,
}) {
  if (standardWorkDays <= 0 || standardDayHours <= 0) {
    return fallbackHourlyRate;
  }
  final baseHourly = baseSalary / standardWorkDays / standardDayHours;
  final completionHourly =
      completionSalary / standardWorkDays / standardDayHours;
  switch (parseOvertimeHourlyBaseMode(mode)) {
    case OvertimeHourlyBaseModes.completion:
      return completionHourly;
    case OvertimeHourlyBaseModes.basePlusCompletion:
      return baseHourly + completionHourly;
    default:
      return baseHourly;
  }
}
