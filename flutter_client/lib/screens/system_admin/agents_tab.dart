import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/admin/admin_mobile_widgets.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/hrm_page_chrome.dart';
import 'system_admin_helpers.dart';
import '../../utils/web_route_parser.dart';

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
        0, (sum, a) => sum + AdminHelpers.agentTotalStores(a));

    final statsRow = AdminMobileStatRow(children: [
      AdminHelpers.countBadge('Tổng', _agents.length, AdminHelpers.warning),
      const SizedBox(width: 8),
      AdminHelpers.countBadge('Hoạt động', activeCount, AdminHelpers.success),
      const SizedBox(width: 8),
      AdminHelpers.countBadge(
          'Cửa hàng đăng ký', totalStores, AdminHelpers.primary),
    ]);

    if (adminUseMobileLayout(context)) {
      return AdminMobileListToolbar(
        searchController: _searchCtrl,
        searchHint: 'Tìm đại lý theo tên, mã, email...',
        onSearchChanged: _applyFilters,
        activeFilterCount: _activeFilter != null ? 1 : 0,
        onRefresh: loadData,
        onOpenFilters: () => showAdminFilterSheet(
          context,
          onApply: _applyFilters,
          onClear: () {
            setState(() => _activeFilter = null);
            _applyFilters();
          },
          child: _buildStatusFilter(fullWidth: true),
        ),
        onCreate:
            context.systemAdminCanCreate ? _showCreateAgentDialog : null,
        createLabel: 'Thêm đại lý',
        stats: statsRow,
      );
    }

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
              _buildStatusFilter(),
              if (context.systemAdminCanCreate)
                FilledButton.icon(
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
          statsRow,
        ],
      ),
    );
  }

  Widget _buildStatusFilter({bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<bool?>(
          isExpanded: fullWidth,
          value: _activeFilter,
          hint: const Text('Trạng thái', style: TextStyle(fontSize: 13)),
          items: const [
            DropdownMenuItem(
                value: null,
                child: Text('Tất cả', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(
                value: true,
                child: Text('Hoạt động', style: TextStyle(fontSize: 13))),
            DropdownMenuItem(
                value: false, child: Text('Tắt', style: TextStyle(fontSize: 13))),
          ],
          onChanged: (v) {
            _activeFilter = v;
            _applyFilters();
          },
        ),
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
      onTap: () {
        if (adminUseMobileLayout(context)) {
          _showAgentMobileActions(agent);
        } else {
          _showEditAgentDialog(agent);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: HrmPageChrome.primaryNavy,
            child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([code, email].where((s) => s.isNotEmpty).join(' \u00b7 '), style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                'ĐK: ${AdminHelpers.agentTotalStores(agent)} · '
                'Kích hoạt: ${AdminHelpers.agentActivatedStores(agent)} · '
                'D.thử: ${AdminHelpers.agentTrialStores(agent)} · '
                'Key còn: ${AdminHelpers.agentAvailableKeys(agent)} · '
                'Quỹ GH: ${AdminHelpers.agentRenewalBalance(agent)}d',
                style: TextStyle(
                  fontSize: 11,
                  color: AdminHelpers.agentRenewalBalance(agent) <= 0
                      ? AdminHelpers.warning
                      : const Color(0xFF7C3AED),
                ),
              ),
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

  Future<void> _showAgentMobileActions(Map<String, dynamic> agent) async {
    final name = agent['name']?.toString() ?? 'Đại lý';
    final code = agent['code']?.toString() ?? '';
    final canEdit = context.systemAdminCanEdit;

    final actions = <AdminActionSheetItem>[
      AdminActionSheetItem(
        icon: Icons.visibility_outlined,
        label: 'Xem thông tin',
        onTap: () => _showEditAgentDialog(agent, readOnly: !canEdit),
      ),
      AdminActionSheetItem(
        icon: Icons.link,
        label: 'Link đăng ký cửa hàng',
        onTap: () => _showAgentStoreReferralLink(code.trim().toUpperCase()),
      ),
    ];

    if (canEdit) {
      actions.addAll([
        AdminActionSheetItem(
          icon: Icons.edit,
          label: 'Sửa đại lý',
          onTap: () => _showEditAgentDialog(agent),
        ),
        AdminActionSheetItem(
          icon: Icons.calendar_month,
          label: 'Cấp quỹ gia hạn',
          color: const Color(0xFF7C3AED),
          onTap: () => _showAdjustRenewalBalanceDialog(agent),
        ),
        AdminActionSheetItem(
          icon: Icons.refresh,
          label: 'Tạo lại token đăng ký',
          onTap: () => _regenerateToken(agent),
        ),
      ]);
      if (context.systemAdminCanDelete) {
        actions.add(AdminActionSheetItem(
          icon: Icons.delete_outline,
          label: 'Xóa đại lý',
          color: AdminHelpers.danger,
          onTap: () => _deleteAgent(agent),
        ));
      }
    }

    await showAdminActionSheet(
      context,
      title: name,
      subtitle: code.isNotEmpty ? 'Mã: $code' : null,
      actions: actions,
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
              if (agent['phone'] != null)
                Text('SĐT Zalo: ${agent['phone']}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500])),
              if (agent['address'] != null &&
                  agent['address'].toString().isNotEmpty)
                Text('Địa chỉ: ${agent['address']}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500])),
              if (agent['code'] != null)
                Text('Mã: ${agent['code']}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(height: 4),
              _buildAgentStatChips(agent),
            ]),
        trailing: context.systemAdminCanEdit
            ? PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: Colors.grey[400]),
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'referral',
                child: Row(children: [
                  Icon(Icons.link, size: 16),
                  SizedBox(width: 8),
                  Text('Link đăng ký cửa hàng')
                ])),
            const PopupMenuItem(
                value: 'renewal',
                child: Row(children: [
                  Icon(Icons.calendar_month, size: 16, color: Color(0xFF7C3AED)),
                  SizedBox(width: 8),
                  Text('Cấp quỹ gia hạn')
                ])),
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
            if (context.systemAdminCanDelete)
              const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 16, color: AdminHelpers.danger),
                    SizedBox(width: 8),
                    Text('Xóa đại lý', style: TextStyle(color: AdminHelpers.danger))
                  ])),
          ],
          onSelected: (v) {
            if (v == 'referral') {
              _showAgentStoreReferralLink(
                  agent['code']?.toString().trim().toUpperCase() ?? '');
            }
            if (v == 'token') _regenerateToken(agent);
            if (v == 'renewal') _showAdjustRenewalBalanceDialog(agent);
            if (v == 'edit') _showEditAgentDialog(agent);
            if (v == 'delete') _deleteAgent(agent);
          },
        )
            : IconButton(
                icon: Icon(Icons.visibility_outlined, color: Colors.grey[400]),
                onPressed: () => _showEditAgentDialog(agent, readOnly: true),
              ),
      ),
    );
  }

  Widget _buildAgentStatsSummary(Map<String, dynamic> agent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Thống kê',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Text(
            'Cửa hàng đăng ký: ${AdminHelpers.agentTotalStores(agent)} · '
            'Đã kích hoạt: ${AdminHelpers.agentActivatedStores(agent)} · '
            'Dùng thử: ${AdminHelpers.agentTrialStores(agent)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          if (AdminHelpers.agentLockedStores(agent) > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Khóa: ${AdminHelpers.agentLockedStores(agent)} cửa hàng',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'License key: còn ${AdminHelpers.agentAvailableKeys(agent)} · '
            'đã dùng ${AdminHelpers.agentUsedKeys(agent)} · '
            'tổng ${AdminHelpers.agentTotalKeys(agent)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentStatChips(Map<String, dynamic> agent) {
    final isActive = agent['isActive'] as bool? ?? true;
    final registered = AdminHelpers.agentTotalStores(agent);
    final activated = AdminHelpers.agentActivatedStores(agent);
    final trial = AdminHelpers.agentTrialStores(agent);
    final lockedStores = AdminHelpers.agentLockedStores(agent);
    final availableKeys = AdminHelpers.agentAvailableKeys(agent);
    final usedKeys = AdminHelpers.agentUsedKeys(agent);
    final totalKeys = AdminHelpers.agentTotalKeys(agent);
    final renewalBalance = AdminHelpers.agentRenewalBalance(agent);

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        AdminHelpers.statusChip(
          isActive ? 'Hoạt động' : 'Tắt',
          isActive ? AdminHelpers.success : Colors.grey,
        ),
        AdminHelpers.statusChip(
          'ĐK: $registered',
          AdminHelpers.primary,
        ),
        AdminHelpers.statusChip(
          'Kích hoạt: $activated',
          AdminHelpers.success,
        ),
        AdminHelpers.statusChip(
          'D.thử: $trial',
          const Color(0xFF7C3AED),
        ),
        if (lockedStores > 0)
          AdminHelpers.statusChip(
            '$lockedStores khóa',
            AdminHelpers.warning,
          ),
        if (totalKeys > 0)
          AdminHelpers.statusChip(
            'Key: $availableKeys còn · $usedKeys đã dùng',
            AdminHelpers.info,
          ),
        AdminHelpers.statusChip(
          'Quỹ GH: ${renewalBalance}d',
          renewalBalance > 0
              ? const Color(0xFF7C3AED)
              : AdminHelpers.warning,
        ),
      ],
    );
  }

  Future<void> _deleteAgent(Map<String, dynamic> agent) async {
    final name = agent['name']?.toString() ?? 'Đại lý';
    final storeCount = AdminHelpers.agentTotalStores(agent);
    if (storeCount > 0) {
      AdminHelpers.showError(
          context, 'Không thể xóa. Đại lý đang quản lý $storeCount cửa hàng');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Xác nhận xóa đại lý'),
        content: Text(
            'Bạn có chắc muốn xóa đại lý "$name"?\n\nTài khoản đăng nhập cổng đại lý (nếu có) cũng sẽ bị xóa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminHelpers.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final res =
        await _apiService.deleteAgent(agent['id']?.toString() ?? '');
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã xóa đại lý $name');
      loadData();
    } else {
      AdminHelpers.showError(context, res['message'] ?? 'Không xóa được đại lý');
    }
  }

  Future<void> _regenerateToken(Map<String, dynamic> agent) async {
    final res = await _apiService.regenerateAgentToken(
        agentId: agent['id']?.toString());
    if (mounted && res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      final regLink = data?['registrationLink']?.toString() ?? '';
      if (regLink.isNotEmpty) {
        _showAgentAccountRegistrationLink(regLink);
        return;
      }
      final newToken =
          data?['registrationToken'] ?? data?['token'] ?? '';
      showDialog(
        context: context,
        builder: (ctx) => ScrollableAlertDialog(
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
            FilledButton(
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
    final addressCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => ScrollableAlertDialog(
        title: const Text('Thêm đại lý'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AdminHelpers.dialogField(nameCtrl, 'Tên đại lý', Icons.person),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(codeCtrl, 'Mã đại lý', Icons.tag),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(emailCtrl, 'Email đăng nhập cổng đại lý', Icons.email),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(phoneCtrl, 'SĐT hỗ trợ Zalo', Icons.phone),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(addressCtrl, 'Địa chỉ', Icons.location_on),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu (tuỳ chọn)',
                  helperText:
                      'Tạo tài khoản cổng đại lý (Agent), không phải SuperAdmin. Bỏ trống để gửi link tự đăng ký.',
                  helperMaxLines: 3,
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          FilledButton(
            onPressed: saving ? null : () async {
              final pwd = passwordCtrl.text.trim();
              if (nameCtrl.text.trim().isEmpty) {
                AdminHelpers.showError(context, 'Vui lòng nhập tên đại lý');
                return;
              }
              if (codeCtrl.text.trim().isEmpty) {
                AdminHelpers.showError(context, 'Vui lòng nhập mã đại lý');
                return;
              }
              if (pwd.isNotEmpty && emailCtrl.text.trim().isEmpty) {
                AdminHelpers.showError(context, 'Cần nhập email khi đặt mật khẩu');
                return;
              }
              if (pwd.isNotEmpty && pwd.length < 6) {
                AdminHelpers.showError(context, 'Mật khẩu tối thiểu 6 ký tự');
                return;
              }
              setSt(() => saving = true);
              final res = await _apiService.createAgent(
                  name: nameCtrl.text,
                  code: codeCtrl.text,
                  email: emailCtrl.text,
                  phone: phoneCtrl.text,
                  address: addressCtrl.text,
                  password: pwd.isEmpty ? null : pwd);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                loadData();
                if (mounted) {
                  final hasCreds = pwd.isNotEmpty;
                  final data = res['data'] as Map<String, dynamic>?;
                  final agentCode = (data?['code'] ?? codeCtrl.text)
                      .toString()
                      .trim()
                      .toUpperCase();
                  AdminHelpers.showSuccess(
                      context,
                      hasCreds
                          ? 'Đã tạo đại lý + tài khoản đăng nhập'
                          : 'Tạo đại lý thành công. Gửi link đăng ký tài khoản đại lý.');
                  _showAgentLinksAfterCreate(
                    agentCode: agentCode,
                    agentAccountLink: hasCreds
                        ? null
                        : data?['registrationLink']?.toString(),
                  );
                }
              } else {
                if (mounted) AdminHelpers.showApiError(context, res);
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.warning),
            child: saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Tạo'),
          ),
        ],
      ),
      ),
    ).then((_) {
      nameCtrl.dispose();
      codeCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
      passwordCtrl.dispose();
    });
  }

  String _buildStoreReferralLink(String agentCode) {
    if (agentCode.isEmpty) return '';
    return '${webAppBaseUrl(ApiService.baseUrl)}/#/register?agentCode=$agentCode';
  }

  void _showAgentLinksAfterCreate({
    required String agentCode,
    String? agentAccountLink,
  }) {
    final storeLink = _buildStoreReferralLink(agentCode);
    if (storeLink.isEmpty && (agentAccountLink == null || agentAccountLink.isEmpty)) {
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Link đại lý'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (storeLink.isNotEmpty) ...[
              const Text(
                'Link đăng ký cửa hàng (gửi cho khách hàng):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Khách đăng ký qua link này, cửa hàng sẽ tự gán cho đại lý.',
                style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
              ),
              const SizedBox(height: 8),
              _linkBox(storeLink),
              const SizedBox(height: 16),
            ],
            if (agentAccountLink != null && agentAccountLink.isNotEmpty) ...[
              const Text(
                'Link đăng ký tài khoản đại lý:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Gửi cho đại lý để họ tự tạo tài khoản đăng nhập cổng đại lý.',
                style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
              ),
              const SizedBox(height: 8),
              _linkBox(agentAccountLink),
            ],
          ],
        ),
        actions: [
          if (storeLink.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: storeLink));
                NotificationOverlayManager().showSuccess(
                    title: 'Sao chép', message: 'Đã sao chép link cửa hàng');
              },
              child: const Text('Sao chép link cửa hàng'),
            ),
          if (agentAccountLink != null && agentAccountLink.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: agentAccountLink));
                NotificationOverlayManager().showSuccess(
                    title: 'Sao chép', message: 'Đã sao chép link tài khoản');
              },
              child: const Text('Sao chép link tài khoản'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _linkBox(String link) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(link,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
    );
  }

  void _showAgentAccountRegistrationLink(String link) {
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Link đăng ký tài khoản đại lý'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gửi link sau để đại lý tự tạo tài khoản đăng nhập cổng đại lý:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(link,
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              NotificationOverlayManager()
                  .showSuccess(title: 'Sao chép', message: 'Đã sao chép link');
            },
            child: const Text('Sao chép'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showAgentStoreReferralLink(String agentCode) {
    if (agentCode.isEmpty) {
      AdminHelpers.showError(context, 'Đại lý chưa có mã, không tạo được link');
      return;
    }
    final link = _buildStoreReferralLink(agentCode);
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Link đăng ký cửa hàng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gửi link sau cho đại lý. Cửa hàng đăng ký qua link này sẽ thuộc quyền quản lý của đại lý:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(link,
                  style: const TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: link));
              NotificationOverlayManager()
                  .showSuccess(title: 'Sao chép', message: 'Đã sao chép link');
            },
            child: const Text('Sao chép'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showAdjustRenewalBalanceDialog(Map<String, dynamic> agent) {
    final name = agent['name']?.toString() ?? 'Đại lý';
    final current = (agent['renewalDayBalance'] as num?)?.toInt() ?? 0;
    final addCtrl = TextEditingController(text: '500');
    final setCtrl = TextEditingController(text: current.toString());
    var modeAdd = true;
    var saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => ScrollableAlertDialog(
          title: Text('Quỹ gia hạn — $name'),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600
                ? MediaQuery.of(context).size.width - 32
                : 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hiện còn: $current ngày',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: true, label: Text('Cộng thêm')),
                    ButtonSegment(
                        value: false, label: Text('Đặt lại')),
                  ],
                  selected: {modeAdd},
                  onSelectionChanged: (s) =>
                      setSt(() => modeAdd = s.first),
                ),
                const SizedBox(height: 12),
                if (modeAdd)
                  AdminHelpers.dialogField(
                      addCtrl, 'Số ngày cộng thêm', Icons.add)
                else
                  AdminHelpers.dialogField(
                      setCtrl, 'Số dư mới (ngày)', Icons.edit),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final addDays = int.tryParse(addCtrl.text.trim());
                      final setBalance = int.tryParse(setCtrl.text.trim());
                      if (modeAdd) {
                        if (addDays == null || addDays <= 0) {
                          AdminHelpers.showError(
                              context, 'Số ngày cộng thêm không hợp lệ');
                          return;
                        }
                      } else {
                        if (setBalance == null || setBalance < 0) {
                          AdminHelpers.showError(
                              context, 'Số dư mới không hợp lệ');
                          return;
                        }
                      }
                      setSt(() => saving = true);
                      final res =
                          await _apiService.adjustAgentRenewalBalance(
                        agentId: agent['id']?.toString() ?? '',
                        addDays: modeAdd ? addDays : null,
                        setBalance: modeAdd ? null : setBalance,
                      );
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      if (res['isSuccess'] == true) {
                        AdminHelpers.showSuccess(
                            context, 'Đã cập nhật quỹ gia hạn');
                        loadData();
                      } else {
                        AdminHelpers.showApiError(context, res);
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED)),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Lưu'),
            ),
          ],
        ),
      ),
    ).then((_) {
      addCtrl.dispose();
      setCtrl.dispose();
    });
  }

  void _showEditAgentDialog(Map<String, dynamic> agent, {bool readOnly = false}) {
    final nameCtrl =
        TextEditingController(text: agent['name'] ?? '');
    final emailCtrl =
        TextEditingController(text: agent['email'] ?? '');
    final phoneCtrl =
        TextEditingController(text: agent['phone'] ?? '');
    final addressCtrl =
        TextEditingController(text: agent['address'] ?? '');
    final agentCode = agent['code']?.toString().trim().toUpperCase() ?? '';
    final storeLink = _buildStoreReferralLink(agentCode);
    final accountLink = agent['registrationLink']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(readOnly ? 'Thông tin đại lý' : 'Sửa đại lý'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            AdminHelpers.dialogField(
                nameCtrl, 'Tên đại lý', Icons.person, readOnly: readOnly),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                emailCtrl, 'Email liên hệ', Icons.email, readOnly: readOnly),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                phoneCtrl, 'SĐT hỗ trợ Zalo', Icons.phone, readOnly: readOnly),
            const SizedBox(height: 12),
            AdminHelpers.dialogField(
                addressCtrl, 'Địa chỉ', Icons.location_on, readOnly: readOnly),
            const SizedBox(height: 12),
            _buildAgentStatsSummary(agent),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month,
                      color: Color(0xFF7C3AED), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Quỹ gia hạn còn: ${agent['renewalDayBalance'] ?? 0} ngày',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  if (context.systemAdminCanEdit)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAdjustRenewalBalanceDialog(agent);
                      },
                      child: const Text('Cấp thêm'),
                    ),
                ],
              ),
            ),
            if (agentCode.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Link đăng ký cửa hàng',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              _linkBox(storeLink),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: storeLink));
                    NotificationOverlayManager().showSuccess(
                        title: 'Sao chép', message: 'Đã sao chép link cửa hàng');
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Sao chép'),
                ),
              ),
            ],
            if (accountLink != null && accountLink.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Link đăng ký tài khoản đại lý',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 6),
              _linkBox(accountLink),
            ],
          ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(readOnly ? 'Đóng' : 'Hủy')),
          if (!readOnly && context.systemAdminCanEdit)
            FilledButton(
              onPressed: () async {
              final res = await _apiService.updateAgent(
                  id: agent['id']?.toString(),
                  name: nameCtrl.text,
                  email: emailCtrl.text,
                  phone: phoneCtrl.text,
                  address: addressCtrl.text);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              if (res['isSuccess'] == true) {
                AdminHelpers.showSuccess(context, 'Đã cập nhật đại lý');
                loadData();
              } else {
                AdminHelpers.showApiError(context, res);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      addressCtrl.dispose();
    });
  }
}
