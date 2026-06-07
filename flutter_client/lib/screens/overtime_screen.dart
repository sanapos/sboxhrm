import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/paged_load_utils.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/app_responsive_dialog.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import '../widgets/hrm_mini_stat_chip.dart';

class OvertimeScreen extends StatefulWidget {
  const OvertimeScreen({super.key});

  @override
  State<OvertimeScreen> createState() => _OvertimeScreenState();
}

class _OvertimeScreenState extends State<OvertimeScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = false;
  bool _showMobileSummary = false;
  int _currentPage = 1;
  final int _pageSize = 20;

  List<Map<String, dynamic>> _allOvertimes = [];
  List<Map<String, dynamic>> _myOvertimes = [];
  List<Map<String, dynamic>> _pendingOvertimes = [];
  Map<String, dynamic>? _statistics;
  List<Map<String, dynamic>> _employees = [];
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() => _currentPage = 1);
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final allFuture = fetchAllPagedMaps(
        (p, s) => _apiService.getOvertimes(page: p, pageSize: s),
        pageSize: 500,
      );
      final myRes = await _apiService.getMyOvertimes();
      final pendingRes = await _apiService.getPendingOvertimes();
      final statsRes = await _apiService.getOvertimeStatistics();
      final allList = await allFuture;
      setState(() {
        _allOvertimes = allList;
        if (myRes['isSuccess'] == true) {
          _myOvertimes = mapsFromPagedApiData(myRes['data']);
          if (_myOvertimes.isEmpty && myRes['data'] is List) {
            _myOvertimes = List<Map<String, dynamic>>.from(myRes['data']);
          }
        }
        if (pendingRes['isSuccess'] == true) {
          _pendingOvertimes = mapsFromPagedApiData(pendingRes['data']);
          if (_pendingOvertimes.isEmpty && pendingRes['data'] is List) {
            _pendingOvertimes =
                List<Map<String, dynamic>>.from(pendingRes['data']);
          }
        }
        if (statsRes['isSuccess'] == true) _statistics = statsRes['data'];
      });
      if (_branches.isEmpty) {
        try {
          final emps = await _apiService.getEmployees(pageSize: 500);
          if (mounted) {
            setState(() => _employees =
                emps.map((e) => Map<String, dynamic>.from(e as Map)).toList());
          }
        } catch (_) {}
        try {
          final br = await _apiService.getBranchesForSelect();
          final bd = br['data'];
          if (bd is List && mounted) {
            setState(() => _branches =
                bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error loading overtime data: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: isMobile
                ? HrmMobileNestedTabLayout(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    headerSections: _overtimeHeaderSections(),
                    tabBar: TabBar(
                      controller: _tabController,
                      labelColor: const Color(0xFFEA580C),
                      unselectedLabelColor: Colors.grey[600],
                      indicatorColor: const Color(0xFFEA580C),
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: 'Tất cả'),
                        Tab(text: 'Của tôi'),
                        Tab(text: 'Chờ duyệt'),
                        Tab(text: 'Thống kê'),
                      ],
                    ),
                    tabBarView: TabBarView(
                      controller: _tabController,
                      children: [
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _buildOvertimeList(
                                _filteredOvertimes(_allOvertimes),
                                showActions: false,
                                nestedTab: true),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _buildOvertimeList(_myOvertimes,
                                showActions: false, nestedTab: true),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _buildOvertimeList(
                                _filteredOvertimes(_pendingOvertimes),
                                showActions: true,
                                nestedTab: true),
                        _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : HrmScrollSlivers.nestedTabList(
                                child: _buildStatisticsTab()),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      _buildStatsRow(),
                      TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFFEA580C),
                        unselectedLabelColor: Colors.grey[600],
                        indicatorColor: const Color(0xFFEA580C),
                        indicatorWeight: 3,
                        tabs: const [
                          Tab(text: 'Tất cả'),
                          Tab(text: 'Của tôi'),
                          Tab(text: 'Chờ duyệt'),
                          Tab(text: 'Thống kê'),
                        ],
                      ),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildOvertimeList(
                                      _filteredOvertimes(_allOvertimes),
                                      showActions: false),
                                  _buildOvertimeList(_myOvertimes,
                                      showActions: false),
                                  _buildOvertimeList(
                                      _filteredOvertimes(_pendingOvertimes),
                                      showActions: true),
                                  _buildStatisticsTab(),
                                ],
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton:
          Provider.of<PermissionProvider>(context, listen: false)
                  .canCreate('Overtime')
              ? FloatingActionButton.extended(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Đăng ký tăng ca'),
                  backgroundColor: const Color(0xFFEA580C),
                )
              : null,
    );
  }

  List<Map<String, dynamic>> _filteredOvertimes(
      List<Map<String, dynamic>> list) {
    if (_selectedBranchId == null) return list;
    final branchEmpIds = _employees
        .where((e) => e['branchId']?.toString() == _selectedBranchId)
        .map((e) => e['id']?.toString() ?? '')
        .toSet();
    return list
        .where((ot) => branchEmpIds.contains(ot['employeeUserId']?.toString()))
        .toList();
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: const BoxDecoration(
        gradient:
            LinearGradient(colors: [Color(0xFFEA580C), Color(0xFFF97316)]),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12)),
                child:
                    const Icon(Icons.more_time, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Qu\u1ea3n l\u00fd t\u0103ng ca',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    Text(
                        '\u0110\u0103ng k\u00fd v\u00e0 ph\u00ea duy\u1ec7t t\u0103ng ca',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
          if (_branches.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: ValueKey('branch_$_selectedBranchId'),
              initialValue: _selectedBranchId,
              isExpanded: true,
              dropdownColor: Colors.white,
              decoration: InputDecoration(
                labelText: 'Chi nh\u00e1nh',
                labelStyle:
                    const TextStyle(color: Colors.white70, fontSize: 13),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white30)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white30)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.15),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              iconEnabledColor: Colors.white,
              items: [
                const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('T\u1ea5t c\u1ea3 chi nh\u00e1nh',
                        style: TextStyle(color: Colors.black87))),
                ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b['id']?.toString(),
                    child: Text(b['name']?.toString() ?? '',
                        style: const TextStyle(color: Colors.black87),
                        overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => _selectedBranchId = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          _buildMiniStat(
              'Tổng', '${_allOvertimes.length}', HrmPageChrome.primaryNavy),
          const SizedBox(width: 12),
          _buildMiniStat('Chờ duyệt', '${_pendingOvertimes.length}',
              const Color(0xFFF59E0B)),
          const SizedBox(width: 12),
          _buildMiniStat('Tổng giờ TC', '${_statistics?['totalHours'] ?? 0}h',
              HrmPageChrome.primaryNavy),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(
          children: [
            Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color)),
                  Text(label,
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _overtimeHeaderSections() => [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: InkWell(
            onTap: () =>
                setState(() => _showMobileSummary = !_showMobileSummary),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined,
                      size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text('Tổng quan',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Colors.blue.shade700)),
                  const Spacer(),
                  Icon(
                      _showMobileSummary
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: Colors.blue.shade700),
                ],
              ),
            ),
          ),
        ),
        if (_showMobileSummary) _buildStatsRow(),
      ];

  Widget _buildOvertimeList(List<Map<String, dynamic>> items,
      {required bool showActions, bool nestedTab = false}) {
    if (items.isEmpty) {
      final empty = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_time, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Không có yêu cầu tăng ca',
                style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
      if (nestedTab) {
        return CustomScrollView(
          slivers: [
            SliverOverlapInjector(
              handle:
                  NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverFillRemaining(child: empty),
          ],
        );
      }
      return empty;
    }
    final totalCount = items.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = (page - 1) * _pageSize;
    final endIndex = (page * _pageSize).clamp(0, totalCount);
    final paginatedItems =
        items.sublist(startIndex.clamp(0, totalCount), endIndex);

    if (nestedTab) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            SliverOverlapInjector(
              handle:
                  NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => Padding(
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
                      child: _buildOvertimeDeckItem(paginatedItems[i],
                          showActions: showActions),
                    ),
                  ),
                  childCount: paginatedItems.length,
                ),
              ),
            ),
            if (totalPages > 1)
              SliverToBoxAdapter(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Hiển thị ${startIndex + 1}-$endIndex / $totalCount',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left, size: 20),
                            onPressed: page > 1
                                ? () => setState(() => _currentPage--)
                                : null,
                            visualDensity: VisualDensity.compact,
                          ),
                          Text('$page / $totalPages',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w500)),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, size: 20),
                            onPressed: page < totalPages
                                ? () => setState(() => _currentPage++)
                                : null,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: paginatedItems.length,
              itemBuilder: (ctx, i) => Padding(
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
                  child: _buildOvertimeDeckItem(paginatedItems[i],
                      showActions: showActions),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Hiển thị ${startIndex + 1}-$endIndex / $totalCount',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      onPressed: page > 1
                          ? () => setState(() => _currentPage--)
                          : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$page / $totalPages',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      onPressed: page < totalPages
                          ? () => setState(() => _currentPage++)
                          : null,
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

  Widget _buildOvertimeDeckItem(Map<String, dynamic> ot,
      {required bool showActions}) {
    final status = ot['status']?.toString() ?? 'Pending';
    final statusColor = _getStatusColor(status);
    final statusText = _getStatusText(status);
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: statusColor.withValues(alpha: 0.1),
              child: Icon(Icons.person, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ot['employeeName'] ?? 'Nhân viên',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDate(ot['date'] ?? ot['overtimeDate'])} · ${ot['startTime']?.toString().substring(0, 5) ?? '--:--'}-${ot['endTime']?.toString().substring(0, 5) ?? '--:--'} · ${ot['totalHours'] ?? ot['hours'] ?? 0}h',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(statusText,
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 11)),
            ),
            if (showActions &&
                status == 'Pending' &&
                Provider.of<PermissionProvider>(context, listen: false)
                    .canApprove('Overtime')) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _approveOvertime(ot['id']),
                child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.check_circle,
                        size: 20, color: HrmPageChrome.primaryNavy)),
              ),
              InkWell(
                onTap: () => _rejectOvertime(ot['id']),
                child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.cancel, size: 20, color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsTab() {
    if (_statistics == null) {
      return const Center(child: Text('Chưa có dữ liệu thống kê'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatCard(
                  'Tổng yêu cầu',
                  '${_statistics?['totalRequests'] ?? 0}',
                  Icons.list_alt,
                  HrmPageChrome.primaryNavy),
              const SizedBox(width: 16),
              _buildStatCard('Đã duyệt', '${_statistics?['approved'] ?? 0}',
                  Icons.check_circle, HrmPageChrome.primaryNavy),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatCard('Từ chối', '${_statistics?['rejected'] ?? 0}',
                  Icons.cancel, const Color(0xFFEF4444)),
              const SizedBox(width: 16),
              _buildStatCard('Tổng giờ', '${_statistics?['totalHours'] ?? 0}h',
                  Icons.schedule, const Color(0xFFEA580C)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: HrmStatSummaryCard(
        icon: icon,
        value: value,
        label: label,
        color: color,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return HrmPageChrome.primaryNavy;
      case 'rejected':
        return const Color(0xFFEF4444);
      case 'completed':
        return HrmPageChrome.primaryNavy;
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return 'Đã duyệt';
      case 'rejected':
        return 'Từ chối';
      case 'completed':
        return 'Hoàn thành';
      case 'pending':
        return 'Chờ duyệt';
      default:
        return status;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      return DateFormat('dd/MM/yyyy').format(DateTime.parse(date.toString()));
    } catch (_) {
      return date.toString();
    }
  }

  void _showCreateDialog() {
    DateTime? selectedDate;
    final startCtrl = TextEditingController();
    final endCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final isMobile = MediaQuery.of(ctx).size.width < 768;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final content = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(selectedDate != null
                      ? DateFormat('dd/MM/yyyy').format(selectedDate!)
                      : 'Chọn ngày'),
                  leading: const Icon(Icons.calendar_today),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade300)),
                  onTap: () async {
                    final d = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 90)));
                    if (d != null) setDialogState(() => selectedDate = d);
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                            controller: startCtrl,
                            decoration: InputDecoration(
                                labelText: 'Giờ bắt đầu (HH:mm) *',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10))))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: endCtrl,
                            decoration: InputDecoration(
                                labelText: 'Giờ kết thúc (HH:mm) *',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10))))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                        labelText: 'Lý do *',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10))),
                    maxLines: 2),
              ],
            );
            final actions = AppDialogActions(
              onCancel: () => Navigator.pop(ctx),
              onConfirm: () async {
                if (selectedDate == null) {
                  appNotification.showWarning(
                      title: 'Thiếu thông tin',
                      message: 'Vui lòng chọn ngày tăng ca');
                  return;
                }
                if (startCtrl.text.trim().isEmpty ||
                    endCtrl.text.trim().isEmpty) {
                  appNotification.showWarning(
                      title: 'Thiếu thông tin',
                      message: 'Vui lòng nhập giờ bắt đầu và kết thúc');
                  return;
                }
                if (reasonCtrl.text.trim().isEmpty) {
                  appNotification.showWarning(
                      title: 'Thiếu thông tin',
                      message: 'Vui lòng nhập lý do tăng ca');
                  return;
                }
                final data = {
                  'overtimeDate': selectedDate!.toIso8601String(),
                  'startTime': startCtrl.text,
                  'endTime': endCtrl.text,
                  'reason': reasonCtrl.text
                };
                final res = await _apiService.createOvertime(data);
                if (res['isSuccess'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _loadData(showLoading: false);
                } else {
                  if (ctx.mounted) {
                    appNotification.showError(
                        title: 'Lỗi',
                        message: res['message']?.toString() ??
                            'Không thể đăng ký tăng ca');
                  }
                }
              },
              confirmLabel: 'Gửi yêu cầu',
              confirmIcon: Icons.send,
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
                      leading: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx)),
                      title: const Row(children: [
                        Icon(Icons.more_time,
                            color: Color(0xFFEA580C), size: 20),
                        SizedBox(width: 10),
                        Expanded(child: Text('Đăng ký tăng ca'))
                      ]),
                      elevation: 0.5,
                    ),
                    body: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: content,
                    ),
                    bottomNavigationBar: Container(
                      padding: EdgeInsets.fromLTRB(
                          16, 12, 16, 12 + MediaQuery.of(ctx).padding.bottom),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surface,
                        border: Border(
                            top: BorderSide(
                                color: Theme.of(ctx).dividerColor, width: 0.5)),
                      ),
                      child: SafeArea(top: false, child: actions),
                    ),
                  ),
                ),
              );
            }

            return ScrollableAlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.more_time, color: Color(0xFFEA580C)),
                SizedBox(width: 8),
                Text('Đăng ký tăng ca')
              ]),
              content: SizedBox(width: 420, child: content),
              actions: [actions],
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            );
          },
        );
      },
    );
  }

  Future<void> _approveOvertime(dynamic id) async {
    await _apiService.approveOvertime(id.toString());
    await _loadData(showLoading: false);
  }

  Future<void> _rejectOvertime(dynamic id) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await AppResponsiveDialog.show<bool>(
      context: context,
      title: 'Từ chối tăng ca',
      icon: Icons.cancel_outlined,
      iconColor: Colors.red,
      maxWidth: 420,
      child: TextField(
          controller: reasonCtrl,
          decoration: InputDecoration(
              labelText: 'Lý do từ chối',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
          maxLines: 2),
      actions: AppDialogActions(
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () => Navigator.pop(context, true),
        confirmLabel: 'Từ chối',
        confirmVariant: AppButtonVariant.danger,
      ),
    );
    if (confirmed == true) {
      await _apiService.rejectOvertime(id.toString(), reason: reasonCtrl.text);
      await _loadData(showLoading: false);
    }
  }
}
