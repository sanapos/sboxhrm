import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import 'biometric_auth.dart';

/// Đăng nhập sinh trắc bằng gói `local_auth`. Chỉ `lib/main.dart` (SBOX HRM, SBOX POS Android) nạp tệp này.
class LocalAuthBiometric implements BiometricAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (!await _auth.isDeviceSupported()) return false;
    if (!await _auth.canCheckBiometrics) return false;
    return (await _auth.getAvailableBiometrics()).isNotEmpty;
  }

  @override
  Future<bool> fingerprintOnly() async {
    final types = await _auth.getAvailableBiometrics();
    return !types.contains(BiometricType.face) && types.contains(BiometricType.fingerprint);
  }

  @override
  Future<bool> authenticate({
    required String reason,
    required String androidTitle,
    required String androidCancel,
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        authMessages: [
          AndroidAuthMessages(
            signInTitle: androidTitle,
            signInHint: '',
            cancelButton: androidCancel,
          ),
        ],
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException catch (e) {
      debugPrint('BiometricLogin: authenticate ${e.code.name}');
      return false;
    }
  }
}
