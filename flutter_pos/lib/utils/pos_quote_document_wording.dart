import '../models/pos_quote.dart';

/// Đánh dấu HTML đã sửa riêng trên một chứng từ. Mẫu chung không có dấu này.
const posQuoteDocWordingMark = '<!--SBOX_DOC_WORDING-->';

bool posQuoteDocWordingIsCustom(String html) =>
    html.contains(posQuoteDocWordingMark);

/// HTML đã khóa lời của đúng loại chứng từ. Null nếu còn in theo mẫu.
String? posQuoteSavedWordingHtml(
  Iterable<PosQuoteDocument> docs,
  String kind,
) {
  for (final d in docs) {
    if (d.kind != kind) continue;
    if (!posQuoteDocWordingIsCustom(d.htmlContent)) continue;
    final html = d.htmlContent.trim();
    if (html.isNotEmpty) return html;
  }
  return null;
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
