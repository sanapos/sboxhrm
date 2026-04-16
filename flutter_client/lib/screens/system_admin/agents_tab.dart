import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';

class AgentsTab extends StatefulWidget {
  const AgentsTab({super.key});

  @override
  State<AgentsTab> createState() => AgentsTabState();
}

class AgentsTabState extends State<AgentsTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _filteredAgents = [];
  bool _isLoading = false;

  final _searchCtrl = TextEditingController();
  bool? _activeFilter;
  int _currentPage = 1;
  final int _pageSize = 20;

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

  List<Map<String, dynamic>> get agents => _agents;

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getSystemAgents();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        _agents = AdminHelpers.extractList(res['data']);
        _applyFilters();
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      debugPrint('AgentsTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilters() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredAgents = _agents.where((a) {
        final name = (a['name'] ?? '').toString().toLowerCase();
        final code = (a['code'] ?? '').toString().toLowerCase();
        final email = (a['email'] ?? '').toString().toLowerCase();
        final phone = (a['phone'] ?? '').toString().toLowerCase();
        final matchSearch = query.isEmpty ||
            name.contains(query) ||
            code.contains(query) ||
            email.contains(query) ||
            phone.contains(query);

        final isActive = a['isActive'] as bool? ?? true;
        final matchActive =
            _activeFilter == null || isActive == _activeFilter;

        return matchSearch && matchActive;
      }).toList();
      _currentPage = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _filteredAgents.isEmpty
              ? AdminHelpers.emptyState(Icons.support_agent,
                  _searchCtrl.text.isNotEmpty
                      ? 'Không tìm thấy đại lý'
                      : 'Chưa có đại lý')
              : _buildPaginatedList(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final activeCount =
        _agents.where((a) => a['isActive'] == true).length;
    final totalStores = _agents.fold<int>(
        0,
        (sum, a) =>
            sum +
            ((a['storeCount'] ?? a['totalStores'] ?? 0) as num).toInt());

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          AdminHelpers.searchBar(
            controller: _searchCtrl,
            hint: 'Tìm đại lý theo tên, mã, email...',
            onChanged: _applyFilters,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
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
                  child: DropdownButton<bool?>(
                    value: _activeFilter,
                    hint: const Text('Trạng thái',
                        style: TextStyle(fontSize: 13)),
                    items: const [
                      DropdownMenuItem(
                          value: null,
                          child: Text('Tất cả',
                              style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: true,
                          child: Text('Hoạt động',
                              style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(
                          value: false,
                          child:
                              Text('Tắt', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (v) {
                      _activeFilter = v;
                      _applyFilters();
                    },
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showCreateAgentDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm đại lý'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AdminHelpers.warning,
                    foregroundColor: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              AdminHelpers.countBadge(
                  'Tổng', _agents.length, AdminHelpers.warning),
              const SizedBox(width: 8),
              AdminHelpers.countBadge(
                  'Hoạt động', activeCount, AdminHelpers.success),
              const SizedBox(width: 8),
              AdminHelpers.countBadge(
                  'Cửa hàng quản lý', totalStores, AdminHelpers.primary),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginatedList() {
    final isMobile = Responsive.isMobile(context);
    final totalCount = _filteredAgents.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = isMobile ? 0 : (page - 1) * _pageSize;
    final endIndex = isMobile ? totalCount : (page * _pageSize).clamp(0, totalCount);
    final paginatedItems = _filteredAgents.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: Responsive.isMobile(context)
            ? ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: paginatedItems.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: _buildAgentDeckItem(paginatedItems[i]),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: paginatedItems.length,
                itemBuilder: (ctx, i) => _buildAgentCard(paginatedItems[i]),
              ),
        ),
        if (totalPages > 1 && !isMobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hiển thị ${startIndex + 1}-$endIndex / $totalCount', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Row(children: [
                  IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: page > 1 ? () => setState(() => _currentPage--) : null, visualDensity: VisualDensity.compact),
                  Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: page < totalPages ? () => setState(() => _currentPage++) : null, visualDensity: VisualDensity.compact),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAgentDeckItem(Map<String, dynamic> agent) {
    final isActive = agent['isActive'] as bool? ?? true;
    final name = agent['name']?.toString() ?? '';
    final code = agent['code']?.toString() ?? '';
    final email = agent['email']?.toString() ?? '';

    return InkWell(
      onTap: () => _showEditAgentDialog(agent),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF1E3A5F),
            child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([code, email].where((s) => s.isNotEmpty).join(' \u00b7 '), style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isActive ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(isActive ? 'H\u0110' : 'T\u1eaft', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isActive ? Colors.green : Colors.red)),
          ),
        ]),
      ),
    );
  }

  Widget _buildAgentCard(Map<String, dynamic> agent) {
    final isActive = agent['isActive'] as bool? ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AdminHelpers.cardDecoration(
        borderColor: isActive ? AdminHelpers.warning : Colors.grey,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: AdminHelpers.warning.withValues(alpha: 0.1),
          child: Text(
            (agent['name'] ?? 'A').toString().substring(0, 1).toUpperCase(),
            style: const TextStyle(
                color: AdminHelpers.warning, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(agent['name'] ?? 'N/A',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (agent['email'] != null)
                Text(agent['email'],
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[600])),
              if (agent['code'] != null)
                Text('Mã: ${agent['code']}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500])),
              if (agent['phone'] != null)
                Text('SĐT: ${agent['phone']}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 4),
              Row(children: [
                AdminHelpers.statusChip(isActive ? 'Hoạt động' : 'Tắt',
                    isActive ? AdminHelpers.success : Colors.grey),
                const SizedBox(width: 6),
                AdminHelpers.statusChip(
                    '${agent['storeCount'] ?? agent['totalStores'] ?? 0} stores',
                    AdminHelpers.primary),
                if (agent['maxStores'] != null) ...[
                  const SizedBox(width: 6),
                  AdminHelpers.statusChip(
                      'Max: ${agent['maxStores']}', AdminHelpers.info),
                ],
              ]),
            ]),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.grey[400]),
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'token',
                child: Row(children: [
                  Icon(Icons.refresh, size: 16),
                  SizedBox(width: 8),
                  Text('Tạo lại token')
                ])),
            const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit, size: 16),
                  SizedBox(width: 8),
                  Text('Sửa')
                ])),
          ],
          onSelected: (v) {
            if (v == 'token') _regenerateToken(agent);
            if (v == 'edit') _showEditAgentDialog(agent);
          },
        ),
      ),
    );
  }

  Future<void> _regenerateToken(Map<String, dynamic> agent) async {
    final res = await _apiService.regenerateAgentToken(
        agentId: agent['id']?.toString());
    if (mounted && res['isSuccess'] == true) {
      final newToken =
          res['data']?['registrationToken'] ?? res['data']?['token'] ?? '';
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Token mới'),
          content:
              Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Token đăng ký đại lý:',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8)),
              child: SelectableText(newToken.toString(),
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                    ClipboardData(text: newToken.toString()));
                NotificationOverlayManager().showSuccess(title: 'Sao chép', message: 'Đã sao chép');
              },
              child: const Text('Sao chép'),
            ),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng')),
          ],
        ),
      );
    }
  }

  void _showCreateAgentDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm đại lý'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AdminHelpers.dialogField(nameCtrl, 'Tên đại lý', Icons.person),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(codeCtrl, 'Mã đại lý', Icons.tag),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(emailCtrl, 'Email', Icons.email),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                phoneCtrl, 'Số điện thoại', Icons.phone),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final res = await _apiService.createAgent(
                  name: nameCtrl.text,
                  code: codeCtrl.text,
                  email: emailCtrl.text,
                  phone: phoneCtrl.text);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                loadData();
                if (mounted) {
                  AdminHelpers.showSuccess(
                      context, 'Tạo đại lý thành công');
                }
              } else {
                if (mounted) AdminHelpers.showApiError(context, res);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.warning),
            child: const Text('Tạo'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      codeCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
    });
  }

  void _showEditAgentDialog(Map<String, dynamic> agent) {
    final nameCtrl =
        TextEditingController(text: agent['name'] ?? '');
    final phoneCtrl =
        TextEditingController(text: agent['phone'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa đại lý'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AdminHelpers.dialogField(
                nameCtrl, 'Tên đại lý', Icons.person),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                phoneCtrl, 'Số điện thoại', Icons.phone),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              await _apiService.updateAgent(
                  id: agent['id']?.toString(),
                  name: nameCtrl.text,
                  phone: phoneCtrl.text);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              loadData();
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
    });
  }
}
