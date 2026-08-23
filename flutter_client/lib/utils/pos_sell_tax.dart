import 'pos_sell_store_settings.dart';

/// Dòng hàng dùng tính VAT theo từng mặt hàng.
class PosSellTaxLine {
  const PosSellTaxLine({
    required this.lineTotal,
    required this.vatRate,
    this.vatExempt = false,
  });

  final double lineTotal;
  final double vatRate;
  final bool vatExempt;
}

/// Tính thuế VAT theo chế độ thiết lập cửa hàng.
///
/// - [PosSellTaxMode.includedInPrice]: giá bán đã gồm VAT → **VAT trên HĐ = 0đ**
///   (không tách phần thuế ra khỏi giá).
/// - [PosSellTaxMode.perItem]: cộng thêm VAT theo % từng mặt hàng.
/// - [PosSellTaxMode.orderTotal]: cộng thêm VAT % trên tổng đơn.
class PosSellTax {
  static double vatAmount({
    required PosSellTaxMode mode,
    required double netTotal,
    required double orderVatRate,
    required bool orderVatExempt,
    required List<PosSellTaxLine> lines,
  }) {
    if (netTotal <= 0) return 0;

    switch (mode) {
      case PosSellTaxMode.includedInPrice:
        // Giá đã gồm VAT — không tách / không cộng thêm trên hóa đơn.
        return 0;
      case PosSellTaxMode.orderTotal:
        if (orderVatExempt || orderVatRate <= 0) return 0;
        return netTotal * orderVatRate / 100;
      case PosSellTaxMode.perItem:
        if (lines.isEmpty) return 0;
        final gross =
            lines.fold<double>(0, (a, l) => a + l.lineTotal.clamp(0, double.infinity));
        if (gross <= 0) return 0;
        final ratio = (netTotal / gross).clamp(0.0, 1.0);
        return lines.fold<double>(0, (a, l) {
          if (l.vatExempt || l.vatRate <= 0 || l.lineTotal <= 0) return a;
          final taxable = l.lineTotal * ratio;
          return a + taxable * l.vatRate / 100;
        });
    }
  }

  static double grandTotal({
    required PosSellTaxMode mode,
    required double netTotal,
    required double vatAmount,
  }) {
    switch (mode) {
      case PosSellTaxMode.includedInPrice:
        return netTotal;
      case PosSellTaxMode.orderTotal:
      case PosSellTaxMode.perItem:
        return netTotal + vatAmount;
    }
  }
}
