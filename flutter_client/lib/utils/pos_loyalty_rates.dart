import '../models/pos_sell_industry.dart';

/// Tỷ lệ tích / đổi điểm theo cửa hàng (khớp server PosLoyaltyRates).
class PosLoyaltyRates {
  const PosLoyaltyRates({
    this.enabled = true,
    this.earnPerAmount = 10000,
    this.redeemValue = 100,
    this.maxRedeemPercent = 100,
  });

  static const defaults = PosLoyaltyRates();

  final bool enabled;
  final double earnPerAmount;
  final double redeemValue;
  final double maxRedeemPercent;

  bool get canEarn => enabled && earnPerAmount > 0;
  bool get canRedeem => enabled && redeemValue > 0;

  factory PosLoyaltyRates.fromSettings(PosStoreSellSettingsDto? s) {
    if (s == null) return defaults;
    var pct = s.loyaltyMaxRedeemPercent;
    if (pct <= 0) pct = 100;
    if (pct > 100) pct = 100;
    return PosLoyaltyRates(
      enabled: s.loyaltyEnabled,
      earnPerAmount: s.loyaltyEarnPerAmount < 0 ? 0 : s.loyaltyEarnPerAmount,
      redeemValue: s.loyaltyRedeemValue < 0 ? 0 : s.loyaltyRedeemValue,
      maxRedeemPercent: pct,
    );
  }

  /// Như server CalcPointsEarn: dòng có % tích lũy riêng → (tiền thực trả × %) ÷ giá trị 1 điểm;
  /// dòng còn lại theo mức chung. Tiền dòng chia lại theo tỷ lệ tổng đơn (sau giảm đơn / voucher / đổi điểm).
  double earnPointsForLines(num netTotalAfterRedeem, List<({double lineTotal, double? percent})> lines) {
    final net = netTotalAfterRedeem.toDouble();
    if (!enabled || net <= 0) return 0;
    if (!lines.any((l) => (l.percent ?? 0) > 0)) return earnPoints(net);
    final sum = lines.fold<double>(0, (a, l) => a + (l.lineTotal > 0 ? l.lineTotal : 0));
    if (sum <= 0) return 0;
    final ratio = net / sum < 1 ? net / sum : 1.0;
    var percentMoney = 0.0, rest = 0.0;
    for (final l in lines) {
      final v = (l.lineTotal > 0 ? l.lineTotal : 0) * ratio;
      final p = l.percent ?? 0;
      if (p > 0) {
        percentMoney += v * (p > 100 ? 100 : p) / 100;
      } else {
        rest += v;
      }
    }
    var pts = redeemValue > 0 ? (percentMoney / redeemValue).floorToDouble() : 0.0;
    if (canEarn) pts += (rest / earnPerAmount).floorToDouble();
    return pts;
  }

  double earnPoints(num netTotalAfterRedeem) {
    final net = netTotalAfterRedeem.toDouble();
    if (!canEarn || net <= 0) return 0;
    return (net / earnPerAmount).floorToDouble();
  }

  /// Giảm giá tối đa (đ) từ điểm, đã kẹp % và số dư.
  ({double points, double discount}) capRedeem({
    required double requestedPoints,
    required double balance,
    required num maxFromOrder,
  }) {
    if (!canRedeem || requestedPoints <= 0 || balance <= 0) {
      return (points: 0, discount: 0);
    }
    var points = requestedPoints;
    if (points > balance) points = balance;
    var cap = maxFromOrder.toDouble();
    if (maxRedeemPercent < 100) {
      cap = (maxFromOrder.toDouble() * maxRedeemPercent / 100).roundToDouble();
    }
    if (cap < 0) cap = 0.0;
    var discount = points * redeemValue;
    if (discount > cap) {
      points = (cap / redeemValue).floorToDouble();
      discount = points * redeemValue;
    }
    if (points <= 0) return (points: 0, discount: 0);
    return (points: points, discount: discount);
  }
}
