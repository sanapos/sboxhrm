import 'package:flutter/material.dart';

import '../../../l10n/app_tr.dart';
import '../../../widgets/sbox/sbox_ui.dart';

/// Danh mục chức năng từ server (api/system-admin/v2/catalog).
class SaModule {
  SaModule({required this.code, required this.name, required this.description, required this.category, required this.productLine, required this.requires});
  final String code;
  final String name;
  final String description;
  final String category;
  final String productLine;
  final List<String> requires;

  factory SaModule.fromJson(Map<String, dynamic> j) => SaModule(
        code: '${j['code']}',
        name: '${j['name']}',
        description: '${j['description'] ?? ''}',
        category: '${j['category']}',
        productLine: '${j['productLine'] ?? 'common'}',
        requires: (j['requires'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

class SaPreset {
  SaPreset({required this.key, required this.name, required this.description, required this.productLine, required this.modules});
  final String key;
  final String name;
  final String description;
  final String productLine;
  final List<String> modules;

  factory SaPreset.fromJson(Map<String, dynamic> j) => SaPreset(
        key: '${j['key']}',
        name: '${j['name']}',
        description: '${j['description'] ?? ''}',
        productLine: '${j['productLine'] ?? 'both'}',
        modules: (j['modules'] as List?)?.map((e) => '$e').toList() ?? const [],
      );
}

class SaCatalog {
  SaCatalog({required this.categories, required this.modules, required this.presets, required this.fcm});
  final List<({String name, String productLine})> categories;
  final List<SaModule> modules;
  final List<SaPreset> presets;
  final List<({String code, String name})> fcm;

  late final Map<String, SaModule> byCode = {for (final m in modules) m.code.toLowerCase(): m};

  SaModule? module(String code) => byCode[code.toLowerCase()];
  String nameOf(String code) => module(code)?.name ?? code;

  factory SaCatalog.fromJson(Map<String, dynamic> j) => SaCatalog(
        categories: (j['categories'] as List? ?? [])
            .whereType<Map>()
            .map((e) => (name: '${e['name']}', productLine: '${e['productLine']}'))
            .toList(),
        modules: (j['modules'] as List? ?? []).whereType<Map>().map((e) => SaModule.fromJson(Map<String, dynamic>.from(e))).toList(),
        presets: (j['presets'] as List? ?? []).whereType<Map>().map((e) => SaPreset.fromJson(Map<String, dynamic>.from(e))).toList(),
        fcm: (j['fcmCategories'] as List? ?? []).whereType<Map>().map((e) => (code: '${e['code']}', name: '${e['name']}')).toList(),
      );

  /// (mã đã chọn, mã còn thiếu)
  List<(String, String)> missing(Set<String> selected) {
    final lower = {for (final s in selected) s.toLowerCase()};
    final out = <(String, String)>[];
    for (final c in selected) {
      for (final r in module(c)?.requires ?? const <String>[]) {
        if (!lower.contains(r.toLowerCase())) out.add((c, r));
      }
    }
    return out;
  }

  Set<String> withDependencies(Set<String> selected) {
    final set = {...selected};
    final lower = {for (final s in set) s.toLowerCase()};
    final queue = [...set];
    while (queue.isNotEmpty) {
      final c = queue.removeLast();
      for (final r in module(c)?.requires ?? const <String>[]) {
        if (lower.add(r.toLowerCase())) {
          set.add(r);
          queue.add(r);
        }
      }
    }
    return set;
  }
}

String saProductLineLabel(String? v) => switch (v) {
      'pos' => 'Bán hàng',
      'hrm' => 'Nhân sự',
      'both' => 'Bán hàng + Nhân sự',
      _ => 'Chung',
    };

SboxTone saProductLineTone(String? v) => switch (v) {
      'pos' => SboxTone.success,
      'hrm' => SboxTone.brand,
      'both' => SboxTone.violet,
      _ => SboxTone.neutral,
    };

String saMoney(num? v) => v == null ? 'Liên hệ' : SboxFmt.money(v);

String saDate(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '—';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

void saToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(tr(message)),
    backgroundColor: error ? SboxColors.danger : null,
    behavior: SnackBarBehavior.floating,
  ));
}

bool saOk(BuildContext context, Map<String, dynamic> r, String okMessage) {
  final ok = r['isSuccess'] == true;
  if (context.mounted) saToast(context, ok ? okMessage : '${r['message'] ?? 'Không thực hiện được'}', error: !ok);
  return ok;
}

InputDecoration saInput(String label, {String? suffix, String? helper, String? hint}) => InputDecoration(
      labelText: tr(label),
      suffixText: suffix,
      helperText: helper == null ? null : tr(helper),
      hintText: hint == null ? null : tr(hint),
      helperMaxLines: 2,
      isDense: true,
      border: OutlineInputBorder(borderRadius: SboxRadius.mdAll),
    );

/// Nút chọn phân đoạn kiểu viên thuốc.
class SaSegment<T> extends StatelessWidget {
  const SaSegment({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in options.entries)
          Padding(
            padding: const EdgeInsets.only(right: SboxSpace.xs),
            child: ChoiceChip(
              label: Text(tr(e.value)),
              selected: e.key == value,
              showCheckmark: false,
              onSelected: (_) => onChanged(e.key),
              labelStyle: SboxType.smallStyle(e.key == value ? SboxColors.brand700 : SboxColors.textSecondary)
                  .copyWith(fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500),
              selectedColor: SboxColors.brand50,
              backgroundColor: SboxColors.white,
              side: BorderSide(color: e.key == value ? SboxColors.brand300 : SboxColors.border),
              shape: const StadiumBorder(),
            ),
          ),
      ]),
    );
  }
}
