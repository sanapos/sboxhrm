import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import 'system_admin_helpers.dart';
import '../../utils/responsive_helper.dart';

class AuditTab extends StatefulWidget {
  const AuditTab({super.key});

  @override
  State<AuditTab> createState() => AuditTabState();
}

class AuditTabState extends State<AuditTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _auditLogs = [];
  List<Map<String, dynamic>> _filteredLogs = [];
  bool _isLoading = false;

  final _searchCtrl = TextEditingController();
  String? _actionFilter;

  // Pagination state
  int _currentPage = 1;
  final int _pageSize = 50;
  int _totalCount = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getAuditLogs(
        page: _currentPage,
        pageSize: _pageSize,
        action: _actionFilter,
      );
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = res['data'];
        _auditLogs = AdminHelpers.extractList(data);
        if (data is Map) {
          _totalCount = (data['total'] ?? data['totalCount'] ?? _auditLogs.length) as int;
          _totalPages = (data['totalPages'] ?? (_totalCount / _pageSize).ceil()) as int;
        } else {
          _totalCount = _auditLogs.length;
          _totalPages = 1;
        }
        _applyFilters();
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      debugPrint('AuditTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilters() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredLogs = _auditLogs.where((l) {
        final desc = (l['description'] ?? l['entityType'] ?? '')
            .toString()
            .toLowerCase();
        final user = (l['userName'] ?? l['userEmail'] ?? '')
            .toString()
            .toLowerCase();
        final matchSearch = query.isEmpty ||
            desc.contains(query) ||
            user.contains(query);

        final action = (l['action'] ?? l['actionType'] ?? '')
            .toString()
            .toLowerCase();
        final matchAction = _actionFilter == null ||
            action == _actionFilter!.toLowerCase();

        return matchSearch && matchAction;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final actionMap = <String, int>{};
    for (final l in _auditLogs) {
      final a =
          (l['action'] ?? l['actionType'] ?? 'Unknown').toString();
      actionMap[a] = (actionMap[a] ?? 0) + 1;
    }
    final actions = actionMap.keys.toList()..sort();

    return Column(
      children: [
        _buildToolbar(actions, actionMap),
        Expanded(
          child: _filteredLogs.isEmpty
              ? AdminHelpers.emptyState(Icons.history,
                  _searchCtrl.text.isNotEmpty
                      ? 'Không tìm thấy nhật ký'
                      : 'Chưa có nhật ký hoạt động')
              : Responsive.isMobile(context)
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _filteredLogs.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: _buildAuditDeckItem(_filteredLogs[i]),
                      ),
                    ),
                  )
                : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _filteredLogs.length,
                  itemBuilder: (ctx, i) =>
                      _buildAuditRow(_filteredLogs[i]),
                ),
        ),
        if (_totalPages > 1 && !Responsive.isMobile(context)) _buildPagination(),
      ],
    );
  }

  Widget _buildToolbar(
      List<String> actions, Map<String, int> actionMap) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          AdminHelpers.searchBar(
            controller: _searchCtrl,
            hint: 'Tìm nhật ký theo mô tả, người dùng...',
            onChanged: _applyFilters,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _actionFilter,
                    hint: const Text('Loại hành động',
                        style: TextStyle(fontSize: 13)),
                    items: [
                      const DropdownMenuItem(
                          value: null,
                          child: Text('Tất cả',
                              style: TextStyle(fontSize: 13))),
                      ...actions.map((a) => DropdownMenuItem(
                          value: a,
                          child: Text('$a (${actionMap[a]})',
                              style: const TextStyle(fontSize: 13)))),
                    ],
                    onChanged: (v) {
                      _actionFilter = v;
                      _currentPage = 1;
                      loadData();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              AdminHelpers.countBadge(
                  'Tổng', _totalCount, AdminHelpers.primary),
              const SizedBox(width: 8),
              ...actionMap.entries.take(5).map((e) {
                final color = switch (e.key.toLowerCase()) {
                  'create' => AdminHelpers.success,
                  'update' => AdminHelpers.info,
                  'delete' => AdminHelpers.danger,
                  'login' => AdminHelpers.primaryDark,
                  _ => Colors.grey,
                };
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdminHelpers.countBadge(e.key, e.value, color),
                );
              }),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 0,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    _currentPage = 1;
                    loadData();
                  }
                : null,
            icon: const Icon(Icons.first_page, size: 20),
            tooltip: 'Trang đầu',
          ),
          IconButton(
            onPressed: _currentPage > 1
                ? () {
                    _currentPage--;
                    loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_left, size: 20),
            tooltip: 'Trang trước',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Trang $_currentPage / $_totalPages',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () {
                    _currentPage++;
                    loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_right, size: 20),
            tooltip: 'Trang sau',
          ),
          IconButton(
            onPressed: _currentPage < _totalPages
                ? () {
                    _currentPage = _totalPages;
                    loadData();
                  }
                : null,
            icon: const Icon(Icons.last_page, size: 20),
            tooltip: 'Trang cuối',
          ),
          if (!isMobile) const SizedBox(width: 16),
          Text(
            'Hiển thị ${(_currentPage - 1) * _pageSize + 1}-${(_currentPage * _pageSize).clamp(0, _totalCount)} / $_totalCount',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditDeckItem(Map<String, dynamic> log) {
    final action = log['action'] ?? log['actionType'] ?? '';
    final Color actionColor = switch (action.toString().toLowerCase()) {
      'create' => AdminHelpers.success,
      'update' => AdminHelpers.info,
      'delete' => AdminHelpers.danger,
      'login' => AdminHelpers.primaryDark,
      _ => Colors.grey,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: actionColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(
            action.toString().toLowerCase() == 'create' ? Icons.add
                : action.toString().toLowerCase() == 'delete' ? Icons.delete
                : action.toString().toLowerCase() == 'login' ? Icons.login
                : Icons.edit,
            color: actionColor, size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(log['description'] ?? log['entityType'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text([action.toString(), log['userName'] ?? log['userEmail'] ?? ''].where((s) => s.isNotEmpty).join(' \u00b7 '),
              style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Text(AdminHelpers.formatDate(log['createdAt'] ?? log['timestamp']),
          style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
      ]),
    );
  }

  Widget _buildAuditRow(Map<String, dynamic> log) {
    final action = log['action'] ?? log['actionType'] ?? '';
    final Color actionColor = switch (action.toString().toLowerCase()) {
      'create' => AdminHelpers.success,
      'update' => AdminHelpers.info,
      'delete' => AdminHelpers.danger,
      'login' => AdminHelpers.primaryDark,
      _ => Colors.grey,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AdminHelpers.cardDecoration(borderColor: actionColor),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6)),
          child: Icon(
            action.toString().toLowerCase() == 'create'
                ? Icons.add
                : action.toString().toLowerCase() == 'delete'
                    ? Icons.delete
                    : action.toString().toLowerCase() == 'login'
                        ? Icons.login
                        : Icons.edit,
            color: actionColor,
            size: 14,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    log['description'] ?? log['entityType'] ?? 'N/A',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                Row(children: [
                  AdminHelpers.statusChip(
                      action.toString(), actionColor),
                  if (log['userName'] != null ||
                      log['userEmail'] != null) ...[
                    const SizedBox(width: 6),
                    Text(
                        log['userName'] ?? log['userEmail'] ?? '',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600])),
                  ],
                ]),
              ]),
        ),
        Text(
            AdminHelpers.formatDate(
                log['createdAt'] ?? log['timestamp']),
            style:
                TextStyle(fontSize: 11, color: Colors.grey[500])),
      ]),
    );
  }
}
