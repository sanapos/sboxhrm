import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/branch.dart';
import '../services/api_service.dart';
import '../providers/auth_provider.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

/// Màn hình Quản lý Chi nhánh
class BranchManagementScreen extends StatefulWidget {
  const BranchManagementScreen({super.key});

  @override
  State<BranchManagementScreen> createState() => _BranchManagementScreenState();
}

class _BranchManagementScreenState extends State<BranchManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();

  // Data
  List<Branch> _branches = [];
  List<BranchTreeNode> _branchTree = [];
  BranchStats? _stats;
  List<BranchSelect> _branchSelect = [];

  bool _loading = false;
  int _currentTab = 0;
  String _searchQuery = '';
  bool? _filterActive;
  bool _isManager = false;
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentTab = _tabController.index);
      _loadTabData(_tabController.index);
    });
    _checkRole();
    _loadTabData(0);
  }

  void _checkRole() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final role = auth.user?.role.toLowerCase() ?? '';
    _isManager = role == 'admin' || role == 'manager' || role == 'superadmin';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTabData(int tab) async {
    setState(() => _loading = true);
    try {
      switch (tab) {
        case 0:
          await Future.wait([_loadBranches(), _loadStats()]);
          break;
        case 1:
          await Future.wait([_loadBranchTree(), _loadStats()]);
          break;
        case 2:
          await _loadStats();
          break;
      }
    } catch (e) {
      debugPrint('Error loading tab $tab: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBranches() async {
    final resp = await _api.getBranches(search: _searchQuery.isNotEmpty ? _searchQuery : null, isActive: _filterActive);
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _branches = (resp['data'] as List)
          .map((b) => Branch.fromJson(b as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadBranchTree() async {
    final resp = await _api.getBranchTree();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _branchTree = (resp['data'] as List)
          .map((n) => BranchTreeNode.fromJson(n as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadStats() async {
    final resp = await _api.getBranchStats();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _stats = BranchStats.fromJson(resp['data'] as Map<String, dynamic>);
    }
  }

  Future<void> _loadBranchSelect() async {
    final resp = await _api.getBranchesForSelect();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _branchSelect = (resp['data'] as List)
          .map((b) => BranchSelect.fromJson(b as Map<String, dynamic>))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Quản lý Chi nhánh', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Danh sách'),
            Tab(icon: Icon(Icons.account_tree), text: 'Cây chi nhánh'),
            Tab(icon: Icon(Icons.analytics), text: 'Thống kê'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildListTab(),
                _buildTreeTab(),
                _buildStatsTab(),
              ],
            ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 1: DANH SÁCH CHI NHÁNH
  // ═══════════════════════════════════════════════════════════════

  Widget _buildListTab() {
    return RefreshIndicator(
      onRefresh: () => _loadTabData(0),
      child: Column(
        children: [
          _buildListHeader(),
          Expanded(
            child: _branches.isEmpty
                ? _buildEmptyState('Chưa có chi nhánh nào', 'Hãy tạo chi nhánh đầu tiên cho hệ thống.')
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _branches.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _buildBranchDeckItem(_branches[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildListHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // Title row
          Row(
            children: [
              Icon(Icons.business, color: theme.colorScheme.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quản lý Chi nhánh', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    Text('${_branches.length} chi nhánh', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                  ],
                ),
              ),
              if (_isManager)
                FilledButton.icon(
                  onPressed: () => _showBranchDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Thêm mới'),
                ),
              if (Responsive.isMobile(context))
                IconButton(
                  icon: Stack(
                    children: [
                      Icon(
                        _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                        color: _showMobileFilters ? Colors.orange : Colors.grey[600],
                      ),
                      if (_searchQuery.isNotEmpty || _filterActive != null)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
                ),
            ],
          ),
          if (!Responsive.isMobile(context) || _showMobileFilters) ...[
          const SizedBox(height: 8),
          // Search & filter
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm chi nhánh...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      _searchQuery = value;
                      _loadTabData(0);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Đang hoạt động'),
                selected: _filterActive == true,
                onSelected: (v) {
                  setState(() => _filterActive = v ? true : null);
                  _loadTabData(0);
                },
              ),
              const SizedBox(width: 4),
              FilterChip(
                label: const Text('Ngừng HĐ'),
                selected: _filterActive == false,
                onSelected: (v) {
                  setState(() => _filterActive = v ? false : null);
                  _loadTabData(0);
                },
              ),
            ],
          ),
          ], // end _showMobileFilters
        ],
      ),
    );
  }

  Widget _buildBranchDeckItem(Branch branch) {
    final isActive = branch.isActive;
    final color = branch.isHeadquarter ? Colors.amber.shade700 : (isActive ? Colors.blue : Colors.grey);

    return InkWell(
      onTap: () => _showBranchDetail(branch),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(branch.isHeadquarter ? Icons.domain : Icons.business, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(branch.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      branch.code,
                      if (branch.managerName != null) branch.managerName!,
                      '${branch.employeeCount} NV',
                      if (branch.fullAddress.isNotEmpty) branch.fullAddress,
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _buildStatusBadge(isActive, branch.isHeadquarter),
            if (_isManager)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Sửa')])),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Row(children: [
                      Icon(isActive ? Icons.block : Icons.check_circle, size: 16),
                      const SizedBox(width: 8),
                      Text(isActive ? 'Ngừng hoạt động' : 'Kích hoạt'),
                    ]),
                  ),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Xóa', style: TextStyle(color: Colors.red))])),
                ],
                onSelected: (action) {
                  switch (action) {
                    case 'edit': _showBranchDialog(branch: branch); break;
                    case 'toggle': _toggleBranchActive(branch); break;
                    case 'delete': _confirmDeleteBranch(branch); break;
                  }
                },
              )
            else
              const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  // Keep old card for desktop

  Widget _buildStatusBadge(bool isActive, bool isHQ) {
    if (isHQ) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star, size: 12, color: Colors.amber.shade700),
            const SizedBox(width: 4),
            Text('Trụ sở chính', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade700)),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isActive ? Colors.green.shade300 : Colors.red.shade300),
      ),
      child: Text(
        isActive ? 'Hoạt động' : 'Ngừng HĐ',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.green.shade700 : Colors.red.shade700),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 2: CÂY CHI NHÁNH
  // ═══════════════════════════════════════════════════════════════

  Widget _buildTreeTab() {
    return RefreshIndicator(
      onRefresh: () => _loadTabData(1),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.account_tree, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Cây Chi nhánh', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    for (var n in _branchTree) {
                      _toggleExpandAll(n, true);
                    }
                    setState(() {});
                  },
                  icon: const Icon(Icons.unfold_more, size: 18),
                  label: const Text('Mở tất cả'),
                ),
                TextButton.icon(
                  onPressed: () {
                    for (var n in _branchTree) {
                      _toggleExpandAll(n, false);
                    }
                    setState(() {});
                  },
                  icon: const Icon(Icons.unfold_less, size: 18),
                  label: const Text('Thu gọn'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_branchTree.isEmpty)
              _buildEmptyState('Chưa có dữ liệu cây chi nhánh', 'Hãy thêm các chi nhánh để hiển thị cây.')
            else
              ..._branchTree.map((node) => _buildTreeNode(node, 0)),
          ],
        ),
      ),
    );
  }

  void _toggleExpandAll(BranchTreeNode node, bool expand) {
    node.isExpanded = expand;
    for (var child in node.children) {
      _toggleExpandAll(child, expand);
    }
  }

  Widget _buildTreeNode(BranchTreeNode node, int depth) {
    final hasChildren = node.children.isNotEmpty;
    final color = node.isHeadquarter ? Colors.amber.shade700 : (node.isActive ? Colors.blue : Colors.grey);

    return Padding(
      padding: EdgeInsets.only(left: depth * 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: depth == 0 ? 3 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: color.withValues(alpha: 0.4), width: depth == 0 ? 2 : 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: hasChildren ? () => setState(() => node.isExpanded = !node.isExpanded) : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Expand icon
                    if (hasChildren)
                      Icon(
                        node.isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                        color: color,
                        size: 24,
                      )
                    else
                      const SizedBox(width: 24),
                    const SizedBox(width: 8),
                    // Branch icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        node.isHeadquarter ? Icons.domain : Icons.business,
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              ),
                              Text(node.code, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          if (node.address != null || node.city != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              [node.address, node.city].where((e) => e != null && e.isNotEmpty).join(', '),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Manager avatar
                    if (node.managerName != null)
                      Tooltip(
                        message: node.managerName!,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage: node.managerPhoto != null ? NetworkImage(node.managerPhoto!) : null,
                          onBackgroundImageError: node.managerPhoto != null ? (_, __) {} : null,
                          child: node.managerPhoto == null ? Text(node.managerName![0].toUpperCase(), style: const TextStyle(fontSize: 12)) : null,
                        ),
                      ),
                    const SizedBox(width: 8),
                    // Employee count
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people, size: 14, color: Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Text('${node.employeeCount}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                        ],
                      ),
                    ),
                    // Status
                    if (!node.isActive)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Ngừng', style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Children
          if (hasChildren && node.isExpanded)
            ...node.children.map((child) => _buildTreeNode(child, depth + 1)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 3: THỐNG KÊ
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStatsTab() {
    if (_stats == null) {
      return _buildEmptyState('Chưa có dữ liệu thống kê', 'Hãy thêm chi nhánh để xem thống kê.');
    }
    final s = _stats!;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => _loadTabData(2),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tổng quan Chi nhánh', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            // Stats cards
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildStatCardLarge('Tổng chi nhánh', s.totalBranches, Icons.business, Colors.blue),
                _buildStatCardLarge('Đang hoạt động', s.activeBranches, Icons.check_circle, Colors.green),
                _buildStatCardLarge('Ngừng hoạt động', s.inactiveBranches, Icons.block, Colors.red),
                _buildStatCardLarge('Trụ sở chính', s.headquarterCount, Icons.domain, Colors.amber.shade700),
                _buildStatCardLarge('Tổng nhân viên', s.totalEmployees, Icons.people, Colors.purple),
              ],
            ),
            const SizedBox(height: 24),
            // Ratio chart
            if (s.totalBranches > 0) ...[
              Text('Tỷ lệ hoạt động', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildRatioBar(s),
              const SizedBox(height: 24),
            ],
            // Average
            if (s.totalBranches > 0 && s.activeBranches > 0) ...[
              Text('Thông tin thêm', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _buildInfoRow('Trung bình NV/CN', (s.totalEmployees / s.activeBranches).toStringAsFixed(1), Icons.analytics),
                      const Divider(),
                      _buildInfoRow('Tỷ lệ hoạt động', '${(s.activeBranches / s.totalBranches * 100).toStringAsFixed(1)}%', Icons.pie_chart),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCardLarge(String label, int value, IconData icon, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildRatioBar(BranchStats s) {
    final activeRatio = s.totalBranches > 0 ? s.activeBranches / s.totalBranches : 0.0;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  flex: s.activeBranches,
                  child: Container(
                    color: Colors.green,
                    alignment: Alignment.center,
                    child: s.activeBranches > 0
                        ? Text('${s.activeBranches}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))
                        : null,
                  ),
                ),
                if (s.inactiveBranches > 0)
                  Expanded(
                    flex: s.inactiveBranches,
                    child: Container(
                      color: Colors.red.shade400,
                      alignment: Alignment.center,
                      child: Text('${s.inactiveBranches}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _legendDot(Colors.green, 'Hoạt động (${(activeRatio * 100).toStringAsFixed(0)}%)'),
            const SizedBox(width: 16),
            _legendDot(Colors.red.shade400, 'Ngừng HĐ (${((1 - activeRatio) * 100).toStringAsFixed(0)}%)'),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════════

  void _showBranchDetail(Branch branch) {
    final theme = Theme.of(context);
    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (ctx) {
        final detailContent = SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: (branch.isHeadquarter ? Colors.amber : Colors.blue).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      branch.isHeadquarter ? Icons.domain : Icons.business,
                      color: branch.isHeadquarter ? Colors.amber.shade700 : Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(branch.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                        Text(branch.code, style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  _buildStatusBadge(branch.isActive, branch.isHeadquarter),
                ],
              ),
              const Divider(height: 32),
              // Details
              if (branch.description != null && branch.description!.isNotEmpty) ...[
                Text(branch.description!, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
              ],
              _detailRow(Icons.location_on, 'Địa chỉ', branch.fullAddress.isNotEmpty ? branch.fullAddress : '(Chưa cập nhật)'),
              if (branch.phone != null) _detailRow(Icons.phone, 'Điện thoại', branch.phone!),
              if (branch.email != null) _detailRow(Icons.email, 'Email', branch.email!),
              if (branch.taxCode != null) _detailRow(Icons.receipt, 'MST', branch.taxCode!),
              if (branch.managerName != null) _detailRow(Icons.person, 'Quản lý', branch.managerName!),
              if (branch.parentBranchName != null) _detailRow(Icons.account_tree, 'Chi nhánh cha', branch.parentBranchName!),
              _detailRow(Icons.people, 'Nhân viên', '${branch.employeeCount}'),
              if (branch.openTime != null || branch.closeTime != null)
                _detailRow(Icons.access_time, 'Giờ làm việc', '${branch.openTime ?? '--'} - ${branch.closeTime ?? '--'}'),
              if (branch.maxEmployees != null) _detailRow(Icons.group_add, 'Sức chứa', '${branch.maxEmployees}'),
            ],
          ),
        );
        final actionButtons = _isManager
            ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showBranchDialog(branch: branch);
                    },
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Sửa'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _toggleBranchActive(branch);
                    },
                    icon: Icon(branch.isActive ? Icons.block : Icons.check_circle, size: 16),
                    label: Text(branch.isActive ? 'Ngừng HĐ' : 'Kích hoạt'),
                  ),
                ],
              )
            : null;
        if (isMobile) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Scaffold(
                appBar: AppBar(
                  title: Text(branch.name),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ),
                body: detailContent,
                bottomNavigationBar: actionButtons != null
                    ? Padding(padding: const EdgeInsets.all(16), child: actionButtons)
                    : null,
              ),
            ),
          );
        }
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with close button
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: (branch.isHeadquarter ? Colors.amber : Colors.blue).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            branch.isHeadquarter ? Icons.domain : Icons.business,
                            color: branch.isHeadquarter ? Colors.amber.shade700 : Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(branch.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                              Text(branch.code, style: TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        _buildStatusBadge(branch.isActive, branch.isHeadquarter),
                        const SizedBox(width: 8),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const Divider(height: 32),
                    if (branch.description != null && branch.description!.isNotEmpty) ...[
                      Text(branch.description!, style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 12),
                    ],
                    _detailRow(Icons.location_on, 'Địa chỉ', branch.fullAddress.isNotEmpty ? branch.fullAddress : '(Chưa cập nhật)'),
                    if (branch.phone != null) _detailRow(Icons.phone, 'Điện thoại', branch.phone!),
                    if (branch.email != null) _detailRow(Icons.email, 'Email', branch.email!),
                    if (branch.taxCode != null) _detailRow(Icons.receipt, 'MST', branch.taxCode!),
                    if (branch.managerName != null) _detailRow(Icons.person, 'Quản lý', branch.managerName!),
                    if (branch.parentBranchName != null) _detailRow(Icons.account_tree, 'Chi nhánh cha', branch.parentBranchName!),
                    _detailRow(Icons.people, 'Nhân viên', '${branch.employeeCount}'),
                    if (branch.openTime != null || branch.closeTime != null)
                      _detailRow(Icons.access_time, 'Giờ làm việc', '${branch.openTime ?? '--'} - ${branch.closeTime ?? '--'}'),
                    if (branch.maxEmployees != null) _detailRow(Icons.group_add, 'Sức chứa', '${branch.maxEmployees}'),
                    const SizedBox(height: 16),
                    if (_isManager)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showBranchDialog(branch: branch);
                            },
                            icon: const Icon(Icons.edit, size: 16),
                            label: const Text('Sửa'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _toggleBranchActive(branch);
                            },
                            icon: Icon(branch.isActive ? Icons.block : Icons.check_circle, size: 16),
                            label: Text(branch.isActive ? 'Ngừng HĐ' : 'Kích hoạt'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // CREATE / EDIT DIALOG
  // ═══════════════════════════════════════════════════════════════

  void _showBranchDialog({Branch? branch}) async {
    await _loadBranchSelect();
    if (!mounted) return;

    final isEdit = branch != null;
    final codeCtrl = TextEditingController(text: branch?.code ?? '');
    final nameCtrl = TextEditingController(text: branch?.name ?? '');
    final descCtrl = TextEditingController(text: branch?.description ?? '');
    final phoneCtrl = TextEditingController(text: branch?.phone ?? '');
    final emailCtrl = TextEditingController(text: branch?.email ?? '');
    final addressCtrl = TextEditingController(text: branch?.address ?? '');
    final cityCtrl = TextEditingController(text: branch?.city ?? '');
    final districtCtrl = TextEditingController(text: branch?.district ?? '');
    final wardCtrl = TextEditingController(text: branch?.ward ?? '');
    final taxCodeCtrl = TextEditingController(text: branch?.taxCode ?? '');
    final openTimeCtrl = TextEditingController(text: branch?.openTime ?? '');
    final closeTimeCtrl = TextEditingController(text: branch?.closeTime ?? '');
    final maxEmpCtrl = TextEditingController(text: branch?.maxEmployees?.toString() ?? '');
    final sortOrderCtrl = TextEditingController(text: branch?.sortOrder.toString() ?? '0');
    bool isHeadquarter = branch?.isHeadquarter ?? false;
    String? parentBranchId = branch?.parentBranchId;
    bool saving = false;

    final formKey = GlobalKey<FormState>();

    final isMobileBranch = Responsive.isMobile(context);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mã & tên
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: codeCtrl,
                          decoration: _inputDecoration('Mã chi nhánh *', Icons.tag),
                          validator: (v) => v == null || v.isEmpty ? 'Bắt buộc' : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: nameCtrl,
                          decoration: _inputDecoration('Tên chi nhánh *', Icons.business),
                          validator: (v) => v == null || v.isEmpty ? 'Bắt buộc' : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: descCtrl,
                    decoration: _inputDecoration('Mô tả', Icons.description),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  // Phone & email
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: phoneCtrl,
                          decoration: _inputDecoration('Số điện thoại', Icons.phone),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: emailCtrl,
                          decoration: _inputDecoration('Email', Icons.email),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Địa chỉ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: addressCtrl,
                    decoration: _inputDecoration('Địa chỉ', Icons.location_on),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: cityCtrl, decoration: _inputDecoration('Tỉnh/Thành phố', Icons.location_city))),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: districtCtrl, decoration: _inputDecoration('Quận/Huyện', Icons.map))),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: wardCtrl, decoration: _inputDecoration('Phường/Xã', Icons.place))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Cấu hình', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  // Parent branch
                  DropdownButtonFormField<String>(
                    initialValue: parentBranchId,
                    decoration: _inputDecoration('Chi nhánh cha', Icons.account_tree),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('-- Không có --')),
                      ..._branchSelect
                          .where((b) => b.id != branch?.id)
                          .map((b) => DropdownMenuItem(value: b.id, child: Text('${b.code} - ${b.name}'))),
                    ],
                    onChanged: (v) => setDialogState(() => parentBranchId = v),
                  ),
                  const SizedBox(height: 12),
                  // Headquarters toggle
                  SwitchListTile(
                    title: const Text('Trụ sở chính'),
                    subtitle: const Text('Đánh dấu đây là trụ sở chính của công ty'),
                    value: isHeadquarter,
                    onChanged: (v) => setDialogState(() => isHeadquarter = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 12),
                  // Tax code & sort order
                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: taxCodeCtrl, decoration: _inputDecoration('Mã số thuế', Icons.receipt))),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: sortOrderCtrl, decoration: _inputDecoration('Thứ tự', Icons.sort), keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Working hours & capacity
                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: openTimeCtrl, decoration: _inputDecoration('Giờ mở cửa', Icons.access_time))),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: closeTimeCtrl, decoration: _inputDecoration('Giờ đóng cửa', Icons.access_time_filled))),
                      const SizedBox(width: 12),
                      Expanded(child: TextFormField(controller: maxEmpCtrl, decoration: _inputDecoration('Sức chứa NV', Icons.group_add), keyboardType: TextInputType.number)),
                    ],
                  ),
                ],
              ),
            ),
          );
          final onSave = saving
              ? null
              : () async {
                  if (!formKey.currentState!.validate()) return;
                  setDialogState(() => saving = true);

                  final data = {
                    'code': codeCtrl.text.trim(),
                    'name': nameCtrl.text.trim(),
                    'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    'address': addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
                    'city': cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
                    'district': districtCtrl.text.trim().isEmpty ? null : districtCtrl.text.trim(),
                    'ward': wardCtrl.text.trim().isEmpty ? null : wardCtrl.text.trim(),
                    'taxCode': taxCodeCtrl.text.trim().isEmpty ? null : taxCodeCtrl.text.trim(),
                    'openTime': openTimeCtrl.text.trim().isEmpty ? null : openTimeCtrl.text.trim(),
                    'closeTime': closeTimeCtrl.text.trim().isEmpty ? null : closeTimeCtrl.text.trim(),
                    'maxEmployees': maxEmpCtrl.text.trim().isEmpty ? null : int.tryParse(maxEmpCtrl.text.trim()),
                    'sortOrder': int.tryParse(sortOrderCtrl.text.trim()) ?? 0,
                    'parentBranchId': parentBranchId,
                    'isHeadquarter': isHeadquarter,
                  };

                  final resp = isEdit
                      ? await _api.updateBranch(branch.id, data)
                      : await _api.createBranch(data);

                  setDialogState(() => saving = false);

                  if (resp['isSuccess'] == true) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    appNotification.showSuccess(
                      title: isEdit ? 'Cập nhật thành công' : 'Tạo thành công',
                      message: isEdit ? 'Chi nhánh đã được cập nhật.' : 'Chi nhánh mới đã được tạo.',
                    );
                    _loadTabData(_currentTab);
                  } else {
                    appNotification.showError(
                      title: 'Lỗi',
                      message: resp['message']?.toString() ?? 'Có lỗi xảy ra',
                    );
                  }
                };
          final saveIcon = saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(isEdit ? Icons.save : Icons.add, size: 18);
          final saveLabel = Text(saving ? 'Đang lưu...' : (isEdit ? 'Lưu' : 'Tạo mới'));
          if (isMobileBranch) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(isEdit ? 'Sửa chi nhánh' : 'Thêm chi nhánh mới'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: saving ? null : () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onSave,
                          icon: saveIcon,
                          label: saveLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Icon(isEdit ? Icons.edit : Icons.add_business, color: Colors.blue),
                        const SizedBox(width: 12),
                        Text(
                          isEdit ? 'Sửa chi nhánh' : 'Thêm chi nhánh mới',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                      ],
                    ),
                  ),
                  // Form
                  Flexible(child: formContent),
                  // Actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: saving ? null : () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onSave,
                          icon: saveIcon,
                          label: saveLabel,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      isDense: true,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _toggleBranchActive(Branch branch) async {
    final resp = await _api.toggleBranchActive(branch.id);
    if (resp['isSuccess'] == true) {
      appNotification.showSuccess(
        title: 'Thành công',
        message: branch.isActive ? 'Đã ngừng hoạt động chi nhánh.' : 'Đã kích hoạt chi nhánh.',
      );
      _loadTabData(_currentTab);
    } else {
      appNotification.showError(title: 'Lỗi', message: resp['message']?.toString() ?? 'Có lỗi xảy ra');
    }
  }

  void _confirmDeleteBranch(Branch branch) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.red.shade400),
            const SizedBox(width: 8),
            const Text('Xác nhận xóa'),
          ],
        ),
        content: Text('Bạn có chắc muốn xóa chi nhánh "${branch.name}" (${branch.code})?\n\nHành động này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final resp = await _api.deleteBranch(branch.id);
              if (resp['isSuccess'] == true) {
                appNotification.showSuccess(title: 'Đã xóa', message: 'Chi nhánh "${branch.name}" đã được xóa.');
                _loadTabData(_currentTab);
              } else {
                appNotification.showError(title: 'Lỗi', message: resp['message']?.toString() ?? 'Có lỗi xảy ra');
              }
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // COMMON
  // ═══════════════════════════════════════════════════════════════

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade500), textAlign: TextAlign.center),
          if (_isManager) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _showBranchDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm chi nhánh'),
            ),
          ],
        ],
      ),
    );
  }
}
