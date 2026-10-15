/// Đọc nội dung mã QR trên căn cước công dân gắn chip:
/// `CCCD|CMND_CŨ|HỌ_TÊN|NGÀY_SINH|GIỚI_TÍNH|ĐỊA_CHỈ|NGÀY_CẤP` (7 trường, CMND cũ có thể để trống),
/// hoặc bản 6 trường không có CMND cũ. Ngày dạng `ddMMyyyy` (hoặc `dd/MM/yyyy`).
///
/// Trả về null nếu không phải mã căn cước hợp lệ (không đủ trường, số căn cước không đủ 12 chữ số).
/// Khoá kết quả: `cccd`, `oldIdNumber`, `fullName`, `dob` (DateTime?), `gender` ('Nam' | 'Nữ' | null),
/// `address`, `issueDate` (chuỗi gốc), `issueDateValue` (DateTime?).
Map<String, dynamic>? parseCccdQr(String raw) {
  // Bỏ ký tự điều khiển / BOM / xuống dòng ở đầu cuối (máy quét hay thêm \r\n).
  final text = raw.replaceAll('﻿', '').trim();
  final parts = text.split('|').map((p) => p.trim()).toList();
  if (parts.length < 6) return null;

  final String cccd = parts[0];
  final String? oldId;
  final String fullName, dobStr, gender, address, issueDateStr;
  if (parts.length >= 7) {
    oldId = parts[1].isEmpty ? null : parts[1];
    fullName = parts[2];
    dobStr = parts[3];
    gender = parts[4];
    address = parts[5];
    issueDateStr = parts[6];
  } else {
    oldId = null;
    fullName = parts[1];
    dobStr = parts[2];
    gender = parts[3];
    address = parts[4];
    issueDateStr = parts[5];
  }

  if (!RegExp(r'^\d{12}$').hasMatch(cccd)) return null;

  return {
    'cccd': cccd,
    'oldIdNumber': oldId,
    'fullName': _titleCase(fullName),
    'dob': _parseDate(dobStr),
    'gender': _normalizeGender(gender),
    'address': address,
    'issueDate': issueDateStr,
    'issueDateValue': _parseDate(issueDateStr),
  };
}

String _titleCase(String name) => name
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

String? _normalizeGender(String g) {
  final v = g.trim().toLowerCase();
  if (v == 'nam' || v == 'male' || v == 'm') return 'Nam';
  if (v == 'nữ' || v == 'nu' || v == 'female' || v == 'f') return 'Nữ';
  return null;
}

/// `ddMMyyyy`, `dd/MM/yyyy`, `dd-MM-yyyy`; ngày không có thật (31/02, tháng 13 ...) → null.
DateTime? _parseDate(String s) {
  int? d, m, y;
  final digits = s.trim();
  if (RegExp(r'^\d{8}$').hasMatch(digits)) {
    d = int.parse(digits.substring(0, 2));
    m = int.parse(digits.substring(2, 4));
    y = int.parse(digits.substring(4, 8));
  } else {
    final match = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(digits);
    if (match == null) return null;
    d = int.parse(match.group(1)!);
    m = int.parse(match.group(2)!);
    y = int.parse(match.group(3)!);
  }
  if (y < 1900 || m < 1 || m > 12 || d < 1) return null;
  final dt = DateTime(y, m, d);
  // DateTime tự cuộn ngày thừa sang tháng sau (31/02 → 03/03) — không chấp nhận.
  return dt.year == y && dt.month == m && dt.day == d ? dt : null;
}
