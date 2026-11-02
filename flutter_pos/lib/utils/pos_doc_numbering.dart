import '../services/api_service.dart';

/// Đánh số báo giá / hợp đồng do cửa hàng đặt ở app chính (Thông tin cửa hàng › Đánh số báo giá & hợp đồng).
/// Máy này chỉ cần biết có «Tự nhập» không và số kế tiếp để gợi ý (GET /api/pos/quotes/numbering).
class PosDocNumberingInfo {
  const PosDocNumberingInfo({required this.manual, required this.pattern, required this.next});

  static const maxNoLength = 30;

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
