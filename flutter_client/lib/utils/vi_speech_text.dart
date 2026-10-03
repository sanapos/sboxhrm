/// Chuẩn hóa văn bản trước khi đọc bằng giọng máy (TTS) tiếng Việt:
/// tiền, giờ, ngày, phần trăm, chữ viết tắt hay gặp trong SBOX → chữ đọc được tự nhiên.
class ViSpeechText {
  ViSpeechText._();

  static const _abbr = <String, String>{
    'NV': 'nhân viên',
    'KH': 'khách hàng',
    'HĐ': 'hóa đơn',
    'HĐĐT': 'hóa đơn điện tử',
    'SL': 'số lượng',
    'SĐT': 'số điện thoại',
    'TK': 'tài khoản',
    'CK': 'chuyển khoản',
    'TM': 'tiền mặt',
    'BHXH': 'bảo hiểm xã hội',
    'BHYT': 'bảo hiểm y tế',
    'TNCN': 'thu nhập cá nhân',
    'KPI': 'ka pê i',
    'POS': 'pốt',
    'QR': 'quy a',
    'GPS': 'gi pi ét',
    'ID': 'ai đi',
    'OK': 'ô kê',
  };

  /// «1.500.000đ» → «1 triệu 500 nghìn đồng»; số lớn đọc theo triệu / nghìn cho tự nhiên.
  static String _money(String digits) {
    final n = int.tryParse(digits.replaceAll(RegExp(r'[.,\s]'), ''));
    if (n == null) return '$digits đồng';
    return '${_compactNumber(n)} đồng';
  }

  static String _compactNumber(int n) {
    if (n < 1000) return '$n';
    final parts = <String>[];
    final ty = n ~/ 1000000000;
    final trieu = (n % 1000000000) ~/ 1000000;
    final nghin = (n % 1000000) ~/ 1000;
    final le = n % 1000;
    if (ty > 0) parts.add('$ty tỷ');
    if (trieu > 0) parts.add('$trieu triệu');
    if (nghin > 0) parts.add('$nghin nghìn');
    if (le > 0) parts.add('$le');
    return parts.join(' ');
  }

  static String normalize(String input) {
    var t = input;
    // Tiền: 1.500.000đ / 1.500.000 đ / 1,500,000 VND / 50k
    t = t.replaceAllMapped(RegExp(r'(\d[\d.,]*)\s?(?:đ|₫|vnđ|vnd|VND|VNĐ)(?![a-zà-ỹ])'), (m) => _money(m[1]!));
    t = t.replaceAllMapped(RegExp(r'\b(\d+)k\b'), (m) => '${m[1]} nghìn');
    // Giờ: 08:30 → 8 giờ 30; 08:00 → 8 giờ
    t = t.replaceAllMapped(RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b'), (m) {
      final h = int.parse(m[1]!);
      final mi = int.parse(m[2]!);
      return mi == 0 ? '$h giờ' : '$h giờ $mi';
    });
    // Ngày: 03/10/2026 → ngày 3 tháng 10 năm 2026; 03/10 → ngày 3 tháng 10
    // «ngày» đã có sẵn trước số thì không thêm lần nữa.
    t = t.replaceAllMapped(RegExp(r'(?:([Nn]gày)\s+)?\b(\d{1,2})/(\d{1,2})/(\d{4})\b'),
        (m) => '${m[1] ?? 'ngày'} ${int.parse(m[2]!)} tháng ${int.parse(m[3]!)} năm ${m[4]}');
    t = t.replaceAllMapped(RegExp(r'(?:([Nn]gày)\s+)?\b(\d{1,2})/(\d{1,2})\b'),
        (m) => '${m[1] ?? 'ngày'} ${int.parse(m[2]!)} tháng ${int.parse(m[3]!)}');
    // Phần trăm, phân số đơn giản, khoảng «–»
    t = t.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s?%'), (m) => '${m[1]!.replaceAll('.', ' phẩy ').replaceAll(',', ' phẩy ')} phần trăm');
    t = t.replaceAllMapped(RegExp(r'(\d)\s?[–-]\s?(\d)'), (m) => '${m[1]} đến ${m[2]}');
    // Số có dấu chấm nghìn (không phải tiền): 12.500 → 12 nghìn 500
    t = t.replaceAllMapped(RegExp(r'\b\d{1,3}(?:\.\d{3})+\b'), (m) => _compactNumber(int.parse(m[0]!.replaceAll('.', ''))));
    // Chữ viết tắt (nguyên từ)
    _abbr.forEach((k, v) {
      t = t.replaceAll(RegExp('(?<![\\p{L}])${RegExp.escape(k)}(?![\\p{L}])', unicode: true), v);
    });
    // Ký hiệu
    t = t
        .replaceAll('&', ' và ')
        .replaceAll('→', ', ')
        .replaceAll('›', ', ')
        .replaceAll(RegExp(r'[«»"“”]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }
}
