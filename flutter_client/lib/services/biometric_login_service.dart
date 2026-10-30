import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import 'api_service.dart';

/// Tài khoản đã bật đăng nhập bằng Face ID / vân tay trên máy này (không có mật khẩu).
class BiometricAccount {
  const BiometricAccount({
    required this.server,
    required this.storeCode,
    required this.email,
  });

  final String server;

  /// Mã cửa hàng thật gửi lên khi đăng nhập ('' = cổng SuperAdmin/Agent).
  final String storeCode;
  final String email;

  bool sameAs(String server, String storeCode, String email) =>
      this.server == server &&
      this.storeCode.toLowerCase() == storeCode.trim().toLowerCase() &&
      this.email.toLowerCase() == email.trim().toLowerCase();

  Map<String, String> toJson() =>
      {'server': server, 'storeCode': storeCode, 'email': email};

  static BiometricAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final server = raw['server']?.toString() ?? '';
    final email = raw['email']?.toString() ?? '';
    if (server.isEmpty || email.isEmpty) return null;
    return BiometricAccount(
      server: server,
      storeCode: raw['storeCode']?.toString() ?? '',
      email: email,
    );
  }
}

/// Đăng nhập nhanh bằng Face ID / Touch ID / vân tay của điện thoại.
///
/// Refresh token chỉ sống 120 phút nên không dùng được cho lần mở app hôm sau:
/// mật khẩu được giữ trong kho bảo mật của máy (Keychain iOS, Keystore Android),
/// chỉ đọc ra sau khi xác thực sinh trắc học thành công rồi đăng nhập như thường.
/// Không lưu ở SharedPreferences, không đồng bộ iCloud, không gửi đi đâu khác.
class BiometricLoginService {
  BiometricLoginService._();
  static final BiometricLoginService instance = BiometricLoginService._();

  final LocalAuthentication _auth = LocalAuthentication();
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _secretKey = 'sbox_bio_login_secret_v1';
  static const String _accountPref = 'sbox_bio_login_account_v1';
  static const String _declinedPref = 'sbox_bio_login_declined_v1';

  bool get platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Máy có cảm biến và đã cài khuôn mặt / vân tay.
  Future<bool> isAvailable() async {
    if (!platformSupported) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (e) {
      debugPrint('BiometricLogin: availability check failed: $e');
      return false;
    }
  }

  /// Nhãn nút / công tắc theo loại cảm biến của máy.
  Future<String> loginLabel() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final types = await _auth.getAvailableBiometrics();
        if (!types.contains(BiometricType.face) &&
            types.contains(BiometricType.fingerprint)) {
          return tr('Đăng nhập bằng Touch ID');
        }
      } catch (_) {}
      return tr('Đăng nhập bằng Face ID');
    }
    return tr('Đăng nhập bằng vân tay / khuôn mặt');
  }

  Future<BiometricAccount?> savedAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountPref);
      if (raw == null || raw.isEmpty) return null;
      return BiometricAccount.fromJson(json.decode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Tài khoản đã bật cho máy chủ đang kết nối (đổi máy chủ thì không hiện nút).
  Future<BiometricAccount?> accountForCurrentServer() async {
    final acc = await savedAccount();
    if (acc == null || acc.server != ApiService.baseUrl) return null;
    return acc;
  }

  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        authMessages: [
          AndroidAuthMessages(
            signInTitle: tr('Xác thực đăng nhập SBOX'),
            signInHint: '',
            cancelButton: tr('Hủy'),
          ),
        ],
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      debugPrint('BiometricLogin: authenticate ${e.code.name}');
      return false;
    } catch (e) {
      debugPrint('BiometricLogin: authenticate error: $e');
      return false;
    }
  }

  /// Bật cho tài khoản vừa nhập đúng mật khẩu. Hỏi Face ID trước khi lưu.
  Future<bool> enable({
    required String storeCode,
    required String email,
    required String password,
  }) async {
    if (!await authenticate(tr('Xác nhận để bật đăng nhập nhanh'))) {
      return false;
    }
    return _write(storeCode: storeCode, email: email, password: password);
  }

  /// Cập nhật mật khẩu đã lưu khi người dùng đăng nhập/đổi mật khẩu đúng tài khoản đó.
  Future<void> updatePasswordIfEnabled({
    required String storeCode,
    required String email,
    required String password,
  }) async {
    final acc = await savedAccount();
    if (acc == null || !acc.sameAs(ApiService.baseUrl, storeCode, email)) {
      return;
    }
    await _write(storeCode: storeCode, email: email, password: password);
  }

  Future<bool> _write({
    required String storeCode,
    required String email,
    required String password,
  }) async {
    final acc = BiometricAccount(
      server: ApiService.baseUrl,
      storeCode: storeCode.trim(),
      email: email.trim(),
    );
    try {
      await _storage.write(
        key: _secretKey,
        value: json.encode({...acc.toJson(), 'password': password}),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accountPref, json.encode(acc.toJson()));
      return true;
    } catch (e) {
      debugPrint('BiometricLogin: save failed: $e');
      return false;
    }
  }

  /// Face ID → trả về mật khẩu đã lưu của [acc]; null nếu hủy hoặc không còn dữ liệu.
  Future<String?> unlockPassword(BiometricAccount acc, String reason) async {
    if (!await authenticate(reason)) return null;
    try {
      final raw = await _storage.read(key: _secretKey);
      final data = raw == null ? null : json.decode(raw);
      final stored = BiometricAccount.fromJson(data);
      final password = data is Map ? data['password']?.toString() : null;
      if (stored == null ||
          password == null ||
          password.isEmpty ||
          !stored.sameAs(acc.server, acc.storeCode, acc.email)) {
        await disable();
        return null;
      }
      return password;
    } catch (e) {
      // Khóa Keystore mất (khôi phục bản sao lưu, xóa khóa màn hình…) → tắt hẳn.
      debugPrint('BiometricLogin: read failed: $e');
      await disable();
      return null;
    }
  }

  Future<void> disable() async {
    try {
      await _storage.delete(key: _secretKey);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accountPref);
    } catch (_) {}
  }

  String _declineKey(String storeCode, String email) =>
      '${ApiService.baseUrl}|${storeCode.trim().toLowerCase()}|${email.trim().toLowerCase()}';

  /// Người dùng đã bấm «Để sau» cho tài khoản này — không hỏi lại sau mỗi lần đăng nhập.
  Future<bool> wasDeclined(String storeCode, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_declinedPref) ?? const [])
          .contains(_declineKey(storeCode, email));
    } catch (_) {
      return false;
    }
  }

  Future<void> markDeclined(String storeCode, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_declinedPref) ?? <String>[];
      final key = _declineKey(storeCode, email);
      if (!list.contains(key)) {
        await prefs.setStringList(_declinedPref, [...list, key]);
      }
    } catch (_) {}
  }

  /// Danh tính đăng nhập gần nhất trên máy (giống cách màn đăng nhập gửi lên server).
  Future<({String storeCode, String email})> lastLoginIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('saved_email') ?? '';
    final adminEmail = prefs.getString('admin_saved_email') ?? '';
    var storeCode = prefs.getString('saved_store_code') ?? '';
    if (adminEmail.isNotEmpty &&
        email.toLowerCase() == adminEmail.toLowerCase()) {
      storeCode = '';
    }
    return (storeCode: storeCode, email: email);
  }
}
