/// Chính sách tính lương của cửa hàng (Thiết lập lương → Chính sách tính lương).
///
/// Hai chế độ:
/// - **Theo luật** ([PayrollPolicy.law]): mức tối thiểu theo Bộ luật Lao động 2019 / Luật BHXH —
///   cửa hàng không chỉnh được (hệ số tăng ca chỉ được cao hơn mức luật).
/// - **Tùy chỉnh**: cửa hàng tự quyết từng mục. Mặc định = cách tính trước đây (không đổi số khi chưa chọn).
///
/// Lưu trong thiết lập lương cửa hàng (`/api/settings/salary`, AppSettings `payroll_policy_*`).
library;

/// Loại lương được áp một quy tắc (ngày lễ / nghỉ có lương / phụ cấp đêm).
enum PayScope {
  none('none', 'Không áp dụng'),
  shiftOnly('shift', 'Chỉ lương ca'),
  monthly('monthly', 'Chỉ lương tháng'),
  monthlyDaily('monthly_daily', 'Lương tháng + lương ngày'),
  all('all', 'Mọi loại lương (cả giờ, ca)');

  const PayScope(this.code, this.label);
  final String code;
  final String label;

  static PayScope parse(Object? v, PayScope fallback) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    for (final x in values) {
      if (x.code == s) return x;
    }
    return fallback;
  }

  /// rateType: 0 = giờ, 1 = tháng, 2 = ngày, 3 = ca.
  bool covers(int rateType) => switch (this) {
        PayScope.none => false,
        PayScope.shiftOnly => rateType == 3,
        PayScope.monthly => rateType == 1,
        PayScope.monthlyDaily => rateType == 1 || rateType == 2,
        PayScope.all => true,
      };
}

/// Cách tính phụ cấp làm đêm.
enum NightBasis {
  /// Chỉ giờ thực làm trong 22:00–06:00 (Điều 98 BLLĐ).
  nightHours('night_hours', 'Giờ làm thực tế trong 22:00–06:00 (theo luật)'),

  /// Cả ca, với ca loại «Qua đêm» / mức lương ca đánh dấu «Ca đêm» (cách tính trước đây).
  wholeShift('whole_shift', 'Cả ca — ca loại «Qua đêm» hoặc mức lương «Ca đêm»');

  const NightBasis(this.code, this.label);
  final String code;
  final String label;

  static NightBasis parse(Object? v, NightBasis fallback) {
    final s = '${v ?? ''}'.trim().toLowerCase();
    for (final x in values) {
      if (x.code == s) return x;
    }
    return fallback;
  }
}

class PayrollPolicy {
  const PayrollPolicy({
    required this.isLaw,
    required this.holidayPayScope,
    required this.paidLeavePayScope,
    required this.nightPremiumEnabled,
    required this.nightPremiumPercent,
    required this.nightBasis,
    required this.nightScope,
    required this.bhxh14DayRule,
    this.minOtWeekday = 0,
    this.minOtRestDay = 0,
    this.minOtHoliday = 0,
  });

  /// Áp mức theo luật (khóa các mục bên dưới).
  final bool isLaw;

  /// Ngày lễ rơi vào ngày làm việc: trả lương cho loại lương nào (Điều 112).
  final PayScope holidayPayScope;

  /// Ngày nghỉ có lương đã duyệt (phép năm, việc riêng có lương, nghỉ bù…): trả cho loại lương nào (Điều 113, 115).
  final PayScope paidLeavePayScope;

  final bool nightPremiumEnabled;

  /// % đơn giá giờ cộng thêm cho giờ làm đêm (luật: tối thiểu 30%).
  final double nightPremiumPercent;
  final NightBasis nightBasis;

  /// Loại lương được phụ cấp đêm.
  final PayScope nightScope;

  /// Tháng (đã kết thúc) không làm & không hưởng lương từ 14 ngày làm việc → không đóng BHXH / BHYT / BHTN.
  final bool bhxh14DayRule;

  /// Hệ số tăng ca tối thiểu (chế độ theo luật). 0 = không ép.
  final double minOtWeekday;
  final double minOtRestDay;
  final double minOtHoliday;

  /// Mức theo luật.
  static const law = PayrollPolicy(
    isLaw: true,
    holidayPayScope: PayScope.all,
    paidLeavePayScope: PayScope.all,
    nightPremiumEnabled: true,
    nightPremiumPercent: 30,
    nightBasis: NightBasis.nightHours,
    nightScope: PayScope.all,
    bhxh14DayRule: true,
    minOtWeekday: 1.5,
    minOtRestDay: 2.0,
    minOtHoliday: 3.0,
  );

  /// Mặc định khi cửa hàng chưa chọn = cách tính trước đây (không đổi số lương).
  static const legacyDefault = PayrollPolicy(
    isLaw: false,
    holidayPayScope: PayScope.monthlyDaily,
    paidLeavePayScope: PayScope.monthlyDaily,
    nightPremiumEnabled: true,
    nightPremiumPercent: 30,
    nightBasis: NightBasis.wholeShift,
    // Trước đây phụ cấp đêm chỉ có trong đơn giá lương ca.
    nightScope: PayScope.shiftOnly,
    bhxh14DayRule: true,
  );

  /// Phụ cấp đêm áp cho loại lương [rateType]?
  bool nightAppliesTo(int rateType) => nightPremiumEnabled && nightScope.covers(rateType);

  /// Hệ số cả ca trong đơn giá lương ca (cách «cả ca»); 1.0 khi tính theo giờ đêm / tắt / lương ca không thuộc phạm vi.
  double get wholeShiftCoefficient =>
      nightAppliesTo(3) && nightBasis == NightBasis.wholeShift ? 1 + nightPremiumPercent / 100 : 1.0;

  static double _num(Object? v, double fb) {
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}'.replaceAll(',', '.')) ?? fb;
  }

  static bool _bool(Object? v, bool fb) {
    if (v is bool) return v;
    final s = '${v ?? ''}'.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return fb;
  }

  /// Đọc từ thiết lập lương cửa hàng (GET /api/settings/salary).
  static PayrollPolicy fromSalarySettings(Map<String, dynamic>? s) {
    final preset = '${s?['payrollPolicyPreset'] ?? ''}'.trim().toLowerCase();
    if (preset == 'law') return law;
    const d = legacyDefault;
    return PayrollPolicy(
      isLaw: false,
      holidayPayScope: PayScope.parse(s?['holidayPayScope'], d.holidayPayScope),
      paidLeavePayScope: PayScope.parse(s?['paidLeavePayScope'], d.paidLeavePayScope),
      nightPremiumEnabled: _bool(s?['nightPremiumEnabled'], d.nightPremiumEnabled),
      nightPremiumPercent: _num(s?['nightPremiumPercent'], d.nightPremiumPercent).clamp(0, 300).toDouble(),
      nightBasis: NightBasis.parse(s?['nightPremiumBasis'], d.nightBasis),
      nightScope: PayScope.parse(s?['nightPremiumScope'], d.nightScope),
      bhxh14DayRule: _bool(s?['bhxh14DayRule'], d.bhxh14DayRule),
    );
  }

  /// Ghi vào thiết lập lương cửa hàng (PUT /api/settings/salary).
  Map<String, dynamic> toSalarySettings() => {
        'payrollPolicyPreset': isLaw ? 'law' : 'custom',
        'holidayPayScope': holidayPayScope.code,
        'paidLeavePayScope': paidLeavePayScope.code,
        'nightPremiumEnabled': nightPremiumEnabled,
        'nightPremiumPercent': nightPremiumPercent,
        'nightPremiumBasis': nightBasis.code,
        'nightPremiumScope': nightScope.code,
        'bhxh14DayRule': bhxh14DayRule,
      };

  /// Hệ số tăng ca thực dùng: theo luật thì không thấp hơn mức tối thiểu.
  double otWeekday(double configured) => configured < minOtWeekday ? minOtWeekday : configured;
  double otRestDay(double configured) => configured < minOtRestDay ? minOtRestDay : configured;
  double otHoliday(double configured) => configured < minOtHoliday ? minOtHoliday : configured;
}
