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
import '../widgets/app_responsive_dialog.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
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
  /// all | fined | unfined
  String _penaltyFilter = 'all';
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
  List<Map<String, dynamic>> _penaltyTickets = [];
  Map<String, dynamic> _penaltySettings = {};
  /// Mã NV / PIN → GUID nhân viên (tạo phiếu phạt).
  final Map<String, String> _empCodeToGuid = {};
  /// Giải trình nháp khi chưa có phiếu: `code|yyyy-MM-dd|Late|EarlyLeave`
  final Map<String, String> _draftExplanations = {};
  bool _actionBusy = false;
  final _pngKey = GlobalKey();

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
        _api
            .getPenaltyTickets(
              fromDate: _from,
              toDate: _to,
              pageSize: 2000,
            )
            .catchError((_) => <String, dynamic>{}),
        _api.getPenaltySettings().catchError((_) => <String, dynamic>{}),
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

      final ticketRaw = p2[4] as Map<String, dynamic>;
      final tickets = <Map<String, dynamic>>[];
      final ticketData = ticketRaw['data'];
      final ticketItems = ticketData is Map
          ? (ticketData['items'] ?? ticketData['data'])
          : (ticketRaw['items'] ?? ticketData);
      if (ticketItems is List) {
        for (final t in ticketItems) {
          if (t is Map) tickets.add(Map<String, dynamic>.from(t));
        }
      }

      final settingsRaw = p2[5] as Map<String, dynamic>;
      final settings = settingsRaw['data'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(settingsRaw['data'] as Map)
          : (settingsRaw.isNotEmpty
              ? Map<String, dynamic>.from(settingsRaw)
              : <String, dynamic>{});

      final codeToGuid = <String, String>{};
      for (final e in _branchFilter.employees) {
        final id = e['id']?.toString() ?? '';
        final code = e['employeeCode']?.toString() ??
            e['code']?.toString() ??
            e['pin']?.toString() ??
            '';
        if (id.isEmpty) continue;
        if (code.isNotEmpty) codeToGuid[code] = id;
        codeToGuid[id] = id;
      }
      for (final p in profiles) {
        final id = p['employeeId']?.toString() ??
            p['id']?.toString() ??
            '';
        final code = p['employeeCode']?.toString() ??
            p['code']?.toString() ??
            '';
        if (id.isEmpty) continue;
        if (code.isNotEmpty) codeToGuid[code] = id;
        codeToGuid[id] = id;
      }

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
        _penaltyTickets = tickets;
        _penaltySettings = settings;
        _empCodeToGuid
          ..clear()
          ..addAll(codeToGuid);
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

    if (_penaltyFilter == 'fined') {
      list = list.where(_isFullyPenalized).toList();
    } else if (_penaltyFilter == 'unfined') {
      list = list.where((e) => !_isFullyPenalized(e)).toList();
    }

    list = List.of(list)
      ..sort((a, b) {
        final d = b.date.compareTo(a.date);
        if (d != 0) return d;
        return a.employeeName.compareTo(b.employeeName);
      });
    return list;
  }

  String _empKey(DailyShiftLateEntry e) =>
      e.employeeCode.isNotEmpty ? e.employeeCode : e.employeeId;

  String _dayStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _draftKey(DailyShiftLateEntry e, String type) =>
      '${_empKey(e)}|${_dayStr(e.date)}|$type';

  bool _isCancelledStatus(String? st) {
    final s = (st ?? '').toLowerCase();
    return s == 'cancelled' || s == '2';
  }

  bool _isActiveTicket(Map<String, dynamic> t) =>
      !_isCancelledStatus(t['status']?.toString());

  bool _ticketMatchesEmp(Map<String, dynamic> t, DailyShiftLateEntry e) {
    final tid = t['employeeId']?.toString() ?? '';
    final tcode = t['employeeCode']?.toString() ?? '';
    final code = e.employeeCode;
    final id = e.employeeId;
    final guid = _resolveEmployeeGuid(e);
    if (tcode.isNotEmpty &&
        (tcode == code || tcode == id)) {
      return true;
    }
    if (tid.isEmpty) return false;
    return tid == code ||
        tid == id ||
        tid == guid ||
        _empCodeToGuid[code] == tid ||
        _empCodeToGuid[id] == tid;
  }

  bool _ticketMatchesDay(Map<String, dynamic> t, DateTime day) {
    final vd = t['violationDate'];
    DateTime? d;
    if (vd is DateTime) {
      d = vd;
    } else if (vd != null) {
      d = DateTime.tryParse(vd.toString());
    }
    if (d == null) return false;
    return d.year == day.year && d.month == day.month && d.day == day.day;
  }

  String _normalizeType(String? type) {
    final t = (type ?? '').toLowerCase();
    if (t == 'late' || t == '1') return 'Late';
    if (t == 'earlyleave' || t == 'early' || t == '2') return 'EarlyLeave';
    return type ?? '';
  }

  List<Map<String, dynamic>> _ticketsFor(
    DailyShiftLateEntry e, {
    String? type,
    bool activeOnly = false,
  }) {
    return _penaltyTickets.where((t) {
      if (!_ticketMatchesEmp(t, e)) return false;
      if (!_ticketMatchesDay(t, e.date)) return false;
      if (activeOnly && !_isActiveTicket(t)) return false;
      if (type != null) {
        if (_normalizeType(t['type']?.toString()) != type) return false;
      } else {
        final nt = _normalizeType(t['type']?.toString());
        final okLate = e.lateMinutes > 0 && nt == 'Late';
        final okEarly = e.earlyMinutes > 0 && nt == 'EarlyLeave';
        if (!okLate && !okEarly) return false;
      }
      return true;
    }).toList();
  }

  List<String> _neededTypes(DailyShiftLateEntry e) {
    final types = <String>[];
    if (e.lateMinutes > 0) types.add('Late');
    if (e.earlyMinutes > 0) types.add('EarlyLeave');
    return types;
  }

  bool _hasActiveType(DailyShiftLateEntry e, String type) =>
      _ticketsFor(e, type: type, activeOnly: true).isNotEmpty;

  bool _isFullyPenalized(DailyShiftLateEntry e) {
    final needed = _neededTypes(e);
    if (needed.isEmpty) return false;
    return needed.every((t) => _hasActiveType(e, t));
  }

  bool _hasAnyActivePenalty(DailyShiftLateEntry e) =>
      _neededTypes(e).any((t) => _hasActiveType(e, t));

  String _penaltyLabel(DailyShiftLateEntry e) {
    final needed = _neededTypes(e);
    if (needed.isEmpty) return '—';
    final done = needed.where((t) => _hasActiveType(e, t)).length;
    if (done == 0) return 'Chưa phạt';
    if (done == needed.length) return 'Đã phạt';
    return 'Một phần';
  }

  Color _penaltyLabelColor(DailyShiftLateEntry e) {
    final label = _penaltyLabel(e);
    if (label == 'Đã phạt') return const Color(0xFF047857);
    if (label == 'Một phần') return const Color(0xFFB45309);
    return const Color(0xFF6B7280);
  }

  bool _isAutoDescription(String? desc) {
    if (desc == null || desc.trim().isEmpty) return true;
    final d = desc.trim().toLowerCase();
    return d.startsWith('đi trễ') ||
        d.startsWith('về sớm') ||
        d.startsWith('di tre') ||
        d.startsWith('ve som');
  }

  String _explanationText(DailyShiftLateEntry e) {
    final parts = <String>[];
    for (final type in _neededTypes(e)) {
      final draft = _draftExplanations[_draftKey(e, type)];
      if (draft != null && draft.trim().isNotEmpty) {
        parts.add(draft.trim());
        continue;
      }
      final tickets = _ticketsFor(e, type: type);
      String? found;
      for (final t in tickets) {
        final cancel = t['cancellationReason']?.toString().trim();
        if (cancel != null && cancel.isNotEmpty) {
          found = cancel;
          break;
        }
      }
      if (found == null) {
        for (final t in tickets) {
          final desc = t['description']?.toString().trim();
          if (desc != null &&
              desc.isNotEmpty &&
              !_isAutoDescription(desc)) {
            found = desc;
            break;
          }
        }
      }
      if (found != null && found.isNotEmpty) parts.add(found);
    }
    if (parts.isEmpty) return '';
    return parts.toSet().join(' · ');
  }

  String? _resolveEmployeeGuid(DailyShiftLateEntry e) {
    for (final key in [e.employeeId, e.employeeCode]) {
      if (key.isEmpty) continue;
      final g = _empCodeToGuid[key];
      if (g != null && g.isNotEmpty) return g;
      if (key.contains('-') && key.length > 30) return key; // GUID-like
    }
    return null;
  }

  double _toDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  int _toInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  double _amountFor(String type, int minutes) {
    if (minutes <= 0) return 0;
    final isLate = type == 'Late';
    final m1 = _toInt(
        _penaltySettings[isLate ? 'lateMinutes1' : 'earlyMinutes1'], 15);
    final m2 = _toInt(
        _penaltySettings[isLate ? 'lateMinutes2' : 'earlyMinutes2'], 30);
    final m3 = _toInt(
        _penaltySettings[isLate ? 'lateMinutes3' : 'earlyMinutes3'], 60);
    final p1 = _toDouble(
        _penaltySettings[isLate ? 'latePenalty1' : 'earlyPenalty1']);
    final p2 = _toDouble(
        _penaltySettings[isLate ? 'latePenalty2' : 'earlyPenalty2']);
    final p3 = _toDouble(
        _penaltySettings[isLate ? 'latePenalty3' : 'earlyPenalty3']);
    if (minutes >= m3 && p3 > 0) return p3;
    if (minutes >= m2 && p2 > 0) return p2;
    if (minutes >= m1 && p1 > 0) return p1;
    // Legacy flat
    final flat = _toDouble(_penaltySettings[
        isLate ? 'lateDeduction' : 'earlyLeaveDeduction']);
    return flat > 0 ? flat : 0;
  }

  String _money(double v) {
    final n = NumberFormat('#,###', 'vi_VN').format(v.round());
    return '$nđ';
  }

  Future<void> _applyPenalty(DailyShiftLateEntry e) async {
    if (_actionBusy) return;
    final canApprove =
        context.read<PermissionProvider>().canApprove('PenaltyTickets');
    final needed = _neededTypes(e)
        .where((t) => !_hasActiveType(e, t))
        .toList();
    if (needed.isEmpty) {
      appNotification.showWarning(
          title: 'Đã phạt', message: tr('Các lỗi của dòng này đã có phiếu phạt'));
      return;
    }
    final guid = _resolveEmployeeGuid(e);
    if (guid == null || guid.isEmpty) {
      appNotification.showWarning(
          title: 'Không tạo được phiếu',
          message: tr('Không xác định được hồ sơ nhân viên'));
      return;
    }

    final lines = <String>[];
    final payloads = <Map<String, dynamic>>[];
    for (final type in needed) {
      final mins = type == 'Late' ? e.lateMinutes : e.earlyMinutes;
      final amount = _amountFor(type, mins);
      if (amount <= 0) {
        appNotification.showWarning(
            title: 'Chưa cấu hình mức phạt',
            message: tr(
                'Vào Thiết lập phạt để cấu hình bậc phạt đi trễ / về sớm'));
        return;
      }
      final label = type == 'Late' ? 'Đi trễ' : 'Về sớm';
      final draft = _draftExplanations[_draftKey(e, type)]?.trim();
      final desc = (draft != null && draft.isNotEmpty)
          ? draft
          : '$label $mins phút — ${e.employeeName}';
      lines.add('$label $mins phút → ${_money(amount)}');
      payloads.add({
        'employeeId': guid,
        'type': type,
        'amount': amount,
        'violationDate': e.date.toIso8601String(),
        'minutesLateOrEarly': mins,
        'description': desc,
      });
    }

    final explanationCtrl = TextEditingController(
      text: _explanationText(e),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Tạo phiếu phạt'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('${e.employeeName} · ${_dateFmt.format(e.date)}'),
                style: vietnameseTextStyle(
                    const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 8),
            ...lines.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(tr(l), style: vietnameseTextStyle()),
                )),
            const SizedBox(height: 12),
            TextField(
              controller: explanationCtrl,
              decoration: InputDecoration(
                labelText: tr('Giải trình / ghi chú'),
                hintText: tr('Lý do đi trễ / về sớm (nếu có)'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy'),
                style: const TextStyle(color: Color(0xFF71717A))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _theme),
            child: Text(tr('Phạt')),
          ),
        ],
      ),
    );
    final note = explanationCtrl.text.trim();
    explanationCtrl.dispose();
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      for (final p in payloads) {
        if (note.isNotEmpty) p['description'] = note;
        final res = await _api.createPenaltyTicket(p);
        if (res['isSuccess'] != true) {
          appNotification.showError(
              title: 'Lỗi', message: res['message'] ?? 'Không tạo được phiếu');
          return;
        }
        final id = res['data']?['id']?.toString();
        if (id != null && canApprove) {
          await _api.approvePenaltyTicket(id);
        }
        final type = p['type']?.toString() ?? '';
        _draftExplanations.remove(_draftKey(e, type));
      }
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã tạo phiếu phạt'));
      await _reloadTicketsOnly();
    } catch (err) {
      appNotification.showError(title: 'Lỗi', message: '$err');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _cancelPenalty(DailyShiftLateEntry e) async {
    if (_actionBusy) return;
    final active = <Map<String, dynamic>>[];
    for (final type in _neededTypes(e)) {
      active.addAll(_ticketsFor(e, type: type, activeOnly: true));
    }
    if (active.isEmpty) {
      appNotification.showWarning(
          title: 'Chưa phạt', message: tr('Chưa có phiếu phạt để hủy'));
      return;
    }

    final reasonCtrl = TextEditingController(text: _explanationText(e));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Hủy phiếu phạt'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Hủy ${active.length} phiếu · ${e.employeeName} · ${_dateFmt.format(e.date)}'),
              style: vietnameseTextStyle(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                labelText: tr('Giải trình / lý do hủy'),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Không'),
                style: const TextStyle(color: Color(0xFF71717A))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Hủy phạt')),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true) return;

    setState(() => _actionBusy = true);
    try {
      for (final t in active) {
        final id = t['id']?.toString();
        if (id == null) continue;
        final res =
            await _api.cancelPenaltyTicket(id, reason: reason);
        if (res['isSuccess'] != true) {
          appNotification.showError(
              title: 'Lỗi', message: res['message'] ?? 'Không hủy được');
          return;
        }
      }
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã hủy phiếu phạt'));
      await _reloadTicketsOnly();
    } catch (err) {
      appNotification.showError(title: 'Lỗi', message: '$err');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _editExplanation(DailyShiftLateEntry e) async {
    final ctrl = TextEditingController(text: _explanationText(e));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Giải trình'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: tr('Giải trình của nhân sự'),
            hintText: tr('Lý do đi trễ / về sớm'),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _theme),
            child: Text(tr('Lưu')),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return;

    setState(() {
      for (final type in _neededTypes(e)) {
        if (text.isEmpty) {
          _draftExplanations.remove(_draftKey(e, type));
        } else {
          _draftExplanations[_draftKey(e, type)] = text;
        }
      }
    });

    // Đồng bộ lên phiếu Pending nếu có
    final pending = _ticketsFor(e, activeOnly: true)
        .where((t) {
          final st = (t['status']?.toString() ?? '').toLowerCase();
          return st == 'pending' || st == '0';
        })
        .toList();
    for (final t in pending) {
      final id = t['id']?.toString();
      if (id == null) continue;
      await _api.updatePenaltyTicket(id, {
        'description': text.isEmpty
            ? (t['description'] ?? '')
            : text,
      });
    }
    if (pending.isNotEmpty) await _reloadTicketsOnly();
  }

  Future<void> _reloadTicketsOnly() async {
    try {
      final ticketRaw = await _api.getPenaltyTickets(
        fromDate: _from,
        toDate: _to,
        pageSize: 2000,
      );
      final tickets = <Map<String, dynamic>>[];
      final ticketData = ticketRaw['data'];
      final ticketItems = ticketData is Map
          ? (ticketData['items'] ?? ticketData['data'])
          : (ticketRaw['items'] ?? ticketData);
      if (ticketItems is List) {
        for (final t in ticketItems) {
          if (t is Map) tickets.add(Map<String, dynamic>.from(t));
        }
      }
      if (mounted) setState(() => _penaltyTickets = tickets);
    } catch (_) {}
  }

  /// Tổng số lần vi phạm (trễ hoặc sớm) của NV trong kỳ đã lọc.
  Map<String, int> get _violationCountByEmp {
    final map = <String, int>{};
    for (final e in _filteredEntries) {
      final k = _empKey(e);
      map[k] = (map[k] ?? 0) + 1;
    }
    return map;
  }

  /// Thứ tự lần vi phạm theo thời gian tăng dần trong kỳ (1 = lần đầu, ≥2 = tái phạm).
  Map<DailyShiftLateEntry, int> get _occurrenceIndexByEntry {
    final chronological = List<DailyShiftLateEntry>.from(_filteredEntries)
      ..sort((a, b) {
        final d = a.date.compareTo(b.date);
        if (d != 0) return d;
        final ai = a.checkIn ?? a.checkOut ?? a.date;
        final bi = b.checkIn ?? b.checkOut ?? b.date;
        return ai.compareTo(bi);
      });
    final counters = <String, int>{};
    final out = <DailyShiftLateEntry, int>{};
    for (final e in chronological) {
      final k = _empKey(e);
      final n = (counters[k] ?? 0) + 1;
      counters[k] = n;
      out[e] = n;
    }
    return out;
  }

  List<_EmpAgg> get _byEmployee {
    final map = <String, _EmpAgg>{};
    for (final e in _filteredEntries) {
      final key = _empKey(e);
      final agg = map.putIfAbsent(
        key,
        () => _EmpAgg(
          code: e.employeeCode,
          name: e.employeeName,
        ),
      );
      agg.totalEvents++;
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
        final t = b.totalEvents.compareTo(a.totalEvents);
        if (t != 0) return t;
        final m = (b.lateMinutes + b.earlyMinutes)
            .compareTo(a.lateMinutes + a.earlyMinutes);
        if (m != 0) return m;
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
    final counts = _violationCountByEmp;
    final empCount = counts.length;
    final repeatEmp = counts.values.where((c) => c >= 2).length;
    final avgLate =
        lateEvents > 0 ? (lateMin / lateEvents).round() : 0;
    return [
      ReportKpiItem(
        label: 'Lần đi trễ',
        value: '$lateEvents',
        icon: Icons.timer_off_outlined,
        color: _lateColor,
      ),
      ReportKpiItem(
        label: 'TB phút/lần trễ',
        value: lateEvents > 0 ? '${avgLate}p' : '—',
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
      if (_teamView)
        ReportKpiItem(
          label: 'NV tái phạm',
          value: '$repeatEmp',
          icon: Icons.replay,
          color: const Color(0xFFB45309),
        ),
    ];
  }

  Widget _analysisBanner(List<DailyShiftLateEntry> rows) {
    if (rows.isEmpty || !_teamView) return const SizedBox.shrink();
    final counts = _violationCountByEmp;
    final repeatEmp = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = _byEmployee.take(3).toList();
    if (repeatEmp.isEmpty && top.isEmpty) return const SizedBox.shrink();

    String nameOf(String key) {
      final hit = rows.where((e) => _empKey(e) == key);
      return hit.isEmpty ? key : hit.first.employeeName;
    }

    final tips = <String>[];
    if (repeatEmp.isNotEmpty) {
      final topRepeat = repeatEmp.take(2).map((e) {
        final n = nameOf(e.key);
        return '$n (${e.value} lần)';
      }).join(', ');
      tips.add('Tái phạm nhiều: $topRepeat');
    }
    if (top.isNotEmpty) {
      tips.add(
          'Cần chú ý: ${top.map((e) => '${e.name} (${e.totalEvents} lần)').join(', ')}');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.analytics_outlined,
                size: 18, color: Color(0xFFB45309)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(tips.join(' · ')),
                style: vietnameseTextStyle(const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Color(0xFF92400E),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportExcel() async {
    final occ = _occurrenceIndexByEntry;
    final totals = _violationCountByEmp;
    final rows = _viewTab == 0
        ? _filteredEntries
            .asMap()
            .entries
            .map((e) {
              final r = e.value;
              final key = _empKey(r);
              final n = occ[r] ?? 1;
              final total = totals[key] ?? 1;
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
                '$n/$total',
                total >= 2 ? 'Có' : '',
                _penaltyLabel(r),
                _explanationText(r),
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
                r.totalEvents,
                r.lateCount,
                r.lateMinutes,
                r.earlyCount,
                r.earlyMinutes,
                r.totalEvents >= 2 ? r.totalEvents - 1 : 0,
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
              'Lần trong kỳ',
              'Tái phạm',
              'Đã phạt',
              'Giải trình',
            ]
          : [
              'STT',
              'Nhân viên',
              'Mã NV',
              'Tổng lần',
              'Số lần trễ',
              'Tổng phút trễ',
              'Số lần về sớm',
              'Tổng phút sớm',
              'Số lần tái phạm',
            ],
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: _teamView),
    );
  }

  Future<void> _exportPng() async {
    await ClientPngExport.capture(
      context: context,
      key: _pngKey,
      filePrefix: 'DiTreVeSom',
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
                          statusFilter: _kindChips(),
                          statusSummary: _kindSummary(),
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
                          empSuggestions: _entries
                              .map((e) => e.employeeName)
                              .where((n) => n.isNotEmpty)
                              .toSet()
                              .toList()
                            ..sort(),
                          onApply: () {},
                          onClearFilters: _teamView
                              ? () => setState(() {
                                    _empSearch = '';
                                    _selectedBranchId = null;
                                    _kindFilter = 'all';
                                    _penaltyFilter = 'all';
                                    _minMinutes = 1;
                                    _page = 1;
                                  })
                              : null,
                        ),
                      ),
                      reportLoadErrorBanner(_loadError),
                      if (!_loading) _analysisBanner(filtered),
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

  String? _kindSummary() {
    final parts = <String>[];
    switch (_kindFilter) {
      case 'late':
        parts.add('Chỉ đi trễ');
        break;
      case 'early':
        parts.add('Chỉ về sớm');
        break;
    }
    switch (_penaltyFilter) {
      case 'fined':
        parts.add('Đã phạt');
        break;
      case 'unfined':
        parts.add('Chưa phạt');
        break;
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _kindChips() {
    Widget chip(String value, String label, {required bool selected, required VoidCallback onTap}) {
      return FilterChip(
        label: Text(tr(label),
            style: vietnameseTextStyle(TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? _theme : const Color(0xFF374151),
            ))),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: _theme.withValues(alpha: 0.12),
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
        chip('all', 'Trễ & sớm',
            selected: _kindFilter == 'all',
            onTap: () => setState(() {
                  _kindFilter = 'all';
                  _page = 1;
                })),
        chip('late', 'Chỉ đi trễ',
            selected: _kindFilter == 'late',
            onTap: () => setState(() {
                  _kindFilter = 'late';
                  _page = 1;
                })),
        chip('early', 'Chỉ về sớm',
            selected: _kindFilter == 'early',
            onTap: () => setState(() {
                  _kindFilter = 'early';
                  _page = 1;
                })),
        chip('pen_all', 'Tất cả phạt',
            selected: _penaltyFilter == 'all',
            onTap: () => setState(() {
                  _penaltyFilter = 'all';
                  _page = 1;
                })),
        chip('fined', 'Đã phạt',
            selected: _penaltyFilter == 'fined',
            onTap: () => setState(() {
                  _penaltyFilter = 'fined';
                  _page = 1;
                })),
        chip('unfined', 'Chưa phạt',
            selected: _penaltyFilter == 'unfined',
            onTap: () => setState(() {
                  _penaltyFilter = 'unfined';
                  _page = 1;
                })),
      ],
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
    final occ = _occurrenceIndexByEntry;
    final totals = _violationCountByEmp;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canFine = perm.canCreate('PenaltyTickets');
    final canCancel = perm.canApprove('PenaltyTickets');
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
      if (_teamView) const DataColumn(label: Text('Tái phạm')),
      const DataColumn(label: Text('Đã phạt')),
      const DataColumn(label: Text('Giải trình')),
      if (_teamView && (canFine || canCancel))
        const DataColumn(label: Text('Thao tác')),
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
              dataRowMinHeight: 44,
              dataRowMaxHeight: 64,
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
                final key = _empKey(r);
                final n = occ[r] ?? 1;
                final total = totals[key] ?? 1;
                final isRepeat = n >= 2;
                final explain = _explanationText(r);
                final needFine = !_isFullyPenalized(r);
                final canCancelRow = _hasAnyActivePenalty(r);
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
                  if (_teamView)
                    DataCell(Text(
                      '$n/$total',
                      style: TextStyle(
                        color: isRepeat
                            ? const Color(0xFFB45309)
                            : const Color(0xFF6B7280),
                        fontWeight:
                            isRepeat ? FontWeight.w700 : FontWeight.w500,
                      ),
                    )),
                  DataCell(Text(
                    tr(_penaltyLabel(r)),
                    style: TextStyle(
                      color: _penaltyLabelColor(r),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  )),
                  DataCell(
                    InkWell(
                      onTap: () => _editExplanation(r),
                      child: SizedBox(
                        width: 160,
                        child: Text(
                          explain.isEmpty ? tr('Nhập giải trình…') : explain,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: vietnameseTextStyle(TextStyle(
                            fontSize: 12,
                            color: explain.isEmpty
                                ? const Color(0xFF9CA3AF)
                                : const Color(0xFF374151),
                            fontStyle: explain.isEmpty
                                ? FontStyle.italic
                                : FontStyle.normal,
                          )),
                        ),
                      ),
                    ),
                  ),
                  if (_teamView && (canFine || canCancel))
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canFine && needFine)
                          TextButton(
                            onPressed:
                                _actionBusy ? null : () => _applyPenalty(r),
                            style: TextButton.styleFrom(
                              foregroundColor: _theme,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(tr('Phạt'),
                                style: vietnameseTextStyle(const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))),
                          ),
                        if (canCancel && canCancelRow)
                          TextButton(
                            onPressed:
                                _actionBusy ? null : () => _cancelPenalty(r),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(tr('Hủy phạt'),
                                style: vietnameseTextStyle(const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))),
                          ),
                      ],
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
    final occ = _occurrenceIndexByEntry;
    final totals = _violationCountByEmp;
    final n = occ[r] ?? 1;
    final total = totals[_empKey(r)] ?? 1;
    final explain = _explanationText(r);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canFine = perm.canCreate('PenaltyTickets');
    final canCancel = perm.canApprove('PenaltyTickets');
    final needFine = !_isFullyPenalized(r);
    final canCancelRow = _hasAnyActivePenalty(r);
    final parts = <String>[
      if (r.shiftName.isNotEmpty) r.shiftName,
      if (r.checkIn != null) 'Vào ${_timeFmt.format(r.checkIn!)}',
      if (r.checkOut != null) 'Ra ${_timeFmt.format(r.checkOut!)}',
      if (_teamView) 'Lần $n/$total trong kỳ',
      _penaltyLabel(r),
      if (explain.isNotEmpty) 'GT: $explain',
    ];
    final lateEarly = r.lateMinutes > 0 && r.earlyMinutes > 0
        ? 'Trễ ${r.lateMinutes}p · Sớm ${r.earlyMinutes}p'
        : (r.lateMinutes > 0
            ? 'Đi trễ ${r.lateMinutes} phút'
            : 'Về sớm ${r.earlyMinutes} phút');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportTimelineCard(
          title: _teamView
              ? r.employeeName
              : (r.shiftName.isEmpty ? 'Ca' : r.shiftName),
          trailing: _dateFmt.format(r.date),
          subtitle: [
            if (_teamView && r.employeeCode.isNotEmpty) 'Mã ${r.employeeCode}',
            ...parts,
          ].where((s) => s.isNotEmpty).join(' · '),
          accentColor: r.lateMinutes > 0 ? _lateColor : _earlyColor,
          statusLabel: _teamView && n >= 2
              ? '$lateEarly · Tái phạm'
              : lateEarly,
          statusColor: n >= 2
              ? const Color(0xFFB45309)
              : (r.lateMinutes > 0 ? _lateColor : _earlyColor),
          icon: r.lateMinutes > 0 ? Icons.timer_off : Icons.logout,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: () => _editExplanation(r),
                icon: const Icon(Icons.edit_note, size: 16),
                label: Text(tr('Giải trình'),
                    style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
              ),
              if (_teamView && canFine && needFine)
                TextButton.icon(
                  onPressed: _actionBusy ? null : () => _applyPenalty(r),
                  icon: const Icon(Icons.gavel, size: 16),
                  label: Text(tr('Phạt'),
                      style: vietnameseTextStyle(const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700))),
                ),
              if (_teamView && canCancel && canCancelRow)
                TextButton.icon(
                  onPressed: _actionBusy ? null : () => _cancelPenalty(r),
                  icon:
                      Icon(Icons.undo, size: 16, color: Colors.red.shade700),
                  label: Text(tr('Hủy phạt'),
                      style: vietnameseTextStyle(TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade700))),
                ),
            ],
          ),
        ),
      ],
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
              'Tổng lần',
              'Tái phạm',
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
              final repeats = r.totalEvents >= 2 ? r.totalEvents - 1 : 0;
              return DataRow(cells: [
                DataCell(Text('${i + 1}')),
                DataCell(SizedBox(
                    width: 160,
                    child: Text(r.name, overflow: TextOverflow.ellipsis))),
                DataCell(Text(r.code)),
                DataCell(Text('${r.totalEvents}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text(
                  repeats > 0 ? '$repeats' : '—',
                  style: TextStyle(
                    color: repeats > 0 ? const Color(0xFFB45309) : null,
                    fontWeight:
                        repeats > 0 ? FontWeight.w700 : FontWeight.normal,
                  ),
                )),
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
          .map((e) {
            final repeats = e.totalEvents >= 2 ? e.totalEvents - 1 : 0;
            return ReportEmployeeSummaryCard(
              name: e.name,
              meta: [
                if (e.code.isNotEmpty) 'Mã ${e.code}',
                '${e.totalEvents} lần trong kỳ',
                if (repeats > 0) 'Tái phạm $repeats',
              ].join(' · '),
              primaryValue: e.lateMinutes > 0
                  ? 'Trễ ${e.lateMinutes}p (${e.lateCount} lần)'
                  : '—',
              secondaryValue: e.earlyMinutes > 0
                  ? 'Sớm ${e.earlyMinutes}p (${e.earlyCount} lần)'
                  : 'Không về sớm',
              accentColor: repeats > 0 ? const Color(0xFFB45309) : _theme,
              onTap: () => setState(() {
                _viewTab = 0;
                _empSearch = e.name;
                _page = 1;
              }),
            );
          })
          .toList(),
    );
  }
}

class _EmpAgg {
  final String code;
  final String name;
  int totalEvents = 0;
  int lateCount = 0;
  int lateMinutes = 0;
  int earlyCount = 0;
  int earlyMinutes = 0;

  _EmpAgg({required this.code, required this.name});
}
