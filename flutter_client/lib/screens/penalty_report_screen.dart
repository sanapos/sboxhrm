import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/vietnamese_font.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/reports/hrm_report_widgets.dart';

const _theme = HrmPageChrome.primaryNavy;
const _accentBlue = Color(0xFF2563EB);
const _accentLight = Color(0xFF3B82F6);
const _accentDark = Color(0xFF1E40AF);

class PenaltyReportScreen extends StatefulWidget {
  const PenaltyReportScreen({super.key});
  @override
  State<PenaltyReportScreen> createState() => _PenaltyReportScreenState();
}

class _PenaltyReportScreenState extends State<PenaltyReportScreen> {
  final ApiService _api = ApiService();
  final _branchFilter = ReportBranchFilter();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  String? _statusFilter;
  String _empSearch = '';
  String? _selectedBranchId;
  int _viewTab = 0;
  int _page = 1;
  static const _pageSize = 50;

  bool _loading = false;
  String? _loadError;
  List<Map<String, dynamic>> _tickets = [];
  int _totalCount = 0;
  int? _summaryTotalTickets;
  List<Map<String, dynamic>> _byEmployee = [];

  bool get _teamView {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  List<Map<String, dynamic>> get _filtered {
    var result = _tickets;
    if (_teamView && _selectedBranchId != null) {
      final ids = _branchFilter.userIdsForBranch(_selectedBranchId);
      if (ids.isEmpty) return [];
      result = result
          .where((t) => ids.contains(t['employeeUserId']?.toString()))
          .toList();
    }
    if (_teamView && _empSearch.isNotEmpty) {
      result = result
          .where((t) => (t['employeeName']?.toString() ?? '')
              .toLowerCase()
              .contains(_empSearch.toLowerCase()))
          .toList();
    }
    return result;
  }

  List<String> get _empSuggestions => _tickets
      .map((t) => t['employeeName']?.toString() ?? '')
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
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final result = await loadPenaltyReportTickets(
        _api,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        pageSize: _pageSize,
        page: _page,
      );
      if (mounted) {
        setState(() {
          _tickets = result.items;
          _totalCount = result.totalCount;
          _loadError = result.error;
        });
      }
      if (_teamView) await _loadSummary();
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = 'Không tải được báo cáo phạt: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSummary() async {
    try {
      final res = await _api.getPenaltySummaryReport(from: _from, to: _to);
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        final raw = data['byEmployee'] ?? data['ByEmployee'];
        if (mounted) {
          setState(() {
            final total = data['totalTickets'] ?? data['TotalTickets'];
            _summaryTotalTickets =
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

  List<ReportKpiItem> _buildKpis() {
    final f = penaltyRowsForReportStats(_filtered, _statusFilter);
    final total = f.length;
    final approved = f.where((t) => isApprovedPenaltyStatus(t['status'])).length;
    final totalAmt = f.fold(0.0, (s, t) => s + reportSafeDouble(t['amount']));
    final approvedAmt = f
        .where((t) => isApprovedPenaltyStatus(t['status']))
        .fold(0.0, (s, t) => s + reportSafeDouble(t['amount']));

    if (!_teamView) {
      return [
        ReportKpiItem(
            label: 'Phiếu phạt',
            value: total.toString(),
            icon: Icons.receipt_long,
            color: _theme),
        ReportKpiItem(
            label: 'Đã duyệt',
            value: approved.toString(),
            icon: Icons.check_circle_outline,
            color: _accentBlue),
        ReportKpiItem(
            label: 'Tổng tiền',
            value: '${reportMoneyFmt.format(totalAmt)}đ',
            icon: Icons.money_off_outlined,
            color: _accentLight),
        ReportKpiItem(
            label: 'Tiền đã duyệt',
            value: '${reportMoneyFmt.format(approvedAmt)}đ',
            icon: Icons.payments_outlined,
            color: _accentDark),
      ];
    }
    final empCount = f
        .map((t) => t['employeeName']?.toString() ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .length;
    return [
      ReportKpiItem(
          label: 'Tổng phiếu',
          value: (_statusFilter == null && _summaryTotalTickets != null)
              ? '$_summaryTotalTickets'
              : (_statusFilter != null ? '$_totalCount' : '$total'),
          icon: Icons.receipt_long,
          color: _theme),
      ReportKpiItem(
          label: 'NV vi phạm',
          value: empCount.toString(),
          icon: Icons.people_outline,
          color: _accentBlue),
      ReportKpiItem(
          label: 'Tổng tiền phạt',
          value: '${reportMoneyFmt.format(totalAmt)}đ',
          icon: Icons.money_off_outlined,
          color: _accentLight),
      ReportKpiItem(
          label: 'Tiền đã duyệt',
          value: '${reportMoneyFmt.format(approvedAmt)}đ',
          icon: Icons.payments_outlined,
          color: _accentDark),
    ];
  }

  Future<void> _exportExcel() async {
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final t = data[i];
      final date =
          parseApiCalendarDate(t['date']);
      rows.add([
        i + 1,
        if (_teamView) t['employeeName']?.toString() ?? '',
        if (_teamView) t['departmentName']?.toString() ?? '',
        t['penaltyTypeLabel']?.toString() ??
            penaltyTypeDisplayLabel(t['type']),
        date != null ? reportDateFmt.format(date) : '',
        reportSafeDouble(t['amount']),
        t['statusLabel']?.toString() ?? penaltyStatusDisplayLabel(t['status']),
        t['note']?.toString() ?? t['reason']?.toString() ?? '',
      ]);
    }
    await ClientExcelExport.export(
      context: context,
      title: _teamView ? 'Báo cáo phạt' : 'Phiếu phạt của tôi',
      sheetName: 'Bao cao phat',
      filePrefix: 'BaoCaoPhat',
      headers: [
        'STT',
        if (_teamView) 'Nhân viên',
        if (_teamView) 'Phòng ban',
        'Loại phạt',
        'Ngày',
        'Số tiền (đ)',
        'Trạng thái',
        'Ghi chú',
      ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: _teamView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('PenaltyReport');

    return Theme(
      data: vietnameseThemeOverlay(context),
      child: ReportScreenShell(
      title: _teamView ? 'Báo cáo phạt' : 'Phiếu phạt của tôi',
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
                  if (_teamView)
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
                  else if (_teamView && _viewTab == 1)
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
    ),
    );
  }

  String? _filterStatusSummary() {
    if (_statusFilter == null) return null;
    switch (_statusFilter) {
      case '0':
        return 'Chờ duyệt';
      case '1':
        return 'Đã duyệt';
      case '3':
        return 'Tự động duyệt';
      case '2':
        return 'Đã hủy';
      default:
        return null;
    }
  }

  Widget _statusDrop() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _statusFilter,
          isExpanded: true,
          hint: Text('Trạng thái',
              style: vietnameseTextStyle(
                  const TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
          style: vietnameseTextStyle(
              const TextStyle(fontSize: 12, color: Color(0xFF111827))),
          items: [
            DropdownMenuItem(
                value: null,
                child: Text('Tất cả', style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '0',
                child: Text('Chờ duyệt', style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '1',
                child: Text('Đã duyệt', style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '3',
                child: Text('Tự động duyệt', style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '2',
                child: Text('Đã hủy', style: vietnameseTextStyle())),
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
        title: _teamView ? 'Không có phiếu phạt' : 'Bạn chưa có phiếu phạt',
        subtitle: 'Thử đổi khoảng thời gian hoặc bộ lọc',
      );
    }

    if (!_teamView) {
      return Column(
        children: rows.map((t) => _personalCard(t)).toList(),
      );
    }

    return Column(children: rows.map((t) => _teamDetailCard(t)).toList());
  }

  Widget _personalCard(Map<String, dynamic> t) {
    final date =
        parseApiCalendarDate(t['date']);
    final amt = reportSafeDouble(t['amount']);
    return ReportTimelineCard(
      title: t['penaltyTypeLabel']?.toString() ??
          penaltyTypeDisplayLabel(t['type']),
      trailing: date != null ? reportDateFmt.format(date) : null,
      amount: '${reportMoneyFmt.format(amt)}đ',
      subtitle: t['note']?.toString() ?? t['reason']?.toString() ?? '',
      accentColor: _theme,
      statusLabel: t['statusLabel']?.toString() ??
          penaltyStatusDisplayLabel(t['status']),
      statusColor: penaltyStatusColor(t['status']),
      icon: Icons.gavel_outlined,
    );
  }

  Widget _teamDetailCard(Map<String, dynamic> t) {
    final date =
        parseApiCalendarDate(t['date']);
    final name = t['employeeName']?.toString() ?? '-';
    final dept = t['departmentName']?.toString() ?? '';
    return ReportTimelineCard(
      title: name,
      trailing: date != null ? reportDateFmt.format(date) : null,
      amount:
          '${reportMoneyFmt.format(reportSafeDouble(t['amount']))}đ | ${t['penaltyTypeLabel'] ?? penaltyTypeDisplayLabel(t['type'])}',
      subtitle: [
        if (dept.isNotEmpty) dept,
        t['note']?.toString() ?? t['reason']?.toString() ?? '',
      ].where((s) => s.isNotEmpty).join(' | '),
      accentColor: _theme,
      statusLabel: t['statusLabel']?.toString() ??
          penaltyStatusDisplayLabel(t['status']),
      statusColor: penaltyStatusColor(t['status']),
      icon: Icons.person_outline,
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
            '-';
        final dept = e['department']?.toString() ??
            e['Department']?.toString() ??
            '';
        final count = e['ticketCount'] ?? e['TicketCount'] ?? 0;
        final amt = reportSafeDouble(e['totalAmount'] ?? e['TotalAmount']);
        return ReportEmployeeSummaryCard(
          name: name,
          meta: dept.isNotEmpty ? dept : null,
          primaryValue: '${reportMoneyFmt.format(amt)}đ',
          secondaryValue: '$count phiếu',
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
