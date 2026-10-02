import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../utils/permission_role_options.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'ac_common.dart';

/// Hồ sơ nhân viên chưa có tài khoản (để liên kết khi tạo).
class AcEmployee {
  AcEmployee(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id'] ?? ''}';
  String get code => '${m['employeeCode'] ?? ''}';
  String get firstName => '${m['firstName'] ?? ''}';
  String get lastName => '${m['lastName'] ?? ''}';
  String get name {
    final n = '${m['fullName'] ?? '$lastName $firstName'}'.trim();
    return n.isEmpty ? code : n;
  }

  String get email => '${m['companyEmail'] ?? m['personalEmail'] ?? m['email'] ?? ''}'.trim();
  String get phone => '${m['phoneNumber'] ?? ''}'.trim();
  String get label => code.isEmpty ? name : '$name · $code';
}

/// Mở form thêm / sửa tài khoản. Trả về true khi đã lưu.
Future<bool> showAccountEditor(
  BuildContext context, {
  Account? account,
  required RolePolicy policy,
  required List<PermissionRoleOption> roleOptions,
  List<AcEmployee> employees = const [],
  ApiService? api,
}) async {
  final narrow = MediaQuery.of(context).size.width < 640;
  final body = AcEditor(account: account, policy: policy, roleOptions: roleOptions, employees: employees, api: api);
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => narrow
        ? Dialog.fullscreen(child: body)
        : Dialog(
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620, maxHeight: 820), child: body),
          ),
  );
  return r == true;
}

class AcEditor extends StatefulWidget {
  const AcEditor({
    super.key,
    this.account,
    required this.policy,
    required this.roleOptions,
    this.employees = const [],
    this.api,
  });

  final Account? account;
  final RolePolicy policy;
  final List<PermissionRoleOption> roleOptions;
  final List<AcEmployee> employees;
  final ApiService? api;

  @override
  State<AcEditor> createState() => _AcEditorState();
}

class _AcEditorState extends State<AcEditor> {
  late final ApiService _api = widget.api ?? ApiService();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _pass = TextEditingController();
  bool _showPass = false;
  late String _role;
  AcEmployee? _employee;
  List<Map<String, dynamic>> _areas = [];
  final Set<String> _areaIds = {};
  bool _saving = false;
  String? _error;

  bool get _editing => widget.account != null;
  Account? get _a => widget.account;

  /// Được đổi vai trò tài khoản này không (không đổi vai trò của chính mình / tài khoản cấp cao).
  bool get _roleLocked => _editing && widget.policy.denyManage(_a!) != null;

  List<String> get _roleChoices {
    final out = <String>[...widget.policy.assignable];
    if (_editing && !out.any((r) => r.toLowerCase() == _role.toLowerCase())) out.insert(0, _role);
    return out;
  }

  @override
  void initState() {
    super.initState();
    final a = _a;
    if (a != null) {
      _name.text = a.fullName;
      _user.text = a.userName;
      _email.text = a.email;
      _phone.text = a.phone ?? '';
      _role = a.role;
    } else {
      _role = widget.policy.canAssign('Employee')
          ? 'Employee'
          : (widget.policy.assignable.isNotEmpty ? widget.policy.assignable.last : 'Employee');
      _pass.text = randomPassword();
    }
    _loadAreas();
  }

  @override
  void dispose() {
    for (final c in [_name, _user, _email, _phone, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAreas() async {
    try {
      final res = await _api.getPosServiceAreas();
      final data = res['data'];
      final list = data is List ? data : (data is Map ? (data['items'] ?? data['areas'] ?? const []) : const []);
      final areas = [for (final e in (list as List).whereType<Map>()) Map<String, dynamic>.from(e)];
      final ids = <String>{};
      if (_editing && areas.isNotEmpty) {
        final r = await _api.getPosUserServiceAreas(_a!.id);
        final d = r['data'];
        if (d is Map && d['areaIds'] is List) {
          for (final id in d['areaIds'] as List) {
            if ('$id'.isNotEmpty) ids.add('$id');
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _areas = areas;
        _areaIds
          ..clear()
          ..addAll(ids);
      });
    } catch (_) {/* không có POS — bỏ qua */}
  }

  void _pickEmployee(AcEmployee e) {
    setState(() {
      _employee = e;
      _name.text = e.name;
      if (e.email.isNotEmpty) _email.text = e.email;
      if (e.phone.isNotEmpty) _phone.text = e.phone;
      if (_user.text.trim().isEmpty && e.code.isNotEmpty) _user.text = e.code.toLowerCase();
    });
  }

  String? _validate() {
    if (_name.text.trim().isEmpty) return 'Nhập họ và tên.';
    final email = _email.text.trim();
    if (email.isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return 'Email không hợp lệ.';
    final user = _user.text.trim();
    if (user.isNotEmpty && !RegExp(r'^[A-Za-z0-9._@-]+$').hasMatch(user)) {
      return 'Tên đăng nhập chỉ gồm chữ không dấu, số và . _ - @';
    }
    if (!_editing && _pass.text.length < 6) return 'Mật khẩu tối thiểu 6 ký tự.';
    return null;
  }

  Future<void> _save() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    final firstName = parts.last;
    final lastName = parts.length > 1 ? parts.sublist(0, parts.length - 1).join(' ') : '';
    final userName = _user.text.trim().isEmpty ? _email.text.trim().split('@').first : _user.text.trim();
    final data = <String, dynamic>{
      'userName': userName,
      'firstName': firstName,
      'lastName': lastName,
      'email': _email.text.trim(),
      'phoneNumber': _phone.text.trim(),
      if (!_roleLocked) 'role': _role,
      if (!_editing) 'password': _pass.text,
      if (!_editing && _employee != null) 'employeeId': _employee!.id,
    };
    try {
      final res = _editing ? await _api.updateAccount(_a!.id, data) : await _api.createAccount(data);
      if (res['isSuccess'] != true) {
        setState(() {
          _saving = false;
          _error = _message(res, 'Không lưu được tài khoản.');
        });
        return;
      }
      var uid = _a?.id;
      final d = res['data'];
      if (d is Map && d['id'] != null) uid = '${d['id']}';
      if (uid != null && uid.isNotEmpty && _areas.isNotEmpty) {
        // Quản lý trở lên luôn xem mọi khu — xóa giới hạn nếu có.
        await _api.setPosUserServiceAreas(uid, posAreaRoles.contains(_role) ? _areaIds.toList() : <String>[]);
      }
      if (!mounted) return;
      if (!_editing) {
        await _showCreated(userName);
        if (!mounted) return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Lỗi kết nối: $e';
      });
    }
  }

  static String _message(Map res, String fallback) {
    final m = res['message']?.toString();
    if (m != null && m.isNotEmpty) return m;
    final errs = res['errors'];
    if (errs is List && errs.isNotEmpty) return errs.join('\n');
    return fallback;
  }

  /// Sau khi tạo: hiện thông tin đăng nhập để gửi cho nhân viên.
  Future<void> _showCreated(String userName) => showDialog<void>(
        context: context,
        builder: (ctx) {
          final text = 'Tên đăng nhập: $userName\nEmail: ${_email.text.trim()}\nMật khẩu: ${_pass.text}';
          return AlertDialog(
            title: Text(tr('Đã tạo tài khoản')),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Gửi thông tin đăng nhập cho nhân viên. Mật khẩu sẽ không hiện lại.'), style: SboxType.smallStyle()),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(10), border: Border.all(color: SboxColors.border)),
                child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', height: 1.6)),
              ),
            ]),
            actions: [
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(tr('Sao chép')),
              ),
              FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Xong'))),
            ],
          );
        },
      );

  InputDecoration _dec(String label, {String? hint, Widget? suffix, IconData? icon}) => InputDecoration(
        labelText: tr(label),
        hintText: hint == null ? null : tr(hint),
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(tr(t), style: SboxType.titleSmStyle()),
      );

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 640;
    final title = _editing ? 'Sửa tài khoản' : 'Thêm tài khoản';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Tiêu đề
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(title), style: SboxType.titleStyle()),
              if (_editing) Text(_a!.fullName, style: SboxType.smallStyle()),
            ]),
          ),
          IconButton(onPressed: _saving ? null : () => Navigator.pop(context, false), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      const Divider(height: 1),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (!_editing && widget.employees.isNotEmpty) ...[
              _label('Liên kết hồ sơ nhân viên'),
              _EmployeePicker(employees: widget.employees, selected: _employee, onPick: _pickEmployee, onClear: () => setState(() => _employee = null)),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('Không bắt buộc. Liên kết để nhân viên xem công, lương, gửi đơn của mình.'), style: SboxType.captionStyle()),
              ),
            ],
            _label('Thông tin đăng nhập'),
            TextField(controller: _name, decoration: _dec('Họ và tên *', hint: 'Nguyễn Văn An', icon: Icons.person_outline_rounded)),
            const SizedBox(height: 12),
            _pair(
              narrow,
              TextField(controller: _user, decoration: _dec('Tên đăng nhập', hint: 'Để trống = phần trước @ của email', icon: Icons.alternate_email_rounded)),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: _dec('Email *', icon: Icons.mail_outline_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _dec('Số điện thoại', icon: Icons.phone_outlined)),
            if (!_editing) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _pass,
                obscureText: !_showPass,
                decoration: _dec('Mật khẩu *',
                    icon: Icons.lock_outline_rounded,
                    suffix: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: tr('Tạo ngẫu nhiên'),
                        icon: const Icon(Icons.casino_outlined, size: 20),
                        onPressed: () => setState(() {
                          _pass.text = randomPassword();
                          _showPass = true;
                        }),
                      ),
                      IconButton(
                        tooltip: tr(_showPass ? 'Ẩn' : 'Hiện'),
                        icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                        onPressed: () => setState(() => _showPass = !_showPass),
                      ),
                    ])),
              ),
            ],
            _label('Vai trò'),
            if (_roleLocked)
              SettingsNoteBox(
                '${roleLabel(_role, widget.roleOptions)} — ${widget.policy.denyManage(_a!)}',
              )
            else if (_roleChoices.isEmpty)
              const SettingsNoteBox('Bạn chưa được gán vai trò nào cho người khác.')
            else
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in _roleChoices)
                  _RoleChoice(
                    label: roleLabel(r, widget.roleOptions),
                    hint: roleHint(r),
                    selected: r.toLowerCase() == _role.toLowerCase(),
                    enabled: widget.policy.canAssign(r),
                    onTap: () => setState(() => _role = r),
                  ),
              ]),
            if (_areas.isNotEmpty && posAreaRoles.contains(_role)) ...[
              _label('Khu vực bán hàng được xem'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                  label: Text(tr('Tất cả khu')),
                  selected: _areaIds.isEmpty,
                  onSelected: (_) => setState(_areaIds.clear),
                ),
                for (final a in _areas)
                  FilterChip(
                    label: Text('${a['name'] ?? a['Name'] ?? a['code'] ?? ''}'),
                    selected: _areaIds.contains('${a['id'] ?? a['Id']}'),
                    onSelected: (v) => setState(() {
                      final id = '${a['id'] ?? a['Id']}';
                      v ? _areaIds.add(id) : _areaIds.remove(id);
                    }),
                  ),
              ]),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              SettingsNoteBox(_error!, danger: true),
            ],
          ]),
        ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(children: [
          if (_editing) Expanded(child: Text(tr('Đổi vai trò sẽ đăng xuất tài khoản khỏi mọi thiết bị.'), style: SboxType.captionStyle())) else const Spacer(),
          const SizedBox(width: 12),
          SboxButton.ghost(label: 'Hủy', onPressed: _saving ? null : () => Navigator.pop(context, false)),
          const SizedBox(width: 8),
          SboxButton(label: _editing ? 'Lưu' : 'Tạo tài khoản', icon: Icons.check_rounded, loading: _saving, onPressed: _saving ? null : _save),
        ]),
      ),
    ]);
  }

  Widget _pair(bool narrow, Widget a, Widget b) => narrow
      ? Column(children: [a, const SizedBox(height: 12), b])
      : Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);
}

/// Ô ghi chú nhỏ (không dùng SettingsNote vì nằm trong dialog).
class SettingsNoteBox extends StatelessWidget {
  const SettingsNoteBox(this.text, {super.key, this.danger = false});
  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: danger ? SboxColors.dangerSoft : SboxColors.slate50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: danger ? SboxColors.danger.withValues(alpha: 0.3) : SboxColors.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(danger ? Icons.error_outline_rounded : Icons.lock_outline_rounded, size: 18, color: danger ? SboxColors.dangerText : SboxColors.slate500),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(text), style: SboxType.smallStyle(danger ? SboxColors.dangerText : SboxColors.textSecondary))),
        ]),
      );
}

class _RoleChoice extends StatelessWidget {
  const _RoleChoice({required this.label, required this.hint, required this.selected, required this.enabled, required this.onTap});
  final String label;
  final String hint;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? SboxColors.brand50 : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? SboxColors.brand600 : SboxColors.border, width: selected ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(tr(label),
                    style: SboxType.bodyStrong(enabled ? (selected ? SboxColors.brand700 : SboxColors.text) : SboxColors.textDisabled)),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: SboxColors.brand600),
            ]),
            if (hint.isNotEmpty) Text(tr(hint), style: SboxType.captionStyle(), maxLines: 2),
          ]),
        ),
      );
}

class _EmployeePicker extends StatelessWidget {
  const _EmployeePicker({required this.employees, required this.selected, required this.onPick, required this.onClear});
  final List<AcEmployee> employees;
  final AcEmployee? selected;
  final ValueChanged<AcEmployee> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (selected != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(10), border: Border.all(color: SboxColors.brand200)),
        child: Row(children: [
          const Icon(Icons.badge_outlined, color: SboxColors.brand700, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(selected!.label, style: SboxType.bodyStrong(SboxColors.brand700))),
          IconButton(tooltip: tr('Bỏ liên kết'), onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18)),
        ]),
      );
    }
    return Autocomplete<AcEmployee>(
      displayStringForOption: (e) => e.label,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        final list = q.isEmpty ? employees : employees.where((e) => e.label.toLowerCase().contains(q) || e.email.toLowerCase().contains(q));
        return list.take(30);
      },
      onSelected: onPick,
      fieldViewBuilder: (ctx, c, f, _) => TextField(
        controller: c,
        focusNode: f,
        decoration: InputDecoration(
          hintText: tr('Tìm theo tên hoặc mã nhân viên'),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
    );
  }
}

/// Đặt lại mật khẩu cho tài khoản khác. Trả về true khi đã đổi.
Future<bool> showResetPassword(BuildContext context, Account a, {ApiService? api}) async {
  final r = await showDialog<bool>(context: context, builder: (_) => _ResetPasswordDialog(a, api ?? ApiService()));
  return r == true;
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog(this.a, this.api);
  final Account a;
  final ApiService api;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _c = TextEditingController(text: randomPassword());
  bool _show = true;
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_c.text.length < 6) {
      setState(() => _error = 'Mật khẩu tối thiểu 6 ký tự.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final res = await widget.api.resetAccountPassword(widget.a.id, _c.text);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _saving = false;
        _done = true;
      });
    } else {
      setState(() {
        _saving = false;
        _error = _AcEditorState._message(res, 'Không đặt lại được mật khẩu.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = 'Tên đăng nhập: ${widget.a.userName}\nMật khẩu mới: ${_c.text}';
    return AlertDialog(
      title: Text(tr(_done ? 'Đã đặt lại mật khẩu' : 'Đặt lại mật khẩu')),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.a.fullName, style: SboxType.bodyStrong()),
          const SizedBox(height: 4),
          Text(tr('Tài khoản sẽ bị đăng xuất khỏi mọi thiết bị và phải đăng nhập bằng mật khẩu mới.'), style: SboxType.smallStyle()),
          const SizedBox(height: 14),
          if (_done)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: SboxColors.successSoft, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', height: 1.6)),
            )
          else
            TextField(
              controller: _c,
              obscureText: !_show,
              decoration: InputDecoration(
                labelText: tr('Mật khẩu mới'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: tr('Tạo ngẫu nhiên'),
                    icon: const Icon(Icons.casino_outlined, size: 20),
                    onPressed: () => setState(() => _c.text = randomPassword()),
                  ),
                  IconButton(
                    icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ]),
              ),
            ),
          if (_error != null) ...[const SizedBox(height: 12), SettingsNoteBox(_error!, danger: true)],
        ]),
      ),
      actions: _done
          ? [
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: text)),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(tr('Sao chép')),
              ),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Xong'))),
            ]
          : [
              TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: Text(tr('Hủy'))),
              FilledButton(onPressed: _saving ? null : _save, child: Text(tr(_saving ? 'Đang lưu…' : 'Đặt lại'))),
            ],
    );
  }
}
