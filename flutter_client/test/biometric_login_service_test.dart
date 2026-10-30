import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:local_auth_platform_interface/local_auth_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';
import 'package:zkteco_flutter_client/services/biometric_login_service.dart';

class _FakeLocalAuth extends LocalAuthPlatform {
  bool allow = true;
  List<BiometricType> enrolled = [BiometricType.strong];
  int prompts = 0;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required Iterable<AuthMessages> authMessages,
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    prompts++;
    return allow;
  }

  @override
  Future<bool> deviceSupportsBiometrics() async => enrolled.isNotEmpty;

  @override
  Future<List<BiometricType>> getEnrolledBiometrics() async => enrolled;

  @override
  Future<bool> isDeviceSupported() async => true;

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bio = BiometricLoginService.instance;
  late _FakeLocalAuth auth;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    auth = _FakeLocalAuth();
    LocalAuthPlatform.instance = auth;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('bật sau khi xác thực → Face ID trả lại đúng mật khẩu', () async {
    expect(await bio.isAvailable(), isTrue);
    expect(
        await bio.enable(storeCode: 'sanapos', email: 'an@x.vn', password: 'p@ss123'),
        isTrue);

    final acc = await bio.accountForCurrentServer();
    expect(acc, isNotNull);
    expect(acc!.server, ApiService.baseUrl);
    expect(acc.sameAs(ApiService.baseUrl, 'SANAPOS', 'AN@x.vn'), isTrue);
    expect(await bio.unlockPassword(acc, 'r'), 'p@ss123');
    expect(auth.prompts, 2);
  });

  test('hủy Face ID → không lưu, không trả mật khẩu', () async {
    auth.allow = false;
    expect(
        await bio.enable(storeCode: 's', email: 'e@x.vn', password: 'p@ss123'),
        isFalse);
    expect(await bio.savedAccount(), isNull);

    auth.allow = true;
    await bio.enable(storeCode: 's', email: 'e@x.vn', password: 'p@ss123');
    auth.allow = false;
    final acc = (await bio.savedAccount())!;
    expect(await bio.unlockPassword(acc, 'r'), isNull);
    // Hủy không làm mất cài đặt.
    expect(await bio.savedAccount(), isNotNull);
  });

  test('máy chưa cài vân tay / khuôn mặt → không khả dụng', () async {
    auth.enrolled = [];
    expect(await bio.isAvailable(), isFalse);
  });

  test('đổi mật khẩu chỉ cập nhật đúng tài khoản đã bật', () async {
    await bio.enable(storeCode: 's', email: 'e@x.vn', password: 'old-pass');
    await bio.updatePasswordIfEnabled(
        storeCode: 's', email: 'other@x.vn', password: 'wrong');
    final acc = (await bio.savedAccount())!;
    expect(await bio.unlockPassword(acc, 'r'), 'old-pass');

    await bio.updatePasswordIfEnabled(
        storeCode: 'S', email: 'E@x.vn', password: 'new-pass');
    expect(await bio.unlockPassword(acc, 'r'), 'new-pass');
  });

  test('mất mật khẩu trong kho bảo mật → tự tắt', () async {
    await bio.enable(storeCode: 's', email: 'e@x.vn', password: 'p@ss123');
    final acc = (await bio.savedAccount())!;
    FlutterSecureStorage.setMockInitialValues({});
    expect(await bio.unlockPassword(acc, 'r'), isNull);
    expect(await bio.savedAccount(), isNull);
  });

  test('«Để sau» chỉ áp dụng cho tài khoản đó', () async {
    await bio.markDeclined('s', 'e@x.vn');
    expect(await bio.wasDeclined('S', 'E@X.VN'), isTrue);
    expect(await bio.wasDeclined('s', 'khac@x.vn'), isFalse);
  });

  test('web không hỗ trợ / tắt xóa sạch', () async {
    await bio.enable(storeCode: 's', email: 'e@x.vn', password: 'p@ss123');
    await bio.disable();
    expect(await bio.savedAccount(), isNull);
  });
}
