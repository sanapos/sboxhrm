import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_barcode_print.dart';
import 'package:zkteco_flutter_client/utils/pos_scale_barcode.dart';

/// Tem cân tạo tại quầy (encode) + loại mã vạch khi in tem.
void main() {
  const cfg = PosScaleBarcodeConfig(enabled: true);

  test('Tem cân in ra quét lại đúng PLU và khối lượng', () {
    final code = cfg.encode('123', 0.45)!;
    expect(code.length, 13);
    expect(code.startsWith('2000123'), isTrue);
    final back = cfg.decode(code)!;
    expect(back.plu, '00123');
    expect(back.value, closeTo(0.45, 1e-9));
    expect(back.isWeight, isTrue);
  });

  test('Vượt sức chứa / PLU dài → không tạo mã', () {
    expect(cfg.encode('123', 100), isNull); // tối đa 99,999 kg
    expect(cfg.encode('1234567', 1), isNull);
    expect(cfg.encode('', 1), isNull);
  });

  test('Mã thành tiền', () {
    final price = cfg.copyWith(mode: 'price');
    final code = price.encode('7', 67500)!;
    expect(price.decode(code)!.value, 67500);
    expect(price.encode('7', 150000), isNull);
  });

  test('Chọn đúng loại mã vạch khi in tem', () {
    expect(posBarcodeSymbology('8934588063060').name, contains('EAN 13'));
    expect(posBarcodeSymbology('8934588063061').name, contains('128')); // sai số kiểm tra
    expect(posBarcodeSymbology('SP000123').name, contains('128'));
  });
}
