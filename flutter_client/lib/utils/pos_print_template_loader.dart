import '../models/pos_print_template.dart';
import '../services/api_service.dart';

List<PosPrintTemplate> parsePosPrintTemplatesResponse(Map<String, dynamic> res) {
  if (res['isSuccess'] == true && res['data'] is List) {
    return (res['data'] as List)
        .map((e) => PosPrintTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }
  return [];
}

/// Chọn mẫu đúng khổ máy (K58/K80). Mặc định store K80 không dùng cho máy 58mm.
PosPrintTemplate? pickPosPrintTemplateForPaper(
  List<PosPrintTemplate> list, {
  String? paperSize,
  String? templateId,
}) {
  if (list.isEmpty) return null;
  DateTime stamp(PosPrintTemplate t) =>
      t.updatedAt ?? t.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final want = (paperSize ?? '').trim().toUpperCase();
  if (want.isNotEmpty) {
    final sized = list
        .where((t) => t.paperSize.trim().toUpperCase() == want)
        .toList();
    if (sized.isNotEmpty) {
      final defs = sized.where((t) => t.isDefault).toList();
      final pool = defs.isNotEmpty ? defs : sized;
      pool.sort((a, b) => stamp(b).compareTo(stamp(a)));
      return pool.first;
    }
  }
  if (templateId != null && templateId.isNotEmpty) {
    final hit = list.where((t) => t.id == templateId).firstOrNull;
    if (hit != null) return hit;
  }
  final defaults = list.where((t) => t.isDefault).toList();
  final pool = defaults.isNotEmpty ? defaults : list;
  final sorted = [...pool]..sort((a, b) => stamp(b).compareTo(stamp(a)));
  return sorted.first;
}

/// Tải danh sách mẫu in; tự seed mặc định nếu chưa có.
Future<List<PosPrintTemplate>> loadPosPrintTemplates(
  ApiService api,
  String documentType,
) async {
  var res = await api.getPosPrintTemplates(documentType: documentType);
  var templates = parsePosPrintTemplatesResponse(res);

  if (templates.isEmpty) {
    await api.seedPosPrintTemplates(documentType: documentType);
    res = await api.getPosPrintTemplates(documentType: documentType);
    templates = parsePosPrintTemplatesResponse(res);
  }

  templates = templates.where((t) => t.isActive).toList();
  if (PosPrintPaperSizes.isLabelDoc(documentType)) {
    templates = templates
        .where((t) => PosPrintPaperSizes.isLabelSize(t.paperSize))
        .toList();
  }

  return templates;
}
