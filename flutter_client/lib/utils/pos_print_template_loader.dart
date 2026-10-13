import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_print_template.dart';
import '../services/api_service.dart';
import '../services/pos_network_monitor.dart';

/// Mẫu in lưu trên máy — mất mạng (bán offline) vẫn in đúng mẫu cửa hàng.
const _tplDiskPrefix = 'pos_tpl_cache_v1_';

Future<List<PosPrintTemplate>> _readDiskTemplates(String documentType) async {
  try {
    final raw = (await SharedPreferences.getInstance()).getString(_tplDiskPrefix + documentType);
    if (raw == null || raw.isEmpty) return const [];
    return parsePosPrintTemplatesResponse({'isSuccess': true, 'data': jsonDecode(raw)})
        .where((t) => t.isActive)
        .toList();
  } catch (_) {
    return const [];
  }
}

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
  // Mất kết nối máy chủ: dùng mẫu đã lưu trên máy ngay, không chờ hết giờ.
  if (!PosNetworkMonitor.instance.reachable.value) {
    final disk = await _readDiskTemplates(documentType);
    if (disk.isNotEmpty) return disk;
  }
  var res = await api.getPosPrintTemplates(documentType: documentType);
  var templates = parsePosPrintTemplatesResponse(res);
  if (templates.isNotEmpty && res['data'] is List) {
    unawaited(SharedPreferences.getInstance().then((p) =>
        p.setString(_tplDiskPrefix + documentType, jsonEncode(res['data']))).catchError((_) => false));
  } else if (templates.isEmpty && res['isSuccess'] != true) {
    final disk = await _readDiskTemplates(documentType);
    if (disk.isNotEmpty) return disk;
  }

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
