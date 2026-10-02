import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'dp_common.dart';

/// Mở form thêm / sửa phòng ban. Trả true nếu đã lưu.
Future<bool?> openDeptEditor(BuildContext context, DeptTree tree, {Dept? dept, String? parentId}) {
  final wide = MediaQuery.of(context).size.width >= 700;
  final page = DeptEditor(tree: tree, dept: dept, initialParentId: parentId);
  if (wide) {
    return showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760), child: page),
      ),
    );
  }
  return Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => page));
}

class DeptEditor extends StatefulWidget {
  const DeptEditor({super.key, required this.tree, this.dept, this.initialParentId});

  final DeptTree tree;
  final Dept? dept;
  final String? initialParentId;

  @override
  State<DeptEditor> createState() => _DeptEditorState();
}

class _DeptEditorState extends State<DeptEditor> {
  final _api = ApiService();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _desc;
  final _position = TextEditingController();
  late String? _parentId;
  String? _managerId;
  String? _managerName;
  String? _managerPhoto;
  late List<String> _positions;
  late bool _active;
  bool _codeTouched = false;
  bool _saving = false;

  bool get _isNew => widget.dept == null;

  @override
  void initState() {
    super.initState();
    final d = widget.dept;
    _name = TextEditingController(text: d?.name ?? '');
    _code = TextEditingController(text: d?.code ?? '');
    _desc = TextEditingController(text: d?.description ?? '');
    _parentId = d?.parentId ?? widget.initialParentId;
    _managerId = d?.managerId;
    _managerName = d?.managerName;
    _managerPhoto = d?.managerPhoto;
    _positions = [...?d?.positions];
    _active = d?.isActive ?? true;
    _codeTouched = !_isNew;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _desc.dispose();
    _position.dispose();
    super.dispose();
  }

  Iterable<String> get _otherCodes => widget.tree.byId.values.where((x) => x.id != widget.dept?.id).map((x) => x.code);

  void _onName(String v) {
    if (!_codeTouched) _code.text = v.trim().isEmpty ? '' : suggestDeptCode(v, _otherCodes);
    setState(() {});
  }

  Future<void> _pickParent() async {
    final exclude = widget.dept == null ? <String>{} : widget.tree.descendantsOf(widget.dept!.id);
    final id = await pickDepartment(context, widget.tree,
        title: 'Chọn phòng ban cha', exclude: exclude, noneLabel: 'Không có (phòng ban cấp cao nhất)');
    if (id == null) return;
    setState(() => _parentId = id.isEmpty ? null : id);
  }

  Future<void> _pickManager() async {
    final r = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _ManagerPicker());
    if (r == null) return;
    setState(() {
      if (r.isEmpty) {
        _managerId = null;
        _managerName = null;
        _managerPhoto = null;
      } else {
        _managerId = '${r['id']}';
        _managerName = r['name']?.toString();
        _managerPhoto = r['photoUrl']?.toString();
      }
    });
  }

  void _addPosition() {
    final v = _position.text.trim();
    if (v.isEmpty || _positions.any((p) => p.toLowerCase() == v.toLowerCase())) return;
    setState(() {
      _positions.add(v);
      _position.clear();
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    var code = _code.text.trim();
    if (name.isEmpty) {
      dpToast(context, 'Nhập tên phòng ban', error: true);
      return;
    }
    if (code.isEmpty) code = suggestDeptCode(name, _otherCodes);
    if (_otherCodes.any((c) => c.toUpperCase() == code.toUpperCase())) {
      dpToast(context, 'Mã "$code" đã dùng cho phòng ban khác', error: true);
      return;
    }
    _addPosition();
    setState(() => _saving = true);
    final siblings = widget.tree.kids(_parentId);
    final order = widget.dept?.parentId == _parentId && widget.dept != null
        ? widget.dept!.sortOrder
        : (siblings.isEmpty ? 0 : siblings.map((s) => s.sortOrder).reduce((a, b) => a > b ? a : b) + 1);
    final r = _isNew
        ? await _api.createDepartment(
            code: code,
            name: name,
            description: _desc.text.trim(),
            parentDepartmentId: _parentId,
            managerId: _managerId,
            sortOrder: order,
            positions: _positions,
          )
        : await _api.updateDepartment(
            departmentId: widget.dept!.id,
            code: code,
            name: name,
            description: _desc.text.trim(),
            parentDepartmentId: _parentId,
            managerId: _managerId,
            sortOrder: order,
            isActive: _active,
            positions: _positions,
          );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      dpToast(context, _isNew ? 'Đã tạo phòng ban $name' : 'Đã lưu phòng ban $name');
      Navigator.of(context).pop(true);
    } else {
      dpToast(context, r['message']?.toString() ?? 'Không lưu được', error: true);
    }
  }

  InputDecoration _dec(String label, {String? hint, String? helper}) => InputDecoration(
        labelText: tr(label),
        hintText: hint == null ? null : tr(hint),
        helperText: helper == null ? null : tr(helper),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _picker(String label, String value, IconData icon, VoidCallback onTap, {Widget? leading, VoidCallback? onClear}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: _dec(label).copyWith(
            suffixIcon: onClear != null
                ? IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: onClear)
                : const Icon(Icons.expand_more_rounded),
          ),
          child: Row(children: [
            leading ?? Icon(icon, size: 18, color: SboxColors.slate500),
            const SizedBox(width: 8),
            Expanded(child: Text(tr(value), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tree = widget.tree;
    final body = ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), children: [
      Row(children: [
        Expanded(flex: 3, child: TextField(controller: _name, autofocus: _isNew, onChanged: _onName, decoration: _dec('Tên phòng ban *', hint: 'VD: Phòng Kinh doanh'))),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: TextField(
            controller: _code,
            onChanged: (_) => _codeTouched = true,
            textCapitalization: TextCapitalization.characters,
            decoration: _dec('Mã', helper: _isNew ? 'Tự gợi ý theo tên' : null),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      _picker(
        'Thuộc phòng ban',
        _parentId == null ? 'Cấp cao nhất' : tree.pathOf(_parentId!),
        Icons.account_tree_outlined,
        _pickParent,
      ),
      const SizedBox(height: 14),
      _picker(
        'Trưởng phòng / quản lý',
        _managerName ?? 'Chưa phân công',
        Icons.person_outline_rounded,
        _pickManager,
        leading: _managerName == null ? null : DpAvatar(name: _managerName!, photo: _managerPhoto, size: 24),
        onClear: _managerId == null ? null : () => setState(() {
              _managerId = null;
              _managerName = null;
              _managerPhoto = null;
            }),
      ),
      const SizedBox(height: 16),
      Text(tr('Chức vụ trong phòng'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in _positions)
          InputChip(label: Text(tr(p)), onDeleted: () => setState(() => _positions.remove(p))),
      ]),
      const SizedBox(height: 6),
      TextField(
        controller: _position,
        onSubmitted: (_) => _addPosition(),
        decoration: _dec('Thêm chức vụ', hint: 'VD: Trưởng nhóm, Nhân viên').copyWith(
          suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: _addPosition),
        ),
      ),
      const SizedBox(height: 14),
      TextField(controller: _desc, maxLines: 2, decoration: _dec('Mô tả / nhiệm vụ')),
      if (!_isNew)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _active,
          onChanged: (v) => setState(() => _active = v),
          title: Text(tr(_active ? 'Đang hoạt động' : 'Ngừng hoạt động'), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(tr('Phòng ngừng hoạt động vẫn giữ nhân viên và lịch sử')),
        ),
    ]);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(tr(_isNew ? 'Thêm phòng ban' : 'Sửa phòng ban')),
        actions: [IconButton(onPressed: () => Navigator.pop(context, false), icon: const Icon(Icons.close_rounded))],
      ),
      body: body,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SboxButton(label: 'Lưu phòng ban', icon: Icons.check_rounded, expand: true, loading: _saving, onPressed: _saving ? null : _save),
        ),
      ),
    );
  }
}

/// Tìm và chọn người quản lý. Trả {} = bỏ người quản lý.
class _ManagerPicker extends StatefulWidget {
  const _ManagerPicker();

  @override
  State<_ManagerPicker> createState() => _ManagerPickerState();
}

class _ManagerPickerState extends State<_ManagerPicker> {
  final _api = ApiService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final r = await _api.searchEmployeesForDepartment(q);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _rows = [if (r['data'] is List) for (final x in (r['data'] as List).whereType<Map>()) Map<String, dynamic>.from(x)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Chọn người quản lý')),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
            },
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: tr('Tên hoặc mã nhân viên'),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.person_off_outlined),
                title: Text(tr('Chưa phân công')),
                onTap: () => Navigator.pop(context, <String, dynamic>{}),
              ),
              for (final e in _rows)
                ListTile(
                  dense: true,
                  leading: DpAvatar(name: '${e['name'] ?? ''}', photo: e['photoUrl']?.toString(), size: 32),
                  title: Text(tr('${e['name'] ?? ''}')),
                  subtitle: Text(tr([e['employeeCode'], e['position'], e['department']]
                      .whereType<Object>()
                      .map((x) => '$x')
                      .where((x) => x.isNotEmpty)
                      .join(' · '))),
                  onTap: () => Navigator.pop(context, e),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy')))],
    );
  }
}
