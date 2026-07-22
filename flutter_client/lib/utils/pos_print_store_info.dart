import 'pos_sell_store_settings.dart';

/// Thông tin cửa hàng dùng khi in hóa đơn / phiếu.
class PosPrintStoreInfo {
  const PosPrintStoreInfo({
    this.storeName,
    this.address,
    this.phone,
  });

  final String? storeName;
  final String? address;
  final String? phone;

  static Future<PosPrintStoreInfo> load() async {
    final s = await PosSellStoreSettings.load();
    return PosPrintStoreInfo(
      storeName: s.storeName.trim().isNotEmpty ? s.storeName.trim() : null,
      address: s.address.trim().isNotEmpty ? s.address.trim() : null,
      phone: s.phone.trim().isNotEmpty ? s.phone.trim() : null,
    );
  }
}
