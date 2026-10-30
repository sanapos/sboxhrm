import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';

import 'pos_guide_common.dart';

/// Dữ liệu mẫu quán «Trà sữa & Cà phê Mộc» cho ảnh các bước Dịch vụ, Combo, Nguyên vật liệu, Topping.

const catalogCategories = [
  {'id': 'c1', 'name': 'Cà phê', 'productCount': 4},
  {'id': 'c2', 'name': 'Trà sữa', 'productCount': 5},
  {'id': 'c3', 'name': 'Bánh & combo', 'productCount': 3},
  {'id': 'c4', 'name': 'Nguyên vật liệu', 'productCount': 6},
  {'id': 'c5', 'name': 'Topping', 'productCount': 5},
  {'id': 'c6', 'name': 'Dịch vụ', 'productCount': 3},
];

Map<String, Object?> catalogProduct(String id, String code, String name, String cat, String catName, num price,
        {num cost = 0, num onHand = 0, int type = 0, String unit = 'Ly', Map<String, Object?> extra = const {}}) =>
    {
      'id': id, 'productCode': code, 'name': name, 'categoryId': cat, 'categoryName': catName,
      'basePrice': price, 'costPrice': cost, 'onHandQty': onHand, 'productType': '$type',
      'baseUnitName': unit, 'isActive': true, 'isDirectSale': type != 3, ...extra,
    };

final catalogProducts = <String, Map<String, Object?>>{
  for (final p in [
    catalogProduct('p1', 'CFS', 'Cà phê sữa đá', 'c1', 'Cà phê', 29000, cost: 9000, onHand: 150),
    catalogProduct('p2', 'TSTC', 'Trà sữa trân châu đường đen', 'c2', 'Trà sữa', 39000, cost: 11500,
        extra: {
          'description': 'Trà đen pha đậm, sữa tươi, trân châu đường đen nấu mỗi ngày.',
          'allowToppings': true,
          'toppingGroupIds': ['g1', 'g2'],
        }),
    catalogProduct('p3', 'TIRA', 'Bánh tiramisu', 'c3', 'Bánh & combo', 45000, cost: 22000, onHand: 12, unit: 'Cái'),
    catalogProduct('p4', 'CBSANG', 'Combo sáng: Cà phê sữa + bánh', 'c3', 'Bánh & combo', 65000,
        cost: 31000, type: 2, unit: 'Phần', extra: {'showComboComponentsOnSell': true, 'comboTrackStock': false}),
    // Nguyên vật liệu (loại 3): không bán trực tiếp, chỉ trừ theo định lượng.
    catalogProduct('m1', 'NVL-TRADEN', 'Trà đen pha sẵn', 'c4', 'Nguyên vật liệu', 0, cost: 60, onHand: 12000, type: 3, unit: 'ml'),
    catalogProduct('m2', 'NVL-SUATUOI', 'Sữa tươi không đường', 'c4', 'Nguyên vật liệu', 0, cost: 32, onHand: 18000, type: 3, unit: 'ml'),
    catalogProduct('m3', 'NVL-DUONGDEN', 'Siro đường đen', 'c4', 'Nguyên vật liệu', 0, cost: 90, onHand: 2400, type: 3, unit: 'ml'),
    catalogProduct('m4', 'NVL-TRANCHAU', 'Trân châu đen (đã nấu)', 'c4', 'Nguyên vật liệu', 0, cost: 45, onHand: 3500, type: 3, unit: 'g'),
    catalogProduct('m5', 'NVL-LY700', 'Ly nhựa 700ml + nắp', 'c4', 'Nguyên vật liệu', 0, cost: 1300, onHand: 420, type: 3, unit: 'Cái'),
    // Topping (loại 4): quản lý tồn, chọn kèm món khi bán.
    catalogProduct('t1', 'TP-TCTRANG', 'Trân châu trắng', 'c5', 'Topping', 8000, cost: 2500, onHand: 200, type: 4, unit: 'Phần'),
    catalogProduct('t2', 'TP-THACHDUA', 'Thạch dừa', 'c5', 'Topping', 7000, cost: 2000, onHand: 160, type: 4, unit: 'Phần'),
    catalogProduct('t3', 'TP-PUDDING', 'Pudding trứng', 'c5', 'Topping', 10000, cost: 3500, onHand: 90, type: 4, unit: 'Phần'),
    catalogProduct('t4', 'TP-KEMCHEESE', 'Kem cheese', 'c5', 'Topping', 12000, cost: 4500, onHand: 70, type: 4, unit: 'Phần'),
  ])
    p['id'] as String: p,
};

Map<String, Object?> _line(String id, String productId, num qty, {String type = '0'}) {
  final p = catalogProducts[productId]!;
  return {
    'id': id, 'componentProductId': productId, 'componentProductCode': p['productCode'],
    'componentProductName': p['name'], 'qty': qty, 'componentOnHandQty': p['onHandQty'],
    'componentBasePrice': (p['productType'] == '3') ? p['costPrice'] : p['basePrice'],
    'componentUnitName': p['baseUnitName'], 'componentProductType': type, 'trackStock': true,
  };
}

/// Định lượng 1 ly trà sữa trân châu đường đen.
final recipeLines = {
  'p2': [
    _line('r1', 'm1', 120, type: '3'),
    _line('r2', 'm2', 80, type: '3'),
    _line('r3', 'm3', 25, type: '3'),
    _line('r4', 'm4', 50, type: '3'),
    _line('r5', 'm5', 1, type: '3'),
  ],
};

/// Thành phần combo sáng.
final comboLines = {
  'p4': [_line('k1', 'p1', 1), _line('k2', 'p3', 1)],
};

Map<String, Object?> _opt(String id, String productId) {
  final p = catalogProducts[productId]!;
  return {'id': id, 'toppingProductId': productId, 'toppingProductName': p['name'], 'extraPrice': p['basePrice']};
}

final toppingGroups = [
  {
    'id': 'g1', 'name': 'Topping trà sữa', 'sortOrder': 1, 'linkedProductCount': 5,
    'items': [_opt('o1', 't1'), _opt('o2', 't2'), _opt('o3', 't3')],
  },
  {
    'id': 'g2', 'name': 'Kem phủ', 'sortOrder': 2, 'linkedProductCount': 3,
    'items': [_opt('o4', 't4')],
  },
];

/// API giả cho màn Hàng hóa / sửa hàng / nhóm topping / báo cáo NVL.
MockClient catalogApi({Map<String, Object?> sellSettings = const {'sellProfile': 'restaurant'}, Object? materialsReport}) =>
    posGuideApi((req) {
      final p = req.url.path;
      if (p.endsWith('/api/pos/sell-settings')) return {'id': 'ss1', ...sellSettings};
      if (p.endsWith('/api/pos/catalog/categories')) return catalogCategories;
      if (p.endsWith('/api/pos/topping-groups')) return toppingGroups;
      if (p.endsWith('/api/pos/reports/materials/summary')) return materialsReport;
      final m = RegExp(r'/api/pos/products/(\w+)(/[\w-]+)?$').firstMatch(p);
      if (m != null) {
        final id = m.group(1)!;
        return switch (m.group(2)) {
          '/recipe-lines' => recipeLines[id] ?? const [],
          '/combo-lines' => comboLines[id] ?? const [],
          null => catalogProducts[id],
          _ => const [],
        };
      }
      if (p.endsWith('/api/pos/products')) {
        final list = catalogProducts.values.toList();
        return {'items': list, 'totalCount': list.length, 'total': list.length, 'page': 1, 'totalPages': 1};
      }
      return null;
    });

PosProduct catalogPosProduct(String id) => PosProduct.fromJson(Map<String, dynamic>.from(catalogProducts[id]!));

Finder catalogField(String label) => find.widgetWithText(TextField, label);

/// Đưa [f] lên [alignment] khung cuộn; lặp vì mục vừa mở rộng chỉ có chiều cao thật sau vài khung hình.
Future<void> catalogReveal(WidgetTester t, Finder f, {double alignment = 0.12}) async {
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 300));
    await Scrollable.ensureVisible(t.element(f.first), alignment: alignment);
  }
  await t.pump(const Duration(milliseconds: 300));
}
