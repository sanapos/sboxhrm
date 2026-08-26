import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Biến thể app: HRM (mặc định) hoặc POS độc lập cho Play Store.
///
/// Bật POS bằng `--flavor pos` (package `sbox.sana.vn.pos`) và/hoặc
/// `--dart-define=SBOX_POS_STANDALONE=true`.
abstract final class SboxAppVariant {
  static const androidPosApplicationId = 'sbox.sana.vn.pos';

  static const bool _fromDefine = bool.fromEnvironment(
    'SBOX_POS_STANDALONE',
    defaultValue: false,
  );

  static bool _fromPackage = false;

  static bool get standalonePos => _fromDefine || _fromPackage;

  static String get productLine =>
      standalonePos ? 'SBOX POS' : 'SBOX HRM - SBOX POS';

  static String get slogan => standalonePos
      ? 'Thu ngân, hoá đơn, kho, máy in — trên điện thoại và máy POS'
      : 'Giải pháp quản lý toàn diện cho doanh nghiệp';

  static String get loginHeroTitle => standalonePos
      ? 'Bán hàng\nthời gian thực'
      : 'Quản lý nhân sự\nthời gian thực';

  static String get materialAppTitle => productLine;

  static Future<void> bootstrap() async {
    if (_fromDefine || kIsWeb) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _fromPackage = info.packageName == androidPosApplicationId;
    } catch (_) {}
  }
}
