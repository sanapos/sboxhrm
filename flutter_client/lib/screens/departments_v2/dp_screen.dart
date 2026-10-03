import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/page_top_actions.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'dp_common.dart';
import 'dp_editor.dart';

/// Phòng ban: cây phòng ban (trái) + chi tiết, nhân viên, chuyển nhân viên (phải); sơ đồ tổ chức.
/// Điện thoại: cây phòng ban → bấm vào phòng mở trang chi tiết.
class DepartmentsV2Screen extends StatefulWidget {
  const DepartmentsV2Screen({super.key});

  @override
  State<DepartmentsV2Screen> createState() => _DepartmentsV2ScreenState();
}

/// Mục đặc biệt: nhân viên chưa có phòng ban.
const _kNone = 'none';

class _DepartmentsV2ScreenState extends State<DepartmentsV2Screen> {
  final _api = ApiService();
  DeptTree _tree = DeptTree(const []);
  int _totalEmployees = 0;
  int _unassigned = 0;
  bool _loading = true;
  String? _error;
  String? _selected;
  final Set<String> _collapsed = {};
  String _q = '';
  bool _chart = false;
  int _detailVersion = 0;

  bool _can(String a) {
    try {
      final p = Provider.of<PermissionProvider>(context, listen: false);
      return switch (a) {
        'create' => p.canCreate('Department'),
        'edit' => p.canEdit('Department'),
        'move' => p.canEdit('Department') || p.canEdit('Employee'),
        _ => p.canDelete('Department'),
      };
    } catch (_) {
      return true;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.getDepartmentOverview();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        final d = r['data'] as Map;
        _tree = DeptTree([for (final x in (d['items'] as List? ?? const []).whereType<Map>()) Dept(Map<String, dynamic>.from(x))]);
        _totalEmployees = (d['totalEmployees'] as num?)?.toInt() ?? 0;
        _unassigned = (d['unassigned'] as num?)?.toInt() ?? 0;
        _error = null;
        if (_selected == null || (_selected != _kNone && !_tree.byId.containsKey(_selected))) {
          _selected = _tree.roots.isNotEmpty ? _tree.roots.first.id : (_unassigned > 0 ? _kNone : null);
        }
        _detailVersion++;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được phòng ban';
      }
    });
  }

  Future<void> _add([String? parentId]) async {
    final ok = await openDeptEditor(context, _tree, parentId: parentId);
    if (ok == true) _load();
  }

  Future<void> _edit(Dept d) async {
    final ok = await openDeptEditor(context, _tree, dept: d);
    if (ok == true) _load();
  }

  /// Lên / xuống trong cùng cấp.
  Future<void> _shift(Dept d, int dir) async {
    final sibs = [..._tree.kids(d.parentId)];
    final i = sibs.indexWhere((x) => x.id == d.id);
    final j = i + dir;
    if (i < 0 || j < 0 || j >= sibs.length) return;
    sibs
      ..removeAt(i)
      ..insert(j, d);
    final r = await _api.reorderDepartments([
      for (var k = 0; k < sibs.length; k++) {'id': sibs[k].id, 'parentId': d.parentId, 'sortOrder': k},
    ]);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _load();
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không sắp xếp được', error: true);
    }
  }

  Future<void> _moveUnder(Dept d) async {
    final id = await pickDepartment(context, _tree,
        title: 'Chuyển "${d.name}" vào', exclude: _tree.descendantsOf(d.id), noneLabel: 'Cấp cao nhất');
    if (id == null) return;
    final parent = id.isEmpty ? null : id;
    if (parent == d.parentId) return;
    final r = await _api.reorderDepartments([
      {'id': d.id, 'parentId': parent, 'sortOrder': _tree.kids(parent).length},
    ]);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      dpToast(context, 'Đã chuyển ${d.name}');
      _load();
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không chuyển được', error: true);
    }
  }

  Future<void> _delete(Dept d) async {
    if (d.childCount > 0) {
      dpToast(context, 'Phòng ban còn ${d.childCount} phòng con. Chuyển hoặc xóa phòng con trước.', error: true);
      return;
    }
    String? target;
    if (d.directCount > 0) {
      final picked = await pickDepartment(context, _tree,
          title: 'Chuyển ${d.directCount} nhân viên của "${d.name}" sang', exclude: {d.id});
      if (picked == null || picked.isEmpty) return;
      target = picked;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded, color: SboxColors.danger),
        title: Text(tr('Xóa phòng ban "${d.name}"?')),
        content: Text(tr(target == null
            ? 'Phòng ban không còn nhân viên.'
            : '${d.directCount} nhân viên sẽ chuyển sang "${_tree.byId[target]?.name ?? ''}" trước khi xóa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa phòng ban')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.deleteDepartmentWithTransfer(d.id, target);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      dpToast(context, 'Đã xóa phòng ban ${d.name}');
      _selected = null;
      _load();
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không xóa được', error: true);
    }
  }

  void _open(String id, bool wide) {
    if (wide) {
      setState(() => _selected = id);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: HrmPageChrome.background,
        appBar: AppBar(title: Text(tr(id == _kNone ? 'Chưa có phòng ban' : (_tree.byId[id]?.name ?? '')))),
        body: _DeptDetail(
          key: ValueKey('m$id$_detailVersion'),
          id: id,
          tree: _tree,
          canEdit: _can('edit'),
          canMove: _can('move'),
          canDelete: _can('delete'),
          canCreate: _can('create'),
          onEdit: _edit,
          onAddChild: _add,
          onShift: _shift,
          onMoveUnder: _moveUnder,
          onDelete: _delete,
          onChanged: _load,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 980;
    final canCreate = _can('create');
    return RegisterPageTopActions(
      actions: [
        if (canCreate) HrmTopBarAction(icon: Icons.add, label: 'Thêm phòng ban', primary: true, showLabel: true, onPressed: () => _add()),
      ],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: _loading
            ? const SboxLoading(message: 'Đang tải phòng ban…')
            : _error != null
                ? SboxEmptyState(icon: Icons.cloud_off_rounded, title: 'Không tải được', message: _error)
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 14, wide ? 24 : 12, 10),
                      child: _summary(wide),
                    ),
                    Expanded(child: _chart ? _DeptOrgChart(tree: _tree, onTap: (id) => _open(id, false)) : _treeLayout(wide)),
                  ]),
      ),
    );
  }

  Widget _summary(bool wide) {
    final noManager = _tree.byId.values.where((d) => d.managerId == null && d.isActive).length;
    final toggle = SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: false, icon: const Icon(Icons.list_rounded, size: 18), label: Text(tr('Cây phòng ban'))),
        ButtonSegment(value: true, icon: const Icon(Icons.account_tree_rounded, size: 18), label: Text(tr('Sơ đồ'))),
      ],
      selected: {_chart},
      onSelectionChanged: (s) => setState(() => _chart = s.first),
    );
    Widget stat(String label, String value, IconData icon, SboxTone tone, {VoidCallback? onTap}) => SizedBox(
          width: wide ? 210 : 170,
          child: SboxMetricCard(label: label, value: value, icon: icon, tone: tone, onTap: onTap),
        );
    final stats = [
      stat('Phòng ban', '${_tree.byId.length}', Icons.apartment_rounded, SboxTone.brand),
      stat('Nhân viên', '$_totalEmployees', Icons.groups_rounded, SboxTone.success),
      stat('Chưa có phòng ban', '$_unassigned', Icons.person_search_rounded, _unassigned > 0 ? SboxTone.warning : SboxTone.neutral,
          onTap: _unassigned > 0 ? () => _open(_kNone, wide) : null),
      stat('Phòng chưa có quản lý', '$noManager', Icons.manage_accounts_outlined, noManager > 0 ? SboxTone.danger : SboxTone.neutral),
    ];
    if (wide) {
      return Row(children: [
        for (final s in stats) Padding(padding: const EdgeInsets.only(right: 12), child: s),
        const Spacer(),
        toggle,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: stats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => stats[i],
        ),
      ),
      const SizedBox(height: 10),
      toggle,
    ]);
  }

  Widget _treeLayout(bool wide) {
    final tree = _treeList(wide);
    if (!wide) return tree;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 380, child: Padding(padding: const EdgeInsets.fromLTRB(24, 0, 12, 16), child: tree)),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 24, 16),
          child: _selected == null
              ? const SboxEmptyState(icon: Icons.apartment_rounded, title: 'Chọn một phòng ban')
              : _DeptDetail(
                  key: ValueKey('d$_selected$_detailVersion'),
                  id: _selected!,
                  tree: _tree,
                  canEdit: _can('edit'),
                  canMove: _can('move'),
                  canDelete: _can('delete'),
                  canCreate: _can('create'),
                  onEdit: _edit,
                  onAddChild: _add,
                  onShift: _shift,
                  onMoveUnder: _moveUnder,
                  onDelete: _delete,
                  onChanged: _load,
                ),
        ),
      ),
    ]);
  }

  Widget _treeList(bool wide) {
    final q = _q.trim().toLowerCase();
    final rows = q.isEmpty
        ? _tree.flatten(collapsed: _collapsed)
        : _tree.flatten().where((r) => r.$1.name.toLowerCase().contains(q) || r.$1.code.toLowerCase().contains(q)).toList();
    // Khung thẻ tự dựng (SboxCard bọc Column co theo nội dung, không cho danh sách cuộn bên trong).
    final list = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SboxColors.surface,
        borderRadius: SboxRadius.lgAll,
        border: Border.all(color: SboxColors.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: tr('Tìm phòng ban'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: _tree.byId.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: SboxEmptyState(icon: Icons.apartment_rounded, title: 'Chưa có phòng ban', message: 'Bấm «Thêm phòng ban» để bắt đầu.'),
                )
              : ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 6), children: [
                  for (final (d, depth) in rows) _treeRow(d, q.isEmpty ? depth : 0, wide),
                  if (_unassigned > 0) ...[
                    const Divider(height: 12),
                    _noneRow(wide),
                  ],
                ]),
        ),
      ]),
    );
    if (wide) return Align(alignment: Alignment.topCenter, child: list);
    return Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 90), child: Align(alignment: Alignment.topCenter, child: list));
  }

  Widget _treeRow(Dept d, int depth, bool wide) {
    final sel = wide && _selected == d.id;
    final hasKids = _tree.kids(d.id).isNotEmpty;
    final collapsed = _collapsed.contains(d.id);
    return Material(
      color: sel ? SboxColors.brand50 : Colors.transparent,
      child: InkWell(
        onTap: () => _open(d.id, wide),
        child: Padding(
          padding: EdgeInsets.fromLTRB(6.0 + depth * 18, 6, 12, 6),
          child: Row(children: [
            SizedBox(
              width: 28,
              child: hasKids
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 20,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded, color: SboxColors.slate500),
                      onPressed: () => setState(() => collapsed ? _collapsed.remove(d.id) : _collapsed.add(d.id)),
                    )
                  : const Icon(Icons.circle, size: 6, color: SboxColors.slate300),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(d.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: depth == 0 ? FontWeight.w800 : FontWeight.w600,
                        color: d.isActive ? (sel ? SboxColors.brand700 : SboxColors.slate900) : SboxColors.slate400)),
                Text(
                  tr(d.managerName ?? 'Chưa có quản lý'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: d.managerName == null ? SboxColors.warningText : SboxColors.slate500),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: SboxColors.slate100, borderRadius: BorderRadius.circular(99)),
              child: Text(d.totalCount != d.directCount ? '${d.directCount}/${d.totalCount}' : '${d.directCount}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate600)),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _noneRow(bool wide) => Material(
        color: wide && _selected == _kNone ? SboxColors.warningSoft : Colors.transparent,
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.person_search_rounded, color: SboxColors.warningText),
          title: Text(tr('Chưa có phòng ban'), style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: Text('$_unassigned', style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.warningText)),
          onTap: () => _open(_kNone, wide),
        ),
      );
}

// ─── Chi tiết phòng ban ───────────────────────────────────────

class _DeptDetail extends StatefulWidget {
  const _DeptDetail({
    super.key,
    required this.id,
    required this.tree,
    required this.canEdit,
    required this.canMove,
    required this.canDelete,
    required this.canCreate,
    required this.onEdit,
    required this.onAddChild,
    required this.onShift,
    required this.onMoveUnder,
    required this.onDelete,
    required this.onChanged,
  });

  final String id;
  final DeptTree tree;
  final bool canEdit;
  final bool canMove;
  final bool canDelete;
  final bool canCreate;
  final ValueChanged<Dept> onEdit;
  final ValueChanged<String?> onAddChild;
  final Future<void> Function(Dept d, int dir) onShift;
  final ValueChanged<Dept> onMoveUnder;
  final ValueChanged<Dept> onDelete;
  final VoidCallback onChanged;

  @override
  State<_DeptDetail> createState() => _DeptDetailState();
}

class _DeptDetailState extends State<_DeptDetail> {
  final _api = ApiService();
  List<Map<String, dynamic>> _members = [];
  final Set<String> _sel = {};
  bool _loading = true;
  bool _withChildren = false;
  String _q = '';

  bool get _isNone => widget.id == _kNone;
  Dept? get _d => widget.tree.byId[widget.id];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.getDepartmentMembers(widget.id, includeChildren: _withChildren);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _members = [if (r['data'] is List) for (final x in (r['data'] as List).whereType<Map>()) Map<String, dynamic>.from(x)];
      _sel.removeWhere((id) => !_members.any((m) => '${m['id']}' == id));
    });
  }

  Future<void> _moveSelected() async {
    final target = await pickDepartment(context, widget.tree,
        title: 'Chuyển ${_sel.length} nhân viên sang', exclude: _isNone ? {} : {widget.id}, noneLabel: _isNone ? null : 'Bỏ khỏi phòng ban');
    if (target == null) return;
    final r = await _api.moveEmployeesToDepartment(_sel.toList(), target.isEmpty ? null : target);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      dpToast(context, 'Đã chuyển ${_sel.length} nhân viên');
      _sel.clear();
      widget.onChanged();
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không chuyển được', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final q = _q.trim().toLowerCase();
    final shown = _members
        .where((m) => q.isEmpty || '${m['name']} ${m['employeeCode']} ${m['position']}'.toLowerCase().contains(q))
        .toList();
    return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
      if (d != null) _header(d) else _noneHeader(),
      const SizedBox(height: 12),
      SboxCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text(tr('Nhân viên (${_members.length})'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            if (d != null && d.childCount > 0)
              FilterChip(
                label: Text(tr('Gồm phòng con')),
                selected: _withChildren,
                onSelected: (v) {
                  _withChildren = v;
                  _load();
                },
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: tr('Tìm nhân viên'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            if (widget.canMove && _sel.isNotEmpty) ...[
              const SizedBox(width: 8),
              SboxButton(label: 'Chuyển ${_sel.length} NV', icon: Icons.drive_file_move_outline, onPressed: _moveSelected),
            ],
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(tr(_members.isEmpty ? 'Chưa có nhân viên' : 'Không có nhân viên phù hợp'),
                  textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
            )
          else ...[
            if (widget.canMove)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                tristate: true,
                value: _sel.isEmpty ? false : (_sel.length >= shown.length ? true : null),
                onChanged: (_) => setState(() {
                  if (_sel.length >= shown.length) {
                    _sel.clear();
                  } else {
                    _sel.addAll(shown.map((m) => '${m['id']}'));
                  }
                }),
                title: Text(tr('Chọn tất cả'), style: const TextStyle(fontSize: 13)),
              ),
            for (final m in shown) _memberRow(m),
          ],
        ]),
      ),
    ]);
  }

  Widget _memberRow(Map<String, dynamic> m) {
    final id = '${m['id']}';
    final sub = [m['employeeCode'], m['position'], if (_withChildren) m['departmentName'], m['branchName']]
        .whereType<Object>()
        .map((x) => '$x')
        .where((x) => x.isNotEmpty)
        .join(' · ');
    return InkWell(
      onTap: widget.canMove ? () => setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          if (widget.canMove)
            Checkbox(value: _sel.contains(id), onChanged: (v) => setState(() => v == true ? _sel.add(id) : _sel.remove(id))),
          DpAvatar(name: '${m['name'] ?? ''}', photo: m['photoUrl']?.toString()),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('${m['name'] ?? ''}'), style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(tr(sub), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ]),
          ),
          if (m['probation'] == true) const SboxStatusChip(label: 'Thử việc', tone: SboxTone.violet),
          if (m['onLeave'] == true) const SboxStatusChip(label: 'Tạm nghỉ', tone: SboxTone.warning),
          if ('${widget.tree.byId[widget.id]?.managerName}' == '${m['name']}')
            const Padding(padding: EdgeInsets.only(left: 6), child: SboxStatusChip(label: 'Quản lý', tone: SboxTone.brand)),
        ]),
      ),
    );
  }

  Widget _noneHeader() => SboxCard(
        child: Row(children: [
          const Icon(Icons.person_search_rounded, color: SboxColors.warningText, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Nhân viên chưa có phòng ban'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(tr('Chọn nhân viên rồi bấm «Chuyển» để xếp vào phòng ban.'), style: const TextStyle(color: SboxColors.slate500)),
            ]),
          ),
        ]),
      );

  Widget _header(Dept d) {
    final tree = widget.tree;
    final sibs = tree.kids(d.parentId);
    final idx = sibs.indexWhere((x) => x.id == d.id);
    Widget stat(String label, String value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(tr(label), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          ]),
        );
    return SboxCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (d.parentId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(tr(tree.pathOf(d.parentId!)), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          ),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
              Text(tr(d.name), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              SboxStatusChip(label: d.code),
              if (!d.isActive) const SboxStatusChip(label: 'Ngừng hoạt động', tone: SboxTone.danger, dot: true),
            ]),
          ),
          if (widget.canEdit)
            IconButton(tooltip: tr('Sửa'), icon: const Icon(Icons.edit_outlined), onPressed: () => widget.onEdit(d)),
          if (widget.canEdit || widget.canDelete || widget.canCreate)
            PopupMenuButton<String>(
              tooltip: tr('Thao tác'),
              onSelected: (v) => switch (v) {
                'child' => widget.onAddChild(d.id),
                'up' => widget.onShift(d, -1),
                'down' => widget.onShift(d, 1),
                'move' => widget.onMoveUnder(d),
                _ => widget.onDelete(d),
              },
              itemBuilder: (_) => [
                if (widget.canCreate) PopupMenuItem(value: 'child', child: Text(tr('Thêm phòng con'))),
                if (widget.canEdit && idx > 0) PopupMenuItem(value: 'up', child: Text(tr('Đưa lên trên'))),
                if (widget.canEdit && idx >= 0 && idx < sibs.length - 1) PopupMenuItem(value: 'down', child: Text(tr('Đưa xuống dưới'))),
                if (widget.canEdit) PopupMenuItem(value: 'move', child: Text(tr('Chuyển vào phòng ban khác…'))),
                if (widget.canDelete)
                  PopupMenuItem(value: 'delete', child: Text(tr('Xóa phòng ban'), style: const TextStyle(color: SboxColors.danger))),
              ],
            ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          DpAvatar(name: d.managerName ?? '?', photo: d.managerPhoto, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(d.managerName ?? 'Chưa có người quản lý'),
                  style: TextStyle(fontWeight: FontWeight.w700, color: d.managerName == null ? SboxColors.warningText : null)),
              Text(tr(d.managerPosition ?? 'Trưởng phòng / quản lý'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ]),
          ),
        ]),
        const Divider(height: 24),
        Row(children: [
          stat('Nhân viên trực tiếp', '${d.directCount}'),
          stat('Gồm phòng con', '${d.totalCount}'),
          stat('Phòng con', '${d.childCount}'),
        ]),
        if (d.positions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in d.positions) SboxStatusChip(label: p, icon: Icons.badge_outlined),
          ]),
        ],
        if ((d.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(tr(d.description!), style: const TextStyle(color: SboxColors.slate600)),
        ],
        if (tree.kids(d.id).isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Phòng con'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in tree.kids(d.id)) SboxStatusChip(label: '${c.name} · ${c.totalCount}', icon: Icons.subdirectory_arrow_right_rounded),
          ]),
        ],
      ]),
    );
  }
}

// ─── Sơ đồ tổ chức ───────────────────────────────────────────

class _DeptOrgChart extends StatelessWidget {
  const _DeptOrgChart({required this.tree, required this.onTap});
  final DeptTree tree;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (tree.roots.isEmpty) return const SboxEmptyState(icon: Icons.account_tree_rounded, title: 'Chưa có phòng ban');
    return InteractiveViewer(
      constrained: false,
      minScale: 0.3,
      maxScale: 2,
      boundaryMargin: const EdgeInsets.all(400),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final r in tree.roots) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _node(r)),
        ]),
      ),
    );
  }

  Widget _node(Dept d) {
    final kids = tree.kids(d.id);
    const line = SboxColors.slate300;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _box(d),
      if (kids.isNotEmpty) ...[
        Container(width: 2, height: 18, color: line),
        Row(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < kids.length; i++)
                IntrinsicWidth(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Đường ngang nối các phòng con: nửa trái / nửa phải tùy vị trí.
                  SizedBox(
                    height: 18,
                    child: Row(children: [
                      Expanded(child: Container(height: 2, color: i == 0 ? Colors.transparent : line)),
                      Container(width: 2, height: 18, color: line),
                      Expanded(child: Container(height: 2, color: i == kids.length - 1 ? Colors.transparent : line)),
                    ]),
                  ),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _node(kids[i])),
                ])),
        ]),
      ],
    ]);
  }

  Widget _box(Dept d) => InkWell(
        onTap: () => onTap(d.id),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 200,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: d.isActive ? SboxColors.brand200 : SboxColors.slate200),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(d.name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, color: d.isActive ? SboxColors.slate900 : SboxColors.slate400)),
            const SizedBox(height: 8),
            Row(children: [
              DpAvatar(name: d.managerName ?? '?', photo: d.managerPhoto, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr(d.managerName ?? 'Chưa có quản lý'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: d.managerName == null ? SboxColors.warningText : SboxColors.slate600)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(tr('${d.directCount} NV${d.totalCount != d.directCount ? ' · ${d.totalCount} gồm phòng con' : ''}'),
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
          ]),
        ),
      );
}
