import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/l10n/app_locale.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => trUseLanguage('en'));

  test('Vietnamese is untouched while Vietnamese is the active language',
      () async {
    await trUseLanguage('vi');
    expect(tr('Nhân viên'), 'Nhân viên');
  });

  test('unknown language codes fall back to Vietnamese', () async {
    await trUseLanguage('xx');
    expect(AppLocale.languageCode, 'vi');
    expect(tr('Nhân viên'), 'Nhân viên');
  });

  group('Korean / Japanese / Chinese packs', () {
    final cjk = {
      'ko': RegExp(r'[가-힯]'),
      'ja': RegExp(r'[぀-ヿ一-鿿]'),
      'zh': RegExp(r'[一-鿿]'),
    };
    final vn = RegExp(r'[ăâđêôơưạảấầẩậắằẳặẹẻếềểệịỉọỏốồổộớờởợụủứừửựỳỷỹ]');

    for (final e in cjk.entries) {
      test('${e.key}: common labels are translated', () async {
        await trUseLanguage(e.key);
        for (final s in const ['Lưu', 'Hủy', 'Nhân viên', 'Chấm công', 'Tồn kho']) {
          final out = tr(s);
          expect(out, contains(e.value), reason: '"$s" -> "$out"');
          expect(out, isNot(contains(vn)), reason: '"$s" -> "$out"');
        }
      });
    }

    test('interpolated sentences use the whole-sentence template', () async {
      await trUseLanguage('ko');
      // tr('Không tải được danh sách: \$e') — the value is kept verbatim.
      final out = tr('Không tải được danh sách: timeout 504');
      expect(out, contains('timeout 504'));
      expect(out, isNot(contains(vn)));
    });

    test('money templates match «1.000đ» and «1.000 đ» alike', () async {
      await trUseLanguage('ko');
      // Mẫu «Khách còn nợ {0}đ»; chữ hiển thị nay có dấu cách trước đ.
      for (final s in const ['Khách còn nợ 30.000đ', 'Khách còn nợ 30.000 đ']) {
        final out = tr(s);
        expect(out, contains('30.000 đ'), reason: '"$s" -> "$out"');
        expect(out, isNot(contains('Khách')), reason: '"$s" -> "$out"');
      }
    });

    test('ALL-CAPS labels reuse the sentence-case translation', () async {
      await trUseLanguage('ko');
      expect(tr('MÃ CỬA HÀNG'), tr('Mã cửa hàng'));
      await trUseLanguage('en');
      expect(tr('MÃ CỬA HÀNG'), tr('Mã cửa hàng').toUpperCase());
    });

    test('strings missing from a pack fall back to English, not Vietnamese',
        () async {
      await trUseLanguage('ja');
      // Present in the English base map only if the ja pack lacks it; either way
      // the result must not be Vietnamese.
      expect(tr('Đăng nhập'), isNot(contains(vn)));
    });
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
