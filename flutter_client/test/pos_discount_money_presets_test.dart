import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_discount_editor_dialog.dart';

void main() {
  test('dòng 100.000 vẫn có mức tròn 10k khi thừa gợi ý', () {
    final v = posDiscountMoneyPresetsForAmount(100000);
    expect(v.length, lessThanOrEqualTo(9));
    expect(v, containsAll([1000, 5000, 10000, 20000, 50000, 100000]));
  });

  test('không gợi ý vượt giá trị dòng', () {
    final v = posDiscountMoneyPresetsForAmount(30000);
    expect(v.every((a) => a > 0 && a <= 30000), isTrue);
    expect(v.last, 30000);
  });
}
