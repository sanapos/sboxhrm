import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../models/department.dart';
import '../l10n/app_localizations.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/notification_overlay.dart';

class DepartmentScreen extends StatefulWidget {
  const DepartmentScreen({super.key});

  @override
  State<DepartmentScreen> createState() => _DepartmentScreenState();
}

class _DepartmentScreenState extends State<DepartmentScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  List<Department> _departments = [];
  List<DepartmentTreeNode> _departmentTree = [];
  List<DepartmentSelectDto> _departmentOptions = [];
  List<dynamic> _employees = [];


  bool _isLoading = true;
  bool _isManager = false;
  String _searchQuery = '';
  bool _showInactive = false;
  bool _showMobileFilters = false;

  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  int _pageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  // Org chart zoom
  final TransformationController _transformationController =
      TransformationController();
  final GlobalKey _orgChartKey = GlobalKey();
  final GlobalKey _orgChartViewportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _fitOrgChartToCenter();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUserRole();
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _checkUserRole() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    setState(() {
      _isManager = authProvider.user?.role == 'Admin' ||
          authProvider.user?.role == 'Manager';
    });
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      // Load departments list
      final deptResult = await _apiService.getDepartments(
        pageNumber: _currentPage,
        pageSize: _pageSize,
        searchTerm: _searchQuery.isEmpty ? null : _searchQuery,
        isActive: _showInactive ? null : true,
      );
      if (deptResult['isSuccess'] == true && deptResult['data'] != null) {
        final data = deptResult['data'];
        _departments = (data['items'] as List?)
                ?.map((e) => Department.fromJson(e))
                .toList() ??
            [];
        _totalPages = data['totalPages'] ?? 1;
        _totalCount = data['totalItems'] ?? data['totalCount'] ?? (_totalPages * _pageSize);
      }

      // Load department tree
      final treeResult = await _apiService.getDepartmentTree(
        includeInactive: _showInactive,
      );
      if (treeResult['isSuccess'] == true && treeResult['data'] != null) {
        _departmentTree = (treeResult['data'] as List?)
                ?.map((e) => DepartmentTreeNode.fromJson(e))
                .toList() ??
            [];
      }

      // Load department options for dropdown
      final selectResult = await _apiService.getDepartmentsForSelect();
      if (selectResult['isSuccess'] == true && selectResult['data'] != null) {
        _departmentOptions = (selectResult['data'] as List?)
                ?.map((e) => DepartmentSelectDto.fromJson(e))
                .toList() ??
            [];
      }

      // Load employees for org chart matching (need all employees with departmentId)
      final empResult = await _apiService.getEmployees(pageSize: 9999);
      _employees = empResult;


    } catch (e) {
      debugPrint('Error loading department data: $e');
      _showError('Lỗi khi tải dữ liệu phòng ban');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    NotificationOverlayManager().showError(title: 'Lỗi', message: message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    NotificationOverlayManager().showSuccess(title: 'Thành công', message: message);
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD HIERARCHICAL LIST FROM FLAT DEPARTMENTS
  // ═══════════════════════════════════════════════════════════════

  /// Sắp xếp danh sách phòng ban theo cấu trúc cha-con
  List<Department> _buildHierarchicalList() {
    if (_departments.isEmpty) return [];

    // Tạo map theo parentId
    final Map<String?, List<Department>> childrenMap = {};
    for (final dept in _departments) {
      final parentId = dept.parentDepartmentId;
      childrenMap.putIfAbsent(parentId, () => []);
      childrenMap[parentId]!.add(dept);
    }

    // DFS để sắp xếp theo cha-con
    final result = <Department>[];
    void addWithChildren(String? parentId) {
      final children = childrenMap[parentId];
      if (children == null) return;
      children.sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));
      for (final child in children) {
        result.add(child);
        addWithChildren(child.id);
      }
    }

    addWithChildren(null);

    // Nếu có departments không nằm trong tree (cha không có trong list), add cuối
    final addedIds = result.map((d) => d.id).toSet();
    for (final dept in _departments) {
      if (!addedIds.contains(dept.id)) {
        result.add(dept);
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  // MAIN BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildHeader(),
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              tabs: [
                Tab(icon: const Icon(Icons.list_alt), text: _l10n.list),
                Tab(icon: const Icon(Icons.account_tree), text: _l10n.orgChart),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildListView(),
                      _buildOrgChartView(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.business,
                  color: Theme.of(context).primaryColor, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _l10n.deptManagement,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      _l10n.deptSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              if (_isManager) ...[
                if (Responsive.isMobile(context))
                  if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Department'))
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: () => _showDepartmentDialog(),
                    color: Theme.of(context).primaryColor,
                  )
                else
                if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Department'))
                ElevatedButton.icon(
                  onPressed: () => _showDepartmentDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(_l10n.addNew),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
              if (Responsive.isMobile(context))
                GestureDetector(
                  onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                  child: Stack(
                    children: [
                      Icon(
                        _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                        color: _showMobileFilters ? Colors.orange : Colors.grey[600],
                        size: 22,
                      ),
                      if (_searchQuery.isNotEmpty || _showInactive)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          if (!Responsive.isMobile(context) || _showMobileFilters) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: _l10n.searchDept,
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) {
                    _searchQuery = value;
                  },
                  onSubmitted: (_) {
                    _currentPage = 1;
                    _loadData();
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: Text(_l10n.inactive),
                selected: _showInactive,
                onSelected: (selected) {
                  setState(() => _showInactive = selected);
                  _currentPage = 1;
                  _loadData();
                },
              ),
            ],
          ),
          ], // end _showMobileFilters
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 1: HIERARCHICAL LIST VIEW
  // ═══════════════════════════════════════════════════════════════

  Widget _buildListView() {
    final hierarchicalList = _buildHierarchicalList();

    if (hierarchicalList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.business_center_outlined,
                size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _l10n.noDept,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 8),
            if (_isManager)
              ElevatedButton.icon(
                onPressed: () => _showDepartmentDialog(),
                icon: const Icon(Icons.add),
                label: Text(_l10n.createFirstDept),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Responsive.isMobile(context)
            ? ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: hierarchicalList.length,
                itemBuilder: (_, i) => Padding(
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
                    child: _buildDeptDeckItem(hierarchicalList[i]),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: hierarchicalList.length,
                itemBuilder: (context, index) {
                  final dept = hierarchicalList[index];
                  return _buildHierarchicalCard(dept);
                },
              ),
        ),
        if (_totalPages > 1 && !Responsive.isMobile(context)) _buildPagination(),
      ],
    );
  }

  Widget _buildDeptDeckItem(Department dept) {
    final levelColors = [
      const Color(0xFF0F2340), const Color(0xFF2E7D32), const Color(0xFFEF6C00),
      const Color(0xFF6A1B9A), const Color(0xFF00838F),
    ];
    final levelColor = levelColors[(dept.level ?? 0) % levelColors.length];

    return InkWell(
      onTap: () => _showDepartmentDetails(
          _departments.firstWhere((d) => d.id == dept.id, orElse: () => dept)),
      child: Padding(
        padding: EdgeInsets.only(left: 14.0 + (dept.level ?? 0) * 16, right: 14, top: 10, bottom: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: levelColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              dept.level == 0 ? Icons.corporate_fare : dept.level == 1 ? Icons.business : Icons.folder_outlined,
              color: levelColor, size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: levelColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(dept.code ?? '', style: TextStyle(color: levelColor, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(dept.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (!dept.isActive) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                  child: const Text('Ngừng', style: TextStyle(fontSize: 9)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  dept.managerName ?? _l10n.noManager,
                  '${dept.directEmployeeCount ?? 0} NV',
                ].join(' · '),
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

  Widget _buildHierarchicalCard(Department dept) {
    final levelColors = [
      const Color(0xFF0F2340), // Blue 800
      const Color(0xFF2E7D32), // Green 800
      const Color(0xFFEF6C00), // Orange 800
      const Color(0xFF6A1B9A), // Purple 800
      const Color(0xFF00838F), // Cyan 800
    ];
    final levelColor = levelColors[(dept.level ?? 0) % levelColors.length];
    final indent = (dept.level ?? 0) * 28.0;

    return Padding(
      padding: EdgeInsets.only(left: indent, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Vertical connecting line
          if ((dept.level ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: SizedBox(
                width: 24,
                height: 56,
                child: CustomPaint(
                  painter: _TreeLinePainter(color: levelColor.withValues(alpha: 0.4)),
                ),
              ),
            ),
          // Card
          Expanded(
            child: Card(
              margin: const EdgeInsets.only(bottom: 4),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: levelColor.withValues(alpha: dept.level == 0 ? 0.4 : 0.2),
                  width: dept.level == 0 ? 1.5 : 1,
                ),
              ),
              child: InkWell(
                onTap: () => _showDepartmentDetails(
                    _departments.firstWhere((d) => d.id == dept.id,
                        orElse: () => dept)),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: levelColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          dept.level == 0
                              ? Icons.corporate_fare
                              : dept.level == 1
                                  ? Icons.business
                                  : Icons.folder_outlined,
                          color: levelColor,
                          size: 22,
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
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: levelColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    dept.code ?? '',
                                    style: TextStyle(
                                      color: levelColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    dept.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: dept.level == 0 ? 15 : 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (!dept.isActive) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Ngừng',
                                        style: TextStyle(fontSize: 9)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.person_outline,
                                    size: 13, color: Colors.grey[500]),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    dept.managerName ?? _l10n.noManager,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Employee count badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline,
                                size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              '${dept.directEmployeeCount ?? 0}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            if (dept.totalEmployeeCount !=
                                dept.directEmployeeCount)
                              Text(
                                '/${dept.totalEmployeeCount ?? 0}',
                                style: TextStyle(
                                    color: Colors.grey[500], fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      // Actions
                      if (_isManager)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert,
                              size: 20, color: Colors.grey[400]),
                          padding: EdgeInsets.zero,
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                _showDepartmentDialog(department: dept);
                                break;
                              case 'delete':
                                _confirmDelete(dept);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            if (Provider.of<PermissionProvider>(context, listen: false).canEdit('Department'))
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  const Icon(Icons.edit, size: 18),
                                  const SizedBox(width: 8),
                                  Text(_l10n.edit2),
                                ],
                              ),
                            ),
                            if (Provider.of<PermissionProvider>(context, listen: false).canDelete('Department'))
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete,
                                      size: 18, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text(_l10n.delete,
                                      style: const TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 2: ORG CHART (SƠ ĐỒ TỔ CHỨC)
  // ═══════════════════════════════════════════════════════════════

  static const _orgColors = [
    Color(0xFF153058), // Level 0 - root departments
    Color(0xFF00796B), // Level 1 - sub departments
    Color(0xFFE65100), // Level 2
    Color(0xFF6A1B9A), // Level 3
    Color(0xFF00838F), // Level 4+
  ];

  Color _colorForDepth(int depth) => _orgColors[depth.clamp(0, _orgColors.length - 1)];

  void _fitOrgChartToCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final contentBox = _orgChartKey.currentContext?.findRenderObject() as RenderBox?;
      final viewportBox = _orgChartViewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (contentBox == null || viewportBox == null) return;

      final contentSize = contentBox.size;
      final viewportSize = viewportBox.size;

      // Calculate scale to fit content in viewport with some padding
      final scaleX = viewportSize.width / contentSize.width;
      final scaleY = viewportSize.height / contentSize.height;
      final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 1.0);

      // Center the content
      final scaledWidth = contentSize.width * scale;
      final scaledHeight = contentSize.height * scale;
      final dx = (viewportSize.width - scaledWidth) / 2;
      final dy = (viewportSize.height - scaledHeight) / 2;

      final matrix = Matrix4.identity()
        ..translate(dx > 0 ? dx : 0.0, dy > 0 ? dy : 0.0)
        ..scale(scale);
      _transformationController.value = matrix;
    });
  }

  Widget _buildOrgChartView() {
    if (_departmentTree.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.account_tree_outlined, size: 56, color: Color(0xFF1E3A5F)),
            ),
            const SizedBox(height: 20),
            Text('Chưa có cấu trúc phòng ban',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text('Thêm phòng ban để tạo sơ đồ tổ chức', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
        ),
      );
    }

    // Total stats across the entire tree
    final totalEmps = _departmentTree.fold<int>(0, (s, n) => s + (n.totalEmployeeCount ?? 0));
    int countAllDepts(List<DepartmentTreeNode> nodes) =>
        nodes.fold<int>(nodes.length, (s, n) => s + countAllDepts(n.children));
    final totalDepts = countAllDepts(_departmentTree);

    return Stack(
      children: [
        InteractiveViewer(
          key: _orgChartViewportKey,
          transformationController: _transformationController,
          boundaryMargin: const EdgeInsets.all(1000),
          minScale: 0.1,
          maxScale: 3.0,
          constrained: false,
          child: Padding(
            key: _orgChartKey,
            padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Company root card ──
                _buildCompanyCard(totalEmps, totalDepts),
                _verticalLine(const Color(0xFF153058), 32),
                // ── Root-level departments ──
                _buildChildrenRow(_departmentTree, 0),
              ],
            ),
          ),
        ),
        // Zoom controls
        Positioned(
          right: 16,
          bottom: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _zoomButton(Icons.add, () {
                  // ignore: deprecated_member_use
                  final c = _transformationController.value.clone()..scale(1.25, 1.25, 1.25);
                  _transformationController.value = c;
                }),
                Container(height: 1, width: 28, color: Colors.grey[200]),
                _zoomButton(Icons.remove, () {
                  // ignore: deprecated_member_use
                  final c = _transformationController.value.clone()..scale(0.8, 0.8, 0.8);
                  _transformationController.value = c;
                }),
                Container(height: 1, width: 28, color: Colors.grey[200]),
                _zoomButton(Icons.fit_screen_outlined, () {
                  _fitOrgChartToCenter();
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Đường nối dọc
  Widget _verticalLine(Color color, double height) =>
      Container(width: 2, height: height, color: color.withValues(alpha: 0.25));

  /// Card "CÔNG TY" đứng đầu sơ đồ
  Widget _buildCompanyCard(int totalEmps, int totalDepts) {
    return Container(
      width: 300,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF153058), Color(0xFF1E3A5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: const Color(0xFF153058).withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 10),
          Text(_l10n.company.toUpperCase(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, letterSpacing: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statBadge(Icons.people_outline, '$totalEmps NV'),
              const SizedBox(width: 10),
              _statBadge(Icons.business_outlined, '$totalDepts PB'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _zoomButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, size: 18, color: Colors.grey[700]),
      ),
    );
  }

  /// Vẽ hàng các node con ngang hàng + nối đường
  Widget _buildChildrenRow(List<DepartmentTreeNode> children, int depth) {
    if (children.isEmpty) return const SizedBox.shrink();

    final color = _colorForDepth(depth);

    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Horizontal connector across all siblings
          if (children.length > 1)
            Container(height: 2, color: color.withValues(alpha: 0.2)),
          // Children nodes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children.map((node) {
              final childColor = _colorForDepth(depth);
              final nextColor = _colorForDepth(depth + 1);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _verticalLine(childColor, 20),
                    _buildOrgCard(node, childColor, depth),
                    if (node.children.isNotEmpty) ...[
                      _verticalLine(nextColor, 26),
                      _buildChildrenRow(node.children, depth + 1),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgCard(DepartmentTreeNode node, Color color, int depth) {
    // Lấy danh sách nhân viên trong phòng ban
    final deptEmployees = _employees.where((e) {
      return e['departmentId']?.toString() == node.id;
    }).toList();

    return GestureDetector(
      onTap: () => _showDepartmentEmployees(node),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header bar with code + badge ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          depth == 0 ? Icons.corporate_fare : depth == 1 ? Icons.business : Icons.folder_outlined,
                          color: color,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(node.code ?? '',
                          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (!node.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(4)),
                      child: const Text('Ngừng', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  if (node.children.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('${node.children.length} PB con',
                        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),

            // ── Body ──
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  // Department name
                  Text(node.name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF18181B)),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Manager info
                  if (node.managerName != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              node.managerName!.isNotEmpty ? node.managerName![0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(node.managerName!,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF334155)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(_l10n.manager,
                                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.verified, size: 14, color: color.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_off_outlined, size: 14, color: Colors.orange[400]),
                          const SizedBox(width: 6),
                          Text('Chưa phân công quản lý',
                            style: TextStyle(fontSize: 11, color: Colors.orange[400], fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Employee avatars row + count
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Avatar stack (show up to 4)
                      if (deptEmployees.isNotEmpty)
                        SizedBox(
                          height: 28,
                          width: (deptEmployees.take(4).length * 20.0) + 8,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              for (var i = 0; i < deptEmployees.take(4).length; i++)
                                Positioned(
                                  left: i * 18.0,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _getEmployeeInitial(deptEmployees[i]),
                                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 10),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 6),
                      // Count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (node.directEmployeeCount ?? 0) > 0 ? color.withValues(alpha: 0.08) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (node.directEmployeeCount ?? 0) > 0 ? color.withValues(alpha: 0.2) : Colors.grey[300]!,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.people_outline, size: 13,
                              color: (node.directEmployeeCount ?? 0) > 0 ? color : Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '${node.directEmployeeCount ?? 0}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: (node.directEmployeeCount ?? 0) > 0 ? color : Colors.grey[600],
                              ),
                            ),
                            if (node.totalEmployeeCount != node.directEmployeeCount)
                              Text(' (${node.totalEmployeeCount ?? 0})',
                                style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.5)),
                              ),
                            Text(' NV', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getEmployeeInitial(dynamic emp) {
    final firstName = emp['firstName']?.toString() ?? '';
    final lastName = emp['lastName']?.toString() ?? '';
    if (lastName.isNotEmpty) return lastName[0].toUpperCase();
    if (firstName.isNotEmpty) return firstName[0].toUpperCase();
    return '?';
  }

  // ═══════════════════════════════════════════════════════════════
  // EMPLOYEE LIST POPUP
  // ═══════════════════════════════════════════════════════════════

  void _showDepartmentEmployees(DepartmentTreeNode node) {
    // Filter employees by departmentId
    final deptEmployees = _employees.where((e) {
      final deptId = e['departmentId']?.toString();
      return deptId == node.id;
    }).toList();

    // Sort by name
    deptEmployees.sort((a, b) {
      final nameA = '${a['lastName'] ?? ''} ${a['firstName'] ?? ''}'.trim();
      final nameB = '${b['lastName'] ?? ''} ${b['firstName'] ?? ''}'.trim();
      return nameA.compareTo(nameB);
    });

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people, color: Colors.blue[700], size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Colors.blue[800],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${deptEmployees.length} employees',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 20),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
              // Employee list
              Flexible(
                child: deptEmployees.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_off_outlined,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              _l10n.noEmployeesInDept,
                              style: TextStyle(color: Colors.grey[600]),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: deptEmployees.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 24, indent: 56, color: Colors.grey[200]),
                        itemBuilder: (_, i) {
                          final emp = deptEmployees[i];
                          final fullName =
                              '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                                  .trim();
                          final position = emp['position'] as String?;
                          final empCode = emp['employeeCode'] ?? emp['enrollNumber'] ?? '';
                          final photo = emp['photo'] as String?;

                          return ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.blue[100],
                              backgroundImage:
                                  photo != null && photo.isNotEmpty
                                      ? NetworkImage(photo)
                                      : null,
                              onBackgroundImageError: photo != null && photo.isNotEmpty ? (_, __) {} : null,
                              child: photo == null || photo.isEmpty
                                  ? Text(
                                      fullName.isNotEmpty
                                          ? fullName[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Colors.blue[700],
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              fullName.isNotEmpty ? fullName : 'Chưa có tên',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (position != null && position.isNotEmpty)
                                  Row(
                                    children: [
                                      Icon(Icons.work_outline,
                                          size: 12, color: Colors.orange[600]),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          position,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                if (empCode.toString().isNotEmpty)
                                  Row(
                                    children: [
                                      Icon(Icons.badge_outlined,
                                          size: 12, color: Colors.grey[500]),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Mã NV: $empCode',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            dense: true,
                            visualDensity: const VisualDensity(vertical: -1),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // PAGINATION
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPagination() {
    final start = _totalCount > 0 ? (_currentPage - 1) * _pageSize + 1 : 0;
    final end = (_currentPage * _pageSize).clamp(0, _totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 8),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _pageSize,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() { _pageSize = v; _currentPage = 1; });
                        _loadData();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage = 1);
                    _loadData();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentPage > 1
                ? () {
                    setState(() => _currentPage--);
                    _loadData();
                  }
                : null,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Hiển thị $start-$end / $_totalCount',
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadData();
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed: _currentPage < _totalPages
                ? () {
                    setState(() => _currentPage = _totalPages);
                    _loadData();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // DIALOGS
  // ═══════════════════════════════════════════════════════════════

  void _showDepartmentDetails(Department dept) {
    // Find employees belonging to this department
    final deptEmployees = _employees.where((e) {
      return e['departmentId']?.toString() == dept.id;
    }).toList();

    // Determine level color
    const levelColors = [
      Color(0xFF153058),
      Color(0xFF00796B),
      Color(0xFFE65100),
      Color(0xFF6A1B9A),
      Color(0xFF00838F),
    ];
    final color = levelColors[(dept.level ?? 0).clamp(0, levelColors.length - 1)];

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header with gradient ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        dept.level == 0 ? Icons.corporate_fare : dept.level == 1 ? Icons.business : Icons.folder_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dept.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 17),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(dept.code ?? '',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12, letterSpacing: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),

              // ── Body ──
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status + Level badges
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: dept.isActive ? const Color(0xFFDCFCE7) : Colors.grey[200],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  dept.isActive ? Icons.check_circle : Icons.cancel,
                                  size: 14,
                                  color: dept.isActive ? const Color(0xFF16A34A) : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dept.isActive ? _l10n.active : _l10n.stopped,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: dept.isActive ? const Color(0xFF16A34A) : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Cấp ${dept.level}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Thứ tự: ${dept.sortOrder}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue[700]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // ── Info section ──
                      _detailSection('Thông tin chung', Icons.info_outline, [
                        _detailInfoRow(Icons.business, 'Phòng ban cha', dept.parentDepartmentName ?? 'Không có (Phòng ban gốc)'),
                        if (dept.description != null && dept.description!.isNotEmpty)
                          _detailInfoRow(Icons.description_outlined, 'Mô tả', dept.description!),
                      ]),
                      const SizedBox(height: 16),

                      // ── Manager section ──
                      _detailSection('Quản lý', Icons.person_outline, [
                        if (dept.managerName != null) ...[
                          Builder(builder: (context) {
                            // Find manager position from employees list
                            final managerEmp = _employees.firstWhere(
                              (e) => e['id']?.toString() == dept.managerId,
                              orElse: () => null,
                            );
                            final managerPosition = managerEmp?['position']?.toString() ?? '';
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAFAFA),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE4E4E7)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)]),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      dept.managerName![0].toUpperCase(),
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(dept.managerName!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                        Text(
                                          managerPosition.isNotEmpty ? managerPosition : 'Quản lý phòng ban',
                                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.verified, size: 18, color: color.withValues(alpha: 0.6)),
                                ],
                              ),
                            );
                          }),
                        ] else
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.person_off_outlined, size: 18, color: Colors.orange[400]),
                                const SizedBox(width: 8),
                                Text('Chưa phân công quản lý',
                                  style: TextStyle(fontSize: 13, color: Colors.orange[400], fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                      ]),
                      const SizedBox(height: 16),

                      // ── Employee stats ──
                      _detailSection('Nhân viên', Icons.people_outline, [
                        Row(
                          children: [
                            Expanded(
                              child: _statCard('Trực tiếp', '${dept.directEmployeeCount ?? 0}', Icons.person, color),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _statCard('Tổng cộng', '${dept.totalEmployeeCount ?? 0}', Icons.groups, const Color(0xFF1E3A5F)),
                            ),
                          ],
                        ),
                        if (deptEmployees.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: deptEmployees.length,
                              itemBuilder: (context, index) {
                                final emp = deptEmployees[index];
                                final firstName = emp['firstName']?.toString() ?? '';
                                final lastName = emp['lastName']?.toString() ?? '';
                                final fullName = '$lastName $firstName'.trim();
                                final position = emp['position']?.toString() ?? '';
                                final isManager = emp['id']?.toString() == dept.managerId;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: isManager ? color.withValues(alpha: 0.04) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: isManager ? Border.all(color: color.withValues(alpha: 0.15)) : null,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: color.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            lastName.isNotEmpty ? lastName[0].toUpperCase() : '?',
                                            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(fullName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                              if (position.isNotEmpty)
                                                Text(position, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                            ],
                                          ),
                                        ),
                                        if (isManager)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text('QL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 16),

                      // ── Positions ──
                      if (dept.positions != null && dept.positions!.isNotEmpty)
                        _detailSection('Chức vụ phòng ban', Icons.badge_outlined, [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: dept.positions!.map((pos) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color.withValues(alpha: 0.15)),
                              ),
                              child: Text(pos, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
                            )).toList(),
                          ),
                        ]),

                      if (dept.positions != null && dept.positions!.isNotEmpty)
                        const SizedBox(height: 16),

                      // ── Timestamps ──
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.schedule, size: 14, color: Colors.grey[400]),
                            const SizedBox(width: 6),
                            Text('Tạo: ${DateFormat('dd/MM/yyyy HH:mm').format(dept.createdAt ?? DateTime.now())}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                            ),
                            if (dept.updatedAt != null) ...[
                              const SizedBox(width: 16),
                              Icon(Icons.update, size: 14, color: Colors.grey[400]),
                              const SizedBox(width: 4),
                              Text('Cập nhật: ${DateFormat('dd/MM/yyyy HH:mm').format(dept.updatedAt!)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Footer actions ──
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Đóng'),
                    ),
                    if (_isManager) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showDepartmentDialog(department: dept);
                        },
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Chỉnh sửa'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailSection(String title, IconData icon, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.grey[700])),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _detailInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[400]),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500]), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  void _showDepartmentDialog({Department? department}) {
    final isEdit = department != null;
    final formKey = GlobalKey<FormState>();

    final codeController = TextEditingController(text: department?.code ?? '');
    final nameController = TextEditingController(text: department?.name ?? '');
    final descController =
        TextEditingController(text: department?.description ?? '');
    final sortOrderController =
        TextEditingController(text: '${department?.sortOrder ?? 0}');

    String? selectedParentId = department?.parentDepartmentId;
    String? selectedManagerId = department?.managerId;
    bool isActive = department?.isActive ?? true;

    // Chức vụ trong phòng ban
    final List<String> defaultPositionSuggestions = [
      'Giám đốc', 'Phó Giám đốc', 'Trưởng phòng', 'Phó phòng',
      'Trưởng nhóm', 'Phó nhóm', 'Nhân viên', 'Thực tập sinh',
      'Chuyên viên', 'Kế toán trưởng', 'Thư ký', 'Tổ trưởng',
    ];
    List<String> selectedPositions = department?.positions != null
        ? List<String>.from(department!.positions!)
        : [];

    final isMobile = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Form(
              key: formKey,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Mã phòng ban *',
                        hintText: 'VD: IT, HR, SALES...',
                        prefixIcon: Icon(Icons.code),
                      ),
                      validator: (v) =>
                          v?.isEmpty == true ? 'Vui lòng nhập mã' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên phòng ban *',
                        hintText: 'VD: Phòng Công nghệ Thông tin',
                        prefixIcon: Icon(Icons.business),
                      ),
                      validator: (v) =>
                          v?.isEmpty == true ? 'Vui lòng nhập tên' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedParentId,
                      decoration: const InputDecoration(
                        labelText: 'Phòng ban cha',
                        prefixIcon: Icon(Icons.account_tree),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Không có (Phòng ban gốc)'),
                        ),
                        ..._departmentOptions
                            .where((d) => d.id != department?.id)
                            .map((d) => DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    '${'  ' * (d.level ?? 0)}${d.displayName}',
                                  ),
                                )),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedParentId = v),
                    ),
                    const SizedBox(height: 16),
                    // Quản lý phòng ban (người có chức vụ cao nhất)
                    DropdownButtonFormField<String>(
                      initialValue: selectedManagerId,
                      decoration: const InputDecoration(
                        labelText: 'Quản lý phòng ban',
                        prefixIcon: Icon(Icons.person),
                        hintText: 'Chọn người quản lý...',
                      ),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Chưa phân công', style: TextStyle(color: Colors.grey)),
                        ),
                        ..._employees.map((emp) {
                          final empId = emp['id']?.toString() ?? '';
                          final firstName = emp['firstName']?.toString() ?? '';
                          final lastName = emp['lastName']?.toString() ?? '';
                          final fullName = '$lastName $firstName'.trim();
                          final position = emp['position']?.toString() ?? '';
                          return DropdownMenuItem(
                            value: empId,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fullName,
                                    style: const TextStyle(fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (position.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      position,
                                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedManagerId = v),
                    ),
                    const SizedBox(height: 16),
                    // Chức vụ trong phòng ban
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Chức vụ trong phòng ban',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.fromLTRB(12, 12, 12, 8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (selectedPositions.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: selectedPositions.map((pos) => Chip(
                                label: Text(pos, style: const TextStyle(fontSize: 13)),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () {
                                  setDialogState(() => selectedPositions.remove(pos));
                                },
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              )).toList(),
                            ),
                          const SizedBox(height: 6),
                          Autocomplete<String>(
                            optionsBuilder: (TextEditingValue textEditingValue) {
                              if (textEditingValue.text.isEmpty) {
                                return defaultPositionSuggestions
                                    .where((s) => !selectedPositions.contains(s));
                              }
                              return defaultPositionSuggestions
                                  .where((s) => !selectedPositions.contains(s))
                                  .where((s) => s.toLowerCase().contains(
                                      textEditingValue.text.toLowerCase()));
                            },
                            fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                              return TextField(
                                controller: controller,
                                focusNode: focusNode,
                                decoration: const InputDecoration(
                                  hintText: 'Nhập chức vụ hoặc chọn gợi ý...',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                                ),
                                onSubmitted: (value) {
                                  final trimmed = value.trim();
                                  if (trimmed.isNotEmpty && !selectedPositions.contains(trimmed)) {
                                    setDialogState(() => selectedPositions.add(trimmed));
                                  }
                                  controller.clear();
                                },
                              );
                            },
                            onSelected: (String selection) {
                              if (!selectedPositions.contains(selection)) {
                                setDialogState(() => selectedPositions.add(selection));
                              }
                            },
                          ),
                          if (selectedPositions.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: defaultPositionSuggestions.take(6).map((s) => ActionChip(
                                  label: Text(s, style: const TextStyle(fontSize: 12)),
                                  onPressed: () {
                                    if (!selectedPositions.contains(s)) {
                                      setDialogState(() => selectedPositions.add(s));
                                    }
                                  },
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                )).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả',
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: sortOrderController,
                      decoration: const InputDecoration(
                        labelText: 'Thứ tự hiển thị',
                        prefixIcon: Icon(Icons.sort),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    if (isEdit) ...[
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: Text(_l10n.active),
                        subtitle: Text(
                          isActive
                              ? 'Phòng ban đang hoạt động'
                              : 'Phòng ban đã ngừng',
                        ),
                        value: isActive,
                        onChanged: (v) => setDialogState(() => isActive = v),
                      ),
                    ],
                  ],
                ),
              ),
            );
          Future<Null> onSave() async {
                if (!formKey.currentState!.validate()) return;

                Navigator.pop(context);

                final result = isEdit
                    ? await _apiService.updateDepartment(
                        departmentId: department.id,
                        code: codeController.text.trim(),
                        name: nameController.text.trim(),
                        description: descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                        parentDepartmentId: selectedParentId,
                        managerId: selectedManagerId,
                        sortOrder:
                            int.tryParse(sortOrderController.text) ?? 0,
                        isActive: isActive,
                        positions: selectedPositions,
                      )
                    : await _apiService.createDepartment(
                        code: codeController.text.trim(),
                        name: nameController.text.trim(),
                        description: descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                        parentDepartmentId: selectedParentId,
                        managerId: selectedManagerId,
                        sortOrder:
                            int.tryParse(sortOrderController.text) ?? 0,
                        positions: selectedPositions,
                      );

                if (result['isSuccess'] == true) {
                  _showSuccess(isEdit
                      ? 'Cập nhật phòng ban thành công'
                      : 'Tạo phòng ban thành công');
                  _loadData(showLoading: false);
                } else {
                  _showError(result['message'] ?? 'Có lỗi xảy ra');
                }
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(isEdit ? 'Chỉnh sửa phòng ban' : 'Tạo phòng ban mới'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                        const SizedBox(width: 12),
                        ElevatedButton(onPressed: onSave, child: Text(isEdit ? 'Cập nhật' : 'Tạo mới')),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isEdit ? Icons.edit : Icons.add_business,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(isEdit ? 'Chỉnh sửa phòng ban' : 'Tạo phòng ban mới'),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 500,
              child: formContent,
            ),
            actions: [AppDialogActions(
              onCancel: () => Navigator.pop(context),
              onConfirm: onSave,
              confirmLabel: isEdit ? 'Cập nhật' : 'Tạo mới',
              confirmIcon: Icons.save,
            )],
          );
        },
      ),
    );
  }

  void _confirmDelete(Department dept) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Xác nhận xóa'),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa phòng ban "${dept.name}"?\n\n'
          'Lưu ý: Không thể xóa phòng ban có phòng ban con hoặc có nhân viên.',
        ),
        actions: [AppDialogActions.delete(
          onCancel: () => Navigator.pop(context),
          onConfirm: () async {
            Navigator.pop(context);
            final result = await _apiService.deleteDepartment(dept.id);
            if (result['isSuccess'] == true) {
              _showSuccess('Đã xóa phòng ban');
              await _loadData(showLoading: false);
            } else {
              _showError(result['message'] ?? 'Không thể xóa phòng ban');
            }
          },
        )],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CUSTOM PAINTER: Tree connecting line (L-shape)
// ═══════════════════════════════════════════════════════════════

class _TreeLinePainter extends CustomPainter {
  final Color color;

  _TreeLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height / 2);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
