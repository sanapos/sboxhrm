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
import '../widgets/page_top_actions.dart';
import '../widgets/reports/hrm_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
import '../widgets/sbox/sbox_report.dart';
import '../widgets/sbox/sbox_charts.dart';
import '../utils/branch_filter_helper.dart';
const _theme = HrmPageChrome.primaryNavy;
const _accentDark = SboxColors.brand800;

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
  String? _selectedBranchId = BranchFilterHelper.viewBranchId;
  String? _selectedDepartmentId;
  int _viewTab = 0;
  int _page = 1;
  static const _pageSize = 50;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;
  List<Map<String, dynamic>> _tickets = [];
  int _totalCount = 0;
  List<Map<String, dynamic>> _byEmployee = [];
  final _pngKey = GlobalKey();

  bool get _teamView {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  /// Toàn bộ phiếu trong kỳ (không phân trang) — để dashboard tính đúng.
  List<Map<String, dynamic>> _statsTickets = [];

  List<Map<String, dynamic>> get _filtered => _scoped(_tickets);

  List<Map<String, dynamic>> get _statsFiltered => _scoped(_statsTickets);

  List<Map<String, dynamic>> _scoped(List<Map<String, dynamic>> source) {
    var result = source;
    if (_teamView) {
      result = result
          .where((t) => _branchFilter.mapRowInScope(
                t,
                branchId: _selectedBranchId,
                departmentId: _selectedDepartmentId,
              ))
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
      final pageFuture = loadPenaltyReportTickets(
        _api,
        from: _from,
        to: _to,
        statusFilter: _statusFilter,
        pageSize: _pageSize,
        page: _page,
      );
      // Dashboard cần cả kỳ: tải 1 lần khi đổi bộ lọc (trang 1), không tải lại khi chuyển trang.
      final statsFuture = _page == 1
          ? loadPenaltyReportTickets(_api,
              from: _from, to: _to, statusFilter: _statusFilter, pageSize: 2000, page: 1)
          : null;
      final result = await pageFuture;
      final stats = statsFuture == null ? null : await statsFuture;
      if (mounted) {
        setState(() {
          _tickets = result.items;
          _totalCount = result.totalCount;
          _loadError = result.error;
          if (stats != null) _statsTickets = stats.error == null ? stats.items : result.items;
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

  /// Biểu đồ dashboard: tiền phạt theo ngày, cơ cấu loại vi phạm, trạng thái, top nhân viên.
  List<Widget> _buildCharts() {
    final all = _statsFiltered;
    final f = penaltyRowsForReportStats(all, _statusFilter);
    if (f.isEmpty) return const [];
    final byType = <String, double>{};
    final byDay = <DateTime, double>{};
    final byEmp = <String, double>{};
    final empCnt = <String, int>{};
    for (final t in f) {
      final amt = reportSafeDouble(t['amount']);
      final type = (t['penaltyTypeLabel'] ?? penaltyTypeDisplayLabel(t['type'])).toString();
      byType[type] = (byType[type] ?? 0) + amt;
      final d = parseApiCalendarDate(t['date']);
      if (d != null) {
        final k = DateTime(d.year, d.month, d.day);
        byDay[k] = (byDay[k] ?? 0) + amt;
      }
      final n = t['employeeName']?.toString() ?? '—';
      byEmp[n] = (byEmp[n] ?? 0) + amt;
      empCnt[n] = (empCnt[n] ?? 0) + 1;
    }
    // Trạng thái tính trên mọi phiếu (kể cả đã hủy) để thấy tỷ lệ duyệt.
    final byStatus = <String, ({double v, Color c})>{};
    for (final t in all) {
      final label = t['statusLabel']?.toString() ?? penaltyStatusDisplayLabel(t['status']);
      final prev = byStatus[label];
      byStatus[label] = (v: (prev?.v ?? 0) + 1, c: penaltyStatusColor(t['status']));
    }
    final days = byDay.keys.toList()..sort();
    return [
      SboxChartCard(
        title: 'Tiền phạt theo ngày',
        child: SboxBarChart(
          valueFormat: (v) => SboxFmt.money(v),
          labels: [for (final d in days) sboxDayLabel(d)],
          series: [SboxSeries(name: 'Tiền phạt', values: [for (final d in days) byDay[d]!], color: SboxColors.danger)],
        ),
      ),
      SboxChartCard(
        title: 'Theo loại vi phạm',
        child: SboxDonutChart(
          valueFormat: (v) => SboxFmt.money(v),
          slices: [for (final e in byType.entries) SboxSlice(e.key, e.value)],
        ),
      ),
      SboxChartCard(
        title: 'Trạng thái phiếu',
        subtitle: 'Số phiếu',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SboxRatioBar(parts: [for (final e in byStatus.entries) SboxSlice(e.key, e.value.v, color: e.value.c)]),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 6, children: [
            for (final e in byStatus.entries)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: e.value.c, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('${tr(e.key)}: ${e.value.v.toInt()}', style: const TextStyle(fontSize: 12)),
              ]),
          ]),
        ]),
      ),
      if (_teamView)
        SboxChartCard(
          title: 'Nhân viên bị phạt nhiều nhất',
          child: SboxRankList(
            color: SboxColors.danger,
            valueFormat: (v) => SboxFmt.money(v),
            items: [for (final e in byEmp.entries) SboxSlice(e.key, e.value, caption: '${empCnt[e.key]} phiếu')],
          ),
        ),
    ];
  }

  List<ReportKpiItem> _buildKpis() {
    final f = penaltyRowsForReportStats(_statsFiltered, _statusFilter);
    final total = f.length;
    final approved = f.where((t) => isApprovedPenaltyStatus(t['status'])).length;
    final pending = total - approved;
    final totalAmt = f.fold(0.0, (s, t) => s + reportSafeDouble(t['amount']));
    final approvedAmt = f
        .where((t) => isApprovedPenaltyStatus(t['status']))
        .fold(0.0, (s, t) => s + reportSafeDouble(t['amount']));
    final approvedPct = totalAmt <= 0 ? 0 : (approvedAmt / totalAmt * 100).round();
    final avg = total == 0 ? 0.0 : totalAmt / total;

    if (!_teamView) {
      return [
        ReportKpiItem(
            label: 'Phiếu phạt',
            value: total.toString(),
            note: pending > 0 ? '$pending phiếu chưa duyệt' : 'Đã xử lý hết',
            icon: Icons.receipt_long,
            color: _theme),
        ReportKpiItem(
            label: 'Đã duyệt',
            value: approved.toString(),
            icon: Icons.check_circle_outline,
            color: SboxColors.success),
        ReportKpiItem(
            label: 'Tổng tiền',
            value: '${reportMoneyFmt.format(totalAmt)}đ',
            note: total == 0 ? null : 'TB ${reportMoneyFmt.format(avg)}đ/phiếu',
            icon: Icons.money_off_outlined,
            color: SboxColors.danger),
        ReportKpiItem(
            label: 'Tiền đã duyệt',
            value: '${reportMoneyFmt.format(approvedAmt)}đ',
            note: '$approvedPct% tổng tiền phạt',
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
          value: '$total',
          note: pending > 0 ? '$pending phiếu chưa duyệt' : 'Đã xử lý hết',
          icon: Icons.receipt_long,
          color: _theme),
      ReportKpiItem(
          label: 'NV vi phạm',
          value: empCount.toString(),
          note: empCount == 0 ? null : 'TB ${(total / empCount).toStringAsFixed(1).replaceAll('.', ',')} phiếu/NV',
          icon: Icons.people_outline,
          color: SboxColors.warning),
      ReportKpiItem(
          label: 'Tổng tiền phạt',
          value: '${reportMoneyFmt.format(totalAmt)}đ',
          note: total == 0 ? null : 'TB ${reportMoneyFmt.format(avg)}đ/phiếu',
          icon: Icons.money_off_outlined,
          color: SboxColors.danger),
      ReportKpiItem(
          label: 'Tiền đã duyệt',
          value: '${reportMoneyFmt.format(approvedAmt)}đ',
          note: '$approvedPct% tổng tiền phạt',
          icon: Icons.payments_outlined,
          color: SboxColors.success),
    ];
  }

  Future<void> _exportExcel({bool png = false}) async {
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
    final title = _teamView ? 'Báo cáo phạt' : 'Phiếu phạt của tôi';
    if (png) {
      await ClientPngExport.table(
        context: context,
        title: title,
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
      return;
    }
    await ClientExcelExport.export(
      context: context,
      title: title,
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

  Future<void> _exportPng() => _exportExcel(png: true);

  @override
  Widget build(BuildContext context) {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('PenaltyReport');

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
      child: Theme(
      data: vietnameseThemeOverlay(context),
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
                    storageKey: 'penalty',
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
        border: Border.all(color: SboxColors.slate300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _statusFilter,
          isExpanded: true,
          hint: Text(tr('Trạng thái'),
              style: vietnameseTextStyle(
                  const TextStyle(fontSize: 12, color: SboxColors.slate500))),
          style: vietnameseTextStyle(
              const TextStyle(fontSize: 12, color: SboxColors.slate900)),
          items: [
            DropdownMenuItem(
                value: null,
                child: Text(tr('Tất cả'), style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '0',
                child: Text(tr('Chờ duyệt'), style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '1',
                child: Text(tr('Đã duyệt'), style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '3',
                child: Text(tr('Tự động duyệt'), style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: '2',
                child: Text(tr('Đã hủy'), style: vietnameseTextStyle())),
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
