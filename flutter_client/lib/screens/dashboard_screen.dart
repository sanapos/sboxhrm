import 'dart:async';
// ignore_for_file: unused_import
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/loading_widget.dart';
import '../widgets/ai_assistant_sheet.dart';
import 'main_layout.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _isEmployee = false;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Employee dashboard data
  Map<String, dynamic> _employeeDashboard = {};

  // Data
  Map<String, dynamic> _dailyReport = {};
  List<dynamic> _dailyReportItems = [];
  DateTime? _selectedDate; // null => today
  DateTime? _rangeStart; // for week/month preset; null => single day
  DateTime? _rangeEnd;
  String _presetKey = 'today'; // today|yesterday|thisWeek|lastWeek|thisMonth|lastMonth|custom
  List<dynamic> _todayLeaves = [];
  List<dynamic> _trends = [];
  List<dynamic> _devices = [];
  List<dynamic> _communications = [];
  List<dynamic> _employees = [];
  List<dynamic> _kpiResults = [];
  Map<String, dynamic> _kpiDashboard = {};
  List<dynamic> _todaySchedules = [];

  // Phase 3 data
  List<dynamic> _pendingLeaves = [];
  List<dynamic> _pendingCorrections = [];
  List<dynamic> _pendingSwaps = [];
  List<dynamic> _pendingAdvances = [];
  Map<String, dynamic> _taskStats = {};
  Map<String, dynamic> _overtimeStats = {};
  Map<String, dynamic> _penaltyStats = {};
  Map<String, dynamic> _cashSummary = {};
  Map<String, dynamic> _monthlyReport = {};
  List<dynamic> _expiringDocs = [];

  @override
  void initState() {
    super.initState();
    // Greeting and current-shift display only need coarse updates — every 60s
    // rebuilds the entire dashboard tree unnecessarily. 5 minutes is enough to
    // cross morning/afternoon/evening boundaries and shift transitions.
    _clockTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _isEmployee = authProvider.userRole == 'Employee';
    if (_isEmployee) {
      _loadEmployeeData();
    } else {
      _loadAllData();
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployeeData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _api.getEmployeeDashboard(),
        _api.getMyLeaves(pageSize: 10),
        _api.getMyEmployee(),
      ]);

      if (mounted) {
        final dashResp = results[0];
        final leavesResp = results[1];
        final empResp = results[2];
        setState(() {
          _employeeDashboard = (dashResp['data'] as Map<String, dynamic>?) ?? {};
          _todayLeaves = _extractList(leavesResp);
          if (empResp['isSuccess'] == true && empResp['data'] != null) {
            _employees = [empResp['data']];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Employee dashboard load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Memoized derived values (recomputed once per _loadAllData)
  List<Map<String, dynamic>> _memoLate = const [];
  List<Map<String, dynamic>> _memoAbsent = const [];
  List<Map<String, dynamic>> _memoNotScheduled = const [];
  int _memoCheckIns = 0;
  int _memoCheckOuts = 0;
  int _memoOnlineDevices = 0;

  /// Safely run an API call; log and return [fallback] on error so one failing
  /// endpoint never takes down the entire dashboard batch.
  Future<T> _safe<T>(Future<T> Function() call, T fallback, String label) async {
    try {
      return await call().timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[dashboard] $label failed: $e');
      return fallback;
    }
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final target = _selectedDate ?? DateTime.now();
    final todayStr =
        '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
    final dayStart = DateTime(target.year, target.month, target.day);
    final dayEnd = DateTime(target.year, target.month, target.day, 23, 59, 59);
    final now = DateTime.now();
    final monthStart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final monthEnd =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

    // Phase 1 — minimum data to paint the dashboard. Only 3 calls.
    final emptyMap = <String, dynamic>{};
    final emptyList = <dynamic>[];
    final critical = await Future.wait([
      _safe(() => _api.getDailyAttendanceReport(date: todayStr), emptyMap, 'daily'),
      _safe(() => _api.getDevices(storeOnly: true), emptyList, 'devices'),
      _safe(() => _api.getEmployees(pageSize: 500), emptyList, 'employees'),
    ]);

    if (!mounted) return;
    final dailyResp = critical[0] as Map<String, dynamic>;
    final dailyData = (dailyResp['data'] as Map<String, dynamic>?) ?? {};
    setState(() {
      _dailyReport = dailyData;
      _dailyReportItems = (dailyData['items'] as List<dynamic>?) ?? [];
      _devices = critical[1] as List<dynamic>;
      _employees = critical[2] as List<dynamic>;
      _isLoading = false;
      _recomputeMemoized();
    });

    // Phase 2 — all remaining data in ONE parallel batch (was 2 sequential phases).
    // Each call is independently protected: a single 500 won't break the others.
    final batch = await Future.wait([
      _safe(() => _api.getAttendanceTrends(days: 7), emptyList, 'trends'),          // 0
      _safe(() => _api.getCommunications(page: 1, pageSize: 5), emptyMap, 'comms'), // 1
      _safe(() => _api.getKpiResults(), emptyMap, 'kpi-results'),                   // 2
      _safe(() => _api.getAllLeaves(status: 'Approved', fromDate: todayStr, toDate: todayStr, pageSize: 100), emptyMap, 'leaves-today'), // 3
      _safe(() => _api.getKpiDashboard(), emptyMap, 'kpi-dashboard'),               // 4
      _safe(() => _api.getWorkSchedules(fromDate: dayStart, toDate: dayEnd, pageSize: 500), emptyMap, 'schedules'), // 5
      _safe(() => _api.getPendingLeaves(pageSize: 100), emptyMap, 'pending-leaves'),// 6
      _safe(() => _api.getAttendanceCorrections(pageSize: 100), emptyMap, 'corrections'), // 7
      _safe(() => _api.getShiftSwapsPendingApproval(), emptyMap, 'swaps'),          // 8
      _safe(() => _api.getTaskStatistics(), emptyMap, 'tasks'),                     // 9
      _safe(() => _api.getOvertimeStatistics(), emptyMap, 'ot'),                    // 10
      _safe(() => _api.getPenaltyTicketStats(month: now.month, year: now.year), emptyMap, 'penalty'), // 11
      _safe(() => _api.getCashTransactionSummary(fromDate: monthStart, toDate: monthEnd), emptyMap, 'cash'), // 12
      _safe(() => _api.getMonthlyAttendanceReport(month: now.month, year: now.year), emptyMap, 'monthly'), // 13
      _safe(() => _api.getExpiringDocuments(), emptyMap, 'docs'),                   // 14
      _safe(() => _api.getAdvanceRequests(status: 0, pageSize: 100), emptyMap, 'advances'), // 15
    ]);

    if (!mounted) return;
    Map<String, dynamic> asMap(int i) => batch[i] as Map<String, dynamic>;
    setState(() {
      _trends = batch[0] as List<dynamic>;
      _communications = _extractList(asMap(1));
      _kpiResults = _extractList(asMap(2));
      _todayLeaves = _extractList(asMap(3));
      _kpiDashboard = (asMap(4)['data'] as Map<String, dynamic>?) ?? {};
      _todaySchedules = _extractList(asMap(5));
      _pendingLeaves = _extractList(asMap(6));
      _pendingCorrections = _extractList(asMap(7));
      _pendingSwaps = _extractList(asMap(8));
      _taskStats = (asMap(9)['data'] as Map<String, dynamic>?) ?? asMap(9);
      _overtimeStats = (asMap(10)['data'] as Map<String, dynamic>?) ?? asMap(10);
      _penaltyStats = (asMap(11)['data'] as Map<String, dynamic>?) ?? asMap(11);
      _cashSummary = (asMap(12)['data'] as Map<String, dynamic>?) ?? asMap(12);
      _monthlyReport = (asMap(13)['data'] as Map<String, dynamic>?) ?? asMap(13);
      _expiringDocs = _extractList(asMap(14));
      _pendingAdvances = _extractList(asMap(15));
    });
  }

  /// Recompute all list-scanning derived values in O(n) once per refresh,
  /// instead of re-iterating _dailyReportItems on every widget rebuild.
  void _recomputeMemoized() {
    final late = <Map<String, dynamic>>[];
    final absent = <Map<String, dynamic>>[];
    final notSched = <Map<String, dynamic>>[];
    var ins = 0;
    var outs = 0;
    for (final raw in _dailyReportItems) {
      if (raw is! Map<String, dynamic>) continue;
      final status = (raw['status'] ?? '').toString().toLowerCase();
      if (raw['checkInTime'] != null) ins++;
      if (raw['checkOutTime'] != null) outs++;
      if (status.contains('muộn') || status.contains('trễ') ||
          status.contains('late') || status.contains('sớm') ||
          status.contains('early')) {
        late.add(raw);
      }
      if (status.contains('vắng') || status.contains('absent')) {
        absent.add(raw);
      }
      if (status.contains('không có lịch') || status.contains('ngày nghỉ')) {
        notSched.add(raw);
      }
    }
    _memoLate = late;
    _memoAbsent = absent;
    _memoNotScheduled = notSched;
    _memoCheckIns = ins;
    _memoCheckOuts = outs;

    // Online device count — cached (recomputed when _devices changes).
    var online = 0;
    for (final d in _devices) {
      if (d is Map && _isDeviceOnline(d)) online++;
    }
    _memoOnlineDevices = online;
  }

  /// Online-device heuristic — copy EXACT logic from
  /// `device_management_settings_screen.dart` so the Dashboard and the HRM
  /// Settings screen always show the same counts.
  bool _isDeviceOnline(Map d) {
    // Ưu tiên dùng trạng thái do backend tính sẵn
    final status = d['deviceStatus']?.toString().toLowerCase();
    if (status != null && status.isNotEmpty) {
      return status == 'online';
    }
    // Fallback: tính từ lastOnline (server lưu UTC, phải parse đúng)
    final lastOnline = d['lastOnline'];
    if (lastOnline == null) return false;
    try {
      final raw = lastOnline.toString();
      final dateStr =
          (raw.contains('Z') || raw.contains('+')) ? raw : '${raw}Z';
      final dt = DateTime.parse(dateStr);
      return DateTime.now().toUtc().difference(dt).inMinutes < 5;
    } catch (_) {
      return false;
    }
  }

  List<dynamic> _extractList(Map<String, dynamic> data) {
    final d = data['data'];
    if (d is List) return d;
    if (d is Map) {
      return d['items'] ?? d['data'] ?? d['results'] ?? d['records'] ?? [];
    }
    return [];
  }

  // ===== COMPUTED DATA (from Daily Attendance Report) =====
  // These read pre-computed memoized lists populated by _recomputeMemoized().
  List<dynamic> get _todayEmployees => _dailyReportItems;
  List<dynamic> get _lateEmployees => _memoLate;
  // ignore: unused_element
  List<dynamic> get _absentEmployeesList => _memoAbsent;

  int get _totalEmployees {
    // Match the detail list length.
    if (_dailyReportItems.isNotEmpty) return _dailyReportItems.length;
    final fromReport =
        ((_dailyReport['totalEmployees'] ?? 0) as num).toInt();
    return fromReport > 0 ? fromReport : _employees.length;
  }
  int get _presentCount => _kpiDetailData('present').length;
  int get _absentCount => _kpiDetailData('absent').length;
  int get _lateCount => _memoLate.length;
  int get _checkIns => _memoCheckIns;
  int get _checkOuts => _memoCheckOuts;
  double get _attendanceRate {
    final total = _totalEmployees;
    if (total <= 0) return 0;
    return (_presentCount / total) * 100.0;
  }
  int get _onlineDevices => _memoOnlineDevices;
  int get _totalDevices => _devices.length;

  List<Map<String, dynamic>> get _todayBirthdays {
    final today = DateTime.now();
    final bdays = <Map<String, dynamic>>[];
    for (final e in _employees) {
      if (e is Map<String, dynamic>) {
        final dob = e['dateOfBirth'] ?? e['birthday'];
        if (dob != null) {
          try {
            final d = DateTime.parse(dob.toString());
            if (d.month == today.month && d.day == today.day) {
              bdays.add(e);
            }
          } catch (_) {}
        }
      }
    }
    return bdays;
  }

  List<Map<String, dynamic>> get _monthlyBirthdays {
    final today = DateTime.now();
    final monthly = <Map<String, dynamic>>[];
    for (final e in _employees) {
      if (e is Map<String, dynamic>) {
        final dob = e['dateOfBirth'] ?? e['birthday'];
        if (dob != null) {
          try {
            final d = DateTime.parse(dob.toString());
            if (d.month == today.month) {
              // Skip today's birthdays (already shown separately)
              if (d.day == today.day) continue;
              monthly.add({...e, '_birthdayDay': d.day});
            }
          } catch (_) {}
        }
      }
    }
    monthly.sort((a, b) => (a['_birthdayDay'] as int).compareTo(b['_birthdayDay'] as int));
    return monthly;
  }

  List<Map<String, dynamic>> get _absentWithPermission {
    // On-leave employees from daily report (status = "Nghỉ phép")
    final fromReport = _dailyReportItems.whereType<Map<String, dynamic>>().where((e) {
      final status = (e['status'] ?? '').toString().toLowerCase();
      // Match "Nghỉ phép" but NOT "Ngày nghỉ" (day off)
      return status == 'nghỉ phép' || status.contains('leave') || (status.contains('phép') && !status.contains('ngày nghỉ'));
    }).toList();
    // Also include from leave API if report has none
    final source = fromReport.isNotEmpty
        ? fromReport
        : _todayLeaves.whereType<Map<String, dynamic>>().toList();
    // Dedupe by employee identity — leave API may return one row per day for a multi-day leave
    // or report + leave fallback overlap → caused names appearing twice.
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final e in source) {
      final key = (e['employeeId'] ?? e['employeeUserId'] ?? e['employeeCode'] ??
                   e['userId'] ?? e['id'] ?? e['employeeName'] ?? '').toString();
      if (key.isEmpty || seen.add(key)) {
        unique.add(e);
      }
    }
    return unique;
  }

  List<Map<String, dynamic>> get _absentWithoutPermission => _memoAbsent;

  /// Employees not scheduled today (no work schedule or day off)
  List<Map<String, dynamic>> get _notScheduledEmployees => _memoNotScheduled;

  /// Number of employees scheduled to work today
  int get _scheduledCount {
    return _totalEmployees - _notScheduledEmployees.length;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return LoadingWidget(message: _l10n.loadingOverview);
    }

    final body = _isEmployee
        ? _buildEmployeeDashboard()
        : RefreshIndicator(
            onRefresh: _loadAllData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(MediaQuery.of(context).size.width < 768 ? 12 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 14),
                  _buildQuickActions(),
                  const SizedBox(height: 16),
                  _buildHeroOverview(),
                  const SizedBox(height: 20),
                  _buildMainGrid(),
                ],
              ),
            ),
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAiAssistant(context),
        backgroundColor: const Color(0xFF8B5CF6),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome_rounded),
        label: const Text('Trợ lý AI'),
        tooltip: 'Mở trợ lý ảo HRM',
      ),
    );
  }

  // ===================== HEADER =====================
  Widget _buildHeader() {
    String greeting;
    IconData greetIcon;
    Color iconColor;
    if (_now.hour < 12) {
      greeting = _l10n.goodMorning;
      greetIcon = Icons.wb_sunny_rounded;
      iconColor = const Color(0xFFFCD34D);
    } else if (_now.hour < 18) {
      greeting = _l10n.goodAfternoon;
      greetIcon = Icons.wb_twilight_rounded;
      iconColor = const Color(0xFFFB923C);
    } else {
      greeting = _l10n.goodEvening;
      greetIcon = Icons.nightlight_round;
      iconColor = const Color(0xFFA78BFA);
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final fullName = auth.user?.fullName ?? 'User';
    final role = auth.userRole;
    final initials = _initialsOf(fullName);
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F2340), Color(0xFF1E3A5F), Color(0xFF2D5F8B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Decorative gradient orbs
          Positioned(
            right: -40,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  iconColor.withValues(alpha: 0.35),
                  iconColor.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          Positioned(
            left: -30,
            bottom: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  Colors.white.withValues(alpha: 0.10),
                  Colors.white.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(greetIcon, color: iconColor, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '$greeting,',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _headerBadge(role),
                          const SizedBox(width: 6),
                          _headerBadge('${_weekday(_now.weekday)} • ${_now.day}/${_now.month}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Live clock pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$hh:$mm',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        _now.year.toString(),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[parts.length - 2].characters.first + parts.last.characters.first).toUpperCase();
  }

  Widget _headerBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ===================== QUICK ACTIONS =====================
  Widget _buildQuickActions() {
    final actions = <_QuickAction>[
      _QuickAction(Icons.fingerprint_rounded, 'Chấm công', const Color(0xFF22C55E), () => NavigationNotifier.goToAttendance()),
      _QuickAction(Icons.beach_access_rounded, 'Xin nghỉ', const Color(0xFFF59E0B), () => NavigationNotifier.goToLeaves()),
      _QuickAction(Icons.swap_horiz_rounded, 'Đổi ca', const Color(0xFF8B5CF6), () => NavigationNotifier.goToWorkSchedule()),
      _QuickAction(Icons.payments_rounded, 'Phiếu lương', const Color(0xFF06B6D4), () => NavigationNotifier.goToPayroll()),
      _QuickAction(Icons.campaign_rounded, 'Truyền thông', const Color(0xFFEC4899), () => NavigationNotifier.goToCommunication()),
      _QuickAction(Icons.auto_awesome_rounded, 'Trợ lý AI', const Color(0xFF6366F1), () => showAiAssistant(context)),
    ];

    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _buildQuickActionTile(actions[i]),
      ),
    );
  }

  Widget _buildQuickActionTile(_QuickAction a) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: a.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: a.color.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: a.color.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [a.color, Color.lerp(a.color, Colors.white, 0.35)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: a.color.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(a.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                a.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== HERO OVERVIEW (donut + KPI + date filter) =====================
  Widget _buildHeroOverview() {
    final rate = _attendanceRate.clamp(0, 100).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFEFF3F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 18, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Tổng quan chấm công',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E3A5F)),
                ),
              ),
              if (_rangeLabel().isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _rangeLabel(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E3A5F)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Filter row — own line, horizontally scrollable so nothing is cut off
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildPresetChip('today', 'Hôm nay'),
                const SizedBox(width: 6),
                _buildPresetChip('yesterday', 'Hôm qua'),
                const SizedBox(width: 6),
                _buildPresetChip('thisWeek', 'Tuần này'),
                const SizedBox(width: 6),
                _buildPresetChip('lastWeek', 'Tuần trước'),
                const SizedBox(width: 6),
                _buildPresetChip('thisMonth', 'Tháng này'),
                const SizedBox(width: 6),
                _buildPresetChip('lastMonth', 'Tháng trước'),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _pickCustomDate,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _presetKey == 'custom'
                          ? const Color(0xFF1E3A5F)
                          : Colors.white,
                      border: Border.all(
                          color: _presetKey == 'custom'
                              ? const Color(0xFF1E3A5F)
                              : const Color(0xFFE4E9F0)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month,
                            size: 14,
                            color: _presetKey == 'custom'
                                ? Colors.white
                                : const Color(0xFF475569)),
                        const SizedBox(width: 4),
                        Text(
                          'Lựa chọn khác',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _presetKey == 'custom'
                                ? Colors.white
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 720;
              final donut = _buildAttendanceDonut(rate);
              final tiles = _buildHeroKpiTiles();
              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 260, child: donut),
                    const SizedBox(width: 18),
                    Expanded(child: tiles),
                  ],
                );
              }
              return Column(
                children: [
                  SizedBox(height: 230, child: donut),
                  const SizedBox(height: 12),
                  tiles,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildInsightChipsRow(),
        ],
      ),
    );
  }

  // ===================== INSIGHT CHIPS ROW =====================
  Widget _buildInsightChipsRow() {
    final pendingTotal = _pendingLeaves.length + _pendingCorrections.length +
        _pendingSwaps.length + _pendingAdvances.length;
    final otCount = _toInt(_overtimeStats['totalOvertimeCount'] ??
        _overtimeStats['employeesWithOvertime'] ?? _overtimeStats['count'] ?? 0);
    final taskTotal = _toInt(_taskStats['totalTasks'] ?? _taskStats['total'] ?? 0);
    final taskDone = _toInt(_taskStats['completedCount'] ?? _taskStats['completed'] ?? _taskStats['done'] ?? 0);
    final penaltyCount = _toInt(_penaltyStats['totalTickets'] ??
        _penaltyStats['count'] ?? _penaltyStats['total'] ?? 0);
    final cashIn = ((_cashSummary['totalIncome'] ?? _cashSummary['totalIn'] ?? 0) as num).toDouble();
    final cashOut = ((_cashSummary['totalExpense'] ?? _cashSummary['totalOut'] ?? 0) as num).toDouble();
    final cashNet = cashIn - cashOut;

    // Reorder: Thu chi full-width at row 4 (last)
    final chips = <_InsightChipData>[
      // Row 1
      _InsightChipData(Icons.beach_access_outlined, 'Nghỉ phép', '${_absentWithPermission.length}', const Color(0xFFF59E0B), 'leave_today'),
      _InsightChipData(Icons.pending_actions_outlined, 'Chờ duyệt', '$pendingTotal', const Color(0xFFEF4444), 'pending_all'),
      _InsightChipData(Icons.cake_outlined, 'Sinh nhật', '${_todayBirthdays.length}', const Color(0xFFEC4899), 'birthday_detail'),
      // Row 2
      _InsightChipData(Icons.av_timer_outlined, 'OT tháng', '$otCount NV', const Color(0xFF8B5CF6), 'overtime_detail'),
      _InsightChipData(Icons.task_alt_outlined, 'Công việc', taskTotal > 0 ? '$taskDone/$taskTotal' : '0', const Color(0xFF2D5F8B), 'task_detail'),
      _InsightChipData(Icons.gavel_outlined, 'Vi phạm', '$penaltyCount', const Color(0xFFDC2626), 'penalty_detail'),
      // Row 3
      _InsightChipData(Icons.description_outlined, 'HĐ hết hạn', '${_expiringDocs.length}', const Color(0xFFEA580C), 'docs_detail'),
      _InsightChipData(Icons.account_balance_wallet_outlined, 'Ứng lương', '${_pendingAdvances.length}', const Color(0xFF10B981), 'advance_detail'),
      _InsightChipData(Icons.groups_outlined, 'NV mới', '${_newHiresThisMonth()}', const Color(0xFF0F2340), 'newhires_detail'),
      // Row 4 — full width
      _InsightChipData(Icons.attach_money, 'Thu chi', '${cashNet >= 0 ? '+' : ''}${_fmtMoney(cashNet)}', cashNet >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626), 'finance_detail'),
    ];

    Widget fixedRow(int start, int count) => Row(
      children: List.generate(count * 2 - 1, (i) {
        if (i.isOdd) return const SizedBox(width: 8);
        final idx = start + i ~/ 2;
        return Expanded(child: _buildInsightChip(chips[idx]));
      }),
    );

    // Thu chi chip — full width (spans same width as 3-chip row)
    final thuChiChip = chips[9];
    final thuChiWidget = GestureDetector(
      onTap: () => _showInsightDetail(thuChiChip),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: thuChiChip.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: thuChiChip.color.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(thuChiChip.icon, size: 16, color: thuChiChip.color),
            const SizedBox(width: 8),
            Text(thuChiChip.label,
                style: TextStyle(fontSize: 12, color: thuChiChip.color, fontWeight: FontWeight.w600)),
            const SizedBox(width: 12),
            Text(thuChiChip.value,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: thuChiChip.color)),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        fixedRow(0, 3),
        const SizedBox(height: 8),
        fixedRow(3, 3),
        const SizedBox(height: 8),
        fixedRow(6, 3),
        const SizedBox(height: 8),
        thuChiWidget,
      ],
    );
  }

  Widget _buildInsightChip(_InsightChipData c) {
    return GestureDetector(
      onTap: () => _showInsightDetail(c),
      child: Container(
        constraints: const BoxConstraints(minWidth: 88),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.color.withValues(alpha: 0.22)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(c.icon, size: 12, color: c.color),
              const SizedBox(width: 4),
              Text(c.label, style: TextStyle(fontSize: 10, color: c.color, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Text(c.value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c.color), maxLines: 1),
          ],
        ),
      ),
    );
  }

  int _newHiresThisMonth() {
    final now = DateTime.now();
    var count = 0;
    for (final e in _employees) {
      if (e is Map) {
        final join = e['joinDate'] ?? e['hireDate'] ?? e['startDate'];
        if (join != null) {
          try {
            final d = DateTime.parse(join.toString());
            if (d.year == now.year && d.month == now.month) count++;
          } catch (_) {}
        }
      }
    }
    return count;
  }

  String _fmtMoney(double v) {
    if (v.abs() >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  // ===================== INSIGHT DETAIL SHEET =====================
  void _showInsightDetail(_InsightChipData c) {
    final List<Map<String, dynamic>> items;
    Widget? customContent;

    switch (c.kind) {
      case 'leave_today':
        items = _absentWithPermission;
        break;
      case 'pending_all':
        // Combine all pending lists
        items = [
          ..._pendingLeaves.whereType<Map<String, dynamic>>().map((e) => {...e, '_type': 'Đơn nghỉ phép'}),
          ..._pendingCorrections.whereType<Map<String, dynamic>>().map((e) => {...e, '_type': 'Chỉnh sửa CC'}),
          ..._pendingSwaps.whereType<Map<String, dynamic>>().map((e) => {...e, '_type': 'Đổi ca'}),
          ..._pendingAdvances.whereType<Map<String, dynamic>>().map((e) => {...e, '_type': 'Ứng lương'}),
        ];
        break;
      case 'birthday_detail':
        items = [..._todayBirthdays, ..._monthlyBirthdays];
        break;
      case 'overtime_detail':
        items = [];
        customContent = _buildOvertimeDetailContent();
        break;
      case 'task_detail':
        items = [];
        customContent = _buildTaskDetailContent();
        break;
      case 'penalty_detail':
        items = [];
        customContent = _buildPenaltyDetailContent();
        break;
      case 'docs_detail':
        items = _expiringDocs.whereType<Map<String, dynamic>>().toList();
        break;
      case 'advance_detail':
        items = _pendingAdvances.whereType<Map<String, dynamic>>().toList();
        break;
      case 'finance_detail':
        items = [];
        customContent = _buildFinanceDetailContent();
        break;
      case 'newhires_detail':
        final now = DateTime.now();
        items = _employees.whereType<Map<String, dynamic>>().where((e) {
          final join = e['joinDate'] ?? e['hireDate'] ?? e['startDate'];
          if (join == null) return false;
          try {
            final d = DateTime.parse(join.toString());
            return d.year == now.year && d.month == now.month;
          } catch (_) { return false; }
        }).toList();
        break;
      default:
        items = [];
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(c.icon, color: c.color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(customContent != null ? c.value : '${items.length} mục',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: customContent != null
                    ? SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        child: customContent,
                      )
                    : items.isEmpty
                        ? _emptyState('Không có dữ liệu')
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (_, i) => _buildInsightDetailRow(c.kind, items[i], c.color),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightDetailRow(String kind, Map<String, dynamic> item, Color accent) {
    final name = (item['fullName'] ?? item['employeeName'] ?? item['name'] ?? '-').toString();
    final sub1 = (item['departmentName'] ?? item['department'] ?? item['_type'] ?? '').toString();
    final sub2 = (item['leaveType'] ?? item['type'] ?? item['contractType'] ?? '').toString();

    String badge = '';
    if (kind == 'birthday_detail') {
      final dob = item['dateOfBirth'] ?? item['birthday'];
      badge = dob != null ? _fmtDate(dob) : '';
    } else if (kind == 'pending_all') {
      badge = (item['_type'] ?? '').toString();
    } else if (kind == 'docs_detail') {
      badge = (item['expiryDate'] ?? item['endDate'] ?? '').toString().isNotEmpty
          ? _fmtDate(item['expiryDate'] ?? item['endDate'])
          : '';
    } else if (kind == 'advance_detail') {
      final amt = (item['requestedAmount'] ?? item['amount'] ?? 0) as num;
      badge = '${_fmtMoney(amt.toDouble())}đ';
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accent.withValues(alpha: .12),
            child: Text(name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (sub1.isNotEmpty || sub2.isNotEmpty)
                  Text([sub1, sub2].where((s) => s.isNotEmpty).join(' • '),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (badge.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(8)),
              child: Text(badge, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accent)),
            ),
        ],
      ),
    );
  }

  Widget _buildOvertimeDetailContent() {
    final total = _toInt(_overtimeStats['totalOvertimeCount'] ?? _overtimeStats['count'] ?? 0);
    final hours = ((_overtimeStats['totalOvertimeHours'] ?? _overtimeStats['hours'] ?? 0) as num).toDouble();
    final approved = _toInt(_overtimeStats['approvedCount'] ?? _overtimeStats['approved'] ?? 0);
    final pending = _toInt(_overtimeStats['pendingCount'] ?? _overtimeStats['pending'] ?? 0);
    return Column(children: [
      _detailStatRow(Icons.people_outline, 'Tổng NV làm OT', '$total người', const Color(0xFF8B5CF6)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.timer_outlined, 'Tổng giờ OT', '${hours.toStringAsFixed(1)} giờ', const Color(0xFF8B5CF6)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.check_circle_outline, 'Đã duyệt', '$approved', const Color(0xFF22C55E)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.pending_outlined, 'Chờ duyệt', '$pending', const Color(0xFFF59E0B)),
    ]);
  }

  Widget _buildTaskDetailContent() {
    final total = _toInt(_taskStats['totalTasks'] ?? _taskStats['total'] ?? 0);
    final todo = _toInt(_taskStats['todoCount'] ?? _taskStats['pending'] ?? _taskStats['notStarted'] ?? 0);
    final inProg = _toInt(_taskStats['inProgressCount'] ?? _taskStats['inProgress'] ?? 0);
    final done = _toInt(_taskStats['completedCount'] ?? _taskStats['completed'] ?? _taskStats['done'] ?? 0);
    final overdue = _toInt(_taskStats['overdueCount'] ?? _taskStats['overdue'] ?? 0);
    final rate = total > 0 ? (done / total * 100) : 0.0;
    return Column(children: [
      _detailStatRow(Icons.checklist, 'Tổng công việc', '$total', const Color(0xFF2D5F8B)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.radio_button_unchecked, 'Chưa bắt đầu', '$todo', const Color(0xFF71717A)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.autorenew, 'Đang làm', '$inProg', const Color(0xFFF59E0B)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.check_circle, 'Hoàn thành', '$done', const Color(0xFF22C55E)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.warning_amber, 'Quá hạn', '$overdue', const Color(0xFFEF4444)),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: rate / 100, minHeight: 10,
          backgroundColor: const Color(0xFFE4E4E7),
          valueColor: AlwaysStoppedAnimation(rate >= 80 ? const Color(0xFF22C55E) : rate >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)),
        ),
      ),
      const SizedBox(height: 4),
      Text('Tỉ lệ hoàn thành: ${rate.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
    ]);
  }

  Widget _buildPenaltyDetailContent() {
    final total = _toInt(_penaltyStats['totalTickets'] ?? _penaltyStats['count'] ?? _penaltyStats['total'] ?? 0);
    final totalFine = ((_penaltyStats['totalFineAmount'] ?? _penaltyStats['totalAmount'] ?? 0) as num).toDouble();
    final paid = _toInt(_penaltyStats['paidCount'] ?? _penaltyStats['paid'] ?? 0);
    final unpaid = _toInt(_penaltyStats['unpaidCount'] ?? _penaltyStats['unpaid'] ?? 0);
    return Column(children: [
      _detailStatRow(Icons.receipt_long, 'Tổng phiếu vi phạm', '$total', const Color(0xFFDC2626)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.attach_money, 'Tổng tiền phạt', '${_fmtMoney(totalFine)}đ', const Color(0xFFDC2626)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.check_circle_outline, 'Đã nộp phạt', '$paid', const Color(0xFF22C55E)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.cancel_outlined, 'Chưa nộp', '$unpaid', const Color(0xFFF59E0B)),
    ]);
  }

  Widget _buildFinanceDetailContent() {
    final income = ((_cashSummary['totalIncome'] ?? _cashSummary['totalIn'] ?? 0) as num).toDouble();
    final expense = ((_cashSummary['totalExpense'] ?? _cashSummary['totalOut'] ?? 0) as num).toDouble();
    final net = income - expense;
    final txCount = _toInt(_cashSummary['totalTransactions'] ?? _cashSummary['count'] ?? 0);
    return Column(children: [
      _detailStatRow(Icons.trending_up, 'Tổng thu', '${_fmtMoney(income)}đ', const Color(0xFF22C55E)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.trending_down, 'Tổng chi', '${_fmtMoney(expense)}đ', const Color(0xFFEF4444)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.account_balance, 'Tồn quỹ', '${net >= 0 ? '+' : ''}${_fmtMoney(net)}đ', net >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.receipt, 'Số giao dịch', '$txCount', const Color(0xFF2D5F8B)),
    ]);
  }

  Widget _detailStatRow(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  // Short label shown in the title chip describing the active range
  String _rangeLabel() {
    String d(DateTime x) => '${x.day}/${x.month}';
    switch (_presetKey) {
      case 'today':
        return '';
      case 'yesterday':
        return 'Hôm qua';
      case 'custom':
        return _selectedDate == null ? '' : d(_selectedDate!);
      default:
        if (_rangeStart != null && _rangeEnd != null) {
          return '${d(_rangeStart!)} – ${d(_rangeEnd!)}';
        }
        return '';
    }
  }

  Widget _buildPresetChip(String key, String label) {
    final selected = _presetKey == key;
    return InkWell(
      onTap: () => _applyPreset(key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F) : Colors.white,
          border: Border.all(
              color: selected
                  ? const Color(0xFF1E3A5F)
                  : const Color(0xFFE4E9F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  void _applyPreset(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? start;
    DateTime? end;
    DateTime? single;

    switch (key) {
      case 'today':
        single = today;
        break;
      case 'yesterday':
        single = today.subtract(const Duration(days: 1));
        break;
      case 'thisWeek':
        // Monday = 1 ... Sunday = 7
        start = today.subtract(Duration(days: today.weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      case 'lastWeek':
        final thisMon = today.subtract(Duration(days: today.weekday - 1));
        start = thisMon.subtract(const Duration(days: 7));
        end = thisMon.subtract(const Duration(days: 1));
        break;
      case 'thisMonth':
        start = DateTime(today.year, today.month, 1);
        end = DateTime(today.year, today.month + 1, 0);
        break;
      case 'lastMonth':
        start = DateTime(today.year, today.month - 1, 1);
        end = DateTime(today.year, today.month, 0);
        break;
    }

    setState(() {
      _presetKey = key;
      if (single != null) {
        _selectedDate =
            key == 'today' ? null : single; // null means "today" for API
        _rangeStart = null;
        _rangeEnd = null;
      } else if (start != null && end != null) {
        _rangeStart = start;
        _rangeEnd = end.isAfter(today) ? today : end;
        // Use the end of the range (capped to today) as the "target" day
        // for the daily snapshot.
        _selectedDate = _rangeEnd;
      }
    });
    _loadAllData();
  }

  // ignore: unused_element
  int _daysAgo(DateTime d) {
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(d.year, d.month, d.day);
    return a.difference(b).inDays;
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _presetKey = 'custom';
        _selectedDate = picked;
        _rangeStart = null;
        _rangeEnd = null;
      });
      _loadAllData();
    }
  }

  // ignore: unused_element
  Widget _buildDateChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F) : Colors.white,
          border: Border.all(color: selected ? const Color(0xFF1E3A5F) : const Color(0xFFE4E9F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildAttendanceDonut(double rate) {
    // Color bands: green >= 85, orange 70-85, red < 70
    final Color arcColor = rate >= 85
        ? const Color(0xFF22C55E)
        : rate >= 70
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 72,
              startDegreeOffset: -90,
              sections: [
                PieChartSectionData(
                  value: rate,
                  color: arcColor,
                  radius: 26,
                  showTitle: false,
                ),
                PieChartSectionData(
                  value: (100 - rate).clamp(0.0001, 100),
                  color: const Color(0xFFE2E8F0),
                  radius: 26,
                  showTitle: false,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${rate.toStringAsFixed(1)}%',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: arcColor),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tỉ lệ chấm công',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroKpiTiles() {
    final tiles = <_HeroKpi>[
      _HeroKpi('Tổng NV', '$_totalEmployees', Icons.people_alt_rounded, const Color(0xFF1E3A5F), 'total'),
      _HeroKpi('Có mặt', '$_presentCount', Icons.how_to_reg_rounded, const Color(0xFF22C55E), 'present'),
      _HeroKpi('Đi muộn', '$_lateCount', Icons.schedule_rounded, const Color(0xFFF59E0B), 'late'),
      _HeroKpi('Vắng', '$_absentCount', Icons.person_off_rounded, const Color(0xFFEF4444), 'absent'),
      _HeroKpi('Vào / Ra', '$_checkIns / $_checkOuts', Icons.swap_horiz_rounded, const Color(0xFF2D5F8B), 'inout'),
      _HeroKpi('Thiết bị', '$_onlineDevices/$_totalDevices', Icons.router_rounded, const Color(0xFF0F2340), 'devices'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth < 380
            ? 2
            : constraints.maxWidth < 620
                ? 3
                : 3;
        final ratio = constraints.maxWidth < 380 ? 1.7 : 2.0;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: ratio,
          children: tiles.map(_buildHeroKpiTile).toList(),
        );
      },
    );
  }

  Widget _buildHeroKpiTile(_HeroKpi k) {
    final lighter = Color.lerp(k.color, Colors.white, 0.18)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showKpiDetail(k),
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [k.color, lighter],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: k.color.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Stack(
            children: [
              // decorative ring
              Positioned(
                right: -14,
                bottom: -14,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(k.icon, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                k.label,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(Icons.chevron_right,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.7)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          k.value,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== KPI DETAIL SHEET =====================
  void _showKpiDetail(_HeroKpi k) {
    final items = _kpiDetailData(k.kind);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: k.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(k.icon, color: k.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(k.label,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A))),
                            Text('${items.length} mục',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // List
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text('Không có dữ liệu',
                                  style: TextStyle(
                                      color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) => _buildKpiDetailRow(
                              k.kind, items[i], k.color),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _kpiDetailData(String kind) {
    switch (kind) {
      case 'total':
        // Prefer the daily report roster (same source as the summary total)
        // and fall back to the employee list if it's empty.
        if (_dailyReportItems.isNotEmpty) {
          return _dailyReportItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        return _employees
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      case 'present':
        // "Present" = anybody whose status says có mặt / present / đúng giờ /
        // on time / đi muộn / late / sớm / early. We intentionally include
        // late arrivals because the backend's `present` count also includes
        // them.
        return _dailyReportItems.whereType<Map>().where((r) {
          final s = (r['status'] ?? '').toString().toLowerCase();
          if (s.contains('vắng') ||
              s.contains('absent') ||
              s.contains('nghỉ')) return false;
          if (r['checkInTime'] != null) return true;
          return s.contains('có mặt') ||
              s.contains('present') ||
              s.contains('đúng giờ') ||
              s.contains('on time') ||
              s.contains('muộn') ||
              s.contains('late') ||
              s.contains('sớm') ||
              s.contains('early');
        }).map((e) => Map<String, dynamic>.from(e)).toList();
      case 'late':
        return _memoLate.map((e) => Map<String, dynamic>.from(e)).toList();
      case 'absent':
        // Be strict: only items explicitly marked absent (or with no
        // check-in AND status containing "vắng"/"absent"/"nghỉ").
        return _dailyReportItems.whereType<Map>().where((r) {
          final s = (r['status'] ?? '').toString().toLowerCase();
          return s.contains('vắng') ||
              s.contains('absent') ||
              s.contains('nghỉ');
        }).map((e) => Map<String, dynamic>.from(e)).toList();
      case 'inout':
        return _dailyReportItems
            .whereType<Map>()
            .where((r) =>
                r['checkInTime'] != null || r['checkOutTime'] != null)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      case 'devices':
        return _devices
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    }
    return const [];
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s trước';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 30) return '${diff.inDays} ngày trước';
    return '${t.day}/${t.month}/${t.year}';
  }

  Widget _buildKpiDetailRow(
      String kind, Map<String, dynamic> item, Color accent) {
    if (kind == 'devices') {
      final name = (item['deviceName'] ?? item['DeviceName'] ?? '-').toString();
      final sn =
          (item['serialNumber'] ?? item['SerialNumber'] ?? '').toString();
      final ip = (item['ipAddress'] ?? item['IpAddress'] ?? '').toString();
      final isOnline = _isDeviceOnline(item);
      final lastOnlineRaw = item['lastOnline'] ?? item['LastOnline'];
      String lastSeen = '';
      if (lastOnlineRaw != null && !isOnline) {
        try {
          final lo = DateTime.parse(lastOnlineRaw.toString()).toLocal();
          lastSeen = _relativeTime(lo);
        } catch (_) {}
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: (isOnline
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444))
                  .withValues(alpha: .12),
              child: Icon(Icons.router_rounded,
                  color: isOnline
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (sn.isNotEmpty) 'SN: $sn',
                      if (ip.isNotEmpty) 'IP: $ip',
                      if (lastSeen.isNotEmpty) 'Mất KN: $lastSeen',
                    ].join('  •  '),
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isOnline
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOnline
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626)),
              ),
            ),
          ],
        ),
      );
    }

    // Employee / attendance row
    final name = (item['fullName'] ??
            item['FullName'] ??
            item['employeeName'] ??
            item['EmployeeName'] ??
            '-')
        .toString();
    final code = (item['employeeCode'] ??
            item['EmployeeCode'] ??
            item['code'] ??
            '')
        .toString();
    final dept = (item['department'] ??
            item['Department'] ??
            item['departmentName'] ??
            '')
        .toString();
    final ci = _formatTime(item['checkInTime']);
    final co = _formatTime(item['checkOutTime']);
    final status = (item['status'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accent.withValues(alpha: .12),
            child: Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [
                    if (code.isNotEmpty) code,
                    if (dept.isNotEmpty) dept,
                  ].join('  •  '),
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ci.isNotEmpty || co.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        if (ci.isNotEmpty) ...[
                          const Icon(Icons.login,
                              size: 12, color: Color(0xFF22C55E)),
                          const SizedBox(width: 3),
                          Text(ci,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600)),
                        ],
                        if (ci.isNotEmpty && co.isNotEmpty)
                          const SizedBox(width: 10),
                        if (co.isNotEmpty) ...[
                          const Icon(Icons.logout,
                              size: 12, color: Color(0xFFEF4444)),
                          const SizedBox(width: 3),
                          Text(co,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (status.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                status,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: accent),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    try {
      final dt = DateTime.parse(s).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      // fallback: show HH:mm portion if already formatted
      final m = RegExp(r'(\d{1,2}:\d{2})').firstMatch(s);
      return m?.group(1) ?? s;
    }
  }

  // ===================== MAIN GRID =====================
  Widget _buildMainGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1100;
        final isMedium = constraints.maxWidth > 700;

        if (isWide) {
          return Column(
            children: [
              // Row 1: Realtime + Absent
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _buildRealtimeAttendanceCard()),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: _buildAbsentCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 2: Late/Early + Schedule + Birthday
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildLateEarlyCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTodayScheduleCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildBirthdayCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 3: Trends + Department Stats
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _buildAttendanceTrendCard()),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: _buildDepartmentStatsCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 4: KPI + News
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildKpiCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildInternalNewsCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 5: Salary + Device
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildSalaryTodayCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildDeviceStatusCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 6: Pending Approvals + Task Overview
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildPendingApprovalsCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildTaskOverviewCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 7: Overtime + Penalty
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildOvertimeStatsCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildPenaltyStatsCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 8: Financial + Monthly Attendance
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildFinancialSummaryCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMonthlyAttendanceCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 9: Expiring Documents
              _buildExpiringDocsCard(),
              const SizedBox(height: 16),
              // Row 10: HR Insight + Leave Analytics
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildHRInsightCard()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildLeaveAnalyticsCard()),
                ],
              ),
              const SizedBox(height: 16),
              // Row 11: Productivity
              _buildProductivityCard(),
            ],
          );
        }

        return Column(
          children: [
            if (isMedium) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildRealtimeAttendanceCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildAbsentCard()),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildLateEarlyCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildBirthdayCard()),
              ]),
            ] else ...[
              _buildRealtimeAttendanceCard(),
              const SizedBox(height: 16),
              _buildAbsentCard(),
              const SizedBox(height: 16),
              _buildLateEarlyCard(),
              const SizedBox(height: 16),
              _buildBirthdayCard(),
            ],
            const SizedBox(height: 16),
            _buildTodayScheduleCard(),
            const SizedBox(height: 16),
            _buildAttendanceTrendCard(),
            const SizedBox(height: 16),
            _buildDepartmentStatsCard(),
            const SizedBox(height: 16),
            if (isMedium) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildKpiCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildInternalNewsCard()),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildSalaryTodayCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildDeviceStatusCard()),
              ]),
            ] else ...[
              _buildKpiCard(),
              const SizedBox(height: 16),
              _buildInternalNewsCard(),
              const SizedBox(height: 16),
              _buildSalaryTodayCard(),
              const SizedBox(height: 16),
              _buildDeviceStatusCard(),
            ],
            const SizedBox(height: 16),
            if (isMedium) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildPendingApprovalsCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildTaskOverviewCard()),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildOvertimeStatsCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildPenaltyStatsCard()),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildFinancialSummaryCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildMonthlyAttendanceCard()),
              ]),
            ] else ...[
              _buildPendingApprovalsCard(),
              const SizedBox(height: 16),
              _buildTaskOverviewCard(),
              const SizedBox(height: 16),
              _buildOvertimeStatsCard(),
              const SizedBox(height: 16),
              _buildPenaltyStatsCard(),
              const SizedBox(height: 16),
              _buildFinancialSummaryCard(),
              const SizedBox(height: 16),
              _buildMonthlyAttendanceCard(),
            ],
            const SizedBox(height: 16),
            _buildExpiringDocsCard(),
            const SizedBox(height: 16),
            if (isMedium) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: _buildHRInsightCard()),
                const SizedBox(width: 16),
                Expanded(child: _buildLeaveAnalyticsCard()),
              ]),
            ] else ...[
              _buildHRInsightCard(),
              const SizedBox(height: 16),
              _buildLeaveAnalyticsCard(),
            ],
            const SizedBox(height: 16),
            _buildProductivityCard(),
          ],
        );
      },
    );
  }

  // ===================== CARD: REALTIME ATTENDANCE =====================
  Widget _buildRealtimeAttendanceCard() {
    final working = _todayEmployees.whereType<Map<String, dynamic>>().where((e) {
      final s = (e['status'] ?? '').toString().toLowerCase();
      // Exclude absent, leave, no-schedule, day-off, and employees who already left early
      if (s.contains('vắng') || s.contains('absent') || s == 'nghỉ phép' || s.contains('leave')) return false;
      if (s.contains('không có lịch') || s.contains('ngày nghỉ')) return false;
      if (e['checkInTime'] == null) return false;
      return true;
    }).toList();

    return _DashCard(
      icon: Icons.monitor_heart_outlined,
      title: _l10n.realtimeAttendance,
      color: const Color(0xFF1E3A5F),
      badge: '${working.length} working',
      child: Column(
        children: [
          if (working.isEmpty)
            _emptyState(_l10n.noAttendanceToday)
          else
            ...working.take(8).map((e) => _employeeAttendanceRow(e)),
          if (working.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('+${working.length - 8} nhân viên khác',
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _employeeAttendanceRow(Map<String, dynamic> e) {
    final name = (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString();
    final dept = (e['departmentName'] ?? e['department'] ?? '').toString();
    final status = (e['status'] ?? '').toString().toLowerCase();
    final checkIn = e['checkInTime'];
    final checkOut = e['checkOutTime'];
    final isLate = status.contains('muộn') || status.contains('trễ') || status == 'late';
    final isEarlyLeave = status.contains('sớm') || status.contains('early');
    final statusColor = (isLate || isEarlyLeave) ? const Color(0xFFF59E0B) : const Color(0xFF1E3A5F);
    final statusText = isLate && isEarlyLeave ? '${_l10n.late} + Về sớm' : isLate ? _l10n.late : isEarlyLeave ? 'Về sớm' : _l10n.present;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (dept.isNotEmpty) Text(dept, style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11)),
        ])),
        if (checkIn != null)
          Text(_fmtTime(checkIn), style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F))),
        if (checkOut != null) ...[
          const Text(' → ', style: TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
          Text(_fmtTime(checkOut), style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F))),
        ],
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(statusText,
            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  // ===================== CARD: ABSENT EMPLOYEES =====================
  Widget _buildAbsentCard() {
    final withPerm = _absentWithPermission;
    final withoutPerm = _absentWithoutPermission;
    final notScheduled = _notScheduledEmployees;

    return _DashCard(
      icon: Icons.person_off_outlined,
      title: _l10n.absentEmployees,
      color: const Color(0xFFEF4444),
      badge: '${withPerm.length + withoutPerm.length} người',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('${_l10n.authorized} (${withPerm.length})', const Color(0xFFF59E0B)),
        if (withPerm.isEmpty)
          _emptyRow('Không có')
        else
          ...withPerm.take(5).map((l) => _absentRow(
            (l['employeeName'] ?? l['fullName'] ?? 'N/A').toString(),
            _formatLeaveType((l['departmentName'] ?? l['type'] ?? 'Nghỉ phép').toString()), true)),
        const SizedBox(height: 12),
        _sectionLabel('${_l10n.unauthorized} (${withoutPerm.length})', const Color(0xFFEF4444)),
        if (withoutPerm.isEmpty)
          _emptyRow('Không có')
        else
          ...withoutPerm.take(5).map((e) => _absentRow(
            (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString(),
            (e['departmentName'] ?? e['department'] ?? '').toString(), false)),
        if (notScheduled.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel('${_l10n.noSchedule} (${notScheduled.length})', const Color(0xFFA1A1AA)),
          ...notScheduled.take(3).map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              const Icon(Icons.event_busy, size: 14, color: Color(0xFFA1A1AA)),
              const SizedBox(width: 8),
              Expanded(child: Text(
                (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString(),
                style: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)))),
            ]),
          )),
          if (notScheduled.length > 3)
            Text('+${notScheduled.length - 3} người khác',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
        ],
      ]),
    );
  }

  Widget _absentRow(String name, String detail, bool hasPermission) {
    final color = hasPermission ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(hasPermission ? Icons.event_busy : Icons.warning_amber_rounded, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        Text(detail, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
      ]),
    );
  }

  // ===================== CARD: LATE / EARLY =====================
  Widget _buildLateEarlyCard() {
    return _DashCard(
      icon: Icons.timer_off_outlined,
      title: _l10n.lateEarly,
      color: const Color(0xFFF59E0B),
      badge: '${_lateEmployees.length} người',
      child: Column(children: [
        if (_lateEmployees.isEmpty)
          _emptyState(_l10n.noLateEmployees)
        else
          ..._lateEmployees.take(6).map((e) {
            final name = (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString();
            final dept = (e['departmentName'] ?? e['department'] ?? '').toString();
            final lateMinutes = e['lateMinutes'] ?? e['lateBy'] ?? e['averageLateTime'] ?? '';
            final earlyMinutes = e['earlyLeaveMinutes'] ?? 0;
            String lateLabel = '';
            if (lateMinutes is int && lateMinutes > 0) {
              lateLabel = '${lateMinutes}p trễ';
            } else if (lateMinutes.toString().isNotEmpty && lateMinutes.toString() != '0') {
              lateLabel = _formatLateBy(lateMinutes);
            }
            if (earlyMinutes is int && earlyMinutes > 0) {
              if (lateLabel.isNotEmpty) lateLabel += ' | ';
              lateLabel += '${earlyMinutes}p sớm';
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.schedule, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  if (dept.isNotEmpty) Text(dept, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                ])),
                if (lateLabel.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      lateLabel,
                      style: const TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                  ),
              ]),
            );
          }),
      ]),
    );
  }

  // ===================== CARD: BIRTHDAY =====================
  Widget _buildBirthdayCard() {
    final today = _todayBirthdays;
    final monthly = _monthlyBirthdays;
    final totalBirthdays = today.length + monthly.length;

    return _DashCard(
      icon: Icons.cake_outlined,
      title: _l10n.birthday,
      color: const Color(0xFFEC4899),
      badge: totalBirthdays > 0 ? '$totalBirthdays ${_l10n.birthdayThisMonth}' : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (today.isNotEmpty) ...[
          _sectionLabel('🎂 Hôm nay', const Color(0xFFEC4899)),
          ...today.map((e) {
            final name = (e['fullName'] ?? e['firstName'] ?? 'N/A').toString();
            final dept = (e['department'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFFCE7F3), borderRadius: BorderRadius.circular(8)),
                  child: const Text('🎉', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  if (dept.isNotEmpty) Text(dept, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFEC4899), Color(0xFFF472B6)]),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text(_l10n.today, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ]),
            );
          }),
          if (monthly.isNotEmpty) const SizedBox(height: 12),
        ],
        if (monthly.isNotEmpty) ...[
          _sectionLabel('📅 Trong tháng ${DateTime.now().month}', const Color(0xFF0F2340)),
          ...monthly.take(10).map((e) {
            final name = (e['fullName'] ?? e['firstName'] ?? 'N/A').toString();
            final dept = (e['department'] ?? '').toString();
            final day = e['_birthdayDay'] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                const Icon(Icons.cake, size: 14, color: Color(0xFF0F2340)),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 13)),
                  if (dept.toString().isNotEmpty) Text(dept.toString(), style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                ])),
                Text('Ngày $day', style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
              ]),
            );
          }),
        ],
        if (today.isEmpty && monthly.isEmpty)
          _emptyState('${_l10n.birthday} - ${_l10n.birthdayThisMonth}'),
      ]),
    );
  }

  // ===================== CARD: TODAY SCHEDULE =====================
  Widget _buildTodayScheduleCard() {
    final scheduledWorkers = _scheduledCount;
    final schedulesWithShift = _todaySchedules.whereType<Map<String, dynamic>>()
        .where((s) => s['isDayOff'] != true).toList();

    // Group by shift name with attended count (checkInTime != null on daily report)
    final shiftTotal = <String, int>{};
    final shiftAttended = <String, int>{};

    // Build quick lookup: employeeId -> hasCheckedIn
    final attendedIds = <String>{};
    for (final r in _todayEmployees.whereType<Map<String, dynamic>>()) {
      if (r['checkInTime'] != null) {
        final id = (r['employeeId'] ?? r['employeeUserId'] ?? r['employeeCode'] ?? '').toString();
        if (id.isNotEmpty) attendedIds.add(id);
      }
    }

    for (final s in schedulesWithShift) {
      final shiftName = (s['shiftName'] ?? s['shift']?['name'] ?? 'Ca chung').toString();
      shiftTotal[shiftName] = (shiftTotal[shiftName] ?? 0) + 1;
      final id = (s['employeeId'] ?? s['employeeUserId'] ?? s['employeeCode'] ?? '').toString();
      if (id.isNotEmpty && attendedIds.contains(id)) {
        shiftAttended[shiftName] = (shiftAttended[shiftName] ?? 0) + 1;
      }
    }

    // Determine current shift
    final hour = _now.hour;
    String currentShift;
    IconData shiftIcon;
    Color shiftColor;
    if (hour >= 6 && hour < 14) {
      currentShift = 'Ca sáng';
      shiftIcon = Icons.wb_sunny;
      shiftColor = const Color(0xFFF59E0B);
    } else if (hour >= 14 && hour < 22) {
      currentShift = 'Ca chiều';
      shiftIcon = Icons.wb_twilight;
      shiftColor = const Color(0xFFEF4444);
    } else {
      currentShift = 'Ca đêm';
      shiftIcon = Icons.nightlight;
      shiftColor = const Color(0xFF1E3A5F);
    }

    return _DashCard(
      icon: Icons.calendar_today_outlined,
      title: _l10n.todaySchedule,
      color: const Color(0xFF1E3A5F),
      badge: '$scheduledWorkers NV được xếp lịch',
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [shiftColor.withValues(alpha: 0.1), shiftColor.withValues(alpha: 0.05)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: shiftColor.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: shiftColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
              child: Icon(shiftIcon, color: shiftColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ca hiện tại', style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
              const SizedBox(height: 2),
              Text(currentShift, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: shiftColor)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: shiftColor, borderRadius: BorderRadius.circular(20)),
              child: Text('$_presentCount/$scheduledWorkers',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (shiftTotal.isNotEmpty)
          ...shiftTotal.entries.map((e) {
            final total = e.value;
            final attended = shiftAttended[e.key] ?? 0;
            final rate = total > 0 ? (attended / total) : 0.0;
            final rateColor = rate >= 0.8
                ? const Color(0xFF1E3A5F)
                : rate >= 0.5
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFEF4444);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.access_time, size: 14, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  Text('$attended/$total',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: rateColor)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rate, minHeight: 5,
                    backgroundColor: const Color(0xFFE4E4E7),
                    valueColor: AlwaysStoppedAnimation(rateColor),
                  ),
                ),
              ]),
            );
          }),
        if (shiftTotal.isEmpty && scheduledWorkers == 0)
          _emptyState(_l10n.noScheduledToday),
        const SizedBox(height: 10),
        Row(children: [
          _scheduleInfoBox('Tổng NV', '$_totalEmployees', Icons.groups, const Color(0xFF1E3A5F)),
          const SizedBox(width: 10),
          _scheduleInfoBox('Xếp lịch', '$scheduledWorkers', Icons.event_available, const Color(0xFF1E3A5F)),
          const SizedBox(width: 10),
          _scheduleInfoBox('Nghỉ/Trống', '${_notScheduledEmployees.length}', Icons.event_busy, const Color(0xFFA1A1AA)),
        ]),
      ]),
    );
  }

  Widget _scheduleInfoBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)), textAlign: TextAlign.center),
        ]),
      ),
    );
  }

  // ===================== CARD: ATTENDANCE TREND =====================
  Widget _buildAttendanceTrendCard() {
    return _DashCard(
      icon: Icons.trending_up_rounded,
      title: _l10n.attendanceTrend7Days,
      color: const Color(0xFF1E3A5F),
      child: _trends.isEmpty
          ? _emptyState('Chưa có dữ liệu xu hướng')
          : Column(children: [
              SizedBox(
                height: 160,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _trends.take(7).map((t) {
                    final present = _toInt(t['present'] ?? t['totalCheckIns'] ?? 0);
                    final late = _toInt(t['late'] ?? t['lateArrivals'] ?? 0);
                    final absent = _toInt(t['absent'] ?? t['absences'] ?? 0);
                    final total = present + absent + late;
                    final maxVal = _trends.fold<int>(0, (m, tr) {
                      final p = _toInt(tr['present'] ?? tr['totalCheckIns'] ?? 0);
                      final a = _toInt(tr['absent'] ?? tr['absences'] ?? 0);
                      final l = _toInt(tr['late'] ?? tr['lateArrivals'] ?? 0);
                      return (p + a + l) > m ? (p + a + l) : m;
                    });
                    final date = DateTime.tryParse(t['date']?.toString() ?? '');
                    final dayLabel = date != null ? '${date.day}/${date.month}' : '';
                    final presentH = maxVal > 0 ? (present / maxVal * 120) : 0.0;
                    final lateH = maxVal > 0 ? (late / maxVal * 120) : 0.0;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          Text('$total', style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
                          const SizedBox(height: 4),
                          Container(height: lateH, decoration: const BoxDecoration(
                            color: Color(0xFFF59E0B), borderRadius: BorderRadius.vertical(top: Radius.circular(4)))),
                          Container(height: presentH, decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F),
                            borderRadius: lateH == 0 ? const BorderRadius.vertical(top: Radius.circular(4)) : null)),
                          const SizedBox(height: 6),
                          Text(dayLabel, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _legendDot(_l10n.present, const Color(0xFF1E3A5F)),
                const SizedBox(width: 16),
                _legendDot(_l10n.late, const Color(0xFFF59E0B)),
              ]),
            ]),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
    ]);
  }

  // ===================== CARD: DEPARTMENT STATS =====================
  Widget _buildDepartmentStatsCard() {
    final deptMap = <String, Map<String, int>>{};
    for (final e in _todayEmployees) {
      if (e is Map<String, dynamic>) {
        final dept = (e['departmentName'] ?? e['department'] ?? '').toString();
        if (dept.isEmpty || dept == 'N/A') continue;
        final status = (e['status'] ?? '').toString().toLowerCase();
        // Skip employees with no schedule or day off - they shouldn't be in dept stats
        if (status.contains('không có lịch') || status.contains('ngày nghỉ')) continue;
        deptMap.putIfAbsent(dept, () => {'total': 0, 'present': 0});
        deptMap[dept]!['total'] = (deptMap[dept]!['total'] ?? 0) + 1;
        if (status != 'vắng mặt' && status != 'absent' && status != 'nghỉ phép' && status != 'leave') {
          deptMap[dept]!['present'] = (deptMap[dept]!['present'] ?? 0) + 1;
        }
      }
    }
    final departments = deptMap.entries.map((e) => <String, dynamic>{
      'name': e.key,
      'totalEmployees': e.value['total'] ?? 0,
      'presentToday': e.value['present'] ?? 0,
    }).toList()..sort((a, b) => (b['totalEmployees'] as int).compareTo(a['totalEmployees'] as int));

    return _DashCard(
      icon: Icons.business_outlined,
      title: _l10n.byDepartment,
      color: const Color(0xFF0F2340),
      child: departments.isEmpty
          ? _emptyState('Chưa có dữ liệu phòng ban')
          : Column(children: departments.take(6).map((d) {
              final name = d['name'] ?? 'N/A';
              final total = d['totalEmployees'] ?? 0;
              final present = d['presentToday'] ?? 0;
              final rate = total > 0 ? (present / total * 100) : 0.0;
              final rateColor = rate >= 80 ? const Color(0xFF1E3A5F) : rate >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.apartment, size: 14, color: Color(0xFF0F2340)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                    Text('$present/$total', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                    const SizedBox(width: 8),
                    SizedBox(width: 40, child: Text('${rate.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: rateColor),
                      textAlign: TextAlign.right)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: rate / 100, minHeight: 4,
                      backgroundColor: const Color(0xFFE4E4E7),
                      valueColor: AlwaysStoppedAnimation(rateColor))),
                ]),
              );
            }).toList()),
    );
  }

  // ===================== CARD: KPI =====================
  Widget _buildKpiCard() {
    final periodName = (_kpiDashboard['currentPeriodName'] ?? '').toString();
    final avgScore = ((_kpiDashboard['averageKpiScore'] ?? 0) as num).toDouble();
    final totalBonusAmount = ((_kpiDashboard['totalBonusAmount'] ?? 0) as num).toDouble();
    final totalKpiEmployees = ((_kpiDashboard['totalEmployees'] ?? 0) as num).toInt();
    final totalApproved = ((_kpiDashboard['totalApproved'] ?? 0) as num).toInt();
    final totalCalculated = ((_kpiDashboard['totalSalaryCalculated'] ?? 0) as num).toInt();
    final hasKpiDashboard = periodName.isNotEmpty;

    return _DashCard(
      icon: Icons.speed_outlined,
      title: _l10n.kpiToDate,
      color: const Color(0xFF2D5F8B),
      badge: hasKpiDashboard ? periodName : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // KPI Dashboard summary
        if (hasKpiDashboard) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFF2D5F8B).withValues(alpha: 0.08),
                const Color(0xFF2D5F8B).withValues(alpha: 0.03),
              ]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2D5F8B).withValues(alpha: 0.15)),
            ),
            child: Column(children: [
              Row(children: [
                Expanded(child: _kpiSummaryItem('Điểm TB', avgScore.toStringAsFixed(1),
                    avgScore >= 80 ? const Color(0xFF1E3A5F) : avgScore >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444))),
                Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
                Expanded(child: _kpiSummaryItem('NV đánh giá', '$totalKpiEmployees', const Color(0xFF1E3A5F))),
                Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
                Expanded(child: _kpiSummaryItem('Đã duyệt', '$totalApproved/$totalCalculated', const Color(0xFF1E3A5F))),
              ]),
              if (totalBonusAmount > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.monetization_on, size: 14, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 6),
                  Text('Tổng thưởng KPI: ${_formatCurrency(totalBonusAmount)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E3A5F))),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // Individual KPI results
        if (_kpiResults.isEmpty && !hasKpiDashboard)
          _emptyState('Chưa có dữ liệu KPI')
        else if (_kpiResults.isNotEmpty) ...[
          _sectionLabel(_l10n.topKpiEmployees, const Color(0xFF2D5F8B)),
          ..._kpiResults.take(5).map((k) {
            final name = (k['employeeName'] ?? k['kpiConfigName'] ?? k['name'] ?? 'N/A').toString();
            final score = ((k['weightedScore'] ?? k['actualValue'] ?? k['totalScore'] ?? 0) as num).toDouble();
            final target = ((k['targetValue'] ?? k['target'] ?? 100) as num).toDouble();
            final pct = (k['completionRate'] != null)
                ? ((k['completionRate'] as num).toDouble()).clamp(0.0, 100.0)
                : (target > 0 ? (score / target * 100).clamp(0.0, 100.0) : 0.0);
            Color kpiColor;
            String kpiLabel;
            if (pct >= 90) { kpiColor = const Color(0xFF1E3A5F); kpiLabel = 'Xuất sắc'; }
            else if (pct >= 70) { kpiColor = const Color(0xFF1E3A5F); kpiLabel = 'Tốt'; }
            else if (pct >= 50) { kpiColor = const Color(0xFFF59E0B); kpiLabel = 'Trung bình'; }
            else { kpiColor = const Color(0xFFEF4444); kpiLabel = 'Cần cải thiện'; }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 36, height: 36, child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: pct / 100, strokeWidth: 3,
                    backgroundColor: const Color(0xFFE4E4E7), valueColor: AlwaysStoppedAnimation(kpiColor)),
                  Text('${pct.toInt()}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: kpiColor)),
                ])),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(kpiLabel, style: TextStyle(fontSize: 11, color: kpiColor)),
                ])),
                Text('${score.toStringAsFixed(0)}/${target.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _kpiSummaryItem(String label, String value, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)), textAlign: TextAlign.center),
    ]);
  }

  String _formatCurrency(double amount) {
    if (amount >= 1e9) return '${(amount / 1e9).toStringAsFixed(1)} tỷ';
    if (amount >= 1e6) return '${(amount / 1e6).toStringAsFixed(1)} tr';
    if (amount >= 1e3) return '${(amount / 1e3).toStringAsFixed(0)}k';
    return amount.toStringAsFixed(0);
  }

  // ===================== CARD: INTERNAL NEWS =====================
  Widget _buildInternalNewsCard() {
    return _DashCard(
      icon: Icons.newspaper_outlined,
      title: _l10n.internalNews,
      color: const Color(0xFF0F2340),
      child: _communications.isEmpty
          ? _emptyState('Chưa có bản tin nội bộ')
          : Column(children: _communications.take(5).map((c) {
              final title = (c['title'] ?? 'Không tiêu đề').toString();
              final type = (c['type'] ?? '').toString();
              final created = c['createdAt'] ?? c['publishedAt'];
              String typeLabel = 'Thông báo';
              IconData typeIcon = Icons.info_outline;
              Color typeColor = const Color(0xFF1E3A5F);
              switch (type) {
                case 'News':
                  typeLabel = 'Tin tức'; typeIcon = Icons.article; typeColor = const Color(0xFF0F2340);
                case 'Event':
                  typeLabel = 'Sự kiện'; typeIcon = Icons.event; typeColor = const Color(0xFF0F2340);
                case 'Policy':
                  typeLabel = 'Chính sách'; typeIcon = Icons.policy; typeColor = const Color(0xFFF59E0B);
                case 'Training':
                  typeLabel = 'Đào tạo'; typeIcon = Icons.school; typeColor = const Color(0xFF2D5F8B);
                case 'Culture':
                  typeLabel = 'Văn hóa'; typeIcon = Icons.diversity_3; typeColor = const Color(0xFFEC4899);
                case 'Recruitment':
                  typeLabel = 'Tuyển dụng'; typeIcon = Icons.person_add; typeColor = const Color(0xFF1E3A5F);
                case 'Regulation':
                  typeLabel = 'Quy định'; typeIcon = Icons.gavel; typeColor = const Color(0xFFEF4444);
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(typeIcon, size: 16, color: typeColor)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Text(typeLabel, style: TextStyle(fontSize: 10, color: typeColor))),
                      if (created != null) ...[
                        const SizedBox(width: 6),
                        Text(_fmtDate(created), style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
                      ],
                    ]),
                  ])),
                ]),
              );
            }).toList()),
    );
  }

  // ===================== CARD: SALARY TODAY =====================
  Widget _buildSalaryTodayCard() {
    const workStart = 8;
    const workEnd = 17;
    final totalWorkHours = (workEnd - workStart).toDouble();
    final nowMinutes = _now.hour * 60 + _now.minute;
    final hoursWorked = ((nowMinutes - workStart * 60).clamp(0, (workEnd - workStart) * 60) / 60.0);
    final progress = (hoursWorked / totalWorkHours).clamp(0.0, 1.0);

    return _DashCard(
      icon: Icons.payments_outlined,
      title: 'Lương ngày hôm nay',
      color: const Color(0xFF1E3A5F),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              const Color(0xFF1E3A5F).withValues(alpha: 0.08),
              const Color(0xFF1E3A5F).withValues(alpha: 0.03)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.15)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Tiến độ ngày làm việc', style: TextStyle(fontSize: 12, color: Color(0xFF71717A))),
              Text('${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: progress, minHeight: 8,
                backgroundColor: const Color(0xFFE4E4E7),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF1E3A5F)))),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _salaryInfo('Giờ vào', '${workStart.toString().padLeft(2, '0')}:00'),
              _salaryInfo('Giờ ra', '${workEnd.toString().padLeft(2, '0')}:00'),
              _salaryInfo('Đã làm', '${hoursWorked.toStringAsFixed(1)}h'),
              _salaryInfo('Còn lại', '${(totalWorkHours - hoursWorked).clamp(0, totalWorkHours).toStringAsFixed(1)}h'),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _salaryStatBox(_l10n.present, '$_presentCount/$_totalEmployees', Icons.people, const Color(0xFF1E3A5F))),
          const SizedBox(width: 8),
          Expanded(child: _salaryStatBox(_l10n.attendanceRate, '${_attendanceRate.toStringAsFixed(1)}%', Icons.pie_chart, const Color(0xFF1E3A5F))),
        ]),
      ]),
    );
  }

  Widget _salaryInfo(String label, String value) {
    return Column(children: [
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
      Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
    ]);
  }

  Widget _salaryStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12))),
      child: Row(children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
        ]),
      ]),
    );
  }

  // ===================== CARD: DEVICE STATUS =====================
  Widget _buildDeviceStatusCard() {
    final online = _devices.whereType<Map>().where(_isDeviceOnline).toList();
    final offline =
        _devices.whereType<Map>().where((d) => !_isDeviceOnline(d)).toList();

    return _DashCard(
      icon: Icons.devices_other_outlined,
      title: 'Trạng thái thiết bị',
      color: const Color(0xFF0F2340),
      badge: '$_onlineDevices/$_totalDevices online',
      child: Column(children: [
        Row(children: [
          _miniChip('Online', '${online.length}', const Color(0xFF1E3A5F)),
          const SizedBox(width: 8),
          _miniChip('Offline', '${offline.length}', const Color(0xFFEF4444)),
        ]),
        const SizedBox(height: 12),
        if (_devices.isEmpty)
          _emptyState('Chưa có thiết bị')
        else
          ..._devices.whereType<Map>().take(5).map((d) {
            final name = (d['deviceName'] ?? d['name'] ?? 'N/A').toString();
            final isOn = _isDeviceOnline(d);
            final ip = (d['ipAddress'] ?? '').toString();
            final loc = (d['location'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                  color: isOn ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  if (ip.isNotEmpty || loc.isNotEmpty)
                    Text([if (ip.isNotEmpty) ip, if (loc.isNotEmpty) loc].join(' • '),
                      style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isOn ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12)),
                  child: Text(isOn ? 'Online' : 'Offline',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: isOn ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444))),
                ),
              ]),
            );
          }),
      ]),
    );
  }

  // ===================== CARD: PENDING APPROVALS =====================
  Widget _buildPendingApprovalsCard() {
    final leaveCount = _pendingLeaves.length;
    final correctionCount = _pendingCorrections.length;
    final swapCount = _pendingSwaps.length;
    final advanceCount = _pendingAdvances.length;
    final totalPending = leaveCount + correctionCount + swapCount + advanceCount;

    return _DashCard(
      icon: Icons.pending_actions_outlined,
      title: 'Phê duyệt chờ xử lý',
      color: const Color(0xFFF59E0B),
      badge: totalPending > 0 ? '$totalPending đơn' : null,
      child: Column(children: [
        _approvalRow(Icons.event_busy, 'Đơn nghỉ phép', leaveCount, const Color(0xFFF59E0B)),
        const SizedBox(height: 8),
        _approvalRow(Icons.edit_note, 'Chỉnh sửa chấm công', correctionCount, const Color(0xFF2D5F8B)),
        const SizedBox(height: 8),
        _approvalRow(Icons.swap_horiz, 'Đổi ca làm việc', swapCount, const Color(0xFFEC4899)),
        const SizedBox(height: 8),
        _approvalRow(Icons.account_balance_wallet_outlined, 'Yêu cầu ứng lương', advanceCount, const Color(0xFF10B981)),
        if (totalPending == 0) ...[
          const SizedBox(height: 12),
          _emptyState('Không có đơn chờ duyệt'),
        ],
        if (totalPending > 0) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(child: Text('$totalPending đơn cần được xử lý',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFD97706)))),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _approvalRow(IconData icon, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: count > 0 ? color : const Color(0xFFE4E4E7),
            borderRadius: BorderRadius.circular(20)),
          child: Text('$count',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
              color: count > 0 ? Colors.white : const Color(0xFFA1A1AA))),
        ),
      ]),
    );
  }

  // ===================== CARD: TASK OVERVIEW =====================
  Widget _buildTaskOverviewCard() {
    final total = _toInt(_taskStats['totalTasks'] ?? _taskStats['total'] ?? 0);
    final todo = _toInt(_taskStats['todoCount'] ?? _taskStats['pending'] ?? _taskStats['notStarted'] ?? 0);
    final inProgress = _toInt(_taskStats['inProgressCount'] ?? _taskStats['inProgress'] ?? 0);
    final done = _toInt(_taskStats['completedCount'] ?? _taskStats['completed'] ?? _taskStats['done'] ?? 0);
    final overdue = _toInt(_taskStats['overdueCount'] ?? _taskStats['overdue'] ?? 0);

    return _DashCard(
      icon: Icons.task_alt_outlined,
      title: 'Tổng quan công việc',
      color: const Color(0xFF2D5F8B),
      badge: total > 0 ? '$total việc' : null,
      child: total == 0
          ? _emptyState('Chưa có dữ liệu công việc')
          : Column(children: [
              Row(children: [
                _taskStatBox('Chờ làm', '$todo', Icons.hourglass_empty, const Color(0xFFA1A1AA)),
                const SizedBox(width: 8),
                _taskStatBox('Đang làm', '$inProgress', Icons.play_circle_outline, const Color(0xFF2D5F8B)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _taskStatBox('Hoàn thành', '$done', Icons.check_circle_outline, const Color(0xFF1E3A5F)),
                const SizedBox(width: 8),
                _taskStatBox('Quá hạn', '$overdue', Icons.error_outline, const Color(0xFFEF4444)),
              ]),
              if (total > 0) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: Row(children: [
                      if (done > 0) Expanded(flex: done, child: Container(color: const Color(0xFF1E3A5F))),
                      if (inProgress > 0) Expanded(flex: inProgress, child: Container(color: const Color(0xFF2D5F8B))),
                      if (todo > 0) Expanded(flex: todo, child: Container(color: const Color(0xFFE4E4E7))),
                      if (overdue > 0) Expanded(flex: overdue, child: Container(color: const Color(0xFFEF4444))),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text('Tỷ lệ hoàn thành: ${total > 0 ? (done / total * 100).toStringAsFixed(0) : 0}%',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
              ],
            ]),
    );
  }

  Widget _taskStatBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
          ]),
        ]),
      ),
    );
  }

  // ===================== CARD: OVERTIME STATS =====================
  Widget _buildOvertimeStatsCard() {
    final totalHours = ((_overtimeStats['totalHours'] ?? _overtimeStats['totalOvertimeHours'] ?? 0) as num).toDouble();
    final totalEmployees = _toInt(_overtimeStats['totalEmployees'] ?? _overtimeStats['employeeCount'] ?? 0);
    final pending = _toInt(_overtimeStats['pendingCount'] ?? _overtimeStats['pending'] ?? 0);
    final approved = _toInt(_overtimeStats['approvedCount'] ?? _overtimeStats['approved'] ?? 0);
    final totalAmount = ((_overtimeStats['totalAmount'] ?? _overtimeStats['totalCost'] ?? 0) as num).toDouble();

    return _DashCard(
      icon: Icons.more_time_outlined,
      title: 'Thống kê tăng ca',
      color: const Color(0xFF0F2340),
      badge: totalHours > 0 ? '${totalHours.toStringAsFixed(1)}h' : null,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              const Color(0xFF0F2340).withValues(alpha: 0.08),
              const Color(0xFF0F2340).withValues(alpha: 0.03)]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF0F2340).withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Expanded(child: _kpiSummaryItem('Tổng giờ TC', totalHours.toStringAsFixed(1), const Color(0xFF0F2340))),
            Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
            Expanded(child: _kpiSummaryItem('Số NV', '$totalEmployees', const Color(0xFF2D5F8B))),
            Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
            Expanded(child: _kpiSummaryItem('Chờ duyệt', '$pending', pending > 0 ? const Color(0xFFF59E0B) : const Color(0xFFA1A1AA))),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.check_circle, size: 20, color: Color(0xFF1E3A5F)),
              const SizedBox(height: 4),
              Text('$approved', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
              const Text('Đã duyệt', style: TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
            ]),
          )),
          const SizedBox(width: 8),
          Expanded(child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.monetization_on, size: 20, color: Color(0xFF1E3A5F)),
              const SizedBox(height: 4),
              Text(_formatCurrency(totalAmount), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
              const Text('Chi phí TC', style: TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
            ]),
          )),
        ]),
      ]),
    );
  }

  // ===================== CARD: PENALTY STATS =====================
  Widget _buildPenaltyStatsCard() {
    final totalTickets = _toInt(_penaltyStats['totalTickets'] ?? _penaltyStats['total'] ?? _penaltyStats['count'] ?? 0);
    final totalAmount = ((_penaltyStats['totalAmount'] ?? _penaltyStats['totalFine'] ?? 0) as num).toDouble();
    final lateCount = _toInt(_penaltyStats['lateCount'] ?? _penaltyStats['totalLate'] ?? 0);
    final absentCount = _toInt(_penaltyStats['absentCount'] ?? _penaltyStats['totalAbsent'] ?? 0);
    final otherCount = _toInt(_penaltyStats['otherCount'] ?? _penaltyStats['totalOther'] ?? 0);

    return _DashCard(
      icon: Icons.gavel_outlined,
      title: 'Thống kê vi phạm',
      color: const Color(0xFFEF4444),
      badge: totalTickets > 0 ? '$totalTickets phiếu' : null,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_long, size: 22, color: Color(0xFFEF4444)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$totalTickets phiếu phạt', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
              Text('Tổng: ${_formatCurrency(totalAmount)}', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        _penaltyTypeRow('Đi trễ', lateCount, const Color(0xFFF59E0B)),
        const SizedBox(height: 6),
        _penaltyTypeRow('Vắng mặt', absentCount, const Color(0xFFEF4444)),
        const SizedBox(height: 6),
        _penaltyTypeRow('Khác', otherCount, const Color(0xFFA1A1AA)),
        if (totalTickets == 0) ...[
          const SizedBox(height: 8),
          _emptyState('Không có vi phạm tháng này'),
        ],
      ]),
    );
  }

  Widget _penaltyTypeRow(String label, int count, Color color) {
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
        child: Text('$count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ),
    ]);
  }

  // ===================== CARD: FINANCIAL SUMMARY =====================
  Widget _buildFinancialSummaryCard() {
    final totalIncome = ((_cashSummary['totalIncome'] ?? _cashSummary['income'] ?? 0) as num).toDouble();
    final totalExpense = ((_cashSummary['totalExpense'] ?? _cashSummary['expense'] ?? 0) as num).toDouble();
    final balance = ((_cashSummary['balance'] ?? _cashSummary['net'] ?? (totalIncome - totalExpense)) as num).toDouble();
    final transactionCount = _toInt(_cashSummary['transactionCount'] ?? _cashSummary['count'] ?? 0);

    return _DashCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Thu chi tháng ${_now.month}',
      color: const Color(0xFF1E3A5F),
      badge: transactionCount > 0 ? '$transactionCount giao dịch' : null,
      child: Column(children: [
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.arrow_downward, size: 20, color: Color(0xFF1E3A5F)),
              const SizedBox(height: 4),
              Text(_formatCurrency(totalIncome),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
              const Text('Thu', style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
            ]),
          )),
          const SizedBox(width: 8),
          Expanded(child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.arrow_upward, size: 20, color: Color(0xFFEF4444)),
              const SizedBox(height: 4),
              Text(_formatCurrency(totalExpense),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
              const Text('Chi', style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
            ]),
          )),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              (balance >= 0 ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)).withValues(alpha: 0.08),
              (balance >= 0 ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)).withValues(alpha: 0.03)]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (balance >= 0 ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)).withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(balance >= 0 ? Icons.trending_up : Icons.trending_down,
              size: 22, color: balance >= 0 ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Số dư', style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
              Text(_formatCurrency(balance.abs()),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: balance >= 0 ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444))),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (balance >= 0 ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444)).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20)),
              child: Text(balance >= 0 ? 'Dương' : 'Âm',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                  color: balance >= 0 ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444))),
            ),
          ]),
        ),
      ]),
    );
  }

  // ===================== CARD: MONTHLY ATTENDANCE =====================
  Widget _buildMonthlyAttendanceCard() {
    final items = _monthlyReport['items'] as List<dynamic>? ?? [];
    final summary = _monthlyReport['summary'] as Map<String, dynamic>? ?? _monthlyReport;
    final totalWorkDays = _toInt(summary['totalWorkDays'] ?? summary['workingDays'] ?? 0);
    final avgAttendanceRate = ((summary['averageAttendanceRate'] ?? summary['attendanceRate'] ?? 0) as num).toDouble();
    final totalLate = _toInt(summary['totalLateCount'] ?? summary['lateCount'] ?? 0);
    final totalAbsent = _toInt(summary['totalAbsentCount'] ?? summary['absentCount'] ?? 0);

    return _DashCard(
      icon: Icons.calendar_month_outlined,
      title: 'Chấm công tháng ${_now.month}',
      color: const Color(0xFF2D5F8B),
      badge: avgAttendanceRate > 0 ? '${avgAttendanceRate.toStringAsFixed(1)}%' : null,
      child: Column(children: [
        Row(children: [
          _monthStatBox('Ngày công', '$totalWorkDays', Icons.work_outline, const Color(0xFF1E3A5F)),
          const SizedBox(width: 8),
          _monthStatBox('Tỷ lệ CC', '${avgAttendanceRate.toStringAsFixed(0)}%', Icons.pie_chart_outline,
            avgAttendanceRate >= 80 ? const Color(0xFF1E3A5F) : const Color(0xFFF59E0B)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _monthStatBox('Đi trễ', '$totalLate', Icons.schedule, const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          _monthStatBox('Vắng', '$totalAbsent', Icons.person_off, const Color(0xFFEF4444)),
        ]),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('NV nhiều ngày vắng nhất', const Color(0xFF2D5F8B)),
          ...items.whereType<Map<String, dynamic>>()
            .where((e) => _toInt(e['absentDays'] ?? e['totalAbsent'] ?? 0) > 0)
            .take(4).map((e) {
              final name = (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString();
              final absentDays = _toInt(e['absentDays'] ?? e['totalAbsent'] ?? 0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  const Icon(Icons.person, size: 14, color: Color(0xFFEF4444)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name, style: const TextStyle(fontSize: 13))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text('$absentDays ngày',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
                  ),
                ]),
              );
            }),
        ],
        if (items.isEmpty && totalWorkDays == 0)
          _emptyState('Chưa có dữ liệu tháng này'),
      ]),
    );
  }

  Widget _monthStatBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
          ]),
        ]),
      ),
    );
  }

  // ===================== CARD: EXPIRING DOCUMENTS =====================
  Widget _buildExpiringDocsCard() {
    return _DashCard(
      icon: Icons.description_outlined,
      title: 'Tài liệu sắp hết hạn',
      color: const Color(0xFFD97706),
      badge: _expiringDocs.isNotEmpty ? '${_expiringDocs.length} tài liệu' : null,
      child: _expiringDocs.isEmpty
          ? _emptyState('Không có tài liệu sắp hết hạn')
          : Column(children: _expiringDocs.take(6).map((d) {
              final title = (d['title'] ?? d['documentName'] ?? d['name'] ?? 'N/A').toString();
              final employee = (d['employeeName'] ?? d['fullName'] ?? '').toString();
              final expiry = DateTime.tryParse((d['expiryDate'] ?? d['endDate'] ?? '').toString());
              final daysLeft = expiry != null ? expiry.difference(DateTime.now()).inDays : 0;
              final isUrgent = daysLeft <= 7;
              final statusColor = isUrgent ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
              final statusText = daysLeft <= 0 ? 'Hết hạn' : '$daysLeft ngày';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Icon(isUrgent ? Icons.warning_amber : Icons.schedule, size: 16, color: statusColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (employee.isNotEmpty)
                      Text(employee, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                    child: Text(statusText,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ]),
              );
            }).toList()),
    );
  }

  // ===================== HELPER WIDGETS =====================
  Widget _miniChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8))),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Icon(Icons.inbox_outlined, size: 32, color: Colors.grey[300]),
        const SizedBox(height: 8),
        Text(message, style: TextStyle(fontSize: 13, color: Colors.grey[400]), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _emptyRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA))),
    );
  }

  // ===================== FORMATTERS =====================
  int _toInt(dynamic v) => (v is int) ? v : int.tryParse(v.toString()) ?? 0;

  String _weekday(int wd) {
    const days = ['', 'Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
    return days[wd];
  }

  String _fmtTime(dynamic t) {
    if (t == null) return '';
    final raw = t.toString();
    // TimeSpan values from backend (e.g. shift start "08:30:00") — return as HH:mm.
    if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(raw)) {
      final parts = raw.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    try {
      // AttendanceTime is stored UTC; Dart's DateTime.parse treats bare ISO strings
      // (no Z/offset) as local, which shows VN punches 7h off. Force UTC, then shift to VN.
      final hasTz = raw.endsWith('Z') || raw.contains('+') ||
          RegExp(r'-\d{2}:\d{2}$').hasMatch(raw);
      final dt = hasTz ? DateTime.parse(raw).toUtc() : DateTime.parse('${raw}Z').toUtc();
      final vn = dt.add(const Duration(hours: 7));
      return '${vn.hour.toString().padLeft(2, '0')}:${vn.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) { return d.toString(); }
  }

  String _formatLateBy(dynamic value) {
    if (value == null) return '';
    final s = value.toString();
    if (s.contains(':')) {
      final parts = s.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      if (h > 0) return '${h}g${m}p trễ';
      if (m > 0) return '${m}p trễ';
      return 'Đúng giờ';
    }
    if (s.contains('min')) return s;
    return '${s}p trễ';
  }

  String _formatLeaveType(String type) {
    switch (type) {
      case 'AnnualLeave': return 'Phép năm';
      case 'Holiday': return 'Lễ tết';
      case 'PersonalPaid': return 'Việc riêng có lương';
      case 'PersonalUnpaid': return 'Việc riêng không lương';
      case 'SickLeave': return 'Ốm đau';
      case 'MaternityLeave': return 'Thai sản';
      case 'CompensatoryLeave': return 'Nghỉ bù';
      case 'LongTermLeave': return 'Nghỉ dài hạn';
      default: return type;
    }
  }

  // ===================== CARD: HR INSIGHT =====================
  Widget _buildHRInsightCard() {
    // Gender breakdown from employees list
    int male = 0, female = 0, other = 0;
    int withContract = 0;
    final deptCountMap = <String, int>{};

    for (final e in _employees) {
      if (e is! Map<String, dynamic>) continue;
      final gender = (e['gender'] ?? e['Gender'] ?? '').toString().toLowerCase();
      if (gender == 'male' || gender == 'nam' || gender == '1') {
        male++;
      } else if (gender == 'female' || gender == 'nữ' || gender == '0') {
        female++;
      } else {
        other++;
      }
      final contractType = e['contractType'] ?? e['employmentType'] ?? '';
      if (contractType.toString().isNotEmpty) withContract++;

      final dept = (e['departmentName'] ?? e['department'] ?? '').toString();
      if (dept.isNotEmpty && dept != 'N/A') {
        deptCountMap[dept] = (deptCountMap[dept] ?? 0) + 1;
      }
    }

    final total = _employees.length;
    final topDepts = (deptCountMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(4)
        .toList();

    return _DashCard(
      icon: Icons.groups_3_outlined,
      title: 'Phân tích nhân sự',
      color: const Color(0xFF0F2340),
      badge: '$total nhân viên',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Gender strip
        Row(children: [
          _hrStatMini(Icons.male_rounded, 'Nam', '$male', const Color(0xFF2D5F8B)),
          const SizedBox(width: 8),
          _hrStatMini(Icons.female_rounded, 'Nữ', '$female', const Color(0xFFEC4899)),
          const SizedBox(width: 8),
          _hrStatMini(Icons.person_outlined, 'Khác', '$other', const Color(0xFF71717A)),
          const SizedBox(width: 8),
          _hrStatMini(Icons.person_add_outlined, 'NV mới', '${_newHiresThisMonth()}', const Color(0xFF22C55E)),
        ]),
        const SizedBox(height: 12),
        if (male + female + other > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                if (male > 0) Flexible(flex: male, child: Container(height: 8, color: const Color(0xFF2D5F8B))),
                if (female > 0) Flexible(flex: female, child: Container(height: 8, color: const Color(0xFFEC4899))),
                if (other > 0) Flexible(flex: other, child: Container(height: 8, color: const Color(0xFF71717A))),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Top departments
        if (topDepts.isNotEmpty) ...[
          const Text('Top phòng ban', style: TextStyle(fontSize: 11, color: Color(0xFF71717A), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...topDepts.map((e) {
            final pct = total > 0 ? e.value / total : 0.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text('${e.value} NV', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                  const SizedBox(width: 6),
                  Text('${(pct * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0F2340))),
                ]),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct, minHeight: 4,
                    backgroundColor: const Color(0xFFE4E4E7),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF1E3A5F)),
                  ),
                ),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _hrStatMini(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF71717A))),
        ]),
      ),
    );
  }

  // ===================== CARD: LEAVE ANALYTICS =====================
  Widget _buildLeaveAnalyticsCard() {
    // Build leave type breakdown from all known leave lists
    final allLeaves = <Map<String, dynamic>>[
      ..._pendingLeaves.whereType<Map<String, dynamic>>(),
      ..._todayLeaves.whereType<Map<String, dynamic>>(),
    ];

    final typeMap = <String, int>{};
    for (final l in allLeaves) {
      final t = _formatLeaveType((l['leaveType'] ?? l['type'] ?? 'Khác').toString());
      typeMap[t] = (typeMap[t] ?? 0) + 1;
    }

    final leaveTotal = allLeaves.length;
    final approved = allLeaves.where((l) {
      final s = (l['status'] ?? l['approvalStatus'] ?? '').toString().toLowerCase();
      return s.contains('approved') || s.contains('duyệt');
    }).length;
    final pending = _pendingLeaves.length;
    final annualUsed = _toInt(_monthlyReport['annualLeaveUsed'] ?? _monthlyReport['leaveUsed'] ?? 0);
    final leaveTypes = (typeMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(5).toList();

    return _DashCard(
      icon: Icons.event_note_outlined,
      title: 'Phân tích nghỉ phép',
      color: const Color(0xFFF59E0B),
      badge: '$leaveTotal đơn',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _leaveStatBox('Đã duyệt', '$approved', const Color(0xFF22C55E)),
          const SizedBox(width: 8),
          _leaveStatBox('Chờ duyệt', '$pending', const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          _leaveStatBox('Ngày phép đã dùng', '$annualUsed', const Color(0xFF1E3A5F)),
        ]),
        if (leaveTypes.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Phân loại nghỉ phép', style: TextStyle(fontSize: 11, color: Color(0xFF71717A), fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...leaveTypes.map((e) {
            final pct = leaveTotal > 0 ? e.value / leaveTotal : 0.0;
            const barColor = Color(0xFFF59E0B);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(e.key, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: pct, minHeight: 6, backgroundColor: const Color(0xFFE4E4E7), valueColor: const AlwaysStoppedAnimation(barColor)),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(width: 22, child: Text('${e.value}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B)), textAlign: TextAlign.right)),
              ]),
            );
          }),
        ],
        if (leaveTotal == 0) _emptyState('Không có dữ liệu nghỉ phép'),
      ]),
    );
  }

  Widget _leaveStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF71717A)), textAlign: TextAlign.center, maxLines: 2),
        ]),
      ),
    );
  }

  // ===================== CARD: PRODUCTIVITY DASHBOARD =====================
  Widget _buildProductivityCard() {
    // KPI
    final avgKpi = ((_kpiDashboard['averageKpiScore'] ?? 0) as num).toDouble();
    final kpiTotal = _toInt(_kpiDashboard['totalEmployees'] ?? 0);
    final kpiApproved = _toInt(_kpiDashboard['totalApproved'] ?? 0);

    // Attendance monthly
    final monthTotal = _toInt(_monthlyReport['totalWorkDays'] ?? _monthlyReport['workdays'] ?? 0);
    final monthPresent = _toInt(_monthlyReport['totalPresent'] ?? _monthlyReport['present'] ?? 0);
    final monthLate = _toInt(_monthlyReport['totalLate'] ?? _monthlyReport['late'] ?? 0);
    final monthRate = monthTotal > 0 ? (monthPresent / monthTotal * 100) : _attendanceRate;

    // Task
    final taskTotal = _toInt(_taskStats['totalTasks'] ?? _taskStats['total'] ?? 0);
    final taskDone = _toInt(_taskStats['completedCount'] ?? _taskStats['completed'] ?? 0);
    final taskRate = taskTotal > 0 ? (taskDone / taskTotal * 100) : 0.0;

    // OT
    final otHours = ((_overtimeStats['totalOvertimeHours'] ?? _overtimeStats['hours'] ?? 0) as num).toDouble();

    final kpiColor = avgKpi >= 80 ? const Color(0xFF22C55E) : avgKpi >= 60 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    final attColor = monthRate >= 85 ? const Color(0xFF22C55E) : monthRate >= 70 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    final taskColor = taskRate >= 80 ? const Color(0xFF22C55E) : taskRate >= 50 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);

    return _DashCard(
      icon: Icons.bar_chart_rounded,
      title: 'Năng suất & Hiệu suất',
      color: const Color(0xFF2D5F8B),
      child: Column(children: [
        // KPI gauge row
        _productivityRow('KPI trung bình', '${avgKpi.toStringAsFixed(1)}/100', avgKpi / 100, kpiColor,
            sub: '$kpiApproved/$kpiTotal NV được đánh giá'),
        const SizedBox(height: 10),
        // Attendance rate
        _productivityRow('Chấm công tháng', '${monthRate.toStringAsFixed(1)}%', monthRate / 100, attColor,
            sub: monthLate > 0 ? '$monthLate lần đi trễ trong tháng' : ''),
        const SizedBox(height: 10),
        // Task completion
        _productivityRow('Hoàn thành công việc', '${taskRate.toStringAsFixed(0)}%', taskRate / 100, taskColor,
            sub: '$taskDone/$taskTotal việc'),
        const SizedBox(height: 10),
        // OT hours summary
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Icon(Icons.av_timer, size: 20, color: const Color(0xFF8B5CF6)),
            const SizedBox(width: 10),
            Expanded(child: Text('OT tháng này', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            Text('${otHours.toStringAsFixed(1)} giờ', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6))),
          ]),
        ),
      ]),
    );
  }

  Widget _productivityRow(String label, String value, double progress, Color color, {String sub = ''}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
      ]),
      if (sub.isNotEmpty)
        Text(sub, style: const TextStyle(fontSize: 10, color: Color(0xFF71717A))),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0), minHeight: 7,
          backgroundColor: const Color(0xFFE4E4E7),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }

  // ===================== EMPLOYEE DASHBOARD =====================
  Widget _buildEmployeeDashboard() {
    final todayShift = _employeeDashboard['todayShift'] as Map<String, dynamic>?;
    final nextShift = _employeeDashboard['nextShift'] as Map<String, dynamic>?;
    final attendance = _employeeDashboard['currentAttendance'] as Map<String, dynamic>?;
    final stats = _employeeDashboard['attendanceStats'] as Map<String, dynamic>?;
    final empName = _employees.isNotEmpty
        ? (_employees[0] is Map ? (_employees[0] as Map)['fullName'] : null) ?? ''
        : '';

    return RefreshIndicator(
      onRefresh: _loadEmployeeData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(MediaQuery.of(context).size.width < 768 ? 12 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _now.hour < 12 ? Icons.wb_sunny_outlined : _now.hour < 18 ? Icons.wb_cloudy_outlined : Icons.nightlight_outlined,
                    color: Colors.amber, size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          empName.isNotEmpty ? '${_now.hour < 12 ? _l10n.goodMorning : _now.hour < 18 ? _l10n.goodAfternoon : _l10n.goodEvening}, $empName' : _l10n.loadingOverview,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_weekday(_now.weekday)}, ${_now.day}/${_now.month}/${_now.year}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Current Attendance Status
            _buildEmployeeAttendanceCard(attendance, todayShift),
            const SizedBox(height: 16),

            // Attendance Stats
            if (stats != null) ...[
              _buildEmployeeStatsCard(stats),
              const SizedBox(height: 16),
            ],

            // Today/Next Shift
            _buildEmployeeShiftCard(todayShift, nextShift),
            const SizedBox(height: 16),

            // Recent Leaves
            _buildEmployeeLeavesCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeAttendanceCard(Map<String, dynamic>? attendance, Map<String, dynamic>? todayShift) {
    final status = attendance?['status']?.toString() ?? 'no-shift';
    final checkIn = attendance?['checkInTime'];
    final checkOut = attendance?['checkOutTime'];
    final isLate = attendance?['isLate'] == true;
    final lateMin = attendance?['lateMinutes'];

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'checked-in':
        statusText = 'Đã chấm công vào';
        statusColor = const Color(0xFF22C55E);
        statusIcon = Icons.login_rounded;
        break;
      case 'checked-out':
        statusText = 'Đã chấm công ra';
        statusColor = const Color(0xFF1E3A5F);
        statusIcon = Icons.logout_rounded;
        break;
      case 'not-started':
        statusText = 'Chưa chấm công';
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.access_time_filled;
        break;
      default:
        statusText = 'Không có ca hôm nay';
        statusColor = const Color(0xFF71717A);
        statusIcon = Icons.event_busy;
    }

    return _DashCard(
      icon: Icons.fingerprint_rounded,
      title: 'Chấm công hôm nay',
      color: const Color(0xFF1E3A5F),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statusText, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: statusColor)),
                      if (isLate && lateMin != null)
                        Text('Trễ $lateMin phút', style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTimeBox('Giờ vào', checkIn != null ? _fmtTime(checkIn) : '--:--', const Color(0xFF22C55E)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimeBox('Giờ ra', checkOut != null ? _fmtTime(checkOut) : '--:--', const Color(0xFF1E3A5F)),
              ),
            ],
          ),
          if (todayShift != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTimeBox('Ca bắt đầu', _fmtTime(todayShift['startTime']), const Color(0xFF71717A)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTimeBox('Ca kết thúc', _fmtTime(todayShift['endTime']), const Color(0xFF71717A)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeBox(String label, String time, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
          const SizedBox(height: 4),
          Text(time, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildEmployeeStatsCard(Map<String, dynamic> stats) {
    final totalDays = stats['totalWorkDays'] ?? 0;
    final present = stats['presentDays'] ?? 0;
    final absent = stats['absentDays'] ?? 0;
    final lateCnt = stats['lateCheckIns'] ?? 0;
    final rate = (stats['attendanceRate'] ?? 0).toDouble();
    final avgHours = stats['averageWorkHours'] ?? '0.0';

    return _DashCard(
      icon: Icons.bar_chart_rounded,
      title: 'Thống kê chấm công',
      color: const Color(0xFF2D5F8B),
      badge: '${rate.toStringAsFixed(1)}%',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _statItem('Tổng ngày', '$totalDays', Icons.calendar_today, const Color(0xFF1E3A5F))),
              Expanded(child: _statItem('Có mặt', '$present', Icons.check_circle_rounded, const Color(0xFF22C55E))),
              Expanded(child: _statItem('Vắng', '$absent', Icons.cancel_rounded, const Color(0xFFEF4444))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statItem('Đi trễ', '$lateCnt', Icons.access_time_filled, const Color(0xFFF59E0B))),
              Expanded(child: _statItem('TB giờ/ngày', avgHours, Icons.schedule_rounded, const Color(0xFF2D5F8B))),
              const Expanded(child: SizedBox()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
        ],
      ),
    );
  }

  Widget _buildEmployeeShiftCard(Map<String, dynamic>? todayShift, Map<String, dynamic>? nextShift) {
    return _DashCard(
      icon: Icons.schedule_rounded,
      title: 'Ca làm việc',
      color: const Color(0xFF0F2340),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (todayShift != null) ...[
            _shiftRow('Hôm nay', todayShift, const Color(0xFF22C55E)),
          ] else
            _emptyRow('Không có ca hôm nay'),
          if (nextShift != null) ...[
            const Divider(height: 16),
            _shiftRow('Ca tiếp theo', nextShift, const Color(0xFF2D5F8B)),
          ],
        ],
      ),
    );
  }

  Widget _shiftRow(String label, Map<String, dynamic> shift, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.work_outline, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              Text(
                '${_fmtTime(shift['startTime'])} - ${_fmtTime(shift['endTime'])}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF18181B)),
              ),
              if (shift['description'] != null)
                Text(shift['description'].toString(), style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeLeavesCard() {
    return _DashCard(
      icon: Icons.event_note_rounded,
      title: 'Đơn nghỉ phép gần đây',
      color: const Color(0xFF7C3AED),
      badge: '${_todayLeaves.length}',
      child: _todayLeaves.isEmpty
          ? _emptyState('Chưa có đơn nghỉ phép')
          : Column(
              children: _todayLeaves.take(5).map((leave) {
                final l = leave as Map<String, dynamic>;
                final type = _formatLeaveType(l['leaveType']?.toString() ?? '');
                final status = l['status']?.toString() ?? '';
                final from = _fmtDate(l['fromDate']);
                final to = _fmtDate(l['toDate']);
                Color stColor;
                switch (status.toLowerCase()) {
                  case 'approved':
                    stColor = const Color(0xFF22C55E);
                    break;
                  case 'rejected':
                    stColor = const Color(0xFFEF4444);
                    break;
                  default:
                    stColor = const Color(0xFFF59E0B);
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: stColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: stColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4, height: 36,
                        decoration: BoxDecoration(color: stColor, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('$from - $to', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: stColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Text(status, style: TextStyle(fontSize: 11, color: stColor, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ===================== REUSABLE CARD WIDGET =====================
class _DashCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String? badge;
  final Widget child;

  const _DashCard({required this.icon, required this.title, required this.color, required this.child, this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF18181B)))),
          if (badge != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(badge!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))),
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

class _HeroKpi {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String kind; // total|present|late|absent|inout|devices
  _HeroKpi(this.label, this.value, this.icon, this.color, this.kind);
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _QuickAction(this.icon, this.label, this.color, this.onTap);
}

class _InsightChipData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String kind;
  const _InsightChipData(this.icon, this.label, this.value, this.color, this.kind);
}
