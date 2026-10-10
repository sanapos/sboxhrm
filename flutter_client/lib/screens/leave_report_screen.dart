import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/reports/hrm_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
import '../widgets/sbox/sbox_report.dart';
import '../widgets/sbox/sbox_charts.dart';
import '../utils/branch_filter_helper.dart';
const _theme = HrmPageChrome.primaryNavy;

class LeaveReportScreen extends StatefulWidget {
  const LeaveReportScreen({super.key});
  @override
  State<LeaveReportScreen> createState() => _LeaveReportScreenState();
}

class _LeaveReportScreenState extends State<LeaveReportScreen> {
  final ApiService _api = ApiService();
  final _fmtDateApi = DateFormat('yyyy-MM-dd');
  final _branchFilter = ReportBranchFilter();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  int? _statusFilter;
  String _empSearch = '';
  String? _selectedBranchId = BranchFilterHelper.viewBranchId;
  String? _selectedDepartmentId;
  int _viewTab = 0;
  int _page = 1;
  static const _pageSize = 50;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;
  List<Map<String, dynamic>> _leaves = [];
  int _totalCount = 0;
  List<Map<String, dynamic>> _byEmployee = [];
  String? _annualBalanceText;
  final _pngKey = GlobalKey();

  bool get _teamView {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  bool get _canLeaveSummary {
    return Provider.of<PermissionProvider>(context, listen: false)
        .canView('LeaveReport');
  }

  /// Toàn bộ đơn trong kỳ (không phân trang) — để dashboard tính đúng.
  List<Map<String, dynamic>> _statsLeaves = [];

  List<Map<String, dynamic>> get _filtered => _scoped(_leaves);

  List<Map<String, dynamic>> get _statsFiltered => _scoped(_statsLeaves);

  List<Map<String, dynamic>> _scoped(List<Map<String, dynamic>> source) {
    return source.where((l) {
      if (_teamView &&
          !_branchFilter.mapRowInScope(
            l,
            branchId: _selectedBranchId,
            departmentId: _selectedDepartmentId,
          )) {
        return false;
      }
      if (_teamView &&
          _empSearch.isNotEmpty &&
          !(l['employeeName']?.toString() ?? '')
              .toLowerCase()
              .contains(_empSearch.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  List<String> get _empSuggestions => _leaves
      .map((l) => l['employeeName']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_teamView) {
        _branchFilter.loadOrgFilters(_api).then((_) async {
          await _branchFilter.ensureEmployees(_api,
              branchId: _selectedBranchId);
          if (mounted) setState(() {});
        });
      } else {
        _loadAnnualBalance();
      }
    });
  }

  Future<void> _loadAnnualBalance() async {
    try {
      final me = await _api.getMyEmployee();
      if (me['isSuccess'] != true || me['data'] is! Map) return;
      final empId = (me['data'] as Map)['id']?.toString();
      if (empId == null) return;
      final bal = await _api.getAnnualLeaveBalance(empId);
      if (bal['isSuccess'] == true && bal['data'] is Map && mounted) {
        final d = bal['data'] as Map;
        final remaining = d['remainingDays'] ?? d['RemainingDays'];
        if (remaining != null) {
          setState(() {
            _annualBalanceText = 'Phép năm còn lại: $remaining ngày';
          });
        }
      }
    } catch (_) {}
  }

  String? _leaveStatusParam() {
    if (_statusFilter == null) return null;
    switch (_statusFilter) {
      case 0:
        return 'Pending';
      case 1:
        return 'Approved';
      case 2:
        return 'Rejected';
      case 3:
        return 'Cancelled';
      default:
        return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      Future<Map<String, dynamic>> fetch(int page, int size) => _api.getAllLeaves(
            page: page,
            pageSize: size,
            fromDate: _fmtDateApi.format(_from),
            toDate: _fmtDateApi.format(_to),
            status: _leaveStatusParam(),
          );
      // Dashboard cần cả kỳ: tải 1 lần khi đổi bộ lọc (trang 1).
      final statsFuture = _page == 1 ? fetch(1, 2000) : null;
      final parsed = parsePagedReportListResponse(await fetch(_page, _pageSize));
      final stats = statsFuture == null ? null : parsePagedReportListResponse(await statsFuture);
      if (mounted) {
        setState(() {
          _leaves = parsed.items;
          _totalCount = parsed.totalCount;
          _loadError = parsed.error;
          if (stats != null) _statsLeaves = stats.error == null ? stats.items : parsed.items;
        });
      }
      if (_teamView && _canLeaveSummary) {
        await _loadSummary();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = 'Không tải được báo cáo nghỉ phép: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSummary() async {
    try {
      final res = await _api.getLeaveReport(
        startDate: _from,
        endDate: _to,
        branchId: _teamView ? _selectedBranchId : null,
        departmentId: _teamView ? _selectedDepartmentId : null,
        includeChildBranches: true,
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        final raw = data['items'] ?? data['Items'];
        if (mounted) {
          setState(() {
            if (raw is List) {
              _byEmployee = raw
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }
          });
        }
      }
    } catch (_) {}
  }

  int _normalizeStatus(dynamic s) {
    if (s == null) return 0;
    if (s is int) return s;
    final str = s.toString().toLowerCase();
    if (str == '0' || str == 'pending') return 0;
    if (str == '1' || str == 'approved') return 1;
    if (str == '2' || str == 'rejected') return 2;
    if (str == '3' || str == 'cancelled') return 3;
    return int.tryParse(str) ?? 0;
  }

  String _statusLabel(int s) {
    switch (s) {
      case 0:
        return 'Chờ duyệt';
      case 1:
        return 'Đã duyệt';
      case 2:
        return 'Từ chối';
      case 3:
        return 'Đã hủy';
      default:
        return 'Không rõ';
    }
  }

  Color _statusColor(int s) {
    switch (s) {
      case 0:
        return Colors.orange;
      case 1:
        return SboxColors.success;
      case 2:
        return SboxColors.danger;
      case 3:
        return SboxColors.danger;
      default:
        return Colors.blueGrey;
    }
  }

  String _leaveTypeName(dynamic t) {
    switch (t?.toString().toLowerCase()) {
      case 'annualleave':
        return 'Phép năm';
      case 'holiday':
        return 'Nghỉ lễ';
      case 'personalpaid':
        return 'Phép có lương';
      case 'personalunpaid':
        return 'Phép không lương';
      case 'sickleave':
        return 'Nghỉ ốm';
      case 'maternityleave':
        return 'Thai sản';
      case 'compensatoryleave':
        return 'Nghỉ bù';
      default:
        return t?.toString() ?? '—';
    }
  }

  /// Số ngày nghỉ của đơn — nghỉ nửa ca tính 0,5 ngày.
  /// [inPeriod]: chỉ đếm phần nằm trong kỳ báo cáo (đơn 28/9–3/10 trong báo cáo tháng 10 = 3 ngày).
  double _leaveDays(Map<String, dynamic> l, {bool inPeriod = false}) {
    try {
      var start = parseApiCalendarDate(l['startDate']);
      var end = parseApiCalendarDate(l['endDate']);
      if (inPeriod && start != null && end != null) {
        final from = DateTime(_from.year, _from.month, _from.day);
        final to = DateTime(_to.year, _to.month, _to.day);
        start = DateTime(start.year, start.month, start.day);
        end = DateTime(end.year, end.month, end.day);
        if (start.isBefore(from)) start = from;
        if (end.isAfter(to)) end = to;
        if (end.isBefore(start)) return 0;
      }
      final days = (start == null || end == null) ? 1 : end.difference(start).inDays + 1;
      final half = l['isHalfShift'] == true || l['IsHalfShift'] == true;
      return half ? days * 0.5 : days.toDouble();
    } catch (_) {
      return 1;
    }
  }

  String _daysText(num v) => '${SboxFmt.decimal(v)} ngày';

  /// Biểu đồ dashboard: số người nghỉ theo ngày, cơ cấu loại nghỉ, trạng thái đơn, nghỉ nhiều nhất.
  List<Widget> _buildCharts() {
    final all = _statsFiltered;
    final f = leaveRowsForReportStats(all, _statusFilter)
        .where((l) => _normalizeStatus(l['status']) == 1)
        .toList();
    if (all.isEmpty) return const [];
    final byType = <String, double>{};
    final byEmp = <String, double>{};
    final cnt = <String, int>{};
    // Số người nghỉ mỗi ngày trong kỳ (đơn đã duyệt).
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    final perDay = <DateTime, double>{};
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      perDay[d] = 0;
    }
    for (final l in f) {
      final d = _leaveDays(l, inPeriod: true);
      final t = _leaveTypeName(l['leaveType'] ?? l['type']);
      byType[t] = (byType[t] ?? 0) + d;
      final n = l['employeeName']?.toString() ?? '—';
      byEmp[n] = (byEmp[n] ?? 0) + d;
      cnt[n] = (cnt[n] ?? 0) + 1;
      final s = parseApiCalendarDate(l['startDate']);
      final e = parseApiCalendarDate(l['endDate']) ?? s;
      if (s != null && e != null) {
        final w = (l['isHalfShift'] == true) ? 0.5 : 1.0;
        for (var d0 = DateTime(s.year, s.month, s.day);
            !d0.isAfter(DateTime(e.year, e.month, e.day));
            d0 = d0.add(const Duration(days: 1))) {
          if (perDay.containsKey(d0)) perDay[d0] = perDay[d0]! + w;
        }
      }
    }
    final byStatus = <int, double>{};
    for (final l in all) {
      final s = _normalizeStatus(l['status']);
      byStatus[s] = (byStatus[s] ?? 0) + 1;
    }
    final total = byType.values.fold<double>(0, (a, b) => a + b);
    final days = perDay.keys.toList()..sort();
    return [
      if (_teamView && days.length > 1 && days.length <= 62)
        SboxChartCard(
          title: 'Số người nghỉ theo ngày',
          subtitle: 'Đơn đã duyệt',
          wide: true,
          child: SboxBarChart(
            valueFormat: (v) => '${SboxFmt.decimal(v)} người',
            labels: [for (final d in days) sboxDayLabel(d)],
            series: [SboxSeries(name: 'Người nghỉ', values: [for (final d in days) perDay[d]!], color: SboxColors.violet)],
          ),
        ),
      if (byType.isNotEmpty)
        SboxChartCard(
          title: 'Ngày nghỉ theo loại',
          subtitle: 'Đơn đã duyệt',
          child: SboxDonutChart(
            valueFormat: (v) => _daysText(v ?? 0),
            centerValue: SboxFmt.decimal(total),
            centerLabel: 'ngày nghỉ',
            slices: [for (final e in byType.entries) SboxSlice(e.key, e.value)],
          ),
        ),
      SboxChartCard(
        title: 'Trạng thái đơn',
        subtitle: 'Số đơn',
        child: SboxDonutChart(
          valueFormat: (v) => '${SboxFmt.number(v)} đơn',
          centerValue: '${all.length}',
          centerLabel: 'đơn',
          slices: [
            for (final e in byStatus.entries) SboxSlice(_statusLabel(e.key), e.value, color: _statusColor(e.key)),
          ],
        ),
      ),
      if (_teamView && byEmp.isNotEmpty)
        SboxChartCard(
          title: 'Nghỉ nhiều nhất',
          child: SboxRankList(
            color: SboxColors.violet,
            valueFormat: (v) => _daysText(v ?? 0),
            items: [for (final e in byEmp.entries) SboxSlice(e.key, e.value, caption: '${cnt[e.key]} đơn')],
          ),
        ),
    ];
  }

  List<ReportKpiItem> _buildKpis() {
    final f = leaveRowsForReportStats(_statsFiltered, _statusFilter);
    final pending = f.where((l) => _normalizeStatus(l['status']) == 0).length;
    final approvedRows = f.where((l) => _normalizeStatus(l['status']) == 1).toList();
    final approved = approvedRows.length;
    final totalDays = approvedRows.fold<double>(0, (s, l) => s + _leaveDays(l, inPeriod: true));
    final decided = _statsFiltered.where((l) {
      final s = _normalizeStatus(l['status']);
      return s == 1 || s == 2;
    }).length;
    final approvalRate = decided == 0 ? null : (approved / decided * 100).round();
    final empCount = approvedRows.map((l) => l['employeeName']?.toString() ?? '').toSet().length;

    if (!_teamView) {
      return [
        ReportKpiItem(
            label: 'Đơn nghỉ',
            value: f.length.toString(),
            icon: Icons.description_outlined,
            color: Colors.blueGrey),
        ReportKpiItem(
            label: 'Chờ duyệt',
            value: pending.toString(),
            icon: Icons.hourglass_empty,
            color: Colors.orange),
        ReportKpiItem(
            label: 'Đã duyệt',
            value: approved.toString(),
            icon: Icons.check_circle_outline,
            color: SboxColors.success),
        ReportKpiItem(
            label: 'Tổng ngày nghỉ',
            value: _daysText(totalDays),
            note: _annualBalanceText,
            icon: Icons.event_busy,
            color: _theme),
      ];
    }
    return [
      ReportKpiItem(
          label: 'Tổng đơn',
          value: '${f.length}',
          note: pending > 0 ? '$pending đơn chờ duyệt' : 'Đã xử lý hết',
          icon: Icons.description_outlined,
          color: Colors.blueGrey),
      ReportKpiItem(
          label: 'Đã duyệt',
          value: approved.toString(),
          note: approvalRate == null ? null : 'Tỷ lệ duyệt $approvalRate%',
          icon: Icons.check_circle_outline,
          color: SboxColors.success),
      ReportKpiItem(
          label: 'Tổng ngày nghỉ',
          value: _daysText(totalDays),
          note: empCount == 0 ? null : 'TB ${SboxFmt.decimal(totalDays / empCount)} ngày/NV',
          icon: Icons.event_busy,
          color: SboxColors.violet),
      ReportKpiItem(
          label: 'Nhân viên nghỉ',
          value: '$empCount',
          icon: Icons.people_outline,
          color: _theme),
    ];
  }

  Future<void> _exportExcel({bool png = false}) async {
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final l = data[i];
      final startDate = parseApiCalendarDate(l['startDate']);
      final endDate = parseApiCalendarDate(l['endDate']);
      rows.add([
        i + 1,
        if (_teamView) l['employeeName']?.toString() ?? '',
        _leaveTypeName(l['type'] ?? l['leaveType']),
        startDate != null ? reportDateFmt.format(startDate) : '',
        endDate != null ? reportDateFmt.format(endDate) : '',
        _leaveDays(l),
        l['reason']?.toString() ?? '',
        _statusLabel(_normalizeStatus(l['status'])),
        l['approvedByName']?.toString() ?? '',
      ]);
    }
    final title = _teamView ? 'Báo cáo nghỉ phép' : 'Ngày nghỉ của tôi';
    const filePrefix = 'BaoCaoNghiPhep';
    final headers = [
      'STT',
      if (_teamView) 'Nhân viên',
      'Loại phép',
      'Từ ngày',
      'Đến ngày',
      'Số ngày',
      'Lý do',
      'Trạng thái',
      'Người duyệt',
    ];
    final periodLabel = reportPeriodSubtitle(_from, _to, team: _teamView);
    if (png) {
      await ClientPngExport.table(
        context: context,
        title: title,
        filePrefix: filePrefix,
        headers: headers,
        rows: rows,
        periodLabel: periodLabel,
      );
      return;
    }
    await ClientExcelExport.export(
      context: context,
      title: title,
      sheetName: 'Bao cao nghi phep',
      filePrefix: filePrefix,
      headers: headers,
      rows: rows,
      periodLabel: periodLabel,
    );
  }

  Future<void> _exportPng() => _exportExcel(png: true);

  @override
  Widget build(BuildContext context) {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('LeaveReport');

    return RegisterPageTopActions(
      actions: [
        if (canExport)
          HrmTopBarAction(
            icon: Icons.image_outlined,
            label: 'Xuất PNG',
            onPressed: _filtered.isEmpty ? null : _exportPng,
            pinOnMobile: false,
          ),
        if (canExport)
          HrmTopBarAction(
            icon: Icons.file_download_outlined,
            label: 'Xuất Excel',
            onPressed: _filtered.isEmpty ? null : _exportExcel,
          ),
      ],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  RepaintBoundary(
                    key: _pngKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                  if (!_teamView && _annualBalanceText != null)
                    ReportPersonalInsightBanner(
                      message: _annualBalanceText!,
                      color: _theme,
                      icon: Icons.beach_access_outlined,
                    ),
                  ReportCollapsibleChrome(
                    expanded: _showOverviewPanel,
                    onToggle: () => setState(
                        () => _showOverviewPanel = !_showOverviewPanel),
                    filter: ReportFilterSection(
                      embedded: true,
                      from: _from,
                      to: _to,
                      datePreset: _datePreset,
                      onDateChanged: (f, t, p) => setState(() {
                        _from = f;
                        _to = t;
                        _datePreset = p;
                      }),
                      statusFilter: _statusDrop(),
                      statusSummary: _filterStatusSummary(),
                      showTeamFilters: _teamView,
                      branchFilter: _teamView ? _branchFilter : null,
                      selectedBranchId: _selectedBranchId,
                      onBranchChanged: (v) async {
                        await _branchFilter.ensureEmployees(_api, branchId: v);
                        if (mounted) setState(() => _selectedBranchId = v);
                      },
                      selectedDepartmentId: _selectedDepartmentId,
                      onDepartmentChanged: (v) {
                        if (mounted) setState(() => _selectedDepartmentId = v);
                      },
                      empSearch: _empSearch,
                      onEmpSearchChanged: (v) => setState(() => _empSearch = v),
                      empSuggestions: _empSuggestions,
                      onApply: () {
                        setState(() => _page = 1);
                        _load();
                      },
                      onClearFilters: _teamView
                          ? () => setState(() {
                                _empSearch = '';
                                _selectedBranchId = BranchFilterHelper.viewBranchId;
                                _selectedDepartmentId = null;
                              })
                          : null,
                    ),
                  ),
                  reportLoadErrorBanner(_loadError),
                  ReportDashboard(
                    storageKey: 'leave',
                    subtitle: reportPeriodSubtitle(_from, _to, team: _teamView),
                    kpis: _buildKpis(),
                    charts: _buildCharts(),
                  ),
                  if (_teamView && _canLeaveSummary)
                    ReportViewModeTabs(
                      index: _viewTab,
                      onChanged: (i) {
                        setState(() => _viewTab = i);
                        if (i == 1) _loadSummary();
                      },
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_teamView && _viewTab == 1 && _canLeaveSummary)
                    _buildByEmployee()
                  else
                    _buildBody(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_teamView && _viewTab == 0)
            ReportPaginationBar(
              page: _page,
              pageSize: _pageSize,
              totalCount: _totalCount,
              onPageChanged: (p) {
                setState(() => _page = p);
                _load();
              },
            ),
        ],
      ),
      ),
    );
  }

  String? _filterStatusSummary() {
    if (_statusFilter == null) return null;
    return _statusLabel(_statusFilter!);
  }

  Widget _statusDrop() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border.all(color: SboxColors.slate300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _statusFilter,
          isExpanded: true,
          hint: Text(tr('Trạng thái'),
              style: TextStyle(fontSize: 12, color: SboxColors.slate500)),
          style: const TextStyle(fontSize: 12, color: SboxColors.slate900),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('Tất cả'))),
            DropdownMenuItem(value: 0, child: Text(tr('Chờ duyệt'))),
            DropdownMenuItem(value: 1, child: Text(tr('Đã duyệt'))),
            DropdownMenuItem(value: 2, child: Text(tr('Từ chối'))),
            DropdownMenuItem(value: 3, child: Text(tr('Đã hủy'))),
          ],
          onChanged: (v) => setState(() => _statusFilter = v),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final rows = _filtered;
    if (rows.isEmpty) {
      return ReportEmptyState(
        title: _teamView ? 'Không có đơn nghỉ phép' : 'Bạn chưa có đơn nghỉ',
        subtitle: 'Thử đổi khoảng thời gian hoặc bộ lọc',
      );
    }
    return Column(children: rows.map(_leaveCard).toList());
  }

  Widget _leaveCard(Map<String, dynamic> l) {
    final startDate = parseApiCalendarDate(l['startDate']);
    final endDate = parseApiCalendarDate(l['endDate']);
    final days = _leaveDays(l);
    final status = _normalizeStatus(l['status']);
    final range = (startDate != null && endDate != null)
        ? '${reportDateFmt.format(startDate)} – ${reportDateFmt.format(endDate)}'
        : '—';

    return ReportTimelineCard(
      title: _teamView
          ? (l['employeeName']?.toString() ?? '—')
          : _leaveTypeName(l['type'] ?? l['leaveType']),
      trailing: '$days ngày',
      amount: _teamView ? range : null,
      subtitle: [
        if (_teamView) _leaveTypeName(l['type'] ?? l['leaveType']),
        if (!_teamView) range,
        l['reason']?.toString() ?? '',
      ].where((s) => s.isNotEmpty).join(' · '),
      accentColor: _theme,
      statusLabel: _statusLabel(status),
      statusColor: _statusColor(status),
      icon: Icons.event_busy_outlined,
    );
  }

  Widget _buildByEmployee() {
    final rows = _branchFilter.filterEmployeeRows(
      _byEmployee,
      branchId: _teamView ? _selectedBranchId : null,
      departmentId: _teamView ? _selectedDepartmentId : null,
    );
    if (rows.isEmpty) {
      return const ReportEmptyState(
        title: 'Chưa có dữ liệu tổng hợp',
        subtitle: 'Thử đổi khoảng thời gian',
      );
    }
    return Column(
      children: rows.map((e) {
        final name = e['employeeName']?.toString() ??
            e['EmployeeName']?.toString() ??
            '—';
        final dept = e['departmentName']?.toString() ??
            e['DepartmentName']?.toString() ??
            '';
        final days = reportSafeDouble(e['totalDays'] ?? e['TotalDays']);
        final requests = e['totalRequests'] ?? e['TotalRequests'] ?? 0;
        return ReportEmployeeSummaryCard(
          name: name,
          meta: dept.isNotEmpty ? dept : null,
          primaryValue: '${_daysText(days)} nghỉ',
          secondaryValue: '$requests đơn',
          accentColor: _theme,
          onTap: () => setState(() {
            _viewTab = 0;
            _empSearch = name;
          }),
        );
      }).toList(),
    );
  }
}
