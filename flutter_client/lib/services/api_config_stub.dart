import '../config/sbox_app_variant.dart';
import '../config/sbox_endpoints.dart';

/// `--dart-define=API_BASE_URL=...` ghi đè; nếu không thì theo biến thể app:
/// POS (flavor `pos` / `SBOX_POS_STANDALONE`) và SBOX BOSS (flavor `boss`) → sboxpos.com, HRM → sboxhrm.com.
String getApiBaseUrl() {
  const explicit = String.fromEnvironment('API_BASE_URL');
  if (explicit.isNotEmpty) return explicit;
  return SboxAppVariant.standalonePos || SboxAppVariant.bossApp
      ? SboxEndpoints.posSite
      : SboxEndpoints.hrmSite;
}
