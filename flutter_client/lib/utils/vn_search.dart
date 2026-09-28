/// Tìm kiếm tiếng Việt không dấu: «nguyen van a» khớp «Nguyễn Văn A».
library;

const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

final Map<int, int> _map = {
  for (var i = 0; i < _from.length; i++) _from.codeUnitAt(i): _to.codeUnitAt(i),
};

/// Chữ thường, bỏ dấu tiếng Việt.
String vnFold(String? s) {
  if (s == null || s.isEmpty) return '';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final c in lower.codeUnits) {
    out.writeCharCode(_map[c] ?? c);
  }
  return out.toString();
}

/// [text] có chứa [query] (không phân biệt hoa thường / dấu). [query] rỗng → true.
bool vnContains(String? text, String query) {
  final q = vnFold(query.trim());
  if (q.isEmpty) return true;
  return vnFold(text).contains(q);
}
