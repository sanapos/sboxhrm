import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/permission_role_options.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'ac_common.dart';
import 'ac_editor.dart';

/// Tạo tài khoản hàng loạt từ hồ sơ nhân viên chưa có tài khoản. Trả về true khi có tài khoản được tạo.
Future<bool> showBulkAccounts(
  BuildContext context, {
  required List<AcEmployee> employees,
  required RolePolicy policy,
  required List<PermissionRoleOption> roleOptions,
  ApiService? api,
}) async {
  final narrow = MediaQuery.of(context).size.width < 640;
  final body = _BulkAccounts(employees: employees, policy: policy, roleOptions: roleOptions, api: api ?? ApiService());
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => narrow
        ? Dialog.fullscreen(child: body)
        : Dialog(
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640, maxHeight: 820), child: body),
          ),
  );
  return r == true;
}

class _BulkAccounts extends StatefulWidget {
  const _BulkAccounts({required this.employees, required this.policy, required this.roleOptions, required this.api});
  final List<AcEmployee> employees;
  final RolePolicy policy;
  final List<PermissionRoleOption> roleOptions;
  final ApiService api;

  @override
  State<_BulkAccounts> createState() => _BulkAccountsState();
}

class _BulkAccountsState extends State<_BulkAccounts> {
  final _pass = TextEditingController(text: randomPassword(8));
  final Set<String> _picked = {};
  String _q = '';
  late String _role = widget.policy.canAssign('Employee')
      ? 'Employee'
      : (widget.policy.assignable.isNotEmpty ? widget.policy.assignable.last : 'Employee');
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _result;

  List<AcEmployee> get _shown {
    final q = _q.trim().toLowerCase();
    return q.isEmpty ? widget.employees : widget.employees.where((e) => e.label.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_picked.isEmpty) return setState(() => _error = 'Chọn ít nhất một nhân viên.');
    if (_pass.text.length < 6) return setState(() => _error = 'Mật khẩu tối thiểu 6 ký tự.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await widget.api.createBulkAccounts(employeeIds: _picked.toList(), password: _pass.text, role: _role);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _saving = false;
        _result = Map<String, dynamic>.from(res['data'] as Map);
      });
    } else {
      setState(() {
        _saving = false;
        _error = res['message']?.toString() ?? 'Không tạo được tài khoản.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Tạo tài khoản từ hồ sơ nhân viên'), style: SboxType.titleStyle()),
              Text(tr('${widget.employees.length} nhân viên chưa có tài khoản'), style: SboxType.smallStyle()),
            ]),
          ),
          IconButton(onPressed: _saving ? null : () => Navigator.pop(context, result != null), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      const Divider(height: 1),
      Flexible(child: result != null ? _resultView(result) : _form()),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(children: [
          if (result == null) Expanded(child: Text(tr('Đã chọn ${_picked.length}'), style: SboxType.bodyStrong())) else const Spacer(),
          if (result == null) ...[
            SboxButton.ghost(label: 'Hủy', onPressed: _saving ? null : () => Navigator.pop(context, false)),
            const SizedBox(width: 8),
            SboxButton(label: 'Tạo ${_picked.length} tài khoản', icon: Icons.group_add_rounded, loading: _saving, onPressed: _saving || _picked.isEmpty ? null : _save),
          ] else
            SboxButton(label: 'Xong', onPressed: () => Navigator.pop(context, true)),
        ]),
      ),
    ]);
  }

  Widget _form() {
    final shown = _shown;
    final allPicked = shown.isNotEmpty && shown.every((e) => _picked.contains(e.id));
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 12), shrinkWrap: true, children: [
      Text(tr('Vai trò cho tất cả'), style: SboxType.titleSmStyle()),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final r in widget.policy.assignable)
          ChoiceChip(label: Text(tr(roleLabel(r, widget.roleOptions))), selected: r == _role, onSelected: (_) => setState(() => _role = r)),
      ]),
      const SizedBox(height: 16),
      TextField(
        controller: _pass,
        decoration: InputDecoration(
          labelText: tr('Mật khẩu chung'),
          helperText: tr('Tên đăng nhập tạo theo mã nhân viên. Nhân viên nên đổi mật khẩu sau lần đăng nhập đầu.'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
          suffixIcon: IconButton(
            tooltip: tr('Tạo ngẫu nhiên'),
            icon: const Icon(Icons.casino_outlined, size: 20),
            onPressed: () => setState(() => _pass.text = randomPassword(8)),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: tr('Tìm nhân viên'),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => setState(() => allPicked ? _picked.removeAll(shown.map((e) => e.id)) : _picked.addAll(shown.map((e) => e.id))),
          child: Text(tr(allPicked ? 'Bỏ chọn' : 'Chọn tất cả')),
        ),
      ]),
      const SizedBox(height: 4),
      for (final e in shown)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _picked.contains(e.id),
          onChanged: (v) => setState(() => v == true ? _picked.add(e.id) : _picked.remove(e.id)),
          title: Text(e.name),
          subtitle: Text([e.code, if (e.email.isNotEmpty) e.email].where((x) => x.isNotEmpty).join(' · ')),
        ),
      if (_error != null) ...[const SizedBox(height: 8), SettingsNoteBox(_error!, danger: true)],
    ]);
  }

  Widget _resultView(Map<String, dynamic> r) {
    final items = [for (final x in (r['items'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];
    final ok = items.where((x) => x['success'] == true).toList();
    final copy = [
      'Mật khẩu chung: ${_pass.text}',
      for (final x in ok) '${x['employeeName']}: ${x['userName'] ?? x['email'] ?? ''}',
    ].join('\n');
    return ListView(padding: const EdgeInsets.all(20), shrinkWrap: true, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        SboxStatusChip(label: 'Đã tạo ${r['created'] ?? ok.length}', tone: SboxTone.success),
        if ((r['skipped'] ?? 0) != 0) SboxStatusChip(label: 'Bỏ qua ${r['skipped']}', tone: SboxTone.warning),
        if ((r['failed'] ?? 0) != 0) SboxStatusChip(label: 'Lỗi ${r['failed']}', tone: SboxTone.danger),
      ]),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: copy)),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(tr('Sao chép danh sách đăng nhập')),
        ),
      ),
      for (final x in items)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            x['success'] == true ? Icons.check_circle_rounded : (x['skipped'] == true ? Icons.remove_circle_outline : Icons.error_outline),
            color: x['success'] == true ? SboxColors.success : (x['skipped'] == true ? SboxColors.warning : SboxColors.danger),
          ),
          title: Text('${x['employeeName'] ?? ''}'),
          subtitle: Text(x['success'] == true ? 'Tên đăng nhập: ${x['userName'] ?? ''}' : '${x['message'] ?? ''}'),
        ),
    ]);
  }
}
