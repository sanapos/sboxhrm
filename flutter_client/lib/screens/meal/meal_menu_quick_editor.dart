import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../models/meal.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import 'meal_ui.dart';

/// Căn tin nhập thực đơn 1 buổi của 1 ngày: chạm món có sẵn để thêm, gõ món mới,
/// chép thực đơn hôm qua / tuần trước. Đã có thực đơn thì sửa, chưa có thì tạo.
/// Trả về true khi đã lưu.
Future<bool> showMealMenuQuickEditor(
  BuildContext context, {
  required DateTime date,
  required String sessionId,
  required String sessionName,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 760),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _MealMenuQuickEditor(date: date, sessionId: sessionId, sessionName: sessionName),
    ),
  );
  return saved == true;
}

class _Dish {
  _Dish(this.name, this.category);
  String name;
  String? category;
}

class _MealMenuQuickEditor extends StatefulWidget {
  const _MealMenuQuickEditor({required this.date, required this.sessionId, required this.sessionName});
  final DateTime date;
  final String sessionId;
  final String sessionName;

  @override
  State<_MealMenuQuickEditor> createState() => _MealMenuQuickEditorState();
}

class _MealMenuQuickEditorState extends State<_MealMenuQuickEditor> {
  final _api = ApiService();
  final _nameCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  final _searchCtl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _menuId;
  final List<_Dish> _items = [];
  List<MealDish> _master = [];
  String? _category;

  static final _df = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _noteCtl.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  Future<MealMenu?> _menuOf(DateTime d) async {
    final res = await _api.getMealMenu(date: _df.format(d), mealSessionId: widget.sessionId);
    if (res['isSuccess'] != true) return null;
    final list = (res['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(MealMenu.fromJson)
        .where((m) => m.mealSessionId == widget.sessionId)
        .toList();
    return list.isEmpty ? null : list.first;
  }

  Future<void> _load() async {
    final results = await Future.wait([_menuOf(widget.date), _api.getMealDishes()]);
    if (!mounted) return;
    final menu = results[0] as MealMenu?;
    final dishesRes = results[1] as Map<String, dynamic>;
    setState(() {
      _menuId = menu?.id;
      _noteCtl.text = menu?.note ?? '';
      _items
        ..clear()
        ..addAll([for (final i in menu?.items ?? const <MealMenuItem>[]) _Dish(i.dishName, i.category)]);
      if (dishesRes['isSuccess'] == true) {
        _master = (dishesRes['data'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MealDish.fromJson)
            .toList();
      }
      _loading = false;
    });
  }

  Future<void> _copyFrom(int daysBack, String label) async {
    final m = await _menuOf(widget.date.subtract(Duration(days: daysBack)));
    if (!mounted) return;
    if (m == null || m.items.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Chép thực đơn', message: 'Không có thực đơn $label');
      return;
    }
    setState(() {
      for (final i in m.items) {
        if (!_items.any((x) => x.name.toLowerCase() == i.dishName.toLowerCase())) {
          _items.add(_Dish(i.dishName, i.category));
        }
      }
    });
  }

  void _add(String name, String? category) {
    final n = name.trim();
    if (n.isEmpty) return;
    if (_items.any((x) => x.name.toLowerCase() == n.toLowerCase())) return;
    setState(() => _items.add(_Dish(n, category)));
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thực đơn', message: 'Chưa có món nào');
      return;
    }
    setState(() => _saving = true);
    final items = [
      for (var i = 0; i < _items.length; i++)
        {'dishName': _items[i].name, 'category': _items[i].category, 'sortOrder': i},
    ];
    final note = _noteCtl.text.trim().isEmpty ? null : _noteCtl.text.trim();
    final res = _menuId == null
        ? await _api.createMealMenu({
            'date': _df.format(widget.date),
            'mealSessionId': widget.sessionId,
            'note': note,
            'items': items,
          })
        : await _api.updateMealMenu(_menuId!, {'note': note, 'items': items});
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Thực đơn', message: 'Đã lưu thực đơn ${widget.sessionName}');
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
          title: 'Thực đơn', message: res['message']?.toString() ?? 'Không lưu được thực đơn');
    }
  }

  List<String> get _categories {
    final set = <String>{};
    for (final d in _master) {
      if ((d.category ?? '').isNotEmpty) set.add(d.category!);
    }
    return set.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = MealUi.dateLong(widget.date);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.restaurant_menu_rounded, color: SboxColors.brand600),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('Thực đơn ${widget.sessionName}'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    Text(dateLabel, style: const TextStyle(color: SboxColors.slate500)),
                  ]),
                ),
                PopupMenuButton<int>(
                  tooltip: tr('Chép thực đơn'),
                  icon: const Icon(Icons.content_copy_rounded),
                  onSelected: (v) => v == 1 ? _copyFrom(1, 'hôm qua') : _copyFrom(7, 'tuần trước'),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 1, child: Text(tr('Chép từ hôm qua'))),
                    PopupMenuItem(value: 7, child: Text(tr('Chép từ cùng ngày tuần trước'))),
                  ],
                ),
              ]),
              const SizedBox(height: 14),
              Expanded(
                child: ListView(children: [
                  _sectionTitle('Món trong thực đơn (${_items.length})', 'Kéo để sắp xếp · chạm × để bỏ'),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: SboxColors.slate50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: SboxColors.slate200),
                      ),
                      child: Text(tr('Chưa có món — chạm món bên dưới hoặc gõ tên món mới'),
                          textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
                    )
                  else
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorderItem: (a, b) => setState(() => _items.insert(b, _items.removeAt(a))),
                      children: [
                        for (var i = 0; i < _items.length; i++)
                          Container(
                            key: ValueKey('${_items[i].name}-$i'),
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: SboxColors.slate200),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: ReorderableDragStartListener(
                                index: i,
                                child: const Icon(Icons.drag_indicator_rounded, color: SboxColors.slate400),
                              ),
                              title: Text(_items[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: (_items[i].category ?? '').isEmpty ? null : Text(_items[i].category!),
                              trailing: IconButton(
                                icon: const Icon(Icons.close_rounded, color: SboxColors.slate500),
                                onPressed: () => setState(() => _items.removeAt(i)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  _sectionTitle('Thêm món mới', null),
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _nameCtl,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          hintText: tr('Tên món, VD: Cá kho tộ'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (v) {
                          _add(v, _category);
                          _nameCtl.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_categories.isNotEmpty)
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String?>(
                          initialValue: _category,
                          isDense: true,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: tr('Nhóm'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(value: null, child: Text(tr('Không'))),
                            for (final c in _categories) DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) => setState(() => _category = v),
                        ),
                      ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        _add(_nameCtl.text, _category);
                        _nameCtl.clear();
                      },
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ]),
                  if (_master.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _sectionTitle('Món có sẵn', 'Chạm để thêm'),
                    TextField(
                      controller: _searchCtl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: tr('Tìm món'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._masterGroups(),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _noteCtl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: tr('Ghi chú (VD: Có món chay, tráng miệng chuối)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16, top: 8),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(tr(_menuId == null ? 'Lưu thực đơn' : 'Cập nhật thực đơn')),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ]),
    );
  }

  Widget _sectionTitle(String title, String? hint) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate800)),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Text(tr(hint), style: const TextStyle(fontSize: 12, color: SboxColors.slate400)),
          ],
        ]),
      );

  List<Widget> _masterGroups() {
    final k = _searchCtl.text.trim().toLowerCase();
    final chosen = _items.map((e) => e.name.toLowerCase()).toSet();
    final groups = <String, List<MealDish>>{};
    for (final d in _master) {
      if (k.isNotEmpty && !d.name.toLowerCase().contains(k)) continue;
      groups.putIfAbsent((d.category ?? '').isEmpty ? 'Khác' : d.category!, () => []).add(d);
    }
    return [
      for (final e in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(e.key, style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
        ),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in e.value)
            FilterChip(
              label: Text(d.name),
              selected: chosen.contains(d.name.toLowerCase()),
              onSelected: (sel) => sel
                  ? _add(d.name, d.category)
                  : setState(() => _items.removeWhere((x) => x.name.toLowerCase() == d.name.toLowerCase())),
            ),
        ]),
      ],
    ];
  }
}
