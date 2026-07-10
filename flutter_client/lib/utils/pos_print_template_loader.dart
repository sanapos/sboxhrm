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

  return templates;
}
