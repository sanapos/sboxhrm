import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_ai_menu_import.dart';

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

  test('parseMenuSizes đọc size có k và tên size có số', () {
    expect(parseMenuSizes('M 30.000; L 38k\nChai 500ml 25k'), [
      {'name': 'M', 'price': 30000.0},
      {'name': 'L', 'price': 38000.0},
      {'name': 'Chai 500ml', 'price': 25000.0},
    ]);
  });
}
