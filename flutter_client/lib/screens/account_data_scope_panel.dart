import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Gán chi nhánh / phòng ban tài khoản được xem dữ liệu (HRM Phân quyền).
class AccountDataScopePanel extends StatefulWidget {
  const AccountDataScopePanel({super.key});

  @override
  State<AccountDataScopePanel> createState() => _AccountDataScopePanelState();
}

class _AccountDataScopePanelState extends State<AccountDataScopePanel> {
  final ApiService _api = ApiService();
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _departments = [];
  String? _selectedUserId;
  bool _loadingList = true;
  bool _loadingScope = false;
  bool _saving = false;
  String _accountQuery = '';

  bool _allBranches = false;
  bool _includeChildBranches = true;
  final Set<String> _branchIds = {};
  List<String> _inheritedBranchIds = [];

  bool _allDepartments = false;
  bool _includeChildDepartments = true;
  final Set<String> _departmentIds = {};
  List<String> _inheritedDepartmentIds = [];

  bool _isAdminAccount = false;
  String? _roleLabel;

  bool get _canEdit => _perm.canEdit('Role');

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    setState(() => _loadingList = true);
    try {
      final results = await Future.wait([
        _api.getAccounts(),
        _api.getBranchesForSelect(),
        _api.getDepartmentsForSelect(),
      ]);
      final accountsRaw = results[0];
      final accounts = accountsRaw is List
          ? accountsRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      accounts.sort((a, b) => _accountLabel(a).compareTo(_accountLabel(b)));

      final brResult = results[1] as Map<String, dynamic>;
      final brData = brResult['data'];
      final branches = brData is List
          ? brData.map((b) => Map<String, dynamic>.from(b as Map)).toList()
          : <Map<String, dynamic>>[];

      final deptResult = results[2] as Map<String, dynamic>;
      final deptData = deptResult['data'];
      final departments = deptData is List
          ? deptData.map((d) => Map<String, dynamic>.from(d as Map)).toList()
          : <Map<String, dynamic>>[];

      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _branches = _flattenTree(branches, 'parentBranchId');
        _departments = _flattenTree(departments, 'parentDepartmentId');
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingList = false);
      appNotification.showError(title: 'Lỗi', message: 'Không tải được danh sách: $e');
    }
  }

  List<Map<String, dynamic>> _flattenTree(
      List<Map<String, dynamic>> items, String parentKey) {
    final byParent = <String?, List<Map<String, dynamic>>>{};
    for (final i in items) {
      var p = i[parentKey]?.toString();
      if (p == null || p.isEmpty || p == 'null') p = null;
      byParent.putIfAbsent(p, () => []).add(i);
    }
    for (final list in byParent.values) {
      list.sort((a, b) => (a['name']?.toString() ?? '')
          .compareTo(b['name']?.toString() ?? ''));
    }
    final out = <Map<String, dynamic>>[];
    void walk(String? parent, int level) {
      for (final n in byParent[parent] ?? const []) {
        out.add({...n, '_level': level});
        walk(n['id']?.toString(), level + 1);
      }
    }

    walk(null, 0);
    if (out.length < items.length) {
      final seen = out.map((e) => e['id']?.toString()).toSet();
      for (final i in items) {
        if (!seen.contains(i['id']?.toString())) {
          out.add({...i, '_level': 0});
        }
      }
    }
    return out;
  }

  String _accountLabel(Map<String, dynamic> a) {
    final name = (a['fullName'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return (a['userName'] ?? a['email'] ?? '').toString();
  }

  String _accountRole(Map<String, dynamic> a) {
    final roles = a['roles'];
    if (roles is List && roles.isNotEmpty) return roles.first.toString();
    return (a['role'] ?? '').toString();
  }

  List<Map<String, dynamic>> get _filteredAccounts {
    final q = _accountQuery.trim().toLowerCase();
    if (q.isEmpty) return _accounts;
    return _accounts.where((a) {
      return _accountLabel(a).toLowerCase().contains(q) ||
          (a['userName']?.toString().toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _selectUser(String userId) async {
    setState(() {
      _selectedUserId = userId;
      _loadingScope = true;
      _isAdminAccount = false;
    });
    try {
      final res = await _api.getAccountDataScope(userId);
      if (!mounted) return;
      final data = res['data'];
      if (data is! Map) {
        setState(() => _loadingScope = false);
        appNotification.showError(
            title: 'Lỗi',
            message: res['message']?.toString() ?? 'Không tải được phạm vi');
        return;
      }
      final m = Map<String, dynamic>.from(data);
      setState(() {
        _allBranches = m['allBranches'] == true;
        _includeChildBranches = m['includeChildBranches'] != false;
        _branchIds
          ..clear()
          ..addAll(((m['branchIds'] as List?) ?? [])
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty));
        _inheritedBranchIds = ((m['inheritedBranchIds'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        _allDepartments = m['allDepartments'] == true;
        _includeChildDepartments = m['includeChildDepartments'] != false;
        _departmentIds
          ..clear()
          ..addAll(((m['departmentIds'] as List?) ?? [])
              .map((e) => e.toString())
              .where((s) => s.isNotEmpty));
        _inheritedDepartmentIds = ((m['inheritedDepartmentIds'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        _isAdminAccount = m['isAdmin'] == true;
        _roleLabel = m['role']?.toString();
        _loadingScope = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingScope = false);
      appNotification.showError(title: 'Lỗi', message: '$e');
    }
  }

  Future<void> _save() async {
    final id = _selectedUserId;
    if (id == null || !_canEdit) return;
    setState(() => _saving = true);
    try {
      final res = await _api.saveAccountDataScope(id, {
        'allBranches': _allBranches,
        'includeChildBranches': _includeChildBranches,
        'branchIds': _allBranches ? <String>[] : _branchIds.toList(),
        'allDepartments': _allDepartments,
        'includeChildDepartments': _includeChildDepartments,
        'departmentIds': _allDepartments ? <String>[] : _departmentIds.toList(),
      });
      if (!mounted) return;
      setState(() => _saving = false);
      if (res['isSuccess'] == true) {
        appNotification.showSuccess(
            title: 'Thành công',
            message: 'Đã lưu phạm vi dữ liệu tài khoản');
      } else {
        appNotification.showError(
            title: 'Lỗi',
            message: res['message']?.toString() ?? 'Không lưu được phạm vi');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      appNotification.showError(title: 'Lỗi', message: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingList) return const LoadingWidget();
    final isNarrow = MediaQuery.sizeOf(context).width < 840;
    if (isNarrow) {
      return Column(
        children: [
          _buildHintBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _accountDropdown(),
          ),
          Expanded(child: _buildScopeEditor()),
        ],
      );
    }
    return Row(
      children: [
        SizedBox(
          width: 280,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Color(0xFFE4E4E7))),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Tài khoản'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      TextField(
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: tr('Tìm tài khoản'),
                          isDense: true,
                          prefixIcon: const Icon(Icons.search, size: 18),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                        ),
                        onChanged: (v) => setState(() => _accountQuery = v),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredAccounts.length,
                    itemBuilder: (_, i) {
                      final a = _filteredAccounts[i];
                      final id = a['id']?.toString();
                      final selected = id == _selectedUserId;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor:
                            HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
                        title: Text(tr(_accountLabel(a)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          tr(_accountRole(a)),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF71717A)),
                        ),
                        onTap: id == null ? null : () => _selectUser(id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            children: [
              _buildHintBar(),
              Expanded(child: _buildScopeEditor()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountDropdown() {
    final ids = _accounts.map((a) => a['id']?.toString()).toSet();
    final value = ids.contains(_selectedUserId) ? _selectedUserId : null;
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr('Tài khoản'),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: _filteredAccounts.map((a) {
        final id = a['id']?.toString() ?? '';
        return DropdownMenuItem(
          value: id,
          child: Text(tr('${_accountLabel(a)} · ${_accountRole(a)}'),
              overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: (v) {
        if (v != null) _selectUser(v);
      },
    );
  }

  Widget _buildHintBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: const Color(0xFFF8FAFC),
      child: Text(
        tr('Chọn tài khoản rồi gán chi nhánh / phòng ban được xem dữ liệu chấm công, nhân sự, báo cáo. Trưởng chi nhánh / trưởng phòng vẫn xem đơn vị mình quản lý.'),
        style: const TextStyle(fontSize: 12, color: Color(0xFF52525B)),
      ),
    );
  }

  Widget _buildScopeEditor() {
    if (_selectedUserId == null) {
      return Center(
        child: Text(tr('Chọn tài khoản để thiết lập phạm vi dữ liệu'),
            style: const TextStyle(color: Color(0xFF71717A))),
      );
    }
    if (_loadingScope) return const LoadingWidget();

    return Column(
      children: [
        if (_isAdminAccount)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr('Tài khoản ${_roleLabel ?? 'Admin'} luôn xem toàn bộ dữ liệu cửa hàng. Phần gán dưới đây không giới hạn quyền này.'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E)),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              _scopeCard(
                title: 'Chi nhánh',
                icon: Icons.account_tree_outlined,
                allValue: _allBranches,
                onAllChanged: _canEdit
                    ? (v) => setState(() => _allBranches = v)
                    : null,
                includeChildren: _includeChildBranches,
                onIncludeChanged: _canEdit
                    ? (v) => setState(() => _includeChildBranches = v)
                    : null,
                includeLabel: 'Kèm chi nhánh con',
                items: _branches,
                selected: _branchIds,
                inherited: _inheritedBranchIds.toSet(),
                enabled: _canEdit && !_allBranches,
              ),
              const SizedBox(height: 12),
              _scopeCard(
                title: 'Phòng ban',
                icon: Icons.business_outlined,
                allValue: _allDepartments,
                onAllChanged: _canEdit
                    ? (v) => setState(() => _allDepartments = v)
                    : null,
                includeChildren: _includeChildDepartments,
                onIncludeChanged: _canEdit
                    ? (v) => setState(() => _includeChildDepartments = v)
                    : null,
                includeLabel: 'Kèm phòng ban con',
                items: _departments,
                selected: _departmentIds,
                inherited: _inheritedDepartmentIds.toSet(),
                enabled: _canEdit && !_allDepartments,
              ),
            ],
          ),
        ),
        if (_canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 18),
                label: Text(tr(_saving ? 'Đang lưu...' : 'Lưu phạm vi')),
                style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy),
              ),
            ),
          ),
      ],
    );
  }

  Widget _scopeCard({
    required String title,
    required IconData icon,
    required bool allValue,
    required ValueChanged<bool>? onAllChanged,
    required bool includeChildren,
    required ValueChanged<bool>? onIncludeChanged,
    required String includeLabel,
    required List<Map<String, dynamic>> items,
    required Set<String> selected,
    required Set<String> inherited,
    required bool enabled,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Icon(icon, size: 18, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr(title),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14))),
                Text(tr('Tất cả'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF52525B))),
                Switch(
                  value: allValue,
                  onChanged: onAllChanged,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(tr(includeLabel), style: const TextStyle(fontSize: 13)),
            value: includeChildren,
            onChanged: onIncludeChanged == null
                ? null
                : (v) => onIncludeChanged(v ?? true),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const Divider(height: 1),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr('Chưa có $title'),
                  style: const TextStyle(color: Color(0xFF71717A))),
            )
          else
            ...items.map((item) {
              final id = item['id']?.toString() ?? '';
              final level = (item['_level'] as int?) ?? 0;
              final name = item['name']?.toString() ?? '';
              final isInherited = inherited.contains(id);
              return CheckboxListTile(
                dense: true,
                enabled: enabled,
                contentPadding: EdgeInsets.only(left: 8.0 + level * 16, right: 8),
                title: Row(
                  children: [
                    Expanded(
                        child: Text(tr(name),
                            style: const TextStyle(fontSize: 13))),
                    if (isInherited)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(tr('Trưởng'),
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF4338CA))),
                      ),
                  ],
                ),
                value: allValue || selected.contains(id),
                onChanged: !enabled
                    ? null
                    : (v) => setState(() {
                          if (v == true) {
                            selected.add(id);
                          } else {
                            selected.remove(id);
                          }
                        }),
                controlAffinity: ListTileControlAffinity.leading,
              );
            }),
        ],
      ),
    );
  }
}
