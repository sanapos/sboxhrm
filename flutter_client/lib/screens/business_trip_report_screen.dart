import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/business_trip_status.dart';
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

class BusinessTripReportScreen extends StatefulWidget {
  const BusinessTripReportScreen({super.key});

  @override
  State<BusinessTripReportScreen> createState() =>
      _BusinessTripReportScreenState();
}

class _BusinessTripReportScreenState extends State<BusinessTripReportScreen> {
  final ApiService _api = ApiService();
  final _branchFilter = ReportBranchFilter();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  int? _statusFilter;
  String _empSearch = '';
  String? _selectedBranchId = BranchFilterHelper.viewBranchId;
  String? _selectedDepartmentId;
  String? _selectedCategoryKey; // categoryId or 'uncategorized'
  int _viewTab = 0;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;
  List<Map<String, dynamic>> _cases = [];
  List<Map<String, dynamic>> _byEmployee = [];
  List<Map<String, dynamic>> _byCategory = [];
  int? _summaryTotalCases;
  double _summaryAdvance = 0;
  double _summarySettled = 0;
  double _summaryBalance = 0;
  double _summaryWithInvoice = 0;
  double _summaryWithoutInvoice = 0;
  int _expenseLineCount = 0;
  final _pngKey = GlobalKey();

  bool get _teamView {
    final role = Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  List<Map<String, dynamic>> get _filtered {
    var result = _cases;
    if (_teamView) {
      result = result
          .where((c) => _branchFilter.mapRowInScope(
                c,
                branchId: _selectedBranchId,
                departmentId: _selectedDepartmentId,
              ))
          .toList();
    }
    if (_teamView && _empSearch.isNotEmpty) {
      final q = _empSearch.toLowerCase();
      result = result
          .where((c) =>
              (c['employeeName']?.toString().toLowerCase().contains(q) ??
                  false) ||
              (c['caseCode']?.toString().toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_statusFilter != null) {
      result = result
          .where((c) => parseTripStatus(c['status']) == _statusFilter)
          .toList();
    } else {
      result = result
          .where((c) => parseTripStatus(c['status']) != 9)
          .toList();
    }
    if (_selectedCategoryKey != null) {
      result = result.where((c) {
        if (_selectedCategoryKey == 'uncategorized') {
          return c['hasUncategorizedExpense'] == true ||
              c['HasUncategorizedExpense'] == true;
        }
        final ids = c['categoryIds'] ?? c['CategoryIds'];
        if (ids is! List) return false;
        return ids.map((e) => e.toString()).contains(_selectedCategoryKey);
      }).toList();
    }
    return result;
  }

  List<String> get _empSuggestions => _cases
      .map((c) => c['employeeName']?.toString() ?? '')
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
      final res = await _api.getBusinessTripReport(
        from: _from,
        to: _to,
        status: _statusFilter,
      );
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final rawItems = data['items'] ?? data['Items'];
        final rawByEmp = data['byEmployee'] ?? data['ByEmployee'];
        final rawByCat = data['byCategory'] ?? data['ByCategory'];
        final total = data['totalCases'] ?? data['TotalCases'];
        setState(() {
          _summaryTotalCases = total is int ? total : int.tryParse('$total');
          _summaryAdvance = reportSafeDouble(
              data['totalAdvanceAmount'] ?? data['TotalAdvanceAmount']);
          _summarySettled = reportSafeDouble(
              data['totalSettledAmount'] ?? data['TotalSettledAmount']);
          _summaryBalance = reportSafeDouble(
              data['totalBalanceAmount'] ?? data['TotalBalanceAmount']);
          _summaryWithInvoice = reportSafeDouble(
              data['totalWithInvoice'] ?? data['TotalWithInvoice']);
          _summaryWithoutInvoice = reportSafeDouble(
              data['totalWithoutInvoice'] ?? data['TotalWithoutInvoice']);
          final lines = data['expenseLineCount'] ?? data['ExpenseLineCount'];
          _expenseLineCount =
              lines is int ? lines : int.tryParse('$lines') ?? 0;
          _cases = rawItems is List
              ? rawItems
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
              : [];
          _byEmployee = rawByEmp is List
              ? rawByEmp
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
              : [];
          _byCategory = rawByCat is List
              ? rawByCat
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList()
              : [];
        });
      } else {
        setState(() {
          _loadError = res['message']?.toString() ?? 'Không tải được báo cáo';
          _cases = [];
          _byEmployee = [];
          _byCategory = [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = 'Không tải được báo cáo công tác phí: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Biểu đồ dashboard: khoản mục chi phí, tạm ứng / quyết toán theo NV, hóa đơn, trạng thái hồ sơ.
  List<Widget> _buildCharts() {
    final f = _filtered.where((c) => parseTripStatus(c['status']) != 9).toList();
    if (f.isEmpty && _byCategory.isEmpty) return const [];
    final adv = <String, double>{};
    final set = <String, double>{};
    for (final c in f) {
      final n = c['employeeName']?.toString() ?? '—';
      adv[n] = (adv[n] ?? 0) + reportSafeDouble(c['advanceAmount']);
      set[n] = (set[n] ?? 0) + reportSafeDouble(c['settledAmount']);
    }
    final names = adv.keys.toList()..sort((a, b) => (set[b]! + adv[b]!).compareTo(set[a]! + adv[a]!));
    final top = names.take(10).toList();
    final byStatus = <String, double>{};
    for (final c in _filtered) {
      final label = c['statusLabel']?.toString() ?? tripStatusLabel(parseTripStatus(c['status']));
      byStatus[label] = (byStatus[label] ?? 0) + 1;
    }
    final withInv = _summaryWithInvoice;
    final withoutInv = _summaryWithoutInvoice;
    return [
      if (_byCategory.isNotEmpty)
        SboxChartCard(
          title: 'Chi phí theo khoản mục',
          child: SboxDonutChart(
            valueFormat: (v) => SboxFmt.money(v),
            slices: [
              for (final e in _byCategory)
                SboxSlice('${e['categoryName'] ?? e['CategoryName'] ?? 'Khác'}', reportSafeDouble(e['totalAmount'])),
            ],
          ),
        ),
      if (withInv + withoutInv > 0)
        SboxChartCard(
          title: 'Chứng từ chi phí',
          subtitle: 'Có / không có hóa đơn',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SboxRatioBar(parts: [
              SboxSlice('Có hóa đơn', withInv, color: SboxColors.success),
              SboxSlice('Không hóa đơn', withoutInv, color: SboxColors.warning),
            ]),
            const SizedBox(height: 10),
            Text('${tr('Có hóa đơn')}: ${reportMoneyFmt.format(withInv)}đ',
                style: const TextStyle(fontSize: 12.5, color: SboxColors.successText)),
            const SizedBox(height: 2),
            Text('${tr('Không hóa đơn')}: ${reportMoneyFmt.format(withoutInv)}đ',
                style: const TextStyle(fontSize: 12.5, color: SboxColors.warningText)),
          ]),
        ),
      if (top.isNotEmpty)
        SboxChartCard(
          title: _teamView ? 'Tạm ứng và quyết toán theo nhân viên' : 'Tạm ứng và quyết toán',
          wide: true,
          child: SboxBarChart(
            valueFormat: (v) => SboxFmt.money(v),
            labels: top,
            series: [
              SboxSeries(name: 'Tạm ứng', values: [for (final n in top) adv[n]!], color: SboxColors.warning),
              SboxSeries(name: 'Quyết toán', values: [for (final n in top) set[n]!], color: SboxColors.success),
            ],
          ),
        ),
      if (byStatus.length > 1)
        SboxChartCard(
          title: 'Trạng thái hồ sơ',
          child: SboxRankList(
            color: SboxColors.brand500,
            valueFormat: (v) => '${SboxFmt.number(v)} hồ sơ',
            items: [for (final e in byStatus.entries) SboxSlice(e.key, e.value)],
          ),
        ),
    ];
  }

  List<ReportKpiItem> _buildKpis() {
    final f = _filtered.where((c) => parseTripStatus(c['status']) != 9).toList();
    final useClientTotals = _statusFilter != null ||
        _selectedBranchId != null ||
        _selectedDepartmentId != null ||
        _empSearch.isNotEmpty ||
        _selectedCategoryKey != null;
    final totalAdv = useClientTotals
        ? f.fold(0.0, (s, c) => s + reportSafeDouble(c['advanceAmount']))
        : _summaryAdvance;
    final totalSet = useClientTotals
        ? f.fold(0.0, (s, c) => s + reportSafeDouble(c['settledAmount']))
        : _summarySettled;
    final totalBal = useClientTotals
        ? f.fold(0.0, (s, c) => s + reportSafeDouble(c['balanceAmount']))
        : _summaryBalance;
    final caseCount = useClientTotals
        ? f.length
        : (_summaryTotalCases ?? f.length);

    final empCount = f.map((c) => c['employeeName']?.toString() ?? '').where((n) => n.isNotEmpty).toSet().length;
    // Chênh lệch = chi phí − tạm ứng: dương → công ty trả thêm cho NV; âm → NV hoàn lại.
    final balNote = totalBal > 0
        ? 'Công ty cần trả thêm cho NV'
        : (totalBal < 0 ? 'NV cần hoàn lại công ty' : 'Đã cân bằng');
    return [
      ReportKpiItem(
          label: _teamView ? 'Tổng hồ sơ' : 'Hồ sơ',
          value: '$caseCount',
          note: _teamView && empCount > 0 ? '$empCount nhân viên' : null,
          icon: Icons.flight_takeoff,
          color: _theme),
      ReportKpiItem(
          label: 'Tổng tạm ứng',
          value: '${reportMoneyFmt.format(totalAdv)}đ',
          icon: Icons.payments_outlined,
          color: SboxColors.warning),
      ReportKpiItem(
          label: 'Tổng chi phí',
          value: '${reportMoneyFmt.format(totalSet)}đ',
          note: _expenseLineCount > 0 ? '$_expenseLineCount khoản chi' : null,
          icon: Icons.receipt_long,
          color: SboxColors.success),
      ReportKpiItem(
          label: 'Chênh lệch',
          value: '${reportMoneyFmt.format(totalBal.abs())}đ',
          note: balNote,
          icon: Icons.balance_outlined,
          color: _theme,
          tone: totalBal == 0 ? SboxTone.success : (totalBal > 0 ? SboxTone.warning : SboxTone.danger)),
    ];
  }

  Future<void> _exportExcel({bool png = false}) async {
    if (_teamView && _viewTab == 1) {
      await _exportCategoryExcel();
      return;
    }
    if (_teamView && _viewTab == 2) {
      await _exportEmployeeExcel();
      return;
    }
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final c = data[i];
      rows.add([
        i + 1,
        c['caseCode'],
        if (_teamView) c['employeeName'],
        if (_teamView) c['employeeCode'],
        c['title'],
        c['destination'] ?? '',
        c['statusLabel'] ?? tripStatusLabel(c['status']),
        reportSafeDouble(c['advanceAmount']),
        reportSafeDouble(c['settledAmount']),
        reportSafeDouble(c['balanceAmount']),
        c['expenseLineCount'] ?? c['ExpenseLineCount'] ?? 0,
        reportSafeDouble(c['totalWithInvoice'] ?? c['TotalWithInvoice']),
        c['createdAt'] != null
            ? reportDateFmt.format(DateTime.parse(c['createdAt'].toString()))
            : '',
      ]);
    }
    final title = _teamView ? 'Báo cáo công tác phí' : 'Lịch sử công tác phí';
    final headers = [
      'STT',
      'Mã HS',
      if (_teamView) 'Nhân viên',
      if (_teamView) 'Mã NV',
      'Tiêu đề',
      'Điểm đến',
      'Trạng thái',
      'Đã ứng (đ)',
      'Tổng chi phí (đ)',
      'Chênh lệch (đ)',
      'Số dòng CP',
      'Có HĐ (đ)',
      'Ngày tạo',
    ];
    final periodLabel = reportPeriodSubtitle(_from, _to, team: _teamView);
    final summaryLines = [
      'Tổng chi phí: ${reportMoneyFmt.format(_summarySettled)}đ',
      'Có hóa đơn: ${reportMoneyFmt.format(_summaryWithInvoice)}đ · Không HĐ: ${reportMoneyFmt.format(_summaryWithoutInvoice)}đ',
      if (_expenseLineCount > 0) 'Số dòng chi: $_expenseLineCount',
    ];
    if (png) {
      await ClientPngExport.table(
        context: context,
        title: title,
        filePrefix: 'BaoCaoCongTacPhi',
        headers: headers,
        rows: rows,
        periodLabel: periodLabel,
        summaryLines: summaryLines,
      );
      return;
    }
    await ClientExcelExport.export(
      context: context,
      title: title,
      sheetName: 'Chi tiet',
      filePrefix: 'BaoCaoCongTacPhi',
      headers: [
        'STT',
        'Mã HS',
        if (_teamView) 'Nhân viên',
        if (_teamView) 'Mã NV',
        'Tiêu đề',
        'Điểm đến',
        'Trạng thái',
        'Đã ứng (đ)',
        'Tổng chi phí (đ)',
        'Chênh lệch (đ)',
        'Số dòng CP',
        'Có HĐ (đ)',
        'Ngày tạo',
      ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: _teamView),
      summaryLines: [
        'Tổng chi phí: ${reportMoneyFmt.format(_summarySettled)}đ',
        'Có hóa đơn: ${reportMoneyFmt.format(_summaryWithInvoice)}đ · Không HĐ: ${reportMoneyFmt.format(_summaryWithoutInvoice)}đ',
        if (_expenseLineCount > 0) 'Số dòng chi: $_expenseLineCount',
      ],
    );
  }

  Future<void> _exportCategoryExcel({bool png = false}) async {
    final rows = <List<dynamic>>[];
    for (int i = 0; i < _byCategory.length; i++) {
      final e = _byCategory[i];
      rows.add([
        i + 1,
        e['categoryName'] ?? e['CategoryName'] ?? '—',
        e['categoryCode'] ?? e['CategoryCode'] ?? '',
        e['lineCount'] ?? e['LineCount'] ?? 0,
        e['caseCount'] ?? e['CaseCount'] ?? 0,
        reportSafeDouble(e['totalAmount'] ?? e['TotalAmount']),
        reportSafeDouble(e['withInvoiceAmount'] ?? e['WithInvoiceAmount']),
        reportSafeDouble(e['withoutInvoiceAmount'] ?? e['WithoutInvoiceAmount']),
        reportSafeDouble(e['percentage'] ?? e['Percentage']),
      ]);
    }
    final headers = [
      'STT',
      'Loại chi phí',
      'Mã',
      'Số dòng',
      'Số HS',
      'Tổng tiền (đ)',
      'Có HĐ (đ)',
      'Không HĐ (đ)',
      'Tỷ lệ (%)',
    ];
    if (png) {
      await ClientPngExport.table(
        context: context,
        title: 'Công tác phí — theo loại chi phí',
        filePrefix: 'CongTacPhi_TheoLoai',
        headers: headers,
        rows: rows,
        periodLabel: reportPeriodSubtitle(_from, _to, team: true),
        summaryLines: [
          'Tổng chi phí: ${reportMoneyFmt.format(_summarySettled)}đ',
        ],
      );
      return;
    }
    await ClientExcelExport.export(
      context: context,
      title: 'Công tác phí — theo loại chi phí',
      sheetName: 'Theo loai CP',
      filePrefix: 'CongTacPhi_TheoLoai',
      headers: [
        'STT',
        'Loại chi phí',
        'Mã',
        'Số dòng',
        'Số HS',
        'Tổng tiền (đ)',
        'Có HĐ (đ)',
        'Không HĐ (đ)',
        'Tỷ lệ (%)',
      ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: true),
      summaryLines: [
        'Tổng chi phí: ${reportMoneyFmt.format(_summarySettled)}đ',
      ],
    );
  }

  Future<void> _exportEmployeeExcel({bool png = false}) async {
    final rows = <List<dynamic>>[];
    for (int i = 0; i < _byEmployee.length; i++) {
      final e = _byEmployee[i];
      rows.add([
        i + 1,
        e['employeeName'] ?? e['EmployeeName'] ?? '—',
        e['employeeCode'] ?? e['EmployeeCode'] ?? '',
        e['department'] ?? e['Department'] ?? '',
        e['totalCases'] ?? e['TotalCases'] ?? 0,
        reportSafeDouble(e['totalAdvance'] ?? e['TotalAdvance']),
        reportSafeDouble(e['totalSettled'] ?? e['TotalSettled']),
        reportSafeDouble(e['totalBalance'] ?? e['TotalBalance']),
      ]);
    }
    final headers = [
      'STT',
      'Nhân viên',
      'Mã NV',
      'Phòng ban',
      'Số HS',
      'Tổng ứng (đ)',
      'Tổng chi phí (đ)',
      'Chênh lệch (đ)',
    ];
    if (png) {
      await ClientPngExport.table(
        context: context,
        title: 'Công tác phí — theo nhân viên',
        filePrefix: 'CongTacPhi_TheoNV',
        headers: headers,
        rows: rows,
        periodLabel: reportPeriodSubtitle(_from, _to, team: true),
      );
      return;
    }
    await ClientExcelExport.export(
      context: context,
      title: 'Công tác phí — theo nhân viên',
      sheetName: 'Theo NV',
      filePrefix: 'CongTacPhi_TheoNV',
      headers: [
        'STT',
        'Nhân viên',
        'Mã NV',
        'Phòng ban',
        'Số HS',
        'Tổng ứng (đ)',
        'Tổng chi phí (đ)',
        'Chênh lệch (đ)',
      ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: true),
    );
  }

  Future<void> _exportPng() {
    if (_teamView && _viewTab == 1) return _exportCategoryExcel(png: true);
    if (_teamView && _viewTab == 2) return _exportEmployeeExcel(png: true);
    return _exportExcel(png: true);
  }

  bool get _pngExportEmpty {
    if (_viewTab == 1) return _byCategory.isEmpty;
    if (_teamView && _viewTab == 2) return _byEmployee.isEmpty;
    return _filtered.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('BusinessTripReport');

    return RegisterPageTopActions(
      actions: [
        if (canExport)
          HrmTopBarAction(
            icon: Icons.image_outlined,
            label: 'Xuất PNG',
            onPressed: _pngExportEmpty ? null : _exportPng,
            pinOnMobile: false,
          ),
        if (canExport)
          HrmTopBarAction(
            icon: Icons.file_download_outlined,
            label: 'Xuất Excel',
            onPressed: _pngExportEmpty ? null : _exportExcel,
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
                      statusSummary: _statusFilter != null
                          ? tripStatusLabel(_statusFilter)
                          : null,
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
                      onApply: _load,
                      onClearFilters: _teamView
                          ? () => setState(() {
                                _empSearch = '';
                                _selectedBranchId = BranchFilterHelper.viewBranchId;
                                _selectedDepartmentId = null;
                                _statusFilter = null;
                                _selectedCategoryKey = null;
                              })
                          : () => setState(() {
                                _statusFilter = null;
                                _selectedCategoryKey = null;
                              }),
                    ),
                  ),
                  if (_selectedCategoryKey != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InputChip(
                          label: Text(tr('Loại CP: ${_categoryLabel(_selectedCategoryKey!)}'),
                            style: const TextStyle(fontSize: 12),
                          ),
                          onDeleted: () =>
                              setState(() => _selectedCategoryKey = null),
                        ),
                      ),
                    ),
                  reportLoadErrorBanner(_loadError),
                  if (!_loading)
                    ReportDashboard(
                      storageKey: 'business_trip',
                      subtitle: reportPeriodSubtitle(_from, _to, team: _teamView),
                      kpis: _buildKpis(),
                      charts: _buildCharts(),
                    ),
                  if (_teamView)
                    ReportViewModeTabs(
                      index: _viewTab,
                      onChanged: (i) => setState(() => _viewTab = i),
                      tabs: const [
                        (label: 'Chi tiết', icon: Icons.list_alt),
                        (label: 'Theo loại', icon: Icons.category_outlined),
                        (label: 'Theo NV', icon: Icons.people_outline),
                      ],
                    )
                  else
                    ReportViewModeTabs(
                      index: _viewTab.clamp(0, 1),
                      onChanged: (i) => setState(() => _viewTab = i),
                      tabs: const [
                        (label: 'Chi tiết', icon: Icons.list_alt),
                        (label: 'Theo loại', icon: Icons.category_outlined),
                      ],
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_viewTab == 1)
                    _buildByCategory()
                  else if (_teamView && _viewTab == 2)
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
        ],
      ),
      ),
    );
  }

  String _categoryLabel(String key) {
    if (key == 'uncategorized') return 'Không phân loại';
    for (final e in _byCategory) {
      final id = (e['categoryId'] ?? e['CategoryId'])?.toString();
      if (id == key) {
        return (e['categoryName'] ?? e['CategoryName'] ?? key).toString();
      }
    }
    return key;
  }

  String? _categoryKeyOf(Map<String, dynamic> e) {
    final id = e['categoryId'] ?? e['CategoryId'];
    if (id == null) return 'uncategorized';
    final s = id.toString();
    if (s.isEmpty || s == 'null') return 'uncategorized';
    return s;
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
            for (int i = 0; i <= 9; i++)
              if (i != 9)
                DropdownMenuItem(
                    value: i, child: Text(tr(tripStatusLabel(i)))),
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
        title: _teamView ? 'Không có hồ sơ công tác' : 'Bạn chưa có hồ sơ',
        subtitle: 'Thử đổi khoảng thời gian hoặc bộ lọc',
      );
    }
    return Column(
      children: rows.map((c) => _caseCard(c)).toList(),
    );
  }

  Widget _caseCard(Map<String, dynamic> c) {
    final status = parseTripStatus(c['status']);
    final created = c['createdAt']?.toString();
    DateTime? createdDt;
    if (created != null) {
      try {
        createdDt = DateTime.parse(created);
      } catch (_) {}
    }
    final lineCount = c['expenseLineCount'] ?? c['ExpenseLineCount'] ?? 0;
    return ReportTimelineCard(
      title: _teamView
          ? '${c['caseCode']} · ${c['employeeName'] ?? '—'}'
          : (c['title']?.toString() ?? c['caseCode']?.toString() ?? '—'),
      trailing: createdDt != null ? reportDateFmt.format(createdDt) : '',
      amount:
          '${reportMoneyFmt.format(reportSafeDouble(c['settledAmount']))}đ',
      subtitle: [
        if (!_teamView) c['caseCode'],
        c['title'],
        c['destination'],
        'Ứng: ${reportMoneyFmt.format(reportSafeDouble(c['advanceAmount']))}đ',
        if (reportSafeDouble(c['balanceAmount']) != 0)
          'CL: ${reportMoneyFmt.format(reportSafeDouble(c['balanceAmount']))}đ',
        if (lineCount is num && lineCount > 0) '$lineCount dòng CP',
      ].where((s) => s != null && s.toString().isNotEmpty).join(' · '),
      accentColor: _theme,
      statusLabel: c['statusLabel']?.toString() ?? tripStatusLabel(status),
      statusColor: tripStatusColor(status),
      icon: Icons.flight_takeoff_outlined,
    );
  }

  Widget _buildByCategory() {
    if (_byCategory.isEmpty) {
      return const ReportEmptyState(
        title: 'Chưa có chi phí theo loại',
        subtitle: 'Chưa có dòng hoạch toán trong kỳ hoặc chưa gắn hạng mục',
      );
    }
    return Column(
      children: _byCategory.map((e) {
        final name =
            (e['categoryName'] ?? e['CategoryName'] ?? '—').toString();
        final lines = e['lineCount'] ?? e['LineCount'] ?? 0;
        final cases = e['caseCount'] ?? e['CaseCount'] ?? 0;
        final total =
            reportSafeDouble(e['totalAmount'] ?? e['TotalAmount']);
        final pct = reportSafeDouble(e['percentage'] ?? e['Percentage']);
        final withInv = reportSafeDouble(
            e['withInvoiceAmount'] ?? e['WithInvoiceAmount']);
        final key = _categoryKeyOf(e);
        final selected = key == _selectedCategoryKey;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          elevation: 0,
          color: selected ? const Color(0xFFEFF8FF) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: selected ? _theme : SboxColors.slate200,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              _selectedCategoryKey =
                  selected ? null : key;
              _viewTab = 0;
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr(name),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Text(tr('${reportMoneyFmt.format(total)}đ'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: SboxColors.success,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('$lines dòng · $cases HS · $pct%'
                    '${withInv > 0 ? ' · HĐ ${reportMoneyFmt.format(withInv)}đ' : ''}'),
                    style: const TextStyle(
                        fontSize: 12, color: SboxColors.slate500),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: SboxColors.slate200,
                      color: _theme,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
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
        final count = e['totalCases'] ?? e['TotalCases'] ?? 0;
        final settled = reportSafeDouble(
            e['totalSettled'] ?? e['TotalSettled'] ?? 0);
        final advance = reportSafeDouble(
            e['totalAdvance'] ?? e['TotalAdvance'] ?? 0);
        return ReportEmployeeSummaryCard(
          name: name,
          meta: dept.isNotEmpty ? dept : null,
          primaryValue: '${reportMoneyFmt.format(settled)}đ chi phí',
          secondaryValue: '$count HS · ứng ${reportMoneyFmt.format(advance)}đ',
          accentColor: _theme,
          onTap: () => setState(() {
            _viewTab = 0;
            _empSearch = name == '—' ? '' : name;
          }),
        );
      }).toList(),
    );
  }
}
