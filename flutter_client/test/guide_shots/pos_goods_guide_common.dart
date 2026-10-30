import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Dữ liệu mẫu cửa hàng tạp hóa cho ảnh hướng dẫn hàng hóa (pos_products, pos_units, pos_lots).

final goodsCategories = [
  {'id': 'c1', 'name': 'Bia & nước ngọt', 'productCount': 12},
  {'id': 'c2', 'name': 'Sữa các loại', 'productCount': 9},
  {'id': 'c3', 'name': 'Gia dụng', 'productCount': 6},
  {'id': 'c4', 'name': 'Nhôm kính', 'productCount': 3},
];

final goodsSuppliers = [
  {'id': 's1', 'code': 'NCC01', 'name': 'Bia Sài Gòn'},
  {'id': 's2', 'code': 'NCC02', 'name': 'Sữa Minh Châu'},
  {'id': 's3', 'code': 'NCC03', 'name': 'Điện máy H.Long'},
];

final goodsLocations = [
  {'id': 'l1', 'name': 'Kệ A1'},
  {'id': 'l2', 'name': 'Kho sau'},
];

Map<String, Object?> goodsUnit(String id, String name, num rate, num price, {bool base = false, String? barcode}) => {
      'id': id, 'unitName': name, 'conversionRate': rate, 'basePrice': price, 'isBaseUnit': base,
      'isDirectSale': true, if (barcode != null) 'barcode': barcode,
    };

/// Bia lon: ĐVT cơ bản Lon, quy đổi Lốc 6 / Thùng 24 — mỗi đơn vị giá và mã vạch riêng.
final beerProduct = <String, Object?>{
  'id': 'g1', 'productCode': 'TIGER330', 'barcode': '8934822101330', 'name': 'Bia Tiger lon 330ml',
  'categoryId': 'c1', 'categoryName': 'Bia & nước ngọt', 'supplierId': 's1', 'supplierName': 'Bia Sài Gòn',
  'basePrice': 18000, 'costPrice': 14500, 'onHandQty': 480, 'minStockQty': 96, 'maxStockQty': 1200,
  'productType': '0', 'baseUnitName': 'Lon', 'isActive': true, 'isDirectSale': true, 'vatRate': 10,
  'units': [
    goodsUnit('u0', 'Lon', 1, 18000, base: true, barcode: '8934822101330'),
    goodsUnit('u1', 'Lốc', 6, 105000, barcode: '8934822106335'),
    goodsUnit('u2', 'Thùng', 24, 395000, barcode: '8934822124339'),
  ],
};

/// Sữa tươi: theo dõi lô / HSD, cảnh báo trước 15 ngày.
final milkProduct = <String, Object?>{
  'id': 'g2', 'productCode': 'VNMTT1L', 'barcode': '8934673573209', 'name': 'Sữa tươi tiệt trùng không đường 1L',
  'categoryId': 'c2', 'categoryName': 'Sữa các loại', 'supplierId': 's2', 'supplierName': 'Sữa Minh Châu',
  'basePrice': 36000, 'costPrice': 31500, 'onHandQty': 64, 'productType': '0', 'baseUnitName': 'Hộp',
  'isActive': true, 'isDirectSale': true, 'trackExpiry': true, 'expiryWarningDays': 15, 'vatRate': 8,
};

/// Nồi cơm điện: bảo hành 12 tháng, bắt buộc nhập seri khi bán.
final riceCookerProduct = <String, Object?>{
  'id': 'g3', 'productCode': 'NCD18', 'barcode': '8936013320188', 'name': 'Nồi cơm điện 1,8L',
  'categoryId': 'c3', 'categoryName': 'Gia dụng', 'supplierId': 's3', 'supplierName': 'Điện máy H.Long',
  'basePrice': 890000, 'costPrice': 690000, 'onHandQty': 14, 'productType': '0', 'baseUnitName': 'Cái',
  'isActive': true, 'isDirectSale': true, 'warrantyMonths': 12, 'requiresSerial': true, 'vatRate': 10,
};

/// Cửa nhôm kính: hàng gia công tính theo m², vị trí kho + trọng lượng.
final doorProduct = <String, Object?>{
  'id': 'g4', 'productCode': 'CNK-XF', 'name': 'Cửa nhôm Xingfa kính cường lực 8 ly',
  'categoryId': 'c4', 'categoryName': 'Nhôm kính', 'basePrice': 2450000, 'costPrice': 1680000,
  'onHandQty': 0, 'productType': '0', 'baseUnitName': 'Bộ', 'isActive': true, 'isDirectSale': true,
  'isMadeToOrder': true, 'priceByArea': true, 'minPricePerSet': 1500000,
  'storageLocationId': 'l2', 'storageLocationName': 'Kho sau', 'weight': 18, 'weightUnit': 'kg', 'vatRate': 10,
};

final goodsProducts = [beerProduct, milkProduct, riceCookerProduct, doorProduct];

/// API giả: ngành bán lẻ (form hàng hóa hiện mã vạch, ĐVT, lô / HSD…), danh mục, NCC, hàng hóa.
MockClient goodsApi([Object? Function(String path)? extra]) => posGuideApi((req) {
      final p = req.url.path;
      final more = extra?.call(p);
      if (more != null) return more;
      if (p.endsWith('/api/pos/sell-settings')) return {'id': 'ss1', 'sellProfile': 'retail'};
      if (p.endsWith('/api/pos/catalog/categories')) return goodsCategories;
      if (p.endsWith('/api/pos/catalog/suppliers')) return goodsSuppliers;
      if (p.endsWith('/api/pos/catalog/storage-locations')) return goodsLocations;
      for (final g in goodsProducts) {
        if (p.endsWith('/api/pos/products/${g['id']}')) return g;
        if (p.endsWith('/api/pos/products/${g['id']}/units')) return g['units'] ?? const [];
      }
      if (p.endsWith('/api/pos/products')) {
        return {'items': goodsProducts, 'totalCount': goodsProducts.length, 'total': goodsProducts.length, 'page': 1, 'totalPages': 1};
      }
      return null;
    });

Future<void> pumpFrames(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Khung bao trọn một mục của form hàng hóa theo tiêu đề mục.
Finder formSection(String title) => GuideMark.within(find.text(title).first, 'Column');

/// Cuộn khung dọc đầu tiên tới [f], đặt ở [alignment] chiều cao (form có thanh nút dính dưới cùng).
Future<void> scrollFormTo(WidgetTester t, Finder f, {double alignment = 0.12}) async {
  await guideScrollTo(t, f, alignment: alignment);
  await t.pump(const Duration(milliseconds: 200));
}
