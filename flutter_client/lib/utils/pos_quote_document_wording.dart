import '../models/pos_quote.dart';

/// Đánh dấu HTML đã sửa riêng trên một chứng từ. Mẫu chung không có dấu này.
const posQuoteDocWordingMark = '<!--SBOX_DOC_WORDING-->';

bool posQuoteDocWordingIsCustom(String html) =>
    html.contains(posQuoteDocWordingMark);

/// HTML đã sửa lời riêng của ĐÚNG một chứng từ ([docId] hoặc [docNo]). Null nếu chứng từ đó in theo mẫu.
///
/// Không truyền [docId]/[docNo]: chỉ áp cho báo giá (mỗi báo giá một bản lời riêng, lấy bản sửa mới nhất) —
/// hợp đồng / biên bản / đề nghị TT có thể có nhiều bản cùng loại nên phải chỉ rõ chứng từ.
String? posQuoteSavedWordingHtml(
  Iterable<PosQuoteDocument> docs,
  String kind, {
  String? docId,
  String? docNo,
}) {
  final byId = docId != null && docId.isNotEmpty;
  final byNo = !byId && docNo != null && docNo.isNotEmpty;
  if (!byId && !byNo && kind != 'Quote') return null;
  PosQuoteDocument? best;
  for (final d in docs) {
    if (d.kind != kind) continue;
    if (byId && d.id != docId) continue;
    if (byNo && d.docNo != docNo) continue;
    if (!d.isCustomWording && !posQuoteDocWordingIsCustom(d.htmlContent)) continue;
    if (d.htmlContent.trim().isEmpty) continue;
    final at = d.wordingUpdatedAt ?? d.issuedAt;
    final bestAt = best?.wordingUpdatedAt ?? best?.issuedAt;
    if (best == null || (at != null && (bestAt == null || at.isAfter(bestAt)))) best = d;
  }
  return best?.htmlContent.trim();
}

/// Phần trong `<body>` để đưa vào trình soạn.
String posQuoteWordingBody(String html) {
  final m = RegExp(
    r'<body[^>]*>([\s\S]*)</body>',
    caseSensitive: false,
  ).firstMatch(html);
  if (m != null) return m.group(1)!.trim();
  return html.trim();
}

/// Ghép phần vừa sửa vào đúng chứng từ và đánh dấu lời riêng.
String posQuoteMergeWording(String original, String editedBody) {
  var body = editedBody.trim();
  if (!body.contains(posQuoteDocWordingMark)) {
    body = '$posQuoteDocWordingMark\n$body';
  }
  final re = RegExp(r'<body[^>]*>[\s\S]*</body>', caseSensitive: false);
  final match = re.firstMatch(original);
  if (match == null) return body;
  final open = RegExp(r'<body[^>]*>', caseSensitive: false)
      .firstMatch(match.group(0)!)!
      .group(0)!;
  return original.replaceRange(match.start, match.end, '$open$body</body>');
}
