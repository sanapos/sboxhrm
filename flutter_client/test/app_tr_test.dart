import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/l10n/app_locale.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

void main() {
  setUp(() {
    AppLocale.setLanguageCode('en');
    trResetCache();
  });

  test('Vietnamese is untouched while Vietnamese is the active language', () {
    AppLocale.setLanguageCode('vi');
    trResetCache();
    expect(tr('Nhân viên'), 'Nhân viên');
  });

  test('exact UI strings come from the map', () {
    expect(tr('Nhân viên'), isNot(contains('â')));
    expect(tr('Đăng nhập'), isNot(contains('Đ')));
  });

  test('trailing punctuation is preserved', () {
    final withColon = tr('Nhân viên:');
    expect(withColon.endsWith(':'), isTrue);
    expect(withColon, isNot(contains('â')));
  });

  test('interpolated counters translate the surrounding fragment', () {
    for (final s in const ['12 nhân viên', '5 ngày', '3 sản phẩm']) {
      final out = tr(s);
      expect(out, isNot(s), reason: '"$s" was left untranslated');
      expect(out, isNot(matches(RegExp(r'[ăâđêôơư]'))),
          reason: '"$s" -> "$out" still contains Vietnamese');
    }
  });

  test('a value pasted straight onto a word still translates', () {
    // 'Xóa chấm công$punch lúc $t' renders with the value glued to the word, so a
    // digit has to count as a word boundary or the fragment never matches.
    final out = tr('Bổ sung chấm công08:00 ngày 12/07');
    expect(out, isNot(contains('chấm công')));
    expect(out, isNot(contains('ngày')));
  });

  test('a fragment is never substituted inside a longer word', () {
    expect(tr('Nhân viênx'), 'Nhân viênx');
  });

  test('the đồng currency symbol survives translation', () {
    expect(tr('Tổng tiền: 1.000.000đ'), contains('đ'));
  });

  test('a sentence that cannot be fully translated stays Vietnamese', () {
    const s = 'Zzz qqq wwwv không xác định được nội dung nhé bạn ơi';
    // Either fully English or left as-is — never a half-translated hybrid from
    // the fragment pass.
    final out = tr(s);
    expect(out == s || !out.contains('nhé'), isTrue);
  });

  test('product-like data is not mangled by fragment substitution', () {
    // No UI phrase matches the whole string, so it must be returned unchanged.
    expect(tr('Nguyễn Văn Bảo Khánh'), 'Nguyễn Văn Bảo Khánh');
  });

  test('translations are memoised', () {
    final first = tr('12 nhân viên');
    final second = tr('12 nhân viên');
    expect(first, same(second));
  });

  test('trN keeps null', () {
    expect(trN(null), isNull);
    expect(trN('Nhân viên'), isNotNull);
  });
}
