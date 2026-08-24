import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'pos_sell_settings_helper.dart';

typedef PosSellFeesParsed = ({
  bool enableSurcharge,
  bool enableDeliveryFee,
  String? surchargeLabel,
  bool? surchargeIsPercent,
  double? surchargeDefault,
  double? deliveryFeeDefault,
});

typedef PosSellVietQrParsed = ({
  bool showAtPayment,
  String? bankAccountId,
});

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
    this.enableSurcharge = false,
    this.enableDeliveryFee = false,
    this.surchargeLabel = '',
    this.surchargeIsPercent = false,
    this.surchargeDefault = 0,
    this.deliveryFeeDefault = 0,
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

  /// Hiện phụ thu (tiền hoặc %) trên màn thanh toán.
  final bool enableSurcharge;

  /// Hiện phí giao hàng trên màn thanh toán.
  final bool enableDeliveryFee;

  /// Tên hiển thị (trống = «Phụ thu»).
  final String surchargeLabel;

  /// Mặc định phụ phí theo % (true) hoặc tiền (false).
  final bool surchargeIsPercent;

  /// Mức mặc định tự nhảy trên đơn mới. 0 = không tự điền.
  final double surchargeDefault;

  /// Gợi ý phí GH (đ) tự nhảy trên đơn mới. 0 = không tự điền.
  final double deliveryFeeDefault;

  String get surchargeDisplayName {
    final t = surchargeLabel.trim();
    return t.isEmpty ? 'Phụ thu' : t;
  }

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
    bool? enableSurcharge,
    bool? enableDeliveryFee,
    String? surchargeLabel,
    bool? surchargeIsPercent,
    double? surchargeDefault,
    double? deliveryFeeDefault,
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
        enableSurcharge: enableSurcharge ?? this.enableSurcharge,
        enableDeliveryFee: enableDeliveryFee ?? this.enableDeliveryFee,
        surchargeLabel: surchargeLabel ?? this.surchargeLabel,
        surchargeIsPercent: surchargeIsPercent ?? this.surchargeIsPercent,
        surchargeDefault: surchargeDefault ?? this.surchargeDefault,
        deliveryFeeDefault: deliveryFeeDefault ?? this.deliveryFeeDefault,
      );

  static const _kName = 'pos_sell_store_name';
  static const _kAddress = 'pos_sell_store_address';
  static const _kPhone = 'pos_sell_store_phone';
  static const _kTaxMode = 'pos_sell_tax_mode';
  static const _kVatRate = 'pos_sell_default_vat_rate';
  static const _kVietQrBankId = 'pos_sell_vietqr_bank_id';
  static const _kShowVietQr = 'pos_sell_show_vietqr_payment';
  static const _kEnableSurcharge = 'pos_sell_enable_surcharge';
  static const _kEnableDeliveryFee = 'pos_sell_enable_delivery_fee';
  static const _kSurchargeLabel = 'pos_sell_surcharge_label';
  static const _kSurchargeIsPercent = 'pos_sell_surcharge_is_percent';
  static const _kSurchargeDefault = 'pos_sell_surcharge_default';
  static const _kDeliveryFeeDefault = 'pos_sell_delivery_fee_default';

  static String formatAmount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  static double parseAmount(String raw) {
    final t = raw.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.');
    return double.tryParse(t) ?? 0;
  }

  static String? _peekedExtraJson;
  static DateTime? _peekedAt;

  static void invalidateServerCache() {
    _peekedExtraJson = null;
    _peekedAt = null;
  }

  static Future<String?> _peekSellExtraJson() async {
    if (_peekedAt != null &&
        DateTime.now().difference(_peekedAt!) < const Duration(seconds: 30)) {
      return _peekedExtraJson;
    }
    try {
      final loaded = await PosSellSettingsHelper(ApiService()).load();
      _peekedExtraJson = loaded.settings?.extraJson;
      _peekedAt = DateTime.now();
      return _peekedExtraJson;
    } catch (_) {
      return _peekedExtraJson;
    }
  }

  /// Tên/địa chỉ/SĐT in bill = Thiết lập cửa hàng (prefs + ExtraJson.receiptStore).
  /// Không lấy JWT / tên tài khoản («link cửa hàng»).
  static Future<PosSellStoreSettings> load({
    String? extraJson,
    bool peekServer = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var name = prefs.getString(_kName) ?? '';
    var address = prefs.getString(_kAddress) ?? '';
    var phone = prefs.getString(_kPhone) ?? '';

    extraJson ??= peekServer ? await _peekSellExtraJson() : null;
    final parsed = parseReceiptStore(extraJson);
    if (parsed != null) {
      if (parsed.$1.isNotEmpty) name = parsed.$1;
      if (parsed.$2.isNotEmpty) address = parsed.$2;
      if (parsed.$3.isNotEmpty) phone = parsed.$3;
    }

    final vatRaw = prefs.getDouble(_kVatRate);
    final fees = parseFees(extraJson);
    final vietQr = parseVietQr(extraJson);
    return PosSellStoreSettings(
      storeName: name.trim(),
      address: address.trim(),
      phone: phone.trim(),
      taxMode: PosSellTaxMode.fromKey(prefs.getString(_kTaxMode)),
      defaultVatRate: vatRaw ?? 8,
      vietQrBankAccountId: vietQr?.bankAccountId ?? prefs.getString(_kVietQrBankId),
      showVietQrAtPayment:
          vietQr?.showAtPayment ?? prefs.getBool(_kShowVietQr) ?? true,
      enableSurcharge: fees?.enableSurcharge ??
          prefs.getBool(_kEnableSurcharge) ??
          false,
      enableDeliveryFee: fees?.enableDeliveryFee ??
          prefs.getBool(_kEnableDeliveryFee) ??
          false,
      surchargeLabel: (fees?.surchargeLabel != null &&
              fees!.surchargeLabel!.isNotEmpty)
          ? fees.surchargeLabel!
          : (prefs.getString(_kSurchargeLabel) ?? ''),
      surchargeIsPercent: fees?.surchargeIsPercent ??
          prefs.getBool(_kSurchargeIsPercent) ??
          false,
      surchargeDefault: fees?.surchargeDefault ??
          prefs.getDouble(_kSurchargeDefault) ??
          0,
      deliveryFeeDefault: fees?.deliveryFeeDefault ??
          prefs.getDouble(_kDeliveryFeeDefault) ??
          0,
    );
  }

  Future<void> save({ApiService? api}) async {
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
    await prefs.setBool(_kEnableSurcharge, enableSurcharge);
    await prefs.setBool(_kEnableDeliveryFee, enableDeliveryFee);
    await prefs.setString(_kSurchargeLabel, surchargeLabel.trim());
    await prefs.setBool(_kSurchargeIsPercent, surchargeIsPercent);
    await prefs.setDouble(_kSurchargeDefault, surchargeDefault);
    await prefs.setDouble(_kDeliveryFeeDefault, deliveryFeeDefault);
    invalidateServerCache();
    await persistSellTax(api ?? ApiService(), includeReceiptStore: true);
  }

  /// Server thắng prefs — QR bill đọc ExtraJson.sellTax.
  PosSellStoreSettings withServerTax(String? extraJson) {
    final parsed = parseSellTax(extraJson);
    if (parsed == null) return this;
    return copyWith(taxMode: parsed.$1, defaultVatRate: parsed.$2);
  }

  /// Tên in bill từ ExtraJson.receiptStore — không dùng JWT.
  PosSellStoreSettings withServerReceiptStore(String? extraJson) {
    final parsed = parseReceiptStore(extraJson);
    if (parsed == null) return this;
    return copyWith(
      storeName: parsed.$1.isNotEmpty ? parsed.$1 : storeName,
      address: parsed.$2.isNotEmpty ? parsed.$2 : address,
      phone: parsed.$3.isNotEmpty ? parsed.$3 : phone,
    );
  }

  /// Phụ thu / phí GH từ ExtraJson.fees — server thắng prefs.
  PosSellStoreSettings withServerFees(String? extraJson) {
    final parsed = parseFees(extraJson);
    if (parsed == null) return this;
    return copyWith(
      enableSurcharge: parsed.enableSurcharge,
      enableDeliveryFee: parsed.enableDeliveryFee,
      surchargeLabel: parsed.surchargeLabel,
      surchargeIsPercent: parsed.surchargeIsPercent,
      surchargeDefault: parsed.surchargeDefault,
      deliveryFeeDefault: parsed.deliveryFeeDefault,
    );
  }

  /// VietQR từ ExtraJson.vietQr — server thắng prefs (đồng bộ đa máy).
  PosSellStoreSettings withServerVietQr(String? extraJson) {
    final parsed = parseVietQr(extraJson);
    if (parsed == null) return this;
    return copyWith(
      showVietQrAtPayment: parsed.showAtPayment,
      clearVietQrBankAccountId: (parsed.bankAccountId ?? '').isEmpty,
      vietQrBankAccountId: parsed.bankAccountId,
    );
  }

  static bool hasServerReceiptStore(String? extraJson) =>
      parseReceiptStore(extraJson) != null;

  static (String, String, String)? parseReceiptStore(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) return null;
    try {
      final root = jsonDecode(extraJson);
      if (root is! Map) return null;
      final rs = root['receiptStore'] ?? root['ReceiptStore'];
      if (rs is! Map) return null;
      final m = Map<String, dynamic>.from(rs);
      return (
        (m['name'] ?? m['Name'] ?? '').toString().trim(),
        (m['address'] ?? m['Address'] ?? '').toString().trim(),
        (m['phone'] ?? m['Phone'] ?? '').toString().trim(),
      );
    } catch (_) {
      return null;
    }
  }

  static bool hasServerTax(String? extraJson) => parseSellTax(extraJson) != null;

  static (PosSellTaxMode, double)? parseSellTax(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) return null;
    try {
      final root = jsonDecode(extraJson);
      if (root is! Map) return null;
      final tax = root['sellTax'] ?? root['SellTax'];
      if (tax is! Map) return null;
      final m = Map<String, dynamic>.from(tax);
      final mode = PosSellTaxMode.fromKey(
          (m['mode'] ?? m['Mode'] ?? '').toString());
      final raw = m['vatRate'] ?? m['VatRate'];
      final rate = raw is num
          ? raw.toDouble()
          : double.tryParse('$raw') ?? 8;
      return (mode, rate.clamp(0, 100));
    } catch (_) {
      return null;
    }
  }

  static PosSellFeesParsed? parseFees(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) return null;
    try {
      final root = jsonDecode(extraJson);
      if (root is! Map) return null;
      final fees = root['fees'] ?? root['Fees'];
      if (fees is! Map) return null;
      final m = Map<String, dynamic>.from(fees);
      bool flag(dynamic v) =>
          v == true || v == 1 || '$v'.toLowerCase() == 'true';
      double numVal(dynamic v) {
        if (v is num) return v.toDouble();
        return parseAmount('$v');
      }

      dynamic pick(String a, String b) {
        if (m.containsKey(a)) return m[a];
        if (m.containsKey(b)) return m[b];
        return null;
      }

      final labelRaw = pick('surchargeLabel', 'SurchargeLabel');
      final percentRaw = pick('surchargeIsPercent', 'SurchargeIsPercent');
      final surchargeRaw = pick('surchargeDefault', 'SurchargeDefault');
      final deliveryRaw = pick('deliveryFeeDefault', 'DeliveryFeeDefault');

      return (
        enableSurcharge: flag(m['enableSurcharge'] ?? m['EnableSurcharge']),
        enableDeliveryFee:
            flag(m['enableDeliveryFee'] ?? m['EnableDeliveryFee']),
        surchargeLabel: labelRaw == null ? null : '$labelRaw'.trim(),
        surchargeIsPercent: percentRaw == null ? null : flag(percentRaw),
        surchargeDefault: surchargeRaw == null ? null : numVal(surchargeRaw),
        deliveryFeeDefault: deliveryRaw == null ? null : numVal(deliveryRaw),
      );
    } catch (_) {
      return null;
    }
  }

  static PosSellVietQrParsed? parseVietQr(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) return null;
    try {
      final root = jsonDecode(extraJson);
      if (root is! Map) return null;
      final vq = root['vietQr'] ?? root['VietQr'] ?? root['VietQR'];
      if (vq is! Map) return null;
      final m = Map<String, dynamic>.from(vq);
      bool flag(dynamic v) =>
          v == true || v == 1 || '$v'.toLowerCase() == 'true';
      final showRaw = m['showAtPayment'] ??
          m['ShowAtPayment'] ??
          m['showVietQrAtPayment'] ??
          m['ShowVietQrAtPayment'];
      final bankRaw = m['bankAccountId'] ??
          m['BankAccountId'] ??
          m['vietQrBankAccountId'] ??
          m['VietQrBankAccountId'];
      final bank = bankRaw == null ? null : '$bankRaw'.trim();
      return (
        showAtPayment: showRaw == null ? true : flag(showRaw),
        bankAccountId: (bank == null || bank.isEmpty) ? null : bank,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> persistSellTax(
    ApiService api, {
    bool includeReceiptStore = false,
  }) async {
    final helper = PosSellSettingsHelper(api);
    final loaded = await helper.load();
    if (loaded.settings == null) return;
    await helper.save(
      loaded.settings!.copyWith(
        extraJson: mergeSellTax(
          loaded.settings!.extraJson,
          includeReceiptStore: includeReceiptStore,
        ),
      ),
      applyDefaults: false,
    );
  }

  String mergeSellTax(String? existing, {bool includeReceiptStore = false}) {
    Map<String, dynamic> root = {};
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existing);
        if (decoded is Map) root = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    root['sellTax'] = {
      'mode': taxMode.key,
      'vatRate': defaultVatRate,
    };
    root['fees'] = {
      'enableSurcharge': enableSurcharge,
      'enableDeliveryFee': enableDeliveryFee,
      'surchargeLabel': surchargeLabel.trim(),
      'surchargeIsPercent': surchargeIsPercent,
      'surchargeDefault': surchargeDefault,
      'deliveryFeeDefault': deliveryFeeDefault,
    };
    if (includeReceiptStore) {
      root['receiptStore'] = {
        'name': storeName.trim(),
        'address': address.trim(),
        'phone': phone.trim(),
      };
    }
    root['vietQr'] = {
      'showAtPayment': showVietQrAtPayment,
      'bankAccountId': (vietQrBankAccountId ?? '').trim(),
    };
    invalidateServerCache();
    return jsonEncode(root);
  }
}
