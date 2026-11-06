import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/config/sbox_app_variant.dart';
import 'package:zkteco_flutter_client/content/app_legal_pages.dart';

void main() {
  group('iosPosText', () {
    test('bỏ tên nền tảng khác', () {
      expect(SboxAppVariant.iosPosText('Ghép máy in trong Cài đặt Android → Bluetooth, rồi bấm Làm mới'),
          'Ghép máy in trong Cài đặt → Bluetooth, rồi bấm Làm mới');
      expect(SboxAppVariant.iosPosText('Khi mất mạng, máy POS Android vẫn thu tiền mặt'),
          'Khi mất mạng, máy POS vẫn thu tiền mặt');
      expect(SboxAppVariant.iosPosText('Dùng app Windows hoặc tải trên CH Play'),
          'Dùng máy tính hoặc tải trên thiết bị');
    });

    test('bỏ lời mời gia hạn và nâng cấp dịch vụ SBOX', () {
      expect(SboxAppVariant.iosPosText('Cửa hàng A — gói dịch vụ đã hết hạn, liên hệ đại lý để gia hạn'),
          'Cửa hàng A — gói dịch vụ đã hết hạn.');
      expect(SboxAppVariant.iosPosText('Gói dịch vụ của cửa hàng chưa có chức năng này. Liên hệ đại lý để nâng cấp gói.'),
          'Gói dịch vụ của cửa hàng chưa có chức năng này.');
    });

    test('giữ nguyên việc gia hạn của cửa hàng', () {
      for (final text in ['Bán / gia hạn gói', 'Gia hạn hội viên', 'Thanh toán']) {
        expect(SboxAppVariant.iosPosText(text), text);
      }
    });
  });

  test('stripIosPosLegal bỏ khuôn mặt, vị trí, chấm công và đánh lại số mục', () {
    final page = SboxAppVariant.stripIosPosLegal(AppLegalPages.privacy);
    expect(page, isNot(matches(RegExp('khuôn mặt|GPS|chấm công|vị trí', caseSensitive: false))));
    expect(page, contains('## 1. Vai trò của các bên'));
    expect(page, contains('### Bán hàng'));
    expect(page, contains('Micro'));
    final numbers = RegExp(r'^## (\d+)\.', multiLine: true).allMatches(page).map((m) => int.parse(m.group(1)!)).toList();
    expect(numbers, List.generate(numbers.length, (i) => i + 1));
  });
}
