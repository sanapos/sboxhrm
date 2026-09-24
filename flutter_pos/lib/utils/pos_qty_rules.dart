import 'package:intl/intl.dart';

import '../models/pos_product.dart';
import '../services/api_service.dart';

/// Format / validate SL theo cờ [PosProduct.allowDecimalQty].
class PosQtyRules {
  PosQtyRules._();

  static final _decFmt = NumberFormat('#,##0.####', 'vi_VN');
  static final _intFmt = NumberFormat('#,##0', 'vi_VN');

  static bool isWhole(double qty) => qty == qty.roundToDouble();

  /// Hàng bắt buộc seri hoặc chưa bật thập phân → chỉ số nguyên.
  static bool mustBeWhole(PosProduct product) =>
      product.requiresSerial ||
      !(product.allowDecimalQty || product.allowAreaQty);

  static bool allowsDecimal(PosProduct product) =>
      (product.allowDecimalQty || product.allowAreaQty) &&
      !product.requiresSerial;

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
      return '$action: «${product.name}» chưa bật Bán số lẻ. Bật để dùng $qty (vd 1,5 · 1,45).';
    }
    return null;
  }

  /// Danh mục bán cache 20 phút và trước đây không có cờ diện tích.
  /// Đọc lại hàng hóa để ô số lượng đúng với thiết lập trong hàng hóa.
  static Future<PosProduct> withFreshQtyFlags(
    ApiService api,
    PosProduct product,
  ) async {
    final id = product.id.trim();
    if (id.isEmpty) return product;
    try {
      final res = await api.getPosProduct(id);
      final data = res['data'];
      if (res['isSuccess'] != true || data is! Map) return product;
      final map = Map<String, dynamic>.from(data);
      bool flag(String camel, String pascal) =>
          map[camel] == true || map[pascal] == true;
      final unit =
          (map['baseUnitName'] ?? map['BaseUnitName'])?.toString().trim();
      bool axis(String camel, String pascal) {
        if (!map.containsKey(camel) && !map.containsKey(pascal)) return true;
        return map[camel] == true || map[pascal] == true;
      }
      return product.copyWith(
        allowDecimalQty: flag('allowDecimalQty', 'AllowDecimalQty'),
        allowAreaQty: flag('allowAreaQty', 'AllowAreaQty'),
        areaLength: axis('allowAreaLength', 'AllowAreaLength'),
        areaWidth: axis('allowAreaWidth', 'AllowAreaWidth'),
        areaHeight: axis('allowAreaHeight', 'AllowAreaHeight'),
        baseUnitName:
            (unit == null || unit.isEmpty) ? product.baseUnitName : unit,
      );
    } catch (_) {
      return product;
    }
  }

  /// Lưu cờ bán số lẻ. [product] null khi lỗi.
  static Future<({PosProduct? product, String? error})> persistAllowDecimal(
    ApiService api,
    PosProduct product,
    bool allow,
  ) async {
    if (product.requiresSerial) {
      return (product: null, error: 'Hàng bắt buộc seri chỉ bán số nguyên.');
    }
    if (product.allowDecimalQty == allow) {
      return (product: product, error: null);
    }
    final res = await api.setPosProductAllowDecimal(product.id, allow);
    if (res['isSuccess'] == true) {
      return (product: product.copyWith(allowDecimalQty: allow), error: null);
    }
    final msg = res['message']?.toString().trim();
    return (
      product: null,
      error: (msg == null || msg.isEmpty) ? 'Không lưu được bán số lẻ.' : msg,
    );
  }
}
