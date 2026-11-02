import 'dart:convert';

import '../services/api_service.dart';
import 'pos_sell_settings_helper.dart';

/// Cách đánh số một loại chứng từ: tự nhảy theo [pattern], hoặc [manual] = người lập nhập / sửa số
/// (ô số gợi ý sẵn số kế tiếp theo mẫu, để trống vẫn tự nhảy).
class PosDocNumberRule {
  const PosDocNumberRule({this.manual = false, required this.pattern});

  final bool manual;
  final String pattern;

  Map<String, dynamic> toJson() => {'manual': manual, 'pattern': pattern};
}

/// Đánh số báo giá / hợp đồng của cửa hàng (PosStoreSellSettings.ExtraJson → "docNumbering").
/// Khớp PosDocNumbering ở máy chủ: chữ cố định + {YYYY} {YY} {MM} {DD} + đúng một {SEQ} / {SEQ:n}.
class PosDocNumbering {
  const PosDocNumbering({
    this.quote = const PosDocNumberRule(pattern: quoteDefault),
    this.contract = const PosDocNumberRule(pattern: contractDefault),
  });

  static const quoteDefault = 'BG{DD}{MM}{YYYY}{SEQ:4}';
  static const contractDefault = 'HDKT{DD}{MM}{YYYY}{SEQ:4}';
  static const maxNoLength = 30;
  static const maxPatternLength = 40;

  /// Mẫu hay dùng — bấm để điền.
  static const quotePresets = ['BG{DD}{MM}{YYYY}{SEQ:4}', 'BG-{YYYY}-{SEQ:4}', '{SEQ:3}/{YYYY}/BG'];
  static const contractPresets = ['HDKT{DD}{MM}{YYYY}{SEQ:4}', 'HĐ-{YYYY}-{SEQ:3}', '{SEQ:2}/{YYYY}/HĐKT'];

  final PosDocNumberRule quote;
  final PosDocNumberRule contract;

  static final _token = RegExp(r'\{([A-Za-z]+)(?::(\d+))?\}');

  static PosDocNumbering parse(String? extraJson) {
    if (extraJson == null || extraJson.trim().isEmpty) return const PosDocNumbering();
    try {
      final root = jsonDecode(extraJson);
      final n = root is Map ? root['docNumbering'] : null;
      if (n is! Map) return const PosDocNumbering();
      PosDocNumberRule rule(Object? raw, String def) {
        if (raw is! Map) return PosDocNumberRule(pattern: def);
        final p = '${raw['pattern'] ?? ''}'.trim();
        return PosDocNumberRule(manual: raw['manual'] == true, pattern: validate(p) == null ? p : def);
      }

      return PosDocNumbering(quote: rule(n['quote'], quoteDefault), contract: rule(n['contract'], contractDefault));
    } catch (_) {
      return const PosDocNumbering();
    }
  }

  /// Ghi vào ExtraJson, giữ nguyên các mục khác.
  String mergeIntoExtraJson(String? extraJson) {
    Map<String, dynamic> root = {};
    try {
      final r = jsonDecode(extraJson ?? '');
      if (r is Map) root = Map<String, dynamic>.from(r);
    } catch (_) {}
    root['docNumbering'] = {'quote': quote.toJson(), 'contract': contract.toJson()};
    return jsonEncode(root);
  }

  /// Lỗi của mẫu (null = hợp lệ).
  static String? validate(String pattern) {
    final p = pattern.trim();
    if (p.isEmpty) return 'Nhập mẫu số';
    if (p.length > maxPatternLength) return 'Mẫu dài quá $maxPatternLength ký tự';
    var seq = 0;
    for (final m in _token.allMatches(p)) {
      final name = m.group(1)!.toUpperCase();
      if (name == 'SEQ') {
        seq++;
        final d = m.group(2) == null ? 4 : int.tryParse(m.group(2)!);
        if (d == null || d < 1 || d > 9) return '{SEQ:n} — n từ 1 đến 9';
      } else if (!const {'YYYY', 'YY', 'MM', 'DD'}.contains(name) || m.group(2) != null) {
        return 'Không hiểu ${m.group(0)} — dùng {YYYY} {YY} {MM} {DD} {SEQ}';
      }
    }
    if (seq != 1) return 'Mẫu phải có đúng một {SEQ} (số thứ tự)';
    final literal = p.replaceAll(_token, '');
    if (literal.contains('{') || literal.contains('}')) return 'Dấu { } chỉ dùng cho {YYYY} {YY} {MM} {DD} {SEQ}';
    if (example(p, now: DateTime(2026, 12, 31)).length > maxNoLength) return 'Số sinh ra dài quá $maxNoLength ký tự';
    return null;
  }

  /// Số mẫu theo ngày [now] và thứ tự [seq] (xem trước trong thiết lập).
  static String example(String pattern, {DateTime? now, int seq = 1}) {
    final d = now ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return pattern.replaceAllMapped(_token, (m) {
      switch (m.group(1)!.toUpperCase()) {
        case 'YYYY':
          return '${d.year}';
        case 'YY':
          return two(d.year % 100);
        case 'MM':
          return two(d.month);
        case 'DD':
          return two(d.day);
        case 'SEQ':
          return '$seq'.padLeft(int.tryParse(m.group(2) ?? '') ?? 4, '0');
        default:
          return m.group(0)!;
      }
    });
  }

  /// Lưu lên cửa hàng (đồng bộ mọi máy). Trả lỗi hoặc null.
  static Future<String?> save(PosDocNumbering next, {ApiService? api}) async {
    final helper = PosSellSettingsHelper(api ?? ApiService());
    final loaded = await helper.load();
    if (loaded.settings == null) return loaded.error ?? 'Không tải được thiết lập';
    final res = await helper.save(
      loaded.settings!.copyWith(extraJson: next.mergeIntoExtraJson(loaded.settings!.extraJson)),
      applyDefaults: false,
    );
    return res.error;
  }
}

/// Thiết lập đánh số + số kế tiếp do máy chủ trả (GET /api/pos/quotes/numbering).
class PosDocNumberingInfo {
  const PosDocNumberingInfo({required this.manual, required this.pattern, required this.next});

  final bool manual;
  final String pattern;
  final String next;

  static Future<PosDocNumberingInfo?> fetch(String kind, {ApiService? api}) async {
    final res = await (api ?? ApiService()).getPosQuoteNumbering(kind);
    if (res['isSuccess'] != true || res['data'] is! Map) return null;
    final d = res['data'] as Map;
    return PosDocNumberingInfo(
      manual: d['manual'] == true,
      pattern: '${d['pattern'] ?? ''}',
      next: '${d['next'] ?? ''}',
    );
  }
}
