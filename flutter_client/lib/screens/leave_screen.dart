import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/responsive_helper.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_button.dart';
import '../widgets/notification_overlay.dart';

class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  TabController? _tabController;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  Timer? _refreshTimer;

  List<dynamic> _myLeaves = [];
  List<dynamic> _allLeaves = [];
  List<dynamic> _pendingLeaves = [];
  List<dynamic> _shifts = [];
  List<dynamic> _employees = [];

  bool _isLoading = true;
  bool _isManager = false;
  bool _initialized = false;
  String? _currentUserId;

  // Filters
  int? _filterLeaveType;
  int? _filterStatus;
  String? _filterEmployeeId;
  String _filterTimePreset = 'all';
  DateTimeRange? _filterDateRange;
  int _currentPage = 1;

  // Sorting
  String _sortColumn = 'createdAt';
  bool _sortAscending = false;
  int _itemsPerPage = 50;
  final List<int> _pageSizeOptions = [25, 50, 100, 200];

  // Mobile UI state
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final role = authProvider.user?.role ?? '';
      _isManager = role == 'Admin' ||
          role == 'Manager' ||
          role == 'SuperAdmin' ||
          role == 'Agent' ||
          role == 'DepartmentHead';
      _currentUserId = authProvider.user?.id;
      _tabController = TabController(
        length: _isManager ? 3 : 1,
        vsync: this,
      );
      // Listen for leave-related SignalR notifications to auto-refresh
      _notificationSub = SignalRService().onNewNotification.listen((data) {
        final category = (data['categoryCode'] ?? data['category'] ?? '').toString().toLowerCase();
        if (category.contains('leave') || category.contains('approval')) {
          _loadData();
        }
      });
      // Periodic refresh every 30 seconds as fallback
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) _loadData();
      });
      _loadData();
    }
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    _refreshTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      try {
        final shiftsResult = await _apiService.getShifts();
        _shifts = shiftsResult;
      } catch (e) {
        _shifts = [];
      }
      try {
        _employees = await _apiService.getEmployees(pageSize: 200);
      } catch (e) {
        _employees = [];
      }
      try {
        final myResult = await _apiService.getMyLeaves();
        if (myResult['isSuccess'] == true && myResult['data'] != null) {
          final data = myResult['data'];
          _myLeaves = data is List ? data : [];
        }
      } catch (e) {
        _myLeaves = [];
      }
      if (_isManager) {
        try {
          final allResult = await _apiService.getAllLeaves(pageSize: 200);
          if (allResult['isSuccess'] == true && allResult['data'] != null) {
            final data = allResult['data'];
            if (data is List) {
              _allLeaves = data;
            } else if (data is Map) {
              _allLeaves = (data['items'] as List?) ?? [];
            } else {
              _allLeaves = [];
            }
          }
        } catch (e) {
          _allLeaves = [];
        }
        try {
          final pendingResult = await _apiService.getPendingLeaves(pageSize: 200);
          if (pendingResult['isSuccess'] == true && pendingResult['data'] != null) {
            final data = pendingResult['data'];
            if (data is List) {
              _pendingLeaves = data;
            } else if (data is Map) {
              _pendingLeaves = (data['items'] as List?) ?? [];
            } else {
              _pendingLeaves = [];
            }
          }
        } catch (e) {
          _pendingLeaves = [];
        }
      }
    } catch (e) {
      debugPrint('Error loading leave data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static int _normalizeStatus(dynamic status) {
    if (status is int) return status;
    final s = status?.toString().toLowerCase() ?? '';
    switch (s) {
      case 'pending': case '0': return 0;
      case 'approved': case '1': return 1;
      case 'rejected': case '2': return 2;
      case 'cancelled': case 'canceled': case '3': return 3;
      default: return -1;
    }
  }

  static int _normalizeLeaveType(dynamic type) {
    if (type is int) return type;
    final s = type?.toString().toLowerCase() ?? '';
    switch (s) {
      case 'annualleave': case 'annual': case '0': return 0;
      case 'holiday': case '1': return 1;
      case 'personalpaid': case '2': return 2;
      case 'personalunpaid': case '3': return 3;
      case 'sickleave': case 'sick': case '4': return 4;
      case 'maternityleave': case 'maternity': case '5': return 5;
      case 'compensatoryleave': case 'compensatory': case '6': return 6;
      case 'longtermleave': case 'longterm': case '7': return 7;
      default: return -1;
    }
  }

  // ignore: unused_element
  String _getShiftName(String shiftId) {
    for (final shift in _shifts) {
      if (shift['id']?.toString() == shiftId) {
        return shift['name'] ?? 'N/A';
      }
    }
    return 'Ca #${shiftId.length > 6 ? shiftId.substring(0, 6) : shiftId}';
  }

  List<dynamic> _applyFilters(List<dynamic> leaves) {
    return leaves.where((leave) {
      if (_filterLeaveType != null && _normalizeLeaveType(leave['type']) != _filterLeaveType) return false;
      if (_filterStatus != null && _normalizeStatus(leave['status']) != _filterStatus) return false;
      if (_filterEmployeeId != null && _filterEmployeeId!.isNotEmpty) {
        final empName = (leave['employeeName'] ?? '').toString().toLowerCase();
        if (!empName.contains(_filterEmployeeId!.toLowerCase())) return false;
      }
      if (_filterDateRange != null) {
        final start = DateTime.tryParse(leave['startDate']?.toString() ?? '');
        final end = DateTime.tryParse(leave['endDate']?.toString() ?? '');
        if (start == null || end == null) return false;
        if (end.isBefore(_filterDateRange!.start) || start.isAfter(_filterDateRange!.end)) return false;
      }
      return true;
    }).toList();
  }

  // ═══════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildHeader(theme),
          if (_tabController != null) _buildTabBar(theme),
          Expanded(
            child: _isLoading || _tabController == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: theme.primaryColor),
                        const SizedBox(height: 16),
                        Text('Đang tải...', style: TextStyle(color: Colors.grey[500])),
                      ],
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(
                      Responsive.isMobile(context) ? 10 : 16,
                      Responsive.isMobile(context) ? 10 : 16,
                      Responsive.isMobile(context) ? 10 : 16,
                      8,
                    ),
                    child: Column(
                      children: [
                        if (Responsive.isMobile(context)) ...[
                          InkWell(
                            onTap: () => setState(() => _showMobileSummary = !_showMobileSummary),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.analytics_outlined, size: 16, color: Colors.blue.shade700),
                                  const SizedBox(width: 6),
                                  Text('Tổng quan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue.shade700)),
                                  const Spacer(),
                                  Icon(_showMobileSummary ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.blue.shade700),
                                ],
                              ),
                            ),
                          ),
                          if (_showMobileSummary) ...[
                            const SizedBox(height: 8),
                            _buildStatsRow(theme),
                          ],
                        ] else ...[
                          _buildStatsRow(theme),
                        ],
                        const SizedBox(height: 12),
                        if (!Responsive.isMobile(context) || _showMobileFilters) ...[
                          _buildFilterBar(theme),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              RefreshIndicator(onRefresh: _loadData, child: _buildLeaveList(_applyFilters(_myLeaves), isMyLeaves: true)),
                              if (_isManager) ...[
                                RefreshIndicator(onRefresh: _loadData, child: _buildLeaveList(_applyFilters(_pendingLeaves), showApprovalActions: true)),
                                RefreshIndicator(onRefresh: _loadData, child: _buildLeaveList(_applyFilters(_allLeaves), isAllTab: true)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildHeader(ThemeData theme) {
    final primary = theme.primaryColor;
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18, isMobile ? 14 : 24, isMobile ? 12 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 8 : 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.event_busy_rounded, size: isMobile ? 18 : 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l10n.leaveManagement,
                  style: TextStyle(fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (!isMobile)
                  Text(
                    _l10n.leaveSubtitle,
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isMobile)
            GestureDetector(
              onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _showMobileFilters ? 0.25 : 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18, color: Colors.white),
                    if (_filterLeaveType != null || _filterStatus != null || _filterEmployeeId != null || _filterTimePreset != 'all')
                      Positioned(right: 0, top: 0, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                  ],
                ),
              ),
            ),
          Material(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => _showLeaveFormDialog(),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: isMobile ? 8 : 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: isMobile ? 18 : 20, color: Colors.white),
                    if (!isMobile) ...[const SizedBox(width: 6), Text(_l10n.createRequest, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // STATS ROW
  // ═══════════════════════════════════════════════════
  Widget _buildStatsRow(ThemeData theme) {
    final source = _isManager ? _allLeaves : _myLeaves;
    final pending = source.where((l) => _normalizeStatus(l['status']) == 0).length;
    final approved = source.where((l) => _normalizeStatus(l['status']) == 1).length;
    final rejected = source.where((l) => _normalizeStatus(l['status']) == 2).length;
    final annual = source.where((l) => _normalizeLeaveType(l['type']) == 0).length;
    final holiday = source.where((l) => _normalizeLeaveType(l['type']) == 1).length;
    final personalPaid = source.where((l) => _normalizeLeaveType(l['type']) == 2).length;

    final cards = [
      _buildStatCard(_l10n.pending, '$pending', Icons.hourglass_bottom_rounded, Colors.orange),
      _buildStatCard(_l10n.approved, '$approved', Icons.check_circle_rounded, Colors.green),
      _buildStatCard(_l10n.rejected, '$rejected', Icons.cancel_rounded, Colors.red),
      _buildStatCard('Phép năm', '$annual', Icons.beach_access_rounded, Colors.teal),
      _buildStatCard('Lễ tết', '$holiday', Icons.celebration_rounded, const Color(0xFFF59E0B)),
      _buildStatCard('Có lương', '$personalPaid', Icons.paid_rounded, Colors.blue),
    ];

    return Row(
      children: cards.expand((c) => [Expanded(child: c), const SizedBox(width: 8)]).toList()..removeLast(),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
    );
  }

  // ═══════════════════════════════════════════════════
  // TAB BAR
  // ═══════════════════════════════════════════════════
  Widget _buildTabBar(ThemeData theme) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: theme.primaryColor,
        unselectedLabelColor: Colors.grey,
        indicatorColor: theme.primaryColor,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: [
          Tab(icon: const Icon(Icons.person_outline_rounded, size: 20), text: _l10n.myRequests),
          if (_isManager) ...[
            Tab(
              icon: Badge(
                label: Text('${_pendingLeaves.length}', style: const TextStyle(fontSize: 10)),
                isLabelVisible: _pendingLeaves.isNotEmpty,
                backgroundColor: Colors.red,
                child: const Icon(Icons.pending_actions_rounded, size: 20),
              ),
              text: _l10n.pending,
            ),
            Tab(icon: const Icon(Icons.list_alt_rounded, size: 20), text: _l10n.all),
          ],
        ],
      ),
    );
  }

  void _applyTimePreset(String preset) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTimeRange? range;

    switch (preset) {
      case 'today':
        range = DateTimeRange(start: today, end: DateTime(today.year, today.month, today.day, 23, 59, 59));
        break;
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        range = DateTimeRange(start: yesterday, end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59));
        break;
      case 'this_week':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        range = DateTimeRange(start: weekStart, end: DateTime(today.year, today.month, today.day, 23, 59, 59));
        break;
      case 'last_week':
        final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
        final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
        final lastWeekEnd = thisWeekStart.subtract(const Duration(days: 1));
        range = DateTimeRange(start: lastWeekStart, end: DateTime(lastWeekEnd.year, lastWeekEnd.month, lastWeekEnd.day, 23, 59, 59));
        break;
      case 'this_month':
        final monthStart = DateTime(today.year, today.month, 1);
        range = DateTimeRange(start: monthStart, end: DateTime(today.year, today.month, today.day, 23, 59, 59));
        break;
      case 'last_month':
        final lastMonthStart = DateTime(today.year, today.month - 1, 1);
        final lastMonthEnd = DateTime(today.year, today.month, 0);
        range = DateTimeRange(start: lastMonthStart, end: DateTime(lastMonthEnd.year, lastMonthEnd.month, lastMonthEnd.day, 23, 59, 59));
        break;
      case 'custom':
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2024),
          lastDate: DateTime(2030),
          initialDateRange: _filterDateRange,
          locale: const Locale('vi'),
        );
        if (picked != null) {
          range = DateTimeRange(
            start: picked.start,
            end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
          );
        } else {
          return;
        }
        break;
      default:
        range = null;
    }
    setState(() {
      _filterTimePreset = preset;
      _filterDateRange = range;
      _currentPage = 1;
    });
  }

  // ═══════════════════════════════════════════════════
  // FILTER BAR
  // ═══════════════════════════════════════════════════
  Widget _buildFilterBar(ThemeData theme) {
    final hasFilters = _filterLeaveType != null ||
        _filterStatus != null ||
        (_filterEmployeeId != null && _filterEmployeeId!.isNotEmpty) ||
        _filterDateRange != null;
    final isMobile = Responsive.isMobile(context);

    final typeDropdown = _buildFilterDropdown<int?>(
      value: _filterLeaveType,
      width: isMobile ? 120 : 140,
      icon: Icons.category_rounded,
      items: [
        DropdownMenuItem(value: null, child: Text(_l10n.allTypes)),
        const DropdownMenuItem(value: 0, child: Text('Phép năm')),
        const DropdownMenuItem(value: 1, child: Text('Lễ tết')),
        const DropdownMenuItem(value: 2, child: Text('VR có lương')),
        const DropdownMenuItem(value: 3, child: Text('VR không lương')),
        const DropdownMenuItem(value: 4, child: Text('Ốm đau')),
        const DropdownMenuItem(value: 5, child: Text('Thai sản')),
        const DropdownMenuItem(value: 6, child: Text('Nghỉ bù')),
        const DropdownMenuItem(value: 7, child: Text('Nghỉ dài hạn')),
      ],
      onChanged: (v) => setState(() { _filterLeaveType = v; _currentPage = 1; }),
    );
    final statusDropdown = _buildFilterDropdown<int?>(
      value: _filterStatus,
      width: isMobile ? 110 : 130,
      icon: Icons.flag_rounded,
      items: [
        DropdownMenuItem(value: null, child: Text(_l10n.allStatus)),
        DropdownMenuItem(value: 0, child: Text(_l10n.pending)),
        DropdownMenuItem(value: 1, child: Text(_l10n.approved)),
        DropdownMenuItem(value: 2, child: Text(_l10n.rejected)),
        DropdownMenuItem(value: 3, child: Text(_l10n.cancelled)),
      ],
      onChanged: (v) => setState(() { _filterStatus = v; _currentPage = 1; }),
    );
    final timeDropdown = _buildFilterDropdown<String>(
      value: _filterTimePreset,
      width: isMobile ? 120 : 130,
      icon: Icons.date_range_rounded,
      items: [
        const DropdownMenuItem(value: 'all', child: Text('Toàn bộ')),
        DropdownMenuItem(value: 'today', child: Text(_l10n.today)),
        DropdownMenuItem(value: 'yesterday', child: Text(_l10n.yesterday)),
        DropdownMenuItem(value: 'this_week', child: Text(_l10n.thisWeek)),
        DropdownMenuItem(value: 'last_week', child: Text(_l10n.lastWeek)),
        DropdownMenuItem(value: 'this_month', child: Text(_l10n.thisMonth)),
        DropdownMenuItem(value: 'last_month', child: Text(_l10n.lastMonth)),
        DropdownMenuItem(value: 'custom', child: Text(_l10n.custom)),
      ],
      onChanged: (v) { if (v != null) _applyTimePreset(v); },
    );
    final countChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics_outlined, size: 14, color: theme.primaryColor),
          const SizedBox(width: 6),
          Text(
            '${(_isManager ? _allLeaves : _myLeaves).length} đơn',
            style: TextStyle(color: theme.primaryColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    final clearBtn = hasFilters ? Material(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => setState(() {
          _filterLeaveType = null;
          _filterStatus = null;
          _filterEmployeeId = null;
          _filterTimePreset = 'all';
          _filterDateRange = null;
          _currentPage = 1;
        }),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_alt_off, size: 16, color: Colors.red.shade700),
              const SizedBox(width: 4),
              Text(_l10n.clearFilter, style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    ) : const SizedBox.shrink();

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [typeDropdown, statusDropdown, timeDropdown]),
            if (_isManager || hasFilters) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_isManager) Expanded(
                    child: SizedBox(
                      height: 36,
                      child: Autocomplete<Map<String, dynamic>>(
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) return _employees.take(20).map((e) => Map<String, dynamic>.from(e));
                          final query = textEditingValue.text.toLowerCase();
                          return _employees.where((emp) {
                            final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.toLowerCase();
                            final code = (emp['employeeCode'] ?? '').toString().toLowerCase();
                            return name.contains(query) || code.contains(query);
                          }).take(20).map((e) => Map<String, dynamic>.from(e));
                        },
                        displayStringForOption: (emp) => '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim(),
                        onSelected: (emp) {
                          final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                          setState(() { _filterEmployeeId = name; _currentPage = 1; });
                        },
                        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: _l10n.searchEmployee,
                              hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                              prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFFFAFAFA),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: theme.primaryColor, width: 1.5)),
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (v) => setState(() { _filterEmployeeId = v; _currentPage = 1; }),
                          );
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 200, maxWidth: 250),
                                child: ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  itemBuilder: (context, index) {
                                    final emp = options.elementAt(index);
                                    final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                                    return ListTile(
                                      dense: true,
                                      title: Text(name, style: const TextStyle(fontSize: 13)),
                                      onTap: () => onSelected(emp),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_isManager && hasFilters) const SizedBox(width: 8),
                  countChip,
                  if (hasFilters) ...[const SizedBox(width: 8), clearBtn],
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Row(children: [countChip]),
            ],
          ],
        ),
      );
    }

    // ── Desktop layout ──
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          typeDropdown,
          statusDropdown,
          timeDropdown,
          if (_isManager)
            SizedBox(
              width: 200,
              height: 36,
              child: Autocomplete<Map<String, dynamic>>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return _employees.take(20).map((e) => Map<String, dynamic>.from(e));
                  }
                  final query = textEditingValue.text.toLowerCase();
                  return _employees.where((emp) {
                    final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.toLowerCase();
                    final code = (emp['employeeCode'] ?? '').toString().toLowerCase();
                    return name.contains(query) || code.contains(query);
                  }).take(20).map((e) => Map<String, dynamic>.from(e));
                },
                displayStringForOption: (emp) => '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim(),
                onSelected: (emp) {
                  final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                  setState(() { _filterEmployeeId = name; _currentPage = 1; });
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: _l10n.searchEmployee,
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: theme.primaryColor, width: 1.5),
                      ),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                controller.clear();
                                setState(() { _filterEmployeeId = null; _currentPage = 1; });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          : null,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setState(() { _filterEmployeeId = v; _currentPage = 1; }),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 250, maxWidth: 280),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final emp = options.elementAt(index);
                            final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                            final code = emp['employeeCode'] ?? '';
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.teal.shade50,
                                child: Text(name.isNotEmpty ? name[0] : '?', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                              ),
                              title: Text(name, style: const TextStyle(fontSize: 13)),
                              subtitle: Text(code, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              onTap: () => onSelected(emp),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          countChip,
          if (hasFilters) clearBtn,
        ],
      ),
    );
  }

  Widget _buildFilterDropdown<T>({
    required T value,
    required double width,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey[500]),
          style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
          dropdownColor: Colors.white,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item.value,
                    child: Row(
                      children: [
                        Icon(icon, size: 15, color: Theme.of(context).primaryColor.withValues(alpha: 0.7)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DefaultTextStyle(
                            style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
                            overflow: TextOverflow.ellipsis,
                            child: item.child,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          selectedItemBuilder: (context) => items
              .map((item) => Row(
                    children: [
                      Icon(icon, size: 15, color: Theme.of(context).primaryColor.withValues(alpha: 0.7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DefaultTextStyle(
                          style: TextStyle(fontSize: 13, color: Theme.of(context).textTheme.bodyMedium?.color),
                          overflow: TextOverflow.ellipsis,
                          child: item.child,
                        ),
                      ),
                    ],
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // LEAVE LIST (table-based)
  // ═══════════════════════════════════════════════════
  Widget _buildLeaveList(List<dynamic> leaves, {
    bool isMyLeaves = false,
    bool showApprovalActions = false,
    bool isAllTab = false,
  }) {
    if (leaves.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              showApprovalActions ? _l10n.noPendingRequests : _l10n.noLeaveRequests,
              style: TextStyle(fontSize: 16, color: Colors.grey[500], fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text('Các đơn nghỉ phép sẽ hiển thị tại đây', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
            if (isMyLeaves) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _showLeaveFormDialog(),
                icon: const Icon(Icons.add_rounded),
                label: Text(_l10n.createNewRequest),
              ),
            ],
          ],
        ),
      );
    }

    final totalPages = (leaves.length / _itemsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;

    // Sort
    leaves.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'startDate':
          final da = DateTime.tryParse(a['startDate']?.toString() ?? '');
          final db = DateTime.tryParse(b['startDate']?.toString() ?? '');
          cmp = (da ?? DateTime(2000)).compareTo(db ?? DateTime(2000));
          break;
        case 'createdAt':
        default:
          final da = DateTime.tryParse(a['createdAt']?.toString() ?? '');
          final db = DateTime.tryParse(b['createdAt']?.toString() ?? '');
          cmp = (da ?? DateTime(2000)).compareTo(db ?? DateTime(2000));
      }
      return _sortAscending ? cmp : -cmp;
    });

    final startIdx = (_currentPage - 1) * _itemsPerPage;
    final endIdx = (startIdx + _itemsPerPage).clamp(0, leaves.length);
    final pageLeaves = leaves.sublist(startIdx, endIdx);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: pageLeaves.length,
                  itemBuilder: (context, index) {
                    final leave = pageLeaves[index] is Map<String, dynamic>
                        ? pageLeaves[index] as Map<String, dynamic>
                        : Map<String, dynamic>.from(pageLeaves[index]);
                    return Padding(
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
                        child: _buildLeaveDeckItem(
                          leave,
                          isMyLeaves: isMyLeaves,
                          showApprovalActions: showApprovalActions,
                          isAllTab: isAllTab,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (totalPages > 1) _buildMobilePagination(leaves),
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          sortColumnIndex: _sortColumn == 'startDate' ? 3 : (_sortColumn == 'createdAt' ? 9 : null),
                          sortAscending: _sortAscending,
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFFAFAFA)),
                          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF71717A)),
                          dataTextStyle: const TextStyle(fontSize: 13, color: Color(0xFF18181B)),
                          columnSpacing: 16,
                          horizontalMargin: 16,
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 60,
                          columns: [
                            const DataColumn(label: Text('STT', textAlign: TextAlign.center)),
                            DataColumn(label: Text(_l10n.employee)),
                            DataColumn(label: Text(_l10n.leaveType)),
                            DataColumn(label: Text(_l10n.leaveDays), onSort: (_, asc) => setState(() { _sortColumn = 'startDate'; _sortAscending = asc; _currentPage = 1; })),
                            DataColumn(label: Text(_l10n.shiftLabel)),
                            DataColumn(label: Text(_l10n.halfShift)),
                            const DataColumn(label: Text('NV thay ca')),
                            DataColumn(label: Text(_l10n.reason)),
                            DataColumn(label: Text(_l10n.status)),
                            DataColumn(label: Text(_l10n.createdAt), onSort: (_, asc) => setState(() { _sortColumn = 'createdAt'; _sortAscending = asc; _currentPage = 1; })),
                            const DataColumn(label: Text('Thao tác')),
                          ],
                          rows: List.generate(pageLeaves.length, (index) {
                            final leave = pageLeaves[index] is Map<String, dynamic>
                                ? pageLeaves[index] as Map<String, dynamic>
                                : Map<String, dynamic>.from(pageLeaves[index]);
                            final globalIdx = startIdx + index;
                            final status = _normalizeStatus(leave['status']);
                            final leaveType = _normalizeLeaveType(leave['type']);
                            final statusInfo = _getStatusInfo(status);
                            final typeInfo = _getLeaveTypeInfo(leaveType);
                            final startDate = DateTime.tryParse(leave['startDate']?.toString() ?? '');
                            final endDate = DateTime.tryParse(leave['endDate']?.toString() ?? '');
                            final isHalfShift = leave['isHalfShift'] == true;
                            final empName = leave['employeeName'] ?? 'N/A';
                            final reason = leave['reason'] ?? '';
                            final shiftName = leave['shiftName']?.toString() ?? '';
                            final shiftNamesInList = (leave['shiftNames'] as List?)?.map((e) => e.toString()).where((s) => s.isNotEmpty).toList() ?? [];
                            final displayShift = shiftNamesInList.isNotEmpty ? shiftNamesInList.join(', ') : shiftName;
                            final replacementName = leave['replacementEmployeeName']?.toString() ?? '';
                            final createdAt = DateTime.tryParse(leave['createdAt']?.toString() ?? '');

                            String dateDisplay = 'N/A';
                            if (startDate != null) {
                              if (endDate != null && endDate.difference(startDate).inDays > 0) {
                                dateDisplay = '${DateFormat('dd/MM/yyyy').format(startDate)} → ${DateFormat('dd/MM/yyyy').format(endDate)}';
                              } else {
                                dateDisplay = DateFormat('dd/MM/yyyy').format(startDate);
                              }
                            }

                            return DataRow(
                              onSelectChanged: (_) => _showLeaveDetailDialog(leave, isMyLeaves: isMyLeaves, showApprovalActions: showApprovalActions, isAllTab: isAllTab),
                              cells: [
                                DataCell(Center(child: Text('${globalIdx + 1}'))),
                                DataCell(Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 130),
                                    child: Text(empName, overflow: TextOverflow.ellipsis),
                                  ),
                                )),
                                DataCell(Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: typeInfo.color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(typeInfo.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: typeInfo.color)),
                                  ),
                                )),
                                DataCell(Center(child: Text(dateDisplay, style: const TextStyle(fontSize: 12)))),
                                DataCell(Center(child: Text(displayShift.isNotEmpty ? displayShift : '-', style: const TextStyle(fontSize: 12)))),
                                DataCell(Center(child: isHalfShift
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('½', style: TextStyle(fontSize: 11, color: Colors.purple, fontWeight: FontWeight.w600)),
                                      )
                                    : const Text('-'))),
                                DataCell(Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 120),
                                    child: Text(replacementName.isNotEmpty ? replacementName : '-', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                  ),
                                )),
                                DataCell(Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 150),
                                    child: Tooltip(
                                      message: reason,
                                      child: Text(reason.isNotEmpty ? reason : '-', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                )),
                                DataCell(Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: statusInfo.color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(statusInfo.icon, size: 12, color: statusInfo.color),
                                            const SizedBox(width: 4),
                                            Text(statusInfo.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusInfo.color)),
                                          ],
                                        ),
                                      ),
                                      if ((leave['totalApprovalLevels'] ?? 1) > 1)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} cấp',
                                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                          ),
                                        ),
                                    ],
                                  ),
                                )),
                                DataCell(Center(child: Text(createdAt != null ? DateFormat('dd/MM/yyyy').format(createdAt) : '-', style: const TextStyle(fontSize: 12)))),
                                DataCell(Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _buildActionButtons(leave, status, isMyLeaves, showApprovalActions, isAllTab),
                                  ),
                                )),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (totalPages > 1) _buildPagination(leaves),
          ],
        );
      },
    );
  }

  Widget _buildPagination(List<dynamic> leaves) {
    final totalItems = leaves.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Builder(builder: (context) {
        final isMobile = Responsive.isMobile(context);
        final infoRow = Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Hiển thị ${startIndex + 1}-$endIndex / $totalItems',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
            ),
            Row(
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
                      value: _itemsPerPage,
                      isDense: true,
                      style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                      items: _pageSizeOptions
                          .map((size) => DropdownMenuItem(value: size, child: Text('$size')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() { _itemsPerPage = v; _currentPage = 1; });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
        final pageNav = Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPageNavBtn(Icons.first_page, _currentPage > 1, () => setState(() => _currentPage = 1)),
            _buildPageNavBtn(Icons.chevron_left, _currentPage > 1, () => setState(() => _currentPage--)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_currentPage / $totalPages',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages, () => setState(() => _currentPage++)),
            _buildPageNavBtn(Icons.last_page, _currentPage < totalPages, () => setState(() => _currentPage = totalPages)),
          ],
        );
        if (isMobile) {
          return Column(children: [infoRow, const SizedBox(height: 8), pageNav]);
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [infoRow, pageNav],
        );
      }),
    );
  }

  Widget _buildPageNavBtn(IconData icon, bool enabled, VoidCallback onPressed) {
    return Material(
      color: enabled ? const Color(0xFFF1F5F9) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 20, color: enabled ? Theme.of(context).primaryColor : Colors.grey[400]),
        ),
      ),
    );
  }

  Widget _buildMobilePagination(List<dynamic> leaves) {
    final totalItems = leaves.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${startIndex + 1}-$endIndex / $totalItems',
                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  _buildPageNavBtn(Icons.chevron_left, _currentPage > 1, () => setState(() => _currentPage--)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_currentPage / $totalPages',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages, () => setState(() => _currentPage++)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  // LEAVE CARD
  // ═══════════════════════════════════════════════════
  Widget _buildLeaveDeckItem(Map<String, dynamic> leave, {
    bool isMyLeaves = false,
    bool showApprovalActions = false,
    bool isAllTab = false,
  }) {
    final status = _normalizeStatus(leave['status']);
    final leaveType = _normalizeLeaveType(leave['type']);
    final statusInfo = _getStatusInfo(status);
    final typeInfo = _getLeaveTypeInfo(leaveType);
    final startDate = DateTime.tryParse(leave['startDate']?.toString() ?? '');
    final endDate = DateTime.tryParse(leave['endDate']?.toString() ?? '');
    final duration = startDate != null && endDate != null ? endDate.difference(startDate).inDays + 1 : 0;
    final empName = leave['employeeName'] ?? 'N/A';
    final isPending = status == 0;

    return InkWell(
      onTap: () => _showLeaveDetailDialog(leave, isMyLeaves: isMyLeaves, showApprovalActions: showApprovalActions, isAllTab: isAllTab),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: typeInfo.color.withValues(alpha: 0.12),
              child: Icon(typeInfo.icon, size: 16, color: typeInfo.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(empName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      typeInfo.label,
                      if (startDate != null) '${DateFormat('dd/MM').format(startDate)}${duration > 1 && endDate != null ? '-${DateFormat('dd/MM').format(endDate)}' : ''}',
                      '$duration ngày',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: statusInfo.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text(statusInfo.label, style: TextStyle(color: statusInfo.color, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                if ((leave['totalApprovalLevels'] ?? 1) > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} cấp',
                      style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                    ),
                  ),
              ],
            ),
            if (_shouldShowActions(status, isMyLeaves, showApprovalActions, isAllTab)) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () { final actions = _buildActionButtons(leave, status, isMyLeaves, showApprovalActions, isAllTab); if (actions.isNotEmpty) _showLeaveDetailDialog(leave, isMyLeaves: isMyLeaves, showApprovalActions: showApprovalActions, isAllTab: isAllTab); },
                borderRadius: BorderRadius.circular(6),
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.more_horiz, size: 18, color: Color(0xFF71717A))),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  bool _shouldShowActions(int status, bool isMyLeaves, bool showApprovalActions, bool isAllTab) {
    final isPending = status == 0;
    // My leaves: show for pending (edit/cancel/delete)
    if (isMyLeaves && isPending) return true;
    // All tab: show for all statuses (pending: edit/cancel/approve/reject/delete; approved/rejected: undo/delete)
    if (isAllTab) return true;
    // Pending tab: show for pending with approval actions
    if (isPending && showApprovalActions) return true;
    return false;
  }

  List<Widget> _buildActionButtons(Map<String, dynamic> leave, int status, bool isMyLeaves, bool showApprovalActions, bool isAllTab) {
    final isPending = status == 0;
    final buttons = <Widget>[];
    final _permProv = Provider.of<PermissionProvider>(context, listen: false);

    // Only allow edit when status is Pending (0)
    if (isPending && (isMyLeaves || isAllTab) && _permProv.canEdit('Leave')) {
      buttons.add(_ActionBtn(icon: Icons.edit_rounded, label: 'Sửa', color: Colors.blue, onTap: () => _showLeaveFormDialog(leave: leave)));
      buttons.add(const SizedBox(width: 6));
    }

    // Cancel: employee can cancel own pending, manager can cancel any pending
    if (isPending) {
      if (isMyLeaves || (isAllTab && _isManager) || (showApprovalActions && _isManager)) {
        buttons.add(_ActionBtn(icon: Icons.cancel_outlined, label: 'Hủy', color: Colors.red, onTap: () => _cancelLeave(leave['id'])));
        buttons.add(const SizedBox(width: 6));
      }
    }

    // Approve/Reject: manager on pending tab or all tab, but NOT own leave
    final leaveOwnerId = leave['employeeUserId']?.toString() ?? leave['userId']?.toString() ?? '';
    if (isPending && (showApprovalActions || isAllTab) && _permProv.canApprove('Leave') && leaveOwnerId != _currentUserId) {
      buttons.add(_ActionBtn(icon: Icons.check_circle_outline, label: 'Duyệt', color: Colors.green, onTap: () => _approveLeave(leave['id'])));
      buttons.add(const SizedBox(width: 6));
      buttons.add(_ActionBtn(icon: Icons.highlight_off, label: 'Từ chối', color: Colors.red, onTap: () => _rejectLeave(leave['id'])));
      buttons.add(const SizedBox(width: 6));
    }

    // Undo: manager on all tab for approved/rejected
    if ((isAllTab || showApprovalActions) && _isManager && (status == 1 || status == 2)) {
      buttons.add(_ActionBtn(icon: Icons.undo_rounded, label: 'Hoàn tác', color: Colors.orange, onTap: () => _undoLeaveApproval(leave['id'])));
      buttons.add(const SizedBox(width: 6));
    }

    // Delete: pending in myLeaves, any status in allTab/pendingTab for manager
    if (((isMyLeaves && isPending) || ((isAllTab || showApprovalActions) && _isManager)) && _permProv.canDelete('Leave')) {
      buttons.add(_ActionBtn(icon: Icons.delete_forever_outlined, label: 'Xóa', color: Colors.red.shade700, onTap: () => _forceDeleteLeave(leave['id'])));
    }

    return buttons;
  }

  // ═══════════════════════════════════════════════════
  // DETAIL DIALOG
  // ═══════════════════════════════════════════════════
  void _showLeaveDetailDialog(Map<String, dynamic> leave, {bool isMyLeaves = false, bool showApprovalActions = false, bool isAllTab = false}) {
    final status = _normalizeStatus(leave['status']);
    final leaveType = _normalizeLeaveType(leave['type']);
    final statusInfo = _getStatusInfo(status);
    final typeInfo = _getLeaveTypeInfo(leaveType);
    final startDate = DateTime.tryParse(leave['startDate']?.toString() ?? '');
    final endDate = DateTime.tryParse(leave['endDate']?.toString() ?? '');
    final duration = startDate != null && endDate != null ? endDate.difference(startDate).inDays + 1 : 0;
    final isHalfShift = leave['isHalfShift'] == true;
    final createdAt = DateTime.tryParse(leave['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(leave['updatedAt']?.toString() ?? '');
    final shiftName = leave['shiftName']?.toString() ?? '';
    final shiftNames = (leave['shiftNames'] as List?)?.map((e) => e.toString()).where((s) => s.isNotEmpty).toList() ?? [];
    final displayShiftNames = shiftNames.isNotEmpty ? shiftNames.join(', ') : shiftName;
    final replacementName = leave['replacementEmployeeName']?.toString() ?? '';
    final reason = leave['reason'] ?? '';
    // Build action buttons that close dialog first
    final dialogActions = <Widget>[];
    final isPending = status == 0;
    final _dlgPerm = Provider.of<PermissionProvider>(context, listen: false);

    if (isPending && (isMyLeaves || isAllTab) && _dlgPerm.canEdit('Leave')) {
      dialogActions.add(_ActionBtn(icon: Icons.edit_rounded, label: 'Sửa', color: Colors.blue, onTap: () { Navigator.pop(context); _showLeaveFormDialog(leave: leave); }));
      dialogActions.add(const SizedBox(width: 6));
    }
    // Cancel: employee can cancel own pending, manager can cancel any pending
    if (isPending) {
      if (isMyLeaves || (isAllTab && _isManager) || (showApprovalActions && _isManager)) {
        dialogActions.add(_ActionBtn(icon: Icons.cancel_outlined, label: 'Hủy', color: Colors.red, onTap: () { Navigator.pop(context); _cancelLeave(leave['id']); }));
        dialogActions.add(const SizedBox(width: 6));
      }
    }
    // Approve/Reject — NOT own leave
    final dlgLeaveOwnerId = leave['employeeUserId']?.toString() ?? leave['userId']?.toString() ?? '';
    if (isPending && (showApprovalActions || isAllTab) && _dlgPerm.canApprove('Leave') && dlgLeaveOwnerId != _currentUserId) {
      dialogActions.add(_ActionBtn(icon: Icons.check_circle_outline, label: 'Duyệt', color: Colors.green, onTap: () { Navigator.pop(context); _approveLeave(leave['id']); }));
      dialogActions.add(const SizedBox(width: 6));
      dialogActions.add(_ActionBtn(icon: Icons.highlight_off, label: 'Từ chối', color: Colors.red, onTap: () { Navigator.pop(context); _rejectLeave(leave['id']); }));
      dialogActions.add(const SizedBox(width: 6));
    }
    // Undo
    if ((isAllTab || showApprovalActions) && _isManager && (status == 1 || status == 2)) {
      dialogActions.add(_ActionBtn(icon: Icons.undo_rounded, label: 'Hoàn tác', color: Colors.orange, onTap: () { Navigator.pop(context); _undoLeaveApproval(leave['id']); }));
      dialogActions.add(const SizedBox(width: 6));
    }
    // Delete
    if (((isMyLeaves && isPending) || ((isAllTab || showApprovalActions) && _isManager)) && _dlgPerm.canDelete('Leave')) {
      dialogActions.add(_ActionBtn(icon: Icons.delete_forever_outlined, label: 'Xóa', color: Colors.red.shade700, onTap: () { Navigator.pop(context); _forceDeleteLeave(leave['id']); }));
    }

    final isMobile = Responsive.isMobile(context);

    final detailContent = Table(
      columnWidths: const {
        0: FixedColumnWidth(140),
        1: FlexColumnWidth(),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade100),
      ),
      children: [
        _detailTableRow('Nhân viên', leave['employeeName'] ?? 'N/A'),
        _detailTableRow('Loại nghỉ', typeInfo.label, valueColor: typeInfo.color),
        _detailTableRow('Trạng thái', statusInfo.label, valueColor: statusInfo.color),
        _detailTableRow('Từ ngày', startDate != null ? DateFormat('EEEE, dd/MM/yyyy', 'vi').format(startDate) : 'N/A'),
        _detailTableRow('Đến ngày', endDate != null ? DateFormat('EEEE, dd/MM/yyyy', 'vi').format(endDate) : 'N/A'),
        _detailTableRow('Số ngày', '$duration ngày${isHalfShift ? ' (Nửa ca)' : ''}'),
        if (displayShiftNames.isNotEmpty)
          _detailTableRow('Ca làm việc', displayShiftNames),
        if (replacementName.isNotEmpty)
          _detailTableRow('Người thay', replacementName),
        _detailTableRow('Lý do', reason.isNotEmpty ? reason : 'N/A'),
        if (status == 2 && leave['rejectionReason'] != null)
          _detailTableRow('Lý do từ chối', leave['rejectionReason'], valueColor: Colors.red),
        if (createdAt != null)
          _detailTableRow('Ngày tạo', DateFormat('dd/MM/yyyy HH:mm').format(createdAt)),
        if (updatedAt != null)
          _detailTableRow('Cập nhật', DateFormat('dd/MM/yyyy HH:mm').format(updatedAt)),
        _detailTableRow('ID', leave['id']?.toString().substring(0, 8) ?? 'N/A'),
      ],
    );

    // Build approval timeline widget
    final approvalRecords = (leave['approvalRecords'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalLevels = leave['totalApprovalLevels'] ?? 1;
    final currentStep = leave['currentApprovalStep'] ?? 0;

    Widget approvalTimeline = const SizedBox.shrink();
    if (approvalRecords.isNotEmpty) {
      approvalRecords.sort((a, b) => (a['stepOrder'] ?? 0).compareTo(b['stepOrder'] ?? 0));
      approvalTimeline = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Progress indicator
          if (totalLevels > 1) ...[
            Row(
              children: [
                const Icon(Icons.linear_scale_rounded, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text('Tiến trình duyệt: $currentStep/$totalLevels cấp', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: totalLevels > 0 ? currentStep / totalLevels : 0,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(status == 1 ? Colors.green : status == 2 ? Colors.red : Colors.blue),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Timeline
          const Text('Lịch sử phê duyệt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...approvalRecords.asMap().entries.map((entry) {
            final idx = entry.key;
            final record = entry.value;
            final stepStatus = record['status'] ?? 0;
            final stepName = record['stepName'] ?? 'Cấp ${record['stepOrder'] ?? idx + 1}';
            final assignedUser = record['assignedUserName'] ?? '';
            final actualUser = record['actualUserName'] ?? '';
            final actionDate = DateTime.tryParse(record['actionDate']?.toString() ?? '');
            final note = record['note']?.toString() ?? '';
            final isLast = idx == approvalRecords.length - 1;

            Color dotColor;
            IconData dotIcon;
            switch (stepStatus) {
              case 1: dotColor = Colors.green; dotIcon = Icons.check_circle; break;
              case 2: dotColor = Colors.red; dotIcon = Icons.cancel; break;
              case 3: dotColor = Colors.grey; dotIcon = Icons.block; break;
              default: dotColor = Colors.orange; dotIcon = Icons.radio_button_unchecked; break;
            }

            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timeline line + dot
                  SizedBox(
                    width: 32,
                    child: Column(
                      children: [
                        Icon(dotIcon, size: 18, color: dotColor),
                        if (!isLast) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(stepName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: dotColor)),
                          if (assignedUser.isNotEmpty)
                            Text('Phân công: $assignedUser', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          if (actualUser.isNotEmpty && stepStatus != 0)
                            Text('Thực hiện: $actualUser', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          if (actionDate != null)
                            Text(DateFormat('dd/MM/yyyy HH:mm').format(actionDate), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          if (note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('"$note"', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Chi tiết đơn nghỉ phép'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusInfo.icon, size: 16, color: statusInfo.color),
                          const SizedBox(width: 6),
                          Text(statusInfo.label, style: TextStyle(color: statusInfo.color, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    detailContent,
                    approvalTimeline,
                    if (dialogActions.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Wrap(spacing: 8, runSpacing: 8, children: dialogActions),
                    ],
                  ],
                ),
              ),
            ),
          );
        }

        return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [statusInfo.color.withValues(alpha: 0.8), statusInfo.color.withValues(alpha: 0.6)],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_rounded, color: Colors.white, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Chi tiết đơn nghỉ phép', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(leave['employeeName'] ?? 'N/A', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusInfo.icon, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(statusInfo.label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      detailContent,
                      approvalTimeline,
                    ],
                  ),
                ),
              ),

              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                child: Row(
                  children: [
                    if (dialogActions.isNotEmpty) ...dialogActions,
                    const Spacer(),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      },
    );
  }

  // ignore: unused_element
  Widget _detailRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? Colors.grey.shade800)),
          ),
        ],
      ),
    );
  }

  TableRow _detailTableRow(String label, String value, {Color? valueColor}) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? Colors.grey.shade800)),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  // FORM DIALOG
  // ═══════════════════════════════════════════════════
  Future<void> _showLeaveFormDialog({Map<String, dynamic>? leave}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _LeaveFormDialog(
        shifts: _shifts,
        employees: _employees,
        apiService: _apiService,
        existingLeave: leave,
        currentUserId: _currentUserId,
        isManager: _isManager,
      ),
    );
    if (result == true) _loadData();
  }

  // ═══════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════
  Future<void> _cancelLeave(String? leaveId) async {
    if (leaveId == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Hủy đơn nghỉ phép',
      content: 'Bạn có chắc chắn muốn hủy đơn nghỉ phép này?',
      confirmText: 'Hủy đơn',
      confirmVariant: AppButtonVariant.danger,
      icon: Icons.cancel_rounded,
    );
    if (confirm != true) return;
    final result = await _apiService.cancelLeave(leaveId);
    _showResultSnackBar(result, 'Đã hủy đơn nghỉ phép', 'Lỗi khi hủy đơn');
  }

  Future<void> _undoLeaveApproval(String? leaveId) async {
    if (leaveId == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Hoàn tác duyệt',
      content: 'Bạn có chắc chắn muốn hoàn tác trạng thái đơn nghỉ phép này về Chờ duyệt?\nHệ thống sẽ khôi phục lịch làm việc nếu đơn đã được duyệt.',
      confirmText: 'Hoàn tác',
      confirmVariant: AppButtonVariant.warning,
      icon: Icons.undo_rounded,
    );
    if (confirm != true) return;
    final result = await _apiService.undoLeaveApproval(leaveId);
    _showResultSnackBar(result, 'Đã hoàn tác trạng thái đơn', 'Lỗi khi hoàn tác');
  }

  Future<void> _forceDeleteLeave(String? leaveId) async {
    if (leaveId == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Xóa đơn nghỉ phép',
      content: 'Bạn có chắc chắn muốn xóa vĩnh viễn đơn nghỉ phép này?\nHành động này không thể hoàn tác.',
      confirmText: 'Xóa',
      confirmVariant: AppButtonVariant.danger,
      icon: Icons.delete_forever_rounded,
    );
    if (confirm != true) return;
    final result = await _apiService.forceDeleteLeave(leaveId);
    _showResultSnackBar(result, 'Đã xóa đơn nghỉ phép', 'Lỗi khi xóa đơn');
  }

  Future<void> _approveLeave(String? leaveId) async {
    if (leaveId == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Duyệt đơn nghỉ phép',
      content: 'Bạn có chắc chắn muốn duyệt đơn nghỉ phép này?\nHệ thống sẽ tự tạo lịch nghỉ cho nhân viên.',
      confirmText: 'Duyệt',
      confirmVariant: AppButtonVariant.success,
      icon: Icons.check_circle_rounded,
    );
    if (confirm != true) return;
    final result = await _apiService.approveLeave(leaveId);
    _showResultSnackBar(result, 'Đã duyệt đơn nghỉ phép', 'Lỗi khi duyệt đơn');
  }

  Future<void> _rejectLeave(String? leaveId) async {
    if (leaveId == null) return;
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(Icons.cancel_rounded, color: Colors.red[400]), const SizedBox(width: 8), const Text('Từ chối đơn nghỉ phép')]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vui lòng nhập lý do từ chối:'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(hintText: 'Lý do từ chối...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ],
          ),
        ),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () {
              if (reasonController.text.trim().isEmpty) {
                NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập lý do từ chối');
                return;
              }
              Navigator.pop(ctx, true);
            },
            confirmLabel: 'Từ chối',
            confirmVariant: AppButtonVariant.danger,
          ),
        ],
      ),
    );
    if (confirm == true && reasonController.text.trim().isNotEmpty) {
      final result = await _apiService.rejectLeave(leaveId, reasonController.text.trim());
      _showResultSnackBar(result, 'Đã từ chối đơn nghỉ phép', 'Lỗi khi từ chối đơn');
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    AppButtonVariant confirmVariant = AppButtonVariant.primary,
    required IconData icon,
  }) {
    final iconColor = switch (confirmVariant) {
      AppButtonVariant.danger => Colors.red,
      AppButtonVariant.success => Colors.green,
      AppButtonVariant.warning => Colors.orange,
      _ => Theme.of(context).colorScheme.primary,
    };
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [Icon(icon, color: iconColor), const SizedBox(width: 8), Text(title)]),
        content: Text(content),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
            cancelLabel: 'Không',
            confirmLabel: confirmText,
            confirmVariant: confirmVariant,
          ),
        ],
      ),
    );
  }

  void _showResultSnackBar(Map<String, dynamic> result, String successMsg, String errorMsg) {
    if (!mounted) return;
    if (result['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Thành công', message: successMsg);
      _loadData();
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? errorMsg);
      // Refresh to clear stale data (e.g. leave already approved by another device)
      _loadData();
    }
  }

  // ═══════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════
  static _StatusInfo _getStatusInfo(int status) {
    switch (status) {
      case 0: return const _StatusInfo('Chờ duyệt', Colors.orange, Icons.hourglass_bottom_rounded);
      case 1: return const _StatusInfo('Đã duyệt', Colors.green, Icons.check_circle_rounded);
      case 2: return const _StatusInfo('Từ chối', Colors.red, Icons.cancel_rounded);
      case 3: return const _StatusInfo('Đã hủy', Colors.grey, Icons.block_rounded);
      default: return const _StatusInfo('N/A', Colors.grey, Icons.help_outline_rounded);
    }
  }

  static _LeaveTypeInfo _getLeaveTypeInfo(int type) {
    switch (type) {
      case 0: return const _LeaveTypeInfo('Phép năm', Colors.teal, Icons.beach_access_rounded);
      case 1: return const _LeaveTypeInfo('Lễ tết', Colors.orange, Icons.celebration_rounded);
      case 2: return const _LeaveTypeInfo('VR có lương', Colors.blue, Icons.paid_rounded);
      case 3: return const _LeaveTypeInfo('VR không lương', Colors.amber, Icons.money_off_rounded);
      case 4: return const _LeaveTypeInfo('Ốm đau', Colors.red, Icons.local_hospital_rounded);
      case 5: return const _LeaveTypeInfo('Thai sản', Colors.pink, Icons.child_friendly_rounded);
      case 6: return const _LeaveTypeInfo('Nghỉ bù', Colors.indigo, Icons.swap_horiz_rounded);
      case 7: return const _LeaveTypeInfo('Nghỉ dài hạn', Colors.brown, Icons.hourglass_full_rounded);
      default: return const _LeaveTypeInfo('Khác', Colors.grey, Icons.help_outline);
    }
  }
}

// ═══════════════════════════════════════════════════
// ACTION BUTTON
// ═══════════════════════════════════════════════════
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _StatusInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusInfo(this.label, this.color, this.icon);
}

class _LeaveTypeInfo {
  final String label;
  final Color color;
  final IconData icon;
  const _LeaveTypeInfo(this.label, this.color, this.icon);
}

// ═══════════════════════════════════════════════════
// LEAVE FORM DIALOG (CREATE + EDIT)
// ═══════════════════════════════════════════════════
class _LeaveFormDialog extends StatefulWidget {
  final List<dynamic> shifts;
  final List<dynamic> employees;
  final ApiService apiService;
  final Map<String, dynamic>? existingLeave;
  final String? currentUserId;
  final bool isManager;

  const _LeaveFormDialog({
    required this.shifts,
    required this.employees,
    required this.apiService,
    this.existingLeave,
    this.currentUserId,
    this.isManager = false,
  });

  @override
  State<_LeaveFormDialog> createState() => _LeaveFormDialogState();
}

class _LeaveFormDialogState extends State<_LeaveFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  AppLocalizations get _l10n => AppLocalizations.of(context);

  List<String> _selectedShiftIds = [];
  String? _selectedReplacementId;
  String? _selectedEmployeeId; // employee id (from employees list)
  String? _selectedEmployeeUserId; // applicationUserId for API
  DateTime _leaveDate = DateTime.now();
  int _leaveType = 0;
  bool _isHalfShift = false;
  bool _isSubmitting = false;

  List<dynamic> _filteredShifts = [];
  bool _isLoadingShifts = false;
  bool _hasScheduleForDate = false;

  bool get _isEditMode => widget.existingLeave != null;

  @override
  void initState() {
    super.initState();
    // Find current user's employee record
    if (widget.currentUserId != null) {
      for (final emp in widget.employees) {
        if (emp['applicationUserId']?.toString() == widget.currentUserId) {
          _selectedEmployeeId = emp['id']?.toString();
          _selectedEmployeeUserId = emp['applicationUserId']?.toString();
          break;
        }
      }
    }
    if (_isEditMode) {
      final l = widget.existingLeave!;
      _leaveType = _LeaveScreenState._normalizeLeaveType(l['type']);
      _isHalfShift = l['isHalfShift'] ?? false;
      _reasonController.text = l['reason'] ?? '';
      final repId = l['replacementEmployeeId']?.toString();
      // Only set if the replacement employee exists in the list
      if (repId != null && widget.employees.any((e) => e['id']?.toString() == repId)) {
        _selectedReplacementId = repId;
      }
      _leaveDate = DateTime.tryParse(l['startDate']?.toString() ?? '') ?? DateTime.now();
      final ids = l['shiftIds'];
      if (ids != null && ids is List) {
        _selectedShiftIds = ids.map((e) => e.toString()).toList();
      } else if (l['shiftId'] != null && l['shiftId'].toString().isNotEmpty) {
        _selectedShiftIds = [l['shiftId'].toString()];
      }
      // Set employee from existing leave
      if (l['employeeUserId'] != null) {
        _selectedEmployeeUserId = l['employeeUserId']?.toString();
        for (final emp in widget.employees) {
          if (emp['applicationUserId']?.toString() == _selectedEmployeeUserId) {
            _selectedEmployeeId = emp['id']?.toString();
            break;
          }
        }
      }
    }
    _filteredShifts = List.from(widget.shifts);
    _loadShiftsForDate();
  }

  Future<void> _loadShiftsForDate() async {
    setState(() => _isLoadingShifts = true);
    try {
      final employeeId = _selectedEmployeeId;

      if (employeeId != null) {
        final scheduleShiftIds = <String>{};

        final wsResult = await widget.apiService.getWorkSchedules(
          employeeId: employeeId,
          fromDate: _leaveDate,
          toDate: _leaveDate,
          isDayOff: false,
        );

        if (wsResult['isSuccess'] == true && wsResult['data'] != null) {
          final data = wsResult['data'];
          final items = data is List ? data : (data['items'] ?? []);
          for (final item in items) {
            final sid = item['shiftId']?.toString();
            if (sid != null && sid.isNotEmpty) scheduleShiftIds.add(sid);
          }
        }

        try {
          final srResult = await widget.apiService.getScheduleRegistrations(
            employeeId: employeeId,
            fromDate: _leaveDate,
            toDate: _leaveDate,
          );
          if (srResult['isSuccess'] == true && srResult['data'] != null) {
            final data = srResult['data'];
            final items = data is List ? data : (data['items'] ?? []);
            for (final item in items) {
              final isDayOff = item['isDayOff'] == true;
              final statusVal = item['status'];
              if (!isDayOff && statusVal != 2 && statusVal != 3) {
                final sid = item['shiftId']?.toString();
                if (sid != null && sid.isNotEmpty) scheduleShiftIds.add(sid);
              }
            }
          }
        } catch (e) {
          debugPrint('ScheduleRegistrations error: $e');
        }

        if (scheduleShiftIds.isNotEmpty) {
          _filteredShifts = widget.shifts.where((s) => scheduleShiftIds.contains(s['id']?.toString())).toList();
          _hasScheduleForDate = true;
        } else {
          _filteredShifts = List.from(widget.shifts);
          _hasScheduleForDate = false;
        }
      } else {
        _filteredShifts = List.from(widget.shifts);
        _hasScheduleForDate = false;
      }
    } catch (e) {
      _filteredShifts = List.from(widget.shifts);
      _hasScheduleForDate = false;
    }
    if (mounted) setState(() => _isLoadingShifts = false);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = Responsive.isMobile(context);

    final formBody = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                      // Employee selector (admin/manager only)
                      if (widget.isManager) ...[
                        _buildSectionLabel('Nhân viên nghỉ phép', Icons.person_rounded, isRequired: true),
                        const SizedBox(height: 8),
                        if (_isEditMode) ...[
                          // Read-only display in edit mode (employee can't be changed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[50],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.person_rounded, size: 20, color: Colors.grey[500]),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    widget.existingLeave?['employeeName']?.toString() ?? 'N/A',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey[400]),
                              ],
                            ),
                          ),
                        ] else ...[
                          DropdownButtonFormField<String>(
                            initialValue: _selectedEmployeeId,
                            decoration: InputDecoration(
                              hintText: 'Chọn nhân viên',
                              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              prefixIcon: const Icon(Icons.person_rounded, size: 20),
                            ),
                            isExpanded: true,
                            items: widget.employees.map<DropdownMenuItem<String>>((emp) {
                              final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                              return DropdownMenuItem(
                                value: emp['id']?.toString(),
                                child: Text(
                                  name.isEmpty ? (emp['employeeCode'] ?? 'N/A') : name,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              );
                            }).toList(),
                            validator: (v) => (v == null || v.isEmpty) ? 'Vui lòng chọn nhân viên' : null,
                            onChanged: (v) {
                              setState(() {
                                _selectedEmployeeId = v;
                                _selectedShiftIds.clear();
                                _selectedReplacementId = null;
                                // Find applicationUserId for the selected employee
                                for (final emp in widget.employees) {
                                  if (emp['id']?.toString() == v) {
                                    _selectedEmployeeUserId = emp['applicationUserId']?.toString();
                                    break;
                                  }
                                }
                              });
                              _loadShiftsForDate();
                            },
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],

                      // Leave type
                      _buildSectionLabel('Loại nghỉ phép', Icons.category_rounded, isRequired: true),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildTypeOption(0, 'Phép năm', Icons.beach_access_rounded, Colors.teal),
                          _buildTypeOption(1, 'Lễ tết', Icons.celebration_rounded, Colors.orange),
                          _buildTypeOption(2, 'VR có lương', Icons.paid_rounded, Colors.blue),
                          _buildTypeOption(3, 'VR không lương', Icons.money_off_rounded, Colors.amber),
                          _buildTypeOption(4, 'Ốm đau', Icons.local_hospital_rounded, Colors.red),
                          _buildTypeOption(5, 'Thai sản', Icons.child_friendly_rounded, Colors.pink),
                          _buildTypeOption(6, 'Nghỉ bù', Icons.swap_horiz_rounded, Colors.indigo),
                          _buildTypeOption(7, 'Nghỉ dài hạn', Icons.hourglass_full_rounded, Colors.brown),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Date
                      _buildSectionLabel('Ngày nghỉ', Icons.date_range_rounded, isRequired: true),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _buildDateField('Ngày nghỉ', _leaveDate)),
                          const SizedBox(width: 12),
                          Row(
                            children: [
                              Checkbox(
                                value: _isHalfShift,
                                onChanged: (v) => setState(() => _isHalfShift = v ?? false),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              Text(_l10n.halfShift, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Shifts
                      _buildSectionLabel('Ca làm việc', Icons.schedule_rounded),
                      const SizedBox(height: 4),
                      Text(
                        _hasScheduleForDate
                            ? 'Ca nghỉ phép (theo lịch làm việc ngày ${DateFormat('dd/MM').format(_leaveDate)})'
                            : 'Chọn ca nghỉ phép (có thể chọn nhiều)',
                        style: TextStyle(fontSize: 12, color: _hasScheduleForDate ? Colors.blue[500] : Colors.grey[500]),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _isLoadingShifts
                            ? const Center(child: Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
                            : _filteredShifts.isEmpty
                                ? Text('Không có ca làm việc cho ngày này', style: TextStyle(color: Colors.grey[400], fontSize: 13))
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 6,
                                    children: _filteredShifts.map<Widget>((shift) {
                                      final id = shift['id']?.toString() ?? '';
                                      final name = shift['name'] ?? 'N/A';
                                      final selected = _selectedShiftIds.contains(id);
                                      return FilterChip(
                                        label: Text(name, style: const TextStyle(fontSize: 13)),
                                        selected: selected,
                                        selectedColor: theme.primaryColor.withValues(alpha: 0.15),
                                        checkmarkColor: theme.primaryColor,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        onSelected: (s) => setState(() => s ? _selectedShiftIds.add(id) : _selectedShiftIds.remove(id)),
                                      );
                                    }).toList(),
                                  ),
                      ),
                      const SizedBox(height: 20),

                      // Replacement employee
                      _buildSectionLabel('Nhân viên thay ca', Icons.swap_horiz_rounded),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedReplacementId,
                        decoration: InputDecoration(
                          hintText: 'Không bắt buộc',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          prefixIcon: const Icon(Icons.person_search_rounded, size: 20),
                        ),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('Không chọn')),
                          ...widget.employees
                              .where((emp) => emp['id']?.toString() != _selectedEmployeeId)
                              .map<DropdownMenuItem<String>>((emp) {
                            final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                            return DropdownMenuItem(
                              value: emp['id']?.toString(),
                              child: Text(name.isEmpty ? (emp['employeeCode'] ?? 'N/A') : name, style: const TextStyle(fontSize: 14)),
                            );
                          }),
                        ],
                        onChanged: (v) => setState(() => _selectedReplacementId = v),
                      ),
                      const SizedBox(height: 20),

                      // Reason
                      _buildSectionLabel('Lý do', Icons.notes_rounded, isRequired: true),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _reasonController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Nhập lý do xin nghỉ phép...',
                          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập lý do' : null,
                      ),
                    ],
                  ),
                );

    final submitButton = FilledButton.icon(
      onPressed: _isSubmitting ? null : _submit,
      icon: _isSubmitting
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Icon(_isEditMode ? Icons.save_rounded : Icons.send_rounded, size: 18),
      label: Text(_isEditMode ? _l10n.save : 'Gửi đơn'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(_isEditMode ? 'Sửa đơn nghỉ phép' : 'Tạo đơn nghỉ phép'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: submitButton,
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: formBody,
          ),
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [theme.primaryColor, theme.primaryColor.withValues(alpha: 0.85)]),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note_rounded, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    _isEditMode ? 'Sửa đơn nghỉ phép' : 'Tạo đơn nghỉ phép',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: formBody,
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15)))),
              child: Row(
                children: [
                  if (_isEditMode)
                    Text(
                      'ID: ${widget.existingLeave!['id']?.toString().substring(0, 8) ?? ''}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                    child: Text(_l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  submitButton,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text, IconData icon, {bool isRequired = false}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        if (isRequired) Text(' *', style: TextStyle(color: Colors.red[400], fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTypeOption(int type, String label, IconData icon, Color color) {
    final selected = _leaveType == type;
    return InkWell(
      onTap: () => setState(() => _leaveType = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : Colors.grey[300]!, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? color : Colors.grey, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: selected ? color : Colors.grey[600], fontWeight: selected ? FontWeight.w600 : FontWeight.normal, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(String label, DateTime date) {
    return InkWell(
      onTap: () => _selectDate(),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 16, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                  const SizedBox(height: 2),
                  Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _leaveDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _leaveDate = picked;
        _selectedShiftIds.clear();
      });
      _loadShiftsForDate();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate shift selection
    if (_selectedShiftIds.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu thông tin',
        message: 'Vui lòng chọn ít nhất một ca làm việc',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      Map<String, dynamic> result;
      if (_isEditMode) {
        result = await widget.apiService.updateLeave(
          leaveId: widget.existingLeave!['id'],
          shiftIds: _selectedShiftIds.isNotEmpty ? _selectedShiftIds : null,
          startDate: _leaveDate,
          endDate: _leaveDate,
          type: _leaveType,
          isHalfShift: _isHalfShift,
          reason: _reasonController.text.trim(),
          replacementEmployeeId: _selectedReplacementId,
          employeeUserId: widget.isManager ? _selectedEmployeeUserId : null,
          employeeId: widget.isManager ? _selectedEmployeeId : null,
        );
      } else {
        result = await widget.apiService.createLeave(
          shiftIds: _selectedShiftIds.isNotEmpty ? _selectedShiftIds : null,
          startDate: _leaveDate,
          endDate: _leaveDate,
          type: _leaveType,
          isHalfShift: _isHalfShift,
          reason: _reasonController.text.trim(),
          replacementEmployeeId: _selectedReplacementId,
          employeeUserId: widget.isManager ? _selectedEmployeeUserId : null,
          employeeId: widget.isManager ? _selectedEmployeeId : null,
        );
      }

      if (mounted) {
        if (result['isSuccess'] == true) {
          NotificationOverlayManager().showSuccess(
            title: 'Thành công',
            message: _isEditMode ? 'Cập nhật đơn thành công' : 'Tạo đơn nghỉ phép thành công',
          );
          Navigator.pop(context, true);
        } else {
          NotificationOverlayManager().showError(
            title: 'Lỗi',
            message: result['message'] ?? 'Lỗi: không rõ nguyên nhân',
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
