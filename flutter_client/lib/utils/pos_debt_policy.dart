import 'dart:convert';

/// Chính sách công nợ khách của cửa hàng (PosStoreSellSettings.ExtraJson → "debt").
/// Khách có hạn mức / hạn thanh toán riêng thì dùng số riêng (hồ sơ khách).
class PosDebtPolicy {
  const PosDebtPolicy({this.defaultLimit, this.termDays = 0, this.blockOverLimit = false, this.blockOverdue = false});

  /// Hạn mức nợ mặc định (đ); null = không giới hạn.
  final double? defaultLimit;
  /// Hạn thanh toán (ngày kể từ ngày bán); 0 = không theo dõi quá hạn.
  final int termDays;
  /// Vượt hạn mức: true = chặn bán nợ; false = chỉ cảnh báo, thu ngân xác nhận.
  final bool blockOverLimit;
  /// Có đơn quá hạn: true = chặn bán nợ thêm; false = chỉ cảnh báo.
  final bool blockOverdue;

  static PosDebtPolicy parse(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) return const PosDebtPolicy();
    try {
      final root = jsonDecode(extraJson);
      final d = root is Map ? root['debt'] : null;
      if (d is! Map) return const PosDebtPolicy();
      final lim = d['defaultLimit'];
      return PosDebtPolicy(
        defaultLimit: lim is num && lim > 0 ? lim.toDouble() : null,
        termDays: (d['termDays'] as num?)?.toInt() ?? 0,
        blockOverLimit: d['blockOverLimit'] == true,
        blockOverdue: d['blockOverdue'] == true,
      );
    } catch (_) {
      return const PosDebtPolicy();
    }
  }

  PosDebtPolicy copyWith({double? defaultLimit, bool clearLimit = false, int? termDays, bool? blockOverLimit, bool? blockOverdue}) =>
      PosDebtPolicy(
        defaultLimit: clearLimit ? null : (defaultLimit ?? this.defaultLimit),
        termDays: termDays ?? this.termDays,
        blockOverLimit: blockOverLimit ?? this.blockOverLimit,
        blockOverdue: blockOverdue ?? this.blockOverdue,
      );

  /// Ghi vào ExtraJson, giữ nguyên các mục khác (scale, hotel…).
  String mergeIntoExtraJson(String? extraJson) {
    Map<String, dynamic> root = {};
    try {
      final r = jsonDecode(extraJson ?? '');
      if (r is Map) root = Map<String, dynamic>.from(r);
    } catch (_) {}
    root['debt'] = {
      if (defaultLimit != null) 'defaultLimit': defaultLimit,
      'termDays': termDays,
      'blockOverLimit': blockOverLimit,
      'blockOverdue': blockOverdue,
    };
    return jsonEncode(root);
  }
}
