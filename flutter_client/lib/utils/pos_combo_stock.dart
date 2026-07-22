import '../models/pos_product.dart';
import '../models/pos_sale_order.dart';

/// Số combo có thể bán = min(tồn thành phần / qty thành phần).
double computeComboSellableQty(List<PosComboLine> lines) {
  if (lines.isEmpty) return 0;
  var min = double.infinity;
  for (final cl in lines) {
    if (cl.qty <= 0) return 0;
    final canMake = cl.componentOnHandQty / cl.qty;
    if (canMake < min) min = canMake;
  }
  return min.isFinite ? min.floorToDouble().clamp(0, double.infinity) : 0;
}

/// Tồn hiển thị trên lưới bán cho combo/dịch vụ/hàng hóa.
double resolveProductSellableQty(PosProduct product) {
  if (product.productType == PosProductType.service) {
    return double.infinity;
  }
  if (product.productType == PosProductType.combo) {
    if (product.sellableQty != null) return product.sellableQty!;
    final lines = product.comboLines;
    if (lines != null && lines.isNotEmpty) {
      return computeComboSellableQty(lines);
    }
    return 0;
  }
  return product.onHandQty;
}

/// Tổng SL thành phần đã dùng trong giỏ (goods trực tiếp + combo bung ra).
Map<String, double> buildComponentReservation(Iterable<CartLineForStock> cartLines) {
  final map = <String, double>{};
  for (final line in cartLines) {
    if (line.productType == PosProductType.combo) {
      for (final cl in line.comboLines) {
        map[cl.componentProductId] =
            (map[cl.componentProductId] ?? 0) + cl.qty * line.qty;
      }
    } else if (line.productType == PosProductType.goods) {
      map[line.productId] = (map[line.productId] ?? 0) + line.qty;
    }
  }
  return map;
}

/// Chỉ phần tồn đã giữ bởi combo (không gồm hàng lẻ cùng SP).
Map<String, double> buildComboOnlyReservation(Iterable<CartLineForStock> cartLines) {
  final map = <String, double>{};
  for (final line in cartLines) {
    if (line.productType != PosProductType.combo) continue;
    for (final cl in line.comboLines) {
      map[cl.componentProductId] =
          (map[cl.componentProductId] ?? 0) + cl.qty * line.qty;
    }
  }
  return map;
}

class CartLineForStock {
  const CartLineForStock({
    required this.productId,
    required this.productType,
    required this.qty,
    this.comboLines = const [],
  });

  final String productId;
  final PosProductType productType;
  final double qty;
  final List<PosComboLine> comboLines;
}

/// Kiểm tra đủ tồn khi thêm/tăng SL combo (tính cả thành phần đã dùng trong giỏ).
bool validateComboStock({
  required PosProduct combo,
  required double requiredComboQty,
  required Map<String, double> componentReserved,
}) {
  final lines = combo.comboLines;
  if (lines == null || lines.isEmpty) return false;
  for (final cl in lines) {
    final need = cl.qty * requiredComboQty;
    final reserved = componentReserved[cl.componentProductId] ?? 0;
    if (cl.componentOnHandQty < reserved + need - 0.0001) return false;
  }
  return true;
}

String? comboStockErrorMessage({
  required PosProduct combo,
  required double requiredComboQty,
  required Map<String, double> componentReserved,
}) {
  final lines = combo.comboLines;
  if (lines == null || lines.isEmpty) {
    return 'Combo «${combo.name}» chưa có thành phần';
  }
  for (final cl in lines) {
    final need = cl.qty * requiredComboQty;
    final reserved = componentReserved[cl.componentProductId] ?? 0;
    final avail = cl.componentOnHandQty - reserved;
    if (avail + 0.0001 < need) {
      final name = cl.componentProductName.isNotEmpty
          ? cl.componentProductName
          : 'thành phần';
      return 'Combo «${combo.name}»: «$name» không đủ (cần ${need.toStringAsFixed(need == need.roundToDouble() ? 0 : 2)}, còn ${avail.clamp(0, double.infinity).toStringAsFixed(0)})';
    }
  }
  return null;
}

/// Bung combo thành dòng phiếu xuất kho / trừ tồn cục bộ.
List<PosSaleOrderLine> expandComboToWarehouseLines({
  required PosProduct combo,
  required double comboQty,
  String? lineNote,
}) {
  final lines = combo.comboLines;
  if (lines == null || lines.isEmpty) {
    return [
      PosSaleOrderLine(
        productId: combo.id,
        productName: combo.name,
        unitName: combo.baseUnitName,
        qty: comboQty,
        unitPrice: combo.basePrice,
        lineNote: lineNote,
      ),
    ];
  }
  return lines
      .map(
        (cl) => PosSaleOrderLine(
          productId: cl.componentProductId,
          productName: cl.componentProductName.isNotEmpty
              ? cl.componentProductName
              : cl.componentProductCode,
          unitName: combo.baseUnitName,
          qty: cl.qty * comboQty,
          unitPrice: cl.componentBasePrice,
          lineNote: lineNote != null && lineNote.isNotEmpty
              ? '$lineNote (combo: ${combo.name})'
              : 'Combo: ${combo.name}',
        ),
      )
      .toList();
}

List<PosComboLine> parseComboLinesFromJson(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => PosComboLine.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

PosProduct applyComboSellableToProduct(PosProduct product) {
  if (product.productType != PosProductType.combo) return product;
  final sellable = product.sellableQty ??
      (product.comboLines != null
          ? computeComboSellableQty(product.comboLines!)
          : 0);
  return product.copyWith(onHandQty: sellable);
}
