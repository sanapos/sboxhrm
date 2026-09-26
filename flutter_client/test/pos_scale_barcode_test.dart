import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_scale_barcode.dart';

/// Thêm số kiểm tra EAN-13 cho 12 chữ số đầu.
String ean(String twelve) {
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(twelve[i]) * (i.isEven ? 1 : 3);
  }
  return '$twelve${(10 - sum % 10) % 10}';
}

void main() {
  const weight = PosScaleBarcodeConfig(enabled: true);
  test('Mã cân trọng lượng: 21 + PLU 00123 + 01250 g → 1,25 kg', () {
    final r = weight.decode(ean('210012301250'))!;
    expect((r.plu, r.value, r.isWeight), ('00123', 1.25, true));
  });
  test('Mã cân giá tiền: 20 + PLU 00456 + 45000đ', () {
    final price = weight.copyWith(mode: 'price');
    final r = price.decode(ean('200045645000'))!;
    expect((r.plu, r.value, r.isWeight), ('00456', 45000.0, false));
  });
  test('Không nhận nhầm mã thường / sai số kiểm tra / đang tắt', () {
    expect(weight.decode('8934563123456'), isNull); // mã sản phẩm thường (đầu 89)
    final ok = ean('210012301250');
    final bad = ok.substring(0, 12) + '${(int.parse(ok[12]) + 1) % 10}';
    expect(weight.decode(bad), isNull);
    expect(const PosScaleBarcodeConfig().decode(ok), isNull); // chưa bật
  });
  test('Lưu / đọc cấu hình trong ExtraJson', () {
    final json = weight.copyWith(prefixes: ['21', '22'], pluDigits: 6).mergeIntoExtraJson('{"sell":{"x":1}}');
    final c = PosScaleBarcodeConfig.parse(json);
    expect((c.enabled, c.pluDigits, c.mode), (true, 6, 'weight'));
    expect(c.prefixes, ['21', '22']);
    expect(json.contains('"sell"'), isTrue);
  });
}
