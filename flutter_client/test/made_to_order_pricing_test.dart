import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_area_dims.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_made_to_order_line_dialog.dart';

void main() {
  test('Giá 1 bộ = diện tích (mm) × đơn giá m², không thấp hơn tối thiểu', () {
    final area = MadeToOrderPricing.area(1800, 2200);
    expect(area, 3.96);
    expect(MadeToOrderPricing.setPrice(area, 450000, 1500000), 1782000);

    final small = MadeToOrderPricing.area(400, 500);
    expect(small, 0.2);
    expect(MadeToOrderPricing.setPrice(small, 450000, 500000), 500000);
    expect(MadeToOrderPricing.area(null, 500), 0);
  });

  test('Ghi chú dòng: thay kích thước + giá m² cũ, giữ ghi chú khác', () {
    var note = MadeToOrderPricing.mergeNote(
      'Phòng khách',
      areaNote: buildPosAreaNote(width: 1800, height: 2200, unit: 'mm'),
      priceNote: MadeToOrderPricing.priceNote(3.96, 450000, null),
    );
    expect(note, contains('Phòng khách'));
    expect(parsePosAreaDims(note).width, 1800);
    expect(parsePosAreaDims(note).height, 2200);

    note = MadeToOrderPricing.mergeNote(
      note,
      areaNote: buildPosAreaNote(width: 900, height: 2100, unit: 'mm'),
      priceNote: MadeToOrderPricing.priceNote(1.89, 450000, 1000000),
    );
    expect(parsePosAreaDims(note).width, 900);
    expect('DT '.allMatches(note).length, 1);
    expect(note, contains('Phòng khách'));
    expect(note, contains('tối thiểu'));
  });
}
