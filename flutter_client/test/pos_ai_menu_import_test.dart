import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_ai_menu_import.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_product_unit_view.dart';

void main() {
  group('parseMenuPrice', () {
    test('số có dấu chấm / phẩy nghìn', () {
      expect(parseMenuPrice('35.000'), 35000);
      expect(parseMenuPrice('35,000'), 35000);
      expect(parseMenuPrice('1.200.000 đ'), 1200000);
    });

    test('viết tắt k / tr như trên menu', () {
      expect(parseMenuPrice('35k'), 35000);
      expect(parseMenuPrice('35 K'), 35000);
      expect(parseMenuPrice('35,5k'), 35500);
      expect(parseMenuPrice('1,2tr'), 1200000);
      expect(parseMenuPrice('1.5 triệu'), 1500000);
    });

    test('ô trống / chữ → 0', () {
      expect(parseMenuPrice(''), 0);
      expect(parseMenuPrice('liên hệ'), 0);
    });
  });

  test('parseMenuSizes đọc size có k, tên size có số, size thiếu giá giữ giá 0', () {
    expect(parseMenuSizes('M 30.000; L 38k\nChai 500ml 25k; XL ;'), [
      {'name': 'M', 'price': 30000.0},
      {'name': 'L', 'price': 38000.0},
      {'name': 'Chai 500ml', 'price': 25000.0},
      {'name': 'XL', 'price': 0.0},
    ]);
  });

  test('parseComboItems / comboItemsText', () {
    expect(parseComboItems('Cơm gà x2; Trà đá\nCanh × 1,5 + Bánh'), [
      {'name': 'Cơm gà', 'qty': 2.0},
      {'name': 'Trà đá', 'qty': 1.0},
      {'name': 'Canh', 'qty': 1.5},
      {'name': 'Bánh', 'qty': 1.0},
    ]);
    expect(
      comboItemsText([
        {'name': 'Cơm gà', 'qty': 2},
        {'name': 'Trà đá', 'qty': 1},
      ]),
      'Cơm gà x2; Trà đá',
    );
    expect(parseNameList('Trà sữa, Trà trái cây;  '), ['Trà sữa', 'Trà trái cây']);
  });

  group('menuRowWarnings', () {
    test('món chưa có giá', () {
      expect(menuRowWarnings(type: 'Goods', price: 0, sizes: const []), ['Chưa có giá']);
      expect(menuRowWarnings(type: 'Topping', price: 5000, sizes: const []), isEmpty);
      expect(menuRowWarnings(type: 'Material', price: 0, sizes: const []), isEmpty);
    });

    test('size thiếu giá được báo, không bị bỏ im lặng', () {
      final w = menuRowWarnings(type: 'Goods', price: 0, sizes: [
        {'name': 'M', 'price': 0.0},
        {'name': 'L', 'price': 38000.0},
      ]);
      expect(w, ['Size M chưa có giá — sẽ lấy giá size rẻ nhất']);
      expect(
        menuRowWarnings(type: 'Goods', price: 30000, sizes: [
          {'name': 'M', 'price': 0.0},
        ]),
        ['Chưa có giá'],
      );
    });

    test('combo bỏ qua size', () {
      expect(
        menuRowWarnings(type: 'Combo', price: 50000, sizes: [
          {'name': 'M', 'price': 0.0},
        ]),
        isEmpty,
      );
      expect(menuTypeHasSizes('Combo'), isFalse);
    });
  });

  group('lựa chọn khi bán món có size', () {
    final product = PosProduct.fromJson({
      'id': 'p1',
      'productCode': 'HH00001',
      'name': 'Cà phê sữa',
      'productType': 'Goods',
      'basePrice': 25000,
      'baseUnitName': 'Ly',
    });
    final baseUnit = PosProductUnit.fromJson({
      'id': 'u1',
      'productId': 'p1',
      'unitName': 'Ly',
      'conversionRate': 1,
      'basePrice': 25000,
      'isDirectSale': true,
      'isBaseUnit': true,
    });

    test('size do AI nhập: chỉ M / L, không có «Ly» thừa', () {
      final views = buildPosProductUnitViews(product, [
        PosProductVariant(id: 'v1', skuCode: 'a', name: 'M',
            attributeJson: '{"Size":"M","_unit":"Ly","_conversion":"1"}', basePrice: 25000),
        PosProductVariant(id: 'v2', skuCode: 'b', name: 'L',
            attributeJson: '{"Size":"L","_unit":"Ly","_conversion":"1"}', basePrice: 30000),
      ], extraUnits: [baseUnit]);
      expect(views.map((v) => '${v.label}=${v.basePrice}'), ['M=25000.0', 'L=30000.0']);
    });

    test('size tạo tay («M · Ly») không còn bị gộp thành một «Ly»', () {
      final views = buildPosProductUnitViews(product, [
        PosProductVariant(id: 'v1', skuCode: 'a', name: 'M · Ly',
            attributeJson: '{"Size":"M","_unit":"Ly","_conversion":"1"}', basePrice: 25000),
        PosProductVariant(id: 'v2', skuCode: 'b', name: 'L · Ly',
            attributeJson: '{"Size":"L","_unit":"Ly","_conversion":"1"}', basePrice: 30000),
      ], extraUnits: [baseUnit]);
      expect(views.map((v) => v.label), ['M · Ly', 'L · Ly']);
    });

    test('chỉ có ĐVT quy đổi (không size): vẫn giữ ĐVT gốc', () {
      final views = buildPosProductUnitViews(product, [
        PosProductVariant(id: 'v3', skuCode: 'c', name: 'Thùng',
            attributeJson: '{"_unit":"Thùng","_conversion":"24"}', basePrice: 500000),
      ], extraUnits: [baseUnit]);
      expect(views.map((v) => v.label), ['Ly', 'Thùng']);
    });
  });
}
