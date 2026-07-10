import 'dart:convert';

/// Danh sách module hiển thị trong lưới «Truy cập nhanh» (tab Thêm).
class MobileQuickActionsLayout {
  const MobileQuickActionsLayout({required this.modules});

  static const slotCount = 9;
  static const storageKey = 'mobile_quick_actions_v2';
  static const legacyStorageKey = 'mobile_quick_actions_v1';
  static const emptySlot = '';

  final List<String> modules;

  static const defaultModules = [
    'PosSell',
    'PosProducts',
    'PosSaleOrders',
    'Employee',
    'Payroll',
    'Leave',
    'Communication',
    'SettingsHub',
    'PosSalesReport',
  ];

  factory MobileQuickActionsLayout.defaults() =>
      MobileQuickActionsLayout(modules: List<String>.from(defaultModules));

  factory MobileQuickActionsLayout.fromJson(Map<String, dynamic> json) {
    final raw = json['modules'];
    final list = raw is List
        ? raw.map((e) => e.toString()).toList()
        : <String>[];
    return MobileQuickActionsLayout(modules: list);
  }

  factory MobileQuickActionsLayout.parseValue(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const MobileQuickActionsLayout(modules: []);
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return MobileQuickActionsLayout.fromJson(decoded);
      }
    } catch (_) {}
    return const MobileQuickActionsLayout(modules: []);
  }

  Map<String, dynamic> toJson() => {'modules': modules};

  String toStorageValue() => json.encode(toJson());

  MobileQuickActionsLayout normalized({required Set<String> allowedModules}) {
    final seen = <String>{};
    final out = <String>[];
    for (final code in modules) {
      if (out.length >= slotCount) break;
      if (code.isEmpty || !allowedModules.contains(code) || seen.contains(code)) {
        continue;
      }
      seen.add(code);
      out.add(code);
    }
    for (final code in defaultModules) {
      if (out.length >= slotCount) break;
      if (!allowedModules.contains(code) || seen.contains(code)) continue;
      seen.add(code);
      out.add(code);
    }
    for (final code in allowedModules) {
      if (out.length >= slotCount) break;
      if (seen.contains(code)) continue;
      seen.add(code);
      out.add(code);
    }
    while (out.length < slotCount) {
      out.add(emptySlot);
    }
    return MobileQuickActionsLayout(
      modules: out.take(slotCount).toList(),
    );
  }
}
