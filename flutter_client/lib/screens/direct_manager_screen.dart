import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_collapsible_overview.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class DirectManagerScreen extends StatefulWidget {
  const DirectManagerScreen({super.key});

  @override
  State<DirectManagerScreen> createState() => _DirectManagerScreenState();
}

class _DirectManagerScreenState extends State<DirectManagerScreen> {
  final ApiService _apiService = ApiService();
  List<Employee> _allEmployees = [];
  List<Employee> _managers = [];
  List<Employee> _filteredManagers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterDepartment = 'Tất cả';
  String _filterPosition = 'Tất cả';

  List<String> _departments = ['Tất cả'];
  List<String> _positions = ['Tất cả'];

  // All unique positions found in data
  List<String> _allPositions = [];
  // Positions that are considered "manager" (excluded = 'Nhân viên' by default)
  Set<String> _excludedPositions = {'Nhân viên'};
  int _currentPage = 1;
  int _pageSize = 20;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  bool _showOverviewPanel = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getEmployeesForSelect();
      if (mounted) {
        _allEmployees = data.map((e) => Employee.fromJson(e)).toList();

        // Collect all unique positions
        final posSet = <String>{};
        for (final emp in _allEmployees) {
          final pos = emp.position?.trim() ?? '';
          if (pos.isNotEmpty) posSet.add(pos);
        }
        _allPositions = posSet.toList()..sort((a, b) => _positionPriority(a) - _positionPriority(b));

        _rebuildManagerList();
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading managers: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        appNotification.showError(title: 'Lỗi', message: tr('Không thể tải danh sách quản lý'));
      }
    }
  }

  void _rebuildManagerList() {
    // Filter: only employees whose position is NOT in excluded set and position is not empty
    _managers = _allEmployees.where((emp) {
      final pos = emp.position?.trim() ?? '';
      return pos.isNotEmpty && !_excludedPositions.contains(pos);
    }).toList();

    // Sort by position priority then name
    _managers.sort((a, b) {
      final posOrder = _positionPriority(a.position) - _positionPriority(b.position);
      if (posOrder != 0) return posOrder;
      return a.fullName.compareTo(b.fullName);
    });

    // Build filter lists
    final deptSet = <String>{};
    final posFilterSet = <String>{};
    for (final m in _managers) {
      if (m.department != null && m.department!.isNotEmpty) {
        deptSet.add(m.department!);
      }
      if (m.position != null && m.position!.isNotEmpty) {
        posFilterSet.add(m.position!);
      }
    }
    _departments = ['Tất cả', ...deptSet.toList()..sort()];
    _positions = ['Tất cả', ...posFilterSet.toList()..sort((a, b) => _positionPriority(a) - _positionPriority(b))];

    // Reset filters if current value no longer valid
    if (!_departments.contains(_filterDepartment)) _filterDepartment = 'Tất cả';
    if (!_positions.contains(_filterPosition)) _filterPosition = 'Tất cả';

    _applyFilters();
  }

  int _positionPriority(String? position) {
    switch (position) {
      case 'Tổng giám đốc':
        return 0;
      case 'Giám đốc':
        return 1;
      case 'Phó giám đốc':
        return 2;
      case 'Kế toán trưởng':
        return 3;
      case 'Trưởng phòng':
        return 4;
      case 'Phó phòng':
        return 5;
      case 'Trưởng nhóm':
        return 6;
      default:
        return 7;
    }
  }

  void _applyFilters() {
    _filteredManagers = _managers.where((emp) {
      final matchesSearch = _searchQuery.isEmpty ||
          emp.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.employeeCode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (emp.phone?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

      final matchesDepartment =
          _filterDepartment == 'Tất cả' || emp.department == _filterDepartment;

      final matchesPosition =
          _filterPosition == 'Tất cả' || emp.position == _filterPosition;

      return matchesSearch && matchesDepartment && matchesPosition;
    }).toList();
    _currentPage = 1;
  }

  Color _positionColor(String? position) {
    switch (position) {
      case 'Tổng giám đốc':
        return Colors.red[700]!;
      case 'Giám đốc':
        return Colors.red[500]!;
      case 'Phó giám đốc':
        return Colors.orange[700]!;
      case 'Kế toán trưởng':
        return Colors.purple[600]!;
      case 'Trưởng phòng':
        return Colors.blue[700]!;
      case 'Phó phòng':
        return Colors.blue[400]!;
      case 'Trưởng nhóm':
        return Colors.teal[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  IconData _positionIcon(String? position) {
    switch (position) {
      case 'Tổng giám đốc':
      case 'Giám đốc':
      case 'Phó giám đốc':
        return Icons.stars;
      case 'Kế toán trưởng':
        return Icons.account_balance;
      case 'Trưởng phòng':
      case 'Phó phòng':
        return Icons.supervisor_account;
      case 'Trưởng nhóm':
        return Icons.group;
      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(isMobile),
            const SizedBox(height: 12),
            Expanded(
              child: HrmResponsiveListLayout(
                headerSections: _directManagerHeaderSections(isMobile),
                desktopBody: _isLoading
                    ? const LoadingWidget()
                    : _filteredManagers.isEmpty
                        ? const EmptyState(
                            icon: Icons.supervisor_account,
                            title: 'Không có quản lý',
                            description: 'Không tìm thấy nhân sự phù hợp',
                          )
                        : _buildManagersList(),
                mobileSlivers: (_) => _directManagerMobileSlivers(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _directManagerHeaderSections(bool isMobile) => [
        _buildOverviewSection(isMobile),
        const SizedBox(height: 12),
      ];

  Widget _buildOverviewSection(bool isMobile) {
    return HrmCollapsibleOverview(
      expanded: _showOverviewPanel,
      onToggle: () =>
          setState(() => _showOverviewPanel = !_showOverviewPanel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStats(isMobile),
          const SizedBox(height: 10),
          _buildFilters(isMobile),
        ],
      ),
    );
  }

  List<Widget> _directManagerMobileSlivers() {
    if (_isLoading) {
      return [
        HrmScrollSlivers.fillRemaining(child: const LoadingWidget()),
      ];
    }
    if (_filteredManagers.isEmpty) {
      return [
        HrmScrollSlivers.fillRemaining(
          child: const EmptyState(
            icon: Icons.supervisor_account,
            title: 'Không có quản lý',
            description: 'Không tìm thấy nhân sự phù hợp',
          ),
        ),
      ];
    }
    final totalCount = _filteredManagers.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedList = _filteredManagers.sublist(
        startIndex.clamp(0, totalCount), endIndex);

    final slivers = HrmScrollSlivers.fromListViewBuilder(
      itemCount: paginatedList.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemBuilder: (_, index) => Padding(
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
          child: _buildManagerDeckItem(paginatedList[index]),
        ),
      ),
    );
    if (totalPages > 1) {
      slivers.add(HrmScrollSlivers.toBox(_buildMobilePagination(
          totalCount, startIndex, endIndex, page, totalPages)));
    }
    return slivers;
  }

  Widget _buildMobilePagination(
      int totalCount, int startIndex, int endIndex, int page, int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr('Hiển thị ${startIndex + 1}-$endIndex / $totalCount'),
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          Row(children: [
            IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed:
                    page > 1 ? () => setState(() => _currentPage--) : null,
                visualDensity: VisualDensity.compact),
            Text(tr('$page / $totalPages'),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: page < totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
                visualDensity: VisualDensity.compact),
          ]),
        ],
      ),
    );
  }

  Widget _buildManagersList() {
    final totalCount = _filteredManagers.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedList = _filteredManagers.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: paginatedList.length,
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
                  child: _buildManagerDeckItem(paginatedList[index]),
                ),
              ),
            ),
          ),
        ),
        if (totalPages > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(tr('Hiển thị ${startIndex + 1}-$endIndex / $totalCount'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Hiển thị:'), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                          items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text(tr('$s')))).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() { _pageSize = v; _currentPage = 1; });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: page > 1 ? () => setState(() => _currentPage--) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(tr('$page / $totalPages'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages ? () => setState(() => _currentPage++) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Row(
      children: [
        Icon(Icons.supervisor_account, size: 28, color: Colors.blue[700]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Quản lý trực tiếp'),
                style: TextStyle(
                  fontSize: isMobile ? 18 : 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(tr('Danh sách nhân sự có chức vụ quản lý'),
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        if (Provider.of<PermissionProvider>(context, listen: false)
            .canEdit('Employee'))
          IconButton(
            onPressed: _showPositionSettings,
            icon: const Icon(Icons.tune),
            tooltip: tr('Thiết lập chức vụ'),
          ),
      ],
    );
  }

  Widget _buildStats(bool isMobile) {
    // Group by position
    final positionCounts = <String, int>{};
    for (final m in _managers) {
      final pos = m.position ?? 'Khác';
      positionCounts[pos] = (positionCounts[pos] ?? 0) + 1;
    }

    final sortedPositions = positionCounts.entries.toList()
      ..sort((a, b) => _positionPriority(a.key) - _positionPriority(b.key));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Total
          _buildStatChip(
            icon: Icons.people,
            label: 'Tổng',
            count: _managers.length,
            color: Colors.blue,
          ),
          const SizedBox(width: 8),
          ...sortedPositions.map((e) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildStatChip(
                  icon: _positionIcon(e.key),
                  label: e.key,
                  count: e.value,
                  color: _positionColor(e.key),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            tr(label),
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              tr('$count'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isMobile) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        // Search
        SizedBox(
          width: isMobile ? double.infinity : 280,
          child: TextField(
            onChanged: (v) => setState(() {
              _searchQuery = v;
              _applyFilters();
            }),
            decoration: InputDecoration(
              hintText: tr('Tìm theo tên, mã NV, SĐT...'),
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        // Department filter
        SizedBox(
          width: isMobile ? double.infinity : 200,
          child: DropdownButtonFormField<String>(
            initialValue: _filterDepartment,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Phòng ban'),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: _departments
                .map((d) => DropdownMenuItem(value: d, child: Text(tr(d), overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() {
              _filterDepartment = v!;
              _applyFilters();
            }),
          ),
        ),
        // Position filter
        SizedBox(
          width: isMobile ? double.infinity : 200,
          child: DropdownButtonFormField<String>(
            initialValue: _filterPosition,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Chức vụ'),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: _positions
                .map((p) => DropdownMenuItem(value: p, child: Text(tr(p), overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setState(() {
              _filterPosition = v!;
              _applyFilters();
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildManagerDeckItem(Employee manager) {
    final color = _positionColor(manager.position);
    return InkWell(
      onTap: () => _showManagerDetails(manager),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: color.withValues(alpha: 0.1),
              backgroundImage: manager.avatarUrl != null && manager.avatarUrl!.isNotEmpty
                  ? _apiService.storeImageProvider(manager.avatarUrl!)
                  : null,
              onBackgroundImageError: manager.avatarUrl != null && manager.avatarUrl!.isNotEmpty ? (_, __) {} : null,
              child: manager.avatarUrl == null || manager.avatarUrl!.isEmpty
                  ? Text(tr(manager.fullName.isNotEmpty ? manager.fullName[0].toUpperCase() : '?'), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(manager.fullName), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    tr([
                      manager.employeeCode,
                      if (manager.department != null) manager.department!,
                      if (manager.position != null) manager.position!,
                    ].join(' · ')),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (manager.phone != null && manager.phone!.isNotEmpty)
              InkWell(
                onTap: () => _makePhoneCall(manager.phone!),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.phone, size: 18, color: Colors.green[600]),
                ),
              ),
            if (manager.email != null && manager.email!.isNotEmpty)
              InkWell(
                onTap: () => _sendEmail(manager.email!),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.email, size: 18, color: Colors.blue[600]),
                ),
              ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTION HELPERS
  // ═══════════════════════════════════════════════════════════════

  Future<void> _makePhoneCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        appNotification.showError(title: 'Lỗi', message: tr('Không thể gọi điện tới $phone'));
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi', message: tr('Không thể gọi điện tới $phone'));
    }
  }

  Future<void> _sendEmail(String email) async {
    final uri = Uri(scheme: 'mailto', path: email);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        appNotification.showError(title: 'Lỗi', message: tr('Không thể gửi email tới $email'));
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi', message: tr('Không thể gửi email tới $email'));
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // POSITION SETTINGS DIALOG
  // ═══════════════════════════════════════════════════════════════

  void _showPositionSettings() {
    final tempExcluded = Set<String>.from(_excludedPositions);

    showDialog(
      context: context,
      builder: (ctx) {
        final isMobile = MediaQuery.of(ctx).size.width < 768;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final quickActions = Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setDialogState(() => tempExcluded.clear()),
                    icon: const Icon(Icons.select_all, size: 16),
                    label: Text(tr('Chọn tất cả'), style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => setDialogState(() {
                      tempExcluded.clear();
                      tempExcluded.addAll(_allPositions);
                    }),
                    icon: const Icon(Icons.deselect, size: 16),
                    label: Text(tr('Bỏ chọn tất cả'), style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            );

            final positionList = _allPositions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(tr('Chưa có dữ liệu chức vụ'), style: TextStyle(color: Colors.grey[500])),
                  )
                : ListView.builder(
                    shrinkWrap: !isMobile,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _allPositions.length,
                    itemBuilder: (_, i) {
                      final pos = _allPositions[i];
                      final isIncluded = !tempExcluded.contains(pos);
                      final color = _positionColor(pos);
                      final count = _allEmployees.where((e) => e.position == pos).length;
                      return CheckboxListTile(
                        value: isIncluded,
                        onChanged: (v) => setDialogState(() {
                          if (v == true) { tempExcluded.remove(pos); } else { tempExcluded.add(pos); }
                        }),
                        secondary: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: Icon(_positionIcon(pos), size: 18, color: color),
                        ),
                        title: Text(tr(pos), style: const TextStyle(fontSize: 14)),
                        subtitle: Text(tr('$count nhân viên'), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                        dense: true,
                        activeColor: Colors.blue[700],
                        controlAffinity: ListTileControlAffinity.trailing,
                      );
                    },
                  );

            final actions = AppDialogActions(
              onCancel: () => Navigator.pop(ctx),
              onConfirm: () {
                Navigator.pop(ctx);
                setState(() {
                  _excludedPositions = tempExcluded;
                  _rebuildManagerList();
                });
              },
              confirmLabel: 'Áp dụng',
              confirmIcon: Icons.check,
            );

            if (isMobile) {
              return Dialog(
                insetPadding: EdgeInsets.zero,
                shape: const RoundedRectangleBorder(),
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Scaffold(
                    appBar: AppBar(
                      leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      title: Row(children: [
                        Icon(Icons.tune, size: 20, color: Colors.blue),
                        SizedBox(width: 10),
                        Expanded(child: Text(tr('Thiết lập chức vụ'))),
                      ]),
                      elevation: 0.5,
                    ),
                    body: Column(
                      children: [
                        quickActions,
                        const Divider(height: 1),
                        Expanded(child: positionList),
                      ],
                    ),
                    bottomNavigationBar: Container(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(ctx).padding.bottom),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surface,
                        border: Border(top: BorderSide(color: Theme.of(ctx).dividerColor, width: 0.5)),
                      ),
                      child: SafeArea(top: false, child: actions),
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
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
                          Icon(Icons.tune, color: Colors.blue[700], size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr('Thiết lập chức vụ'), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blue[800])),
                                const SizedBox(height: 2),
                                Text(tr('Chọn chức vụ hiển thị trong danh sách'), style: TextStyle(fontSize: 12, color: Colors.blue[600])),
                              ],
                            ),
                          ),
                          IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, size: 20), splashRadius: 18),
                        ],
                      ),
                    ),
                    quickActions,
                    const Divider(height: 24),
                    Flexible(child: positionList),
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: actions,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // MANAGER DETAILS
  // ═══════════════════════════════════════════════════════════════

  void _showManagerDetails(Employee manager) {
    final color = _positionColor(manager.position);
    showDialog(
      context: context,
      builder: (ctx) {
        final isMobile = MediaQuery.of(ctx).size.width < 768;

        final headerContent = Column(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
              ),
              child: CircleAvatar(
                radius: 36,
                backgroundColor: color.withValues(alpha: 0.1),
                backgroundImage: manager.avatarUrl != null && manager.avatarUrl!.isNotEmpty
                    ? _apiService.storeImageProvider(manager.avatarUrl!)
                    : null,
                onBackgroundImageError: manager.avatarUrl != null && manager.avatarUrl!.isNotEmpty ? (_, __) {} : null,
                child: manager.avatarUrl == null || manager.avatarUrl!.isEmpty
                    ? Text(
                        tr(manager.fullName.isNotEmpty ? manager.fullName[0].toUpperCase() : '?'),
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 28),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(tr(manager.fullName), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_positionIcon(manager.position), size: 14, color: color),
                  const SizedBox(width: 6),
                  Text(tr(manager.position ?? ''), style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ),
          ],
        );

        final detailsContent = Column(
          children: [
            _buildDetailRow(Icons.badge_outlined, 'Mã nhân viên', manager.employeeCode),
            if (manager.department != null) _buildDetailRow(Icons.business, 'Phòng ban', manager.department!),
            if (manager.email != null) _buildDetailRow(Icons.email_outlined, 'Email', manager.email!),
            if (manager.companyEmail != null) _buildDetailRow(Icons.alternate_email, 'Email công ty', manager.companyEmail!),
            if (manager.phone != null) _buildDetailRow(Icons.phone, 'Số điện thoại', manager.phone!),
            if (manager.branchName != null) _buildDetailRow(Icons.location_on_outlined, 'Chi nhánh', manager.branchName!),
            if (manager.joinDate != null)
              _buildDetailRow(Icons.calendar_today, 'Ngày vào', '${manager.joinDate!.day}/${manager.joinDate!.month}/${manager.joinDate!.year}'),
          ],
        );

        final actionButtons = Row(
          children: [
            if (manager.phone != null && manager.phone!.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _makePhoneCall(manager.phone!),
                  icon: const Icon(Icons.phone, size: 18),
                  label: Text(tr('Gọi điện'), style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green[700],
                    side: BorderSide(color: Colors.green[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            if (manager.phone != null && manager.phone!.isNotEmpty && manager.email != null && manager.email!.isNotEmpty)
              const SizedBox(width: 10),
            if (manager.email != null && manager.email!.isNotEmpty)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sendEmail(manager.email!),
                  icon: const Icon(Icons.email, size: 18),
                  label: Text(tr('Gửi email'), style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue[700],
                    side: BorderSide(color: Colors.blue[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
          ],
        );

        if (isMobile) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            shape: const RoundedRectangleBorder(),
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Scaffold(
                appBar: AppBar(
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  title: Text(tr(manager.fullName), overflow: TextOverflow.ellipsis),
                  elevation: 0.5,
                ),
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: headerContent,
                      ),
                      Padding(padding: const EdgeInsets.all(20), child: detailsContent),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        child: actionButtons,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                bottomNavigationBar: Container(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(ctx).padding.bottom),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surface,
                    border: Border(top: BorderSide(color: Theme.of(ctx).dividerColor, width: 0.5)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      child: AppButton.cancel(
                        onPressed: () => Navigator.pop(ctx),
                        label: 'Đóng',
                        expand: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: headerContent,
                ),
                Padding(padding: const EdgeInsets.all(20), child: detailsContent),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: actionButtons,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, right: 16, top: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              tr(label),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              tr(value),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
