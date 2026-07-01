import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'excel_report_builder.dart';

/// Thông tin cửa hàng hiển thị trên màn bán hàng và mẫu in.
class PosSellStoreSettings {
  const PosSellStoreSettings({
    this.storeName = '',
    this.address = '',
    this.phone = '',
  });

  final String storeName;
  final String address;
  final String phone;

  bool get hasInfo =>
      storeName.trim().isNotEmpty ||
      address.trim().isNotEmpty ||
      phone.trim().isNotEmpty;

  PosSellStoreSettings copyWith({
    String? storeName,
    String? address,
    String? phone,
  }) =>
      PosSellStoreSettings(
        storeName: storeName ?? this.storeName,
        address: address ?? this.address,
        phone: phone ?? this.phone,
      );

  static const _kName = 'pos_sell_store_name';
  static const _kAddress = 'pos_sell_store_address';
  static const _kPhone = 'pos_sell_store_phone';

  static Future<PosSellStoreSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var name = prefs.getString(_kName) ?? '';
    final address = prefs.getString(_kAddress) ?? '';
    final phone = prefs.getString(_kPhone) ?? '';

    if (name.trim().isEmpty) {
      final token = await ApiService().getStoredToken();
      name = ExcelReportContext.fromJwt(token).storeName ?? '';
    }

    return PosSellStoreSettings(
      storeName: name.trim(),
      address: address.trim(),
      phone: phone.trim(),
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, storeName.trim());
    await prefs.setString(_kAddress, address.trim());
    await prefs.setString(_kPhone, phone.trim());
  }
}
