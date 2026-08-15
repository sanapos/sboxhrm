import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/mobile_attendance.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/attendance_correction_privilege.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/responsive_helper.dart';
import '../utils/travel_hours_calculator.dart';
import '../utils/vietnamese_font.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/manual_travel_dialog.dart';
import '../widgets/mobile_attendance_record_detail_sheet.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/reports/hrm_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _theme = HrmPageChrome.primaryNavy;

class _TravelTripRow {
  _TravelTripRow({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.start,
    this.arrive,
    this.startRecord,
    this.arriveRecord,
  });

  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final DateTime start;
  final DateTime? arrive;
  final MobileAttendanceRecord? startRecord;
  final MobileAttendanceRecord? arriveRecord;

  bool get isComplete =>
      arrive != null && startRecord != null && arriveRecord != null;
  double get hours {
    if (!isComplete || arrive == null) return 0;
    if (arrive!.isBefore(start)) return 0;
    return arrive!.difference(start).inMinutes / 60.0;
  }

  String get statusLabel {
    if (startRecord != null && arriveRecord == null) return 'Thiếu đến điểm';
    if (startRecord == null && arriveRecord != null) return 'Thiếu bắt đầu đi';
    if (!isComplete) return 'Thiếu chấm';
    final s = startRecord?.status ?? arriveRecord?.status ?? '';
    if (s == 'approved' || s == 'auto_approved') return 'Đã duyệt';
    if (s == 'pending') return 'Chờ duyệt';
    if (s == 'rejected') return 'Từ chối';
    return s.isEmpty ? '—' : s;
  }
}

class _EmpTravelAgg {
  _EmpTravelAgg({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
  });

  final String employeeId;
  final String employeeName;
  final String employeeCode;
  double hours = 0;
  int completeTrips = 0;
  int incompleteTrips = 0;
}

/// Báo cáo đi đường chi tiết — cặp Bắt đầu đi → Đến điểm làm + nút bổ sung.
class TravelHoursReportScreen extends StatefulWidget {
  const TravelHoursReportScreen({super.key});

  @override
  State<TravelHoursReportScreen> createState() =>
      _TravelHoursReportScreenState();
}

class _TravelHoursReportScreenState extends State<TravelHoursReportScreen> {
  final ApiService _api = ApiService();
  final _branchFilter = ReportBranchFilter();
  final _timeFmt = DateFormat('HH:mm');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _pngKey = GlobalKey();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  String _statusFilter = 'all'; // all | complete | incomplete
  String _empSearch = '';
  String? _selectedBranchId;
  int _viewTab = 0; // 0 chi tiết, 1 theo NV
  int _page = 1;
  static const _pageSize = 40;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;
  List<_TravelTripRow> _trips = [];

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
      await _branchFilter.ensureEmployees(
        _api,
        branchId: _teamView ? _selectedBranchId : null,
      );

      final toEnd = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
      final res = await _api.getMobileAttendanceHistory(
        fromDate: DateTime(_from.year, _from.month, _from.day),
        toDate: toEnd,
        punchTypes: '2,3',
        pageSize: 5000,
      );
      if (res['isSuccess'] != true) {
        throw Exception(res['message']?.toString() ?? 'Không tải được dữ liệu');
      }
      final raw = res['data'];
      final dynamic list =
          raw is List ? raw : (raw is Map ? (raw['items'] ?? raw['records']) : null);
      final records = (list is List)
          ? list
              .whereType<Map>()
              .map((e) =>
                  MobileAttendanceRecord.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : <MobileAttendanceRecord>[];

      final codeById = <String, String>{};
      for (final emp in _branchFilter.employees) {
        final id = emp['id']?.toString() ?? '';
        final code = emp['employeeCode']?.toString() ?? '';
        final userId = emp['applicationUserId']?.toString() ?? '';
        if (id.isNotEmpty && code.isNotEmpty) codeById[id] = code;
        if (userId.isNotEmpty && code.isNotEmpty) codeById[userId] = code;
        if (code.isNotEmpty) codeById[code] = code;
      }

      setState(() {
        _trips = _buildTrips(records, codeById);
        _loading = false;
        _page = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
        _trips = [];
      });
    }
  }

  List<_TravelTripRow> _buildTrips(
    List<MobileAttendanceRecord> records,
    Map<String, String> codeById,
  ) {
    final byEmp = <String, List<MobileAttendanceRecord>>{};
    for (final r in records) {
      if (!isTravelPunchType(r.punchType)) continue;
      final key = r.odooEmployeeId.trim();
      if (key.isEmpty) continue;
      byEmp.putIfAbsent(key, () => []).add(r);
    }

    final out = <_TravelTripRow>[];
    for (final entry in byEmp.entries) {
      final list = entry.value
        ..sort((a, b) => a.punchTime.compareTo(b.punchTime));
      MobileAttendanceRecord? pendingStart;
      for (final r in list) {
        if (r.punchType == mobilePunchTravelStart) {
          if (pendingStart != null) {
            out.add(_TravelTripRow(
              employeeId: entry.key,
              employeeName: pendingStart.employeeName,
              employeeCode: codeById[entry.key] ?? '',
              start: pendingStart.punchTime,
              startRecord: pendingStart,
            ));
          }
          pendingStart = r;
        } else if (r.punchType == mobilePunchTravelArrive) {
          if (pendingStart != null) {
            out.add(_TravelTripRow(
              employeeId: entry.key,
              employeeName: pendingStart.employeeName.isNotEmpty
                  ? pendingStart.employeeName
                  : r.employeeName,
              employeeCode: codeById[entry.key] ?? '',
              start: pendingStart.punchTime,
              arrive: r.punchTime,
              startRecord: pendingStart,
              arriveRecord: r,
            ));
            pendingStart = null;
          } else {
            out.add(_TravelTripRow(
              employeeId: entry.key,
              employeeName: r.employeeName,
              employeeCode: codeById[entry.key] ?? '',
              start: r.punchTime,
              arriveRecord: r,
            ));
          }
        }
      }
      if (pendingStart != null) {
        out.add(_TravelTripRow(
          employeeId: entry.key,
          employeeName: pendingStart.employeeName,
          employeeCode: codeById[entry.key] ?? '',
          start: pendingStart.punchTime,
          startRecord: pendingStart,
        ));
      }
    }

    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  List<_TravelTripRow> get _filtered {
    var result = _trips;
    if (_teamView && _selectedBranchId != null) {
      final ids = _branchFilter.userIdsForBranch(_selectedBranchId);
      if (ids.isEmpty) return [];
      result = result
          .where((t) =>
              ids.contains(t.employeeId) ||
              ids.contains(t.employeeCode) ||
              _branchFilter.employees.any((e) {
                final eid = e['id']?.toString() ?? '';
                final code = e['employeeCode']?.toString() ?? '';
                final uid = e['applicationUserId']?.toString() ?? '';
                if (t.employeeId != eid &&
                    t.employeeId != code &&
                    t.employeeId != uid) {
                  return false;
                }
                return ids.contains(eid) ||
                    ids.contains(uid) ||
                    ids.contains(code);
              }))
          .toList();
    }
    if (_empSearch.trim().isNotEmpty) {
      final q = _empSearch.trim().toLowerCase();
      result = result
          .where((t) =>
              t.employeeName.toLowerCase().contains(q) ||
              t.employeeCode.toLowerCase().contains(q))
          .toList();
    }
    switch (_statusFilter) {
      case 'complete':
        result = result.where((t) => t.isComplete && t.hours > 0).toList();
        break;
      case 'incomplete':
        result = result.where((t) => !t.isComplete).toList();
        break;
    }
    if (!_teamView) {
      final user = context.read<AuthProvider>().user;
      final myIds = <String>{
        if (user != null) user.id,
        if (user?.employeeId != null && user!.employeeId!.isNotEmpty)
          user.employeeId!,
      };
      if (myIds.isNotEmpty) {
        result = result
            .where((t) =>
                myIds.contains(t.employeeId) ||
                myIds.contains(t.employeeCode))
            .toList();
      }
    }
    return result;
  }

  List<_EmpTravelAgg> get _byEmployee {
    final map = <String, _EmpTravelAgg>{};
    for (final t in _filtered) {
      final agg = map.putIfAbsent(
        t.employeeId,
        () => _EmpTravelAgg(
          employeeId: t.employeeId,
          employeeName: t.employeeName,
          employeeCode: t.employeeCode,
        ),
      );
      if (t.isComplete && t.hours > 0) {
        agg.hours += t.hours;
        agg.completeTrips++;
      } else if (!t.isComplete) {
        agg.incompleteTrips++;
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.hours.compareTo(a.hours));
    return list;
  }

  String _fmtHours(double h) {
    if (h <= 0) return '—';
    final hh = h.floor();
    final mm = ((h - hh) * 60).round();
    if (mm <= 0) return '${hh}h';
    return '${hh}h${mm}p';
  }

  List<ReportKpiItem> _buildKpis(List<_TravelTripRow> filtered) {
    final complete = filtered.where((t) => t.isComplete && t.hours > 0).toList();
    final hours = complete.fold<double>(0, (s, t) => s + t.hours);
    final incomplete = filtered.where((t) => !t.isComplete).length;
    final empCount = filtered.map((t) => t.employeeId).toSet().length;
    return [
      ReportKpiItem(
        label: 'Chuyến đủ cặp',
        value: '${complete.length}',
        icon: Icons.directions_car_outlined,
        color: _theme,
      ),
      ReportKpiItem(
        label: 'Tổng giờ',
        value: _fmtHours(hours),
        icon: Icons.schedule,
        color: _theme,
      ),
      ReportKpiItem(
        label: 'Thiếu chấm',
        value: '$incomplete',
        icon: Icons.warning_amber_outlined,
        color: const Color(0xFFD97706),
      ),
      ReportKpiItem(
        label: _teamView ? 'Nhân viên' : 'Lượt',
        value: _teamView ? '$empCount' : '${filtered.length}',
        icon: Icons.people_outline,
        color: _theme,
      ),
    ];
  }

  Future<void> _exportExcel() async {
    final rows = _viewTab == 0
        ? _filtered.asMap().entries.map((e) {
            final r = e.value;
            return <dynamic>[
              e.key + 1,
              _dateFmt.format(r.start),
              if (_teamView) r.employeeName,
              if (_teamView) r.employeeCode,
              _timeFmt.format(r.start),
              r.arrive != null ? _timeFmt.format(r.arrive!) : '',
              r.isComplete ? _fmtHours(r.hours) : '',
              r.statusLabel,
            ];
          }).toList()
        : _byEmployee.asMap().entries.map((e) {
            final r = e.value;
            return <dynamic>[
              e.key + 1,
              r.employeeName,
              r.employeeCode,
              r.completeTrips,
              _fmtHours(r.hours),
              r.incompleteTrips,
            ];
          }).toList();

    await ClientExcelExport.export(
      context: context,
      title: 'Báo cáo đi đường',
      sheetName: _viewTab == 0 ? 'Chi tiet' : 'Theo NV',
      filePrefix: 'DiDuong',
      headers: _viewTab == 0
          ? [
              'STT',
              'Ngày',
              if (_teamView) 'Nhân viên',
              if (_teamView) 'Mã NV',
              'Bắt đầu đi',
              'Đến điểm làm',
              'Giờ đi đường',
              'Trạng thái',
            ]
          : [
              'STT',
              'Nhân viên',
              'Mã NV',
              'Số chuyến',
              'Tổng giờ',
              'Thiếu chấm',
            ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: _teamView),
    );
  }

  Future<void> _exportPng() async {
    await ClientPngExport.capture(
      context: context,
      key: _pngKey,
      filePrefix: 'DiDuong',
    );
  }

  Future<void> _showSupplementDialog({
    String? employeeId,
    DateTime? day,
    TimeOfDay? start,
    TimeOfDay? arrive,
    String? existingStartRecordId,
    String? existingArriveRecordId,
  }) async {
    await _branchFilter.ensureEmployees(_api, branchId: _selectedBranchId);
    if (!mounted) return;
    final isSupplement = (existingStartRecordId != null &&
            existingStartRecordId.isNotEmpty) ||
        (existingArriveRecordId != null && existingArriveRecordId.isNotEmpty);
    final ok = await showManualTravelDialog(
      context,
      api: _api,
      employees: _branchFilter.employees,
      initialEmployeeId: employeeId,
      initialDay: day ?? DateTime(_to.year, _to.month, _to.day),
      initialStart: start,
      initialArrive: arrive,
      title: isSupplement ? 'Bổ sung cặp đi đường' : 'Thêm đi đường',
      existingStartRecordId: existingStartRecordId,
      existingArriveRecordId: existingArriveRecordId,
    );
    if (ok && mounted) _load();
  }

  Future<void> _editRecordTime(MobileAttendanceRecord record) async {
    final initial = record.punchTime.toLocal();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null || !mounted) return;
    final newTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    final res = await _api.updateMobileAttendanceRecord(
      recordId: record.id,
      punchTime: newTime,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Đã sửa giờ chấm đi đường'))),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(
              res['message']?.toString() ?? 'Không sửa được giờ')),
        ),
      );
    }
  }

  Future<void> _deleteTrip(_TravelTripRow r) async {
    final ids = <String>[
      if (r.startRecord != null) r.startRecord!.id,
      if (r.arriveRecord != null) r.arriveRecord!.id,
    ];
    if (ids.isEmpty) return;

    final timeLabel = r.arrive != null
        ? '${_timeFmt.format(r.start)} → ${_timeFmt.format(r.arrive!)}'
        : _timeFmt.format(r.start);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa cặp đi đường?')),
        content: Text(tr(
            'Xóa cả Bắt đầu đi và Đến điểm làm của ${r.employeeName} '
            '(${_dateFmt.format(r.start)} · $timeLabel).')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Huỷ'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa cả cặp')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    var failed = 0;
    String? lastError;
    for (final id in ids) {
      final res = await _api.deleteMobileAttendanceRecord(id);
      if (res['isSuccess'] != true) {
        failed++;
        lastError = res['message']?.toString();
      }
    }
    if (!mounted) return;
    if (failed == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Đã xóa cặp đi đường'))),
      );
      _load();
    } else if (failed < ids.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr(
                'Đã xóa một phần; còn lỗi: ${lastError ?? 'không rõ'}'))),
      );
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                tr(lastError ?? 'Không xóa được cặp đi đường'))),
      );
    }
  }

  Future<void> _showTripActions(_TravelTripRow r, {required bool canEdit}) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tr(r.employeeName),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr(
                  '${_dateFmt.format(r.start)} · ${_timeFmt.format(r.start)}${r.arrive != null ? ' → ${_timeFmt.format(r.arrive!)}' : ''} · ${r.statusLabel}')),
            ),
            if (canEdit && r.startRecord != null)
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: Text(tr('Sửa giờ bắt đầu đi')),
                onTap: () {
                  Navigator.pop(ctx);
                  _editRecordTime(r.startRecord!);
                },
              ),
            if (canEdit && r.arriveRecord != null)
              ListTile(
                leading: const Icon(Icons.edit_calendar_outlined),
                title: Text(tr('Sửa giờ đến điểm làm')),
                onTap: () {
                  Navigator.pop(ctx);
                  _editRecordTime(r.arriveRecord!);
                },
              ),
            if (canEdit && !r.isComplete)
              ListTile(
                leading: const Icon(Icons.add_road),
                title: Text(tr('Bổ sung cặp đi đường')),
                onTap: () {
                  Navigator.pop(ctx);
                  final hasStart = r.startRecord != null;
                  final hasArrive = r.arriveRecord != null;
                  final base = hasStart
                      ? r.start
                      : (r.arrive ?? r.start);
                  _showSupplementDialog(
                    employeeId: r.employeeId,
                    day: DateTime(base.year, base.month, base.day),
                    start: TimeOfDay.fromDateTime(
                        hasStart ? r.start : base.subtract(const Duration(hours: 1))),
                    arrive: TimeOfDay.fromDateTime(hasArrive
                        ? r.arrive!
                        : DateTime(base.year, base.month, base.day,
                            (base.hour + 1).clamp(0, 23), base.minute)),
                    existingStartRecordId: r.startRecord?.id,
                    existingArriveRecordId: r.arriveRecord?.id,
                  );
                },
              ),
            if (r.startRecord != null)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(tr('Chi tiết bắt đầu đi')),
                onTap: () {
                  Navigator.pop(ctx);
                  showMobileAttendanceRecordDetailSheet(
                    context,
                    record: r.startRecord!,
                    apiService: _api,
                    canManageRecord: canEdit,
                    canEditRecord: canEdit,
                    canDeleteRecord: canEdit,
                    onRecordChanged: _load,
                  );
                },
              ),
            if (r.arriveRecord != null)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(tr('Chi tiết đến điểm làm')),
                onTap: () {
                  Navigator.pop(ctx);
                  showMobileAttendanceRecordDetailSheet(
                    context,
                    record: r.arriveRecord!,
                    apiService: _api,
                    canManageRecord: canEdit,
                    canEditRecord: canEdit,
                    canDeleteRecord: canEdit,
                    onRecordChanged: _load,
                  );
                },
              ),
            if (canEdit &&
                (r.startRecord != null || r.arriveRecord != null))
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  tr(r.isComplete
                      ? 'Xóa cả cặp đi đường'
                      : 'Xóa phiếu đi đường'),
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteTrip(r);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final canExport = perm.canExport('TravelHoursReport') ||
        perm.canExport('AttendanceByShift') ||
        perm.canExport('MobileAttendance');
    // Nút thêm: quản lý xem báo cáo được phép bổ sung (không chỉ Edit Mobile).
    final canSupplement = _teamView &&
        (canEditMobileAttendanceRecord(perm) ||
            perm.canEdit('AttendanceByShift') ||
            perm.canEdit('TravelHoursReport') ||
            perm.canCreate('MobileAttendance') ||
            perm.canCreate('TravelHoursReport') ||
            perm.canApprove('MobileAttendanceApproval') ||
            perm.canApprove('AttendanceApproval') ||
            isManagerUserRole(auth.userRole));
    final filtered = _filtered;
    final isMobile = Responsive.isMobile(context);
    final useTable = Responsive.preferTableListLayout(context);

    return RegisterPageTopActions(
      actions: [
        if (canSupplement)
          HrmTopBarAction(
            icon: Icons.add_road,
            label: 'Thêm đi đường',
            onPressed: _showSupplementDialog,
            primary: true,
            iconOnly: false,
            showLabel: true,
          ),
        if (canExport)
          HrmTopBarAction(
            icon: Icons.image_outlined,
            label: 'Xuất PNG',
            onPressed: filtered.isEmpty ? null : _exportPng,
            pinOnMobile: false,
          ),
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
          floatingActionButton: canSupplement && isMobile
              ? FloatingActionButton.extended(
                  onPressed: _showSupplementDialog,
                  backgroundColor: _theme,
                  icon: const Icon(Icons.add_road),
                  label: Text(tr('Thêm đi đường')),
                )
              : null,
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
                        kpi: ReportKpiGrid(items: _buildKpis(filtered)),
                        betweenKpiAndFilter: [
                          if (canSupplement)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                  onPressed: _showSupplementDialog,
                                  icon: const Icon(Icons.add_road, size: 18),
                                  label: Text(tr('Thêm đi đường')),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _theme,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ),
                            ),
                        ],
                        filter: ReportFilterSection(
                          embedded: true,
                          showApplyButton: false,
                          from: _from,
                          to: _to,
                          datePreset: _datePreset,
                          onDateChanged: (f, t, p) {
                            setState(() {
                              _from = f;
                              _to = t;
                              _datePreset = p;
                              _page = 1;
                            });
                            _load();
                          },
                          statusFilter: _statusChips(),
                          statusSummary: _statusSummary(),
                          showTeamFilters: _teamView,
                          branchFilter: _teamView ? _branchFilter : null,
                          selectedBranchId: _selectedBranchId,
                          onBranchChanged: (v) async {
                            await _branchFilter.ensureEmployees(_api,
                                branchId: v);
                            if (mounted) {
                              setState(() {
                                _selectedBranchId = v;
                                _page = 1;
                              });
                            }
                          },
                          empSearch: _empSearch,
                          onEmpSearchChanged: (v) => setState(() {
                            _empSearch = v;
                            _page = 1;
                          }),
                          empSuggestions: _trips
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
                                    _statusFilter = 'all';
                                    _page = 1;
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
                            (
                              label: 'Theo nhân viên',
                              icon: Icons.people_outline
                            ),
                          ],
                          onChanged: (i) => setState(() {
                            _viewTab = i;
                            _page = 1;
                          }),
                        ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(
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
                          canSupplement: canSupplement,
                        ),
                      if (!isMobile) const SizedBox(height: 12),
                          ],
                        ),
                      ),
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

  String? _statusSummary() {
    switch (_statusFilter) {
      case 'complete':
        return 'Đủ cặp';
      case 'incomplete':
        return 'Thiếu chấm';
      default:
        return null;
    }
  }

  Widget _statusChips() {
    Widget chip(String value, String label) {
      final selected = _statusFilter == value;
      return FilterChip(
        selected: selected,
        label: Text(tr(label), style: const TextStyle(fontSize: 12)),
        onSelected: (_) => setState(() {
          _statusFilter = value;
          _page = 1;
        }),
        selectedColor: _theme.withValues(alpha: 0.15),
        checkmarkColor: _theme,
        side: BorderSide(
          color: selected ? _theme : const Color(0xFFD1D5DB),
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        chip('all', 'Tất cả'),
        chip('complete', 'Đủ cặp'),
        chip('incomplete', 'Thiếu chấm'),
      ],
    );
  }

  Widget _buildDetailSection(List<_TravelTripRow> filtered,
      {required bool useTable, bool canSupplement = false}) {
    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(tr('Không có dữ liệu đi đường trong kỳ'),
              style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
    }
    final start = (_page - 1) * _pageSize;
    final pageRows = filtered.skip(start).take(_pageSize).toList();

    if (!useTable) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          children: [
            if (canSupplement)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  tr('Thiếu cặp? Bấm «Thêm đi đường» phía trên để bổ sung Bắt đầu đi + Đến điểm làm.'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ...pageRows.map((r) => _buildTripCard(r, canEdit: canSupplement)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 40,
            dataRowMinHeight: 40,
            dataRowMaxHeight: 56,
            columns: [
              DataColumn(label: Text(tr('STT'))),
              DataColumn(label: Text(tr('Ngày'))),
              if (_teamView) DataColumn(label: Text(tr('Nhân viên'))),
              DataColumn(label: Text(tr('Bắt đầu'))),
              DataColumn(label: Text(tr('Đến điểm'))),
              DataColumn(label: Text(tr('Giờ'))),
              DataColumn(label: Text(tr('TT'))),
            ],
            rows: pageRows.asMap().entries.map((e) {
              final i = start + e.key + 1;
              final r = e.value;
              return DataRow(
                onSelectChanged: (_) =>
                    _showTripActions(r, canEdit: canSupplement),
                cells: [
                DataCell(Text('$i')),
                DataCell(Text(_dateFmt.format(r.start))),
                if (_teamView)
                  DataCell(SizedBox(
                    width: 150,
                    child: Text(
                      r.employeeCode.isEmpty
                          ? r.employeeName
                          : '${r.employeeName}\n${r.employeeCode}',
                      style: const TextStyle(fontSize: 12, height: 1.25),
                    ),
                  )),
                DataCell(Text(r.startRecord != null
                    ? _timeFmt.format(r.start)
                    : '—')),
                DataCell(Text(r.arrive != null
                    ? _timeFmt.format(r.arrive!)
                    : (r.arriveRecord != null
                        ? _timeFmt.format(r.arriveRecord!.punchTime)
                        : '—'))),
                DataCell(Text(_fmtHours(r.hours))),
                DataCell(Text(r.statusLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: r.isComplete
                          ? const Color(0xFF15803D)
                          : const Color(0xFFD97706),
                    ))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTripCard(_TravelTripRow r, {bool canEdit = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _showTripActions(r, canEdit: canEdit),
        leading: CircleAvatar(
          backgroundColor: (r.isComplete ? _theme : const Color(0xFFD97706))
              .withValues(alpha: 0.12),
          child: Icon(
            r.isComplete ? Icons.directions_car : Icons.warning_amber,
            color: r.isComplete ? _theme : const Color(0xFFD97706),
            size: 20,
          ),
        ),
        title: Text(tr(_teamView ? r.employeeName : _dateFmt.format(r.start)),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(
          tr([
            if (_teamView) _dateFmt.format(r.start),
            '${_timeFmt.format(r.start)}${r.arrive != null ? ' → ${_timeFmt.format(r.arrive!)}' : ''}',
            r.statusLabel,
            if (canEdit) 'Chạm để sửa / xóa',
          ].join(' · ')),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        trailing: Text(tr(_fmtHours(r.hours)),
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: _theme, fontSize: 14)),
      ),
    );
  }

  Widget _buildEmployeeSection(bool asCards) {
    final list = _byEmployee;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(tr('Không có dữ liệu'),
              style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
    }
    if (asCards) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          children: list
              .map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(tr(r.employeeName),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(tr(
                          'Mã ${r.employeeCode.isEmpty ? '—' : r.employeeCode} · ${r.completeTrips} chuyến · thiếu ${r.incompleteTrips}')),
                      trailing: Text(tr(_fmtHours(r.hours)),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: _theme)),
                    ),
                  ))
              .toList(),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: Container(
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
              DataColumn(label: Text(tr('STT'))),
              DataColumn(label: Text(tr('Nhân viên'))),
              DataColumn(label: Text(tr('Mã'))),
              DataColumn(label: Text(tr('Chuyến'))),
              DataColumn(label: Text(tr('Giờ'))),
              DataColumn(label: Text(tr('Thiếu'))),
            ],
            rows: list.asMap().entries.map((e) {
              final r = e.value;
              return DataRow(cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(r.employeeName)),
                DataCell(Text(r.employeeCode)),
                DataCell(Text('${r.completeTrips}')),
                DataCell(Text(_fmtHours(r.hours))),
                DataCell(Text('${r.incompleteTrips}')),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }
}
