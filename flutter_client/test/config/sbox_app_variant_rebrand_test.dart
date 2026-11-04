import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/config/sbox_app_variant.dart';
import 'package:zkteco_flutter_client/content/app_legal_pages.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Chạy: flutter test --dart-define=SBOX_APP=staff test/config/sbox_app_variant_rebrand_test.dart
void main() {
  final skip = SboxAppVariant.companionApp ? false : 'cần --dart-define=SBOX_APP=staff';

  test('tên app và tên miền HRM được đổi', () {
    expect(tr('Cần bật Camera trong Cài đặt > SBOX HRM > Quyền'), 'Cần bật Camera trong Cài đặt > SBOX Nhân Viên > Quyền');
    expect(tr('Đường dẫn: sboxhrm.com → Đăng ký'), 'Đường dẫn: sboxpos.com → Đăng ký');
    expect(tr('Tùy chỉnh module Thiết lập HRM'), 'Tùy chỉnh module Thiết lập SBOX');
    expect(SboxAppVariant.rebrand('Nhập từ thư mục SBOX HRM'), 'Nhập từ thư mục SBOX Nhân Viên');
    expect(SboxAppVariant.rebrand('SBOX HRM · Ảnh hiện trường'), 'SBOX Nhân Viên · Ảnh hiện trường');
  }, skip: skip);

  test('lỗi gói dịch vụ không lộ mã module', () {
    const raw = 'Gói dịch vụ của cửa hàng không bao gồm chức năng "PosSalesReport". Vui lòng nâng cấp gói.';
    expect(SboxAppVariant.isPackageBlocked(raw), isTrue);
    expect(SboxAppVariant.isPackageBlocked('Không kết nối được'), isFalse);
    expect(tr(raw), 'Gói dịch vụ của cửa hàng chưa có chức năng này. Liên hệ đại lý để nâng cấp gói.');
    expect(
      tr('Gói dịch vụ không bao gồm chức năng "CashTransaction". Vui lòng nâng cấp gói.'),
      'Gói dịch vụ của cửa hàng chưa có chức năng này. Liên hệ đại lý để nâng cấp gói.',
    );
  }, skip: skip);

  test('email hỗ trợ giữ nguyên khi đi qua tr()', () {
    expect(AppLegalPages.supportEmail, 'sboxhrm@gmail.com');
    expect(tr('Email: **${AppLegalPages.supportEmail}**'), 'Email: **sboxhrm@gmail.com**');
    expect(tr('Mail: support@sboxhrm.com'), 'Mail: support@sboxhrm.com');
  }, skip: skip);

  test('điều khoản không lặp hai mục cùng tên SBOX POS', () {
    final terms = SboxAppVariant.rebrandLegal(AppLegalPages.terms);
    expect(terms, contains('ứng dụng SBOX POS trên'));
    expect(terms, contains('- **Nhân sự**:'));
    expect(terms, contains('- **Bán hàng**:'));
    expect(terms, isNot(contains('- **SBOX POS**:')));
  }, skip: skip);

  test('trang pháp lý ghi SBOX POS và còn đúng email', () {
    for (final page in [AppLegalPages.privacy, AppLegalPages.terms, AppLegalPages.help]) {
      final shown = SboxAppVariant.rebrandLegal(page).split('\n').map(tr).join('\n');
      expect(shown, isNot(contains('SBOX HRM')));
      expect(shown, isNot(contains('sboxpos@gmail.com')));
      expect(shown, isNot(contains('support@sboxpos.com')));
      expect(shown, contains('sboxhrm@gmail.com'));
    }
  }, skip: skip);
}
