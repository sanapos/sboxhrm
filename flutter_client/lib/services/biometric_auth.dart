/// Cảm biến vân tay / khuôn mặt của máy, tách khỏi gói `local_auth`.
///
/// Bản cài đặt thật nằm ở `biometric_auth_local.dart` và chỉ được `lib/main.dart` gắn vào. Bản SBOX Bán Hàng
/// dùng điểm vào riêng, không gắn gì — `biometricAuth` là null nên đăng nhập sinh trắc tự tắt và gói không
/// chứa `local_auth` (Apple từ chối bản POS theo điều 2.5.19 vì quét thấy mã sinh trắc trong gói).
abstract class BiometricAuth {
  /// Máy có cảm biến và người dùng đã cài vân tay / khuôn mặt.
  Future<bool> isAvailable();

  /// true = máy chỉ có vân tay (iOS gọi là Touch ID); false = có khuôn mặt.
  Future<bool> fingerprintOnly();

  Future<bool> authenticate({
    required String reason,
    required String androidTitle,
    required String androidCancel,
  });
}

/// Null = máy / bản app này không có đăng nhập sinh trắc.
BiometricAuth? biometricAuth;
