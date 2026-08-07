/// Biểu thuế TNCN lũy tiến (Luật 2025, áp dụng từ 2026) — mặc định 5 bậc.
class PitTaxDefaults {
  static const personalDeduction = 15500000.0;
  static const dependentDeduction = 6200000.0;

  /// Ngưỡng cộng dồn (VNĐ/tháng): đến 10 / 30 / 60 / 100 triệu.
  static const bracket1Max = 10000000.0;
  static const bracket2Max = 30000000.0;
  static const bracket3Max = 60000000.0;
  static const bracket4Max = 100000000.0;

  static const rate1 = 5.0;
  static const rate2 = 10.0;
  static const rate3 = 20.0;
  static const rate4 = 30.0;
  /// Bậc 5: trên 100 triệu.
  static const rate5 = 35.0;
}

double _toDouble(dynamic v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? fallback;
}

/// Tính thuế lũy tiến từ map thiết lập cửa hàng (TaxSetting JSON).
/// Hỗ trợ cả dữ liệu 5 bậc (ngưỡng trùng từ bậc 5) và 7 bậc cũ.
double calculateProgressivePit(
  double taxableIncome,
  Map<String, dynamic>? taxSettings,
) {
  if (taxableIncome <= 0) return 0;

  final caps = <double>[
    _toDouble(taxSettings?['taxBracket1Max'], PitTaxDefaults.bracket1Max),
    _toDouble(taxSettings?['taxBracket2Max'], PitTaxDefaults.bracket2Max),
    _toDouble(taxSettings?['taxBracket3Max'], PitTaxDefaults.bracket3Max),
    _toDouble(taxSettings?['taxBracket4Max'], PitTaxDefaults.bracket4Max),
    _toDouble(taxSettings?['taxBracket5Max'], PitTaxDefaults.bracket4Max),
    _toDouble(taxSettings?['taxBracket6Max'], PitTaxDefaults.bracket4Max),
  ];
  final rates = <double>[
    _toDouble(taxSettings?['taxRate1'], PitTaxDefaults.rate1),
    _toDouble(taxSettings?['taxRate2'], PitTaxDefaults.rate2),
    _toDouble(taxSettings?['taxRate3'], PitTaxDefaults.rate3),
    _toDouble(taxSettings?['taxRate4'], PitTaxDefaults.rate4),
    _toDouble(taxSettings?['taxRate5'], PitTaxDefaults.rate5),
    _toDouble(taxSettings?['taxRate6'], PitTaxDefaults.rate5),
    _toDouble(taxSettings?['taxRate7'], PitTaxDefaults.rate5),
  ];

  var prev = 0.0;
  var remaining = taxableIncome;
  var tax = 0.0;
  var rateIdx = 0;

  for (final cap in caps) {
    if (cap <= prev) continue;
    if (rateIdx >= rates.length) break;
    final width = cap - prev;
    final amount = remaining > width ? width : remaining;
    if (amount > 0) {
      tax += amount * rates[rateIdx] / 100;
      remaining -= amount;
    }
    prev = cap;
    rateIdx++;
    if (remaining <= 0) return tax;
  }

  if (remaining > 0) {
    final topIdx = rateIdx.clamp(0, rates.length - 1);
    tax += remaining * rates[topIdx] / 100;
  }
  return tax;
}
