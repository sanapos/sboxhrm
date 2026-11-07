import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zkteco_flutter_client/config/sbox_app_variant.dart';

Future<void> _useApp(String packageName, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  PackageInfo.setMockInitialValues(
    appName: 'SBOX',
    packageName: packageName,
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  await SboxAppVariant.bootstrap();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('BOSS và Nhân Viên trên iOS khóa máy chủ, trên Android vẫn đổi được', () async {
    for (final package in ['boss.sboxpos.com', 'staff.sboxpos.com']) {
      await _useApp(package, TargetPlatform.iOS);
      expect(SboxAppVariant.iosStoreApp, isTrue, reason: package);
      expect(SboxAppVariant.fixedServer, isTrue, reason: package);

      await _useApp(package, TargetPlatform.android);
      expect(SboxAppVariant.fixedServer, isFalse, reason: package);
    }
  });

  test('SBOX POS trên iOS khóa máy chủ, trên Android đổi được', () async {
    await _useApp(SboxAppVariant.iosPosBundleId, TargetPlatform.iOS);
    expect(SboxAppVariant.fixedServer, isTrue);

    await _useApp(SboxAppVariant.androidPosApplicationId, TargetPlatform.android);
    expect(SboxAppVariant.fixedServer, isFalse);
  });

  test('Chỉ BOSS trên iOS ẩn màn khuôn mặt, máy chấm công', () async {
    await _useApp('boss.sboxpos.com', TargetPlatform.iOS);
    for (final code in ['Device', 'DeviceUser', 'MobileAttendance', 'FieldCheckIn']) {
      expect(SboxAppVariant.hidesModule(code), isTrue, reason: code);
    }
    expect(SboxAppVariant.hidesModule('Payroll'), isFalse);

    await _useApp('boss.sboxpos.com', TargetPlatform.android);
    expect(SboxAppVariant.hidesModule('DeviceUser'), isFalse);

    await _useApp('staff.sboxpos.com', TargetPlatform.iOS);
    expect(SboxAppVariant.hidesModule('MobileAttendance'), isFalse);
  });
}
