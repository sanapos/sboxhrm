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

  /// Chuẩn hóa đúng 5 ô, không trùng module (giữ lần đầu), điền mặc định nếu thiếu.
  MobileBottomNavLayout normalized({
    required List<String> defaultSlots,
    required Set<String> allowedIds,
  }) {
    final seen = <String>{};
    final out = <String>[];
    for (final id in slots) {
      if (out.length >= slotCount) break;
      if (!allowedIds.contains(id) || seen.contains(id)) continue;
      seen.add(id);
      out.add(id);
    }
    for (final id in defaultSlots) {
      if (out.length >= slotCount) break;
      if (!allowedIds.contains(id) || seen.contains(id)) continue;
      seen.add(id);
      out.add(id);
    }
    // POS hub: luôn giữ «Nhiều hơn» nếu bị thay khi tùy chỉnh.
    const moreId = '_posMore';
    if (allowedIds.contains(moreId) && !seen.contains(moreId)) {
      if (out.length >= slotCount) {
        out[slotCount - 1] = moreId;
      } else {
        out.add(moreId);
      }
      seen.add(moreId);
    }
    for (final id in allowedIds) {
      if (out.length >= slotCount) break;
      if (seen.contains(id)) continue;
      seen.add(id);
      out.add(id);
    }
    while (out.length < slotCount) {
      out.add('_empty');
    }
    return MobileBottomNavLayout(slots: out.take(slotCount).toList());
  }
}
