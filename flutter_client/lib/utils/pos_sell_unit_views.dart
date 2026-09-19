import '../models/pos_product.dart';

import '../services/api_service.dart';

import '../widgets/pos/pos_product_unit_view.dart';



/// ĐVT/biến thể nhúng trong catalog — không gọi API.

List<PosProductUnitView> buildPosSellUnitViewsFromProduct(PosProduct product) {

  final variants =

      product.variants?.where((v) => v.isActive).toList() ?? const [];

  final units =

      product.units?.where((u) => u.isDirectSale).toList() ?? const [];

  return buildPosProductUnitViews(product, variants, extraUnits: units);

}



bool posProductHasEmbeddedSellViews(PosProduct product) {
  final saleUnits = product.units?.where((u) => u.isDirectSale).length ?? 0;
  if (saleUnits > 1) return true;
  final variants = product.variants?.where((v) => v.isActive).length ?? 0;
  return variants > 1;
}



/// Tải đầy đủ ĐVT/biến thể — ưu tiên dữ liệu nhúng, fallback API.

Future<List<PosProductUnitView>> loadPosSellUnitViews(

  ApiService api,

  PosProduct product,

) async {

  if (posProductHasEmbeddedSellViews(product)) {

    return buildPosSellUnitViewsFromProduct(product);

  }



  final fullRes = await api.getPosProduct(product.id);

  var p = product;

  if (fullRes['isSuccess'] == true && fullRes['data'] is Map) {

    p = PosProduct.fromJson(fullRes['data'] as Map<String, dynamic>);

  }



  if (posProductHasEmbeddedSellViews(p)) {

    return buildPosSellUnitViewsFromProduct(p);

  }



  final variants = <PosProductVariant>[];

  final vRes = await api.getPosProductVariants(p.id);

  if (vRes['isSuccess'] == true && vRes['data'] is List) {

    variants.addAll(

      (vRes['data'] as List)

          .map((e) => PosProductVariant.fromJson(e as Map<String, dynamic>))

          .where((v) => v.isActive),

    );

  }



  final units = <PosProductUnit>[];

  final uRes = await api.getPosProductUnits(p.id);

  if (uRes['isSuccess'] == true && uRes['data'] is List) {

    units.addAll(

      (uRes['data'] as List)

          .map((e) => PosProductUnit.fromJson(e as Map<String, dynamic>))

          .where((u) => u.isDirectSale),

    );

  } else if (p.units != null) {

    units.addAll(p.units!.where((u) => u.isDirectSale));

  }



  return buildPosProductUnitViews(p, variants, extraUnits: units);

}



PosProductUnitView? pickUnitView(

  List<PosProductUnitView> views, {

  String? variantId,

  String? unitId,

  String? unitLabel,

}) {

  if (views.isEmpty) return null;

  if (unitId != null) {

    final byUnit = views.where((v) => v.unitId == unitId).firstOrNull;

    if (byUnit != null) return byUnit;

  }

  if (variantId != null) {

    final byVar = views.where((v) => v.variantId == variantId).firstOrNull;

    if (byVar != null) return byVar;

  }

  if (unitLabel != null && unitLabel.isNotEmpty) {

    final byLabel = views.where((v) => v.label == unitLabel).firstOrNull;

    if (byLabel != null) return byLabel;

  }

  return views.first;

}

