import 'package:flutter/foundation.dart' show kIsWeb;

/// URL trang web công khai cho link chia sẻ bài truyền thông.
String communicationPublicShareUrl(String token) {
  if (token.isEmpty) return '';
  if (kIsWeb) {
    final origin = Uri.base.origin;
    if (origin.isNotEmpty && origin != 'null') {
      return '$origin/share/$token';
    }
  }
  const site = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://sbox.sana.vn',
  );
  final base = site.isNotEmpty ? site : 'https://sbox.sana.vn';
  return '${base.replaceAll(RegExp(r'/+$'), '')}/share/$token';
}

/// Gợi ý URL khi API trả publicShareUrl (ưu tiên server).
String resolveCommunicationShareUrl({
  String? serverUrl,
  String? token,
}) {
  if (serverUrl != null && serverUrl.trim().isNotEmpty) {
    return serverUrl.trim();
  }
  if (token != null && token.isNotEmpty) {
    return communicationPublicShareUrl(token);
  }
  return '';
}
