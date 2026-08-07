import '../models/pos_sell_industry.dart';
import '../services/api_service.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;

/// Load / save chung cho các màn thiết lập ngành / màn phụ / hủy-trả.
class PosSellSettingsHelper {
  PosSellSettingsHelper(this._api);

  final ApiService _api;

  Future<({PosStoreSellSettingsDto? settings, String? error})> load() async {
    final res = await _api.getPosSellSettings();
    if (res['isSuccess'] == true && res['data'] is Map) {
      return (
        settings: PosStoreSellSettingsDto.fromJson(
          Map<String, dynamic>.from(res['data'] as Map),
        ),
        error: null,
      );
    }
    return (
      settings: null,
      error: res['message']?.toString() ?? 'Không tải được thiết lập',
    );
  }

  Future<({PosStoreSellSettingsDto? settings, String? error, int? status})>
      save(
    PosStoreSellSettingsDto s, {
    bool applyDefaults = false,
    bool quietRefresh = true,
  }) async {
    final res = await _api.updatePosSellSettings(
      s.toSaveBody(applyProfileDefaults: applyDefaults),
    );
    if (res['isSuccess'] == true && res['data'] is Map) {
      final next = PosStoreSellSettingsDto.fromJson(
        Map<String, dynamic>.from(res['data'] as Map),
      );
      if (quietRefresh) {
        ScreenRefreshNotifier.refreshPosSellIndustry();
      }
      return (settings: next, error: null, status: null);
    }
    return (
      settings: null,
      error: res['message']?.toString() ?? 'Không lưu được',
      status: res['statusCode'] is int ? res['statusCode'] as int : null,
    );
  }
}
