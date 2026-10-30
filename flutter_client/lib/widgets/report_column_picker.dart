import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';

/// Một cột (hoặc nhóm cột lặp như «Lần 1, Lần 2…») của bảng báo cáo có thể ẩn / sắp xếp.
class ReportColumnDef {
  const ReportColumnDef(this.key, this.label, {this.locked = false, this.defaultVisible = true, this.hint});

  final String key;
  final String label;

  /// Luôn hiện (vd. STT, Ngày) — vẫn kéo đổi chỗ được.
  final bool locked;
  final bool defaultVisible;

  /// Ghi chú nhỏ cạnh tên (vd. «Lần 1, Lần 2…»).
  final String? hint;
}

/// Thứ tự + cột ẩn của một bảng. Khóa lạ (bản cũ) bị bỏ, cột mới thêm vào cuối theo mặc định.
class ReportColumnLayout {
  ReportColumnLayout(this.order, this.hidden);

  final List<String> order;
  final Set<String> hidden;

  factory ReportColumnLayout.defaults(List<ReportColumnDef> defs) => ReportColumnLayout(
        [for (final d in defs) d.key],
        {for (final d in defs) if (!d.defaultVisible && !d.locked) d.key},
      );

  ReportColumnLayout normalized(List<ReportColumnDef> defs) {
    final known = {for (final d in defs) d.key: d};
    final o = [for (final k in order) if (known.containsKey(k)) k];
    final h = {for (final k in hidden) if (known.containsKey(k) && !known[k]!.locked) k};
    for (final d in defs) {
      if (o.contains(d.key)) continue;
      o.add(d.key);
      if (!d.defaultVisible && !d.locked) h.add(d.key);
    }
    return ReportColumnLayout(o, h);
  }

  /// Khóa cột đang hiện, đúng thứ tự.
  List<String> get visibleOrder => [for (final k in order) if (!hidden.contains(k)) k];

  Map<String, dynamic> toJson() => {'order': order, 'hidden': hidden.toList()};

  static ReportColumnLayout? fromJson(Object? json) {
    if (json is! Map) return null;
    final o = json['order'];
    final h = json['hidden'];
    if (o is! List) return null;
    return ReportColumnLayout(
      [for (final x in o) x.toString()],
      {if (h is List) for (final x in h) x.toString()},
    );
  }
}

/// Lưu lựa chọn cột theo từng màn (máy này).
class ReportColumnPrefs {
  static Future<ReportColumnLayout> load(String prefKey, List<ReportColumnDef> defs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefKey);
      if (raw != null) {
        final parsed = ReportColumnLayout.fromJson(jsonDecode(raw));
        if (parsed != null) return parsed.normalized(defs);
      }
    } catch (_) {}
    return ReportColumnLayout.defaults(defs);
  }

  static Future<void> save(String prefKey, ReportColumnLayout layout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, jsonEncode(layout.toJson()));
    } catch (_) {}
  }
}

/// Sắp lại các ô của một dòng theo [visibleOrder]. [cellKeys] là khóa cột của từng ô theo thứ tự gốc
/// (nhóm lặp dùng chung một khóa, vd. mọi ô «Lần i» là `punch`) — ô cùng nhóm giữ thứ tự với nhau.
List<T> projectReportColumns<T>(List<T> cells, List<String> cellKeys, List<String> visibleOrder) {
  assert(cells.length == cellKeys.length, 'cells/cellKeys lệch: ${cells.length} vs ${cellKeys.length}');
  final out = <T>[];
  for (final key in visibleOrder) {
    for (var i = 0; i < cellKeys.length && i < cells.length; i++) {
      if (cellKeys[i] == key) out.add(cells[i]);
    }
  }
  return out;
}

/// Kết quả hộp chọn cột.
class ReportColumnPickResult {
  const ReportColumnPickResult(this.layout, {this.remember = true});
  final ReportColumnLayout layout;
  final bool remember;
}

/// Hộp chọn cột: tích để hiện, kéo ⋮⋮ để đổi thứ tự. [showRemember] = thêm ô «Nhớ lựa chọn cho lần sau»
/// (dùng khi xuất Excel). Trả null nếu hủy.
Future<ReportColumnPickResult?> showReportColumnPicker(
  BuildContext context, {
  required String title,
  required List<ReportColumnDef> defs,
  required ReportColumnLayout initial,
  String confirmLabel = 'Áp dụng',
  bool showRemember = false,
}) {
  return showDialog<ReportColumnPickResult>(
    context: context,
    builder: (ctx) => _ReportColumnPickerDialog(
      title: title,
      defs: defs,
      initial: initial.normalized(defs),
      confirmLabel: confirmLabel,
      showRemember: showRemember,
    ),
  );
}

class _ReportColumnPickerDialog extends StatefulWidget {
  const _ReportColumnPickerDialog({
    required this.title,
    required this.defs,
    required this.initial,
    required this.confirmLabel,
    required this.showRemember,
  });

  final String title;
  final List<ReportColumnDef> defs;
  final ReportColumnLayout initial;
  final String confirmLabel;
  final bool showRemember;

  @override
  State<_ReportColumnPickerDialog> createState() => _ReportColumnPickerDialogState();
}

class _ReportColumnPickerDialogState extends State<_ReportColumnPickerDialog> {
  late List<String> _order = [...widget.initial.order];
  late Set<String> _hidden = {...widget.initial.hidden};
  bool _remember = true;

  Map<String, ReportColumnDef> get _byKey => {for (final d in widget.defs) d.key: d};

  @override
  Widget build(BuildContext context) {
    final byKey = _byKey;
    final visibleCount = _order.where((k) => !_hidden.contains(k)).length;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(widget.title), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            tr('Tích để hiện, kéo ⋮⋮ để đổi thứ tự · đang chọn $visibleCount cột'),
            style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: (_order.length * 52.0).clamp(200, 520),
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: _order.length,
          onReorder: (oldIndex, newIndex) => setState(() {
            if (newIndex > oldIndex) newIndex--;
            _order.insert(newIndex, _order.removeAt(oldIndex));
          }),
          itemBuilder: (context, i) {
            final key = _order[i];
            final def = byKey[key]!;
            final shown = def.locked || !_hidden.contains(key);
            return Material(
              key: ValueKey(key),
              color: Colors.transparent,
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 4, right: 8),
                leading: ReorderableDragStartListener(
                  index: i,
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.drag_indicator, color: SboxColors.slate400),
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Flexible(child: Text(tr(def.label), style: const TextStyle(fontSize: 14))),
                    if (def.hint != null) ...[
                      const SizedBox(width: 6),
                      Text(tr(def.hint!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                    ],
                  ],
                ),
                trailing: def.locked
                    ? Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(tr('luôn có'), style: const TextStyle(fontSize: 12, color: SboxColors.slate400)),
                      )
                    : Checkbox(
                        value: shown,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _hidden.remove(key);
                          } else {
                            _hidden.add(key);
                          }
                        }),
                      ),
                onTap: def.locked
                    ? null
                    : () => setState(() => shown ? _hidden.add(key) : _hidden.remove(key)),
              ),
            );
          },
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(12, 8, 16, 14),
      actions: [
        if (widget.showRemember)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(value: _remember, onChanged: (v) => setState(() => _remember = v ?? true)),
              Text(tr('Nhớ lựa chọn cho lần sau'), style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 8),
            ],
          ),
        TextButton(
          onPressed: () => setState(() {
            final d = ReportColumnLayout.defaults(widget.defs);
            _order = d.order;
            _hidden = d.hidden;
          }),
          child: Text(tr('Mặc định')),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ReportColumnPickResult(ReportColumnLayout([..._order], {..._hidden}), remember: _remember),
          ),
          child: Text(tr(widget.confirmLabel)),
        ),
      ],
    );
  }
}
