import 'dart:convert';

/// Cấu hình thứ tự và hiển thị module trên sidebar Thiết lập HRM (theo cửa hàng).
class SettingsHubSidebarConfig {
  const SettingsHubSidebarConfig({
    required this.order,
    required this.hidden,
  });

  /// Thứ tự index module (theo [SettingsHubCatalog]).
  final List<int> order;

  /// Index module bị ẩn khỏi sidebar.
  final Set<int> hidden;

  static const storageKey = 'settings_hub_sidebar_layout';

  factory SettingsHubSidebarConfig.defaults(List<int> allIndices) {
    return SettingsHubSidebarConfig(
      order: List<int>.from(allIndices),
      hidden: const {},
    );
  }

  factory SettingsHubSidebarConfig.fromJson(Map<String, dynamic> json) {
    final rawOrder = json['order'];
    final order = rawOrder is List
        ? rawOrder.map((e) => int.tryParse(e.toString()) ?? -1).where((i) => i >= 0).toList()
        : <int>[];
    final rawHidden = json['hidden'];
    final hidden = rawHidden is List
        ? rawHidden.map((e) => int.tryParse(e.toString()) ?? -1).where((i) => i >= 0).toSet()
        : <int>{};
    return SettingsHubSidebarConfig(order: order, hidden: hidden);
  }

  factory SettingsHubSidebarConfig.parseValue(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const SettingsHubSidebarConfig(order: [], hidden: {});
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return SettingsHubSidebarConfig.fromJson(decoded);
      }
    } catch (_) {}
    return const SettingsHubSidebarConfig(order: [], hidden: {});
  }

  Map<String, dynamic> toJson() => {
        'order': order,
        'hidden': hidden.toList(),
      };

  String toStorageValue() => json.encode(toJson());

  SettingsHubSidebarConfig copyWith({
    List<int>? order,
    Set<int>? hidden,
  }) {
    return SettingsHubSidebarConfig(
      order: order ?? this.order,
      hidden: hidden ?? this.hidden,
    );
  }

  bool isVisible(int index) => !hidden.contains(index);
}
