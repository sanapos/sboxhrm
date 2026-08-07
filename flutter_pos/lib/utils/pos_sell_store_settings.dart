import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'excel_report_builder.dart';

/// Cách tính thuế VAT trên màn bán hàng.
enum PosSellTaxMode {
  includedInPrice('included', 'Giá bán đã bao gồm thuế'),
  perItem('per_item', 'Thuế theo từng mặt hàng'),
  orderTotal('order_total', 'Thuế trên tổng đơn hàng');

  const PosSellTaxMode(this.key, this.label);

  final String key;
  final String label;

  static PosSellTaxMode fromKey(String? key) {
    return PosSellTaxMode.values.firstWhere(
      (e) => e.key == key,
      orElse: () => PosSellTaxMode.includedInPrice,
    );
  }
}

/// Thông tin cửa hàng hiển thị trên màn bán hàng và mẫu in.
class PosSellStoreSettings {
  const PosSellStoreSettings({
    this.storeName = '',
    this.address = '',
    this.phone = '',
    this.taxMode = PosSellTaxMode.includedInPrice,
    this.defaultVatRate = 8,
    this.vietQrBankAccountId,
    this.showVietQrAtPayment = true,
  });

  final String storeName;
  final String address;
  final String phone;

  /// Chế độ tính thuế VAT.
  final PosSellTaxMode taxMode;

  /// % VAT mặc định (đơn hàng hoặc giá đã gồm thuế).
  final double defaultVatRate;

  /// Tài khoản NH nhận VietQR (null = dùng mặc định).
  final String? vietQrBankAccountId;

  /// Hiện mã VietQR trên màn thanh toán.
  final bool showVietQrAtPayment;

  bool get hasInfo =>
      storeName.trim().isNotEmpty ||
      address.trim().isNotEmpty ||
      phone.trim().isNotEmpty;

  PosSellStoreSettings copyWith({
    String? storeName,
    String? address,
    String? phone,
    PosSellTaxMode? taxMode,
    double? defaultVatRate,
    String? vietQrBankAccountId,
    bool clearVietQrBankAccountId = false,
    bool? showVietQrAtPayment,
  }) =>
      PosSellStoreSettings(
        storeName: storeName ?? this.storeName,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        taxMode: taxMode ?? this.taxMode,
        defaultVatRate: defaultVatRate ?? this.defaultVatRate,
        vietQrBankAccountId: clearVietQrBankAccountId
            ? null
            : (vietQrBankAccountId ?? this.vietQrBankAccountId),
        showVietQrAtPayment: showVietQrAtPayment ?? this.showVietQrAtPayment,
      );

  static const _kName = 'pos_sell_store_name';
  static const _kAddress = 'pos_sell_store_address';
  static const _kPhone = 'pos_sell_store_phone';
  static const _kTaxMode = 'pos_sell_tax_mode';
  static const _kVatRate = 'pos_sell_default_vat_rate';
  static const _kVietQrBankId = 'pos_sell_vietqr_bank_id';
  static const _kShowVietQr = 'pos_sell_show_vietqr_payment';

  static Future<PosSellStoreSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    var name = prefs.getString(_kName) ?? '';
    final address = prefs.getString(_kAddress) ?? '';
    final phone = prefs.getString(_kPhone) ?? '';

    if (name.trim().isEmpty) {
      final token = await ApiService().getStoredToken();
      name = ExcelReportContext.fromJwt(token).storeName ?? '';
    }

    final vatRaw = prefs.getDouble(_kVatRate);
    return PosSellStoreSettings(
      storeName: name.trim(),
      address: address.trim(),
      phone: phone.trim(),
      taxMode: PosSellTaxMode.fromKey(prefs.getString(_kTaxMode)),
      defaultVatRate: vatRaw ?? 8,
      vietQrBankAccountId: prefs.getString(_kVietQrBankId),
      showVietQrAtPayment: prefs.getBool(_kShowVietQr) ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, storeName.trim());
    await prefs.setString(_kAddress, address.trim());
    await prefs.setString(_kPhone, phone.trim());
    await prefs.setString(_kTaxMode, taxMode.key);
    await prefs.setDouble(_kVatRate, defaultVatRate);
    if (vietQrBankAccountId != null && vietQrBankAccountId!.isNotEmpty) {
      await prefs.setString(_kVietQrBankId, vietQrBankAccountId!);
    } else {
      await prefs.remove(_kVietQrBankId);
    }
    await prefs.setBool(_kShowVietQr, showVietQrAtPayment);
  }
}
