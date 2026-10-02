import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/pos_esc_pos_text_codec.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Phòng ban (từ /api/departments/v2/overview).
class Dept {
  Dept(this.m);
  final Map<String, dynamic> m;

  String get id => '${m['id']}';
  String get name => '${m['name'] ?? ''}';
  String get code => '${m['code'] ?? ''}';
  String? get parentId => m['parentId']?.toString();
  String? get description => m['description']?.toString();
  bool get isActive => m['isActive'] != false;
  int get sortOrder => (m['sortOrder'] as num?)?.toInt() ?? 0;
  String? get managerId => m['managerId']?.toString();
  String? get managerName => m['managerName']?.toString();
  String? get managerPhoto => m['managerPhoto']?.toString();
  String? get managerPosition => m['managerPosition']?.toString();
  int get directCount => (m['directCount'] as num?)?.toInt() ?? 0;
  int get totalCount => (m['totalCount'] as num?)?.toInt() ?? 0;
  int get childCount => (m['childCount'] as num?)?.toInt() ?? 0;
  List<String> get positions => [for (final p in (m['positions'] as List? ?? const [])) '$p'];
}

/// Cây phòng ban dựng từ danh sách phẳng.
class DeptTree {
  DeptTree(List<Dept> list) {
    for (final d in list) {
      byId[d.id] = d;
    }
    for (final d in list) {
      final p = d.parentId != null && byId.containsKey(d.parentId) ? d.parentId : null;
      (children[p] ??= []).add(d);
    }
    for (final l in children.values) {
      l.sort((a, b) => a.sortOrder != b.sortOrder ? a.sortOrder.compareTo(b.sortOrder) : a.name.compareTo(b.name));
    }
  }

  final Map<String, Dept> byId = {};
  final Map<String?, List<Dept>> children = {};

  List<Dept> get roots => children[null] ?? const [];
  List<Dept> kids(String? id) => children[id] ?? const [];

  /// Thứ tự hiển thị (DFS) kèm cấp.
  List<(Dept, int)> flatten({Set<String>? collapsed}) {
    final out = <(Dept, int)>[];
    void walk(String? parent, int depth) {
      for (final d in kids(parent)) {
        out.add((d, depth));
        if (collapsed == null || !collapsed.contains(d.id)) walk(d.id, depth + 1);
      }
    }

    walk(null, 0);
    return out;
  }

  /// Phòng và mọi phòng con (không được chọn làm phòng cha của chính nó).
  Set<String> descendantsOf(String id) {
    final set = <String>{id};
    final q = [id];
    while (q.isNotEmpty) {
      for (final c in kids(q.removeLast())) {
        if (set.add(c.id)) q.add(c.id);
      }
    }
    return set;
  }

  /// Đường dẫn "Khối A › Phòng B".
  String pathOf(String id) {
    final parts = <String>[];
    String? cur = id;
    var guard = 0;
    while (cur != null && byId.containsKey(cur) && guard++ < 50) {
      parts.insert(0, byId[cur]!.name);
      cur = byId[cur]!.parentId;
    }
    return parts.join(' › ');
  }
}

/// Mã phòng ban gợi ý từ tên: chữ cái đầu không dấu, không trùng mã đã có.
String suggestDeptCode(String name, Iterable<String> existing) {
  final plain = PosEscPosTextCodec.stripDiacritics(name).toUpperCase();
  final words = plain.split(RegExp(r'[^A-Z0-9]+')).where((w) => w.isNotEmpty).toList();
  var base = words.length == 1
      ? words.first.substring(0, words.first.length.clamp(0, 4))
      : words.map((w) => w[0]).join();
  if (base.isEmpty) base = 'PB';
  final taken = existing.map((e) => e.toUpperCase()).toSet();
  var code = base;
  for (var i = 2; taken.contains(code); i++) {
    code = '$base$i';
  }
  return code;
}

class DpAvatar extends StatelessWidget {
  const DpAvatar({super.key, required this.name, this.photo, this.size = 36});
  final String name;
  final String? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    final initials = t.isEmpty ? '?' : t.split(RegExp(r'\s+')).last.characters.first.toUpperCase();
    final hasPhoto = photo != null && photo!.isNotEmpty;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: SboxColors.brand50,
      foregroundImage: hasPhoto ? ApiService().storeImageProvider(photo!) : null,
      onForegroundImageError: hasPhoto ? (_, __) {} : null,
      child: Text(initials, style: TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w800, fontSize: size * 0.4)),
    );
  }
}

void dpToast(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(m)),
      backgroundColor: error ? SboxColors.danger : null,
      behavior: SnackBarBehavior.floating,
    ));

/// Chọn phòng ban (đích chuyển nhân viên / phòng cha). [exclude] = không cho chọn.
Future<String?> pickDepartment(
  BuildContext context,
  DeptTree tree, {
  required String title,
  Set<String> exclude = const {},
  String? noneLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      var q = '';
      return StatefulBuilder(builder: (ctx, set) {
        final rows = tree.flatten().where((r) => q.isEmpty || r.$1.name.toLowerCase().contains(q.toLowerCase())).toList();
        return AlertDialog(
          title: Text(tr(title)),
          content: SizedBox(
            width: 440,
            height: 420,
            child: Column(children: [
              TextField(
                autofocus: true,
                onChanged: (v) => set(() => q = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: tr('Tìm phòng ban'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(children: [
                  if (noneLabel != null)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.remove_circle_outline, color: SboxColors.slate400),
                      title: Text(tr(noneLabel)),
                      onTap: () => Navigator.pop(ctx, ''),
                    ),
                  for (final (d, depth) in rows)
                    ListTile(
                      dense: true,
                      enabled: !exclude.contains(d.id),
                      contentPadding: EdgeInsets.only(left: 12.0 + (q.isEmpty ? depth * 18 : 0), right: 8),
                      leading: Icon(depth == 0 ? Icons.account_tree_rounded : Icons.subdirectory_arrow_right_rounded,
                          size: 18, color: SboxColors.slate400),
                      title: Text(tr(d.name)),
                      trailing: Text('${d.directCount}', style: const TextStyle(color: SboxColors.slate400)),
                      onTap: () => Navigator.pop(ctx, d.id),
                    ),
                ]),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy')))],
        );
      });
    },
  );
}
