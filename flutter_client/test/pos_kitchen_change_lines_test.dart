import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sale_order.dart';
import 'package:zkteco_flutter_client/utils/pos_topping_format.dart';

const _tc = PosSaleLineTopping(id: 'A1', name: 'Trân châu', price: 5000);
const _thach = PosSaleLineTopping(id: 'b2', name: 'Thạch', price: 3000);

String _sent(List<PosSaleLineTopping> toppings, [String? note]) => posKitchenContentEncode(
      toppings.isEmpty
          ? null
          : '[${toppings.map((t) => '{"id":"${t.id}","name":"${t.name}","price":${t.price},"qty":${t.qty}}').join(',')}]',
      note,
    );

List<String> _change(String? sent, List<PosSaleLineTopping> toppings, [String? note]) =>
    posKitchenChangeLines(sentContent: sent, toppings: toppings, lineNote: note);

void main() {
  test('Thêm topping cho món chưa có topping: chỉ in topping mới', () {
    expect(_change(_sent([]), [_tc]), ['+ Trân châu']);
  });

  test('Thêm topping thứ hai: không in lại topping đã báo', () {
    expect(_change(_sent([_tc]), [_tc, _thach]), ['+ Thạch']);
  });

  test('Tăng SL topping: chỉ in phần tăng', () {
    const three = PosSaleLineTopping(id: 'a1', name: 'Trân châu', price: 5000, qty: 3);
    expect(_change(_sent([_tc]), [three]), ['+ Trân châu x2']);
  });

  test('Bỏ topping', () {
    expect(_change(_sent([_tc, _thach]), [_thach]), ['- Bỏ Trân châu']);
  });

  test('Đổi ghi chú / bỏ ghi chú', () {
    expect(_change(_sent([], 'ít đá'), [], 'không đá'), ['không đá']);
    expect(_change(_sent([], 'ít đá'), []), ['Bỏ ghi chú: ít đá']);
  });

  test('Đổi rồi đổi lại như lúc báo: không còn gì để báo', () {
    expect(_change(_sent([_tc, _thach], 'ít đá'), [_thach, _tc], ' ít đá '), isEmpty);
  });

  test('Chưa có mốc / mốc hỏng: không coi là đổi', () {
    expect(_change(null, [_tc]), isEmpty);
    expect(_change('không phải json', [_tc]), isEmpty);
  });

  test('Dòng phụ in thụt, không gắn dấu ghi chú', () {
    expect(posNoteIsSubLine('+ Trân châu'), isTrue);
    expect(posNoteIsSubLine('- Bỏ Thạch'), isTrue);
  });
}
