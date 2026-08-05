import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../models/orgchart.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/hrm_collapsible_overview.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màn hình Sơ đồ tổ chức & Luồng duyệt
class OrgChartScreen extends StatefulWidget {
  const OrgChartScreen({super.key});

  @override
  State<OrgChartScreen> createState() => _OrgChartScreenState();
}

class _OrgChartScreenState extends State<OrgChartScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();

  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  // Data
  List<OrgChartNode> _orgTree = [];
  List<OrgPosition> _positions = [];
  List<OrgAssignment> _assignments = [];
  List<ApprovalFlow> _approvalFlows = [];
  List<UnassignedEmployee> _unassignedEmployees = [];
  OrgChartStats? _stats;

  bool _loading = false;
  int _currentTab = 0;
  bool _showOverviewPanel = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentTab = _tabController.index);
      _loadTabData(_tabController.index);
    });
    _loadTabData(0);
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
        case 0: // Sơ đồ
          await Future.wait([_loadOrgTree(), _loadStats()]);
          break;
        case 1: // Chức vụ
          await _loadPositions();
          break;
        case 2: // Gán chức vụ
          await Future.wait([_loadAssignments(), _loadPositions()]);
          break;
        case 3: // Luồng duyệt
          await _loadApprovalFlows();
          break;
        case 4: // NV chưa gán
          await _loadUnassignedEmployees();
          break;
      }
    } catch (e) {
      debugPrint('Error loading tab $tab: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadOrgTree() async {
    final resp = await _api.getOrgChartTree();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _orgTree = (resp['data'] as List)
          .map((n) => OrgChartNode.fromJson(n as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadStats() async {
    final resp = await _api.getOrgChartStats();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _stats = OrgChartStats.fromJson(resp['data'] as Map<String, dynamic>);
    }
  }

  Future<void> _loadPositions() async {
    final resp = await _api.getOrgPositions();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _positions = (resp['data'] as List)
          .map((p) => OrgPosition.fromJson(p as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadAssignments() async {
    final resp = await _api.getOrgAssignments();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _assignments = (resp['data'] as List)
          .map((a) => OrgAssignment.fromJson(a as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadApprovalFlows() async {
    final resp = await _api.getApprovalFlows();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _approvalFlows = (resp['data'] as List)
          .map((f) => ApprovalFlow.fromJson(f as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadUnassignedEmployees() async {
    final resp = await _api.getUnassignedEmployees();
    if (resp['isSuccess'] == true && resp['data'] != null) {
      _unassignedEmployees = (resp['data'] as List)
          .map((e) => UnassignedEmployee.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  List<Widget> _buildTopActions() {
    return [
      HrmTopBarAction(
        icon: Icons.refresh,
        label: 'Tải lại',
        onPressed: _loading ? null : () => _loadTabData(_currentTab),
      ),
      if (_currentTab == 2 && _perm.canCreate('OrgChart'))
        HrmTopBarAction(
          icon: Icons.add,
          label: 'Gán mới',
          primary: true,
          showLabel: true,
          onPressed: _showCreateAssignmentDialog,
        ),
      if (_currentTab == 3 && _perm.canCreate('OrgChart'))
        HrmTopBarAction(
          icon: Icons.add,
          label: 'Thêm luồng',
          primary: true,
          showLabel: true,
          onPressed: _showCreateApprovalFlowDialog,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RegisterPageTopActions(
      actions: _buildTopActions(),
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Column(
      children: [
        // Tab bar
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.account_tree), text: tr('Sơ đồ')),
              Tab(icon: Icon(Icons.badge), text: tr('Chức vụ')),
              Tab(icon: Icon(Icons.assignment_ind), text: tr('Gán chức vụ')),
              Tab(icon: Icon(Icons.rule), text: tr('Luồng duyệt')),
              Tab(icon: Icon(Icons.person_off), text: tr('NV chưa gán')),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrgTreeTab(),
                    _buildPositionsTab(),
                    _buildAssignmentsTab(),
                    _buildApprovalFlowsTab(),
                    _buildUnassignedTab(),
                  ],
                ),
        ),
      ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 1: SƠ ĐỒ TỔ CHỨC
  // ═══════════════════════════════════════════════════════════════

  Widget _buildOrgTreeTab() {
    return RefreshIndicator(
      onRefresh: () => _loadTabData(0),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats cards
            if (_stats != null)
              HrmCollapsibleOverview(
                expanded: _showOverviewPanel,
                onToggle: () =>
                    setState(() => _showOverviewPanel = !_showOverviewPanel),
                child: _buildStatsRow(),
              ),
            const SizedBox(height: 16),
            // Tree
            if (_orgTree.isEmpty)
              _buildEmptyState('Chưa có dữ liệu sơ đồ tổ chức', 'Hãy tạo phòng ban và gán chức vụ cho nhân viên')
            else
              ..._orgTree.map((node) => _buildOrgNodeCard(node, 0)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final s = _stats!;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _statCard('Phòng ban', s.totalDepartments, Icons.business, Colors.blue),
        _statCard('Chức vụ', s.totalPositions, Icons.badge, Colors.purple),
        _statCard('Đã gán', s.totalAssignments, Icons.assignment_ind, Colors.green),
        _statCard('Tổng NV', s.totalEmployees, Icons.people, Colors.orange),
        _statCard('Chưa gán', s.unassignedEmployees, Icons.person_off, Colors.red),
        _statCard('Luồng duyệt', s.totalApprovalFlows, Icons.rule, Colors.teal),
      ],
    );
  }

  Widget _statCard(String label, int value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(tr('$value'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(tr(label), style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildOrgNodeCard(OrgChartNode node, int depth) {
    final headMember = node.head;
    final hasChildren = node.children.isNotEmpty;
    final memberCount = node.members.length;

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
              side: BorderSide(
                color: depth == 0 ? Colors.blue.shade300 : Colors.grey.shade300,
                width: depth == 0 ? 2 : 1,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _showDepartmentDetailDialog(node, depth);
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: _deptColor(depth).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            depth == 0 ? Icons.business : Icons.folder,
                            color: _deptColor(depth),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr(node.name),
                                style: TextStyle(
                                  fontSize: depth == 0 ? 16 : 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(tr('${node.code} • $memberCount thành viên'),
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                        if (hasChildren)
                          GestureDetector(
                            onTap: () {
                              setState(() => node.isExpanded = !node.isExpanded);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                node.isExpanded ? Icons.expand_less : Icons.expand_more,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Head member
                    if (headMember != null) ...[
                      const Divider(height: 24),
                      _buildMemberTile(headMember, isHead: true),
                    ],
                    // Other members
                    if (node.isExpanded && node.members.length > 1) ...[
                      const SizedBox(height: 4),
                      ...node.members.where((m) => !m.isHead).map(
                        (m) => _buildMemberTile(m, isHead: false),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Children
          if (node.isExpanded && hasChildren)
            ...node.children.map((child) => _buildOrgNodeCard(child, depth + 1)),
        ],
      ),
    );
  }

  Widget _buildMemberTile(OrgChartMember member, {required bool isHead}) {
    final posColor = member.positionColor != null
        ? Color(int.parse('0xFF${member.positionColor!.replaceAll('#', '')}'))
        : (isHead ? Colors.blue : Colors.grey);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: posColor.withValues(alpha: 0.15),
            backgroundImage: member.employeePhoto != null && member.employeePhoto!.isNotEmpty
                ? _api.storeImageProvider(member.employeePhoto!)
                : null,
            onBackgroundImageError: member.employeePhoto != null && member.employeePhoto!.isNotEmpty ? (_, __) {} : null,
            child: member.employeePhoto == null || member.employeePhoto!.isEmpty
                ? Icon(isHead ? Icons.star : Icons.person, size: 16, color: posColor)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(member.employeeName),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isHead ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                Text(
                  tr('${member.positionName} • ${member.employeeCode}'),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: posColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tr(member.positionName),
              style: TextStyle(fontSize: 10, color: posColor, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showDepartmentDetailDialog(OrgChartNode node, int depth) {
    // Sort members by positionLevel ascending (lowest = highest rank)
    final sortedMembers = List<OrgChartMember>.from(node.members)
      ..sort((a, b) => a.positionLevel.compareTo(b.positionLevel));

    final manager = sortedMembers.isNotEmpty ? sortedMembers.first : null;
    final otherMembers = sortedMembers.length > 1 ? sortedMembers.sublist(1) : <OrgChartMember>[];
    final color = _deptColor(depth);
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleRow = Row(
      children: [
        Icon(depth == 0 ? Icons.business : Icons.folder, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(node.name), style: const TextStyle(fontSize: 18)),
              Text(tr('${node.code} • ${node.members.length} thành viên'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.normal)),
            ],
          ),
        ),
      ],
    );

    final contentBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (manager != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.amber.withValues(alpha: 0.2),
                  backgroundImage: manager.employeePhoto != null && manager.employeePhoto!.isNotEmpty
                      ? _api.storeImageProvider(manager.employeePhoto!)
                      : null,
                  onBackgroundImageError: manager.employeePhoto != null && manager.employeePhoto!.isNotEmpty ? (_, __) {} : null,
                  child: manager.employeePhoto == null || manager.employeePhoto!.isEmpty
                      ? const Icon(Icons.star, color: Colors.amber, size: 24)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 16),
                          SizedBox(width: 4),
                          Text(tr('Quản lý phòng ban'),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(tr(manager.employeeName),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(tr('${manager.positionName} • ${manager.employeeCode}'),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (otherMembers.isNotEmpty) ...[
          Text(tr('Danh sách nhân viên'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
          const SizedBox(height: 8),
          ...otherMembers.map((m) {
            final posColor = m.positionColor != null
                ? Color(int.parse('0xFF${m.positionColor!.replaceAll('#', '')}'))
                : Colors.grey;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: posColor.withValues(alpha: 0.15),
                    backgroundImage: m.employeePhoto != null && m.employeePhoto!.isNotEmpty
                        ? _api.storeImageProvider(m.employeePhoto!)
                        : null,
                    onBackgroundImageError: m.employeePhoto != null && m.employeePhoto!.isNotEmpty ? (_, __) {} : null,
                    child: m.employeePhoto == null || m.employeePhoto!.isEmpty
                        ? Icon(Icons.person, size: 18, color: posColor)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(m.employeeName),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(tr('${m.positionName} • ${m.employeeCode}'),
                            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: posColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tr(m.positionName),
                        style: TextStyle(fontSize: 11, color: posColor, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            );
          }),
        ],
        if (node.members.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.people_outline, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(tr('Chưa có nhân viên nào trong phòng ban này'),
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ),
      ],
    );

    if (isMobile) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
                title: Text(tr(node.name), overflow: TextOverflow.ellipsis),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 16),
                    contentBody,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => ScrollableAlertDialog(
          title: titleRow,
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Đóng')),
            ),
          ],
        ),
      );
    }
  }

  Color _deptColor(int depth) {
    final colors = [Colors.blue, Colors.teal, Colors.purple, Colors.orange, Colors.green];
    return colors[depth % colors.length];
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 2: CHỨC VỤ
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPositionsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(tr('Danh sách chức vụ (${_positions.length})'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: _positions.isEmpty
              ? _buildEmptyState('Chưa có chức vụ nào', 'Tạo chức vụ để xây dựng sơ đồ tổ chức')
              : RefreshIndicator(
                  onRefresh: () => _loadTabData(1),
                  child: MediaQuery.of(context).size.width < 600
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _positions.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE4E4E7)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: _buildPositionDeckItem(_positions[i]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _positions.length,
                        itemBuilder: (_, i) => _buildPositionCard(_positions[i]),
                      ),
                ),
        ),
      ],
    );
  }

  Widget _buildPositionDeckItem(OrgPosition position) {
    final posColor = position.color != null
        ? Color(int.parse('0xFF${position.color!.replaceAll('#', '')}'))
        : Colors.blue;
    return InkWell(
      onTap: () => _showEditPositionDialog(position),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: posColor.withValues(alpha: 0.15),
            child: Text(tr('${position.level}'), style: TextStyle(color: posColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(position.name), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                tr([position.code, 'Cấp ${position.level}', '${position.assignmentCount} NV', if (position.canApprove) 'Được duyệt'].join(' · ')),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  Widget _buildPositionCard(OrgPosition position) {
    final posColor = position.color != null
        ? Color(int.parse('0xFF${position.color!.replaceAll('#', '')}'))
        : Colors.blue;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: posColor.withValues(alpha: 0.15),
          child: Text(tr('${position.level}'), style: TextStyle(color: posColor, fontWeight: FontWeight.bold)),
        ),
        title: Text(tr(position.name), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          tr('${position.code} • Cấp ${position.level} • ${position.assignmentCount} NV'
          '${position.canApprove ? ' • Được duyệt' : ''}'),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!position.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                child: Text(tr('Tắt'), style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
              ),
            if (_perm.canEdit('OrgChart'))
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _showEditPositionDialog(position),
              ),
            if (_perm.canDelete('OrgChart'))
              IconButton(
                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                onPressed: () => _confirmDeletePosition(position),
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 3: GÁN CHỨC VỤ
  // ═══════════════════════════════════════════════════════════════

  Widget _buildAssignmentsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tr('Gán chức vụ (${_assignments.length})'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: _assignments.isEmpty
              ? _buildEmptyState('Chưa có gán chức vụ nào', 'Gán chức vụ cho nhân viên để xây dựng sơ đồ')
              : RefreshIndicator(
                  onRefresh: () => _loadTabData(2),
                  child: MediaQuery.of(context).size.width < 600
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _assignments.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE4E4E7)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: _buildAssignDeckItem(_assignments[i]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _assignments.length,
                        itemBuilder: (_, i) => _buildAssignmentCard(_assignments[i]),
                      ),
                ),
        ),
      ],
    );
  }

  Widget _buildAssignDeckItem(OrgAssignment assign) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.blue.shade50,
            backgroundImage: assign.employeePhoto != null && assign.employeePhoto!.isNotEmpty ? _api.storeImageProvider(assign.employeePhoto!) : null,
            onBackgroundImageError: assign.employeePhoto != null && assign.employeePhoto!.isNotEmpty ? (_, __) {} : null,
            child: assign.employeePhoto == null || assign.employeePhoto!.isEmpty ? const Icon(Icons.person, color: Colors.blue, size: 18) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(assign.employeeName), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                tr([assign.employeeCode, assign.positionName, assign.departmentName].join(' · ')),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (assign.isPrimary) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(tr('Chính'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green)),
          ),
        ]),
      ),
    );
  }

  Widget _buildAssignmentCard(OrgAssignment assign) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: assign.employeePhoto != null && assign.employeePhoto!.isNotEmpty
                  ? _api.storeImageProvider(assign.employeePhoto!)
                  : null,
              onBackgroundImageError: assign.employeePhoto != null && assign.employeePhoto!.isNotEmpty ? (_, __) {} : null,
              child: assign.employeePhoto == null || assign.employeePhoto!.isEmpty
                  ? const Icon(Icons.person, color: Colors.blue)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(tr(assign.employeeName), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (assign.isPrimary) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(tr('Chính'), style: TextStyle(fontSize: 9, color: Colors.amber.shade800)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tr('${assign.positionName} • ${assign.departmentName}'),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  if (assign.reportToEmployeeName != null)
                    Text(tr('Báo cáo: ${assign.reportToEmployeeName}'),
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                ],
              ),
            ),
            if (_perm.canEdit('OrgChart') || _perm.canDelete('OrgChart'))
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_perm.canEdit('OrgChart'))
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _showEditAssignmentDialog(assign),
                    ),
                  if (_perm.canDelete('OrgChart'))
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () => _confirmDeleteAssignment(assign),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 4: LUỒNG DUYỆT
  // ═══════════════════════════════════════════════════════════════

  Widget _buildApprovalFlowsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tr('Luồng duyệt (${_approvalFlows.length})'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: _approvalFlows.isEmpty
              ? _buildEmptyState('Chưa có luồng duyệt nào', 'Tạo luồng duyệt để cấu hình quy trình phê duyệt')
              : RefreshIndicator(
                  onRefresh: () => _loadTabData(3),
                  child: MediaQuery.of(context).size.width < 600
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _approvalFlows.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE4E4E7)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: _buildFlowDeckItem(_approvalFlows[i]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _approvalFlows.length,
                        itemBuilder: (_, i) => _buildApprovalFlowCard(_approvalFlows[i]),
                      ),
                ),
        ),
      ],
    );
  }

  Widget _buildFlowDeckItem(ApprovalFlow flow) {
    return InkWell(
      onTap: () => _showEditApprovalFlowDialog(flow),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.teal.shade50,
            child: Icon(Icons.rule, color: Colors.teal.shade700, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(flow.name), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                tr([ApprovalFlow.requestTypeName2(flow.requestType), flow.departmentName ?? 'Tất cả PB', '${flow.steps.length} bước'].join(' · ')),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  Widget _buildApprovalFlowCard(ApprovalFlow flow) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade50,
          child: Icon(Icons.rule, color: Colors.teal.shade700, size: 20),
        ),
        title: Text(tr(flow.name), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          tr('${ApprovalFlow.requestTypeName2(flow.requestType)}'
          '${flow.departmentName != null ? ' • ${flow.departmentName}' : ' • Tất cả PB'}'
          ' • ${flow.steps.length} bước'),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: (_perm.canEdit('OrgChart') || _perm.canDelete('OrgChart'))
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_perm.canEdit('OrgChart'))
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _showEditApprovalFlowDialog(flow),
                    ),
                  if (_perm.canDelete('OrgChart'))
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      onPressed: () => _confirmDeleteApprovalFlow(flow),
                    ),
                ],
              )
            : null,
        children: [
          if (flow.steps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: flow.steps
                    .map((step) => _buildStepTile(step, flow.steps.length))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepTile(ApprovalStep step, int totalSteps) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Step number
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.teal.shade100,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(tr('${step.stepOrder}'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
            ),
          ),
          if (step.stepOrder < totalSteps)
            Container(width: 2, height: 16, color: Colors.teal.shade200),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(step.name), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text(
                  tr('${ApprovalStep.approverTypeName2(step.approverType)}'
                  '${step.approverPositionName != null ? ' (${step.approverPositionName})' : ''}'
                  '${step.approverEmployeeName != null ? ' (${step.approverEmployeeName})' : ''}'
                  '${step.isRequired ? '' : ' [Không bắt buộc]'}'),
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          if (step.maxWaitHours != null)
            Chip(
              label: Text(tr('${step.maxWaitHours}h'), style: const TextStyle(fontSize: 10)),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 5: NV CHƯA GÁN
  // ═══════════════════════════════════════════════════════════════

  Widget _buildUnassignedTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(tr('NV chưa gán chức vụ (${_unassignedEmployees.length})'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: _unassignedEmployees.isEmpty
              ? _buildEmptyState('Tất cả nhân viên đã được gán chức vụ', 'Không có nhân viên nào cần gán thêm')
              : RefreshIndicator(
                  onRefresh: () => _loadTabData(4),
                  child: MediaQuery.of(context).size.width < 600
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _unassignedEmployees.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE4E4E7)),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                            ),
                            child: _buildUnassignedDeckItem(_unassignedEmployees[i]),
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _unassignedEmployees.length,
                        itemBuilder: (_, i) => _buildUnassignedCard(_unassignedEmployees[i]),
                      ),
                ),
        ),
      ],
    );
  }

  Widget _buildUnassignedDeckItem(UnassignedEmployee emp) {
    return InkWell(
      onTap: () => _showQuickAssignDialog(emp),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.orange.shade50,
            backgroundImage: emp.photoUrl != null && emp.photoUrl!.isNotEmpty ? _api.storeImageProvider(emp.photoUrl!) : null,
            onBackgroundImageError: emp.photoUrl != null && emp.photoUrl!.isNotEmpty ? (_, __) {} : null,
            child: emp.photoUrl == null || emp.photoUrl!.isEmpty ? const Icon(Icons.person_off, color: Colors.orange, size: 18) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(emp.fullName), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                tr([emp.employeeCode, if (emp.departmentName != null) emp.departmentName!, if (emp.position != null) emp.position!].join(' · ')),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const Icon(Icons.assignment_ind, size: 18, color: HrmPageChrome.primaryNavy),
        ]),
      ),
    );
  }

  Widget _buildUnassignedCard(UnassignedEmployee emp) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.shade50,
          backgroundImage: emp.photoUrl != null && emp.photoUrl!.isNotEmpty ? _api.storeImageProvider(emp.photoUrl!) : null,
          onBackgroundImageError: emp.photoUrl != null && emp.photoUrl!.isNotEmpty ? (_, __) {} : null,
          child: emp.photoUrl == null || emp.photoUrl!.isEmpty
              ? const Icon(Icons.person_off, color: Colors.orange)
              : null,
        ),
        title: Text(tr(emp.fullName), style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          tr('${emp.employeeCode}${emp.departmentName != null ? ' • ${emp.departmentName}' : ''}'
          '${emp.position != null ? ' • ${emp.position}' : ''}'),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        trailing: _perm.canCreate('OrgChart')
            ? FilledButton.icon(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () => _showQuickAssignDialog(emp),
                icon: const Icon(Icons.assignment_ind, size: 16),
                label: Text(tr('Gán'), style: TextStyle(fontSize: 12)),
              )
            : null,
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(tr(title), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(tr(subtitle), style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════════



  void _showEditPositionDialog(OrgPosition position) {
    final codeCtrl = TextEditingController(text: tr(position.code));
    final nameCtrl = TextEditingController(text: tr(position.name));
    final descCtrl = TextEditingController(text: tr(position.description ?? ''));
    final levelCtrl = TextEditingController(text: tr('${position.level}'));
    final sortCtrl = TextEditingController(text: tr('${position.sortOrder}'));
    final colorCtrl = TextEditingController(text: tr(position.color ?? '#4CAF50'));
    final maxAmountCtrl = TextEditingController(text: tr(formatNumber(position.maxApprovalAmount)));
    bool canApprove = position.canApprove;
    bool isActive = position.isActive;

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeCtrl, decoration: InputDecoration(labelText: tr('Mã chức vụ *'))),
                const SizedBox(height: 8),
                TextField(controller: nameCtrl, decoration: InputDecoration(labelText: tr('Tên chức vụ *'))),
                const SizedBox(height: 8),
                TextField(controller: descCtrl, decoration: InputDecoration(labelText: tr('Mô tả'))),
                const SizedBox(height: 8),
                TextField(controller: levelCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Cấp bậc *'))),
                const SizedBox(height: 8),
                TextField(controller: sortCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('Thứ tự'))),
                const SizedBox(height: 8),
                TextField(controller: colorCtrl, decoration: InputDecoration(labelText: tr('Màu (hex)'))),
                const SizedBox(height: 8),
                SwitchListTile(title: Text(tr('Có quyền duyệt')), value: canApprove, onChanged: (v) => setDialogState(() => canApprove = v), contentPadding: EdgeInsets.zero),
                if (canApprove) TextField(controller: maxAmountCtrl, keyboardType: TextInputType.number, inputFormatters: [ThousandSeparatorFormatter()], decoration: InputDecoration(labelText: tr('Mức duyệt tối đa'))),
                SwitchListTile(title: Text(tr('Đang hoạt động')), value: isActive, onChanged: (v) => setDialogState(() => isActive = v), contentPadding: EdgeInsets.zero),
              ],
            ),
          );
          Future<Null> onSave() async {
                if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
                Navigator.pop(ctx);
                final resp = await _api.updateOrgPosition(position.id, {
                  'code': codeCtrl.text.trim(),
                  'name': nameCtrl.text.trim(),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'level': int.tryParse(levelCtrl.text) ?? 5,
                  'sortOrder': int.tryParse(sortCtrl.text) ?? 0,
                  'color': colorCtrl.text.trim().isEmpty ? null : colorCtrl.text.trim(),
                  'canApprove': canApprove,
                  'maxApprovalAmount': maxAmountCtrl.text.isNotEmpty ? parseFormattedNumber(maxAmountCtrl.text)?.toDouble() : null,
                  'isActive': isActive,
                });
                _handleApiResponse(resp, 'Cập nhật chức vụ');
                _loadTabData(1);
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr('Sửa chức vụ')),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Sửa chức vụ')),
            content: formContent,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeletePosition(OrgPosition position) {
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xóa chức vụ')),
        content: Text(tr('Bạn có chắc muốn xóa chức vụ "${position.name}"?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final resp = await _api.deleteOrgPosition(position.id);
              _handleApiResponse(resp, 'Xóa chức vụ');
              _loadTabData(1);
            },
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
  }

  void _showCreateAssignmentDialog() {
    _showAssignmentDialog(null, null);
  }

  void _showQuickAssignDialog(UnassignedEmployee emp) {
    _showAssignmentDialog(emp.id, null);
  }

  void _showAssignmentDialog(String? preselectedEmployeeId, OrgAssignment? existing) async {
    // Load departments and positions for dropdown
    final deptResp = await _api.getDepartmentsForSelect();
    final departments = <Map<String, dynamic>>[];
    if (deptResp['isSuccess'] == true && deptResp['data'] != null) {
      for (var d in (deptResp['data'] as List)) {
        departments.add({'id': d['id'].toString(), 'name': d['name'].toString()});
      }
    }

    if (!mounted) return;
    await _loadPositions();

    // Load employees
    final empList = await _api.getEmployeesForSelect();
    final employees = <Map<String, dynamic>>[];
    for (var e in empList) {
      employees.add({
        'id': e['id'].toString(),
        'name': '${e['lastName'] ?? ''} ${e['firstName'] ?? ''} (${e['employeeCode'] ?? ''})',
      });
    }

    if (!mounted) return;

    String? selectedEmpId = preselectedEmployeeId;
    String? selectedDeptId;
    String? selectedPosId;
    bool isPrimary = true;

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedEmpId,
                  decoration: InputDecoration(labelText: tr('Nhân viên *')),
                  isExpanded: true,
                  items: employees.map((e) => DropdownMenuItem(value: e['id'] as String, child: Text(tr(e['name'] as String), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setDialogState(() => selectedEmpId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedDeptId,
                  decoration: InputDecoration(labelText: tr('Phòng ban *')),
                  isExpanded: true,
                  items: departments.map((d) => DropdownMenuItem(value: d['id'] as String, child: Text(tr(d['name'] as String), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setDialogState(() => selectedDeptId = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedPosId,
                  decoration: InputDecoration(labelText: tr('Chức vụ *')),
                  isExpanded: true,
                  items: _positions.map((p) => DropdownMenuItem(value: p.id, child: Text(tr('${p.name} (Cấp ${p.level})')))).toList(),
                  onChanged: (v) => setDialogState(() => selectedPosId = v),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: Text(tr('Chức vụ chính')),
                  value: isPrimary,
                  onChanged: (v) => setDialogState(() => isPrimary = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          );
          Future<Null> onSave() async {
                if (selectedEmpId == null || selectedDeptId == null || selectedPosId == null) return;
                Navigator.pop(ctx);
                final resp = await _api.createOrgAssignment({
                  'employeeId': selectedEmpId,
                  'departmentId': selectedDeptId,
                  'positionId': selectedPosId,
                  'isPrimary': isPrimary,
                  'startDate': DateTime.now().toIso8601String(),
                });
                _handleApiResponse(resp, 'Gán chức vụ');
                _loadTabData(_currentTab);
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr('Gán chức vụ')),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: onSave, child: Text(tr('Gán'))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Gán chức vụ')),
            content: formContent,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Gán'))),
            ],
          );
        },
      ),
    );
  }

  void _showEditAssignmentDialog(OrgAssignment assign) {
    bool isPrimary = assign.isPrimary;
    bool isActive = assign.isActive;
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('NV: ${assign.employeeName}'), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(tr('PB: ${assign.departmentName}'), style: TextStyle(color: Colors.grey[600])),
              Text(tr('CV: ${assign.positionName}'), style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 12),
              SwitchListTile(title: Text(tr('Chức vụ chính')), value: isPrimary, onChanged: (v) => setDialogState(() => isPrimary = v), contentPadding: EdgeInsets.zero),
              SwitchListTile(title: Text(tr('Đang hoạt động')), value: isActive, onChanged: (v) => setDialogState(() => isActive = v), contentPadding: EdgeInsets.zero),
            ],
            ),
          );
          Future<void> onSave() async {
                Navigator.pop(ctx);
                final resp = await _api.updateOrgAssignment(assign.id, {
                  'isPrimary': isPrimary,
                  'isActive': isActive,
                  'startDate': assign.startDate?.toIso8601String(),
                  'reportToAssignmentId': assign.reportToAssignmentId,
                });
                _handleApiResponse(resp, 'Cập nhật');
                _loadTabData(_currentTab);
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr('Sửa gán chức vụ')),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Sửa gán chức vụ')),
            content: formContent,
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteAssignment(OrgAssignment assign) {
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xóa gán chức vụ')),
        content: Text(tr('Xóa "${assign.positionName}" của "${assign.employeeName}" tại "${assign.departmentName}"?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final resp = await _api.deleteOrgAssignment(assign.id);
              _handleApiResponse(resp, 'Xóa gán chức vụ');
              _loadTabData(_currentTab);
            },
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
  }

  void _showCreateApprovalFlowDialog() {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int requestType = 1;
    int priority = 1;
    final steps = <Map<String, dynamic>>[];
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: codeCtrl, decoration: InputDecoration(labelText: tr('Mã luồng *'))),
                  const SizedBox(height: 8),
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: tr('Tên luồng *'))),
                  const SizedBox(height: 8),
                  TextField(controller: descCtrl, decoration: InputDecoration(labelText: tr('Mô tả'))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: requestType,
                    decoration: InputDecoration(labelText: tr('Loại yêu cầu')),
                    items: ApprovalFlow.allRequestTypes().map((t) =>
                      DropdownMenuItem(value: t['value'] as int, child: Text(tr(t['label'] as String))),
                    ).toList(),
                    onChanged: (v) => setDialogState(() => requestType = v!),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(text: tr('$priority')),
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: tr('Ưu tiên')),
                    onChanged: (v) => priority = int.tryParse(v) ?? 1,
                  ),
                  const Divider(height: 32),
                  Row(
                    children: [
                      Text(tr('Các bước duyệt'), style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            steps.add({
                              'name': 'Bước ${steps.length + 1}',
                              'approverType': 1,
                              'isRequired': true,
                              'timeoutAction': 1,
                            });
                          });
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(tr('Thêm bước')),
                      ),
                    ],
                  ),
                  ...steps.asMap().entries.map((entry) {
                    final i = entry.key;
                    final step = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(tr('Bước ${i + 1}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                  onPressed: () => setDialogState(() => steps.removeAt(i)),
                                ),
                              ],
                            ),
                            TextField(
                              controller: TextEditingController(text: tr(step['name'])),
                              decoration: InputDecoration(labelText: tr('Tên bước'), isDense: true),
                              onChanged: (v) => step['name'] = v,
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              initialValue: step['approverType'] as int,
                              decoration: InputDecoration(labelText: tr('Loại người duyệt'), isDense: true),
                              items: [
                                DropdownMenuItem(value: 1, child: Text(tr('Quản lý trực tiếp'))),
                                DropdownMenuItem(value: 2, child: Text(tr('Theo chức vụ'))),
                                DropdownMenuItem(value: 3, child: Text(tr('Nhân viên cụ thể'))),
                                DropdownMenuItem(value: 4, child: Text(tr('Trưởng phòng'))),
                                DropdownMenuItem(value: 5, child: Text(tr('Cấp trên bất kỳ'))),
                              ],
                              onChanged: (v) => setDialogState(() => step['approverType'] = v),
                            ),
                            if (step['approverType'] == 2 && _positions.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: step['approverPositionId'],
                                decoration: InputDecoration(labelText: tr('Chức vụ duyệt'), isDense: true),
                                isExpanded: true,
                                items: _positions.map((p) =>
                                  DropdownMenuItem(value: p.id, child: Text(tr(p.name))),
                                ).toList(),
                                onChanged: (v) => step['approverPositionId'] = v,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ],
            ),
          );
          Future<Null> onSave() async {
                if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
                Navigator.pop(ctx);
                final resp = await _api.createApprovalFlow({
                  'code': codeCtrl.text.trim(),
                  'name': nameCtrl.text.trim(),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'requestType': requestType,
                  'priority': priority,
                  'steps': steps.map((s) => {
                    'name': s['name'],
                    'approverType': s['approverType'],
                    'approverPositionId': s['approverPositionId'],
                    'approverEmployeeId': s['approverEmployeeId'],
                    'isRequired': s['isRequired'] ?? true,
                    'timeoutAction': s['timeoutAction'] ?? 1,
                  }).toList(),
                });
                _handleApiResponse(resp, 'Tạo luồng duyệt');
                _loadTabData(3);
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr('Thêm luồng duyệt')),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: onSave, child: Text(tr('Tạo'))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Thêm luồng duyệt')),
            content: SizedBox(width: 500, child: formContent),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Tạo'))),
            ],
          );
        },
      ),
    );
  }

  void _showEditApprovalFlowDialog(ApprovalFlow flow) {
    final codeCtrl = TextEditingController(text: tr(flow.code));
    final nameCtrl = TextEditingController(text: tr(flow.name));
    final descCtrl = TextEditingController(text: tr(flow.description ?? ''));
    int requestType = flow.requestType;
    int priority = flow.priority;
    bool isActive = flow.isActive;
    final steps = flow.steps.map((s) => <String, dynamic>{
      'name': s.name,
      'approverType': s.approverType,
      'approverPositionId': s.approverPositionId,
      'approverEmployeeId': s.approverEmployeeId,
      'isRequired': s.isRequired,
      'timeoutAction': s.timeoutAction,
      'maxWaitHours': s.maxWaitHours,
    }).toList();
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: codeCtrl, decoration: InputDecoration(labelText: tr('Mã luồng *'))),
                  const SizedBox(height: 8),
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: tr('Tên luồng *'))),
                  const SizedBox(height: 8),
                  TextField(controller: descCtrl, decoration: InputDecoration(labelText: tr('Mô tả'))),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: requestType,
                    decoration: InputDecoration(labelText: tr('Loại yêu cầu')),
                    items: ApprovalFlow.allRequestTypes().map((t) =>
                      DropdownMenuItem(value: t['value'] as int, child: Text(tr(t['label'] as String))),
                    ).toList(),
                    onChanged: (v) => setDialogState(() => requestType = v!),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(title: Text(tr('Đang hoạt động')), value: isActive, onChanged: (v) => setDialogState(() => isActive = v), contentPadding: EdgeInsets.zero),
                  const Divider(height: 32),
                  Row(
                    children: [
                      Text(tr('Các bước duyệt'), style: TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            steps.add({
                              'name': 'Bước ${steps.length + 1}',
                              'approverType': 1,
                              'isRequired': true,
                              'timeoutAction': 1,
                            });
                          });
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(tr('Thêm bước')),
                      ),
                    ],
                  ),
                  ...steps.asMap().entries.map((entry) {
                    final i = entry.key;
                    final step = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Text(tr('Bước ${i + 1}'), style: const TextStyle(fontWeight: FontWeight.w600)),
                                const Spacer(),
                                IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), onPressed: () => setDialogState(() => steps.removeAt(i))),
                              ],
                            ),
                            TextField(
                              controller: TextEditingController(text: tr(step['name']?.toString() ?? '')),
                              decoration: InputDecoration(labelText: tr('Tên bước'), isDense: true),
                              onChanged: (v) => step['name'] = v,
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<int>(
                              initialValue: step['approverType'] as int?,
                              decoration: InputDecoration(labelText: tr('Loại người duyệt'), isDense: true),
                              items: [
                                DropdownMenuItem(value: 1, child: Text(tr('Quản lý trực tiếp'))),
                                DropdownMenuItem(value: 2, child: Text(tr('Theo chức vụ'))),
                                DropdownMenuItem(value: 3, child: Text(tr('Nhân viên cụ thể'))),
                                DropdownMenuItem(value: 4, child: Text(tr('Trưởng phòng'))),
                                DropdownMenuItem(value: 5, child: Text(tr('Cấp trên bất kỳ'))),
                              ],
                              onChanged: (v) => setDialogState(() => step['approverType'] = v),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
            ),
          );
          Future<Null> onSave() async {
                if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) return;
                Navigator.pop(ctx);
                final resp = await _api.updateApprovalFlow(flow.id, {
                  'code': codeCtrl.text.trim(),
                  'name': nameCtrl.text.trim(),
                  'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                  'requestType': requestType,
                  'priority': priority,
                  'isActive': isActive,
                  'steps': steps.map((s) => {
                    'name': s['name'],
                    'approverType': s['approverType'],
                    'approverPositionId': s['approverPositionId'],
                    'approverEmployeeId': s['approverEmployeeId'],
                    'isRequired': s['isRequired'] ?? true,
                    'timeoutAction': s['timeoutAction'] ?? 1,
                    'maxWaitHours': s['maxWaitHours'],
                  }).toList(),
                });
                _handleApiResponse(resp, 'Cập nhật luồng duyệt');
                _loadTabData(3);
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr('Sửa luồng duyệt')),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            title: Text(tr('Sửa luồng duyệt')),
            content: SizedBox(width: 500, child: formContent),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
              FilledButton(onPressed: onSave, child: Text(tr('Lưu'))),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeleteApprovalFlow(ApprovalFlow flow) {
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Xóa luồng duyệt')),
        content: Text(tr('Bạn có chắc muốn xóa luồng duyệt "${flow.name}"?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              final resp = await _api.deleteApprovalFlow(flow.id);
              _handleApiResponse(resp, 'Xóa luồng duyệt');
              _loadTabData(3);
            },
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
  }

  void _handleApiResponse(Map<String, dynamic> resp, String action) {
    if (resp['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Thành công', message: resp['message']?.toString() ?? '$action thành công');
    } else {
      appNotification.showError(title: 'Lỗi', message: resp['message']?.toString() ?? '$action thất bại');
    }
  }
}
