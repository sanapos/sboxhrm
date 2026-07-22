import 'dart:convert';

import '../models/pos_print_template_v2.dart';

abstract final class PosPrintTemplateV2Codec {
  static bool isV2Content(String? content) {
    if (content == null || content.trim().isEmpty) return false;
    final t = content.trimLeft();
    return t.startsWith(kPosPrintTemplateV2Marker) ||
        t.startsWith('{') && t.contains('"blocks"');
  }

  static PosPrintTemplateV2? tryParse(String? content) {
    if (content == null || content.trim().isEmpty) return null;
    var raw = content.trim();
    if (raw.startsWith(kPosPrintTemplateV2Marker)) {
      raw = raw.substring(kPosPrintTemplateV2Marker.length).trim();
    }
    try {
      if (raw.startsWith('{')) {
        return PosPrintTemplateV2.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  static String encode(PosPrintTemplateV2 template) =>
      '$kPosPrintTemplateV2Marker\n${template.encode()}';

  /// Chuyển mẫu V2 sang HTML legacy (fallback preview cũ).
  static String toLegacyHtmlHint(PosPrintTemplateV2 template) =>
      encode(template);
}
