import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/pos_promotion_engine.dart';

PosPromoLine line(String key, String productId, double qty, double unit,
        {String? cat, bool barcode = false, double manual = 0}) =>
    PosPromoLine(
        key: key, productId: productId, qty: qty, gross: qty * unit,
        categoryId: cat, hasBarcode: barcode, manualDiscount: manual);

void main() {
  final monday19h = DateTime(2026, 10, 5, 19, 0); // Thứ 2
  final monday10h = DateTime(2026, 10, 5, 10, 0);

  test('Giờ vàng 18h–21h: rau cá giảm 30%, ngoài giờ không giảm', () {
    final p = PosPromotion(
      id: 'p1', name: 'Giờ vàng', type: PosPromotionTypes.timeDiscount,
      timeFromMinutes: 18 * 60, timeToMinutes: 21 * 60,
      config: {'percent': 30, 'target': {'scope': 'categories', 'categoryIds': ['rau']}},
    );
    final cart = [line('a', 'raumuong', 2, 10000, cat: 'rau'), line('b', 'sua', 1, 30000, cat: 'sua')];
    final r = computePosPromotions(promotions: [p], lines: cart, now: monday19h);
    expect(r.lineDiscount['a'], 6000);
    expect(r.lineDiscount['b'], isNull);
    expect(r.applied.single.amount, 6000);
    expect(computePosPromotions(promotions: [p], lines: cart, now: monday10h).total, 0);
  });

  test('Thứ trong tuần và khung giờ qua đêm', () {
    final p = PosPromotion(
      id: 'p', name: 'Đêm', type: PosPromotionTypes.timeDiscount,
      daysOfWeekMask: 1 << 6, // chỉ Chủ nhật
      timeFromMinutes: 22 * 60, timeToMinutes: 2 * 60,
      config: {'percent': 10},
    );
    expect(p.isLiveAt(DateTime(2026, 10, 4, 23, 0)), isTrue); // CN 23h
    expect(p.isLiveAt(DateTime(2026, 10, 4, 21, 0)), isFalse);
    expect(p.isLiveAt(DateTime(2026, 10, 5, 23, 0)), isFalse); // T2
  });

  test('Khung qua đêm: phần sau 0h tính theo ngày bắt đầu khung (CN 22h–2h → 01:00 sáng T2 vẫn áp)', () {
    final p = PosPromotion(
      id: 'p', name: 'Đêm CN', type: PosPromotionTypes.timeDiscount,
      daysOfWeekMask: 1 << 6, // chỉ Chủ nhật
      timeFromMinutes: 22 * 60, timeToMinutes: 2 * 60,
      validTo: DateTime(2026, 10, 4), // chương trình kết thúc ngày CN 04/10
      config: {'percent': 10},
    );
    expect(p.isLiveAt(DateTime(2026, 10, 5, 1, 0)), isTrue); // 01:00 sáng T2 = đêm CN
    expect(p.isLiveAt(DateTime(2026, 10, 5, 2, 30)), isFalse); // hết khung
    expect(p.isLiveAt(DateTime(2026, 10, 4, 1, 0)), isFalse); // 01:00 sáng CN = đêm T7 → không áp
  });

  test('Mua từ 5 giảm 20% theo bậc', () {
    final p = PosPromotion(id: 'q', name: 'Mua nhiều', type: PosPromotionTypes.qtyDiscount, config: {
      'tiers': [{'minQty': 3, 'percent': 10}, {'minQty': 5, 'percent': 20}],
    });
    expect(computePosPromotions(promotions: [p], lines: [line('a', 'x', 5, 10000)], now: monday10h).total, 10000);
    expect(computePosPromotions(promotions: [p], lines: [line('a', 'x', 4, 10000)], now: monday10h).total, 4000);
    expect(computePosPromotions(promotions: [p], lines: [line('a', 'x', 2, 10000)], now: monday10h).total, 0);
  });

  test('Mua 2 tặng 1 cùng loại và mua 2 sữa tặng 1 bánh (gợi ý khi chưa có bánh)', () {
    final same = PosPromotion(id: 's', name: 'Mua 2 tặng 1', type: PosPromotionTypes.buyXGetY,
        config: {'buyQty': 2, 'getQty': 1});
    expect(computePosPromotions(promotions: [same], lines: [line('a', 'x', 6, 5000)], now: monday10h).total, 10000);
    expect(computePosPromotions(promotions: [same], lines: [line('a', 'x', 2, 5000)], now: monday10h).total, 0);

    final gift = PosPromotion(id: 'g', name: 'Sữa tặng bánh', type: PosPromotionTypes.buyXGetY, config: {
      'buyQty': 2, 'getQty': 1, 'giftProductId': 'banh', 'giftProductName': 'Bánh',
      'target': {'scope': 'products', 'products': [{'id': 'sua', 'name': 'Sữa'}]},
    });
    final noGift = computePosPromotions(promotions: [gift], lines: [line('a', 'sua', 4, 8000)], now: monday10h);
    expect(noGift.total, 0);
    expect(noGift.suggestions.single.qty, 2);
    final withGift = computePosPromotions(
        promotions: [gift], lines: [line('a', 'sua', 4, 8000), line('b', 'banh', 1, 6000)], now: monday10h);
    expect(withGift.lineDiscount['b'], 6000);
    expect(withGift.suggestions.single.qty, 1);
  });

  test('Đồng giá 3 món 99.000đ', () {
    final p = PosPromotion(id: 'c', name: 'Đồng giá', type: PosPromotionTypes.comboPrice,
        config: {'comboQty': 3, 'comboPrice': 99000});
    final r = computePosPromotions(
        promotions: [p], lines: [line('a', 'x', 2, 40000), line('b', 'y', 2, 30000)], now: monday10h);
    // nhóm đắt nhất: 40 + 40 + 30 = 110k → giảm 11k; 1 món còn lẻ không giảm
    expect(r.total, 11000);
  });

  test('Giảm hóa đơn tính sau giảm dòng; chọn chương trình tốt nhất khi không cộng dồn', () {
    final line10 = PosPromotion(id: 'l', name: '-10%', type: PosPromotionTypes.timeDiscount, config: {'percent': 10});
    final line20 = PosPromotion(id: 'm', name: '-20%', type: PosPromotionTypes.timeDiscount, config: {'percent': 20});
    final bill = PosPromotion(id: 'b', name: 'HĐ 500k', type: PosPromotionTypes.billDiscount,
        config: {'minBill': 500000, 'billAmount': 50000});
    final r = computePosPromotions(
        promotions: [line10, line20, bill], lines: [line('a', 'x', 1, 700000)], now: monday10h);
    expect(r.lineDiscount['a'], 140000); // chỉ lấy −20%
    expect(r.billDiscount, 50000); // 560k ≥ 500k
    expect(r.applied.map((a) => a.id).toSet(), {'m', 'b'});
    final small = computePosPromotions(promotions: [bill], lines: [line('a', 'x', 1, 400000)], now: monday10h);
    expect(small.billDiscount, 0);
  });

  test('Cộng dồn không vượt thành tiền còn lại (sau giảm tay)', () {
    final a = PosPromotion(id: 'a', name: 'A', type: PosPromotionTypes.timeDiscount, stackable: true, config: {'percent': 60});
    final b = PosPromotion(id: 'b', name: 'B', type: PosPromotionTypes.timeDiscount, stackable: true, config: {'percent': 60});
    final r = computePosPromotions(
        promotions: [a, b], lines: [line('x', 'p', 1, 10000, manual: 2000)], now: monday10h);
    expect(r.lineDiscount['x'], 8000);
  });

  test('Mua kèm giá ưu đãi + gợi ý khi chưa có hàng mua kèm', () {
    final p = PosPromotion(id: 'k', name: 'Mua kèm', type: PosPromotionTypes.addonPrice, config: {
      'addonProductId': 'nuocmam', 'addonProductName': 'Nước mắm', 'addonPrice': 10000, 'maxPerTrigger': 1,
      'target': {'scope': 'products', 'products': ['dau']},
    });
    final r = computePosPromotions(
        promotions: [p], lines: [line('a', 'dau', 1, 50000), line('b', 'nuocmam', 2, 25000)], now: monday10h);
    expect(r.lineDiscount['b'], 15000); // 1 chai được giá 10k
    final s = computePosPromotions(promotions: [p], lines: [line('a', 'dau', 1, 50000)], now: monday10h);
    expect(s.suggestions.single.productId, 'nuocmam');
  });

  test('Hàng cận hạn theo danh sách server tính sẵn; chỉ khách thành viên', () {
    final p = PosPromotion(id: 'e', name: 'Cận hạn', type: PosPromotionTypes.nearExpiry,
        resolvedProductIds: {'sua'}, config: {'percent': 50});
    final r = computePosPromotions(
        promotions: [p], lines: [line('a', 'sua', 1, 20000), line('b', 'banh', 1, 20000)], now: monday10h);
    expect(r.lineDiscount, {'a': 10000});

    final m = PosPromotion(id: 'mb', name: 'Thành viên', type: PosPromotionTypes.timeDiscount,
        membersOnly: true, config: {'percent': 5});
    expect(computePosPromotions(promotions: [m], lines: [line('a', 'x', 1, 20000)], now: monday10h).total, 0);
    expect(computePosPromotions(promotions: [m], lines: [line('a', 'x', 1, 20000)], now: monday10h, hasCustomer: true).total, 1000);
  });

  test('JSON lưu vào đơn', () {
    final p = PosPromotion(id: 'p1', name: 'X', type: PosPromotionTypes.timeDiscount, config: {'percent': 10});
    final r = computePosPromotions(promotions: [p], lines: [line('a', 'x', 1, 10000)], now: monday10h);
    final json = r.toOrderJson({'a': 'x||'});
    expect(json, contains('"applied"'));
    expect(json, contains('"x||":1000'));
    final back = PosPromotion.fromJson({'id': 'z', 'name': 'n', 'type': 'qty_discount', 'configJson': '{"tiers":[]}'});
    expect(back.config['tiers'], isEmpty);
  });
}
