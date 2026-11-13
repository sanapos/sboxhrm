import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/services/fcm_register_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Token FCM của máy không được gắn vào tài khoản đang «Đăng nhập thay» — trước đây làm
/// máy Super Admin nhận thông báo chấm công của cửa hàng khác.
void main() {
  Future<SharedPreferences> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('đăng nhập bình thường → dùng access token hiện tại', () async {
    final p = await prefs({'access_token': 'jwt-admin'});
    expect(fcmRegisterAccessToken(p), 'jwt-admin');
  });

  test('chưa đăng nhập → không gắn', () async {
    expect(fcmRegisterAccessToken(await prefs({})), isNull);
    expect(fcmRegisterAccessToken(await prefs({'access_token': ''})), isNull);
  });

  test('đang đăng nhập thay → không gắn token máy vào tài khoản cửa hàng', () async {
    final p = await prefs({
      'access_token': 'jwt-store-user',
      kImpersonationLabelPrefKey: 'Vọc glamping · Quản lý',
    });
    expect(fcmRegisterAccessToken(p), isNull);
  });
}
