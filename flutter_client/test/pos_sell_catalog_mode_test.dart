import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_sell_product_grid.dart';

/// API giả: danh mục bán [total] món, ghi lại mọi lần gọi danh sách món bán.
class _CatalogApi implements ApiService {
  _CatalogApi(this.total);

  final int total;
  final calls = <({int page, int pageSize, String? search})>[];

  @override
  Future<Map<String, dynamic>> getPosSellProducts({
    String? search,
    String? categoryId,
    bool categoryIncludeChildren = true,
    int page = 1,
    int pageSize = 48,
    DateTime? updatedSince,
  }) async {
    calls.add((page: page, pageSize: pageSize, search: search));
    final count = search != null ? 3 : total;
    final start = (page - 1) * pageSize;
    final n = (count - start).clamp(0, pageSize);
    return {
      'isSuccess': true,
      'data': {
        'total': count,
        'sellableTotal': total,
        'serverTime': DateTime.now().toUtc().toIso8601String(),
        'items': [
          for (var i = start; i < start + n; i++)
            {'id': 'p$i', 'productCode': 'SP$i', 'name': 'Hàng $i', 'basePrice': 10000, 'productType': 0, 'isActive': true},
        ],
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getPosProductCategories() async => {'isSuccess': true, 'data': <dynamic>[]};

  @override
  Map<String, String>? get imageAuthHeaders => null;

  @override
  String getFileUrl(String path) => path;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(<String, dynamic>{'isSuccess': false});
}

Future<void> _pumpGrid(WidgetTester tester, _CatalogApi api, {String storeId = 'store-1'}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: PosSellProductGrid(api: api, onPick: (_) {}, storeId: storeId),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Cửa hàng > 5.000 món: không tải toàn bộ danh mục, lưới phân trang trên server', (tester) async {
    final api = _CatalogApi(6000);
    await _pumpGrid(tester, api);

    // Chỉ trang 1 (hiển thị + kiểm tra cỡ danh mục) — không tải trang 2..60 về máy.
    expect(api.calls.where((c) => c.page > 1), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pos_sell_catalog_server_store-1'), isTrue);
    expect(find.text('Hàng 0'), findsOneWidget);

    // Mở lại: vào thẳng chế độ server, không thử đồng bộ toàn bộ nữa.
    api.calls.clear();
    await tester.pumpWidget(const SizedBox());
    await _pumpGrid(tester, api);
    expect(api.calls, isNotEmpty);
    expect(api.calls.every((c) => c.page == 1 && c.pageSize != 100), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Cửa hàng ≤ 5.000 món: vẫn tải đủ danh mục về máy (offline)', (tester) async {
    final api = _CatalogApi(300);
    await _pumpGrid(tester, api, storeId: 'store-2');

    expect(api.calls.where((c) => c.pageSize == 100).map((c) => c.page).toList(), [1, 2, 3]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pos_sell_catalog_server_store-2') ?? false, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Cửa hàng lớn bớt món còn ≤ 5.000: quay lại danh mục offline', (tester) async {
    SharedPreferences.setMockInitialValues({'pos_sell_catalog_server_store-3': true});
    final api = _CatalogApi(300);
    await _pumpGrid(tester, api, storeId: 'store-3');

    expect(api.calls.where((c) => c.pageSize == 100).map((c) => c.page).toList(), [1, 2, 3]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('pos_sell_catalog_server_store-3'), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
