import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../widgets/reports/hrm_report_widgets.dart';

const _theme = Color(0xFF0284C7);

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
  String? _selectedBranchId;
  int _viewTab = 0;
  int _page = 1;
  static const _pageSize = 50;

  bool _loading = false;
  String? _loadError;
  List<Map<String, dynamic>> _leaves = [];
  int _totalCount = 0;
  int? _summaryTotalRequests;
  List<Map<String, dynamic>> _byEmployee = [];
  String? _annualBalanceText;

  bool get _teamView {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  bool get _canLeaveSummary {
    return Provider.of<PermissionProvider>(context, listen: false)
        .canView('LeaveReport');
  }

  List<Map<String, dynamic>> get _filtered {
    Set<String>? branchIds;
    if (_teamView && _selectedBranchId != null) {
      branchIds = _branchFilter.userIdsForBranch(_selectedBranchId);
      if (branchIds.isEmpty) return [];
    }
    return _leaves.where((l) {
      final empKey = l['employeeUserId']?.toString() ??
          l['employeeId']?.toString() ??
          '';
      if (branchIds != null && !branchIds.contains(empKey)) return false;
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
        _branchFilter.loadBranches(_api).then((_) {
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
      final res = await _api.getAllLeaves(
        page: _page,
        pageSize: _pageSize,
        fromDate: _fmtDateApi.format(_from),
        toDate: _fmtDateApi.format(_to),
        status: _leaveStatusParam(),
      );
      final parsed = parsePagedReportListResponse(res);
      if (mounted) {
        setState(() {
          _leaves = parsed.items;
          _totalCount = parsed.totalCount;
          _loadError = parsed.error;
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
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        final raw = data['items'] ?? data['Items'];
        if (mounted) {
          setState(() {
            final total =
                data['totalLeaveRequests'] ?? data['TotalLeaveRequests'];
            _summaryTotalRequests =
                total is int ? total : int.tryParse('$total');
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
        return const Color(0xFF16A34A);
      case 2:
        return const Color(0xFFDC2626);
      case 3:
        return const Color(0xFFDC2626);
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

  int _leaveDays(Map<String, dynamic> l) {
    try {
      final start = parseApiCalendarDate(l['startDate']);
      final end = parseApiCalendarDate(l['endDate']);
      if (start == null || end == null) return 1;
      return end.difference(start).inDays + 1;
    } catch (_) {
      return 1;
    }
  }

  List<ReportKpiItem> _buildKpis() {
    final f = leaveRowsForReportStats(_filtered, _statusFilter);
    final pending = f.where((l) => _normalizeStatus(l['status']) == 0).length;
    final approved = f.where((l) => _normalizeStatus(l['status']) == 1).length;
    final totalDays = f
        .where((l) => _normalizeStatus(l['status']) == 1)
        .fold(0, (s, l) => s + _leaveDays(l));

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
            color: const Color(0xFF16A34A)),
        ReportKpiItem(
            label: 'Tổng ngày nghỉ',
            value: '$totalDays ngày',
            icon: Icons.event_busy,
            color: _theme),
      ];
    }
    return [
      ReportKpiItem(
          label: 'Tổng đơn',
          value: (_statusFilter == null && _summaryTotalRequests != null)
              ? '$_summaryTotalRequests'
              : (_statusFilter != null ? '$_totalCount' : '${f.length}'),
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
          color: const Color(0xFF16A34A)),
      ReportKpiItem(
          label: 'Tổng ngày nghỉ',
          value: '$totalDays ngày',
          icon: Icons.event_busy,
          color: _theme),
    ];
  }

  Future<void> _exportExcel() async {
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
    await ClientExcelExport.export(
      context: context,
      title: _teamView ? 'Báo cáo nghỉ phép' : 'Ngày nghỉ của tôi',
      sheetName: 'Bao cao nghi phep',
      filePrefix: 'BaoCaoNghiPhep',
      headers: [
        'STT',
        if (_teamView) 'Nhân viên',
        'Loại phép',
        'Từ ngày',
        'Đến ngày',
        'Số ngày',
        'Lý do',
        'Trạng thái',
        'Người duyệt',
      ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: _teamView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('LeaveReport');

    return ReportScreenShell(
      title: _teamView ? 'Báo cáo nghỉ phép' : 'Ngày nghỉ của tôi',
      subtitle: reportPeriodSubtitle(_from, _to, team: _teamView),
      accentColor: _theme,
      canExport: canExport,
      onExport: _exportExcel,
      onRefresh: _load,
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (!_teamView && _annualBalanceText != null)
                    ReportPersonalInsightBanner(
                      message: _annualBalanceText!,
                      color: _theme,
                      icon: Icons.beach_access_outlined,
                    ),
                  ReportFilterSection(
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
                      if (v != null) await _branchFilter.ensureEmployees(_api);
                      if (mounted) setState(() => _selectedBranchId = v);
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
                              _selectedBranchId = null;
                            })
                        : null,
                  ),
                  reportLoadErrorBanner(_loadError),
                  ReportKpiGrid(items: _buildKpis()),
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
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _statusFilter,
          isExpanded: true,
          hint: const Text('Trạng thái',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
          items: const [
            DropdownMenuItem(value: null, child: Text('Tất cả')),
            DropdownMenuItem(value: 0, child: Text('Chờ duyệt')),
            DropdownMenuItem(value: 1, child: Text('Đã duyệt')),
            DropdownMenuItem(value: 2, child: Text('Từ chối')),
            DropdownMenuItem(value: 3, child: Text('Đã hủy')),
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
    if (_byEmployee.isEmpty) {
      return const ReportEmptyState(
        title: 'Chưa có dữ liệu tổng hợp',
        subtitle: 'Thử đổi khoảng thời gian',
      );
    }
    return Column(
      children: _byEmployee.map((e) {
        final name = e['employeeName']?.toString() ??
            e['EmployeeName']?.toString() ??
            '—';
        final dept = e['departmentName']?.toString() ??
            e['DepartmentName']?.toString() ??
            '';
        final days = e['totalDays'] ?? e['TotalDays'] ?? 0;
        final requests = e['totalRequests'] ?? e['TotalRequests'] ?? 0;
        return ReportEmployeeSummaryCard(
          name: name,
          meta: dept.isNotEmpty ? dept : null,
          primaryValue: '$days ngày nghỉ',
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
