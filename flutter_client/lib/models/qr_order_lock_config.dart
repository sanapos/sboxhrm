import 'dart:convert';

/// Khóa QR order ngoài quán — lưu trong ExtraJson.qrOrder.
class QrOrderLockConfig {
  const QrOrderLockConfig({
    this.requireOpenSession = false,
    this.requireGeofence = false,
  });

  /// Chỉ gọi món khi thu ngân đã mở bàn (không tự tạo phiên từ QR).
  final bool requireOpenSession;

  /// Chỉ gọi món khi GPS khách nằm trong geofence cửa hàng.
  final bool requireGeofence;

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
      return QrOrderLockConfig(
        requireOpenSession: m['requireOpenSession'] == true ||
            m['RequireOpenSession'] == true,
        requireGeofence:
            m['requireGeofence'] == true || m['RequireGeofence'] == true,
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
    root['qrOrder'] = {
      'requireOpenSession': requireOpenSession,
      'requireGeofence': requireGeofence,
    };
    return jsonEncode(root);
  }

  QrOrderLockConfig copyWith({
    bool? requireOpenSession,
    bool? requireGeofence,
  }) =>
      QrOrderLockConfig(
        requireOpenSession: requireOpenSession ?? this.requireOpenSession,
        requireGeofence: requireGeofence ?? this.requireGeofence,
      );
}
