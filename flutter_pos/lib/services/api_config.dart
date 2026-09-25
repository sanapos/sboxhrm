import '../config/sbox_endpoints.dart';

/// `--dart-define=API_BASE=...` ghi đè; nếu không thì theo server của bản build
/// (`--dart-define=SBOX_SERVER=pos` → sboxpos.com, mặc định sboxhrm.com).
String getApiBaseUrl() {
  const explicit = String.fromEnvironment('API_BASE');
  if (explicit.isNotEmpty) return explicit;
  return SboxEndpoints.buildDefaultApi;
}
