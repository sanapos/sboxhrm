import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_tr.dart';
import '../models/device.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/attendance_leave_lookup.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/paid_leave_schedule_utils.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/salary_profile_load_utils.dart';
import '../utils/schedule_compliance.dart';
import '../utils/shift_records_calculator.dart';
import '../utils/work_schedule_load_utils.dart';
import '../widgets/hrm_page_chrome.dart';

const _navy = HrmPageChrome.primaryNavy;

Color scheduleComplianceColor(ScheduleComplianceStatus s) => switch (s) {
      ScheduleComplianceStatus.onTime => const Color(0xFF2E7D32),
      ScheduleComplianceStatus.lateEarly => const Color(0xFFEF6C00),
      ScheduleComplianceStatus.missingOut => const Color(0xFF8D6E63),
      ScheduleComplianceStatus.wrongShift => const Color(0xFF7B1FA2),
      ScheduleComplianceStatus.absent => const Color(0xFFC62828),
      ScheduleComplianceStatus.onLeave => const Color(0xFF0277BD),
      ScheduleComplianceStatus.offSchedule => const Color(0xFF546E7A),
    };

/// Đối chiếu chấm công thực tế với lịch làm việc — từng ca, cùng bộ tính với
/// «Tổng hợp chấm công theo ca». Chỉ để theo dõi; lương vẫn tính theo chấm công thực tế.
class ScheduleComplianceScreen extends StatefulWidget {
  const ScheduleComplianceScreen({super.key});

  @override
  State<ScheduleComplianceScreen> createState() => _ScheduleComplianceScreenState();
}

class _ScheduleComplianceScreenState extends State<ScheduleComplianceScreen> {
  final ApiService _api = ApiService();
  final _branchFilter = ReportBranchFilter();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _timeFmt = DateFormat('HH:mm');
  final _isoDate = DateFormat('yyyy-MM-dd');

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  bool _loading = false;
  String? _error;
  int _tab = 0; // 0 chi tiết, 1 theo NV, 2 theo phòng ban
  ScheduleComplianceStatus? _statusFilter;
  String _search = '';
  bool _hasSchedules = true;
  ScheduleComplianceResult? _result;

  bool get _teamView {
    final role = Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final isEmployee =
          isEmployeeUserRole(context.read<AuthProvider>().user?.role);
      await _branchFilter.ensureEmployees(_api);

      final deviceIds = <String>[];
      if (!isEmployee) {
        final raw = await _api.getDevices(storeOnly: true);
        deviceIds.addAll(raw.map((d) => Device.fromJson(d as Map<String, dynamic>).id));
      }

      var deh = 0, dem = 0;
      final dayEnd = await _api
          .getAppSetting('day_end_time')
          .catchError((_) => <String, dynamic>{});
      if (dayEnd['isSuccess'] == true && dayEnd['data'] is Map) {
        final parts = ((dayEnd['data'] as Map)['value']?.toString() ?? '00:00')
            .split(':');
        if (parts.length >= 2) {
          deh = int.tryParse(parts[0]) ?? 0;
          dem = int.tryParse(parts[1]) ?? 0;
        }
      }

      final att = await loadAttendancesForPeriodResult(
        _api,
        deviceIds: deviceIds,
        fromDate: _from,
        toDate: _to,
        dayEndHour: deh,
        dayEndMinute: dem,
      );
      final p = await Future.wait([
        _api.getShifts().catchError((_) => <dynamic>[]),
        _api.getShiftSalaryLevels().catchError((_) => <String, dynamic>{}),
        loadAttendanceSalaryProfiles(_api, preferSelfServiceApi: isEmployee),
        loadAllWorkSchedules(_api, fromDate: _from, toDate: _to, mine: isEmployee),
        loadLeavesForPeriod(
          _api,
          fromDate: _isoDate.format(_from),
          toDate: _isoDate.format(_to),
          status: 'Approved',
        ).catchError((_) => <dynamic>[]),
      ]);

      final shifts = (p[0] as List).map((s) => Map<String, dynamic>.from(s as Map)).toList();
      final levelsRaw = p[1] as Map<String, dynamic>;
      final levels = ((levelsRaw['data']?['items'] ?? levelsRaw['data'] ?? []) as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      final profiles = List<Map<String, dynamic>>.from(p[2] as List);
      final schedules = p[3] as List<Map<String, dynamic>>;
      final leaves = p[4] as List;
      final employees =
          _branchFilter.employees.map((e) => Map<String, dynamic>.from(e)).toList();

      final records = computeDailyShiftRecords(
        attendances: att.items,
        fromDate: _from,
        toDate: _to,
        shiftTemplates: shifts,
        shiftSalaryLevels: levels,
        salaryProfiles: profiles,
        employeesList: employees,
        dayEndHour: deh,
        dayEndMinute: dem,
        scheduleDayOffKeys: buildScheduleDayOffKeys(schedules),
      );
      final leaveLookup = AttendanceLeaveLookup.fromLeaves(
        leaves,
        employeesList: employees,
        includePending: false,
      );
      final byGuid = {for (final e in employees) e['id']?.toString() ?? '': e};
      final result = computeScheduleCompliance(
        schedules: schedules,
        records: records,
        employees: employees,
        fromDate: _from,
        toDate: _to,
        isOnApprovedLeave: (guid, day) {
          final e = byGuid[guid];
          return leaveLookup.classify(
                day: day,
                employeeCode: e?['employeeCode']?.toString(),
                employeeUserId: e?['applicationUserId']?.toString(),
                hrEmployeeId: guid,
                displayEmployeeId: guid,
                isHoliday: false,
                isWeeklyOff: false,
              ) ==
              AbsenceCellKind.approvedLeave;
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _hasSchedules = schedules.isNotEmpty;
        _loading = false;
        if (att.truncated) {
          _error = 'Đã tải ${att.items.length} lượt chấm — thu hẹp kỳ nếu thiếu ngày gần đây.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không tải được dữ liệu: $e';
      });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    await _load();
  }

  List<ScheduleComplianceRow> get _rows {
    final q = _search.trim().toLowerCase();
    return (_result?.rows ?? const <ScheduleComplianceRow>[]).where((r) {
      if (_statusFilter != null && r.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return r.employeeName.toLowerCase().contains(q) ||
          r.employeeCode.toLowerCase().contains(q) ||
          r.department.toLowerCase().contains(q);
    }).toList();
  }

  String _pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';
  String _t(DateTime? d) => d == null ? '' : _timeFmt.format(d);

  Future<void> _export() async {
    final period = '${_dateFmt.format(_from)} – ${_dateFmt.format(_to)}';
    if (_tab == 0) {
      final rows = _rows;
      await ClientExcelExport.export(
        context: context,
        title: 'Đối chiếu chấm công với lịch làm việc',
        sheetName: 'Chi tiet',
        filePrefix: 'DoiChieuLich',
        headers: const [
          'STT', 'Ngày', 'Mã NV', 'Nhân viên', 'Phòng ban', 'Ca theo lịch',
          'Ca thực tế', 'Giờ vào', 'Giờ ra', 'Đi trễ (phút)', 'Về sớm (phút)', 'Kết quả',
        ],
        rows: [
          for (var i = 0; i < rows.length; i++)
            [
              i + 1,
              _dateFmt.format(rows[i].date),
              rows[i].employeeCode,
              rows[i].employeeName,
              rows[i].department,
              rows[i].scheduledShift,
              rows[i].actualShift,
              _t(rows[i].checkIn),
              _t(rows[i].checkOut),
              rows[i].lateMinutes,
              rows[i].earlyMinutes,
              scheduleComplianceLabel(rows[i].status),
            ],
        ],
        periodLabel: period,
      );
      return;
    }
    final stats = _tab == 1 ? _result!.byEmployee : _result!.byDepartment;
    await ClientExcelExport.export(
      context: context,
      title: _tab == 1 ? 'Tuân thủ lịch theo nhân viên' : 'Tuân thủ lịch theo phòng ban',
      sheetName: _tab == 1 ? 'Theo NV' : 'Theo phong ban',
      filePrefix: _tab == 1 ? 'TuanThuLich_NV' : 'TuanThuLich_PB',
      headers: [
        'STT',
        _tab == 1 ? 'Nhân viên' : 'Phòng ban',
        if (_tab == 1) 'Phòng ban',
        'Ca có lịch',
        'Đúng lịch',
        'Đi trễ / Về sớm',
        'Thiếu chấm ra',
        'Sai ca',
        'Vắng có lịch',
        'Nghỉ phép',
        'Ngoài lịch',
        'Tỷ lệ tuân thủ',
        'Tỷ lệ có mặt',
      ],
      rows: [
        for (var i = 0; i < stats.length; i++)
          [
            i + 1,
            stats[i].label,
            if (_tab == 1) stats[i].department,
            stats[i].scheduled,
            for (final s in ScheduleComplianceStatus.values) stats[i].count(s),
            _pct(stats[i].complianceRate),
            _pct(stats[i].attendanceRate),
          ],
      ],
      periodLabel: period,
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: Text(tr('Đối chiếu chấm công với lịch')),
        actions: [
          IconButton(
            tooltip: tr('Xuất Excel'),
            onPressed: result == null || _loading ? null : _export,
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _pickRange,
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text('${_dateFmt.format(_from)} – ${_dateFmt.format(_to)}'),
                ),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, label: Text(tr('Chi tiết'))),
                    ButtonSegment(value: 1, label: Text(tr('Theo NV'))),
                    if (_teamView) ButtonSegment(value: 2, label: Text(tr('Phòng ban'))),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr('Chỉ để theo dõi việc đi làm theo lịch — lương vẫn tính theo chấm công thực tế.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (result != null && !_hasSchedules)
              _empty(tr('Kỳ này chưa có lịch làm việc nào — không có gì để đối chiếu.'))
            else if (result != null) ...[
              _summary(result.total),
              const SizedBox(height: 10),
              if (_tab == 0) ..._details() else ..._stats(_tab == 1 ? result.byEmployee : result.byDepartment),
            ],
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(text, textAlign: TextAlign.center)),
      );

  Widget _summary(ScheduleComplianceStat t) {
    Widget kpi(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(label), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _navy)),
            ],
          ),
        );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              kpi('Ca có lịch', '${t.scheduled}'),
              kpi('Tỷ lệ tuân thủ', _pct(t.complianceRate)),
              kpi('Tỷ lệ có mặt', _pct(t.attendanceRate)),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in ScheduleComplianceStatus.values)
                  ChoiceChip(
                    selected: _statusFilter == s,
                    visualDensity: VisualDensity.compact,
                    avatar: CircleAvatar(backgroundColor: scheduleComplianceColor(s), radius: 6),
                    label: Text('${tr(scheduleComplianceLabel(s))} ${t.count(s)}'),
                    onSelected: (_) => setState(() {
                      _statusFilter = _statusFilter == s ? null : s;
                      _tab = 0;
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _details() {
    final rows = _rows;
    return [
      if (_teamView)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Tìm nhân viên, mã NV, phòng ban'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      if (rows.isEmpty) _empty(tr('Không có dòng nào')),
      for (final r in rows.take(500)) _rowTile(r),
      if (rows.length > 500)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(tr('Hiển thị 500 / ${rows.length} dòng — xuất Excel để xem đủ.'),
              textAlign: TextAlign.center),
        ),
    ];
  }

  Widget _rowTile(ScheduleComplianceRow r) {
    final color = scheduleComplianceColor(r.status);
    final times = [
      if (r.checkIn != null) 'Vào ${_t(r.checkIn)}',
      if (r.checkOut != null) 'Ra ${_t(r.checkOut)}',
      if (r.lateMinutes > 0) 'Trễ ${r.lateMinutes}P',
      if (r.earlyMinutes > 0) 'Sớm ${r.earlyMinutes}P',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 74,
              child: Text(DateFormat('dd/MM\nEEE', 'vi').format(r.date),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_teamView)
                    Text('${r.employeeName}${r.employeeCode.isEmpty ? '' : ' · ${r.employeeCode}'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    [
                      if (r.scheduledShift.isNotEmpty) '${tr('Lịch')}: ${r.scheduledShift}',
                      if (r.actualShift.isNotEmpty) '${tr('Thực tế')}: ${r.actualShift}',
                    ].join('   '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                  if (times.isNotEmpty)
                    Text(times, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(tr(scheduleComplianceLabel(r.status)),
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _stats(List<ScheduleComplianceStat> stats) {
    if (stats.isEmpty) return [_empty(tr('Không có dữ liệu'))];
    return [
      for (final s in stats)
        Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _tab == 1 ? '${s.label} · ${s.department}' : s.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(_pct(s.complianceRate),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: (s.complianceRate ?? 1) >= 0.9
                              ? const Color(0xFF2E7D32)
                              : (s.complianceRate ?? 1) >= 0.7
                                  ? const Color(0xFFEF6C00)
                                  : const Color(0xFFC62828),
                        )),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Row(
                    children: [
                      for (final st in ScheduleComplianceStatus.values)
                        if (s.count(st) > 0)
                          Expanded(
                            flex: s.count(st),
                            child: Container(height: 8, color: scheduleComplianceColor(st)),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    '${s.scheduled} ${tr('ca có lịch')}',
                    for (final st in ScheduleComplianceStatus.values)
                      if (s.count(st) > 0) '${tr(scheduleComplianceLabel(st))} ${s.count(st)}',
                    '${tr('có mặt')} ${_pct(s.attendanceRate)}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
    ];
  }
}
