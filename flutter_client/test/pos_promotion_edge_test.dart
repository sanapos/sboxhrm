import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_promotion_engine.dart';

PosPromoLine line(String key, String productId, double qty, double unit, {double manual = 0}) =>
    PosPromoLine(key: key, productId: productId, qty: qty, gross: qty * unit, manualDiscount: manual);

void main() {
  final now = DateTime(2026, 10, 5, 10, 0);

  test('Chương trình cộng dồn + chương trình riêng lẻ tốt nhất cùng áp lên một dòng', () {
    final stack = PosPromotion(id: 's', name: 'Cộng dồn 10%', type: PosPromotionTypes.timeDiscount, stackable: true, config: {'percent': 10});
    final a = PosPromotion(id: 'a', name: 'A 20%', type: PosPromotionTypes.timeDiscount, config: {'percent': 20});
    final b = PosPromotion(id: 'b', name: 'B 15%', type: PosPromotionTypes.timeDiscount, config: {'percent': 15});
    final r = computePosPromotions(promotions: [stack, a, b], lines: [line('x', 'p', 1, 100000)], now: now);
    expect(r.lineDiscount['x'], 30000);
    expect(r.applied.map((e) => e.id).toSet(), {'s', 'a'});
  });

  test('Mua nhiều giảm giá: gộp nhiều mặt hàng (mixed) và tách riêng từng mặt hàng', () {
    final tiers = [
      {'minQty': 5, 'percent': 20}
    ];
    final mixed = PosPromotion(id: 'm', name: 'Gộp', type: PosPromotionTypes.qtyDiscount, config: {'tiers': tiers, 'mixed': true});
    final sep = PosPromotion(id: 's', name: 'Riêng', type: PosPromotionTypes.qtyDiscount, config: {'tiers': tiers});
    final cart = [line('a', 'p1', 3, 10000), line('b', 'p2', 3, 20000)];
    expect(computePosPromotions(promotions: [mixed], lines: cart, now: now).total, 18000); // 20% × 90.000
    expect(computePosPromotions(promotions: [sep], lines: cart, now: now).total, 0); // mỗi hàng chỉ 3 < 5
  });

  test('Giảm hóa đơn theo %: có trần, chọn chương trình tốt nhất, không vượt tổng', () {
    final p = PosPromotion(id: 'p', name: '10% tối đa 30k', type: PosPromotionTypes.billDiscount,
        config: {'minBill': 100000, 'billPercent': 10, 'maxDiscount': 30000});
    final q = PosPromotion(id: 'q', name: '20k', type: PosPromotionTypes.billDiscount, config: {'billAmount': 20000});
    final r = computePosPromotions(promotions: [p, q], lines: [line('a', 'x', 1, 1000000)], now: now);
    expect(r.billDiscount, 30000);
    expect(r.applied.length, 1);
    final tiny = computePosPromotions(promotions: [q], lines: [line('a', 'x', 1, 15000)], now: now);
    expect(tiny.billDiscount, 15000); // không giảm quá tổng hóa đơn
  });

  test('Mua 2 tặng 1 cùng loại: 7 cái tặng 2, tách trên hai dòng', () {
    final p = PosPromotion(id: 'b', name: 'Mua 2 tặng 1', type: PosPromotionTypes.buyXGetY, config: {'buyQty': 2, 'getQty': 1});
    final r = computePosPromotions(promotions: [p], lines: [line('a', 'x', 4, 10000), line('b', 'x', 3, 10000)], now: now);
    expect(r.total, 20000);
  });

  test('Đồng giá combo: không giảm khi tổng nhỏ hơn giá combo; tổng giảm khớp đúng', () {
    final p = PosPromotion(id: 'c', name: '3 món 99k', type: PosPromotionTypes.comboPrice, config: {'comboQty': 3, 'comboPrice': 99000});
    final cheap = computePosPromotions(promotions: [p], lines: [line('a', 'x', 3, 20000)], now: now);
    expect(cheap.total, 0);
    final r = computePosPromotions(promotions: [p], lines: [line('a', 'x', 2, 50000), line('b', 'y', 1, 30000)], now: now);
    expect(r.total, 31000); // 130.000 → 99.000
    expect(r.lineDiscount.values.fold<double>(0, (a, b) => a + b), r.total);
  });

  test('Hạn chương trình tính hết ngày kết thúc; không áp sau ngày kết thúc / trước ngày bắt đầu', () {
    final p = PosPromotion(id: 'a', name: 'A', type: PosPromotionTypes.timeDiscount,
        validFrom: DateTime(2026, 10, 5), validTo: DateTime(2026, 10, 7), config: {'percent': 10});
    expect(p.isLiveAt(DateTime(2026, 10, 4, 23, 59)), isFalse);
    expect(p.isLiveAt(DateTime(2026, 10, 5, 0, 0)), isTrue);
    expect(p.isLiveAt(DateTime(2026, 10, 7, 23, 59)), isTrue);
    expect(p.isLiveAt(DateTime(2026, 10, 8, 0, 0)), isFalse);
  });

  test('Phần trăm quá 100 bị chặn; tổng từng dòng khớp tổng chương trình áp dụng', () {
    final p = PosPromotion(id: 'a', name: '150%', type: PosPromotionTypes.timeDiscount, config: {'percent': 150});
    final r = computePosPromotions(promotions: [p], lines: [line('a', 'x', 3, 33333)], now: now);
    expect(r.lineDiscount['a'], 99999);
    expect(r.applied.single.amount, r.total);
  });

  test('Giảm cố định theo đơn vị không vượt giá bán', () {
    final p = PosPromotion(id: 'a', name: '-50k', type: PosPromotionTypes.timeDiscount, config: {'amountPerUnit': 50000});
    final r = computePosPromotions(promotions: [p], lines: [line('a', 'x', 2, 30000)], now: now);
    expect(r.total, 60000);
  });
}
