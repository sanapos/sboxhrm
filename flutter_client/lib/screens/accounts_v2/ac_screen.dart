import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/permission_role_options.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'ac_bulk.dart';
import 'ac_common.dart';
import 'ac_editor.dart';

/// Tài khoản đăng nhập: ai vào được hệ thống, với vai trò gì.
/// Chỉ quản lý được tài khoản có vai trò thấp hơn mình; tài khoản chủ cửa hàng chỉ chủ tự sửa.
class AccountsV2Screen extends StatefulWidget {
  const AccountsV2Screen({super.key, this.permOverride, this.myUserId});

  /// Bỏ qua kiểm quyền (dùng cho test): view/create/edit/delete.
  final Set<String>? permOverride;

  /// Mã tài khoản đang đăng nhập (dùng cho test).
  final String? myUserId;

  @override
  State<AccountsV2Screen> createState() => _AccountsV2ScreenState();
}

enum _Filter { all, active, locked, issue }

class _AccountsV2ScreenState extends State<AccountsV2Screen> {
  final _api = ApiService();
  List<Account> _accounts = [];
  List<AcEmployee> _free = [];
  List<PermissionRoleOption> _roleOptions = PermissionRoleOptions.fallback;
  late RolePolicy _policy = RolePolicy.fallback('', myUserId: widget.myUserId);
  bool _loading = true;
  String? _error;
  String _q = '';
  String _role = 'all';
  _Filter _filter = _Filter.all;
  final Set<String> _busy = {};

  bool _can(String action) {
    final o = widget.permOverride;
    if (o != null) return o.contains(action);
    try {
      final p = Provider.of<PermissionProvider>(context, listen: false);
      return switch (action) {
        'create' => p.canCreate('UserManagement'),
        'edit' => p.canEdit('UserManagement'),
        'delete' => p.canDelete('UserManagement'),
        _ => p.canView('UserManagement'),
      };
    } catch (_) {
      return false;
    }
  }

  String? get _myUserId {
    if (widget.myUserId != null) return widget.myUserId;
    try {
      return Provider.of<AuthProvider>(context, listen: false).currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait<dynamic>([
        _api.getAccounts(),
        _api.getAccountRolePolicy(),
        _api.getRoles(),
        _can('create') ? _api.getEmployeesForSelect(pageSize: 10000) : Future.value(const []),
      ]);
      if (!mounted) return;
      final accounts = [for (final m in (r[0] as List).whereType<Map>()) Account(Map<String, dynamic>.from(m))];
      final pol = r[1] as Map<String, dynamic>;
      final roles = PermissionRoleOptions.parse(r[2] is List ? r[2] as List : const []);
      final linked = {for (final a in accounts) if (a.employeeId != null) a.employeeId!};
      final free = <AcEmployee>[];
      for (final m in (r[3] as List).whereType<Map>()) {
        final e = AcEmployee(Map<String, dynamic>.from(m));
        if (e.id.isEmpty || linked.contains(e.id)) continue;
        if ('${m['applicationUserId'] ?? ''}'.isNotEmpty) continue;
        free.add(e);
      }
      free.sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _accounts = accounts
          ..sort((a, b) {
            if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
            if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
            final rk = _policy.rankOf(b.role).compareTo(_policy.rankOf(a.role));
            return rk != 0 ? rk : a.fullName.compareTo(b.fullName);
          });
        _policy = pol['isSuccess'] == true && pol['data'] is Map
            ? RolePolicy.fromJson(Map<String, dynamic>.from(pol['data'] as Map), myUserId: _myUserId)
            : RolePolicy.fallback('', myUserId: _myUserId);
        if (roles.isNotEmpty) _roleOptions = roles;
        _free = free;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không tải được danh sách tài khoản.';
        });
      }
    }
  }

  List<Account> get _shown {
    final q = _q.trim().toLowerCase();
    return _accounts.where((a) {
      if (_role != 'all' && a.role.toLowerCase() != _role.toLowerCase()) return false;
      switch (_filter) {
        case _Filter.active:
          if (!a.isActive) return false;
        case _Filter.locked:
          if (a.isActive) return false;
        case _Filter.issue:
          if (!(a.isActive && a.hrIssue)) return false;
        case _Filter.all:
          break;
      }
      if (q.isEmpty) return true;
      return a.fullName.toLowerCase().contains(q) ||
          a.userName.toLowerCase().contains(q) ||
          a.email.toLowerCase().contains(q) ||
          (a.phone ?? '').contains(q);
    }).toList();
  }

  // ─── Thao tác ──────────────────────────────────────────────────

  Future<void> _add() async {
    if (await showAccountEditor(context, policy: _policy, roleOptions: _roleOptions, employees: _free, api: _api)) _load();
  }

  Future<void> _bulk() async {
    if (await showBulkAccounts(context, employees: _free, policy: _policy, roleOptions: _roleOptions, api: _api)) _load();
  }

  Future<void> _edit(Account a) async {
    if (await showAccountEditor(context, account: a, policy: _policy, roleOptions: _roleOptions, api: _api)) {
      _load();
      if (mounted) acToast(context, 'Đã lưu tài khoản ${a.fullName}');
    }
  }

  Future<void> _resetPassword(Account a) async {
    if (await showResetPassword(context, a, api: _api)) _load();
  }

  Future<void> _toggle(Account a) async {
    final lock = a.isActive;
    if (lock) {
      final ok = await _confirm(
        'Khóa tài khoản ${a.fullName}?',
        'Tài khoản bị đăng xuất ngay và không đăng nhập được nữa. Chỗ trống trong gói dịch vụ được trả lại. Dữ liệu vẫn giữ nguyên, mở khóa lại bất cứ lúc nào.',
        'Khóa',
        danger: true,
      );
      if (!ok) return;
    }
    setState(() => _busy.add(a.id));
    final res = await _api.toggleAccountStatus(a.id, !lock);
    if (!mounted) return;
    setState(() => _busy.remove(a.id));
    if (res['isSuccess'] == true) {
      acToast(context, lock ? 'Đã khóa ${a.fullName}' : 'Đã mở khóa ${a.fullName}');
      _load();
    } else {
      acToast(context, res['message']?.toString() ?? 'Không đổi được trạng thái.', error: true);
    }
  }

  Future<void> _delete(Account a) async {
    final ok = await _confirm(
      'Xóa tài khoản ${a.fullName}?',
      'Không hoàn tác được. Lịch sử thao tác của tài khoản được giữ lại nhưng không đăng nhập được nữa.\n\nNếu nhân viên chỉ tạm nghỉ, nên dùng «Khóa» thay vì xóa.',
      'Xóa vĩnh viễn',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy.add(a.id));
    final res = await _api.deleteAccount(a.id);
    if (!mounted) return;
    setState(() => _busy.remove(a.id));
    if (res['isSuccess'] == true) {
      acToast(context, 'Đã xóa ${a.fullName}');
      _load();
    } else {
      acToast(context, res['message']?.toString() ?? 'Không xóa được.', error: true);
    }
  }

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(title)),
          content: SizedBox(width: 420, child: Text(tr(body))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: SboxColors.danger) : null,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(action)),
            ),
          ],
        ),
      ) ==
      true;

  // ─── Giao diện ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.of(context).size.width < 700;
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: _loading
          ? const SboxLoading(message: 'Đang tải tài khoản…')
          : _error != null
              ? SboxEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: _error!,
                  action: SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh_rounded, onPressed: _load),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(narrow ? 12 : 24, 16, narrow ? 12 : 24, 32),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _header(narrow),
                            const SizedBox(height: 16),
                            _metrics(narrow),
                            const SizedBox(height: 16),
                            _toolbar(narrow),
                            const SizedBox(height: 12),
                            _list(narrow),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _header(bool narrow) {
    final actions = [
      if (_can('create') && _free.isNotEmpty)
        SboxButton.secondary(label: narrow ? 'Từ hồ sơ NV' : 'Tạo từ hồ sơ nhân viên', icon: Icons.group_add_outlined, onPressed: _bulk),
      if (_can('create')) SboxButton(label: 'Thêm tài khoản', icon: Icons.person_add_alt_1_rounded, onPressed: _add),
    ];
    final title = Row(children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: SboxColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.manage_accounts_rounded, color: SboxColors.dangerText),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Tài khoản'), style: SboxType.headlineStyle()),
          Text(tr('Ai được đăng nhập và với vai trò gì. Quyền chi tiết của từng vai trò ở mục Phân quyền.'), style: SboxType.smallStyle()),
        ]),
      ),
    ]);
    if (narrow) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        title,
        if (actions.isNotEmpty) ...[const SizedBox(height: 12), Wrap(spacing: 8, runSpacing: 8, children: actions)],
      ]);
    }
    return Row(children: [
      Expanded(child: title),
      for (final a in actions) ...[const SizedBox(width: 8), a],
    ]);
  }

  Widget _metrics(bool narrow) {
    final active = _accounts.where((a) => a.isActive).length;
    final locked = _accounts.length - active;
    final issue = _accounts.where((a) => a.isActive && a.hrIssue).length;
    Widget m(_Filter f, String label, int n, IconData icon, Color c) {
      final sel = _filter == f;
      return InkWell(
        onTap: () => setState(() => _filter = sel ? _Filter.all : f),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? c.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: sel ? c : SboxColors.border, width: sel ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$n', style: SboxType.titleStyle()),
                Text(tr(label), style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
    }

    final tiles = [
      m(_Filter.all, 'Tổng tài khoản', _accounts.length, Icons.people_alt_outlined, SboxColors.brand600),
      m(_Filter.active, 'Đang hoạt động', active, Icons.check_circle_outline_rounded, SboxColors.success),
      m(_Filter.locked, 'Đã khóa', locked, Icons.lock_outline_rounded, SboxColors.slate500),
      m(_Filter.issue, 'Cần xử lý', issue, Icons.report_gmailerrorred_rounded, SboxColors.warning),
    ];
    if (narrow) {
      return Column(children: [
        Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 8), Expanded(child: tiles[1])]),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 8), Expanded(child: tiles[3])]),
      ]);
    }
    return Row(children: [
      for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: tiles[i])],
    ]);
  }

  Widget _toolbar(bool narrow) {
    final roles = {for (final a in _accounts) a.role}.toList()..sort((a, b) => _policy.rankOf(b).compareTo(_policy.rankOf(a)));
    final search = TextField(
      onChanged: (v) => setState(() => _q = v),
      decoration: InputDecoration(
        hintText: tr('Tìm theo tên, tên đăng nhập, email, SĐT'),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.border)),
      ),
    );
    final chips = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _chip('Tất cả vai trò', _role == 'all', () => setState(() => _role = 'all')),
        for (final r in roles)
          _chip('${roleLabel(r, _roleOptions)} (${_accounts.where((a) => a.role == r).length})', _role == r, () => setState(() => _role = r)),
      ]),
    );
    if (narrow) return Column(children: [search, const SizedBox(height: 8), chips]);
    return Row(children: [SizedBox(width: 340, child: search), const SizedBox(width: 12), Expanded(child: chips)]);
  }

  Widget _chip(String label, bool sel, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(tr(label)), selected: sel, onSelected: (_) => onTap(), showCheckmark: false),
      );

  Widget _list(bool narrow) {
    final shown = _shown;
    if (shown.isEmpty) {
      return SboxCard(
        child: SboxEmptyState(
          icon: Icons.person_search_outlined,
          title: _accounts.isEmpty ? 'Chưa có tài khoản nào' : 'Không có tài khoản phù hợp',
          message: _accounts.isEmpty ? 'Thêm tài khoản để nhân viên đăng nhập.' : 'Thử bỏ bớt bộ lọc.',
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.border)),
      child: Column(children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
          _row(shown[i], narrow),
        ],
      ]),
    );
  }

  Widget _row(Account a, bool narrow) {
    final deny = _policy.denyManage(a);
    final self = a.id == _policy.myUserId;
    final chips = <Widget>[
      if (a.isOwner) const SboxStatusChip(label: 'Chủ cửa hàng', tone: SboxTone.violet, icon: Icons.workspace_premium_rounded),
      if (self) const SboxStatusChip(label: 'Bạn', tone: SboxTone.brand),
      SboxStatusChip(label: roleLabel(a.role, _roleOptions), tone: roleTone(a.role)),
      if (!a.isActive) const SboxStatusChip(label: 'Đã khóa', tone: SboxTone.neutral, icon: Icons.lock_outline_rounded),
      if (a.isActive && a.hrIssueLabel != null) SboxStatusChip(label: a.hrIssueLabel!, tone: SboxTone.warning, icon: Icons.warning_amber_rounded),
    ];
    final sub = [a.userName, if (a.email.isNotEmpty && a.email != a.userName) a.email, if (a.phone != null) a.phone!].join(' · ');
    final menu = _busy.contains(a.id)
        ? const SizedBox(width: 40, height: 40, child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2)))
        : _menu(a, deny, self);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(a.fullName, style: SboxType.bodyStrong(a.isActive ? SboxColors.text : SboxColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
      Text(sub, style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: chips),
    ]);
    return InkWell(
      onTap: _can('edit') ? () => _edit(a) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Opacity(opacity: a.isActive ? 1 : 0.5, child: AcAvatar(a)),
          const SizedBox(width: 12),
          Expanded(child: info),
          if (!narrow)
            SizedBox(
              width: 150,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(tr('Đăng nhập gần nhất'), style: SboxType.captionStyle()),
                Text(tr(agoText(a.lastLoginAt)), style: SboxType.smallStyle()),
              ]),
            ),
          const SizedBox(width: 4),
          menu,
        ]),
      ),
    );
  }

  Widget _menu(Account a, String? deny, bool self) {
    PopupMenuItem<String> item(String v, IconData icon, String label, {bool enabled = true, bool danger = false}) => PopupMenuItem(
          value: v,
          enabled: enabled,
          child: Row(children: [
            Icon(icon, size: 20, color: !enabled ? SboxColors.textDisabled : (danger ? SboxColors.danger : SboxColors.slate600)),
            const SizedBox(width: 10),
            Text(tr(label), style: TextStyle(color: !enabled ? SboxColors.textDisabled : (danger ? SboxColors.danger : null))),
          ]),
        );
    final canEdit = _can('edit');
    final manage = canEdit && deny == null;
    return PopupMenuButton<String>(
      tooltip: tr('Thao tác'),
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (v) => switch (v) {
        'edit' => _edit(a),
        'pass' => _resetPassword(a),
        'toggle' => _toggle(a),
        'delete' => _delete(a),
        _ => null,
      },
      itemBuilder: (_) => [
        item('edit', Icons.edit_outlined, 'Sửa thông tin', enabled: canEdit && (self || deny == null)),
        item('pass', Icons.key_rounded, 'Đặt lại mật khẩu', enabled: manage),
        item('toggle', a.isActive ? Icons.lock_outline_rounded : Icons.lock_open_rounded, a.isActive ? 'Khóa tài khoản' : 'Mở khóa', enabled: manage),
        item('delete', Icons.delete_outline_rounded, 'Xóa', enabled: _can('delete') && deny == null, danger: true),
        if (deny != null)
          PopupMenuItem<String>(
            enabled: false,
            child: SizedBox(
              width: 240,
              child: Text(tr(deny), style: SboxType.captionStyle()),
            ),
          ),
      ],
    );
  }
}
