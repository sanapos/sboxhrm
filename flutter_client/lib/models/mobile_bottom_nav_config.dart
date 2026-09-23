import 'dart:convert';

/// Cấu hình 5 ô cố định trên thanh điều hướng mobile (app hoặc POS hub).
class MobileBottomNavLayout {
  const MobileBottomNavLayout({required this.slots});

  static const slotCount = 5;
  static const storageKeyMain = 'mobile_bottom_nav_main_v3';
  static const storageKeyPos = 'mobile_bottom_nav_pos_v3';
  /// Legacy keys — bỏ qua sau khi nâng bố cục mặc định.
  static const legacyStorageKeyMain = 'mobile_bottom_nav_main_v2';
  static const legacyStorageKeyPos = 'mobile_bottom_nav_pos_v2';

  /// Module code hoặc id đặc biệt: [_drawer], [_posMore].
  final List<String> slots;

  /// Mặc định: Trang chủ · Bán hàng · Chấm công · Cài đặt · Thêm
  /// (đồng bộ lối vào POS + Thiết lập với trang chủ đầy đủ).
  static const defaultMainSlots = [
    'Home',
    'PosSell',
    'MobileAttendance',
    'SettingsHub',
    '_drawer',
  ];

  static const defaultPosSlots = [
    'PosSalesReport',
    'PosProducts',
    'PosSell',
    'PosSaleOrders',
    '_posMore',
  ];

  factory MobileBottomNavLayout.mainDefaults() =>
      MobileBottomNavLayout(slots: List<String>.from(defaultMainSlots));

  factory MobileBottomNavLayout.posDefaults() =>
      MobileBottomNavLayout(slots: List<String>.from(defaultPosSlots));

  factory MobileBottomNavLayout.fromJson(Map<String, dynamic> json) {
    final raw = json['slots'];
    final list = raw is List
        ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : <String>[];
    return MobileBottomNavLayout(slots: list);
  }

  factory MobileBottomNavLayout.parseValue(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const MobileBottomNavLayout(slots: []);
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return MobileBottomNavLayout.fromJson(decoded);
      }
    } catch (_) {}
    return const MobileBottomNavLayout(slots: []);
  }

  Map<String, dynamic> toJson() => {'slots': slots};

  String toStorageValue() => json.encode(toJson());

  MobileBottomNavLayout copyWith({List<String>? slots}) =>
      MobileBottomNavLayout(slots: slots ?? this.slots);

  /// Đúng 5 vị trí. Ô không có trong gói để trống tại chỗ, không kéo chức năng khác vào.
  /// Ô cuối luôn là «Thêm» (app) hoặc «Nhiều hơn» (POS).
  MobileBottomNavLayout normalized({
    required List<String> defaultSlots,
    required Set<String> allowedIds,
  }) {
    const moreId = '_posMore';
    const drawerId = '_drawer';
    final source = slots.length == slotCount ? slots : defaultSlots;
    final out = <String>[];
    for (var i = 0; i < slotCount; i++) {
      final id = i < source.length ? source[i] : '_empty';
      if (id == drawerId || id == moreId) {
        out.add(id);
        continue;
      }
      if (id != '_empty' && allowedIds.contains(id)) {
        out.add(id);
      } else {
        out.add('_empty');
      }
    }
    if (allowedIds.contains(moreId)) {
      out[slotCount - 1] = moreId;
    } else if (allowedIds.contains(drawerId)) {
      out[slotCount - 1] = drawerId;
    }
    final seen = <String>{};
    for (var i = 0; i < out.length; i++) {
      final id = out[i];
      if (id == '_empty' || id == drawerId || id == moreId) continue;
      if (!seen.add(id)) out[i] = '_empty';
    }
    return MobileBottomNavLayout(slots: out);
  }
}
