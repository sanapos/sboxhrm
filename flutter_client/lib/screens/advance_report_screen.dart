import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/hrm.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/reports/hrm_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _theme = HrmPageChrome.primaryNavy;

class AdvanceReportScreen extends StatefulWidget {
  const AdvanceReportScreen({super.key});
  @override
  State<AdvanceReportScreen> createState() => _AdvanceReportScreenState();
}

class _AdvanceReportScreenState extends State<AdvanceReportScreen> {
  final ApiService _api = ApiService();
  final _branchFilter = ReportBranchFilter();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  AdvanceRequestStatus? _statusFilter;
  String _empSearch = '';
  String? _selectedBranchId;
  int _viewTab = 0;
  int _page = 1;
  static const _pageSize = 50;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;
  List<AdvanceRequest> _requests = [];
  int _totalCount = 0;
  int? _summaryTotalRequests;
  List<Map<String, dynamic>> _byEmployee = [];

  bool get _teamView {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  List<AdvanceRequest> get _filtered {
    var result = _requests;
    if (_teamView && _selectedBranchId != null) {
      final ids = _branchFilter.userIdsForBranch(_selectedBranchId);
      if (ids.isEmpty) return [];
      result = result.where((r) => ids.contains(r.employeeUserId)).toList();
    }
    if (_teamView && _empSearch.isNotEmpty) {
      result = result
          .where((r) =>
              r.employeeName.toLowerCase().contains(_empSearch.toLowerCase()))
          .toList();
    }
    return result;
  }

  List<String> get _empSuggestions => _requests
      .map((r) => r.employeeName)
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
      final result = await _api.getAdvanceRequests(
        fromDate: _from,
        toDate: _to,
        status: _statusFilter?.index,
        page: _page,
        pageSize: _pageSize,
      );
      final parsed = parsePagedReportListResponse(result);
      final list = <AdvanceRequest>[];
      for (final item in parsed.items) {
        try {
          list.add(AdvanceRequest.fromJson(item));
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _requests = list;
          _totalCount = parsed.totalCount;
          _loadError = parsed.error;
        });
      }
      if (_teamView) await _loadSummary();
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = 'Không tải được báo cáo ứng lương: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSummary() async {
    try {
      final res = await _api.getAdvanceDebtReport(
        from: _from,
        to: _to,
        status: _statusFilter?.index,
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        final raw = data['items'] ?? data['Items'];
        if (mounted) {
          setState(() {
            final total = data['totalRequests'] ?? data['TotalRequests'];
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

  List<ReportKpiItem> _buildKpis() {
    final f = advanceRowsForReportStats(_filtered, _statusFilter);
    final pending =
        f.where((r) => r.status == AdvanceRequestStatus.pending).length;
    final approved =
        f.where((r) => r.status == AdvanceRequestStatus.approved).length;
    final totalAmt = f.fold(0.0, (s, r) => s + r.amount);
    // Dùng payoutAmount (số tiền thực tế đã duyệt, có thể thấp hơn số tiền
    // yêu cầu) để KPI phản ánh đúng số tiền đã chi/sẽ chi.
    final approvedAmt = f
        .where((r) => r.status == AdvanceRequestStatus.approved)
        .fold(0.0, (s, r) => s + r.payoutAmount);

    if (!_teamView) {
      return [
        ReportKpiItem(
            label: 'Yêu cầu',
            value: f.length.toString(),
            icon: Icons.list_alt,
            color: _theme),
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
            label: 'Tổng đã ứng',
            value: '${reportMoneyFmt.format(approvedAmt)}đ',
            icon: Icons.payments_outlined,
            color: _theme),
      ];
    }
    return [
      ReportKpiItem(
          label: 'Tổng yêu cầu',
          value: (_statusFilter == null && _summaryTotalRequests != null)
              ? '$_summaryTotalRequests'
              : (_statusFilter != null ? '$_totalCount' : '${f.length}'),
          icon: Icons.list_alt,
          color: Colors.blueGrey),
      ReportKpiItem(
          label: 'Chờ duyệt',
          value: pending.toString(),
          icon: Icons.hourglass_empty,
          color: Colors.orange),
      ReportKpiItem(
          label: 'Tổng tiền',
          value: '${reportMoneyFmt.format(totalAmt)}đ',
          icon: Icons.payments_outlined,
          color: _theme),
      ReportKpiItem(
          label: 'Đã duyệt',
          value: '${reportMoneyFmt.format(approvedAmt)}đ',
          icon: Icons.account_balance,
          color: const Color(0xFF16A34A)),
    ];
  }

  String _statusLabel(AdvanceRequestStatus s) {
    switch (s) {
      case AdvanceRequestStatus.pending:
        return 'Chờ duyệt';
      case AdvanceRequestStatus.approved:
        return 'Đã duyệt';
      case AdvanceRequestStatus.rejected:
        return 'Từ chối';
      case AdvanceRequestStatus.cancelled:
        return 'Đã hủy';
    }
  }

  Color _statusColor(AdvanceRequestStatus s) {
    switch (s) {
      case AdvanceRequestStatus.pending:
        return Colors.orange;
      case AdvanceRequestStatus.approved:
        return const Color(0xFF16A34A);
      case AdvanceRequestStatus.rejected:
        return const Color(0xFFDC2626);
      case AdvanceRequestStatus.cancelled:
        return const Color(0xFFDC2626);
    }
  }

  Future<void> _exportExcel() async {
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final r = data[i];
      rows.add([
        i + 1,
        if (_teamView) r.employeeName,
        if (_teamView) r.employeeCode,
        (r.forMonth != null && r.forYear != null)
            ? '${r.forMonth}/${r.forYear}'
            : '',
        reportDateFmt.format(r.requestDate),
        r.amount,
        r.payoutAmount,
        r.reason ?? '',
        _statusLabel(r.status),
        r.approvedByName ?? '',
      ]);
    }
    await ClientExcelExport.export(
      context: context,
      title: _teamView ? 'Báo cáo ứng lương' : 'Lịch sử ứng lương',
      sheetName: 'Bao cao ung luong',
      filePrefix: 'BaoCaoUngLuong',
      headers: [
        'STT',
        if (_teamView) 'Nhân viên',
        if (_teamView) 'Mã NV',
        'Tháng/Năm',
        'Ngày tạo',
        'Số tiền yêu cầu (đ)',
        'Số tiền đã duyệt (đ)',
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
        .canExport('AdvanceReport');

    return RegisterPageTopActions(
      actions: [
        if (canExport)
          HrmTopBarAction(
            icon: Icons.file_download_outlined,
            label: 'Xuất Excel',
            onPressed: _exportExcel,
          ),
        HrmTopBarAction(
          icon: Icons.refresh,
          label: 'Tải lại',
          onPressed: _load,
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
                  ReportCollapsibleChrome(
                    expanded: _showOverviewPanel,
                    onToggle: () => setState(
                        () => _showOverviewPanel = !_showOverviewPanel),
                    kpi: ReportKpiGrid(items: _buildKpis()),
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
                  ),
                  reportLoadErrorBanner(_loadError),
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
        child: DropdownButton<AdvanceRequestStatus?>(
          value: _statusFilter,
          isExpanded: true,
          hint: Text(tr('Trạng thái'),
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
          items: [
            DropdownMenuItem(value: null, child: Text(tr('Tất cả'))),
            ...AdvanceRequestStatus.values.map(
                (s) => DropdownMenuItem(value: s, child: Text(tr(_statusLabel(s))))),
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
        title: _teamView ? 'Không có yêu cầu ứng lương' : 'Bạn chưa có ứng lương',
        subtitle: 'Thử đổi khoảng thời gian hoặc bộ lọc',
      );
    }
    return Column(
      children: rows.map((r) => _requestCard(r)).toList(),
    );
  }

  Widget _requestCard(AdvanceRequest r) {
    final monthYear = (r.forMonth != null && r.forYear != null)
        ? 'Tháng ${r.forMonth}/${r.forYear}'
        : null;
    return ReportTimelineCard(
      title: _teamView ? r.employeeName : (monthYear ?? 'Ứng lương'),
      trailing: reportDateFmt.format(r.requestDate),
      amount: '${reportMoneyFmt.format(r.payoutAmount)}đ',
      subtitle: [
        if (_teamView && monthYear != null) monthYear,
        if (_teamView) r.employeeCode,
        r.reason ?? '',
        if (r.isPartiallyApproved)
          'YC ban đầu: ${reportMoneyFmt.format(r.amount)}đ',
        if (r.approvedByName != null && r.approvedByName!.isNotEmpty)
          'Duyệt: ${r.approvedByName}',
      ].where((s) => s != null && s.toString().isNotEmpty).join(' · '),
      accentColor: _theme,
      statusLabel: _statusLabel(r.status),
      statusColor: _statusColor(r.status),
      icon: Icons.account_balance_wallet_outlined,
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
        final dept = e['department']?.toString() ??
            e['Department']?.toString() ??
            '';
        final count = e['totalRequests'] ?? e['TotalRequests'] ?? 0;
        final amt = reportSafeDouble(e['totalApproved'] ??
            e['TotalApproved'] ??
            e['outstandingDebt'] ??
            e['OutstandingDebt']);
        return ReportEmployeeSummaryCard(
          name: name,
          meta: dept.isNotEmpty ? dept : null,
          primaryValue: '${reportMoneyFmt.format(amt)}đ',
          secondaryValue: '$count lần ứng',
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
