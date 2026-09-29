import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../services/api_service.dart';
import '../theme/sbox_tokens.dart';
import 'hrm_page_chrome.dart';
import 'notification_overlay.dart';

/// Kết quả bảng mẫu phân quyền.
class PermissionPresetResult {
  const PermissionPresetResult.applied() : preview = null, roleName = null;
  const PermissionPresetResult.preview(this.roleName, this.preview);

  /// Vai trò đang xem trước (null = đã áp dụng thẳng).
  final String? roleName;

  /// Quyền của mẫu (cùng dạng với quyền vai trò) để nạp vào bảng — chưa lưu.
  final Map<String, dynamic>? preview;

  bool get isApplied => preview == null;
}

/// Bảng «Mẫu phân quyền»: chọn gói (HRM / POS / HRM + POS), mẫu cho từng vai trò, xem trước hoặc áp dụng.
class PermissionPresetSheet extends StatefulWidget {
  const PermissionPresetSheet({super.key, this.focusRole});

  /// Chỉ hiện một vai trò (nút «Nạp mẫu» trong vai trò đang chọn).
  final String? focusRole;

  static Future<PermissionPresetResult?> show(BuildContext context, {String? focusRole}) {
    return showModalBottomSheet<PermissionPresetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 820),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: PermissionPresetSheet(focusRole: focusRole),
      ),
    );
  }

  @override
  State<PermissionPresetSheet> createState() => _PermissionPresetSheetState();
}

class _PermissionPresetSheetState extends State<PermissionPresetSheet> {
  final _api = ApiService();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String _package = '';
  String _detected = '';
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _presets = [];
  Map<String, String> _defaults = {};
  final Map<String, String> _chosen = {};
  final Set<String> _checked = {};

  static const _roleOrder = [
    'Director', 'Manager', 'DepartmentHead', 'Accountant', 'Cashier', 'Waiter', 'Employee', 'User',
  ];
  static const _roleLabel = {
    'Director': 'Giám đốc',
    'Manager': 'Quản lý',
    'DepartmentHead': 'Trưởng phòng',
    'Accountant': 'Kế toán',
    'Cashier': 'Thu ngân',
    'Waiter': 'Phục vụ',
    'Employee': 'Nhân viên',
    'User': 'Người dùng',
  };
  static const _roleIcon = {
    'Director': Icons.workspace_premium_outlined,
    'Manager': Icons.manage_accounts_outlined,
    'DepartmentHead': Icons.groups_2_outlined,
    'Accountant': Icons.calculate_outlined,
    'Cashier': Icons.point_of_sale_outlined,
    'Waiter': Icons.room_service_outlined,
    'Employee': Icons.badge_outlined,
    'User': Icons.person_outline,
  };

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  Future<void> _load(String? package) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getPermissionPresets(package: package);
    if (!mounted) return;
    final d = r['data'];
    if (r['isSuccess'] != true || d is! Map) {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được mẫu phân quyền';
      });
      return;
    }
    setState(() {
      _loading = false;
      _package = d['package']?.toString() ?? 'full';
      _detected = d['detectedPackage']?.toString() ?? _package;
      _packages = [for (final x in (d['packages'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      _presets = [for (final x in (d['presets'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
      _defaults = {
        for (final e in ((d['defaults'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString(),
      };
      _chosen
        ..clear()
        ..addAll(_defaults);
      _checked
        ..clear()
        ..addAll(_roles.where((r) => r != 'Director'));
    });
  }

  List<String> get _roles {
    final list = _roleOrder.where(_defaults.containsKey).toList();
    if (widget.focusRole != null) return list.where((r) => r == widget.focusRole).toList();
    return list;
  }

  List<Map<String, dynamic>> _presetsFor(String role) => _presets.where((p) {
        final extra = (p['extraRoles'] as List? ?? const []).map((e) => e.toString());
        return p['roleName'] == role || extra.contains(role);
      }).toList();

  Map<String, dynamic>? _preset(String? id) {
    for (final p in _presets) {
      if (p['id'] == id) return p;
    }
    return null;
  }

  Future<void> _preview(String role) async {
    final id = _chosen[role];
    if (id == null) return;
    setState(() => _busy = true);
    final r = await _api.getPermissionPreset(id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true && r['data'] is Map) {
      final data = Map<String, dynamic>.from(r['data'] as Map);
      data['roleName'] = role;
      Navigator.pop(context, PermissionPresetResult.preview(role, data));
    } else {
      NotificationOverlayManager().showError(title: 'Không xem trước được', message: r['message']?.toString() ?? '');
    }
  }

  Future<void> _apply() async {
    final roles = _roles.where(_checked.contains).where((r) => _chosen[r] != null).toList();
    if (roles.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Áp dụng mẫu cho ${roles.length} vai trò?')),
        content: Text(tr('Quyền hiện có của ${roles.map((r) => _roleLabel[r] ?? r).join(', ')} sẽ được thay bằng mẫu đã chọn. '
            'Có thể chỉnh lại từng quyền sau khi áp dụng.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Áp dụng'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await _api.applyPermissionPresets([
      for (final role in roles) {'roleName': role, 'presetId': _chosen[role]!},
    ]);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã áp dụng mẫu phân quyền',
        message: tr('${roles.length} vai trò — nhân viên cần đăng nhập lại / mở lại app để nhận quyền mới.'),
      );
      Navigator.pop(context, const PermissionPresetResult.applied());
    } else {
      NotificationOverlayManager().showError(title: 'Không áp dụng được', message: r['message']?.toString() ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(_error!)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _load(null), child: Text(tr('Thử lại'))),
        ]),
      );
    }
    final roles = _roles;
    final checkedCount = roles.where(_checked.contains).length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_outlined, color: HrmPageChrome.primaryNavy),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(widget.focusRole == null ? 'Mẫu phân quyền dựng sẵn' : 'Nạp mẫu cho ${_roleLabel[widget.focusRole] ?? widget.focusRole}'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            tr('Chọn loại cửa hàng, rồi chọn chức danh cho từng vai trò. Xem trước để chỉnh từng quyền trước khi lưu, '
                'hoặc áp dụng thẳng cho nhiều vai trò.'),
            style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final p in _packages)
                ButtonSegment(
                  value: p['code'].toString(),
                  label: Text(tr('${p['label']}${p['code'] == _detected ? ' ✓' : ''}'), overflow: TextOverflow.ellipsis),
                ),
            ],
            selected: {_package},
            onSelectionChanged: _busy ? null : (s) => _load(s.first),
          ),
          if (_package != _detected)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('Gói của cửa hàng là «${_packages.firstWhere((p) => p['code'] == _detected, orElse: () => {'label': _detected})['label']}» — '
                  'chức năng ngoài gói sẽ không được cấp.'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.warningText)),
            ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: roles.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _roleCard(roles[i]),
        ),
      ),
      if (widget.focusRole == null)
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _busy || checkedCount == 0 ? null : _apply,
              style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.done_all_rounded),
              label: Text(tr('Áp dụng cho $checkedCount vai trò')),
            ),
          ),
        ),
    ]);
  }

  Widget _roleCard(String role) {
    final options = _presetsFor(role);
    final chosen = _preset(_chosen[role]);
    final checked = _checked.contains(role);
    final superRole = chosen?['superRole'] == true;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: checked ? HrmPageChrome.primaryNavy.withValues(alpha: 0.4) : SboxColors.slate200),
      ),
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.focusRole == null)
          Checkbox(
            value: checked,
            onChanged: (v) => setState(() => v == true ? _checked.add(role) : _checked.remove(role)),
          )
        else
          const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(_roleIcon[role] ?? Icons.badge_outlined, size: 18, color: HrmPageChrome.primaryNavy),
              const SizedBox(width: 6),
              Text(tr('Vai trò ${_roleLabel[role] ?? role}'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate500, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (chosen != null)
                Text(tr('${chosen['grantedModules']} chức năng'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            ]),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _chosen[role],
              isExpanded: true,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: [
                for (final p in options)
                  DropdownMenuItem(
                    value: p['id'].toString(),
                    child: Text(tr(p['title'].toString()), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
              ],
              onChanged: (v) => setState(() {
                if (v != null) _chosen[role] = v;
              }),
            ),
            if (chosen != null) ...[
              const SizedBox(height: 6),
              Text(tr(chosen['description'].toString()),
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600, height: 1.35)),
            ],
            if (superRole)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(tr('Giám đốc luôn có toàn quyền khi dùng — mẫu chỉ để hiển thị trên bảng phân quyền.'),
                    style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500, fontStyle: FontStyle.italic)),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _preview(role),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text(tr(widget.focusRole == null ? 'Xem trước & chỉnh' : 'Nạp vào bảng quyền')),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
