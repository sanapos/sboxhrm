import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';

void main() {
  PosStoreSellSettingsDto withExtra(String? extra) =>
      PosStoreSellSettingsDto.fromJson({'sellProfile': 'restaurant', 'extraJson': extra});

  test('mặc định bật khi chưa cấu hình', () {
    expect(withExtra(null).autoStartTimedOnPick, isTrue);
    expect(withExtra('{"offlineSale":{"enabled":true}}').autoStartTimedOnPick, isTrue);
  });

  test('tắt / bật lại qua merge, giữ các khóa khác', () {
    final off = PosStoreSellSettingsDto.mergeAutoStartTimedOnPick(
        '{"allowEditSaleTime":true}', false);
    expect(withExtra(off).autoStartTimedOnPick, isFalse);
    expect(jsonDecode(off)['allowEditSaleTime'], isTrue);
    final on = PosStoreSellSettingsDto.mergeAutoStartTimedOnPick(off, true);
    expect(withExtra(on).autoStartTimedOnPick, isTrue);
  });
}
