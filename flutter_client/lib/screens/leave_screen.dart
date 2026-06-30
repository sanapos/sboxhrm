import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/paged_load_utils.dart';
import '../utils/store_role_helper.dart';
import '../services/signalr_service.dart';
import '../utils/responsive_helper.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_button.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_scroll_safe.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../widgets/leave_request_form.dart';
import '../features/leave/leave_catalog.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/hrm_pushed_screen_shell.dart';
class LeaveScreen extends StatefulWidget {
  final String? highlightId;
  const LeaveScreen({super.key, this.highlightId});

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  TabController? _tabController;
  StreamSubscription<Map<String, dynamic>>? _notificationSub;
  Timer? _refreshTimer;

  List<dynamic> _myLeaves = [];
  List<dynamic> _allLeaves = [];
  List<dynamic> _pendingLeaves = [];
  List<dynamic> _shifts = [];
  List<dynamic> _employees = [];

  bool _isLoading = false;
  bool _isManager = false;
  bool _initialized = false;
  String? _currentUserId;

  // Filters
  int? _filterLeaveType;
  int? _filterStatus;
  String? _filterEmployeeId;
  String _filterTimePreset = 'all';
  DateTimeRange? _filterDateRange;
  String? _filterBranchId;
  List<Map<String, dynamic>> _branches = [];
  int _currentPage = 1;

  // Sorting
  String _sortColumn = 'createdAt';
  bool _sortAscending = false;
  int _itemsPerPage = 50;
  final List<int> _pageSizeOptions = [25, 50, 100, 200];

  // T?ng quan + b? l?c (?n/hi?n cùng nhau)
  bool _showOverviewPanel = false;
  double? _myAnnualLeaveBalance;
  String? _effectiveHighlightId;
  bool _navExtrasApplied = false;

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
      final role = authProvider.userRole;
      _isManager = StoreRoleHelper.isManagerOrAbove(role);
      _currentUserId = authProvider.user?.id;
      _tabController = TabController(
        length: _isManager ? 3 : 1,
        vsync: this,
      );
      _applyNavigationExtras();
      // Listen for leave-related SignalR notifications to auto-refresh
      _notificationSub = SignalRService().onNewNotification.listen((data) {
        final category = (data['categoryCode'] ?? data['category'] ?? '')
            .toString()
            .toLowerCase();
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

  void _applyNavigationExtras() {
    if (_navExtrasApplied) return;
    _navExtrasApplied = true;
    _effectiveHighlightId = widget.highlightId;
    final fromNotif = NavigationNotifier.notificationHighlightId.value;
    if ((_effectiveHighlightId == null || _effectiveHighlightId!.isEmpty) &&
        fromNotif != null &&
        fromNotif.isNotEmpty) {
      _effectiveHighlightId = fromNotif;
    }
    NavigationNotifier.notificationHighlightId.value = null;

    final leaveTab = NavigationNotifier.leaveInitialTab.value;
    NavigationNotifier.leaveInitialTab.value = -1;
    if (leaveTab >= 0 && _isManager && _tabController != null) {
      final idx = leaveTab.clamp(0, _tabController!.length - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tabController != null) {
          _tabController!.animateTo(idx);
        }
      });
    }
  }

  Future<void> _loadData() async {
    if (_isLoading) return; // Prevent concurrent loads
    setState(() => _isLoading = true);
    try {
      try {
        final shiftsResult = await _apiService.getShifts();
        _shifts = shiftsResult;
      } catch (e) {
        _shifts = [];
      }
      try {
        _employees = await _apiService.getEmployeesForSelect();
      } catch (e) {
        _employees = [];
      }
      try {
        final br = await _apiService.getBranchesForSelect();
        final bd = br['data'];
        if (bd is List && mounted) {
          setState(() => _branches =
              bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
        }
      } catch (_) {}
      try {
        final myResult = await _apiService.getMyLeaves();
        if (myResult['isSuccess'] == true && myResult['data'] != null) {
          final data = myResult['data'];
          _myLeaves = data is List ? data : [];
        }
      } catch (e) {
        _myLeaves = [];
      }
      _myAnnualLeaveBalance = null;
      if (_currentUserId != null) {
        for (final emp in _employees) {
          if (emp['applicationUserId']?.toString() == _currentUserId) {
            final empId = emp['id']?.toString();
            if (empId != null) {
              try {
                final bal = await _apiService.getAnnualLeaveBalance(empId);
                if (bal['isSuccess'] == true && bal['data'] != null) {
                  _myAnnualLeaveBalance =
                      (bal['data']['remainingDays'] as num?)?.toDouble();
                }
              } catch (_) {}
            }
            break;
          }
        }
      }
      if (_isManager) {
        try {
          _allLeaves = await fetchAllPagedMaps(
            (p, s) => _apiService.getAllLeaves(page: p, pageSize: s),
            pageSize: 500,
          );
        } catch (e) {
          _allLeaves = [];
        }
        try {
          _pendingLeaves = await fetchAllPagedMaps(
            (p, s) => _apiService.getPendingLeaves(page: p, pageSize: s),
            pageSize: 500,
          );
        } catch (e) {
          _pendingLeaves = [];
        }
      }
    } catch (e) {
      debugPrint('Error loading leave data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _maybeOpenHighlight();
    }
  }

  bool _highlightOpened = false;
  void _maybeOpenHighlight() {
    if (_highlightOpened) return;
    final id = _effectiveHighlightId ?? widget.highlightId;
    if (id == null || id.isEmpty) return;
    dynamic match;
    bool isAllTab = false;
    bool showApprovalActions = false;
    bool isMyLeaves = false;
    bool idMatch(Map l) {
      final sid = id.toString();
      return l['id']?.toString() == sid || l['Id']?.toString() == sid;
    }
    for (final l in _pendingLeaves) {
      if (l is Map && idMatch(l)) {
        match = l;
        showApprovalActions = true;
        break;
      }
    }
    if (match == null) {
      for (final l in _allLeaves) {
        if (l is Map && idMatch(l)) {
          match = l;
          isAllTab = true;
          break;
        }
      }
    }
    if (match == null) {
      for (final l in _myLeaves) {
        if (l is Map && idMatch(l)) {
          match = l;
          isMyLeaves = true;
          break;
        }
      }
    }
    if (match == null) return;
    _highlightOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showLeaveDetailDialog(match,
          isMyLeaves: isMyLeaves,
          showApprovalActions: showApprovalActions,
          isAllTab: isAllTab);
    });
  }

  static int _normalizeStatus(dynamic status) {
    if (status is int) return status;
    final s = status?.toString().toLowerCase() ?? '';
    switch (s) {
      case 'pending':
      case '0':
        return 0;
      case 'approved':
      case '1':
        return 1;
      case 'rejected':
      case '2':
        return 2;
      case 'cancelled':
      case 'canceled':
      case '3':
        return 3;
      default:
        return -1;
    }
  }

  static int _normalizeLeaveType(dynamic type) {
    if (type is int) return type;
    final s = type?.toString().toLowerCase() ?? '';
    switch (s) {
      case 'annualleave':
      case 'annual':
      case '0':
        return 0;
      case 'holiday':
      case '1':
        return 1;
      case 'personalpaid':
      case '2':
        return 2;
      case 'personalunpaid':
      case '3':
        return 3;
      case 'sickleave':
      case 'sick':
      case '4':
        return 4;
      case 'maternityleave':
      case 'maternity':
      case '5':
        return 5;
      case 'compensatoryleave':
      case 'compensatory':
      case '6':
        return 6;
      case 'longtermleave':
      case 'longterm':
      case '7':
        return 7;
      default:
        return -1;
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
      if (_filterBranchId != null) {
        final empId = leave['employeeId']?.toString();
        final emp = _employees.firstWhere(
          (e) => e['id']?.toString() == empId,
          orElse: () => <String, dynamic>{},
        );
        if ((emp as Map).isEmpty ||
            emp['branchId']?.toString() != _filterBranchId) {
          return false;
        }
      }
      if (_filterLeaveType != null &&
          _normalizeLeaveType(leave['type']) != _filterLeaveType) {
        return false;
      }
      if (_filterStatus != null &&
          _normalizeStatus(leave['status']) != _filterStatus) {
        return false;
      }
      if (_filterEmployeeId != null && _filterEmployeeId!.isNotEmpty) {
        final empName = (leave['employeeName'] ?? '').toString().toLowerCase();
        if (!empName.contains(_filterEmployeeId!.toLowerCase())) return false;
      }
      if (_filterDateRange != null) {
        final start = parseApiCalendarDate(leave['startDate']);
        final end = parseApiCalendarDate(leave['endDate']);
        if (start == null || end == null) return false;
        if (end.isBefore(_filterDateRange!.start) ||
            start.isAfter(_filterDateRange!.end)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // ---------------------------------------------------
  // BUILD
  // ---------------------------------------------------
  /// One tab: loading spinner, or list (mobile uses plain ListView — no NestedScrollView).
  Widget _buildLeaveTabContent(
    List<dynamic> leaves, {
    bool isMyLeaves = false,
    bool showApprovalActions = false,
    bool isAllTab = false,
  }) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: Theme.of(context).primaryColor),
      );
    }
    return _buildLeaveList(
      leaves,
      isMyLeaves: isMyLeaves,
      showApprovalActions: showApprovalActions,
      isAllTab: isAllTab,
    );
  }

  Widget _leaveMobileListScroll({required List<Widget> children}) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: children,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = Responsive.isMobile(context);

    if (_tabController == null) {
      return Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Center(
          child: CircularProgressIndicator(color: theme.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: HrmPushedScreenShell.maybeWrap(
        context,
        title: _l10n.leaveManagement,
        child: Column(
        children: [
          _buildHeader(theme),
          if (!isMobile) _buildTabBar(theme),
          Expanded(
            child: isMobile
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: _leavePageHeaderSections(theme),
                            ),
                          ),
                        ),
                        _leaveTabBar(theme),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildLeaveTabContent(
                                _applyFilters(_myLeaves),
                                isMyLeaves: true,
                              ),
                              if (_isManager) ...[
                                _buildLeaveTabContent(
                                  _applyFilters(_pendingLeaves),
                                  showApprovalActions: true,
                                ),
                                _buildLeaveTabContent(
                                  _applyFilters(_allLeaves),
                                  isAllTab: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(
                      children: [
                        _buildOverviewSection(theme),
                        const SizedBox(height: 12),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildLeaveTabContent(
                                _applyFilters(_myLeaves),
                                isMyLeaves: true,
                              ),
                              if (_isManager) ...[
                                _buildLeaveTabContent(
                                  _applyFilters(_pendingLeaves),
                                  showApprovalActions: true,
                                ),
                                _buildLeaveTabContent(
                                  _applyFilters(_allLeaves),
                                  isAllTab: true,
                                ),
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
      ),
    );
  }

  List<Widget> _leavePageHeaderSections(ThemeData theme) => [
        _buildOverviewSection(theme),
        const SizedBox(height: 12),
      ];

  Widget _buildOverviewSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _showOverviewPanel = !_showOverviewPanel),
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
                Text('T?ng quan & b? l?c',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.blue.shade700)),
                const Spacer(),
                Icon(
                    _showOverviewPanel
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 20,
                    color: Colors.blue.shade700),
              ],
            ),
          ),
        ),
        if (_showOverviewPanel) ...[
          const SizedBox(height: 8),
          _buildStatsRow(theme),
          const SizedBox(height: 10),
          _buildFilterBar(theme),
        ],
      ],
    );
  }

  TabBar _leaveTabBar(ThemeData theme) {
    return TabBar(
      controller: _tabController,
      tabAlignment: TabAlignment.fill,
      labelColor: theme.primaryColor,
      unselectedLabelColor: Colors.grey,
      indicatorColor: theme.primaryColor,
      indicatorWeight: 3,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      tabs: [
        Tab(
            icon: const Icon(Icons.person_outline_rounded, size: 20),
            text: _l10n.myRequests),
        if (_isManager) ...[
          Tab(
            icon: Badge(
              label: Text('${_pendingLeaves.length}',
                  style: const TextStyle(fontSize: 10)),
              isLabelVisible: _pendingLeaves.isNotEmpty,
              backgroundColor: Colors.red,
              child: const Icon(Icons.pending_actions_rounded, size: 20),
            ),
            text: _l10n.pending,
          ),
          Tab(
              icon: const Icon(Icons.list_alt_rounded, size: 20),
              text: _l10n.all),
        ],
      ],
    );
  }

  // ---------------------------------------------------
  // HEADER
  // ---------------------------------------------------
  Widget _buildHeader(ThemeData theme) {
    final primary = theme.primaryColor;
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18,
          isMobile ? 14 : 24, isMobile ? 12 : 14),
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
            child: Icon(Icons.event_busy_rounded,
                size: isMobile ? 18 : 22, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _l10n.leaveManagement,
                  style: TextStyle(
                      fontSize: isMobile ? 16 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                if (!isMobile)
                  Text(
                    _l10n.leaveSubtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8)),
                  ),
                if (_myAnnualLeaveBalance != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Phép nam còn: ${_myAnnualLeaveBalance!.toStringAsFixed(_myAnnualLeaveBalance!.truncateToDouble() == _myAnnualLeaveBalance ? 0 : 1)} ngày',
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6EE7B7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showLeaveLegalGuide,
            icon: const Icon(Icons.menu_book_rounded, color: Colors.white),
            tooltip: 'Quy d?nh ngh? phép',
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => _showLeaveFormDialog(),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 12 : 16,
                    vertical: isMobile ? 8 : 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded,
                        size: isMobile ? 18 : 20, color: Colors.white),
                    if (!isMobile) ...[
                      const SizedBox(width: 6),
                      Text(_l10n.createRequest,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13))
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // STATS ROW
  // ---------------------------------------------------
  Widget _buildStatsRow(ThemeData theme) {
    final source = _isManager ? _allLeaves : _myLeaves;
    final pending =
        source.where((l) => _normalizeStatus(l['status']) == 0).length;
    final approved =
        source.where((l) => _normalizeStatus(l['status']) == 1).length;
    final rejected =
        source.where((l) => _normalizeStatus(l['status']) == 2).length;
    final annual =
        source.where((l) => _normalizeLeaveType(l['type']) == 0).length;
    final holiday =
        source.where((l) => _normalizeLeaveType(l['type']) == 1).length;
    final personalPaid =
        source.where((l) => _normalizeLeaveType(l['type']) == 2).length;

    final cards = [
      _buildStatCard(_l10n.pending, '$pending', Icons.hourglass_bottom_rounded,
          Colors.orange),
      _buildStatCard(_l10n.approved, '$approved', Icons.check_circle_rounded,
          Colors.green),
      _buildStatCard(
          _l10n.rejected, '$rejected', Icons.cancel_rounded, Colors.red),
      _buildStatCard(
          'Phép nam', '$annual', Icons.beach_access_rounded, Colors.teal),
      _buildStatCard('L? t?t', '$holiday', Icons.celebration_rounded,
          const Color(0xFFF59E0B)),
      _buildStatCard(
          'Có luong', '$personalPaid', Icons.paid_rounded, Colors.blue),
    ];

    if (Responsive.isMobile(context)) {
      return HrmPageChrome.horizontalStatCards(
        cards: cards,
        minCardWidth: 108,
        gap: 8,
      );
    }

    return Row(
      children: cards
          .expand((c) => [Expanded(child: c), const SizedBox(width: 8)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return HrmStatSummaryCard(
      icon: icon,
      value: value,
      label: label,
      color: color,
    );
  }

  // ---------------------------------------------------
  // TAB BAR
  // ---------------------------------------------------
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
          Tab(
              icon: const Icon(Icons.person_outline_rounded, size: 20),
              text: _l10n.myRequests),
          if (_isManager) ...[
            Tab(
              icon: Badge(
                label: Text('${_pendingLeaves.length}',
                    style: const TextStyle(fontSize: 10)),
                isLabelVisible: _pendingLeaves.isNotEmpty,
                backgroundColor: Colors.red,
                child: const Icon(Icons.pending_actions_rounded, size: 20),
              ),
              text: _l10n.pending,
            ),
            Tab(
                icon: const Icon(Icons.list_alt_rounded, size: 20),
                text: _l10n.all),
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
        range = DateTimeRange(
            start: today,
            end: DateTime(today.year, today.month, today.day, 23, 59, 59));
        break;
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        range = DateTimeRange(
            start: yesterday,
            end: DateTime(
                yesterday.year, yesterday.month, yesterday.day, 23, 59, 59));
        break;
      case 'this_week':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        range = DateTimeRange(
            start: weekStart,
            end: DateTime(today.year, today.month, today.day, 23, 59, 59));
        break;
      case 'last_week':
        final thisWeekStart = today.subtract(Duration(days: today.weekday - 1));
        final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
        final lastWeekEnd = thisWeekStart.subtract(const Duration(days: 1));
        range = DateTimeRange(
            start: lastWeekStart,
            end: DateTime(lastWeekEnd.year, lastWeekEnd.month, lastWeekEnd.day,
                23, 59, 59));
        break;
      case 'this_month':
        final monthStart = DateTime(today.year, today.month, 1);
        range = DateTimeRange(
            start: monthStart,
            end: DateTime(today.year, today.month, today.day, 23, 59, 59));
        break;
      case 'last_month':
        final lastMonthStart = DateTime(today.year, today.month - 1, 1);
        final lastMonthEnd = DateTime(today.year, today.month, 0);
        range = DateTimeRange(
            start: lastMonthStart,
            end: DateTime(lastMonthEnd.year, lastMonthEnd.month,
                lastMonthEnd.day, 23, 59, 59));
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
            end: DateTime(
                picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
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

  // ---------------------------------------------------
  // FILTER BAR (3 hàng × 2 chip)
  // ---------------------------------------------------
  static const _leaveTypeLabels = <int, String>{
    0: 'Phép nam',
    1: 'L? t?t',
    2: 'VR có luong',
    3: 'VR không luong',
    4: '?m dau',
    5: 'Thai s?n',
    6: 'Ngh? bù',
    7: 'Ngh? dài h?n',
  };

  String _filterLeaveTypeLabel() {
    if (_filterLeaveType == null) return _l10n.allTypes;
    return _leaveTypeLabels[_filterLeaveType] ?? _l10n.allTypes;
  }

  String _filterStatusLabel() {
    switch (_filterStatus) {
      case 0:
        return _l10n.pending;
      case 1:
        return _l10n.approved;
      case 2:
        return _l10n.rejected;
      case 3:
        return _l10n.cancelled;
      default:
        return _l10n.allStatus;
    }
  }

  String _filterTimeLabel() {
    switch (_filterTimePreset) {
      case 'today':
        return _l10n.today;
      case 'yesterday':
        return _l10n.yesterday;
      case 'this_week':
        return _l10n.thisWeek;
      case 'last_week':
        return _l10n.lastWeek;
      case 'this_month':
        return _l10n.thisMonth;
      case 'last_month':
        return _l10n.lastMonth;
      case 'custom':
        if (_filterDateRange != null) {
          final f = DateFormat('dd/MM');
          return '${f.format(_filterDateRange!.start)}–${f.format(_filterDateRange!.end)}';
        }
        return _l10n.custom;
      default:
        return 'Toàn b?';
    }
  }

  String _filterBranchLabel() {
    if (_filterBranchId == null) return _l10n.all;
    for (final b in _branches) {
      if (b['id']?.toString() == _filterBranchId) {
        return b['name']?.toString() ?? _l10n.all;
      }
    }
    return _l10n.all;
  }

  String _filterEmployeeLabel() {
    final q = _filterEmployeeId?.trim();
    if (q == null || q.isEmpty) return 'T?t c? NV';
    return q.length > 22 ? '${q.substring(0, 22)}…' : q;
  }

  void _clearAllFilters() {
    setState(() {
      _filterLeaveType = null;
      _filterStatus = null;
      _filterEmployeeId = null;
      _filterTimePreset = 'all';
      _filterDateRange = null;
      _filterBranchId = null;
      _currentPage = 1;
    });
  }

  Future<void> _showFilterOptionsSheet({
    required String title,
    required List<({String label, VoidCallback onPick})> options,
  }) async {
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ...options.map(
              (o) => ListTile(
                title: Text(o.label, style: const TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  o.onPick();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFilterEmployee() async {
    final picked = await showAppSheet<String?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final query = ValueNotifier<String>('');
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (_, scroll) => ValueListenableBuilder<String>(
            valueListenable: query,
            builder: (_, q, __) {
              final lower = q.toLowerCase();
              final list = _employees.where((emp) {
                if (lower.isEmpty) return true;
                final name =
                    '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                        .toLowerCase();
                final code =
                    (emp['employeeCode'] ?? '').toString().toLowerCase();
                return name.contains(lower) || code.contains(lower);
              }).take(80);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: _l10n.searchEmployee,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        isDense: true,
                      ),
                      onChanged: (v) => query.value = v,
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scroll,
                      children: [
                        ListTile(
                          title: const Text('T?t c? nhân viên'),
                          onTap: () => Navigator.pop(ctx, ''),
                        ),
                        ...list.map((emp) {
                          final name =
                              '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                                  .trim();
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(
                                emp['employeeCode']?.toString() ?? '',
                                style: const TextStyle(fontSize: 12)),
                            onTap: () => Navigator.pop(ctx, name),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      _filterEmployeeId = picked.isEmpty ? null : picked;
      _currentPage = 1;
    });
  }

  Widget _buildFilterChipRow(List<Widget> chips) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: chips[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
    bool active = false,
    Color? accentColor,
  }) {
    final accent = accentColor ?? Theme.of(context).primaryColor;
    final isActive = active;
    return Material(
      color: isActive ? accent.withValues(alpha: 0.08) : const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? accent.withValues(alpha: 0.45) : const Color(0xFFE4E4E7),
              width: isActive ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: isActive ? accent : Colors.grey[500]),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.expand_more,
                        size: 16, color: Colors.grey[500]),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  color: isActive ? accent : const Color(0xFF18181B),
                ),
                maxLines: 2,
                softWrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    final hasFilters = _filterLeaveType != null ||
        _filterStatus != null ||
        (_filterEmployeeId != null && _filterEmployeeId!.isNotEmpty) ||
        _filterDateRange != null ||
        _filterBranchId != null ||
        _filterTimePreset != 'all';

    final orderCount = (_isManager ? _allLeaves : _myLeaves).length;
    final pad = Responsive.isMobile(context) ? 10.0 : 14.0;

    final chipType = _buildFilterChip(
      title: 'Lo?i ngh?',
      value: _filterLeaveTypeLabel(),
      icon: Icons.category_rounded,
      active: _filterLeaveType != null,
      onTap: () => _showFilterOptionsSheet(
        title: 'Lo?i ngh?',
        options: [
          (label: _l10n.allTypes, onPick: () => setState(() {
                _filterLeaveType = null;
                _currentPage = 1;
              })),
          ..._leaveTypeLabels.entries.map(
            (e) => (
              label: e.value,
              onPick: () => setState(() {
                _filterLeaveType = e.key;
                _currentPage = 1;
              }),
            ),
          ),
        ],
      ),
    );

    final chipStatus = _buildFilterChip(
      title: 'Tr?ng thái',
      value: _filterStatusLabel(),
      icon: Icons.flag_rounded,
      active: _filterStatus != null,
      onTap: () => _showFilterOptionsSheet(
        title: 'Tr?ng thái',
        options: [
          (label: _l10n.allStatus, onPick: () => setState(() {
                _filterStatus = null;
                _currentPage = 1;
              })),
          (label: _l10n.pending, onPick: () => setState(() {
                _filterStatus = 0;
                _currentPage = 1;
              })),
          (label: _l10n.approved, onPick: () => setState(() {
                _filterStatus = 1;
                _currentPage = 1;
              })),
          (label: _l10n.rejected, onPick: () => setState(() {
                _filterStatus = 2;
                _currentPage = 1;
              })),
          (label: _l10n.cancelled, onPick: () => setState(() {
                _filterStatus = 3;
                _currentPage = 1;
              })),
        ],
      ),
    );

    final chipTime = _buildFilterChip(
      title: 'Th?i gian',
      value: _filterTimeLabel(),
      icon: Icons.date_range_rounded,
      active: _filterTimePreset != 'all',
      onTap: () => _showFilterOptionsSheet(
        title: 'Th?i gian',
        options: [
          (label: 'Toàn b?', onPick: () => _applyTimePreset('all')),
          (label: _l10n.today, onPick: () => _applyTimePreset('today')),
          (label: _l10n.yesterday, onPick: () => _applyTimePreset('yesterday')),
          (label: _l10n.thisWeek, onPick: () => _applyTimePreset('this_week')),
          (label: _l10n.lastWeek, onPick: () => _applyTimePreset('last_week')),
          (label: _l10n.thisMonth, onPick: () => _applyTimePreset('this_month')),
          (label: _l10n.lastMonth, onPick: () => _applyTimePreset('last_month')),
          (label: _l10n.custom, onPick: () => _applyTimePreset('custom')),
        ],
      ),
    );

    final chipBranchOrCount = _branches.isNotEmpty
        ? _buildFilterChip(
            title: 'Chi nhánh',
            value: _filterBranchLabel(),
            icon: Icons.account_tree_outlined,
            active: _filterBranchId != null,
            onTap: () => _showFilterOptionsSheet(
              title: 'Chi nhánh',
              options: [
                (label: _l10n.all, onPick: () => setState(() {
                      _filterBranchId = null;
                      _currentPage = 1;
                    })),
                ..._branches.map(
                  (b) => (
                    label: b['name']?.toString() ?? '',
                    onPick: () => setState(() {
                      _filterBranchId = b['id']?.toString();
                      _currentPage = 1;
                    }),
                  ),
                ),
              ],
            ),
          )
        : _buildFilterChip(
            title: 'S? don',
            value: '$orderCount don',
            icon: Icons.analytics_outlined,
            accentColor: theme.primaryColor,
            onTap: null,
          );

    final chipEmployeeOrBalance = _isManager
        ? _buildFilterChip(
            title: 'Nhân viên',
            value: _filterEmployeeLabel(),
            icon: Icons.person_search_rounded,
            active: _filterEmployeeId != null && _filterEmployeeId!.isNotEmpty,
            onTap: _pickFilterEmployee,
          )
        : _buildFilterChip(
            title: 'Phép nam',
            value: _myAnnualLeaveBalance != null
                ? 'Còn ${_myAnnualLeaveBalance!.toStringAsFixed(_myAnnualLeaveBalance!.truncateToDouble() == _myAnnualLeaveBalance ? 0 : 1)} ngày'
                : '—',
            icon: Icons.beach_access_rounded,
            accentColor: const Color(0xFF059669),
            onTap: null,
          );

    final chipClear = _buildFilterChip(
      title: 'B? l?c',
      value: hasFilters ? _l10n.clearFilter : 'Chua l?c',
      icon: Icons.filter_alt_off,
      accentColor: Colors.red.shade700,
      active: hasFilters,
      onTap: hasFilters ? _clearAllFilters : null,
    );

    return HrmFilterBar(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
      children: [
        _buildFilterChipRow([chipType, chipStatus]),
        const SizedBox(height: 8),
        _buildFilterChipRow([chipTime, chipBranchOrCount]),
        const SizedBox(height: 8),
        _buildFilterChipRow([chipEmployeeOrBalance, chipClear]),
      ],
    );
  }

  // ---------------------------------------------------
  // LEAVE LIST (table-based)
  // ---------------------------------------------------
  Widget _buildLeaveList(
    List<dynamic> leaves, {
    bool isMyLeaves = false,
    bool showApprovalActions = false,
    bool isAllTab = false,
  }) {
    if (leaves.isEmpty) {
      final emptyContent = Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy_outlined, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              showApprovalActions
                  ? _l10n.noPendingRequests
                  : _l10n.noLeaveRequests,
              style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text('Các don ngh? phép s? hi?n th? t?i dây',
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
            if (isMyLeaves) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _showLeaveFormDialog(),
                icon: const Icon(Icons.add_rounded),
                label: Text(_l10n.createNewRequest),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      );
      if (Responsive.isMobile(context)) {
        return _leaveMobileListScroll(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.32,
              child: emptyContent,
            ),
          ],
        );
      }
      return emptyContent;
    }

    final totalPages = (leaves.length / _itemsPerPage).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;

    // Sort
    leaves.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'startDate':
          final da = parseApiCalendarDate(a['startDate']);
          final db = parseApiCalendarDate(b['startDate']);
          cmp = (da ?? DateTime(2000)).compareTo(db ?? DateTime(2000));
          break;
        case 'createdAt':
        default:
          final da = parseApiUtcDateTime(a['createdAt']);
          final db = parseApiUtcDateTime(b['createdAt']);
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
          final cards = <Widget>[
            for (var index = 0; index < pageLeaves.length; index++)
              Padding(
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
                    pageLeaves[index] is Map<String, dynamic>
                        ? pageLeaves[index] as Map<String, dynamic>
                        : Map<String, dynamic>.from(pageLeaves[index]),
                    isMyLeaves: isMyLeaves,
                    showApprovalActions: showApprovalActions,
                    isAllTab: isAllTab,
                  ),
                ),
              ),
            if (totalPages > 1) _buildMobilePagination(leaves),
          ];
          return _leaveMobileListScroll(children: cards);
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
                        constraints:
                            BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          sortColumnIndex: _sortColumn == 'startDate'
                              ? 3
                              : (_sortColumn == 'createdAt' ? 9 : null),
                          sortAscending: _sortAscending,
                          headingRowColor:
                              WidgetStateProperty.all(const Color(0xFFFAFAFA)),
                          headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Color(0xFF71717A)),
                          dataTextStyle: const TextStyle(
                              fontSize: 13, color: Color(0xFF18181B)),
                          columnSpacing: 16,
                          horizontalMargin: 16,
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 60,
                          columns: [
                            const DataColumn(
                                label:
                                    Text('STT', textAlign: TextAlign.center)),
                            DataColumn(label: Text(_l10n.employee)),
                            DataColumn(label: Text(_l10n.leaveType)),
                            DataColumn(
                                label: Text(_l10n.leaveDays),
                                onSort: (_, asc) => setState(() {
                                      _sortColumn = 'startDate';
                                      _sortAscending = asc;
                                      _currentPage = 1;
                                    })),
                            DataColumn(label: Text(_l10n.shiftLabel)),
                            DataColumn(label: Text(_l10n.halfShift)),
                            const DataColumn(label: Text('NV thay ca')),
                            DataColumn(label: Text(_l10n.reason)),
                            DataColumn(label: Text(_l10n.status)),
                            DataColumn(
                                label: Text(_l10n.createdAt),
                                onSort: (_, asc) => setState(() {
                                      _sortColumn = 'createdAt';
                                      _sortAscending = asc;
                                      _currentPage = 1;
                                    })),
                            const DataColumn(label: Text('Thao tác')),
                          ],
                          rows: List.generate(pageLeaves.length, (index) {
                            final leave = pageLeaves[index]
                                    is Map<String, dynamic>
                                ? pageLeaves[index] as Map<String, dynamic>
                                : Map<String, dynamic>.from(pageLeaves[index]);
                            final globalIdx = startIdx + index;
                            final status = _normalizeStatus(leave['status']);
                            final leaveType =
                                _normalizeLeaveType(leave['type']);
                            final statusInfo = _getStatusInfo(status);
                            final typeInfo = _getLeaveTypeInfoFromLeave(
                                Map<String, dynamic>.from(leave as Map));
                            final startDate =
                                parseApiCalendarDate(leave['startDate']);
                            final endDate =
                                parseApiCalendarDate(leave['endDate']);
                            final isHalfShift = leave['isHalfShift'] == true;
                            final empName = leave['employeeName'] ?? 'N/A';
                            final reason = leave['reason'] ?? '';
                            final shiftName =
                                leave['shiftName']?.toString() ?? '';
                            final shiftNamesInList =
                                (leave['shiftNames'] as List?)
                                        ?.map((e) => e.toString())
                                        .where((s) => s.isNotEmpty)
                                        .toList() ??
                                    [];
                            final displayShift = shiftNamesInList.isNotEmpty
                                ? shiftNamesInList.join(', ')
                                : shiftName;
                            final replacementName =
                                leave['replacementEmployeeName']?.toString() ??
                                    '';
                            final createdAt =
                                parseApiUtcDateTime(leave['createdAt']);

                            String dateDisplay = 'N/A';
                            if (startDate != null) {
                              if (endDate != null &&
                                  endDate.difference(startDate).inDays > 0) {
                                dateDisplay =
                                    '${DateFormat('dd/MM/yyyy').format(startDate)} ? ${DateFormat('dd/MM/yyyy').format(endDate)}';
                              } else {
                                dateDisplay =
                                    DateFormat('dd/MM/yyyy').format(startDate);
                              }
                            }

                            return DataRow(
                              onSelectChanged: (_) => _showLeaveDetailDialog(
                                  leave,
                                  isMyLeaves: isMyLeaves,
                                  showApprovalActions: showApprovalActions,
                                  isAllTab: isAllTab),
                              cells: [
                                DataCell(
                                    Center(child: Text('${globalIdx + 1}'))),
                                DataCell(Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 130),
                                    child: Text(empName,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                )),
                                DataCell(Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          typeInfo.color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(typeInfo.label,
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: typeInfo.color)),
                                  ),
                                )),
                                DataCell(Center(
                                    child: Text(dateDisplay,
                                        style: const TextStyle(fontSize: 12)))),
                                DataCell(Center(
                                    child: Text(
                                        displayShift.isNotEmpty
                                            ? displayShift
                                            : '-',
                                        style: const TextStyle(fontSize: 12)))),
                                DataCell(Center(
                                    child: isHalfShift
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                                color: Colors.purple
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(4)),
                                            child: const Text('½',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.purple,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          )
                                        : const Text('-'))),
                                DataCell(Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 120),
                                    child: Text(
                                        replacementName.isNotEmpty
                                            ? replacementName
                                            : '-',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12)),
                                  ),
                                )),
                                DataCell(Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 150),
                                    child: Tooltip(
                                      message: reason,
                                      child: Text(
                                          reason.isNotEmpty ? reason : '-',
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                )),
                                DataCell(Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: statusInfo.color
                                              .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(statusInfo.icon,
                                                size: 12,
                                                color: statusInfo.color),
                                            const SizedBox(width: 4),
                                            Text(statusInfo.label,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: statusInfo.color)),
                                          ],
                                        ),
                                      ),
                                      if ((leave['totalApprovalLevels'] ?? 1) >
                                          1)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '${leave['currentApprovalStep'] ?? 0}/${leave['totalApprovalLevels']} c?p',
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade600),
                                          ),
                                        ),
                                    ],
                                  ),
                                )),
                                DataCell(Center(
                                    child: Text(
                                        createdAt != null
                                            ? formatApiDateTime(
                                                createdAt,
                                                pattern: 'dd/MM/yyyy',
                                              )
                                            : '-',
                                        style: const TextStyle(fontSize: 12)))),
                                DataCell(Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: _buildActionButtons(
                                        leave,
                                        status,
                                        isMyLeaves,
                                        showApprovalActions,
                                        isAllTab),
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
              'Hi?n th? ${startIndex + 1}-$endIndex / $totalItems',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500),
            ),
            Row(
              children: [
                Text('Hi?n th?:',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                          .map((size) => DropdownMenuItem(
                              value: size, child: Text('$size')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _itemsPerPage = v;
                            _currentPage = 1;
                          });
                        }
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
            _buildPageNavBtn(Icons.first_page, _currentPage > 1,
                () => setState(() => _currentPage = 1)),
            _buildPageNavBtn(Icons.chevron_left, _currentPage > 1,
                () => setState(() => _currentPage--)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$_currentPage / $totalPages',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
            ),
            const SizedBox(width: 8),
            _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages,
                () => setState(() => _currentPage++)),
            _buildPageNavBtn(Icons.last_page, _currentPage < totalPages,
                () => setState(() => _currentPage = totalPages)),
          ],
        );
        if (isMobile) {
          return Column(
              children: [infoRow, const SizedBox(height: 8), pageNav]);
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
          child: Icon(icon,
              size: 20,
              color:
                  enabled ? Theme.of(context).primaryColor : Colors.grey[400]),
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
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
              ),
              Row(
                children: [
                  _buildPageNavBtn(Icons.chevron_left, _currentPage > 1,
                      () => setState(() => _currentPage--)),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_currentPage / $totalPages',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildPageNavBtn(
                      Icons.chevron_right,
                      _currentPage < totalPages,
                      () => setState(() => _currentPage++)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------
  // LEAVE CARD — 3 dòng (tên · lo?i · ngày ngh?)
  // ---------------------------------------------------
  String _formatLeaveDateLine(
    DateTime? startDate,
    DateTime? endDate, {
    required bool isHalfShift,
  }) {
    if (startDate == null) return 'Chua có ngày ngh?';
    final fmt = DateFormat('dd/MM/yyyy');
    final startStr = fmt.format(startDate);
    final effectiveEnd = endDate ?? startDate;
    final dayCount = effectiveEnd.difference(startDate).inDays + 1;
    final halfNote = isHalfShift ? ' · n?a ca' : '';

    if (dayCount <= 1) {
      return '$startStr · 1 ngày$halfNote';
    }
    return '$startStr ? ${fmt.format(effectiveEnd)} · $dayCount ngày$halfNote';
  }

  Widget _buildLeaveStatusChip(_StatusInfo statusInfo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: statusInfo.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        statusInfo.label,
        style: TextStyle(
          color: statusInfo.color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _buildLeaveDeckItem(
    Map<String, dynamic> leave, {
    bool isMyLeaves = false,
    bool showApprovalActions = false,
    bool isAllTab = false,
  }) {
    final status = _normalizeStatus(leave['status']);
    final statusInfo = _getStatusInfo(status);
    final typeInfo = _getLeaveTypeInfoFromLeave(leave);
    final startDate = parseApiCalendarDate(leave['startDate']);
    final endDate = parseApiCalendarDate(leave['endDate']);
    final isHalfShift = leave['isHalfShift'] == true;
    final dateLine = _formatLeaveDateLine(startDate, endDate,
        isHalfShift: isHalfShift);

    final empName = (leave['employeeName'] ?? '').toString().trim();
    final line1Title =
        empName.isNotEmpty && empName != 'N/A' ? empName : typeInfo.label;

    final approvalLevels = (leave['totalApprovalLevels'] as num?)?.toInt() ?? 1;
    final approvalStep = (leave['currentApprovalStep'] as num?)?.toInt() ?? 0;
    final showActions = _shouldShowActions(
        status, isMyLeaves, showApprovalActions, isAllTab);

    void openDetail() => _showLeaveDetailDialog(leave,
        isMyLeaves: isMyLeaves,
        showApprovalActions: showApprovalActions,
        isAllTab: isAllTab);

    return InkWell(
      onTap: openDetail,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: typeInfo.color.withValues(alpha: 0.12),
              child: Icon(typeInfo.icon, size: 18, color: typeInfo.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dòng 1 — nhân viên + tr?ng thái
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          line1Title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            height: 1.3,
                            color: Color(0xFF18181B),
                          ),
                          maxLines: 2,
                          softWrap: true,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildLeaveStatusChip(statusInfo),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Dòng 2 — lo?i ngh?
                  Text(
                    typeInfo.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: typeInfo.color,
                    ),
                    maxLines: 2,
                    softWrap: true,
                  ),
                  const SizedBox(height: 5),
                  // Dòng 3 — ngày xin ngh? (d? dd/MM/yyyy)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.date_range_rounded,
                            size: 15, color: Colors.grey[600]),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dateLine,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            color: Colors.grey[700],
                          ),
                          maxLines: 2,
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                  if (approvalLevels > 1) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Duy?t $approvalStep/$approvalLevels c?p',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showActions)
                  InkWell(
                    onTap: () {
                      final actions = _buildActionButtons(leave, status,
                          isMyLeaves, showApprovalActions, isAllTab);
                      if (actions.isNotEmpty) openDetail();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.more_horiz,
                          size: 20, color: Color(0xFF71717A)),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right,
                      size: 20, color: Color(0xFF71717A)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowActions(
      int status, bool isMyLeaves, bool showApprovalActions, bool isAllTab) {
    final isPending = status == 0;
    // My leaves: show for pending (edit/cancel/delete)
    if (isMyLeaves && isPending) return true;
    // All tab: show for all statuses (pending: edit/cancel/approve/reject/delete; approved/rejected: undo/delete)
    if (isAllTab) return true;
    // Pending tab: show for pending with approval actions
    if (isPending && showApprovalActions) return true;
    return false;
  }

  List<Widget> _buildActionButtons(Map<String, dynamic> leave, int status,
      bool isMyLeaves, bool showApprovalActions, bool isAllTab) {
    final isPending = status == 0;
    final buttons = <Widget>[];
    final permProv = Provider.of<PermissionProvider>(context, listen: false);

    // Only allow edit when status is Pending (0)
    if (isPending && (isMyLeaves || isAllTab) && permProv.canEdit('Leave')) {
      buttons.add(_ActionBtn(
          icon: Icons.edit_rounded,
          label: 'S?a',
          color: Colors.blue,
          onTap: () => _showLeaveFormDialog(leave: leave)));
      buttons.add(const SizedBox(width: 6));
    }

    // Cancel: employee can cancel own pending, manager can cancel any pending
    if (isPending) {
      if (isMyLeaves ||
          (isAllTab && _isManager) ||
          (showApprovalActions && _isManager)) {
        buttons.add(_ActionBtn(
            icon: Icons.cancel_outlined,
            label: 'H?y',
            color: Colors.red,
            onTap: () => _cancelLeave(leave['id'])));
        buttons.add(const SizedBox(width: 6));
      }
    }

    // Approve/Reject: manager on pending tab or all tab, but NOT own leave
    final leaveOwnerId = leave['employeeUserId']?.toString() ??
        leave['userId']?.toString() ??
        '';
    if (isPending &&
        (showApprovalActions || isAllTab) &&
        permProv.canApprove('Leave') &&
        leaveOwnerId != _currentUserId) {
      buttons.add(_ActionBtn(
          icon: Icons.check_circle_outline,
          label: 'Duy?t',
          color: Colors.green,
          onTap: () => _approveLeave(
              leave['id']?.toString(),
              Map<String, dynamic>.from(leave as Map))));
      buttons.add(const SizedBox(width: 6));
      buttons.add(_ActionBtn(
          icon: Icons.highlight_off,
          label: 'T? ch?i',
          color: Colors.red,
          onTap: () => _rejectLeave(leave['id'])));
      buttons.add(const SizedBox(width: 6));
    }

    // Undo: manager on all tab for approved/rejected
    if ((isAllTab || showApprovalActions) &&
        _isManager &&
        (status == 1 || status == 2)) {
      buttons.add(_ActionBtn(
          icon: Icons.undo_rounded,
          label: 'Hoàn tác',
          color: Colors.orange,
          onTap: () => _undoLeaveApproval(leave['id'])));
      buttons.add(const SizedBox(width: 6));
    }

    // Delete: có quy?n xóa module — NV xóa don pending c?a mình; QL xóa trên tab qu?n lý
    final canDeleteLeave = permProv.canDelete('Leave');
    if (canDeleteLeave &&
        ((isMyLeaves && isPending) ||
            isAllTab ||
            showApprovalActions ||
            permProv.canApprove('Leave'))) {
      buttons.add(_ActionBtn(
          icon: Icons.delete_forever_outlined,
          label: 'Xóa',
          color: Colors.red.shade700,
          onTap: () => _forceDeleteLeave(leave['id'])));
    }

    return buttons;
  }

  // ---------------------------------------------------
  // DETAIL DIALOG
  // ---------------------------------------------------
  void _showLeaveDetailDialog(Map<String, dynamic> leave,
      {bool isMyLeaves = false,
      bool showApprovalActions = false,
      bool isAllTab = false}) {
    final status = _normalizeStatus(leave['status']);
    final leaveType = _normalizeLeaveType(leave['type']);
    final statusInfo = _getStatusInfo(status);
    final typeInfo = _getLeaveTypeInfoFromLeave(leave);
    final payment = LeaveCatalog.displayFor(leave).paymentSource;
    final startDate = parseApiCalendarDate(leave['startDate']);
    final endDate = parseApiCalendarDate(leave['endDate']);
    final duration = startDate != null && endDate != null
        ? endDate.difference(startDate).inDays + 1
        : 0;
    final isHalfShift = leave['isHalfShift'] == true;
    final createdAt = parseApiUtcDateTime(leave['createdAt']);
    final updatedAt = parseApiUtcDateTime(leave['updatedAt']);
    final shiftName = leave['shiftName']?.toString() ?? '';
    final shiftNames = (leave['shiftNames'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        [];
    final displayShiftNames =
        shiftNames.isNotEmpty ? shiftNames.join(', ') : shiftName;
    final replacementName = leave['replacementEmployeeName']?.toString() ?? '';
    final reason = leave['reason'] ?? '';
    // Build action buttons that close dialog first
    final dialogActions = <Widget>[];
    final isPending = status == 0;
    final dlgPerm = Provider.of<PermissionProvider>(context, listen: false);

    if (isPending && (isMyLeaves || isAllTab) && dlgPerm.canEdit('Leave')) {
      dialogActions.add(_ActionBtn(
          icon: Icons.edit_rounded,
          label: 'S?a',
          color: Colors.blue,
          onTap: () {
            Navigator.pop(context);
            _showLeaveFormDialog(leave: leave);
          }));
      dialogActions.add(const SizedBox(width: 6));
    }
    // Cancel: employee can cancel own pending, manager can cancel any pending
    if (isPending) {
      if (isMyLeaves ||
          (isAllTab && _isManager) ||
          (showApprovalActions && _isManager)) {
        dialogActions.add(_ActionBtn(
            icon: Icons.cancel_outlined,
            label: 'H?y',
            color: Colors.red,
            onTap: () {
              Navigator.pop(context);
              _cancelLeave(leave['id']);
            }));
        dialogActions.add(const SizedBox(width: 6));
      }
    }
    // Approve/Reject — NOT own leave
    final dlgLeaveOwnerId = leave['employeeUserId']?.toString() ??
        leave['userId']?.toString() ??
        '';
    if (isPending &&
        (showApprovalActions || isAllTab) &&
        dlgPerm.canApprove('Leave') &&
        dlgLeaveOwnerId != _currentUserId) {
      dialogActions.add(_ActionBtn(
          icon: Icons.check_circle_outline,
          label: 'Duy?t',
          color: Colors.green,
          onTap: () {
            Navigator.pop(context);
            _approveLeave(
                leave['id']?.toString(),
                Map<String, dynamic>.from(leave as Map));
          }));
      dialogActions.add(const SizedBox(width: 6));
      dialogActions.add(_ActionBtn(
          icon: Icons.highlight_off,
          label: 'T? ch?i',
          color: Colors.red,
          onTap: () {
            Navigator.pop(context);
            _rejectLeave(leave['id']);
          }));
      dialogActions.add(const SizedBox(width: 6));
    }
    // Undo
    if ((isAllTab || showApprovalActions) &&
        _isManager &&
        (status == 1 || status == 2)) {
      dialogActions.add(_ActionBtn(
          icon: Icons.undo_rounded,
          label: 'Hoàn tác',
          color: Colors.orange,
          onTap: () {
            Navigator.pop(context);
            _undoLeaveApproval(leave['id']);
          }));
      dialogActions.add(const SizedBox(width: 6));
    }
    // Delete
    if (dlgPerm.canDelete('Leave') &&
        ((isMyLeaves && isPending) ||
            isAllTab ||
            showApprovalActions ||
            dlgPerm.canApprove('Leave'))) {
      dialogActions.add(_ActionBtn(
          icon: Icons.delete_forever_outlined,
          label: 'Xóa',
          color: Colors.red.shade700,
          onTap: () {
            Navigator.pop(context);
            _forceDeleteLeave(leave['id']);
          }));
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
        _detailTableRow('Lo?i ngh?', typeInfo.label,
            valueColor: typeInfo.color),
        _detailTableRow('Chi tr?', payment.label,
            valueColor: payment.color),
        if (leave['bhxhDocumentNote']?.toString().isNotEmpty == true)
          _detailTableRow(
              'Gi?y BHXH', leave['bhxhDocumentNote']?.toString() ?? ''),
        if (leave['countAsWork'] == true)
          _detailTableRow(
            'Tính công',
            'Có — không ghi Phép trên ch?m công',
            valueColor: const Color(0xFF059669),
          ),
        if (leave['annualBalanceApplied'] == true)
          _detailTableRow(
            'Ðã tr? phép nam',
            '${leave['annualLeaveDaysDeducted'] ?? 0} ngày',
            valueColor: const Color(0xFF0D9488),
          ),
        _detailTableRow('Tr?ng thái', statusInfo.label,
            valueColor: statusInfo.color),
        _detailTableRow(
            'T? ngày',
            startDate != null
                ? DateFormat('EEEE, dd/MM/yyyy', 'vi').format(startDate)
                : 'N/A'),
        _detailTableRow(
            'Ð?n ngày',
            endDate != null
                ? DateFormat('EEEE, dd/MM/yyyy', 'vi').format(endDate)
                : 'N/A'),
        _detailTableRow(
            'S? ngày', '$duration ngày${isHalfShift ? ' (N?a ca)' : ''}'),
        if (displayShiftNames.isNotEmpty)
          _detailTableRow('Ca làm vi?c', displayShiftNames),
        if (replacementName.isNotEmpty)
          _detailTableRow('Ngu?i thay', replacementName),
        _detailTableRow('Lý do', reason.isNotEmpty ? reason : 'N/A'),
        if (status == 2 && leave['rejectionReason'] != null)
          _detailTableRow('Lý do t? ch?i', leave['rejectionReason'],
              valueColor: Colors.red),
        if (createdAt != null)
          _detailTableRow('Ngày t?o', formatApiDateTime(createdAt)),
        if (updatedAt != null)
          _detailTableRow('C?p nh?t', formatApiDateTime(updatedAt)),
        _detailTableRow('ID', leave['id']?.toString().substring(0, 8) ?? 'N/A'),
      ],
    );

    // Build approval timeline widget
    final approvalRecords =
        (leave['approvalRecords'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalLevels = leave['totalApprovalLevels'] ?? 1;
    final currentStep = leave['currentApprovalStep'] ?? 0;

    Widget approvalTimeline = const SizedBox.shrink();
    if (approvalRecords.isNotEmpty) {
      approvalRecords
          .sort((a, b) => (a['stepOrder'] ?? 0).compareTo(b['stepOrder'] ?? 0));
      approvalTimeline = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          // Progress indicator
          if (totalLevels > 1) ...[
            Row(
              children: [
                const Icon(Icons.linear_scale_rounded,
                    size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text('Ti?n trình duy?t: $currentStep/$totalLevels c?p',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: totalLevels > 0 ? currentStep / totalLevels : 0,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(status == 1
                    ? Colors.green
                    : status == 2
                        ? Colors.red
                        : Colors.blue),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Timeline
          const Text('L?ch s? phê duy?t',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...approvalRecords.asMap().entries.map((entry) {
            final idx = entry.key;
            final record = entry.value;
            final stepStatus = record['status'] ?? 0;
            final stepName =
                record['stepName'] ?? 'C?p ${record['stepOrder'] ?? idx + 1}';
            final assignedUser = record['assignedUserName'] ?? '';
            final actualUser = record['actualUserName'] ?? '';
            final actionDate = parseApiUtcDateTime(record['actionDate']);
            final note = record['note']?.toString() ?? '';
            final isLast = idx == approvalRecords.length - 1;

            Color dotColor;
            IconData dotIcon;
            switch (stepStatus) {
              case 1:
                dotColor = Colors.green;
                dotIcon = Icons.check_circle;
                break;
              case 2:
                dotColor = Colors.red;
                dotIcon = Icons.cancel;
                break;
              case 3:
                dotColor = Colors.grey;
                dotIcon = Icons.block;
                break;
              default:
                dotColor = Colors.orange;
                dotIcon = Icons.radio_button_unchecked;
                break;
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
                        if (!isLast)
                          Expanded(
                              child: Container(
                                  width: 2, color: Colors.grey.shade300)),
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
                          Text(stepName,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: dotColor)),
                          if (assignedUser.isNotEmpty)
                            Text('Phân công: $assignedUser',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          if (actualUser.isNotEmpty && stepStatus != 0)
                            Text('Th?c hi?n: $actualUser',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          if (actionDate != null)
                            Text(
                                formatApiDateTime(actionDate),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade500)),
                          if (note.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('"$note"',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey.shade700)),
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
                title: const Text('Chi ti?t don ngh? phép'),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusInfo.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusInfo.icon,
                              size: 16, color: statusInfo.color),
                          const SizedBox(width: 6),
                          Text(statusInfo.label,
                              style: TextStyle(
                                  color: statusInfo.color,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
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

        final dialogMaxH = MediaQuery.sizeOf(context).height * 0.88;
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 500, maxHeight: dialogMaxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        statusInfo.color.withValues(alpha: 0.8),
                        statusInfo.color.withValues(alpha: 0.6)
                      ],
                    ),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.description_rounded,
                          color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Chi ti?t don ngh? phép',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text(leave['employeeName'] ?? 'N/A',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusInfo.icon,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(statusInfo.label,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Expanded(
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
                  decoration: BoxDecoration(
                      border:
                          Border(top: BorderSide(color: Colors.grey.shade200))),
                  child: Row(
                    children: [
                      if (dialogActions.isNotEmpty) ...dialogActions,
                      const Spacer(),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Ðóng')),
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
  Widget _detailRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(
              width: 100,
              child: Text(label,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? Colors.grey.shade800)),
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
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? Colors.grey.shade800)),
        ),
      ],
    );
  }

  // ---------------------------------------------------
  // FORM DIALOG
  // ---------------------------------------------------
  void _showLeaveLegalGuide() {
    showDialog<void>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Ngh? phép theo pháp lu?t'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Doanh nghi?p tr? luong\n'
            '   Phép nam, l?, vi?c riêng có luong, ngh? bù, ?m dùng phép nam.\n\n'
            '2. Không hu?ng luong\n'
            '   Vi?c riêng không luong, ngh? dài h?n không luong.\n\n'
            '3. BHXH & d?c bi?t\n'
            '   ?m hu?ng BHXH (c?n gi?y ngh?), thai s?n DN + d?i soát BHXH.\n\n'
            'M?i ngày ngh? ch? m?t ch? d? — không v?a luong DN v?a tr? c?p BHXH.\n'
            'Ca ngh?: theo Thi?t l?p luong. Ngu?i thay ca: cùng phòng ban.',
            style: TextStyle(fontSize: 14, height: 1.45),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ðóng')),
        ],
      ),
    );
  }

  Future<void> _showLeaveFormDialog({Map<String, dynamic>? leave}) async {
    final result = await LeaveRequestFormDialog.show(
      context,
      shifts: _shifts,
      employees: _employees,
      apiService: _apiService,
      existingLeave: leave,
      currentUserId: _currentUserId,
      isManager: _isManager,
    );
    if (result == true) _loadData();
  }

  // ---------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------
  Future<void> _cancelLeave(String? leaveId) async {
    if (leaveId == null) return;
    final confirm = await _showConfirmDialog(
      title: 'H?y don ngh? phép',
      content: 'B?n có ch?c ch?n mu?n h?y don ngh? phép này?',
      confirmText: 'H?y don',
      confirmVariant: AppButtonVariant.danger,
      icon: Icons.cancel_rounded,
    );
    if (confirm != true) return;
    final result = await _apiService.cancelLeave(leaveId);
    _showResultSnackBar(result, 'Ðã h?y don ngh? phép', 'L?i khi h?y don');
  }

  Future<void> _undoLeaveApproval(String? leaveId) async {
    if (leaveId == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Hoàn tác duy?t',
      content:
          'B?n có ch?c ch?n mu?n hoàn tác tr?ng thái don ngh? phép này v? Ch? duy?t?\nH? th?ng s? khôi ph?c l?ch làm vi?c n?u don dã du?c duy?t.',
      confirmText: 'Hoàn tác',
      confirmVariant: AppButtonVariant.warning,
      icon: Icons.undo_rounded,
    );
    if (confirm != true) return;
    final result = await _apiService.undoLeaveApproval(leaveId);
    _showResultSnackBar(
        result, 'Ðã hoàn tác tr?ng thái don', 'L?i khi hoàn tác');
  }

  Future<void> _forceDeleteLeave(String? leaveId) async {
    if (leaveId == null) return;
    final confirm = await _showConfirmDialog(
      title: 'Xóa don ngh? phép',
      content:
          'B?n có ch?c ch?n mu?n xóa vinh vi?n don ngh? phép này?\nHành d?ng này không th? hoàn tác.',
      confirmText: 'Xóa',
      confirmVariant: AppButtonVariant.danger,
      icon: Icons.delete_forever_rounded,
    );
    if (confirm != true) return;
    final result = await _apiService.forceDeleteLeave(leaveId);
    _showResultSnackBar(result, 'Ðã xóa don ngh? phép', 'L?i khi xóa don');
  }

  Future<void> _approveLeave(String? leaveId, [Map<String, dynamic>? leave]) async {
    if (leaveId == null) return;
    var countAsWork = false;

    double? balanceRemaining;
    double daysNeeded = 0;
    var willDeductAnnual = false;
    if (leave != null) {
      final type = _normalizeLeaveType(leave['type']);
      final sm = leave['sickLeaveMode'] is int
          ? leave['sickLeaveMode'] as int
          : int.tryParse(leave['sickLeaveMode']?.toString() ?? '') ?? 0;
      willDeductAnnual = leave['countAsWork'] != true &&
          (type == 0 || (type == 4 && sm == 1));
      if (willDeductAnnual) {
        final start = parseApiCalendarDate(leave['startDate']);
        final end = parseApiCalendarDate(leave['endDate']);
        if (start != null && end != null) {
          final d = end.difference(start).inDays + 1;
          daysNeeded = (leave['isHalfShift'] == true ? d * 0.5 : d.toDouble());
        }
        final empId = leave['employeeId']?.toString();
        if (empId != null && empId.isNotEmpty) {
          final bal = await _apiService.getAnnualLeaveBalance(empId);
          if (bal['isSuccess'] == true && bal['data'] != null) {
            balanceRemaining =
                (bal['data']['remainingDays'] as num?)?.toDouble();
          }
        }
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ScrollableAlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A)),
              SizedBox(width: 8),
              Text('Duy?t don ngh? phép'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Xác nh?n duy?t don này?'),
              if (willDeductAnnual && balanceRemaining != null) ...[
                const SizedBox(height: 10),
                Text(
                  'S? tr? $daysNeeded ngày phép nam. Còn l?i: $balanceRemaining ngày.',
                  style: TextStyle(
                    fontSize: 13,
                    color: daysNeeded > balanceRemaining
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF047857),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: countAsWork,
                title: const Text(
                  'Phép duy?t nhung v?n tính công',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Không ghi "Phép" trên b?ng ch?m công',
                  style: TextStyle(fontSize: 12),
                ),
                onChanged: (v) => setLocal(() => countAsWork = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('H?y'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Duy?t'),
            ),
          ],
        ),
      ),
    );
    if (confirm != true) return;
    final result = await _apiService.approveLeave(
      leaveId,
      countAsWork: countAsWork ? true : null,
    );
    _showResultSnackBar(result, 'Ðã duy?t don ngh? phép', 'L?i khi duy?t don');
  }

  Future<void> _rejectLeave(String? leaveId) async {
    if (leaveId == null) return;
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.cancel_rounded, color: Colors.red[400]),
          const SizedBox(width: 8),
          const Text('T? ch?i don ngh? phép')
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vui lòng nh?p lý do t? ch?i:'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                maxLines: 3,
                autofocus: true,
                decoration: InputDecoration(
                    hintText: 'Lý do t? ch?i...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ],
          ),
        ),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () {
              if (reasonController.text.trim().isEmpty) {
                NotificationOverlayManager().showWarning(
                    title: 'Thi?u thông tin',
                    message: 'Vui lòng nh?p lý do t? ch?i');
                return;
              }
              Navigator.pop(ctx, true);
            },
            confirmLabel: 'T? ch?i',
            confirmVariant: AppButtonVariant.danger,
          ),
        ],
      ),
    );
    if (confirm == true && reasonController.text.trim().isNotEmpty) {
      final result =
          await _apiService.rejectLeave(leaveId, reasonController.text.trim());
      _showResultSnackBar(
          result, 'Ðã t? ch?i don ngh? phép', 'L?i khi t? ch?i don');
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
      builder: (ctx) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 8),
          Text(title)
        ]),
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

  void _showResultSnackBar(
      Map<String, dynamic> result, String successMsg, String errorMsg) {
    if (!mounted) return;
    if (result['isSuccess'] == true) {
      NotificationOverlayManager()
          .showSuccess(title: 'Thành công', message: successMsg);
      _loadData();
    } else {
      NotificationOverlayManager()
          .showError(title: 'L?i', message: result['message'] ?? errorMsg);
      // Refresh to clear stale data (e.g. leave already approved by another device)
      _loadData();
    }
  }

  // ---------------------------------------------------
  // HELPERS
  // ---------------------------------------------------
  static _StatusInfo _getStatusInfo(int status) {
    switch (status) {
      case 0:
        return const _StatusInfo(
            'Ch? duy?t', Colors.orange, Icons.hourglass_bottom_rounded);
      case 1:
        return const _StatusInfo(
            'Ðã duy?t', Colors.green, Icons.check_circle_rounded);
      case 2:
        return const _StatusInfo('T? ch?i', Colors.red, Icons.cancel_rounded);
      case 3:
        return const _StatusInfo('Ðã h?y', Colors.grey, Icons.block_rounded);
      default:
        return const _StatusInfo(
            'N/A', Colors.grey, Icons.help_outline_rounded);
    }
  }

  static _LeaveTypeInfo _getLeaveTypeInfoFromLeave(Map<String, dynamic> leave) {
    final d = LeaveCatalog.displayFor(leave);
    return _LeaveTypeInfo(d.title, d.color, d.icon);
  }

  static _LeaveTypeInfo _getLeaveTypeInfo(int type) {
    switch (type) {
      case 0:
        return const _LeaveTypeInfo(
            'Phép nam', Colors.teal, Icons.beach_access_rounded);
      case 1:
        return const _LeaveTypeInfo(
            'L? t?t', Colors.orange, Icons.celebration_rounded);
      case 2:
        return const _LeaveTypeInfo(
            'VR có luong', Colors.blue, Icons.paid_rounded);
      case 3:
        return const _LeaveTypeInfo(
            'VR không luong', Colors.amber, Icons.money_off_rounded);
      case 4:
        return const _LeaveTypeInfo(
            '?m dau', Colors.red, Icons.local_hospital_rounded);
      case 5:
        return const _LeaveTypeInfo(
            'Thai s?n', Colors.pink, Icons.child_friendly_rounded);
      case 6:
        return const _LeaveTypeInfo(
            'Ngh? bù', Colors.indigo, Icons.swap_horiz_rounded);
      case 7:
        return const _LeaveTypeInfo(
            'Ngh? dài h?n', Colors.brown, Icons.hourglass_full_rounded);
      default:
        return const _LeaveTypeInfo('Khác', Colors.grey, Icons.help_outline);
    }
  }
}

// ---------------------------------------------------
// ACTION BUTTON
// ---------------------------------------------------
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

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
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
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
