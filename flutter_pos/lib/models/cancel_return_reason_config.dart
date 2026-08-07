import 'dart:convert';

/// Cấu hình trong sell-settings.extraJson → cancelReturnReason.
class CancelReturnReasonConfig {
  const CancelReturnReasonConfig({
    this.enabled = false,
    this.reasons = const ['Thao tác sai', 'Khách yêu cầu'],
  });

  final bool enabled;
  final List<String> reasons;

  static const defaultReasons = ['Thao tác sai', 'Khách yêu cầu'];

  factory CancelReturnReasonConfig.fromExtraJson(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) {
      return const CancelReturnReasonConfig();
    }
    try {
      final root = jsonDecode(extraJson);
      if (root is! Map) return const CancelReturnReasonConfig();
      final raw = root['cancelReturnReason'] ?? root['CancelReturnReason'];
      if (raw is! Map) return const CancelReturnReasonConfig();
      final m = Map<String, dynamic>.from(raw);
      final reasons = (m['reasons'] as List?)
              ?.map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          defaultReasons;
      return CancelReturnReasonConfig(
        enabled: m['enabled'] == true,
        reasons: reasons.isEmpty ? defaultReasons : reasons,
      );
    } catch (_) {
      return const CancelReturnReasonConfig();
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
    root['cancelReturnReason'] = {
      'enabled': enabled,
      'reasons': reasons,
    };
    return jsonEncode(root);
  }

  CancelReturnReasonConfig copyWith({
    bool? enabled,
    List<String>? reasons,
  }) {
    return CancelReturnReasonConfig(
      enabled: enabled ?? this.enabled,
      reasons: reasons ?? this.reasons,
    );
  }
}

/// Kết quả dialog chọn lý do hủy/trả.
class CancelReturnReasonResult {
  const CancelReturnReasonResult({
    required this.reason,
    this.detailNote,
  });

  final String reason;
  final String? detailNote;
}
