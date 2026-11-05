import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_store_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('công tắc «Hiện mã QR nổi ở màn chính»', () {
    test('mặc định bật — cửa hàng cũ giữ đúng hành vi hiện tại', () {
      expect(const PosSellStoreSettings().showPaymentQrOverlay, isTrue);
      final old = jsonEncode({
        'vietQr': {'showAtPayment': true, 'bankAccountId': 'b1'},
      });
      expect(PosSellStoreSettings.parseVietQr(old)!.showOverlay, isNull);
      expect(
        const PosSellStoreSettings().withServerVietQr(old).showPaymentQrOverlay,
        isTrue,
      );
    });

    test('lưu lên server và đọc lại đúng giá trị', () {
      for (final on in [true, false]) {
        final json = PosSellStoreSettings(showPaymentQrOverlay: on).mergeSellTax(null);
        expect(jsonDecode(json)['vietQr']['showOverlay'], on);
        expect(
          const PosSellStoreSettings().withServerVietQr(json).showPaymentQrOverlay,
          on,
        );
      }
    });

    test('lưu không làm mất thiết lập khác trong ExtraJson', () {
      final json = const PosSellStoreSettings(showPaymentQrOverlay: false)
          .mergeSellTax(jsonEncode({'khac': 1}));
      final root = jsonDecode(json) as Map;
      expect(root['khac'], 1);
      expect(root['vietQr']['showAtPayment'], isTrue);
    });

    test('server thắng lưu máy; server chưa có thì dùng lưu máy', () async {
      SharedPreferences.setMockInitialValues({'pos_sell_show_payment_qr_overlay': false});
      final offServer = await PosSellStoreSettings.load(extraJson: jsonEncode({
        'vietQr': {'showOverlay': true},
      }));
      expect(offServer.showPaymentQrOverlay, isTrue);
      final local = await PosSellStoreSettings.load(extraJson: jsonEncode({
        'vietQr': {'showAtPayment': true},
      }));
      expect(local.showPaymentQrOverlay, isFalse);
    });

    test('lưu → báo cho màn bán đang mở và ghi vào máy', () async {
      SharedPreferences.setMockInitialValues({});
      var notified = 0;
      void listener() => notified++;
      PosSellStoreSettings.saved.addListener(listener);
      addTearDown(() => PosSellStoreSettings.saved.removeListener(listener));
      await const PosSellStoreSettings(showPaymentQrOverlay: false).save();
      expect(notified, 1);
      expect(PosSellStoreSettings.saved.value!.showPaymentQrOverlay, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('pos_sell_show_payment_qr_overlay'), isFalse);
    });

    test('copyWith đổi công tắc, không đụng công tắc QR trong màn thanh toán', () {
      final s = const PosSellStoreSettings(showVietQrAtPayment: false)
          .copyWith(showPaymentQrOverlay: false);
      expect(s.showPaymentQrOverlay, isFalse);
      expect(s.showVietQrAtPayment, isFalse);
      expect(s.copyWith(storeName: 'A').showPaymentQrOverlay, isFalse);
    });
  });
}
