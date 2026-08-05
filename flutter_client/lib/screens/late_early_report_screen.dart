import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/attendance_date_range_presets.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/paid_leave_schedule_utils.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/responsive_helper.dart';
import '../utils/salary_profile_load_utils.dart';
import '../utils/shift_records_calculator.dart';
import '../utils/vietnamese_font.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/reports/hrm_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Brand blue shades — cùng tông, đậm/nhạt khác để phân biệt trễ / sớm.
const _theme = HrmPageChrome.primaryNavy; // #0056B3
const _lateColor = Color(0xFF00408A); // đậm hơn — đi trễ
const _earlyColor = Color(0xFF3B8CFF); // nhạt hơn — về sớm

/// Báo cáo tổng hợp đi trễ / về sớm — cùng thuật toán [computeDailyShiftPairs]
/// với màn Tổng hợp chấm công theo ca.
class LateEarlyReportScreen extends StatefulWidget {
  const LateEarlyReportScreen({super.key});

  @override
  State<LateEarlyReportScreen> createState() => _LateEarlyReportScreenState();
}

class _LateEarlyReportScreenState extends State<LateEarlyReportScreen> {
  final ApiService _api = ApiService();
  final _branchFilter = ReportBranchFilter();
  final _timeFmt = DateFormat('HH:mm');
  final _dateFmt = DateFormat('dd/MM/yyyy');

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  /// all | late | early
  String _kindFilter = 'all';
  int _minMinutes = 1;
  String _empSearch = '';
  String? _selectedBranchId;
  int _viewTab = 0; // 0 chi tiết, 1 theo NV
  int _page = 1;
  static const _pageSize = 40;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;
  List<DailyShiftLateEntry> _entries = [];

  bool get _teamView {
    final role = Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      if (_teamView) {
        _branchFilter.loadBranches(_api).then((_) {
          if (mounted) setState(() {});
        });
      }
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final isEmployee = isEmployeeUserRole(
        context.read<AuthProvider>().user?.role,
      );
      await _branchFilter.ensureEmployees(
        _api,
        branchId: _teamView ? _selectedBranchId : null,
      );

      final List<Device> devices;
      if (isEmployee) {
        devices = [];
      } else {
        final devicesRaw = await _api.getDevices(storeOnly: true);
        devices = devicesRaw
            .map((d) => Device.fromJson(d as Map<String, dynamic>))
            .toList();
      }
      final deviceIds = devices.map((d) => d.id).toList();

      final dayEndResult = await _api
          .getAppSetting('day_end_time')
          .catchError((_) => <String, dynamic>{});
      var deh = 0, dem = 0;
      if (dayEndResult['isSuccess'] == true && dayEndResult['data'] is Map) {
        final value =
            (dayEndResult['data'] as Map)['value']?.toString() ?? '00:00:00';
        final parts = value.split(':');
        if (parts.length >= 2) {
          deh = int.tryParse(parts[0]) ?? 0;
          dem = int.tryParse(parts[1]) ?? 0;
        }
      }

      final range = _resolvePresetRange();
      _from = range.start;
      _to = range.end;

      final attLoad = await loadAttendancesForPeriodResult(
        _api,
        deviceIds: deviceIds,
        fromDate: _from,
        toDate: _to,
        dayEndHour: deh,
        dayEndMinute: dem,
        pageSize: 1000,
      );

      final p2 = await Future.wait([
        _api.getShifts().catchError((_) => <dynamic>[]),
        _api.getShiftSalaryLevels().catchError((_) => <String, dynamic>{}),
        loadAttendanceSalaryProfiles(
          _api,
          preferSelfServiceApi: isEmployee,
        ),
        (isEmployee
                ? _api.getMyWorkSchedules(
                    fromDate: _from, toDate: _to, pageSize: 1000)
                : _api.getWorkSchedules(
                    fromDate: _from, toDate: _to, pageSize: 1000))
            .catchError((_) => <String, dynamic>{}),
      ]);

      final shifts = (p2[0] as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      final levelsRaw = p2[1] as Map<String, dynamic>;
      final levels = ((levelsRaw['data']?['items'] ??
              levelsRaw['data'] ??
              []) as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      final profiles = List<Map<String, dynamic>>.from(p2[2] as List);
      final schedules = extractWorkScheduleItems(
        p2[3] is Map<String, dynamic>
            ? p2[3] as Map<String, dynamic>
            : <String, dynamic>{},
      );
      final dayOffKeys = buildScheduleDayOffKeys(schedules);

      final attendances = attLoad.items;

      final entries = computeDailyShiftLateEntries(
        attendances: attendances,
        fromDate: _from,
        toDate: _to,
        shiftTemplates: shifts,
        shiftSalaryLevels: levels,
        salaryProfiles: profiles,
        employeesList: _branchFilter.employees
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        dayEndHour: deh,
        dayEndMinute: dem,
        scheduleDayOffKeys: dayOffKeys,
      );

      if (!mounted) return;
      setState(() {
        _entries = entries;
        _page = 1;
        _loading = false;
        if (attLoad.truncated) {
          _loadError =
              'Đã tải ${attendances.length} log — thu hẹp kỳ nếu thiếu ngày gần đây.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Không tải được báo cáo đi trễ/về sớm: $e';
        });
      }
    }
  }

  DateTimeRange _resolvePresetRange() {
    switch (_datePreset) {
      case 'today':
        return AttendanceDateRangePresets.resolve('today');
      case 'yesterday':
        return AttendanceDateRangePresets.resolve('yesterday');
      case 'this_week':
        return AttendanceDateRangePresets.resolve('week');
      case 'last_week':
        return AttendanceDateRangePresets.resolve('lastWeek');
      case 'last_month':
        return AttendanceDateRangePresets.resolve('lastMonth');
      case 'custom':
        return DateTimeRange(start: _from, end: _to);
      case 'this_month':
      default:
        return AttendanceDateRangePresets.resolve('month');
    }
  }

  List<DailyShiftLateEntry> get _filteredEntries {
    var list = _entries;
    if (_kindFilter == 'late') {
      list = list.where((e) => e.lateMinutes >= _minMinutes).toList();
    } else if (_kindFilter == 'early') {
      list = list.where((e) => e.earlyMinutes >= _minMinutes).toList();
    } else {
      list = list
          .where((e) =>
              e.lateMinutes >= _minMinutes || e.earlyMinutes >= _minMinutes)
          .toList();
    }

    if (_teamView && _selectedBranchId != null) {
      final codes = _branchFilter.codesForBranch(_selectedBranchId);
      if (codes.isEmpty) return [];
      list = list
          .where((e) =>
              codes.contains(e.employeeCode) || codes.contains(e.employeeId))
          .toList();
    }

    if (_teamView && _empSearch.trim().isNotEmpty) {
      final q = _empSearch.trim().toLowerCase();
      list = list
          .where((e) =>
              e.employeeName.toLowerCase().contains(q) ||
              e.employeeCode.toLowerCase().contains(q))
          .toList();
    }

    list = List.of(list)
      ..sort((a, b) {
        final d = b.date.compareTo(a.date);
        if (d != 0) return d;
        return a.employeeName.compareTo(b.employeeName);
      });
    return list;
  }

  List<_EmpAgg> get _byEmployee {
    final map = <String, _EmpAgg>{};
    for (final e in _filteredEntries) {
      final key = e.employeeCode.isNotEmpty ? e.employeeCode : e.employeeId;
      final agg = map.putIfAbsent(
        key,
        () => _EmpAgg(
          code: e.employeeCode,
          name: e.employeeName,
        ),
      );
      if (e.lateMinutes > 0) {
        agg.lateCount++;
        agg.lateMinutes += e.lateMinutes;
      }
      if (e.earlyMinutes > 0) {
        agg.earlyCount++;
        agg.earlyMinutes += e.earlyMinutes;
      }
    }
    final list = map.values.toList()
      ..sort((a, b) {
        final t = (b.lateMinutes + b.earlyMinutes)
            .compareTo(a.lateMinutes + a.earlyMinutes);
        if (t != 0) return t;
        return a.name.compareTo(b.name);
      });
    return list;
  }

  List<ReportKpiItem> _buildKpis(List<DailyShiftLateEntry> rows) {
    final lateEvents = rows.where((e) => e.lateMinutes > 0).length;
    final earlyEvents = rows.where((e) => e.earlyMinutes > 0).length;
    final lateMin =
        rows.fold<int>(0, (s, e) => s + (e.lateMinutes > 0 ? e.lateMinutes : 0));
    final earlyMin = rows.fold<int>(
        0, (s, e) => s + (e.earlyMinutes > 0 ? e.earlyMinutes : 0));
    final empCount = rows
        .map((e) => e.employeeCode.isNotEmpty ? e.employeeCode : e.employeeId)
        .toSet()
        .length;
    return [
      ReportKpiItem(
        label: 'Lần đi trễ',
        value: '$lateEvents',
        icon: Icons.timer_off_outlined,
        color: _lateColor,
      ),
      ReportKpiItem(
        label: 'Tổng phút trễ',
        value: '$lateMin',
        icon: Icons.hourglass_bottom,
        color: _theme,
      ),
      ReportKpiItem(
        label: 'Lần về sớm',
        value: '$earlyEvents',
        icon: Icons.logout,
        color: _earlyColor,
      ),
      ReportKpiItem(
        label: _teamView ? 'NV vi phạm' : 'Tổng phút sớm',
        value: _teamView ? '$empCount' : '$earlyMin',
        icon: _teamView ? Icons.people_outline : Icons.hourglass_top,
        color: _theme,
      ),
    ];
  }

  Future<void> _exportExcel() async {
    final rows = _viewTab == 0
        ? _filteredEntries
            .asMap()
            .entries
            .map((e) {
              final r = e.value;
              return <dynamic>[
                e.key + 1,
                _dateFmt.format(r.date),
                if (_teamView) r.employeeName,
                if (_teamView) r.employeeCode,
                r.shiftName,
                r.checkIn != null ? _timeFmt.format(r.checkIn!) : '',
                r.checkOut != null ? _timeFmt.format(r.checkOut!) : '',
                r.lateMinutes > 0 ? r.lateMinutes : '',
                r.earlyMinutes > 0 ? r.earlyMinutes : '',
              ];
            })
            .toList()
        : _byEmployee
            .asMap()
            .entries
            .map((e) {
              final r = e.value;
              return <dynamic>[
                e.key + 1,
                r.name,
                r.code,
                r.lateCount,
                r.lateMinutes,
                r.earlyCount,
                r.earlyMinutes,
              ];
            })
            .toList();

    await ClientExcelExport.export(
      context: context,
      title: 'Báo cáo đi trễ / về sớm',
      sheetName: _viewTab == 0 ? 'Chi tiet' : 'Theo NV',
      filePrefix: 'DiTreVeSom',
      headers: _viewTab == 0
          ? [
              'STT',
              'Ngày',
              if (_teamView) 'Nhân viên',
              if (_teamView) 'Mã NV',
              'Ca',
              'Giờ vào',
              'Giờ ra',
              'Đi trễ (phút)',
              'Về sớm (phút)',
            ]
          : [
              'STT',
              'Nhân viên',
              'Mã NV',
              'Số lần trễ',
              'Tổng phút trễ',
              'Số lần về sớm',
              'Tổng phút sớm',
            ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: _teamView),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canExport = perm.canExport('LateEarlyReport') ||
        perm.canExport('AttendanceByShift');
    final filtered = _filteredEntries;
    final isMobile = Responsive.isMobile(context);
    final useTable = Responsive.preferTableListLayout(context);

    return RegisterPageTopActions(
      actions: [
        if (canExport)
          HrmTopBarAction(
            icon: Icons.file_download_outlined,
            label: 'Xuất Excel',
            onPressed: filtered.isEmpty ? null : _exportExcel,
          ),
        HrmTopBarAction(
          icon: Icons.refresh,
          label: 'Tải lại',
          onPressed: _load,
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
                      ReportCollapsibleChrome(
                        expanded: _showOverviewPanel,
                        onToggle: () => setState(
                            () => _showOverviewPanel = !_showOverviewPanel),
                        kpi: ReportKpiGrid(items: _buildKpis(filtered)),
                        betweenKpiAndFilter: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                            child: Row(
                              children: [
                                Text(tr('Tối thiểu'),
                                    style: vietnameseTextStyle(TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700))),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 88,
                                  child: DropdownButtonFormField<int>(
                                    value: _minMinutes,
                                    isDense: true,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 1, child: Text('≥ 1 phút')),
                                      DropdownMenuItem(
                                          value: 5, child: Text('≥ 5 phút')),
                                      DropdownMenuItem(
                                          value: 10, child: Text('≥ 10 phút')),
                                      DropdownMenuItem(
                                          value: 15, child: Text('≥ 15 phút')),
                                      DropdownMenuItem(
                                          value: 30, child: Text('≥ 30 phút')),
                                    ],
                                    onChanged: (v) => setState(() {
                                      _minMinutes = v ?? 1;
                                      _page = 1;
                                    }),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  tr('Theo ca · ân hạn đã trừ'),
                                  style: vietnameseTextStyle(TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600)),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                          statusFilter: _kindDrop(),
                          statusSummary: _kindSummary(),
                          showTeamFilters: _teamView,
                          branchFilter: _teamView ? _branchFilter : null,
                          selectedBranchId: _selectedBranchId,
                          onBranchChanged: (v) async {
                            await _branchFilter.ensureEmployees(_api,
                                branchId: v);
                            if (mounted) {
                              setState(() => _selectedBranchId = v);
                            }
                          },
                          empSearch: _empSearch,
                          onEmpSearchChanged: (v) =>
                              setState(() => _empSearch = v),
                          empSuggestions: _entries
                              .map((e) => e.employeeName)
                              .where((n) => n.isNotEmpty)
                              .toSet()
                              .toList()
                            ..sort(),
                          onApply: () {
                            setState(() => _page = 1);
                            _load();
                          },
                          onClearFilters: _teamView
                              ? () => setState(() {
                                    _empSearch = '';
                                    _selectedBranchId = null;
                                    _kindFilter = 'all';
                                    _minMinutes = 1;
                                  })
                              : null,
                        ),
                      ),
                      reportLoadErrorBanner(_loadError),
                      if (_teamView)
                        ReportViewModeTabs(
                          index: _viewTab,
                          tabs: const [
                            (label: 'Chi tiết', icon: Icons.list_alt),
                            (label: 'Theo nhân viên', icon: Icons.people_outline),
                          ],
                          onChanged: (i) => setState(() {
                            _viewTab = i;
                            _page = 1;
                          }),
                        ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(48),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: HrmPageChrome.primaryNavy,
                            ),
                          ),
                        )
                      else if (_viewTab == 1 && _teamView)
                        _buildEmployeeSection(isMobile || !useTable)
                      else
                        _buildDetailSection(
                          filtered,
                          useTable: useTable && !isMobile,
                        ),
                      if (!isMobile) const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (_viewTab == 0)
                ReportPaginationBar(
                  page: _page,
                  pageSize: _pageSize,
                  totalCount: filtered.length,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String? _kindSummary() {
    switch (_kindFilter) {
      case 'late':
        return 'Chỉ đi trễ';
      case 'early':
        return 'Chỉ về sớm';
      default:
        return null;
    }
  }

  Widget _kindDrop() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _kindFilter,
          isExpanded: true,
          style: vietnameseTextStyle(
              const TextStyle(fontSize: 12, color: Color(0xFF111827))),
          items: [
            DropdownMenuItem(
                value: 'all',
                child: Text(tr('Trễ & sớm'), style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: 'late',
                child: Text(tr('Chỉ đi trễ'), style: vietnameseTextStyle())),
            DropdownMenuItem(
                value: 'early',
                child: Text(tr('Chỉ về sớm'), style: vietnameseTextStyle())),
          ],
          onChanged: (v) => setState(() {
            _kindFilter = v ?? 'all';
            _page = 1;
          }),
        ),
      ),
    );
  }

  List<DailyShiftLateEntry> _paged(List<DailyShiftLateEntry> all) {
    if (all.isEmpty) return [];
    final start = (_page - 1) * _pageSize;
    if (start >= all.length) return [];
    final end = (start + _pageSize).clamp(0, all.length);
    return all.sublist(start, end);
  }

  Widget _buildDetailSection(
    List<DailyShiftLateEntry> all, {
    required bool useTable,
  }) {
    if (all.isEmpty) {
      return ReportEmptyState(
        title: 'Không có đi trễ / về sớm',
        subtitle:
            'Trong kỳ này không có ca vượt ân hạn (hoặc đổi bộ lọc / kỳ ngày)',
      );
    }
    final pageRows = _paged(all);
    if (useTable) {
      return _buildDesktopDetailTable(pageRows, all.length);
    }
    return Column(
      children: pageRows.map(_mobileDetailCard).toList(),
    );
  }

  Widget _buildDesktopDetailTable(
      List<DailyShiftLateEntry> rows, int totalCount) {
    final cols = <DataColumn>[
      const DataColumn(label: Text('STT')),
      const DataColumn(label: Text('Ngày')),
      if (_teamView) const DataColumn(label: Text('Nhân viên')),
      if (_teamView) const DataColumn(label: Text('Mã')),
      const DataColumn(label: Text('Ca')),
      const DataColumn(label: Text('Vào')),
      const DataColumn(label: Text('Ra')),
      const DataColumn(label: Text('Trễ (p)')),
      const DataColumn(label: Text('Sớm (p)')),
    ];
    final start = (_page - 1) * _pageSize;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              tr('Chi tiết theo ca ($totalCount dòng)'),
              style: vietnameseTextStyle(
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 52,
              columns: cols
                  .map((c) => DataColumn(
                        label: DefaultTextStyle(
                          style: vietnameseTextStyle(const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                          child: c.label,
                        ),
                      ))
                  .toList(),
              rows: rows.asMap().entries.map((e) {
                final i = e.key;
                final r = e.value;
                return DataRow(cells: [
                  DataCell(Text('${start + i + 1}')),
                  DataCell(Text(_dateFmt.format(r.date))),
                  if (_teamView)
                    DataCell(SizedBox(
                      width: 140,
                      child: Text(r.employeeName,
                          overflow: TextOverflow.ellipsis),
                    )),
                  if (_teamView) DataCell(Text(r.employeeCode)),
                  DataCell(Text(r.shiftName.isEmpty ? '—' : r.shiftName)),
                  DataCell(Text(
                      r.checkIn != null ? _timeFmt.format(r.checkIn!) : '—')),
                  DataCell(Text(
                      r.checkOut != null ? _timeFmt.format(r.checkOut!) : '—')),
                  DataCell(Text(
                    r.lateMinutes > 0 ? '${r.lateMinutes}' : '—',
                    style: TextStyle(
                      color: r.lateMinutes > 0 ? _lateColor : null,
                      fontWeight:
                          r.lateMinutes > 0 ? FontWeight.w700 : FontWeight.normal,
                    ),
                  )),
                  DataCell(Text(
                    r.earlyMinutes > 0 ? '${r.earlyMinutes}' : '—',
                    style: TextStyle(
                      color: r.earlyMinutes > 0 ? _earlyColor : null,
                      fontWeight: r.earlyMinutes > 0
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  )),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileDetailCard(DailyShiftLateEntry r) {
    final parts = <String>[
      if (r.shiftName.isNotEmpty) r.shiftName,
      if (r.checkIn != null) 'Vào ${_timeFmt.format(r.checkIn!)}',
      if (r.checkOut != null) 'Ra ${_timeFmt.format(r.checkOut!)}',
    ];
    return ReportTimelineCard(
      title: _teamView ? r.employeeName : (r.shiftName.isEmpty ? 'Ca' : r.shiftName),
      trailing: _dateFmt.format(r.date),
      subtitle: [
        if (_teamView && r.employeeCode.isNotEmpty) 'Mã ${r.employeeCode}',
        ...parts,
      ].where((s) => s.isNotEmpty).join(' · '),
      accentColor: r.lateMinutes > 0 ? _lateColor : _earlyColor,
      statusLabel: r.lateMinutes > 0 && r.earlyMinutes > 0
          ? 'Trễ ${r.lateMinutes}p · Sớm ${r.earlyMinutes}p'
          : (r.lateMinutes > 0
              ? 'Đi trễ ${r.lateMinutes} phút'
              : 'Về sớm ${r.earlyMinutes} phút'),
      statusColor: r.lateMinutes > 0 ? _lateColor : _earlyColor,
      icon: r.lateMinutes > 0 ? Icons.timer_off : Icons.logout,
    );
  }

  Widget _buildEmployeeSection(bool compact) {
    final list = _byEmployee;
    if (list.isEmpty) {
      return const ReportEmptyState(
        title: 'Chưa có dữ liệu tổng hợp',
        subtitle: 'Thử đổi khoảng thời gian hoặc bộ lọc',
      );
    }
    if (!compact) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            columns: [
              'STT',
              'Nhân viên',
              'Mã',
              'Lần trễ',
              'Phút trễ',
              'Lần sớm',
              'Phút sớm',
            ]
                .map((h) => DataColumn(
                      label: Text(tr(h),
                          style: vietnameseTextStyle(const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600))),
                    ))
                .toList(),
            rows: list.asMap().entries.map((e) {
              final i = e.key;
              final r = e.value;
              return DataRow(cells: [
                DataCell(Text('${i + 1}')),
                DataCell(SizedBox(
                    width: 160,
                    child: Text(r.name, overflow: TextOverflow.ellipsis))),
                DataCell(Text(r.code)),
                DataCell(Text('${r.lateCount}')),
                DataCell(Text('${r.lateMinutes}',
                    style: const TextStyle(
                        color: _lateColor, fontWeight: FontWeight.w700))),
                DataCell(Text('${r.earlyCount}')),
                DataCell(Text('${r.earlyMinutes}',
                    style: const TextStyle(
                        color: _earlyColor, fontWeight: FontWeight.w700))),
              ]);
            }).toList(),
          ),
        ),
      );
    }
    return Column(
      children: list
          .map((e) => ReportEmployeeSummaryCard(
                name: e.name,
                meta: e.code.isNotEmpty ? 'Mã ${e.code}' : null,
                primaryValue: e.lateMinutes > 0
                    ? 'Trễ ${e.lateMinutes}p (${e.lateCount} lần)'
                    : '—',
                secondaryValue: e.earlyMinutes > 0
                    ? 'Sớm ${e.earlyMinutes}p (${e.earlyCount} lần)'
                    : 'Không về sớm',
                accentColor: _theme,
                onTap: () => setState(() {
                  _viewTab = 0;
                  _empSearch = e.name;
                  _page = 1;
                }),
              ))
          .toList(),
    );
  }
}

class _EmpAgg {
  final String code;
  final String name;
  int lateCount = 0;
  int lateMinutes = 0;
  int earlyCount = 0;
  int earlyMinutes = 0;

  _EmpAgg({required this.code, required this.name});
}
