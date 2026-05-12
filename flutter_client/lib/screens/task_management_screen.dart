import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/task.dart';
import '../models/employee.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';

// ==========================================================================
// QUẢN LÝ CÔNG VIỆC - Task Management
// Chức năng:
//   1. Phân công công việc (giao việc cho nhân viên, batch assign)
//   2. Kiểm soát tiến độ (thanh tiến độ, trạng thái, Kanban board)
//   3. Cập nhật tiến độ (slider, quick status chips)
//   4. Đốc thúc công việc (gửi nhắc nhở, mức độ khẩn cấp)
//   5. Đánh giá công việc (chấm điểm chất lượng, tiến độ, tổng thể)
//   6. Tổng kết hoạt động (thống kê theo trạng thái, nhân viên, thời gian)
//   7. Bộ lọc công việc (trạng thái, ưu tiên, người thực hiện, ngày)
//   8. Thời gian nhân viên (giờ ước tính vs thực tế)
// ==========================================================================

class TaskManagementScreen extends StatefulWidget {
  const TaskManagementScreen({super.key});
  @override
  State<TaskManagementScreen> createState() => _TaskManagementScreenState();
}

class _TaskManagementScreenState extends State<TaskManagementScreen>
    with TickerProviderStateMixin {
  final _api = ApiService();
  late TabController _tabCtrl;

  // ---------- data ----------
  List<WorkTask> _tasks = [];
  List<Employee> _employees = [];
  TaskStatistics? _stats;
  KanbanBoard? _kanban;
  bool _loading = true;
  int _total = 0;
  int _page = 1;
  final int _pageSize = 20;

  // ---------- filters ----------
  String? _search;
  WorkTaskStatus? _statusFilter;
  TaskPriority? _priorityFilter;
  TaskType? _typeFilter;
  String? _assigneeFilter;
  DateTime? _fromDate, _toDate;
  bool _isMyTasks = false;
  String? _filterBranchId;
  List<Map<String, dynamic>> _branches = [];

  // ---------- selection ----------
  final Set<String> _sel = {};
  bool _selectMode = false;

  // ---------- mobile UI ----------
  bool _showMobileFilters = false;

  // ---------- side detail ----------
  WorkTask? _detailTask;
  List<TaskComment> _comments = [];
  List<TaskHistory> _history = [];
  bool _detailLoading = false;
  final _commentCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) _loadTab(_tabCtrl.index);
    });
    _init();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  // ======================== DATA LOADING ========================
  Future<void> _init() async {
    setState(() => _loading = true);
    await Future.wait([_loadEmployees(), _loadTasks(), _loadStats()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadTab(int i) async {
    if (i == 0) {
      await _loadTasks();
    } else if (i == 1) {
      await _loadKanban();
    } else {
      await _loadStats();
    }
  }

  Future<void> _loadEmployees() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.userRole == 'Employee') {
      // Employee: load only own profile
      final resp = await _api.getMyEmployee();
      if (mounted && resp['isSuccess'] == true && resp['data'] != null) {
        setState(() => _employees = [Employee.fromJson(resp['data'])]);
      }
    } else {
      final r = await _api.getEmployees(pageSize: 500);
      if (mounted) {
        setState(
            () => _employees = r.map((e) => Employee.fromJson(e)).toList());
      }
    }
    try {
      final br = await _api.getBranchesForSelect();
      final bd = br['data'];
      if (bd is List && mounted) {
        setState(() => _branches =
            bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _loadTasks() async {
    final Map<String, dynamic> r;
    if (_isMyTasks) {
      r = await _api.getMyTasks(
        page: _page,
        pageSize: _pageSize,
        status: _statusFilter?.index,
        priority: _priorityFilter?.index,
      );
    } else {
      r = await _api.getTasks(
        page: _page,
        pageSize: _pageSize,
        search: _search,
        status: _statusFilter?.index,
        priority: _priorityFilter?.index,
        taskType: _typeFilter?.index,
        assigneeId: _assigneeFilter,
        fromDate: _fromDate,
        toDate: _toDate,
      );
    }
    if (r['isSuccess'] == true && r['data'] != null) {
      final d = r['data'];
      if (mounted) {
        setState(() {
          _tasks = (d['items'] as List?)
                  ?.map((e) => WorkTask.fromJson(e))
                  .toList() ??
              [];
          _total = d['totalCount'] ?? 0;
        });
      }
    }
  }

  Future<void> _loadKanban() async {
    final r = await _api.getTaskKanbanBoard(
      assigneeId: _assigneeFilter,
      priority: _priorityFilter?.index,
    );
    if (r['isSuccess'] == true && r['data'] != null && mounted) {
      setState(() => _kanban = KanbanBoard.fromJson(r['data']));
    }
  }

  Future<void> _loadStats() async {
    final r =
        await _api.getTaskStatistics(fromDate: _fromDate, toDate: _toDate);
    if (r['isSuccess'] == true && r['data'] != null && mounted) {
      setState(() => _stats = TaskStatistics.fromJson(r['data']));
    }
  }

  Future<void> _loadDetail(String taskId) async {
    setState(() => _detailLoading = true);
    final r = await _api.getTaskById(taskId);
    if (r['isSuccess'] == true && r['data'] != null) {
      final t = WorkTask.fromJson(r['data']);
      final hr = await _api.getTaskHistory(taskId);
      if (mounted) {
        setState(() {
          _detailTask = t;
          _comments = t.comments ?? [];
          final hList = hr['data'] as List? ?? [];
          _history = hList.map((e) => TaskHistory.fromJson(e)).toList();
          _detailLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _detailLoading = false);
    }
  }

  // ======================== BUILD ========================
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final isMobile = w <= 900;
    final showDesktopDetail = !isMobile && _detailTask != null;
    final showMobileDetail = isMobile && _detailTask != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          if (!showMobileDetail) _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : showMobileDetail
                    ? _buildDetailPanel()
                    : Row(
                        children: [
                          // ========== MAIN CONTENT ==========
                          Expanded(
                            flex: showDesktopDetail ? 6 : 10,
                            child: TabBarView(
                              controller: _tabCtrl,
                              children: [
                                _buildListView(),
                                _buildKanbanView(),
                                _buildStatsView(),
                              ],
                            ),
                          ),
                          // ========== SIDE DETAIL PANEL ==========
                          if (showDesktopDetail) ...[
                            const VerticalDivider(width: 1),
                            Expanded(flex: 4, child: _buildDetailPanel()),
                          ],
                        ],
                      ),
          ),
        ],
      ),
      floatingActionButton: showMobileDetail
          ? null
          : Provider.of<PermissionProvider>(context, listen: false)
                  .canCreate('Task')
              ? FloatingActionButton.extended(
                  onPressed: _showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo công việc'),
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                )
              : null,
    );
  }

  // ======================== HEADER ========================
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          LayoutBuilder(builder: (context, headerConstraints) {
            final isNarrow = headerConstraints.maxWidth < 600;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  isNarrow ? 12 : 20, isNarrow ? 8 : 16, isNarrow ? 8 : 20, 4),
              child: Row(
                children: [
                  if (!isNarrow) ...[
                    const Icon(Icons.task_alt,
                        color: Color(0xFF1E3A5F), size: 28),
                    const SizedBox(width: 10),
                    const Text('Quản lý Công việc',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF18181B))),
                  ],
                  if (isNarrow)
                    const Text('Công việc',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF18181B))),
                  const Spacer(),
                  if (_selectMode && _sel.isNotEmpty) ...[
                    Text('${_sel.length} đã chọn',
                        style: const TextStyle(
                            color: Color(0xFF1E3A5F),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    if (isNarrow) ...[
                      IconButton(
                        icon: const Icon(Icons.check_circle, size: 20),
                        color: Colors.green,
                        tooltip: 'Hoàn thành',
                        onPressed: () => _batchStatus(WorkTaskStatus.completed),
                      ),
                      IconButton(
                        icon: const Icon(Icons.person_add, size: 20),
                        color: Colors.blue,
                        tooltip: 'Giao việc',
                        onPressed: _showBatchAssign,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        color: Colors.red,
                        tooltip: 'Xóa',
                        onPressed: _confirmBatchDelete,
                      ),
                    ] else ...[
                      _buildBatchBtn(
                          'Hoàn thành',
                          Icons.check_circle,
                          Colors.green,
                          () => _batchStatus(WorkTaskStatus.completed)),
                      const SizedBox(width: 4),
                      _buildBatchBtn('Giao việc', Icons.person_add, Colors.blue,
                          _showBatchAssign),
                      const SizedBox(width: 4),
                      _buildBatchBtn(
                          'Xóa', Icons.delete, Colors.red, _confirmBatchDelete),
                    ],
                    const SizedBox(width: 8),
                  ],
                  if (isNarrow)
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isMyTasks = !_isMyTasks;
                          _page = 1;
                        });
                        _loadTasks();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _isMyTasks
                              ? const Color(0xFF1E3A5F)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.person,
                              size: 14,
                              color: _isMyTasks
                                  ? Colors.white
                                  : const Color(0xFF1E3A5F)),
                          const SizedBox(width: 4),
                          Text('Của tôi',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _isMyTasks
                                      ? Colors.white
                                      : const Color(0xFF1E3A5F))),
                        ]),
                      ),
                    ),
                  if (isNarrow) const SizedBox(width: 4),
                  if (isNarrow)
                    IconButton(
                      icon: Stack(
                        children: [
                          Icon(
                              _showMobileFilters
                                  ? Icons.filter_alt
                                  : Icons.filter_alt_outlined,
                              color: const Color(0xFF1E3A5F)),
                          if (_search?.isNotEmpty == true ||
                              _statusFilter != null ||
                              _priorityFilter != null ||
                              _typeFilter != null ||
                              _assigneeFilter != null)
                            Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                        color: Colors.orangeAccent,
                                        shape: BoxShape.circle))),
                        ],
                      ),
                      tooltip: 'Bộ lọc',
                      onPressed: () => setState(
                          () => _showMobileFilters = !_showMobileFilters),
                    ),
                  IconButton(
                    icon: Icon(_selectMode ? Icons.close : Icons.checklist,
                        color:
                            _selectMode ? Colors.red : const Color(0xFF71717A)),
                    tooltip: _selectMode ? 'Thoát chọn' : 'Chọn nhiều',
                    onPressed: () => setState(() {
                      _selectMode = !_selectMode;
                      if (!_selectMode) _sel.clear();
                    }),
                  ),
                ],
              ),
            );
          }),
          LayoutBuilder(builder: (context, tabConstraints) {
            final tabNarrow = tabConstraints.maxWidth < 600;
            return TabBar(
              controller: _tabCtrl,
              indicatorColor: const Color(0xFF1E3A5F),
              labelColor: const Color(0xFF1E3A5F),
              unselectedLabelColor: const Color(0xFFA1A1AA),
              labelPadding:
                  tabNarrow ? const EdgeInsets.symmetric(horizontal: 4) : null,
              labelStyle: TextStyle(
                  fontSize: tabNarrow ? 12 : 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: TextStyle(fontSize: tabNarrow ? 12 : 14),
              tabs: [
                Tab(
                  height: tabNarrow ? 36 : null,
                  icon: tabNarrow ? null : const Icon(Icons.view_list_rounded),
                  text: 'Danh sách',
                ),
                Tab(
                  height: tabNarrow ? 36 : null,
                  icon:
                      tabNarrow ? null : const Icon(Icons.view_kanban_rounded),
                  text: 'Kanban',
                ),
                Tab(
                  height: tabNarrow ? 36 : null,
                  icon: tabNarrow ? null : const Icon(Icons.analytics_rounded),
                  text: 'Tổng kết',
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBatchBtn(
      String label, IconData icon, Color c, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: c),
      label: Text(label, style: TextStyle(color: c, fontSize: 12)),
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32)),
    );
  }

  // ======================== LIST VIEW ========================
  Widget _buildListView() {
    final isMobile = Responsive.isMobile(context);
    // Calculate summary counts for mobile quick stats
    final myTasks = _tasks;
    final overdueCount = myTasks.where((t) => t.isOverdue).length;
    final inProgressCount =
        myTasks.where((t) => t.status == WorkTaskStatus.inProgress).length;
    final todoCount =
        myTasks.where((t) => t.status == WorkTaskStatus.todo).length;
    final completedCount =
        myTasks.where((t) => t.status == WorkTaskStatus.completed).length;

    return Column(
      children: [
        if (!isMobile || _showMobileFilters) _buildFilters(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadTasks();
              await _loadStats();
            },
            child: _tasks.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 80),
                    Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                            color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                        child: Icon(Icons.task_alt,
                            size: 48, color: Colors.grey[400]),
                      ),
                      const SizedBox(height: 16),
                      Text('Chưa có công việc nào',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Nhấn nút + để tạo công việc mới',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 13)),
                    ])),
                  ])
                : isMobile
                    ? ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                        itemCount: _tasks.length + 1, // +1 for summary header
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            // ── Quick stats summary ──
                            return Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(children: [
                                      _taskStatChip(
                                          Icons.pending_actions,
                                          '$todoCount',
                                          'Chờ làm',
                                          const Color(0xFFA1A1AA), () {
                                        setState(() {
                                          _statusFilter = WorkTaskStatus.todo;
                                          _page = 1;
                                        });
                                        _loadTasks();
                                      }),
                                      const SizedBox(width: 6),
                                      _taskStatChip(
                                          Icons.play_circle_filled,
                                          '$inProgressCount',
                                          'Đang làm',
                                          const Color(0xFF1E3A5F), () {
                                        setState(() {
                                          _statusFilter =
                                              WorkTaskStatus.inProgress;
                                          _page = 1;
                                        });
                                        _loadTasks();
                                      }),
                                      const SizedBox(width: 6),
                                      _taskStatChip(
                                          Icons.check_circle,
                                          '$completedCount',
                                          'Xong',
                                          const Color(0xFF22C55E), () {
                                        setState(() {
                                          _statusFilter =
                                              WorkTaskStatus.completed;
                                          _page = 1;
                                        });
                                        _loadTasks();
                                      }),
                                      if (overdueCount > 0) ...[
                                        const SizedBox(width: 6),
                                        _taskStatChip(
                                            Icons.warning_amber,
                                            '$overdueCount',
                                            'Trễ hạn',
                                            const Color(0xFFEF4444),
                                            () {}),
                                      ],
                                    ]),
                                  ),
                                  if (_total > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                          '$_total công việc${_isMyTasks ? ' của tôi' : ''}',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFA1A1AA))),
                                    ),
                                ],
                              ),
                            );
                          }
                          final task = _tasks[i - 1];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: task.isOverdue
                                        ? const Color(0xFFEF4444)
                                            .withValues(alpha: 0.3)
                                        : const Color(0xFFE4E4E7)),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2)),
                                ],
                              ),
                              child: _buildTaskDeckItem(task),
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _tasks.length + 1,
                        itemBuilder: (_, i) => i == _tasks.length
                            ? _buildPagination()
                            : _buildTaskCard(_tasks[i]),
                      ),
          ),
        ),
      ],
    );
  }

  Widget _taskStatChip(IconData icon, String value, String label, Color color,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(value,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 4),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }

  // ---------- Filters ----------
  // Bộ lọc: Trạng thái, Ưu tiên, Người thực hiện, Khoảng thời gian, Tìm kiếm
  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm công việc...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    suffixIcon: _search != null
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setState(() => _search = null);
                              _loadTasks();
                            })
                        : null,
                  ),
                  onSubmitted: (v) {
                    setState(() => _search = v.isEmpty ? null : v);
                    _loadTasks();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Bộ lọc ngày - Khoảng thời gian
              _buildDateRangeFilter(),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: Text('Của tôi',
                      style: TextStyle(
                          fontSize: 12,
                          color: _isMyTasks
                              ? Colors.white
                              : const Color(0xFF1E3A5F))),
                  selected: _isMyTasks,
                  onSelected: (_) {
                    setState(() {
                      _isMyTasks = !_isMyTasks;
                      _page = 1;
                    });
                    _loadTasks();
                  },
                  avatar: Icon(Icons.person,
                      size: 16,
                      color:
                          _isMyTasks ? Colors.white : const Color(0xFF1E3A5F)),
                  backgroundColor: const Color(0xFFE0F2FE),
                  selectedColor: const Color(0xFF1E3A5F),
                  checkmarkColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                _chip(
                    _statusFilter != null
                        ? getTaskStatusLabel(_statusFilter!)
                        : 'Trạng thái',
                    _statusFilter != null,
                    _showStatusFilter),
                const SizedBox(width: 6),
                _chip(
                    _priorityFilter != null
                        ? getPriorityLabel(_priorityFilter!)
                        : 'Ưu tiên',
                    _priorityFilter != null,
                    _showPriorityFilter),
                const SizedBox(width: 6),
                _chip(
                    _typeFilter != null
                        ? getTaskTypeLabel(_typeFilter!)
                        : 'Loại',
                    _typeFilter != null,
                    _showTypeFilter),
                const SizedBox(width: 6),
                _chip(
                    _assigneeFilter != null
                        ? (_employees
                                .where((e) => e.id == _assigneeFilter)
                                .firstOrNull
                                ?.fullName ??
                            'Đã chọn')
                        : 'Người thực hiện',
                    _assigneeFilter != null,
                    _showAssigneeFilter),
                const SizedBox(width: 6),
                if (_branches.isNotEmpty) _branchChipFilter(),
                if (_priorityFilter != null ||
                    _typeFilter != null ||
                    _assigneeFilter != null ||
                    _filterBranchId != null ||
                    _fromDate != null ||
                    _isMyTasks)
                  TextButton.icon(
                    onPressed: _clearFilters,
                    icon: const Icon(Icons.clear_all,
                        size: 16, color: Color(0xFFEF4444)),
                    label: const Text('Xóa bộ lọc',
                        style:
                            TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    final fmt = DateFormat('dd/MM');
    final label = _fromDate != null && _toDate != null
        ? '${fmt.format(_fromDate!)} - ${fmt.format(_toDate!)}'
        : _fromDate != null
            ? 'Từ ${fmt.format(_fromDate!)}'
            : 'Khoảng thời gian';
    return OutlinedButton.icon(
      onPressed: () async {
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
          initialDateRange: _fromDate != null
              ? DateTimeRange(start: _fromDate!, end: _toDate ?? DateTime.now())
              : null,
        );
        if (range != null) {
          setState(() {
            _fromDate = range.start;
            _toDate = range.end;
          });
          _loadTasks();
          _loadStats();
        }
      },
      icon: Icon(Icons.date_range,
          size: 16,
          color: _fromDate != null
              ? const Color(0xFF1E3A5F)
              : const Color(0xFFA1A1AA)),
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: _fromDate != null
                  ? const Color(0xFF1E3A5F)
                  : const Color(0xFFA1A1AA))),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
            color: _fromDate != null
                ? const Color(0xFF1E3A5F)
                : const Color(0xFFE4E4E7)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label,
          style: TextStyle(
              fontSize: 12,
              color: selected ? Colors.white : const Color(0xFF71717A))),
      selected: selected,
      onSelected: (_) => onTap(),
      backgroundColor: const Color(0xFFF1F5F9),
      selectedColor: const Color(0xFF1E3A5F),
      checkmarkColor: Colors.white,
      visualDensity: VisualDensity.compact,
    );
  }

  void _showStatusFilter() => _showFilterSheet<WorkTaskStatus>(
        'Trạng thái',
        WorkTaskStatus.values,
        (s) => getTaskStatusLabel(s),
        (s) => _statusIcon(s),
        (s) => _statusColor(s),
        _statusFilter,
        (v) {
          setState(() => _statusFilter = v);
          _loadTasks();
        },
      );
  void _showPriorityFilter() => _showFilterSheet<TaskPriority>(
        'Ưu tiên',
        TaskPriority.values,
        (p) => getPriorityLabel(p),
        (_) => Icons.flag,
        (p) => _priorityColor(p),
        _priorityFilter,
        (v) {
          setState(() => _priorityFilter = v);
          _loadTasks();
        },
      );
  void _showTypeFilter() => _showFilterSheet<TaskType>(
        'Loại công việc',
        TaskType.values,
        (t) => getTaskTypeLabel(t),
        (_) => Icons.category,
        (_) => const Color(0xFF71717A),
        _typeFilter,
        (v) {
          setState(() => _typeFilter = v);
          _loadTasks();
        },
      );

  Widget _branchChipFilter() {
    final selected = _filterBranchId != null;
    final branchName = selected
        ? _branches
                .firstWhere((b) => b['id']?.toString() == _filterBranchId,
                    orElse: () => {})['name']
                ?.toString() ??
            'Chi nhánh'
        : 'Chi nhánh';
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (_) => ListView(shrinkWrap: true, children: [
          ListTile(
            title: const Text('Tất cả chi nhánh'),
            leading: const Icon(Icons.all_inclusive),
            onTap: () {
              setState(() => _filterBranchId = null);
              Navigator.pop(context);
            },
          ),
          ..._branches.map((b) => ListTile(
                title: Text(b['name']?.toString() ?? ''),
                leading: const Icon(Icons.account_tree_outlined),
                selected: _filterBranchId == b['id']?.toString(),
                onTap: () {
                  setState(() => _filterBranchId = b['id']?.toString());
                  Navigator.pop(context);
                },
              )),
        ]),
      ),
      child: Chip(
        avatar: Icon(Icons.account_tree_outlined,
            size: 16, color: selected ? Colors.white : const Color(0xFF71717A)),
        label: Text(branchName,
            style: TextStyle(
                fontSize: 12,
                color: selected ? Colors.white : const Color(0xFF71717A))),
        backgroundColor:
            selected ? const Color(0xFF1E3A5F) : const Color(0xFFF1F5F9),
        deleteIcon: selected
            ? const Icon(Icons.close, size: 14, color: Colors.white)
            : null,
        onDeleted:
            selected ? () => setState(() => _filterBranchId = null) : null,
      ),
    );
  }

  void _showAssigneeFilter() {
    showModalBottomSheet(
        context: context,
        builder: (_) => ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                    title: const Text('Tất cả'),
                    leading: const Icon(Icons.all_inclusive),
                    onTap: () {
                      setState(() => _assigneeFilter = null);
                      Navigator.pop(context);
                      _loadTasks();
                    }),
                ...(_filterBranchId != null
                        ? _employees.where((e) => e.branchId == _filterBranchId)
                        : _employees.cast<Employee>())
                    .map((e) => ListTile(
                          title: Text(e.fullName),
                          subtitle: Text(e.employeeCode),
                          leading: CircleAvatar(
                              backgroundColor: const Color(0xFF1E3A5F),
                              child: Text(
                                  e.firstName.isNotEmpty ? e.firstName[0] : '?',
                                  style: const TextStyle(color: Colors.white))),
                          selected: _assigneeFilter == e.id,
                          onTap: () {
                            setState(() => _assigneeFilter = e.id);
                            Navigator.pop(context);
                            _loadTasks();
                          },
                        )),
              ],
            ));
  }

  void _showFilterSheet<T>(
      String title,
      List<T> values,
      String Function(T) label,
      IconData Function(T) icon,
      Color Function(T) color,
      T? current,
      void Function(T?) onSelect) {
    showModalBottomSheet(
        context: context,
        builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16))),
              ListTile(
                  title: const Text('Tất cả'),
                  leading: const Icon(Icons.all_inclusive),
                  onTap: () {
                    onSelect(null);
                    Navigator.pop(context);
                  }),
              ...values.map((v) => ListTile(
                    title: Text(label(v)),
                    leading: Icon(icon(v), color: color(v)),
                    selected: current == v,
                    selectedTileColor: color(v).withValues(alpha: 0.08),
                    onTap: () {
                      onSelect(v);
                      Navigator.pop(context);
                    },
                  )),
            ]));
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _priorityFilter = null;
      _typeFilter = null;
      _assigneeFilter = null;
      _fromDate = null;
      _toDate = null;
      _isMyTasks = false;
      _filterBranchId = null;
    });
    _loadTasks();
  }

  // ---------- Task Deck Item (Mobile) - Professional Card ----------
  Widget _buildTaskDeckItem(WorkTask t) {
    final isSel = _sel.contains(t.id);
    final deadlineInfo = _getDeadlineInfo(t);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_selectMode) {
          setState(() {
            isSel ? _sel.remove(t.id) : _sel.add(t.id);
          });
        } else {
          _loadDetail(t.id);
        }
      },
      onLongPress: () {
        if (!_selectMode) {
          setState(() {
            _selectMode = true;
            _sel.add(t.id);
          });
        }
      },
      child: Column(
        children: [
          // ── Top accent bar with priority color ──
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: _priorityColor(t.priority),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Row 1: Type icon + Code + Status + Priority ──
                Row(children: [
                  if (_selectMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                            value: isSel,
                            onChanged: (v) => setState(() {
                                  v == true
                                      ? _sel.add(t.id)
                                      : _sel.remove(t.id);
                                }),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _taskTypeColor(t.taskType).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(_taskTypeIcon(t.taskType),
                        color: _taskTypeColor(t.taskType), size: 14),
                  ),
                  const SizedBox(width: 8),
                  Text(t.taskCode,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              const Color(0xFF1E3A5F).withValues(alpha: 0.7))),
                  const Spacer(),
                  _statusBadge(t.status),
                  const SizedBox(width: 6),
                  _priorityBadge(t.priority),
                ]),
                const SizedBox(height: 8),
                // ── Row 2: Title ──
                Text(t.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF18181B)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (t.description != null && t.description!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(t.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFA1A1AA), fontSize: 12)),
                ],
                // ── Row 3: Progress bar (if any) ──
                if (t.progress > 0 ||
                    t.status == WorkTaskStatus.inProgress) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: t.progress / 100,
                          minHeight: 5,
                          backgroundColor: const Color(0xFFE4E4E7),
                          valueColor: AlwaysStoppedAnimation(
                              _progressColor(t.progress)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${t.progress}%',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _progressColor(t.progress))),
                  ]),
                ],
                const SizedBox(height: 8),
                // ── Row 4: Assignee + Deadline + Counters ──
                Row(children: [
                  if (t.assigneeName != null) ...[
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: const Color(0xFF1E3A5F),
                      child: Text(t.assigneeName![0],
                          style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(t.assigneeName!,
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (deadlineInfo != null) ...[
                    Icon(deadlineInfo['icon'] as IconData,
                        size: 13, color: deadlineInfo['color'] as Color),
                    const SizedBox(width: 3),
                    Text(deadlineInfo['text'] as String,
                        style: TextStyle(
                            fontSize: 10,
                            color: deadlineInfo['color'] as Color,
                            fontWeight: FontWeight.w600)),
                  ],
                  const Spacer(),
                  // Quick action counters
                  if (t.hasSubTasks) ...[
                    const Icon(Icons.checklist,
                        size: 12, color: Color(0xFFA1A1AA)),
                    const SizedBox(width: 2),
                    Text('${t.completedSubTaskCount}/${t.subTaskCount}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFFA1A1AA))),
                    const SizedBox(width: 6),
                  ],
                  if (t.hasComments) ...[
                    const Icon(Icons.chat_bubble_outline,
                        size: 12, color: Color(0xFFA1A1AA)),
                    const SizedBox(width: 2),
                    Text('${t.commentCount}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFFA1A1AA))),
                    const SizedBox(width: 6),
                  ],
                  if (t.estimatedHours != null) ...[
                    const Icon(Icons.access_time,
                        size: 12, color: Color(0xFFA1A1AA)),
                    const SizedBox(width: 2),
                    Text('${t.actualHours ?? 0}/${t.estimatedHours}h',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFFA1A1AA))),
                  ],
                ]),
                // ── Row 5: Quick action buttons (for non-completed tasks) ──
                if (t.status != WorkTaskStatus.completed &&
                    t.status != WorkTaskStatus.cancelled) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (t.status == WorkTaskStatus.todo)
                      _quickActionBtn(
                          'Bắt đầu',
                          Icons.play_arrow_rounded,
                          const Color(0xFF1E3A5F),
                          () => _updateStatus(t.id, WorkTaskStatus.inProgress)),
                    if (t.status == WorkTaskStatus.inProgress) ...[
                      _quickActionBtn(
                          'Tiến độ',
                          Icons.trending_up,
                          const Color(0xFF1E3A5F),
                          () => _updateProgress(t.id, t.progress)),
                      const SizedBox(width: 6),
                      _quickActionBtn(
                          'Hoàn thành',
                          Icons.check_circle_outline,
                          const Color(0xFF22C55E),
                          () => _updateStatus(t.id, WorkTaskStatus.completed)),
                    ],
                    if (t.status == WorkTaskStatus.inReview)
                      _quickActionBtn(
                          'Duyệt xong',
                          Icons.verified,
                          const Color(0xFF22C55E),
                          () => _updateStatus(t.id, WorkTaskStatus.completed)),
                    if (t.status == WorkTaskStatus.onHold)
                      _quickActionBtn(
                          'Tiếp tục',
                          Icons.play_arrow_rounded,
                          const Color(0xFF1E3A5F),
                          () => _updateStatus(t.id, WorkTaskStatus.inProgress)),
                    const Spacer(),
                    InkWell(
                      onTap: () => _showTaskQuickMenu(t),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.more_horiz,
                            size: 18, color: Color(0xFFA1A1AA)),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickActionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }

  void _showTaskQuickMenu(WorkTask t) {
    final canEdit =
        Provider.of<PermissionProvider>(context, listen: false).canEdit('Task');
    final canDelete = Provider.of<PermissionProvider>(context, listen: false)
        .canDelete('Task');
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFE4E4E7),
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: _taskTypeColor(t.taskType).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(_taskTypeIcon(t.taskType),
                    color: _taskTypeColor(t.taskType), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(t.taskCode,
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1E3A5F),
                            fontWeight: FontWeight.w600)),
                    Text(t.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ])),
              _statusBadge(t.status),
            ]),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.visibility, color: Color(0xFF1E3A5F)),
            title: const Text('Xem chi tiết'),
            dense: true,
            onTap: () {
              Navigator.pop(ctx);
              _loadDetail(t.id);
            },
          ),
          if (canEdit)
            ListTile(
              leading: const Icon(Icons.edit, color: Color(0xFF1E3A5F)),
              title: const Text('Chỉnh sửa'),
              dense: true,
              onTap: () {
                Navigator.pop(ctx);
                _showEditDialog(t);
              },
            ),
          ListTile(
            leading: const Icon(Icons.trending_up, color: Color(0xFF1E3A5F)),
            title: const Text('Cập nhật tiến độ'),
            dense: true,
            onTap: () {
              Navigator.pop(ctx);
              _updateProgress(t.id, t.progress);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz, color: Color(0xFF1E3A5F)),
            title: const Text('Đổi trạng thái'),
            dense: true,
            onTap: () {
              Navigator.pop(ctx);
              _showStatusChangeSheet(t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_active,
                color: Color(0xFFF59E0B)),
            title: const Text('Đốc thúc'),
            dense: true,
            onTap: () {
              Navigator.pop(ctx);
              _showReminderDialog(t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.star_rate, color: Color(0xFFF59E0B)),
            title: const Text('Đánh giá'),
            dense: true,
            onTap: () {
              Navigator.pop(ctx);
              _showEvaluationDialog(t);
            },
          ),
          if (canDelete)
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title:
                  const Text('Xóa', style: TextStyle(color: Color(0xFFEF4444))),
              dense: true,
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteTask(t);
              },
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showStatusChangeSheet(WorkTask t) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFE4E4E7),
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Đổi trạng thái',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ...WorkTaskStatus.values
              .where((s) => s != WorkTaskStatus.cancelled)
              .map((s) => ListTile(
                    leading: Icon(_statusIcon(s), color: _statusColor(s)),
                    title: Text(getTaskStatusLabel(s)),
                    selected: t.status == s,
                    selectedTileColor: _statusColor(s).withValues(alpha: 0.08),
                    trailing: t.status == s
                        ? const Icon(Icons.check, color: Color(0xFF1E3A5F))
                        : null,
                    onTap: t.status == s
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _updateStatus(t.id, s);
                          },
                  )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Map<String, dynamic>? _getDeadlineInfo(WorkTask t) {
    if (t.status == WorkTaskStatus.completed ||
        t.status == WorkTaskStatus.cancelled) {
      if (t.completedDate != null) {
        return {
          'icon': Icons.check_circle,
          'color': const Color(0xFF22C55E),
          'text': 'Xong ${DateFormat('dd/MM').format(t.completedDate!)}'
        };
      }
      return null;
    }
    if (t.dueDate == null) return null;
    final now = DateTime.now();
    final diff = t.dueDate!.difference(now);
    if (diff.isNegative) {
      final days = diff.inDays.abs();
      if (days == 0) {
        return {
          'icon': Icons.warning_amber,
          'color': const Color(0xFFEF4444),
          'text': 'Trễ hôm nay'
        };
      }
      return {
        'icon': Icons.error_outline,
        'color': const Color(0xFFEF4444),
        'text': 'Trễ $days ngày'
      };
    } else {
      final days = diff.inDays;
      if (days == 0) {
        return {
          'icon': Icons.schedule,
          'color': const Color(0xFFF59E0B),
          'text': 'Hết hạn hôm nay'
        };
      }
      if (days == 1) {
        return {
          'icon': Icons.schedule,
          'color': const Color(0xFFF59E0B),
          'text': 'Còn 1 ngày'
        };
      }
      if (days <= 3) {
        return {
          'icon': Icons.schedule,
          'color': const Color(0xFFF59E0B),
          'text': 'Còn $days ngày'
        };
      }
      return {
        'icon': Icons.event,
        'color': const Color(0xFFA1A1AA),
        'text': DateFormat('dd/MM').format(t.dueDate!)
      };
    }
  }

  // ---------- Task Card ----------
  Widget _buildTaskCard(WorkTask t) {
    final isSel = _sel.contains(t.id);
    final isActive = _detailTask?.id == t.id;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: isActive ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
            color: isActive ? const Color(0xFF1E3A5F) : const Color(0xFFE4E4E7),
            width: isActive ? 1.5 : 0.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          if (_selectMode) {
            setState(() {
              isSel ? _sel.remove(t.id) : _sel.add(t.id);
            });
          } else {
            _loadDetail(t.id);
          }
        },
        onLongPress: () {
          if (!_selectMode) {
            setState(() {
              _selectMode = true;
              _sel.add(t.id);
            });
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border(
                left: BorderSide(color: _priorityColor(t.priority), width: 4)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_selectMode)
                    Checkbox(
                        value: isSel,
                        onChanged: (v) => setState(() {
                              v == true ? _sel.add(t.id) : _sel.remove(t.id);
                            }),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap),
                  Icon(_taskTypeIcon(t.taskType),
                      size: 15, color: _taskTypeColor(t.taskType)),
                  const SizedBox(width: 5),
                  Text(t.taskCode,
                      style: const TextStyle(
                          color: Color(0xFF1E3A5F),
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                  const SizedBox(width: 8),
                  _statusBadge(t.status),
                  const Spacer(),
                  _priorityBadge(t.priority),
                ],
              ),
              const SizedBox(height: 6),
              Text(t.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF18181B))),
              if (t.description != null && t.description!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(t.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFFA1A1AA), fontSize: 12)),
              ],
              if (t.progress > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                      child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: t.progress / 100,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE4E4E7),
                        valueColor:
                            AlwaysStoppedAnimation(_progressColor(t.progress))),
                  )),
                  const SizedBox(width: 8),
                  Text('${t.progress}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _progressColor(t.progress))),
                ]),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (t.assigneeName != null) ...[
                    CircleAvatar(
                        radius: 10,
                        backgroundColor: const Color(0xFF1E3A5F),
                        child: Text(t.assigneeName![0],
                            style: const TextStyle(
                                fontSize: 9, color: Colors.white))),
                    const SizedBox(width: 4),
                    Text(t.assigneeName!,
                        style: const TextStyle(
                            color: Color(0xFF71717A), fontSize: 11)),
                    const SizedBox(width: 12),
                  ],
                  if (t.dueDate != null) ...[
                    Icon(Icons.event,
                        size: 13,
                        color:
                            t.isOverdue ? Colors.red : const Color(0xFFA1A1AA)),
                    const SizedBox(width: 3),
                    Text(DateFormat('dd/MM/yyyy').format(t.dueDate!),
                        style: TextStyle(
                            fontSize: 11,
                            color: t.isOverdue
                                ? Colors.red
                                : const Color(0xFFA1A1AA),
                            fontWeight: t.isOverdue
                                ? FontWeight.w600
                                : FontWeight.normal)),
                  ],
                  const Spacer(),
                  // Thời gian nhân viên - hiển thị giờ ước tính/thực tế
                  if (t.estimatedHours != null) ...[
                    const Icon(Icons.access_time,
                        size: 13, color: Color(0xFFA1A1AA)),
                    const SizedBox(width: 3),
                    Text('${t.actualHours ?? 0}/${t.estimatedHours}h',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFA1A1AA))),
                    const SizedBox(width: 8),
                  ],
                  if (t.hasSubTasks) ...[
                    const Icon(Icons.checklist,
                        size: 13, color: Color(0xFFA1A1AA)),
                    Text(' ${t.completedSubTaskCount}/${t.subTaskCount}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFA1A1AA))),
                    const SizedBox(width: 6),
                  ],
                  if (t.hasComments) ...[
                    const Icon(Icons.chat_bubble_outline,
                        size: 13, color: Color(0xFFA1A1AA)),
                    Text(' ${t.commentCount}',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFA1A1AA))),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final pages = (_total / _pageSize).ceil();
    if (pages <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _page > 1
                ? () {
                    setState(() => _page--);
                    _loadTasks();
                  }
                : null),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8)),
          child: Text(
              'Hiển thị ${(_page - 1) * _pageSize + 1}-${(_page * _pageSize).clamp(0, _total)} / $_total',
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
        IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _page < pages
                ? () {
                    setState(() => _page++);
                    _loadTasks();
                  }
                : null),
      ]),
    );
  }

  // ======================== KANBAN VIEW ========================
  Widget _buildKanbanView() {
    if (_kanban == null) {
      _loadKanban();
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 600) {
        return ListView(
          padding: const EdgeInsets.all(12),
          children:
              _kanban!.columns.map((c) => _buildKanbanColMobile(c)).toList(),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _kanban!.columns.map((c) => _buildKanbanCol(c)).toList(),
        ),
      );
    });
  }

  Widget _buildKanbanColMobile(KanbanColumn col) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _statusColor(col.status).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                  bottom:
                      BorderSide(color: _statusColor(col.status), width: 2)),
            ),
            child: Row(children: [
              Icon(_statusIcon(col.status),
                  color: _statusColor(col.status), size: 20),
              const SizedBox(width: 8),
              Text(getTaskStatusLabel(col.status),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _statusColor(col.status))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: _statusColor(col.status),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${col.taskCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          ...col.tasks.map((t) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: _buildKanbanCard(t),
              )),
        ],
      ),
    );
  }

  Widget _buildKanbanCol(KanbanColumn col) {
    return Container(
      width: 300,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _statusColor(col.status).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                  bottom:
                      BorderSide(color: _statusColor(col.status), width: 2)),
            ),
            child: Row(children: [
              Icon(_statusIcon(col.status),
                  color: _statusColor(col.status), size: 20),
              const SizedBox(width: 8),
              Text(getTaskStatusLabel(col.status),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _statusColor(col.status))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: _statusColor(col.status),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${col.taskCount}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          Expanded(
            child: DragTarget<WorkTask>(
              onWillAcceptWithDetails: (d) => d.data.status != col.status,
              onAcceptWithDetails: (d) => _updateStatus(d.data.id, col.status),
              builder: (ctx, candidate, _) => Container(
                decoration: BoxDecoration(
                  color: candidate.isNotEmpty
                      ? _statusColor(col.status).withValues(alpha: 0.05)
                      : const Color(0xFFFAFAFA),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: col.tasks.length,
                  itemBuilder: (_, i) {
                    final t = col.tasks[i];
                    return Draggable<WorkTask>(
                      data: t,
                      feedback: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(8),
                          child:
                              SizedBox(width: 280, child: _buildKanbanCard(t))),
                      childWhenDragging:
                          Opacity(opacity: 0.3, child: _buildKanbanCard(t)),
                      child: _buildKanbanCard(t),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKanbanCard(WorkTask t) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _loadDetail(t.id),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(t.taskCode,
                  style: const TextStyle(
                      color: Color(0xFF1E3A5F),
                      fontSize: 10,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              _priorityBadge(t.priority),
            ]),
            const SizedBox(height: 4),
            Text(t.title,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (t.progress > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                      value: t.progress / 100,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFE4E4E7),
                      valueColor:
                          AlwaysStoppedAnimation(_progressColor(t.progress)))),
            ],
            const SizedBox(height: 6),
            Row(children: [
              if (t.assigneeName != null)
                CircleAvatar(
                    radius: 10,
                    backgroundColor: const Color(0xFF1E3A5F),
                    child: Text(t.assigneeName![0],
                        style:
                            const TextStyle(fontSize: 9, color: Colors.white))),
              const Spacer(),
              if (t.dueDate != null)
                Text(DateFormat('dd/MM').format(t.dueDate!),
                    style: TextStyle(
                        fontSize: 10,
                        color: t.isOverdue
                            ? Colors.red
                            : const Color(0xFFA1A1AA))),
            ]),
          ]),
        ),
      ),
    );
  }

  // ======================== STATISTICS VIEW ========================
  // Tổng kết các hoạt động: thống kê tổng quan, theo trạng thái, theo nhân viên
  Widget _buildStatsView() {
    if (_stats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = _stats!;
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 10 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // --- Summary Cards (compact on mobile) ---
        Row(
          children: [
            Expanded(
                child: _statCard('Tổng', s.totalTasks, Icons.assignment,
                    const Color(0xFF1E3A5F))),
            const SizedBox(width: 6),
            Expanded(
                child: _statCard('Xong', s.completedCount, Icons.check_circle,
                    const Color(0xFF1E3A5F))),
            const SizedBox(width: 6),
            Expanded(
                child: _statCard('Đang làm', s.inProgressCount,
                    Icons.pending_actions, const Color(0xFFF59E0B))),
            const SizedBox(width: 6),
            Expanded(
                child: _statCard('Quá hạn', s.overdueCount, Icons.warning_amber,
                    const Color(0xFFEF4444))),
          ],
        ),
        const SizedBox(height: 12),
        // --- Completion Rate ---
        _sectionCard('Tỉ lệ hoàn thành', Icons.pie_chart,
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                            value: s.completionRate / 100,
                            minHeight: 24,
                            backgroundColor: const Color(0xFFE4E4E7),
                            valueColor: const AlwaysStoppedAnimation(
                                Color(0xFF1E3A5F))))),
                const SizedBox(width: 12),
                Text('${s.completionRate.toStringAsFixed(1)}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Color(0xFF1E3A5F))),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Tiến độ trung bình: ${s.averageProgress.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Color(0xFFA1A1AA))),
            ])),
        const SizedBox(height: 12),
        // --- Theo trạng thái ---
        _sectionCard('Phân bổ theo trạng thái', Icons.donut_large,
            child: Column(children: [
              _statBar('Chờ làm', s.todoCount, s.totalTasks,
                  const Color(0xFFA1A1AA)),
              _statBar('Đang làm', s.inProgressCount, s.totalTasks,
                  const Color(0xFF1E3A5F)),
              _statBar('Đang xem xét', s.inReviewCount, s.totalTasks,
                  const Color(0xFF0F2340)),
              _statBar('Hoàn thành', s.completedCount, s.totalTasks,
                  const Color(0xFF1E3A5F)),
              _statBar('Tạm hoãn', s.onHoldCount, s.totalTasks,
                  const Color(0xFFF59E0B)),
              _statBar('Đã hủy', s.cancelledCount, s.totalTasks,
                  const Color(0xFFEF4444)),
            ])),
        const SizedBox(height: 12),
        // --- Theo nhân viên (thời gian nhân viên) ---
        if (s.byAssignee != null && s.byAssignee!.isNotEmpty)
          _sectionCard('Thống kê theo nhân viên', Icons.people,
              child: Column(
                children: s.byAssignee!
                    .map((a) => Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF1E3A5F),
                                child: Text(a.employeeName?[0] ?? '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(a.employeeName ?? 'Unknown',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF18181B))),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    _miniStat('Tổng', a.totalTasks,
                                        const Color(0xFF1E3A5F)),
                                    const SizedBox(width: 6),
                                    _miniStat('Xong', a.completedTasks,
                                        const Color(0xFF1E3A5F)),
                                    const SizedBox(width: 6),
                                    _miniStat('Đang làm', a.inProgressTasks,
                                        const Color(0xFFF59E0B)),
                                    if (a.overdueTasks > 0) ...[
                                      const SizedBox(width: 6),
                                      _miniStat('Quá hạn', a.overdueTasks,
                                          const Color(0xFFEF4444))
                                    ],
                                  ]),
                                ])),
                            // Tỉ lệ hoàn thành cá nhân
                            SizedBox(
                              width: 48,
                              height: 48,
                              child:
                                  Stack(alignment: Alignment.center, children: [
                                CircularProgressIndicator(
                                  value: a.totalTasks > 0
                                      ? a.completedTasks / a.totalTasks
                                      : 0,
                                  strokeWidth: 4,
                                  backgroundColor: const Color(0xFFE4E4E7),
                                  valueColor: const AlwaysStoppedAnimation(
                                      Color(0xFF1E3A5F)),
                                ),
                                Text(
                                    '${a.totalTasks > 0 ? (a.completedTasks / a.totalTasks * 100).round() : 0}%',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ]),
                            ),
                          ]),
                        ))
                    .toList(),
              )),
      ]),
    );
  }

  Widget _statCard(String title, int value, IconData icon, Color c) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: c.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: c, size: 16),
        ),
        const SizedBox(height: 4),
        Text('$value',
            style:
                TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c)),
        Text(title,
            style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  Widget _sectionCard(String title, IconData icon, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: Color(0x08000000), blurRadius: 8)
          ]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF1E3A5F)),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF18181B)))
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }

  Widget _statBar(String label, int count, int total, Color c) {
    final pct = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
            width: 100,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12, color: Color(0xFF71717A)))),
        Expanded(
            child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E4E7),
                    valueColor: AlwaysStoppedAnimation(c)))),
        const SizedBox(width: 8),
        SizedBox(
            width: 50,
            child: Text('$count (${(pct * 100).round()}%)',
                style:
                    const TextStyle(fontSize: 11, color: Color(0xFF71717A)))),
      ]),
    );
  }

  Widget _miniStat(String label, int value, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4)),
      child: Text('$label: $value',
          style:
              TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w500)),
    );
  }

  // ======================== SIDE DETAIL PANEL ========================
  // Panel chi tiết: thông tin, cập nhật tiến độ, đốc thúc, đánh giá, bình luận, lịch sử
  Widget _buildDetailPanel() {
    if (_detailLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final t = _detailTask!;
    final isMobile = Responsive.isMobile(context);
    final deadlineInfo = _getDeadlineInfo(t);
    final canEdit =
        Provider.of<PermissionProvider>(context, listen: false).canEdit('Task');
    final canDelete = Provider.of<PermissionProvider>(context, listen: false)
        .canDelete('Task');

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // ── Detail Header with gradient ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8B)]),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Top bar: back + code + status + actions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    child: Row(children: [
                      if (isMobile)
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 22),
                          onPressed: () => setState(() => _detailTask = null),
                        )
                      else
                        const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(t.taskCode,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      _statusBadgeLight(t.status),
                      const Spacer(),
                      if (canEdit)
                        IconButton(
                            icon: const Icon(Icons.edit,
                                size: 20, color: Colors.white70),
                            tooltip: 'Chỉnh sửa',
                            onPressed: () => _showEditDialog(t)),
                      IconButton(
                          icon: const Icon(Icons.notifications_active,
                              size: 20, color: Color(0xFFF59E0B)),
                          tooltip: 'Đốc thúc',
                          onPressed: () => _showReminderDialog(t)),
                      IconButton(
                          icon: const Icon(Icons.star_rate,
                              size: 20, color: Color(0xFFF59E0B)),
                          tooltip: 'Đánh giá',
                          onPressed: () => _showEvaluationDialog(t)),
                      if (canDelete)
                        IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 20, color: Color(0xFFFF8A80)),
                            tooltip: 'Xóa',
                            onPressed: () => _confirmDeleteTask(t)),
                      if (!isMobile)
                        IconButton(
                            icon: const Icon(Icons.close,
                                size: 20, color: Colors.white70),
                            onPressed: () =>
                                setState(() => _detailTask = null)),
                    ]),
                  ),
                  // Title + deadline
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 6),
                        Row(children: [
                          if (t.assigneeName != null) ...[
                            CircleAvatar(
                                radius: 11,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                child: Text(t.assigneeName![0],
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600))),
                            const SizedBox(width: 6),
                            Text(t.assigneeName!,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            const SizedBox(width: 12),
                          ],
                          if (deadlineInfo != null) ...[
                            Icon(deadlineInfo['icon'] as IconData,
                                size: 14, color: Colors.white70),
                            const SizedBox(width: 4),
                            Text(deadlineInfo['text'] as String,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Quick status update chips ──
                Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    children: WorkTaskStatus.values
                        .where((s) => s != WorkTaskStatus.cancelled)
                        .map((s) {
                      final active = t.status == s;
                      return ChoiceChip(
                        label: Text(getTaskStatusLabel(s),
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    active ? Colors.white : _statusColor(s))),
                        selected: active,
                        selectedColor: _statusColor(s),
                        backgroundColor:
                            _statusColor(s).withValues(alpha: 0.08),
                        onSelected:
                            active ? null : (_) => _updateStatus(t.id, s),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList()),
                const SizedBox(height: 16),
                // ── Progress section ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.trending_up,
                            size: 16, color: Color(0xFF1E3A5F)),
                        const SizedBox(width: 6),
                        const Text('Tiến độ',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        const Spacer(),
                        Text('${t.progress}%',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: _progressColor(t.progress))),
                      ]),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: _progressColor(t.progress),
                          thumbColor: _progressColor(t.progress),
                          inactiveTrackColor: const Color(0xFFE4E4E7),
                          overlayColor:
                              _progressColor(t.progress).withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: t.progress.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 20,
                          label: '${t.progress}%',
                          onChanged: (v) => setState(() {
                            _detailTask = WorkTask(
                              id: t.id,
                              taskCode: t.taskCode,
                              title: t.title,
                              description: t.description,
                              taskType: t.taskType,
                              priority: t.priority,
                              status: t.status,
                              progress: v.toInt(),
                              storeId: t.storeId,
                              assignedById: t.assignedById,
                              createdAt: t.createdAt,
                              assigneeName: t.assigneeName,
                              assignedByName: t.assignedByName,
                              dueDate: t.dueDate,
                              startDate: t.startDate,
                              completedDate: t.completedDate,
                              estimatedHours: t.estimatedHours,
                              actualHours: t.actualHours,
                              assigneeId: t.assigneeId,
                              comments: t.comments,
                              subTasks: t.subTasks,
                              subTaskCount: t.subTaskCount,
                              completedSubTaskCount: t.completedSubTaskCount,
                              commentCount: t.commentCount,
                              attachmentCount: t.attachmentCount,
                            );
                          }),
                          onChangeEnd: (v) => _updateProgress(t.id, v.toInt()),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _updateProgress(t.id, t.progress),
                          icon: const Icon(Icons.upload, size: 14),
                          label: const Text(
                              'Cập nhật tiến độ (ghi chú & hình ảnh)',
                              style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E3A5F),
                            side: const BorderSide(
                                color: Color(0xFF1E3A5F), width: 0.5),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Mô tả ──
                if (t.description != null && t.description!.isNotEmpty) ...[
                  _detailLabel('Mô tả'),
                  const SizedBox(height: 4),
                  Text(t.description!,
                      style: const TextStyle(
                          color: Color(0xFF71717A), fontSize: 13)),
                  const SizedBox(height: 12),
                ],
                // ── Chi tiết thông tin ──
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFAFAFA),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(children: [
                    _detailRow(
                        Icons.person, 'Người giao', t.assignedByName ?? 'N/A'),
                    _detailRow(Icons.person_outline, 'Người thực hiện',
                        t.assigneeName ?? 'Chưa giao'),
                    _detailRow(
                        Icons.flag, 'Độ ưu tiên', getPriorityLabel(t.priority),
                        color: _priorityColor(t.priority)),
                    _detailRow(
                        Icons.category, 'Loại', getTaskTypeLabel(t.taskType)),
                    if (t.startDate != null)
                      _detailRow(Icons.play_arrow, 'Bắt đầu',
                          DateFormat('dd/MM/yyyy HH:mm').format(t.startDate!)),
                    if (t.dueDate != null)
                      _detailRow(Icons.event, 'Hết hạn',
                          DateFormat('dd/MM/yyyy HH:mm').format(t.dueDate!),
                          color: t.isOverdue ? Colors.red : null),
                    if (t.completedDate != null)
                      _detailRow(
                          Icons.check_circle,
                          'Hoàn thành',
                          DateFormat('dd/MM/yyyy HH:mm')
                              .format(t.completedDate!),
                          color: const Color(0xFF22C55E)),
                    if (t.estimatedHours != null)
                      _detailRow(Icons.schedule, 'Giờ ước tính',
                          '${t.estimatedHours}h'),
                    if (t.actualHours != null)
                      _detailRow(
                          Icons.timer, 'Giờ thực tế', '${t.actualHours}h'),
                  ]),
                ),
                const SizedBox(height: 16),
                // ── Công việc con (Sub-tasks) ──
                if (t.subTasks != null && t.subTasks!.isNotEmpty) ...[
                  _detailLabel(
                      'Công việc con (${t.completedSubTaskCount}/${t.subTaskCount})'),
                  const SizedBox(height: 6),
                  ...t.subTasks!.map((st) => Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFAFAFA),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFE4E4E7), width: 0.5)),
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(
                              st.status == WorkTaskStatus.completed
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              size: 18,
                              color: st.status == WorkTaskStatus.completed
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFFA1A1AA)),
                          title: Text(st.title,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  decoration:
                                      st.status == WorkTaskStatus.completed
                                          ? TextDecoration.lineThrough
                                          : null,
                                  color: st.status == WorkTaskStatus.completed
                                      ? const Color(0xFFA1A1AA)
                                      : const Color(0xFF18181B))),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            if (st.assigneeName != null)
                              Text(st.assigneeName!,
                                  style: const TextStyle(
                                      fontSize: 10, color: Color(0xFFA1A1AA))),
                            const SizedBox(width: 4),
                            _priorityBadge(st.priority),
                          ]),
                          onTap: () => _loadDetail(st.id),
                        ),
                      )),
                  const SizedBox(height: 16),
                ] else if (t.hasSubTasks) ...[
                  _detailLabel(
                      'Công việc con (${t.completedSubTaskCount}/${t.subTaskCount})'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Expanded(
                          child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: t.subTaskCount > 0
                                ? t.completedSubTaskCount / t.subTaskCount
                                : 0,
                            minHeight: 6,
                            backgroundColor: const Color(0xFFE4E4E7),
                            valueColor: const AlwaysStoppedAnimation(
                                Color(0xFF1E3A5F))),
                      )),
                      const SizedBox(width: 8),
                      Text('${t.completedSubTaskCount}/${t.subTaskCount}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E3A5F))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                // ── Tags ──
                if (t.tagList.isNotEmpty) ...[
                  _detailLabel('Nhãn'),
                  const SizedBox(height: 6),
                  Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: t.tagList
                          .map((tag) => Chip(
                                label: Text(tag,
                                    style: const TextStyle(fontSize: 10)),
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                backgroundColor: const Color(0xFFE0F2FE),
                                side: BorderSide.none,
                              ))
                          .toList()),
                  const SizedBox(height: 16),
                ],
                // ── Đánh giá (Evaluation Display) ──
                _buildEvaluationSection(t),
                // ── Báo cáo tiến độ ──
                _buildProgressReports(),
                const SizedBox(height: 16),
                // ── Bình luận ──
                _detailLabel('Bình luận'),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: _commentCtrl,
                    decoration: InputDecoration(
                      hintText: 'Thêm bình luận...',
                      hintStyle: const TextStyle(fontSize: 13),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE4E4E7))),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                    ),
                    maxLines: 2,
                    style: const TextStyle(fontSize: 13),
                  )),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _addComment,
                    icon: const Icon(Icons.send, size: 18),
                    style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F)),
                  ),
                ]),
                const SizedBox(height: 8),
                if (_comments.isEmpty)
                  const Center(
                      child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Chưa có bình luận',
                              style: TextStyle(
                                  color: Color(0xFFA1A1AA), fontSize: 13))))
                else
                  ..._comments.map((c) => _buildCommentCard(c)),
                const SizedBox(height: 16),
                // ── Lịch sử thay đổi ──
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: _detailLabel('Lịch sử thay đổi'),
                  initiallyExpanded: false,
                  children: _history.isEmpty
                      ? [
                          const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text('Chưa có lịch sử',
                                  style: TextStyle(color: Color(0xFFA1A1AA))))
                        ]
                      : _history
                          .take(20)
                          .map((h) => ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                leading: Icon(_historyIcon(h.changeType),
                                    size: 16, color: const Color(0xFF1E3A5F)),
                                title: Text(h.description ?? h.changeType,
                                    style: const TextStyle(fontSize: 12)),
                                subtitle: Text(
                                    '${h.userName ?? ''} \u2022 ${DateFormat('dd/MM HH:mm').format(h.createdAt)}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFA1A1AA))),
                              ))
                          .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Evaluation Section in Detail Panel ──
  Widget _buildEvaluationSection(WorkTask t) {
    // Show evaluation if task has any
    if (t.status != WorkTaskStatus.completed &&
        t.status != WorkTaskStatus.inReview) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _detailLabel('Đánh giá'),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _showEvaluationDialog(t),
            icon:
                const Icon(Icons.star_rate, size: 14, color: Color(0xFFF59E0B)),
            label: const Text('Đánh giá',
                style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28)),
          ),
        ]),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline, size: 16, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Expanded(
                child: Text(
                    'Nhấn "Đánh giá" để chấm điểm chất lượng, tiến độ và tổng thể (1-5 sao)',
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
          ]),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Báo cáo tiến độ - hiển thị các lần cập nhật tiến độ ──
  Widget _buildProgressReports() {
    final progressComments =
        _comments.where((c) => c.isProgressUpdate).toList();
    if (progressComments.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.assessment, size: 16, color: Color(0xFF1E3A5F)),
          const SizedBox(width: 6),
          _detailLabel('Báo cáo tiến độ'),
          const Spacer(),
          Text('${progressComments.length} lần cập nhật',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
        ]),
        const SizedBox(height: 8),
        ...progressComments.map((c) {
          final images = c.imageUrlList;
          final links = c.linkUrlList;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: user + time + progress badge
                Row(children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: const Color(0xFF22C55E),
                    child: Text(
                      (c.userName ?? '?')[0].toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.userName ?? 'Unknown',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12)),
                        Text(DateFormat('dd/MM/yyyy HH:mm').format(c.createdAt),
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFFA1A1AA))),
                      ],
                    ),
                  ),
                  if (c.progressSnapshot != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _progressColor(c.progressSnapshot!),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${c.progressSnapshot}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                ]),
                // Content
                if (c.content.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(c.content,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF18181B))),
                ],
                // Images
                if (images.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: images.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (ctx, i) => InkWell(
                        onTap: () => _showImageDialog(images[i]),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            images[i],
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 100,
                              height: 100,
                              color: const Color(0xFFE4E4E7),
                              child: const Icon(Icons.broken_image,
                                  size: 32, color: Color(0xFFA1A1AA)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // Links
                if (links.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ...links.map((url) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: InkWell(
                          onTap: () => _launchUrl(url),
                          child: Row(children: [
                            const Icon(Icons.link,
                                size: 14, color: Color(0xFF1E3A5F)),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                url,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF1E3A5F),
                                    decoration: TextDecoration.underline),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ]),
                        ),
                      )),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _statusBadgeLight(WorkTaskStatus s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(getTaskStatusLabel(s),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _detailLabel(String text) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF18181B)));

  Widget _detailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, size: 16, color: color ?? const Color(0xFFA1A1AA)),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
        Expanded(
            child: Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: color ?? const Color(0xFF18181B)))),
      ]),
    );
  }

  Widget _buildCommentCard(TaskComment c) {
    final isProgress = c.isProgressUpdate;
    final images = c.imageUrlList;
    final links = c.linkUrlList;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: isProgress ? const Color(0xFFF0FDF4) : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: isProgress
              ? Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.3))
              : null),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
              radius: 12,
              backgroundColor: isProgress
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF1E3A5F),
              child: Icon(
                isProgress ? Icons.trending_up : Icons.person,
                size: 12,
                color: Colors.white,
              )),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.userName ?? 'Unknown',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12)),
                if (isProgress && c.progressSnapshot != null)
                  Text('Cập nhật tiến độ: ${c.progressSnapshot}%',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF22C55E),
                          fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          if (isProgress && c.progressSnapshot != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('${c.progressSnapshot}%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          const SizedBox(width: 6),
          Text(DateFormat('dd/MM HH:mm').format(c.createdAt),
              style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
        ]),
        const SizedBox(height: 6),
        Text(c.content,
            style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
        // Images
        if (images.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: images
                .map((url) => InkWell(
                      onTap: () => _showImageDialog(url),
                      child: Container(
                        width: 80,
                        height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image,
                                  size: 20, color: Color(0xFFA1A1AA)),
                            ),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
        // Links
        if (links.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: links
                .map((url) => InkWell(
                      onTap: () => _launchUrl(url),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: const Color(0xFF1E3A5F)
                                  .withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.link,
                                size: 12, color: Color(0xFF1E3A5F)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                url.length > 40
                                    ? '${url.substring(0, 40)}...'
                                    : url,
                                style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF1E3A5F),
                                    decoration: TextDecoration.underline),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ]),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Không thể mở link: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Hình ảnh', style: TextStyle(fontSize: 14)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close))
              ],
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Icon(Icons.broken_image,
                      size: 60, color: Color(0xFFA1A1AA)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======================== DIALOGS ========================

  // --- Tạo công việc ---
  void _showCreateDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final hoursCtrl = TextEditingController();
    var type = TaskType.task;
    var priority = TaskPriority.medium;
    List<String> selectedAssigneeIds = [];
    DateTime? startDate, dueDate;
    bool saving = false;
    final isMobile = Responsive.isMobile(context);

    void calcHours(StateSetter ss) {
      if (startDate != null &&
          dueDate != null &&
          dueDate!.isAfter(startDate!)) {
        final diff = dueDate!.difference(startDate!);
        final hours = (diff.inMinutes / 60.0);
        ss(() => hoursCtrl.text = hours.toStringAsFixed(1));
      }
    }

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
              final formContent = SingleChildScrollView(
                  padding:
                      isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _dialogField(titleCtrl, 'Tiêu đề *', Icons.title),
                    const SizedBox(height: 12),
                    _dialogField(descCtrl, 'Mô tả', Icons.description,
                        maxLines: 3),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: DropdownButtonFormField<TaskType>(
                        initialValue: type,
                        decoration: _dropDecor('Loại'),
                        items: TaskType.values
                            .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(getTaskTypeLabel(t),
                                    style: const TextStyle(fontSize: 13))))
                            .toList(),
                        onChanged: (v) => ss(() => type = v!),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          child: DropdownButtonFormField<TaskPriority>(
                        initialValue: priority,
                        decoration: _dropDecor('Ưu tiên'),
                        items: TaskPriority.values
                            .map((p) => DropdownMenuItem(
                                value: p,
                                child: Row(children: [
                                  Icon(Icons.flag,
                                      size: 14, color: _priorityColor(p)),
                                  const SizedBox(width: 4),
                                  Text(getPriorityLabel(p),
                                      style: const TextStyle(fontSize: 13))
                                ])))
                            .toList(),
                        onChanged: (v) => ss(() => priority = v!),
                      )),
                    ]),
                    const SizedBox(height: 12),
                    // Multi-assignee picker
                    InputDecorator(
                      decoration: _dropDecor('Giao cho (Chọn nhiều người)'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (selectedAssigneeIds.isNotEmpty &&
                              _employees.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: selectedAssigneeIds.map((id) {
                                final emp = _employees
                                    .cast<dynamic>()
                                    .where((e) => e.id == id)
                                    .firstOrNull;
                                final name = emp?.fullName ?? id;
                                return Chip(
                                  label: Text(name,
                                      style: const TextStyle(fontSize: 12)),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  onDeleted: () =>
                                      ss(() => selectedAssigneeIds.remove(id)),
                                  backgroundColor: const Color(0xFFEFF6FF),
                                  side: const BorderSide(
                                      color: Color(0xFF1E3A5F), width: 0.5),
                                  labelPadding: const EdgeInsets.only(left: 4),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              if (_employees.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Đang tải danh sách nhân viên, vui lòng thử lại...')),
                                );
                                return;
                              }
                              final picked = await Navigator.of(context)
                                  .push<List<String>>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => _MultiAssigneePickerPage(
                                    employees: _employees,
                                    selected: List.from(selectedAssigneeIds),
                                  ),
                                ),
                              );
                              if (picked != null) {
                                ss(() => selectedAssigneeIds = picked);
                              }
                            },
                            child: Row(
                              children: [
                                Icon(Icons.person_add,
                                    size: 16,
                                    color: const Color(0xFF1E3A5F)
                                        .withValues(alpha: 0.7)),
                                const SizedBox(width: 6),
                                Text(
                                  selectedAssigneeIds.isEmpty
                                      ? 'Chọn người thực hiện...'
                                      : 'Thêm người...',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: const Color(0xFF1E3A5F)
                                          .withValues(alpha: 0.7)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _datePickerField(
                              'Bắt đầu (ngày giờ)', startDate, (d) {
                        ss(() => startDate = d);
                        calcHours(ss);
                      })),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _datePickerField('Hết hạn (ngày giờ)', dueDate,
                              (d) {
                        ss(() => dueDate = d);
                        calcHours(ss);
                      })),
                    ]),
                    if (startDate != null &&
                        dueDate != null &&
                        dueDate!.isAfter(startDate!))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 14, color: Color(0xFF1E3A5F)),
                            const SizedBox(width: 4),
                            Text(
                              'Thời gian: ${_formatDuration(dueDate!.difference(startDate!))}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1E3A5F),
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    _dialogField(hoursCtrl, 'Giờ ước tính', Icons.access_time,
                        keyboardType: TextInputType.number),
                  ]));
              final onSave = saving
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        _snack(ctx, 'Vui lòng nhập tiêu đề', Colors.red);
                        return;
                      }
                      ss(() => saving = true);
                      final r = await _api.createTask(
                        title: titleCtrl.text.trim(),
                        description: descCtrl.text.trim().isEmpty
                            ? null
                            : descCtrl.text.trim(),
                        taskType: type.index,
                        priority: priority.index,
                        assigneeId: selectedAssigneeIds.isNotEmpty
                            ? selectedAssigneeIds.first
                            : null,
                        assigneeIds: selectedAssigneeIds.length > 1
                            ? selectedAssigneeIds
                            : null,
                        startDate: startDate,
                        dueDate: dueDate,
                        estimatedHours: double.tryParse(hoursCtrl.text),
                      );
                      ss(() => saving = false);
                      if (!ctx.mounted) return;
                      if (r['isSuccess'] == true) {
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        _snack(context, 'Tạo công việc thành công',
                            const Color(0xFF1E3A5F));
                        _loadTasks();
                        _loadStats();
                      } else {
                        _snack(ctx, r['message'] ?? 'Lỗi', Colors.red);
                      }
                    };
              final saveChild = saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Tạo');
              if (isMobile) {
                return Dialog(
                  insetPadding: EdgeInsets.zero,
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: Scaffold(
                      appBar: AppBar(
                        title: const Text('Tạo công việc mới'),
                        leading: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx)),
                      ),
                      body: formContent,
                      bottomNavigationBar: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: FilledButton(
                            onPressed: onSave,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A5F),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Tạo công việc',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Row(children: [
                  Icon(Icons.add_task, color: Color(0xFF1E3A5F)),
                  SizedBox(width: 8),
                  Text('Tạo công việc mới', style: TextStyle(fontSize: 18)),
                ]),
                content: SizedBox(
                    width: MediaQuery.of(ctx).size.width < 600
                        ? MediaQuery.of(ctx).size.width - 32
                        : 520,
                    child: formContent),
                actions: [
                  AppDialogActions(
                    onConfirm: onSave,
                    confirmLabel:
                        saveChild is Text ? saveChild.data ?? 'Lưu' : 'Lưu',
                    isLoading: saveChild is! Text,
                  ),
                ],
              );
            })).then((_) {
      titleCtrl.dispose();
      descCtrl.dispose();
      hoursCtrl.dispose();
    });
  }

  // --- Chỉnh sửa công việc ---
  void _showEditDialog(WorkTask task) {
    final titleCtrl = TextEditingController(text: task.title);
    final descCtrl = TextEditingController(text: task.description ?? '');
    final hoursCtrl =
        TextEditingController(text: task.estimatedHours?.toString() ?? '');
    final actualCtrl =
        TextEditingController(text: task.actualHours?.toString() ?? '');
    var type = task.taskType;
    var priority = task.priority;
    // Build initial selectedAssigneeIds from assignees list or single assigneeId
    List<String> selectedAssigneeIds = [];
    if (task.assignees != null && task.assignees!.isNotEmpty) {
      selectedAssigneeIds = task.assignees!.map((a) => a.employeeId).toList();
    } else if (task.assigneeId != null) {
      selectedAssigneeIds = [task.assigneeId!];
    }
    DateTime? startDate = task.startDate, dueDate = task.dueDate;
    bool saving = false;
    final isMobile = Responsive.isMobile(context);

    void calcHours(StateSetter ss) {
      if (startDate != null &&
          dueDate != null &&
          dueDate!.isAfter(startDate!)) {
        final diff = dueDate!.difference(startDate!);
        final hours = (diff.inMinutes / 60.0);
        ss(() => hoursCtrl.text = hours.toStringAsFixed(1));
      }
    }

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
              final formContent = SingleChildScrollView(
                  padding:
                      isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _dialogField(titleCtrl, 'Tiêu đề *', Icons.title),
                    const SizedBox(height: 12),
                    _dialogField(descCtrl, 'Mô tả', Icons.description,
                        maxLines: 3),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: DropdownButtonFormField<TaskType>(
                              initialValue: type,
                              decoration: _dropDecor('Loại'),
                              items: TaskType.values
                                  .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(getTaskTypeLabel(t),
                                          style:
                                              const TextStyle(fontSize: 13))))
                                  .toList(),
                              onChanged: (v) => ss(() => type = v!))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: DropdownButtonFormField<TaskPriority>(
                              initialValue: priority,
                              decoration: _dropDecor('Ưu tiên'),
                              items: TaskPriority.values
                                  .map((p) => DropdownMenuItem(
                                      value: p,
                                      child: Row(children: [
                                        Icon(Icons.flag,
                                            size: 14, color: _priorityColor(p)),
                                        const SizedBox(width: 4),
                                        Text(getPriorityLabel(p),
                                            style:
                                                const TextStyle(fontSize: 13))
                                      ])))
                                  .toList(),
                              onChanged: (v) => ss(() => priority = v!))),
                    ]),
                    const SizedBox(height: 12),
                    // Multi-assignee picker
                    InputDecorator(
                      decoration: _dropDecor('Giao cho (Chọn nhiều người)'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (selectedAssigneeIds.isNotEmpty &&
                              _employees.isNotEmpty)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: selectedAssigneeIds.map((id) {
                                final emp = _employees
                                    .cast<dynamic>()
                                    .where((e) => e.id == id)
                                    .firstOrNull;
                                final name = emp?.fullName ?? id;
                                return Chip(
                                  label: Text(name,
                                      style: const TextStyle(fontSize: 12)),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  onDeleted: () =>
                                      ss(() => selectedAssigneeIds.remove(id)),
                                  backgroundColor: const Color(0xFFEFF6FF),
                                  side: const BorderSide(
                                      color: Color(0xFF1E3A5F), width: 0.5),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                );
                              }).toList(),
                            ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () async {
                              if (_employees.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Đang tải danh sách nhân viên, vui lòng thử lại...')),
                                );
                                return;
                              }
                              final picked = await Navigator.of(context)
                                  .push<List<String>>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => _MultiAssigneePickerPage(
                                    employees: _employees,
                                    selected: List.from(selectedAssigneeIds),
                                  ),
                                ),
                              );
                              if (picked != null) {
                                ss(() => selectedAssigneeIds = picked);
                              }
                            },
                            child: Row(
                              children: [
                                Icon(Icons.person_add,
                                    size: 16,
                                    color: const Color(0xFF1E3A5F)
                                        .withValues(alpha: 0.7)),
                                const SizedBox(width: 6),
                                Text(
                                  selectedAssigneeIds.isEmpty
                                      ? 'Chọn người thực hiện...'
                                      : 'Thêm người...',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: const Color(0xFF1E3A5F)
                                          .withValues(alpha: 0.7)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _datePickerField(
                              'Bắt đầu (ngày giờ)', startDate, (d) {
                        ss(() => startDate = d);
                        calcHours(ss);
                      })),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _datePickerField('Hết hạn (ngày giờ)', dueDate,
                              (d) {
                        ss(() => dueDate = d);
                        calcHours(ss);
                      })),
                    ]),
                    if (startDate != null &&
                        dueDate != null &&
                        dueDate!.isAfter(startDate!))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 14, color: Color(0xFF1E3A5F)),
                            const SizedBox(width: 4),
                            Text(
                              'Thời gian: ${_formatDuration(dueDate!.difference(startDate!))}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF1E3A5F),
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: _dialogField(
                              hoursCtrl, 'Giờ ước tính', Icons.schedule,
                              keyboardType: TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _dialogField(
                              actualCtrl, 'Giờ thực tế', Icons.timer,
                              keyboardType: TextInputType.number)),
                    ]),
                  ]));
              final onSave = saving
                  ? null
                  : () async {
                      if (titleCtrl.text.trim().isEmpty) {
                        _snack(ctx, 'Vui lòng nhập tiêu đề', Colors.red);
                        return;
                      }
                      ss(() => saving = true);
                      final data = <String, dynamic>{
                        'title': titleCtrl.text.trim(),
                        'description': descCtrl.text.trim(),
                        'taskType': type.index,
                        'priority': priority.index,
                        if (selectedAssigneeIds.isNotEmpty)
                          'assigneeId': selectedAssigneeIds.first,
                        if (selectedAssigneeIds.length > 1)
                          'assigneeIds': selectedAssigneeIds,
                        if (startDate != null)
                          'startDate': startDate!.toIso8601String(),
                        if (dueDate != null)
                          'dueDate': dueDate!.toIso8601String(),
                        if (hoursCtrl.text.isNotEmpty)
                          'estimatedHours': double.tryParse(hoursCtrl.text),
                        if (actualCtrl.text.isNotEmpty)
                          'actualHours': double.tryParse(actualCtrl.text),
                      };
                      final r = await _api.updateTask(task.id, data);
                      ss(() => saving = false);
                      if (!ctx.mounted) return;
                      if (r['isSuccess'] == true) {
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        _snack(context, 'Đã cập nhật', const Color(0xFF1E3A5F));
                        _loadDetail(task.id);
                        _loadTasks();
                        _loadStats();
                      } else {
                        _snack(ctx, r['message'] ?? 'Lỗi', Colors.red);
                      }
                    };
              final saveChild = saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Lưu');
              if (isMobile) {
                return Dialog(
                  insetPadding: EdgeInsets.zero,
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: Scaffold(
                      appBar: AppBar(
                        title: Text('Sửa: ${task.taskCode}'),
                        leading: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx)),
                      ),
                      body: formContent,
                      bottomNavigationBar: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: FilledButton(
                            onPressed: onSave,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A5F),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Lưu thay đổi',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: Row(children: [
                  const Icon(Icons.edit, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('Sửa: ${task.taskCode}',
                          style: const TextStyle(fontSize: 16))),
                ]),
                content: SizedBox(
                    width: MediaQuery.of(ctx).size.width < 600
                        ? MediaQuery.of(ctx).size.width - 32
                        : 520,
                    child: formContent),
                actions: [
                  AppDialogActions(
                    onConfirm: onSave,
                    confirmLabel:
                        saveChild is Text ? saveChild.data ?? 'Lưu' : 'Lưu',
                    isLoading: saveChild is! Text,
                  ),
                ],
              );
            })).then((_) {
      titleCtrl.dispose();
      descCtrl.dispose();
      hoursCtrl.dispose();
      actualCtrl.dispose();
    });
  }

  // --- Đốc thúc công việc ---
  // Gửi nhắc nhở/đốc thúc cho nhân viên thực hiện
  void _showReminderDialog(WorkTask task) {
    final msgCtrl = TextEditingController();
    int urgency = 0;
    bool sending = false;
    String? recipientId = task.assigneeId;
    final isMobile = Responsive.isMobile(context);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
              final formContent = SingleChildScrollView(
                  padding:
                      isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            size: 16, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('${task.taskCode} - ${task.title}',
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis)),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: recipientId,
                      decoration: _dropDecor('Gửi đến'),
                      items: _employees
                          .map((e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.fullName,
                                  style: const TextStyle(fontSize: 13))))
                          .toList(),
                      onChanged: (v) => ss(() => recipientId = v),
                    ),
                    const SizedBox(height: 12),
                    _dialogField(msgCtrl, 'Nội dung đốc thúc *', Icons.message,
                        maxLines: 3),
                    const SizedBox(height: 12),
                    const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Mức độ khẩn:',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF71717A)))),
                    const SizedBox(height: 6),
                    Row(children: [
                      _urgencyChip(
                          ss,
                          'Bình thường',
                          0,
                          urgency,
                          const Color(0xFF1E3A5F),
                          (v) => ss(() => urgency = v)),
                      const SizedBox(width: 8),
                      _urgencyChip(
                          ss,
                          'Gấp',
                          1,
                          urgency,
                          const Color(0xFFF59E0B),
                          (v) => ss(() => urgency = v)),
                      const SizedBox(width: 8),
                      _urgencyChip(
                          ss,
                          'Rất gấp',
                          2,
                          urgency,
                          const Color(0xFFEF4444),
                          (v) => ss(() => urgency = v)),
                    ]),
                  ]));
              final onSend = sending || recipientId == null
                  ? null
                  : () async {
                      if (msgCtrl.text.trim().isEmpty) {
                        _snack(ctx, 'Nhập nội dung đốc thúc', Colors.red);
                        return;
                      }
                      ss(() => sending = true);
                      final r = await _api.sendTaskReminder(task.id,
                          sentToId: recipientId!,
                          message: msgCtrl.text.trim(),
                          urgencyLevel: urgency);
                      ss(() => sending = false);
                      if (!ctx.mounted) return;
                      if (r['isSuccess'] == true) {
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        _snack(context, 'Đã gửi đốc thúc',
                            const Color(0xFFF59E0B));
                        _loadDetail(task.id);
                      } else {
                        _snack(ctx, r['message'] ?? 'Lỗi', Colors.red);
                      }
                    };
              final sendIcon = sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 16);
              if (isMobile) {
                return Dialog(
                  insetPadding: EdgeInsets.zero,
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: Scaffold(
                      appBar: AppBar(
                        title: const Text('Đốc thúc công việc'),
                        leading: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx)),
                      ),
                      body: formContent,
                      bottomNavigationBar: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: FilledButton.icon(
                            onPressed: onSend,
                            icon: sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send, size: 16),
                            label: const Text('Gửi đốc thúc',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF59E0B),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Row(children: [
                  Icon(Icons.notifications_active, color: Color(0xFFF59E0B)),
                  SizedBox(width: 8),
                  Text('Đốc thúc công việc', style: TextStyle(fontSize: 16)),
                ]),
                content: SizedBox(
                    width: MediaQuery.of(ctx).size.width < 600
                        ? MediaQuery.of(ctx).size.width - 32
                        : 420,
                    child: formContent),
                actions: [
                  AppDialogActions(
                    onConfirm: onSend,
                    confirmLabel: 'Gửi đốc thúc',
                    confirmIcon: sendIcon is Icon ? sendIcon.icon : Icons.send,
                    confirmVariant: AppButtonVariant.warning,
                    isLoading: sendIcon is! Icon,
                  ),
                ],
              );
            })).then((_) {
      msgCtrl.dispose();
    });
  }

  Widget _urgencyChip(StateSetter ss, String label, int level, int current,
      Color c, ValueChanged<int> onTap) {
    final active = current == level;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(fontSize: 11, color: active ? Colors.white : c)),
      selected: active,
      selectedColor: c,
      backgroundColor: c.withValues(alpha: 0.1),
      onSelected: (_) => onTap(level),
      visualDensity: VisualDensity.compact,
    );
  }

  // --- Đánh giá công việc ---
  // Chấm điểm chất lượng, tiến độ, tổng thể (1-5 sao)
  void _showEvaluationDialog(WorkTask task) {
    int quality = 4, timeliness = 4, overall = 4;
    final commentCtrl = TextEditingController();
    bool saving = false;
    final isMobile = Responsive.isMobile(context);

    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
              final formContent = SingleChildScrollView(
                  padding:
                      isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        const Icon(Icons.task_alt,
                            size: 16, color: Color(0xFF1E3A5F)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text('${task.taskCode} - ${task.title}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    _starRow('Chất lượng công việc', quality,
                        (v) => ss(() => quality = v)),
                    const SizedBox(height: 8),
                    _starRow('Tiến độ hoàn thành', timeliness,
                        (v) => ss(() => timeliness = v)),
                    const SizedBox(height: 8),
                    _starRow('Đánh giá tổng thể', overall,
                        (v) => ss(() => overall = v)),
                    const SizedBox(height: 12),
                    _dialogField(commentCtrl, 'Nhận xét', Icons.comment,
                        maxLines: 3),
                  ]));
              final onSave = saving
                  ? null
                  : () async {
                      ss(() => saving = true);
                      final r = await _api.createTaskEvaluation(task.id,
                          qualityScore: quality,
                          timelinessScore: timeliness,
                          overallScore: overall,
                          comment: commentCtrl.text.trim().isEmpty
                              ? null
                              : commentCtrl.text.trim());
                      ss(() => saving = false);
                      if (!ctx.mounted) return;
                      if (r['isSuccess'] == true) {
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        _snack(context, 'Đã đánh giá', const Color(0xFF1E3A5F));
                        _loadDetail(task.id);
                      } else {
                        _snack(ctx, r['message'] ?? 'Lỗi', Colors.red);
                      }
                    };
              final saveIcon = saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 16);
              if (isMobile) {
                return Dialog(
                  insetPadding: EdgeInsets.zero,
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: Scaffold(
                      appBar: AppBar(
                        title: const Text('Đánh giá công việc'),
                        leading: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx)),
                      ),
                      body: formContent,
                      bottomNavigationBar: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: FilledButton.icon(
                            onPressed: onSave,
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check, size: 16),
                            label: const Text('Lưu đánh giá',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A5F),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              return AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Row(children: [
                  Icon(Icons.star_rate, color: Color(0xFFF59E0B)),
                  SizedBox(width: 8),
                  Text('Đánh giá công việc', style: TextStyle(fontSize: 16)),
                ]),
                content: SizedBox(
                    width: MediaQuery.of(ctx).size.width < 600
                        ? MediaQuery.of(ctx).size.width - 32
                        : 420,
                    child: formContent),
                actions: [
                  AppDialogActions(
                    onConfirm: onSave,
                    confirmLabel: 'Lưu đánh giá',
                    confirmIcon: saveIcon is Icon ? saveIcon.icon : Icons.save,
                    isLoading: saveIcon is! Icon,
                  ),
                ],
              );
            })).then((_) {
      commentCtrl.dispose();
    });
  }

  Widget _starRow(String label, int value, ValueChanged<int> onChanged) {
    return Row(children: [
      SizedBox(
          width: 150,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)))),
      const Spacer(),
      ...List.generate(
          5,
          (i) => GestureDetector(
                onTap: () => onChanged(i + 1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                      i < value
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 28,
                      color: const Color(0xFFF59E0B)),
                ),
              )),
    ]);
  }

  // --- Dialog helpers ---
  Widget _dialogField(TextEditingController ctrl, String label, IconData icon,
      {int maxLines = 1, TextInputType? keyboardType}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        prefixIcon: Icon(icon, size: 18),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
      ),
    );
  }

  InputDecoration _dropDecor(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
      );

  Widget _datePickerField(
      String label, DateTime? value, ValueChanged<DateTime> onPicked) {
    return InkWell(
      onTap: () async {
        final d = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2030));
        if (d != null) {
          if (!mounted) return;
          final t = await showTimePicker(
              context: context,
              initialTime: value != null
                  ? TimeOfDay(hour: value.hour, minute: value.minute)
                  : TimeOfDay.now());
          final picked =
              DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
          onPicked(picked);
        }
      },
      child: InputDecorator(
        decoration: _dropDecor(label),
        child: Text(
            value != null
                ? DateFormat('dd/MM/yyyy HH:mm').format(value)
                : 'Chọn ngày giờ',
            style: TextStyle(
                fontSize: 13,
                color: value != null
                    ? const Color(0xFF18181B)
                    : const Color(0xFFA1A1AA))),
      ),
    );
  }

  // ======================== ACTIONS ========================

  Future<void> _updateStatus(String taskId, WorkTaskStatus status) async {
    final r = await _api.updateTaskStatus(taskId, status.index);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _snack(context, 'Đã cập nhật trạng thái', const Color(0xFF1E3A5F));
      _loadTasks();
      _loadKanban();
      _loadStats();
      if (_detailTask?.id == taskId) _loadDetail(taskId);
    } else {
      _snack(context, r['message'] ?? 'Lỗi', Colors.red);
    }
  }

  Future<void> _updateProgress(String taskId, int progress) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ProgressUpdatePage(
          initialProgress: progress,
          api: _api,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final r = await _api.updateTaskProgress(taskId, result);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _loadTasks();
      _loadStats();
      if (_detailTask?.id == taskId) _loadDetail(taskId);
      _snack(context, 'Đã cập nhật tiến độ ${result['progress']}%',
          const Color(0xFF1E3A5F));
    } else {
      _snack(context, r['message'] ?? 'Lỗi cập nhật tiến độ', Colors.red);
    }
  }

  Future<void> _addComment() async {
    final content = _commentCtrl.text.trim();
    if (content.isEmpty || _detailTask == null) return;
    final data = <String, dynamic>{
      'content': content,
      'commentType': 0,
    };
    final r = await _api.addTaskComment(_detailTask!.id, data);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _commentCtrl.clear();
      _loadDetail(_detailTask!.id);
      _snack(context, 'Đã thêm bình luận', const Color(0xFF1E3A5F));
    } else {
      _snack(context, r['message'] ?? 'Lỗi', Colors.red);
    }
  }

  Future<void> _batchStatus(WorkTaskStatus status) async {
    final r = await _api.batchUpdateTaskStatus(_sel.toList(), status.index);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      setState(() {
        _sel.clear();
        _selectMode = false;
      });
      _loadTasks();
      _loadStats();
      _snack(context, 'Đã cập nhật ${r['data']} công việc',
          const Color(0xFF1E3A5F));
    } else {
      _snack(context, r['message'] ?? 'Lỗi', Colors.red);
    }
  }

  void _showBatchAssign() {
    final isMobile = Responsive.isMobile(context);
    final listContent = ListView(
        shrinkWrap: !isMobile,
        children: _employees
            .map((e) => ListTile(
                  title: Text(e.fullName),
                  subtitle: Text(e.employeeCode),
                  leading: CircleAvatar(
                      backgroundColor: const Color(0xFF1E3A5F),
                      child: Text(e.firstName.isNotEmpty ? e.firstName[0] : '?',
                          style: const TextStyle(color: Colors.white))),
                  onTap: () async {
                    Navigator.pop(context);
                    final r = await _api.batchAssignTasks(_sel.toList(), e.id);
                    if (mounted) {
                      if (r['isSuccess'] == true) {
                        setState(() {
                          _sel.clear();
                          _selectMode = false;
                        });
                        _loadTasks();
                        _snack(
                            context, 'Đã giao việc', const Color(0xFF6366F1));
                      }
                    }
                  },
                ))
            .toList());
    showDialog(
        context: context,
        builder: (ctx) {
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Giao việc hàng loạt'),
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: listContent,
                ),
              ),
            );
          }
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Giao việc hàng loạt'),
            content: SizedBox(
                width: MediaQuery.of(ctx).size.width < 600
                    ? MediaQuery.of(ctx).size.width - 64
                    : 300,
                child: listContent),
            actions: [
              AppButton.cancel(onPressed: () => Navigator.pop(ctx)),
            ],
          );
        });
  }

  void _confirmBatchDelete() {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Text('Xác nhận xóa'),
              content: Text(
                  'Bạn có chắc muốn xóa ${_sel.length} công việc đã chọn?'),
              actions: [
                AppDialogActions.delete(
                  onConfirm: () async {
                    Navigator.pop(ctx);
                    final r = await _api.batchDeleteTasks(_sel.toList());
                    if (mounted && r['isSuccess'] == true) {
                      setState(() {
                        _sel.clear();
                        _selectMode = false;
                      });
                      _loadTasks();
                      _loadStats();
                      _snack(context, 'Đã xóa', const Color(0xFF1E3A5F));
                    }
                  },
                ),
              ],
            ));
  }

  // ======================== HELPERS ========================
  void _snack(BuildContext ctx, String msg, Color c) {
    if (c == Colors.red || c == const Color(0xFFEF4444)) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: msg);
    } else if (c == const Color(0xFFF59E0B)) {
      NotificationOverlayManager()
          .showWarning(title: 'Thông báo', message: msg);
    } else if (c == const Color(0xFF6366F1)) {
      NotificationOverlayManager().showInfo(title: 'Thông báo', message: msg);
    } else {
      NotificationOverlayManager()
          .showSuccess(title: 'Thành công', message: msg);
    }
  }

  Widget _statusBadge(WorkTaskStatus s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: _statusColor(s).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _statusColor(s).withValues(alpha: 0.3))),
        child: Text(getTaskStatusLabel(s),
            style: TextStyle(
                color: _statusColor(s),
                fontSize: 10,
                fontWeight: FontWeight.w600)),
      );

  Widget _priorityBadge(TaskPriority p) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
          color: _priorityColor(p).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4)),
      child: Icon(Icons.flag, size: 14, color: _priorityColor(p)),
    );
  }

  Color _statusColor(WorkTaskStatus s) => switch (s) {
        WorkTaskStatus.todo => const Color(0xFFA1A1AA),
        WorkTaskStatus.inProgress => const Color(0xFF1E3A5F),
        WorkTaskStatus.inReview => const Color(0xFF0F2340),
        WorkTaskStatus.completed => const Color(0xFF1E3A5F),
        WorkTaskStatus.cancelled => const Color(0xFFEF4444),
        WorkTaskStatus.onHold => const Color(0xFFF59E0B),
      };

  IconData _statusIcon(WorkTaskStatus s) => switch (s) {
        WorkTaskStatus.todo => Icons.radio_button_unchecked,
        WorkTaskStatus.inProgress => Icons.play_circle_rounded,
        WorkTaskStatus.inReview => Icons.visibility,
        WorkTaskStatus.completed => Icons.check_circle_rounded,
        WorkTaskStatus.cancelled => Icons.cancel_rounded,
        WorkTaskStatus.onHold => Icons.pause_circle_rounded,
      };

  Color _priorityColor(TaskPriority p) => switch (p) {
        TaskPriority.low => const Color(0xFFA1A1AA),
        TaskPriority.medium => const Color(0xFF1E3A5F),
        TaskPriority.high => const Color(0xFFF59E0B),
        TaskPriority.urgent => const Color(0xFFEF4444),
      };

  Color _progressColor(int p) {
    if (p >= 100) return const Color(0xFF1E3A5F);
    if (p >= 70) return const Color(0xFF1E3A5F);
    if (p >= 30) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }

  IconData _historyIcon(String type) => switch (type) {
        'StatusChanged' => Icons.swap_horiz,
        'ProgressUpdated' => Icons.trending_up,
        'AssigneeChanged' => Icons.person,
        'TitleChanged' => Icons.edit,
        'CommentAdded' => Icons.comment,
        'ReminderSent' => Icons.notifications_active,
        'Evaluated' => Icons.star,
        _ => Icons.history,
      };

  IconData _taskTypeIcon(TaskType t) => switch (t) {
        TaskType.task => Icons.task_alt,
        TaskType.bug => Icons.bug_report,
        TaskType.feature => Icons.auto_awesome,
        TaskType.improvement => Icons.trending_up,
        TaskType.meeting => Icons.groups,
        TaskType.other => Icons.more_horiz,
      };

  Color _taskTypeColor(TaskType t) => switch (t) {
        TaskType.task => const Color(0xFF1E3A5F),
        TaskType.bug => const Color(0xFFEF4444),
        TaskType.feature => const Color(0xFF8B5CF6),
        TaskType.improvement => const Color(0xFF10B981),
        TaskType.meeting => const Color(0xFFF59E0B),
        TaskType.other => const Color(0xFFA1A1AA),
      };

  void _confirmDeleteTask(WorkTask task) {
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: const Row(children: [
                Icon(Icons.warning_amber, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Text('Xác nhận xóa', style: TextStyle(fontSize: 16)),
              ]),
              content: Text(
                  'Bạn có chắc muốn xóa công việc "${task.title}" (${task.taskCode})?'),
              actions: [
                AppDialogActions.delete(
                  onConfirm: () async {
                    Navigator.pop(ctx);
                    final r = await _api.deleteTask(task.id);
                    if (mounted && r['isSuccess'] == true) {
                      setState(() => _detailTask = null);
                      _loadTasks();
                      _loadStats();
                      _snack(
                          context, 'Đã xóa công việc', const Color(0xFF1E3A5F));
                    } else if (mounted) {
                      _snack(context, r['message'] ?? 'Lỗi xóa', Colors.red);
                    }
                  },
                ),
              ],
            ));
  }

  String _formatDuration(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    final parts = <String>[];
    if (days > 0) parts.add('$days ngày');
    if (hours > 0) parts.add('$hours giờ');
    if (mins > 0) parts.add('$mins phút');
    return parts.isEmpty ? '0 phút' : parts.join(' ');
  }
}

/// Multi-assignee picker as a full-screen page (avoids nested dialog gray screen)
class _MultiAssigneePickerPage extends StatefulWidget {
  final List<dynamic> employees;
  final List<String> selected;
  const _MultiAssigneePickerPage(
      {required this.employees, required this.selected});
  @override
  State<_MultiAssigneePickerPage> createState() =>
      _MultiAssigneePickerPageState();
}

class _MultiAssigneePickerPageState extends State<_MultiAssigneePickerPage> {
  late List<String> _selected;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.employees.where((e) {
      final name = (e.fullName as String).toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();

    final body = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Tìm nhân viên...',
              prefixIcon: const Icon(Icons.search, size: 18),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: _selected.map((id) {
                final emp = widget.employees
                    .cast<dynamic>()
                    .where((e) => e.id == id)
                    .firstOrNull;
                final name = emp?.fullName ?? 'Unknown';
                return Chip(
                  label: Text(name, style: const TextStyle(fontSize: 11)),
                  deleteIcon: const Icon(Icons.close, size: 12),
                  onDeleted: () => setState(() => _selected.remove(id)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: const Color(0xFFEFF6FF),
                );
              }).toList(),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final emp = filtered[i];
              final isSelected = _selected.contains(emp.id);
              return CheckboxListTile(
                value: isSelected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selected.add(emp.id);
                    } else {
                      _selected.remove(emp.id);
                    }
                  });
                },
                title: Text(emp.fullName, style: const TextStyle(fontSize: 13)),
                subtitle: emp.department != null
                    ? Text(emp.department!,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B)))
                    : null,
                secondary: CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF1E3A5F),
                  child: Text(
                    emp.fullName.isNotEmpty
                        ? emp.fullName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                dense: true,
                controlAffinity: ListTileControlAffinity.trailing,
              );
            },
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Text('Chọn người thực hiện', style: TextStyle(fontSize: 16)),
          const Spacer(),
          Text('${_selected.length} đã chọn',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        ]),
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
      ),
      body: body,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _selected),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Xác nhận (${_selected.length})',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

/// Full-screen page for progress update with image upload
class _ProgressUpdatePage extends StatefulWidget {
  final int initialProgress;
  final ApiService api;
  const _ProgressUpdatePage({required this.initialProgress, required this.api});
  @override
  State<_ProgressUpdatePage> createState() => _ProgressUpdatePageState();
}

class _ProgressUpdatePageState extends State<_ProgressUpdatePage> {
  late double _sliderVal;
  final _notesCtrl = TextEditingController();
  final _linkUrlsCtrl = TextEditingController();
  final List<XFile> _pickedImages = [];
  final List<Uint8List> _imageBytes = [];
  bool _saving = false;
  String _statusText = '';

  @override
  void initState() {
    super.initState();
    _sliderVal = widget.initialProgress.toDouble().clamp(0, 100);
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _linkUrlsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      // Try pickMultiImage first, fall back to single pick if it fails
      List<XFile> images = [];
      try {
        images = await picker.pickMultiImage(imageQuality: 80, maxWidth: 1920);
      } catch (_) {
        // Fallback: pick single image from gallery
        final single = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 80, maxWidth: 1920);
        if (single != null) images = [single];
      }
      for (final img in images) {
        final bytes = await img.readAsBytes();
        setState(() {
          _pickedImages.add(img);
          _imageBytes.add(bytes);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Lỗi chọn ảnh: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
          source: ImageSource.camera, imageQuality: 80, maxWidth: 1920);
      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _pickedImages.add(photo);
          _imageBytes.add(bytes);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Lỗi chụp ảnh: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _pickedImages.removeAt(index);
      _imageBytes.removeAt(index);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _statusText = 'Đang xử lý...';
    });

    // Upload images first
    final List<String> uploadedUrls = [];
    if (_pickedImages.isNotEmpty) {
      for (int i = 0; i < _pickedImages.length; i++) {
        setState(() =>
            _statusText = 'Đang tải ảnh ${i + 1}/${_pickedImages.length}...');
        try {
          final r = await widget.api.uploadFile(
              _imageBytes[i], _pickedImages[i].name,
              folder: 'tasks');
          if (r['isSuccess'] == true && r['data'] != null) {
            final d = r['data'];
            final url =
                d is String ? d : (d['fileUrl'] ?? d['url'] ?? d['filePath']);
            if (url != null) uploadedUrls.add(url.toString());
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(
                        'Lỗi tải ảnh ${i + 1}: ${r['message'] ?? 'Unknown'}'),
                    backgroundColor: Colors.orange),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Lỗi tải ảnh ${i + 1}: $e'),
                  backgroundColor: Colors.red),
            );
          }
        }
      }
    }

    // Build result data
    final linkLines = _linkUrlsCtrl.text
        .trim()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    final data = <String, dynamic>{
      'progress': _sliderVal.toInt(),
      if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
      if (uploadedUrls.isNotEmpty) 'imageUrls': json.encode(uploadedUrls),
      if (linkLines.isNotEmpty) 'linkUrls': json.encode(linkLines),
    };

    if (mounted) {
      setState(() => _saving = false);
      Navigator.pop(context, data);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Cập nhật tiến độ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Progress slider
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8)
                ],
              ),
              child: Column(
                children: [
                  Row(children: [
                    const Icon(Icons.trending_up,
                        size: 20, color: Color(0xFF1E3A5F)),
                    const SizedBox(width: 8),
                    const Text('Tiến độ: ',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    Text('${_sliderVal.toInt()}%',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A5F))),
                  ]),
                  const SizedBox(height: 8),
                  Slider(
                    value: _sliderVal,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '${_sliderVal.toInt()}%',
                    activeColor: const Color(0xFF1E3A5F),
                    onChanged: (v) => setState(() => _sliderVal = v),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [0, 25, 50, 75, 100]
                        .map((v) => ActionChip(
                              label: Text('$v%',
                                  style: const TextStyle(fontSize: 12)),
                              backgroundColor: _sliderVal.toInt() == v
                                  ? const Color(0xFF1E3A5F)
                                  : null,
                              labelStyle: TextStyle(
                                  color: _sliderVal.toInt() == v
                                      ? Colors.white
                                      : null),
                              onPressed: () =>
                                  setState(() => _sliderVal = v.toDouble()),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Notes
            TextField(
              controller: _notesCtrl,
              maxLines: 4,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Ghi chú tiến độ',
                hintText: 'Mô tả công việc đã hoàn thành...',
                prefixIcon: const Padding(
                    padding: EdgeInsets.only(bottom: 50),
                    child: Icon(Icons.notes, size: 20)),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            // Image section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8)
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.photo_library,
                        size: 18, color: Color(0xFF1E3A5F)),
                    const SizedBox(width: 8),
                    const Text('Hình ảnh',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E3A5F))),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickImages,
                      icon: const Icon(Icons.photo_library, size: 16),
                      label: const Text('Thư viện',
                          style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 34),
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: const BorderSide(
                            color: Color(0xFF1E3A5F), width: 0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _takePhoto,
                      icon: const Icon(Icons.camera_alt, size: 16),
                      label: const Text('Chụp', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: const Size(0, 34),
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: const BorderSide(
                            color: Color(0xFF1E3A5F), width: 0.5),
                      ),
                    ),
                  ]),
                  if (_imageBytes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _imageBytes.asMap().entries.map((entry) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(entry.value,
                                  width: 80, height: 80, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: GestureDetector(
                                onTap: () => _removeImage(entry.key),
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Column(children: [
                          Icon(Icons.add_photo_alternate,
                              size: 40, color: Colors.grey[300]),
                          const SizedBox(height: 4),
                          Text('Chưa có hình ảnh',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[400])),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Link URLs
            TextField(
              controller: _linkUrlsCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Link tài liệu (mỗi dòng 1 link)',
                hintText: 'https://docs.google.com/...',
                prefixIcon: const Icon(Icons.link, size: 20),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text(_statusText,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF1E3A5F))),
                  ]),
                ),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Hủy'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: Text(_saving ? 'Đang gửi...' : 'Cập nhật tiến độ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A5F),
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
