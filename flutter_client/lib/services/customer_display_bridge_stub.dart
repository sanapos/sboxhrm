/// Stub — nền tảng không hỗ trợ mở cửa sổ/display phụ qua bridge.
class CustomerDisplayPlatformBridge {
  static Future<bool> openSecondary({String route = '/customer-display'}) async =>
      false;

  static Future<bool> closeSecondary() async => false;

  static Future<List<Map<String, dynamic>>> listDisplays() async => const [];

  static Future<void> publishNative(String json) async {}

  static Future<String?> readNative() async => null;

  static Stream<String>? nativeStateStream() => null;
}
