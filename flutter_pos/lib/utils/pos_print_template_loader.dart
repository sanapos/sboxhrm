import 'dart:async';

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

class _TplCacheEntry {
  _TplCacheEntry(this.list, this.epoch) : at = DateTime.now();
  final List<PosPrintTemplate> list;
  final int epoch;
  final DateTime at;
}

final _tplCache = <String, _TplCacheEntry>{};
final _tplInflight = <String, Future<List<PosPrintTemplate>>>{};

/// Sau thời gian này lần in tiếp vẫn dùng bản đệm nhưng tải lại ở nền.
const _tplFreshFor = Duration(seconds: 30);

/// Tải danh sách mẫu in; tự seed mặc định nếu chưa có.
/// Có bộ nhớ đệm: in bill không phải chờ API mẫu in mỗi lần (bản đệm cũ → trả ngay, tải lại ở nền).
Future<List<PosPrintTemplate>> loadPosPrintTemplates(
  ApiService api,
  String documentType,
) async {
  final hit = _tplCache[documentType];
  if (hit != null && hit.epoch == posPrintTemplatesEpoch && hit.list.isNotEmpty) {
    if (DateTime.now().difference(hit.at) > _tplFreshFor) {
      unawaited(_fetchPosPrintTemplates(api, documentType).catchError((_) => hit.list));
    }
    return hit.list;
  }
  return _fetchPosPrintTemplates(api, documentType);
}

Future<List<PosPrintTemplate>> _fetchPosPrintTemplates(ApiService api, String documentType) {
  final running = _tplInflight[documentType];
  if (running != null) return running;
  final epoch = posPrintTemplatesEpoch;
  final f = _loadPosPrintTemplatesFromApi(api, documentType).then((list) {
    if (list.isNotEmpty) _tplCache[documentType] = _TplCacheEntry(list, epoch);
    return list;
  }).whenComplete(() {
    _tplInflight.remove(documentType);
  });
  _tplInflight[documentType] = f;
  return f;
}

Future<List<PosPrintTemplate>> _loadPosPrintTemplatesFromApi(
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
