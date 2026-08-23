import 'dart:convert';

/// Khóa QR order ngoài quán — lưu trong ExtraJson.qrOrder.
class QrOrderLockConfig {
  const QrOrderLockConfig({
    this.requireOpenSession = false,
    this.requireGeofence = false,
    this.requireOrderConfirmation = false,
    this.onlineAutoConfirm = false,
    this.onlineAutoPrintKitchen = false,
    this.onlineAutoPay = false,
    this.onlineAutoPrintProvisional = false,
    this.onlineAutoCreateShipment = false,
    this.onlineDefaultCarrierCode,
    this.storeZalo,
    this.logoUrl,
    this.banners = const [],
  });

  /// Chỉ gọi món khi thu ngân đã mở bàn (không tự tạo phiên từ QR).
  final bool requireOpenSession;

  /// Chỉ gọi món khi GPS khách nằm trong geofence cửa hàng.
  final bool requireGeofence;

  /// Bật: không tự in bếp — thu ngân xác nhận (âm thanh + thông báo).
  /// Mặc định tắt: không cần xác nhận, theo «Tự in phiếu bếp».
  final bool requireOrderConfirmation;

  /// Đơn online: tự chuyển trạng thái «Đã xác nhận» khi khách gửi.
  final bool onlineAutoConfirm;

  /// Đơn online: tự in phiếu bếp khi đơn được xác nhận (tự động hoặc thu ngân).
  final bool onlineAutoPrintKitchen;

  /// Đơn online: tự hoàn thành đơn COD khi xác nhận.
  final bool onlineAutoPay;

  /// Đơn online: gợi ý in tạm tính ngay sau xác nhận (trên POS).
  final bool onlineAutoPrintProvisional;

  /// Đơn online: tự tạo vận đơn khi chuyển «Đang giao».
  final bool onlineAutoCreateShipment;

  /// Hãng mặc định: Internal | Ghn | Ghtk | … (trống = hỏi thủ công).
  final String? onlineDefaultCarrierCode;

  /// SĐT / link Zalo shop hiển thị trên trang đặt online (để trống = dùng SĐT cửa hàng).
  final String? storeZalo;

  /// Logo quán trên trang khách QR (path stores/.../qr-order/...).
  final String? logoUrl;

  /// Ảnh quảng cáo (tối đa 5) khi khách mở link đặt hàng.
  final List<String> banners;

  factory QrOrderLockConfig.fromExtraJson(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) {
      return const QrOrderLockConfig();
    }
    try {
      final root = jsonDecode(extraJson);
      if (root is! Map) return const QrOrderLockConfig();
      final qr = root['qrOrder'] ?? root['QrOrder'];
      if (qr is! Map) return const QrOrderLockConfig();
      final m = Map<String, dynamic>.from(qr);
      final logo = (m['logoUrl'] ?? m['LogoUrl'])?.toString().trim();
      final rawBanners = m['banners'] ?? m['Banners'];
      final banners = <String>[];
      if (rawBanners is List) {
        for (final e in rawBanners) {
          final s = e.toString().trim();
          if (s.isEmpty) continue;
          banners.add(s);
          if (banners.length >= 5) break;
        }
      }
      return QrOrderLockConfig(
        requireOpenSession: m['requireOpenSession'] == true ||
            m['RequireOpenSession'] == true,
        requireGeofence:
            m['requireGeofence'] == true || m['RequireGeofence'] == true,
        requireOrderConfirmation: m['requireOrderConfirmation'] == true ||
            m['RequireOrderConfirmation'] == true,
        onlineAutoConfirm: m['onlineAutoConfirm'] == true ||
            m['OnlineAutoConfirm'] == true,
        onlineAutoPrintKitchen: m['onlineAutoPrintKitchen'] == true ||
            m['OnlineAutoPrintKitchen'] == true,
        onlineAutoPay:
            m['onlineAutoPay'] == true || m['OnlineAutoPay'] == true,
        onlineAutoPrintProvisional: m['onlineAutoPrintProvisional'] == true ||
            m['OnlineAutoPrintProvisional'] == true,
        onlineAutoCreateShipment: m['onlineAutoCreateShipment'] == true ||
            m['OnlineAutoCreateShipment'] == true,
        onlineDefaultCarrierCode: _optStr(
            m['onlineDefaultCarrierCode'] ?? m['OnlineDefaultCarrierCode']),
        storeZalo: _optStr(m['storeZalo'] ?? m['StoreZalo']),
        logoUrl: (logo == null || logo.isEmpty) ? null : logo,
        banners: banners,
      );
    } catch (_) {
      return const QrOrderLockConfig();
    }
  }

  String mergeIntoExtraJson(String? existing) {
    Map<String, dynamic> root = {};
    if (existing != null && existing.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existing);
        if (decoded is Map) root = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    final qr = <String, dynamic>{};
    final existingQr = root['qrOrder'] ?? root['QrOrder'];
    if (existingQr is Map) {
      qr.addAll(Map<String, dynamic>.from(existingQr));
    }
    qr['requireOpenSession'] = requireOpenSession;
    qr['requireGeofence'] = requireGeofence;
    qr['requireOrderConfirmation'] = requireOrderConfirmation;
    qr['onlineAutoConfirm'] = onlineAutoConfirm;
    qr['onlineAutoPrintKitchen'] = onlineAutoPrintKitchen;
    qr['onlineAutoPay'] = onlineAutoPay;
    qr['onlineAutoPrintProvisional'] = onlineAutoPrintProvisional;
    qr['onlineAutoCreateShipment'] = onlineAutoCreateShipment;
    final carrier = (onlineDefaultCarrierCode ?? '').trim();
    if (carrier.isEmpty) {
      qr.remove('onlineDefaultCarrierCode');
      qr.remove('OnlineDefaultCarrierCode');
    } else {
      qr['onlineDefaultCarrierCode'] = carrier;
    }
    final zalo = (storeZalo ?? '').trim();
    if (zalo.isEmpty) {
      qr.remove('storeZalo');
      qr.remove('StoreZalo');
    } else {
      qr['storeZalo'] = zalo;
    }
    final logo = (logoUrl ?? '').trim();
    if (logo.isEmpty) {
      qr.remove('logoUrl');
      qr.remove('LogoUrl');
    } else {
      qr['logoUrl'] = logo;
    }
    qr['banners'] = banners
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(5)
        .toList();
    root['qrOrder'] = qr;
    root.remove('QrOrder');
    return jsonEncode(root);
  }

  QrOrderLockConfig copyWith({
    bool? requireOpenSession,
    bool? requireGeofence,
    bool? requireOrderConfirmation,
    bool? onlineAutoConfirm,
    bool? onlineAutoPrintKitchen,
    bool? onlineAutoPay,
    bool? onlineAutoPrintProvisional,
    bool? onlineAutoCreateShipment,
    String? onlineDefaultCarrierCode,
    String? storeZalo,
    String? logoUrl,
    List<String>? banners,
    bool clearLogo = false,
    bool clearStoreZalo = false,
    bool clearOnlineDefaultCarrier = false,
  }) =>
      QrOrderLockConfig(
        requireOpenSession: requireOpenSession ?? this.requireOpenSession,
        requireGeofence: requireGeofence ?? this.requireGeofence,
        requireOrderConfirmation:
            requireOrderConfirmation ?? this.requireOrderConfirmation,
        onlineAutoConfirm: onlineAutoConfirm ?? this.onlineAutoConfirm,
        onlineAutoPrintKitchen:
            onlineAutoPrintKitchen ?? this.onlineAutoPrintKitchen,
        onlineAutoPay: onlineAutoPay ?? this.onlineAutoPay,
        onlineAutoPrintProvisional:
            onlineAutoPrintProvisional ?? this.onlineAutoPrintProvisional,
        onlineAutoCreateShipment:
            onlineAutoCreateShipment ?? this.onlineAutoCreateShipment,
        onlineDefaultCarrierCode: clearOnlineDefaultCarrier
            ? null
            : (onlineDefaultCarrierCode ?? this.onlineDefaultCarrierCode),
        storeZalo: clearStoreZalo ? null : (storeZalo ?? this.storeZalo),
        logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
        banners: banners ?? this.banners,
      );

  static String? _optStr(dynamic v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }
}
