import 'dart:convert';

/// `.xlsx` files are ZIP archives and start with `PK`.
bool isValidXlsxBytes(List<int> bytes) {
  if (bytes.length < 4) return false;
  return bytes[0] == 0x50 && bytes[1] == 0x4B;
}

String extensionFromMimeType(String mimeType) {
  final m = mimeType.toLowerCase().split(';').first.trim();
  return switch (m) {
    'image/png' => '.png',
    'image/jpeg' || 'image/jpg' => '.jpg',
    'image/gif' => '.gif',
    'image/webp' => '.webp',
    'application/pdf' => '.pdf',
    'text/csv' => '.csv',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
      '.xlsx',
    'application/vnd.ms-excel' => '.xls',
    _ => '',
  };
}

bool hasKnownFileExtension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot >= name.length - 1) return false;
  final ext = name.substring(dot).toLowerCase();
  const known = {
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.webp',
    '.bmp',
    '.pdf',
    '.xlsx',
    '.xls',
    '.csv',
    '.txt',
    '.zip',
  };
  return known.contains(ext);
}

/// Safe download filename — respects existing extension, else uses MIME / default.
String normalizeSaveFileName(
  String filename, {
  String? mimeType,
  String defaultExtension = '.xlsx',
}) {
  var name = filename.trim();
  final fallbackExt = defaultExtension.startsWith('.')
      ? defaultExtension
      : '.$defaultExtension';

  if (name.isEmpty) {
    var ext = mimeType != null ? extensionFromMimeType(mimeType) : '';
    if (ext.isEmpty) ext = fallbackExt;
    name = 'export$ext';
  }

  if (hasKnownFileExtension(name)) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  var ext = mimeType != null ? extensionFromMimeType(mimeType) : '';
  if (ext.isEmpty) ext = fallbackExt;
  if (!name.toLowerCase().endsWith(ext)) {
    name = '$name$ext';
  }
  return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}

String normalizeExportFileName(String filename, {String extension = '.xlsx'}) {
  return normalizeSaveFileName(filename, defaultExtension: extension);
}

/// When server returns JSON/HTML/text instead of xlsx, extract a user message.
String? parseNonExcelExportError(List<int> bytes) {
  if (bytes.isEmpty) return 'File tải về rỗng.';
  if (isValidXlsxBytes(bytes)) return null;

  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.isEmpty) return 'File tải về không phải Excel hợp lệ.';

  if (text.startsWith('<!DOCTYPE') ||
      text.startsWith('<html') ||
      text.startsWith('<HTML')) {
    return 'Máy chủ trả về trang web thay vì file Excel. Hãy đăng nhập lại.';
  }

  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      final decoded = json.decode(text);
      if (decoded is Map) {
        final msg = decoded['message'] ??
            decoded['Message'] ??
            decoded['title'] ??
            decoded['Title'];
        if (msg != null && msg.toString().trim().isNotEmpty) {
          return msg.toString().trim();
        }
      }
    } catch (_) {}
    return 'Máy chủ trả về JSON thay vì file Excel.';
  }

  if (text.length <= 300) return text;
  return 'File tải về không phải Excel hợp lệ.';
}
