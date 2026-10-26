import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/models/customer_display_models.dart';

String _extra(Map<String, Object?> cd) {
  final parts = cd.entries.map((e) {
    final v = e.value;
    return '"${e.key}":${v is String ? '"$v"' : v}';
  }).join(',');
  return '{"customerDisplay":{$parts}}';
}

void main() {
  group('màn khách tại máy (T1 7″)', () {
    test('cửa hàng chưa lưu thiết lập: vẫn hiện như trước', () {
      expect(CustomerDisplayConfig.fromExtraJson(null).localDisplayOn, true);
      expect(CustomerDisplayConfig.fromExtraJson('{"other":1}').localDisplayOn, true);
    });

    test('đã tắt «Bật màn hình phụ» → không hiện bill', () {
      final c = CustomerDisplayConfig.fromExtraJson(
          _extra({'enabled': false, 'target': 't1Native'}));
      expect(c.configured, true);
      expect(c.localDisplayOn, false);
    });

    test('chọn Window / trình duyệt → không hiện, kể cả đang bật', () {
      final c = CustomerDisplayConfig.fromExtraJson(
          _extra({'enabled': true, 'target': 'window'}));
      expect(c.localDisplayOn, false);
    });

    test('bật + T1 native → hiện', () {
      final c = CustomerDisplayConfig.fromExtraJson(
          _extra({'enabled': true, 'target': 't1Native'}));
      expect(c.localDisplayOn, true);
    });

    test('lưu rồi đọc lại giữ đúng trạng thái; copyWith không mất cờ đã cấu hình', () {
      final saved = const CustomerDisplayConfig(enabled: false).mergeIntoExtraJson(null);
      final c = CustomerDisplayConfig.fromExtraJson(saved);
      expect(c.localDisplayOn, false);
      expect(c.copyWith(viewerCode: 'ABCDEFGH').localDisplayOn, false);
      expect(c.copyWith(enabled: true).localDisplayOn, true);
    });
  });
}
