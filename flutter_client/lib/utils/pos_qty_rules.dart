import 'package:intl/intl.dart';

import '../models/pos_product.dart';

/// Format / validate SL theo cờ [PosProduct.allowDecimalQty].
class PosQtyRules {
  PosQtyRules._();

  static final _decFmt = NumberFormat('#,##0.####', 'vi_VN');
  static final _intFmt = NumberFormat('#,##0', 'vi_VN');

  static bool isWhole(double qty) => qty == qty.roundToDouble();

  /// Hàng bắt buộc seri hoặc chưa bật thập phân → chỉ số nguyên.
  static bool mustBeWhole(PosProduct product) =>
      product.requiresSerial || !product.allowDecimalQty;

  static bool allowsDecimal(PosProduct product) =>
      product.allowDecimalQty && !product.requiresSerial;

  static String format(
    double qty, {
    PosProduct? product,
    bool? allowDecimal,
  }) {
    final dec = allowDecimal ??
        (product == null ? !isWhole(qty) : allowsDecimal(product));
    if (!dec || isWhole(qty)) return _intFmt.format(qty.round());
    return _decFmt.format(qty);
  }

  /// Null = hợp lệ.
  static String? validate(PosProduct product, double qty, {String action = 'Thao tác'}) {
    if (qty <= 0) return '$action: số lượng phải > 0 («${product.name}»).';
    if (mustBeWhole(product) && !isWhole(qty)) {
      if (product.requiresSerial) {
        return '$action: «${product.name}» bắt buộc seri — số lượng phải là số nguyên.';
      }
      return '$action: «${product.name}» chưa cho phép SL thập phân. Bật trong hàng hóa để dùng $qty.';
    }
    return null;
  }
}
