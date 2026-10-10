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

import '../theme/sbox_tokens.dart';
import '../widgets/sbox/sbox_report.dart';
import '../widgets/sbox/sbox_charts.dart';

import '../utils/branch_filter_helper.dart';
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
  String? _selectedBranchId = BranchFilterHelper.viewBranchId;
  String? _selectedDepartmentId;
  int _viewTab = 0;
  int _page = 1;
  static const _pageSize = 50;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;
  List<AdvanceRequest> _requests = [];
  int _totalCount = 0;
  List<Map<String, dynamic>> _byEmployee = [];
  final _pngKey = GlobalKey();

  bool get _teamView {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  /// Toàn bộ yêu cầu trong kỳ (không phân trang) — để dashboard tính đúng.
  List<AdvanceRequest> _statsRequests = [];

  List<AdvanceRequest> get _filtered => _scoped(_requests);

  List<AdvanceRequest> get _statsFiltered => _scoped(_statsRequests);

  List<AdvanceRequest> _scoped(List<AdvanceRequest> source) {
    var result = source;
    if (_teamView) {
      result = result.where((r) {
        return _branchFilter.mapRowInScope(
          {
            'employeeUserId': r.employeeUserId,
            'employeeCode': r.employeeCode,
          },
          branchId: _selectedBranchId,
          departmentId: _selectedDepartmentId,
        );
      }).toList();
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
        _branchFilter.loadOrgFilters(_api).then((_) async {
          await _branchFilter.ensureEmployees(_api,
              branchId: _selectedBranchId);
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
      Future<Map<String, dynamic>> fetch(int page, int size) => _api.getAdvanceRequests(
            fromDate: _from,
            toDate: _to,
            status: _statusFilter?.index,
            page: page,
            pageSize: size,
          );
      List<AdvanceRequest> toList(List<Map<String, dynamic>> items) {
        final list = <AdvanceRequest>[];
        for (final item in items) {
          try {
            list.add(AdvanceRequest.fromJson(item));
          } catch (_) {}
        }
        return list;
      }

      // Dashboard cần cả kỳ: tải 1 lần khi đổi bộ lọc (trang 1).
      final statsFuture = _page == 1 ? fetch(1, 2000) : null;
      final parsed = parsePagedReportListResponse(await fetch(_page, _pageSize));
      final list = toList(parsed.items);
      final statsParsed = statsFuture == null ? null : parsePagedReportListResponse(await statsFuture);
      if (mounted) {
        setState(() {
          _requests = list;
          _totalCount = parsed.totalCount;
          _loadError = parsed.error;
          if (statsParsed != null) {
            _statsRequests = statsParsed.error == null ? toList(statsParsed.items) : list;
          }
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

  /// Biểu đồ dashboard: tiền ứng theo ngày (yêu cầu / đã duyệt), trạng thái, top nhân viên.
  List<Widget> _buildCharts() {
    final all = _statsFiltered;
    final f = advanceRowsForReportStats(all, _statusFilter);
    if (f.isEmpty) return const [];
    final req = <DateTime, double>{};
    final ok = <DateTime, double>{};
    final byStatus = <AdvanceRequestStatus, double>{};
    final byEmp = <String, double>{};
    final empCnt = <String, int>{};
    for (final r in f) {
      final d = r.requestDate.isUtc ? r.requestDate.toLocal() : r.requestDate;
      final k = DateTime(d.year, d.month, d.day);
      req[k] = (req[k] ?? 0) + r.amount;
      ok.putIfAbsent(k, () => 0);
      if (r.status == AdvanceRequestStatus.approved) {
        ok[k] = ok[k]! + r.payoutAmount;
        byEmp[r.employeeName] = (byEmp[r.employeeName] ?? 0) + r.payoutAmount;
        empCnt[r.employeeName] = (empCnt[r.employeeName] ?? 0) + 1;
      }
    }
    for (final r in all) {
      byStatus[r.status] = (byStatus[r.status] ?? 0) + r.amount;
    }
    final days = req.keys.toList()..sort();
    String statusVi(AdvanceRequestStatus s) => switch (s) {
          AdvanceRequestStatus.pending => 'Chờ duyệt',
          AdvanceRequestStatus.approved => 'Đã duyệt',
          AdvanceRequestStatus.rejected => 'Từ chối',
          _ => 'Đã hủy',
        };
    Color statusColor(AdvanceRequestStatus s) => switch (s) {
          AdvanceRequestStatus.pending => SboxColors.warning,
          AdvanceRequestStatus.approved => SboxColors.success,
          AdvanceRequestStatus.rejected => SboxColors.danger,
          _ => SboxColors.slate400,
        };
    return [
      SboxChartCard(
        title: 'Tiền ứng theo ngày',
        subtitle: 'Yêu cầu và đã duyệt chi',
        child: SboxBarChart(
          valueFormat: (v) => SboxFmt.money(v),
          labels: [for (final d in days) sboxDayLabel(d)],
          series: [
            SboxSeries(name: 'Yêu cầu', values: [for (final d in days) req[d]!], color: SboxColors.slate300),
            SboxSeries(name: 'Đã duyệt', values: [for (final d in days) ok[d]!], color: SboxColors.success),
          ],
        ),
      ),
      SboxChartCard(
        title: 'Theo trạng thái',
        subtitle: 'Số tiền yêu cầu',
        child: SboxDonutChart(
          valueFormat: (v) => SboxFmt.money(v),
          slices: [
            for (final e in byStatus.entries) SboxSlice(statusVi(e.key), e.value, color: statusColor(e.key)),
          ],
        ),
      ),
      if (_teamView)
        SboxChartCard(
          title: 'Ứng nhiều nhất',
          subtitle: 'Đã duyệt chi',
          wide: true,
          child: SboxRankList(
            valueFormat: (v) => SboxFmt.money(v),
            items: [for (final e in byEmp.entries) SboxSlice(e.key, e.value, caption: '${empCnt[e.key]} lần')],
          ),
        ),
    ];
  }

  List<ReportKpiItem> _buildKpis() {
    final f = advanceRowsForReportStats(_statsFiltered, _statusFilter);
    final pendingRows = f.where((r) => r.status == AdvanceRequestStatus.pending).toList();
    final pending = pendingRows.length;
    final pendingAmt = pendingRows.fold(0.0, (s, r) => s + r.amount);
    final approved =
        f.where((r) => r.status == AdvanceRequestStatus.approved).length;
    final totalAmt = f.fold(0.0, (s, r) => s + r.amount);
    // Dùng payoutAmount (số tiền thực tế đã duyệt, có thể thấp hơn số tiền
    // yêu cầu) để KPI phản ánh đúng số tiền đã chi/sẽ chi.
    final approvedAmt = f
        .where((r) => r.status == AdvanceRequestStatus.approved)
        .fold(0.0, (s, r) => s + r.payoutAmount);
    // Bảng lương chỉ trừ phiếu ĐÃ CHI (theo ngày chi / tháng trừ) — tách khỏi phiếu duyệt chưa chi.
    final paidAmt = f
        .where((r) => r.status == AdvanceRequestStatus.approved && r.isPaid)
        .fold(0.0, (s, r) => s + r.payoutAmount);
    final unpaidAmt = approvedAmt - paidAmt;
    final empCount = f
        .where((r) => r.status == AdvanceRequestStatus.approved)
        .map((r) => r.employeeName)
        .toSet()
        .length;

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
            note: pending == 0 ? null : '${reportMoneyFmt.format(pendingAmt)}đ',
            icon: Icons.hourglass_empty,
            color: Colors.orange),
        ReportKpiItem(
            label: 'Đã duyệt',
            value: approved.toString(),
            icon: Icons.check_circle_outline,
            color: SboxColors.success),
        ReportKpiItem(
            label: 'Đã nhận',
            value: '${reportMoneyFmt.format(paidAmt)}đ',
            note: unpaidAmt > 0
                ? 'Chờ chi ${reportMoneyFmt.format(unpaidAmt)}đ'
                : (paidAmt > 0 ? 'Trừ vào lương khi chốt' : null),
            icon: Icons.payments_outlined,
            color: _theme),
      ];
    }
    return [
      ReportKpiItem(
          label: 'Tổng yêu cầu',
          value: '${f.length}',
          note: '${reportMoneyFmt.format(totalAmt)}đ',
          icon: Icons.list_alt,
          color: Colors.blueGrey),
      ReportKpiItem(
          label: 'Chờ duyệt',
          value: pending.toString(),
          note: pending == 0 ? 'Đã xử lý hết' : '${reportMoneyFmt.format(pendingAmt)}đ đang chờ',
          icon: Icons.hourglass_empty,
          color: Colors.orange),
      ReportKpiItem(
          label: 'Đã duyệt chi',
          value: '${reportMoneyFmt.format(approvedAmt)}đ',
          note: unpaidAmt > 0
              ? 'Đã chi ${reportMoneyFmt.format(paidAmt)}đ · Chờ chi ${reportMoneyFmt.format(unpaidAmt)}đ'
              : '$approved yêu cầu · đã chi hết',
          icon: Icons.account_balance,
          color: SboxColors.success),
      ReportKpiItem(
          label: 'Nhân viên đã ứng',
          value: '$empCount',
          note: empCount == 0 ? null : 'TB ${reportMoneyFmt.format(approvedAmt / empCount)}đ/NV',
          icon: Icons.people_outline,
          color: _theme),
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
        return SboxColors.success;
      case AdvanceRequestStatus.rejected:
        return SboxColors.danger;
      case AdvanceRequestStatus.cancelled:
        return SboxColors.danger;
    }
  }

  Future<void> _exportExcel({bool png = false}) async {
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
        r.status == AdvanceRequestStatus.approved && r.isPaid ? 'Đã chi' : _statusLabel(r.status),
        r.approvedByName ?? '',
      ]);
    }
    final title = _teamView ? 'Báo cáo ứng lương' : 'Lịch sử ứng lương';
    final headers = [
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
    ];
    final periodLabel = reportPeriodSubtitle(_from, _to, team: _teamView);
    if (png) {
      await ClientPngExport.table(
        context: context,
        title: title,
        filePrefix: 'BaoCaoUngLuong',
        headers: headers,
        rows: rows,
        periodLabel: periodLabel,
      );
      return;
    }
    await ClientExcelExport.export(
      context: context,
      title: title,
      sheetName: 'Bao cao ung luong',
      filePrefix: 'BaoCaoUngLuong',
      headers: headers,
      rows: rows,
      periodLabel: periodLabel,
    );
  }

  Future<void> _exportPng() => _exportExcel(png: true);

  @override
  Widget build(BuildContext context) {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('AdvanceReport');

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
                    storageKey: 'advance',
                    subtitle: reportPeriodSubtitle(_from, _to, team: _teamView),
                    kpis: _buildKpis(),
                    charts: _buildCharts(),
                  ),
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
        child: DropdownButton<AdvanceRequestStatus?>(
          value: _statusFilter,
          isExpanded: true,
          hint: Text(tr('Trạng thái'),
              style: TextStyle(fontSize: 12, color: SboxColors.slate500)),
          style: const TextStyle(fontSize: 12, color: SboxColors.slate900),
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
      statusLabel: r.status == AdvanceRequestStatus.approved && r.isPaid ? 'Đã chi' : _statusLabel(r.status),
      statusColor: _statusColor(r.status),
      icon: Icons.account_balance_wallet_outlined,
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
        final dept = e['department']?.toString() ??
            e['Department']?.toString() ??
            '';
        final count = e['totalRequests'] ?? e['TotalRequests'] ?? 0;
        final amt = reportSafeDouble(e['totalApproved'] ?? e['TotalApproved']);
        final unpaid = reportSafeDouble(e['outstandingDebt'] ?? e['OutstandingDebt']);
        return ReportEmployeeSummaryCard(
          name: name,
          meta: dept.isNotEmpty ? dept : null,
          primaryValue: '${reportMoneyFmt.format(amt)}đ',
          secondaryValue: unpaid > 0
              ? '$count lần ứng · chờ chi ${reportMoneyFmt.format(unpaid)}đ'
              : '$count lần ứng',
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
