import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/attendance_leave_lookup.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/attendance_report_helpers.dart';
import '../utils/report_access_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/salary_profile_load_utils.dart';
import '../utils/shift_records_calculator.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/reports/hrm_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màu chủ đạo kiểu KiotViet (xanh dương #0070F4 + xanh lá #00B63E).
const _theme = PosTheme.kiotBlue;

enum _DayStatus {
  present,
  halfDay,
  missingPunch,
  unpaidAbsent,
  approvedLeave,
  pendingLeave,
  weeklyOff,
  holiday,
  future,
}

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  final ApiService _api = ApiService();
  final _fmtDate = DateFormat('yyyy-MM-dd');
  final _fmtDay = DateFormat('dd');
  final _fmtWeekday = DateFormat('E', 'vi');
  final _fmtTime = DateFormat('HH:mm');
  final _branchFilter = ReportBranchFilter();

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  String _empSearch = '';
  String? _selectedBranchId;
  String? _selectedDepartmentId;
  String? _selectedEmployeeId;
  int _page = 1;
  static const _calEmpPageSize = 25;
  /// Sort employees in calendar: 0=name, 1=code
  int _empSortColumn = 0;
  bool _empSortAscending = true;

  bool _loading = false;
  bool _showOverviewPanel = true;
  String? _loadError;

  List<Map<String, dynamic>> _employees = [];
  /// key: `$guid|$dateKey` (fallback code)
  final Map<String, Map<String, dynamic>> _dayCells = {};
  /// Giờ chuẩn store mặc định / 1 công.
  double _stdWorkHours = 8;
  /// % đủ 1 công (thiết lập hệ thống).
  double _minWorkDayPercent = 80;
  final _pngKey = GlobalKey();

  bool get _teamView {
    final role = Provider.of<AuthProvider>(context, listen: false).userRole;
    return isTeamReportView(role: role);
  }

  List<DateTime> get _daysInRange {
    final days = <DateTime>[];
    var d = DateTime(_from.year, _from.month, _from.day);
    final end = DateTime(_to.year, _to.month, _to.day);
    while (!d.isAfter(end)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }
    return days;
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    final q = _empSearch.trim().toLowerCase();
    return _employees.where((e) {
      if (_teamView &&
          !_branchFilter.mapRowInScope(
            e,
            branchId: _selectedBranchId,
            departmentId: _selectedDepartmentId,
          )) {
        return false;
      }
      final id = e['id']?.toString() ?? '';
      if (_selectedEmployeeId != null && id != _selectedEmployeeId) {
        return false;
      }
      if (q.isNotEmpty) {
        final name = (e['fullName'] ??
                '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim())
            .toString()
            .toLowerCase();
        final code = (e['employeeCode'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !code.contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final na = (a['fullName'] ??
                '${a['lastName'] ?? ''} ${a['firstName'] ?? ''}'.trim())
            .toString()
            .toLowerCase();
        final nb = (b['fullName'] ??
                '${b['lastName'] ?? ''} ${b['firstName'] ?? ''}'.trim())
            .toString()
            .toLowerCase();
        final ca = (a['employeeCode'] ?? '').toString().toLowerCase();
        final cb = (b['employeeCode'] ?? '').toString().toLowerCase();
        final c = _empSortColumn == 1 ? ca.compareTo(cb) : na.compareTo(nb);
        return _empSortAscending ? c : -c;
      });
  }

  List<String> get _empSuggestions {
    final names = <String>{};
    for (final e in _employees) {
      final n = (e['fullName'] ??
              '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim())
          .toString();
      if (n.isNotEmpty) names.add(n);
    }
    return names.toList()..sort();
  }

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_teamView) {
        _branchFilter.loadOrgFilters(_api).then((_) {
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
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final isEmployee = isEmployeeUserRole(auth.userRole);

      await _branchFilter.ensureEmployees(
        _api,
        branchId: _teamView ? _selectedBranchId : null,
      );
      var employees = List<Map<String, dynamic>>.from(_branchFilter.employees);

      if (isEmployee) {
        final me = await _api.getMyEmployee();
        if (me['isSuccess'] == true && me['data'] is Map) {
          employees = [Map<String, dynamic>.from(me['data'] as Map)];
        }
      }

      final List<Device> devices;
      if (isEmployee) {
        devices = [];
      } else {
        final raw = await _api.getDevices(storeOnly: true);
        devices = raw
            .map((d) => Device.fromJson(d as Map<String, dynamic>))
            .toList();
      }
      final deviceIds = devices.map((d) => d.id).toList();

      final settings = await Future.wait([
        _api.getAppSetting('day_end_time').catchError((_) => <String, dynamic>{}),
        _api
            .getAppSetting('min_work_day_percent')
            .catchError((_) => <String, dynamic>{}),
        _api
            .getAppSetting('decimal_work_day_enabled')
            .catchError((_) => <String, dynamic>{}),
        _api
            .getAppSetting('standard_work_hours')
            .catchError((_) => <String, dynamic>{}),
        _api.getSalarySettings().catchError((_) => <String, dynamic>{}),
        _api
            .getAppSetting('min_hours_for_work_day')
            .catchError((_) => <String, dynamic>{}),
        _api
            .getAppSetting('min_half_day_hours')
            .catchError((_) => <String, dynamic>{}),
      ]);

      int deh = 0, dem = 0;
      final dayEnd = settings[0];
      if (dayEnd['isSuccess'] == true && dayEnd['data'] is Map) {
        final value =
            (dayEnd['data'] as Map)['value']?.toString() ?? '00:00:00';
        final parts = value.split(':');
        if (parts.length >= 2) {
          deh = int.tryParse(parts[0]) ?? 0;
          dem = int.tryParse(parts[1]) ?? 0;
        }
      }

      Map<String, dynamic>? salarySettings;
      final salaryRes = settings[4];
      if (salaryRes['isSuccess'] == true && salaryRes['data'] is Map) {
        salarySettings = Map<String, dynamic>.from(salaryRes['data'] as Map);
      }
      final minPercent = parseMinWorkDayPercent(
        salarySettings: salarySettings,
        percentAppSettingValue: _settingValue(settings[1]),
        legacyHoursAppSettingValue: _settingValue(settings[5]),
      );
      final minHalfHours = parseMinHalfDayHours(
        salarySettings: salarySettings,
        appSettingValue: _settingValue(settings[6]),
      );
      final decimalEnabled = parseDecimalWorkDayEnabled(
        salarySettings: salarySettings,
        appSettingValue: _settingValue(settings[2]),
      );
      // Ưu tiên app setting → thiết lập lương → mặc định 8h
      var stdHours =
          double.tryParse(_settingValue(settings[3]) ?? '') ?? 0;
      if (stdHours <= 0) {
        stdHours = parseStandardWorkHours(salarySettings: salarySettings);
      }
      if (stdHours <= 0) stdHours = 8;

      final fromStr = _fmtDate.format(_from);
      final toStr = _fmtDate.format(_to);

      final attLoad = await loadAttendancesForPeriodResult(
        _api,
        deviceIds: deviceIds,
        fromDate: _from,
        toDate: _to,
        dayEndHour: deh,
        dayEndMinute: dem,
        pageSize: 1000,
      );

      final parallel = await Future.wait([
        _api.getShifts().catchError((_) => <dynamic>[]),
        loadAttendanceSalaryProfiles(
          _api,
          preferSelfServiceApi: isEmployee,
        ),
        _api.getHolidaySettings(0).catchError((_) => <dynamic>[]),
        loadLeavesForPeriod(
          _api,
          fromDate: fromStr,
          toDate: toStr,
          status: 'Approved',
        ).catchError((_) => <dynamic>[]),
        loadLeavesForPeriod(
          _api,
          fromDate: fromStr,
          toDate: toStr,
          status: 'Pending',
        ).catchError((_) => <dynamic>[]),
        _api
            .getShiftSalaryLevels()
            .catchError((_) => <String, dynamic>{}),
      ]);

      final shifts = (parallel[0] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final salaryProfiles = parallel[1] as List<Map<String, dynamic>>;
      final holidays = parallel[2] as List;
      final approvedLeaves = parallel[3] as List;
      final pendingLeaves = parallel[4] as List;
      final allLeaves = [...approvedLeaves, ...pendingLeaves];
      final salaryLevelsResult = parallel[5] as Map<String, dynamic>;
      final shiftLevels = ((salaryLevelsResult['data']?['items'] ??
              salaryLevelsResult['data'] ??
              []) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      final paidLeaveByCode = <String, String>{};
      final weeklyOffByCode = <String, String>{};
      final paidLeaveByGuid = <String, String>{};
      final weeklyOffByGuid = <String, String>{};
      for (final profile in salaryProfiles) {
        final plt = profile['paidLeaveType']?.toString();
        final weekly = profile['weeklyOffDays']?.toString() ?? 'Sunday';
        final emps = profile['employees'] as List? ?? [];
        for (final emp in emps) {
          if (emp is! Map) continue;
          final code = emp['employeeCode']?.toString() ?? '';
          final guid = emp['id']?.toString() ?? '';
          if (code.isNotEmpty) {
            if (plt != null && plt.isNotEmpty) paidLeaveByCode[code] = plt;
            weeklyOffByCode[code] = weekly;
          }
          if (guid.isNotEmpty) {
            if (plt != null && plt.isNotEmpty) paidLeaveByGuid[guid] = plt;
            weeklyOffByGuid[guid] = weekly;
          }
        }
      }

      final leaveLookup = AttendanceLeaveLookup.fromLeaves(
        allLeaves,
        employeesList: employees,
        includePending: true,
      );

      final punchKeys = buildAttendanceDayKeys(
        attLoad.items,
        dayEndHour: deh,
        dayEndMinute: dem,
      );

      final shiftRecords = computeDailyShiftRecords(
        attendances: attLoad.items,
        fromDate: _from,
        toDate: _to,
        shiftTemplates: shifts,
        shiftSalaryLevels: shiftLevels,
        salaryProfiles: salaryProfiles,
        employeesList: employees,
        holidays: holidays,
        dayEndHour: deh,
        dayEndMinute: dem,
        minWorkDayPercent: minPercent,
        minHalfDayHours: minHalfHours,
        decimalWorkDayEnabled: decimalEnabled,
        standardWorkHours: stdHours,
      );

      final shiftPairs = computeDailyShiftPairs(
        attendances: attLoad.items,
        fromDate: _from,
        toDate: _to,
        shiftTemplates: shifts,
        shiftSalaryLevels: shiftLevels,
        salaryProfiles: salaryProfiles,
        employeesList: employees,
        dayEndHour: deh,
        dayEndMinute: dem,
      );

      // Index theo mọi mã định danh NV (PIN / mã NV / GUID / userId)
      // để không miss record → báo nhầm "! thiếu chấm" khi đã có đủ vào-ra.
      final recordByKey = <String, DailyShiftRecord>{};
      for (final r in shiftRecords) {
        final dk = _fmtDate.format(r.date);
        for (final id in _employeeAliasIds(
          employees,
          punchKeys: {r.employeeCode, r.employeeId},
        )) {
          recordByKey['$id|$dk'] = r;
        }
      }

      // Lưu ý: DailyShiftPair.employeeId thường = employeeCode (mã chấm).
      // Gán cùng list cho alias — không .add() hai lần.
      final pairsByKey = <String, List<DailyShiftPair>>{};
      for (final p in shiftPairs) {
        final dk = _fmtDate.format(p.date);
        final aliases = _employeeAliasIds(
          employees,
          punchKeys: {p.employeeCode, p.employeeId},
        );
        if (aliases.isEmpty) continue;

        List<DailyShiftPair>? shared;
        for (final id in aliases) {
          final existing = pairsByKey['$id|$dk'];
          if (existing != null) {
            shared = existing;
            break;
          }
        }
        shared ??= <DailyShiftPair>[];

        final dup = shared.any((x) =>
            identical(x, p) ||
            (x.shiftTemplateId != null &&
                x.shiftTemplateId == p.shiftTemplateId &&
                x.checkIn == p.checkIn &&
                x.checkOut == p.checkOut) ||
            (x.shiftName == p.shiftName &&
                x.checkIn == p.checkIn &&
                x.checkOut == p.checkOut));
        if (!dup) shared.add(p);

        for (final id in aliases) {
          pairsByKey['$id|$dk'] = shared;
        }
      }

      final today = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
      );

      final dayCells = <String, Map<String, dynamic>>{};

      for (final emp in employees) {
        final code = emp['employeeCode']?.toString() ?? '';
        final guid = emp['id']?.toString() ?? '';
        final userId = emp['applicationUserId']?.toString();
        final name = emp['fullName']?.toString() ??
            '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
        if (code.isEmpty && guid.isEmpty) continue;

        final plt =
            paidLeaveByCode[code] ?? paidLeaveByGuid[guid] ?? 'sunday';
        final weekly =
            weeklyOffByCode[code] ?? weeklyOffByGuid[guid] ?? 'Sunday';
        final cellId = guid.isNotEmpty ? guid : code;

        for (var d = DateTime(_from.year, _from.month, _from.day);
            !d.isAfter(DateTime(_to.year, _to.month, _to.day));
            d = d.add(const Duration(days: 1))) {
          final dk = _fmtDate.format(d);
          final cellKey = '$cellId|$dk';

          if (d.isAfter(today)) {
            dayCells[cellKey] = _emptyCell(
              d: d,
              dk: dk,
              guid: guid,
              code: code,
              name: name,
              status: _DayStatus.future,
            );
            continue;
          }

          final record = recordByKey['$code|$dk'] ??
              recordByKey['$guid|$dk'] ??
              (userId != null ? recordByKey['$userId|$dk'] : null);
          final pairs = _uniquePairs(
            pairsByKey['$code|$dk'] ??
                pairsByKey['$guid|$dk'] ??
                (userId != null ? pairsByKey['$userId|$dk'] : null) ??
                const <DailyShiftPair>[],
          );

          final hasPunch = employeeHasPunchOnDay(
            punchKeys: punchKeys,
            dateKey: dk,
            employeeCode: code.isEmpty ? null : code,
            employeeGuid: guid.isEmpty ? null : guid,
            applicationUserId: userId,
          );

          final hasCompletePair = pairs.any(
            (p) => p.checkIn != null && p.checkOut != null,
          );
          final hasIncompletePair = pairs.any(
            (p) => p.checkIn != null && p.checkOut == null,
          );

          // Giờ làm thực tế trong ngày (ưu tiên record, fallback tổng cặp vào-ra)
          var workHours = record?.decimalHours ?? 0.0;
          if (workHours <= 0) workHours = record?.workHours ?? 0.0;
          if (workHours <= 0) workHours = _hoursFromPairs(pairs);

          // Giờ chuẩn 1 công của NV (hồ sơ lương) — mặc định stdHours store
          double hoursPerDay = stdHours;
          for (final profile in salaryProfiles) {
            final emps = profile['employees'] as List? ?? [];
            final matched = emps.any((e) =>
                e is Map &&
                (e['id']?.toString() == guid ||
                    e['employeeCode']?.toString() == code));
            if (matched) {
              hoursPerDay = parseHoursPerWorkDay(
                profile: profile,
                fallbackHours: stdHours,
              );
              break;
            }
          }

          final dayCredit = computeDayWorkCredit(
            actualHours: workHours,
            hoursPerWorkDay: hoursPerDay,
            minPercent: minPercent,
            decimalWorkDayEnabled: decimalEnabled,
            minHalfDayHours: minHalfHours,
          );

          // X đủ công / X/2 / ! thiếu chấm
          _DayStatus? punchStatus;
          var workCount = 0.0;
          if (hasPunch || hasCompletePair || workHours > 0) {
            if (!hasCompletePair && workHours <= 0) {
              punchStatus = _DayStatus.missingPunch;
            } else if (dayCredit >= 0.95) {
              punchStatus = _DayStatus.present;
              workCount = dayCredit;
            } else if (dayCredit > 0) {
              punchStatus = _DayStatus.halfDay;
              workCount = dayCredit;
            } else {
              punchStatus = _DayStatus.missingPunch;
            }
            // Thứ 7 nửa buổi (sat-afternoon-sun) — tối đa X/2
            if (plt.toLowerCase() == 'sat-afternoon-sun' &&
                d.weekday == DateTime.saturday &&
                punchStatus == _DayStatus.present) {
              punchStatus = _DayStatus.halfDay;
              workCount = 0.5;
            }
          }

          if (punchStatus != null) {
            dayCells[cellKey] = {
              'date': d,
              'dateKey': dk,
              'employeeId': guid,
              'employeeCode': code,
              'employeeName': name.isEmpty ? code : name,
              'status': punchStatus.name,
              'workCount': workCount,
              'workHours': workHours,
              'stdWorkHours': stdHours,
              'lateMinutes': record?.lateMinutes ?? 0,
              'earlyMinutes': record?.earlyMinutes ?? 0,
              'hasIncompletePair': hasIncompletePair,
              'shiftNames': record?.shiftNames ??
                  pairs
                      .map((p) => p.shiftName)
                      .where((s) => s.isNotEmpty)
                      .toList(),
              'punchTimes':
                  record?.punchTimes ?? pairs.expand(_pairPunchTimes).toList(),
              'pairs': pairs
                  .map((p) => {
                        'shiftName': p.shiftName,
                        'checkIn': p.checkIn,
                        'checkOut': p.checkOut,
                        'lateMinutes': p.lateMinutes,
                        'earlyMinutes': p.earlyMinutes,
                      })
                  .toList(),
              'recordStatus': record?.status,
            };
            continue;
          }

          final holiday = isHolidayDate(
            d,
            holidays,
            employeeCode: code.isEmpty ? null : code,
            employeeGuid: guid.isEmpty ? null : guid,
          );
          final rest = isEmployeeRestDay(
            d,
            paidLeaveType: plt,
            weeklyOffDays: weekly,
          );

          final kind = leaveLookup.classify(
            day: d,
            employeeCode: code.isEmpty ? null : code,
            employeeUserId: userId,
            hrEmployeeId: guid.isEmpty ? null : guid,
            displayEmployeeId: code.isEmpty ? guid : code,
            isHoliday: holiday,
            isWeeklyOff: rest,
          );

          final status = switch (kind) {
            AbsenceCellKind.holiday => _DayStatus.holiday,
            AbsenceCellKind.weeklyOff => _DayStatus.weeklyOff,
            AbsenceCellKind.approvedLeave => _DayStatus.approvedLeave,
            AbsenceCellKind.pendingLeave => _DayStatus.pendingLeave,
            AbsenceCellKind.unpaidAbsent => _DayStatus.unpaidAbsent,
          };

          dayCells[cellKey] = _emptyCell(
            d: d,
            dk: dk,
            guid: guid,
            code: code,
            name: name,
            status: status,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _employees = employees;
        _stdWorkHours = stdHours;
        _minWorkDayPercent = minPercent;
        _dayCells
          ..clear()
          ..addAll(dayCells);
        _loading = false;
        _page = 1;
        if (_selectedEmployeeId != null &&
            !_employees.any((e) => e['id']?.toString() == _selectedEmployeeId)) {
          _selectedEmployeeId = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  String? _settingValue(dynamic result) {
    if (result is Map && result['isSuccess'] == true && result['data'] is Map) {
      return (result['data'] as Map)['value']?.toString();
    }
    return null;
  }

  Map<String, dynamic> _emptyCell({
    required DateTime d,
    required String dk,
    required String guid,
    required String code,
    required String name,
    required _DayStatus status,
  }) {
    return {
      'date': d,
      'dateKey': dk,
      'employeeId': guid,
      'employeeCode': code,
      'employeeName': name.isEmpty ? code : name,
      'status': status.name,
      'workCount': 0.0,
      'lateMinutes': 0,
      'earlyMinutes': 0,
      'shiftNames': const <String>[],
      'punchTimes': const <DateTime>[],
      'pairs': const <Map<String, dynamic>>[],
    };
  }

  List<DateTime> _pairPunchTimes(DailyShiftPair p) {
    return [
      if (p.checkIn != null) p.checkIn!,
      if (p.checkOut != null) p.checkOut!,
    ];
  }

  /// Các mã có thể khớp NV: mã NV, PIN, GUID, userId (và chính các punchKeys).
  Set<String> _employeeAliasIds(
    List<Map<String, dynamic>> employees, {
    required Set<String> punchKeys,
  }) {
    final keys = punchKeys.where((s) => s.isNotEmpty).toSet();
    if (keys.isEmpty) return {};
    final aliases = <String>{...keys};
    for (final emp in employees) {
      final ids = <String>[
        emp['employeeCode']?.toString() ?? '',
        emp['pin']?.toString() ?? '',
        emp['enrollNumber']?.toString() ?? '',
        emp['id']?.toString() ?? '',
        emp['applicationUserId']?.toString() ?? '',
      ].where((s) => s.isNotEmpty).toSet();
      if (ids.any(keys.contains)) {
        aliases.addAll(ids);
      }
    }
    return aliases;
  }

  double _hoursFromPairs(List<DailyShiftPair> pairs) {
    var minutes = 0;
    for (final p in pairs) {
      final cin = p.checkIn;
      var cout = p.checkOut;
      if (cin == null || cout == null) continue;
      if (cout.isBefore(cin)) cout = cout.add(const Duration(days: 1));
      final m = cout.difference(cin).inMinutes;
      if (m > 0) minutes += m;
    }
    return minutes / 60.0;
  }

  /// Bỏ ca trùng (cùng ca + cùng giờ vào/ra).
  List<DailyShiftPair> _uniquePairs(List<DailyShiftPair> pairs) {
    if (pairs.length <= 1) return pairs;
    final seen = <String>{};
    final out = <DailyShiftPair>[];
    for (final p in pairs) {
      final cin = p.checkIn?.millisecondsSinceEpoch ?? 0;
      final cout = p.checkOut?.millisecondsSinceEpoch ?? 0;
      final key =
          '${p.shiftTemplateId ?? p.shiftName}|$cin|$cout|${p.lateMinutes}|${p.earlyMinutes}';
      if (seen.add(key)) out.add(p);
    }
    // Sắp theo giờ vào tăng dần cho tooltip dễ đọc
    out.sort((a, b) {
      final ta = a.checkIn ?? a.checkOut ?? a.date;
      final tb = b.checkIn ?? b.checkOut ?? b.date;
      return ta.compareTo(tb);
    });
    return out;
  }

  List<ReportKpiItem> _buildKpis() {
    final emps = _filteredEmployees;
    final days = _daysInRange;
    var present = 0, half = 0, unpaid = 0, leave = 0;
    var totalWork = 0.0;
    for (final emp in emps) {
      final id = emp['id']?.toString() ?? '';
      final code = emp['employeeCode']?.toString() ?? '';
      final keyId = id.isNotEmpty ? id : code;
      for (final d in days) {
        final cell = _dayCells['$keyId|${_fmtDate.format(d)}'];
        if (cell == null) continue;
        final st = cell['status']?.toString() ?? '';
        final wc = (cell['workCount'] as num?)?.toDouble() ?? 0;
        if (st == _DayStatus.present.name) {
          present++;
          totalWork += wc > 0 ? wc : 1;
        } else if (st == _DayStatus.halfDay.name) {
          half++;
          totalWork += wc > 0 ? wc : 0.5;
        } else if (st == _DayStatus.unpaidAbsent.name) {
          unpaid++;
        } else if (st == _DayStatus.approvedLeave.name ||
            st == _DayStatus.pendingLeave.name) {
          leave++;
        }
      }
    }
    final workLabel = totalWork == totalWork.roundToDouble()
        ? totalWork.toInt().toString()
        : totalWork.toStringAsFixed(1);
    return [
      ReportKpiItem(
          label: 'NV',
          value: emps.length.toString(),
          icon: Icons.people_outline,
          color: Colors.blueGrey),
      ReportKpiItem(
          label: 'X đủ công',
          value: present.toString(),
          icon: Icons.check_circle_outline,
          color: PosTheme.primaryDark),
      ReportKpiItem(
          label: 'X/2',
          value: half.toString(),
          icon: Icons.timelapse,
          color: PosTheme.kiotBlue),
      ReportKpiItem(
          label: 'Tổng công',
          value: workLabel,
          icon: Icons.calculate_outlined,
          color: _theme),
      ReportKpiItem(
          label: 'V vắng',
          value: unpaid.toString(),
          icon: Icons.person_off_outlined,
          color: const Color(0xFFD32F2F)),
      ReportKpiItem(
          label: 'Phép',
          value: leave.toString(),
          icon: Icons.beach_access_outlined,
          color: PosTheme.primary),
    ];
  }

  /// Thanh KPI 1 hàng — nền trắng, viền xanh, thấp gọn.
  Widget _compactKpiBar(List<ReportKpiItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.white,
      child: HrmStatBar(
        items: [
          for (final k in items)
            HrmStatItem(icon: k.icon, label: k.label, value: k.value),
        ],
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        gap: 6,
        valueFontSize: 14,
        minCardWidth: 100,
      ),
    );
  }

  Future<void> _exportExcel() async {
    final days = _daysInRange;
    final emps = _filteredEmployees;
    final headers = <String>[
      'STT',
      'Mã NV',
      'Họ tên',
      ...days.map((d) => DateFormat('dd/MM').format(d)),
      'Tổng công',
    ];
    final rows = <List<dynamic>>[];
    for (var i = 0; i < emps.length; i++) {
      final emp = emps[i];
      final id = emp['id']?.toString() ?? '';
      final code = emp['employeeCode']?.toString() ?? '';
      final name = emp['fullName']?.toString() ??
          '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
      final keyId = id.isNotEmpty ? id : code;
      final row = <dynamic>[i + 1, code, name];
      var total = 0.0;
      for (final d in days) {
        final cell = _dayCells['$keyId|${_fmtDate.format(d)}'];
        row.add(_cellExportLabel(cell));
        total += _cellWorkCredit(cell);
      }
      row.add(total == total.roundToDouble()
          ? total.toInt()
          : double.parse(total.toStringAsFixed(2)));
      rows.add(row);
    }
    await ClientExcelExport.export(
      context: context,
      title: 'Bảng lịch chấm công',
      sheetName: 'Bang lich',
      filePrefix: 'BangLichChamCong',
      headers: headers,
      rows: rows,
      periodLabel: reportPeriodSubtitle(_from, _to, team: _teamView),
    );
  }

  Future<void> _exportPng() async {
    await ClientPngExport.capture(
      context: context,
      key: _pngKey,
      filePrefix: 'ChamCong',
    );
  }

  double _cellWorkCredit(Map<String, dynamic>? cell) {
    if (cell == null) return 0;
    final st = cell['status']?.toString() ?? '';
    final wc = (cell['workCount'] as num?)?.toDouble() ?? 0;
    if (st == _DayStatus.present.name) return wc > 0 ? wc : 1;
    if (st == _DayStatus.halfDay.name) return wc > 0 ? wc : 0.5;
    return 0;
  }

  String _cellExportLabel(Map<String, dynamic>? cell) {
    if (cell == null) return '';
    final st = cell['status']?.toString() ?? '';
    final late = (cell['lateMinutes'] as int?) ?? 0;
    final early = (cell['earlyMinutes'] as int?) ?? 0;
    switch (st) {
      case 'present':
        final parts = <String>['X'];
        if (late > 0) parts.add('T${late}p');
        if (early > 0) parts.add('S${early}p');
        return parts.join('/');
      case 'halfDay':
        final parts = <String>['X/2'];
        if (late > 0) parts.add('T${late}p');
        if (early > 0) parts.add('S${early}p');
        return parts.join('/');
      case 'missingPunch':
        return 'Thiếu chấm';
      case 'unpaidAbsent':
        return 'V';
      case 'approvedLeave':
        return 'Phép';
      case 'pendingLeave':
        return 'Chờ phép';
      case 'weeklyOff':
        return 'Nghỉ tuần';
      case 'holiday':
        return 'Lễ';
      default:
        return '';
    }
  }

  Widget _employeeDropdown() {
    if (!_teamView || _employees.length <= 1) {
      return const SizedBox.shrink();
    }
    final items = [
      DropdownMenuItem<String?>(
        value: null,
        child: Text(tr('Tất cả nhân viên')),
      ),
      ..._employees.map((e) {
        final id = e['id']?.toString();
        final code = e['employeeCode']?.toString() ?? '';
        final name = e['fullName']?.toString() ??
            '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
        final label = [
          if (code.isNotEmpty) code,
          if (name.isNotEmpty) name,
        ].join(' · ');
        return DropdownMenuItem<String?>(
          value: id,
          child: Text(tr(label), overflow: TextOverflow.ellipsis),
        );
      }),
    ];
    final validIds = _employees.map((e) => e['id']?.toString()).toSet();
    final value = validIds.contains(_selectedEmployeeId)
        ? _selectedEmployeeId
        : null;

    return DropdownButtonFormField<String?>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: tr('Nhân viên'),
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        prefixIcon: Icon(Icons.person_outline, size: 18),
      ),
      items: items,
      onChanged: (v) => setState(() {
        _selectedEmployeeId = v;
        _page = 1;
      }),
    );
  }

  Widget _calendarLegend() {
    final pctLabel = _minWorkDayPercent == _minWorkDayPercent.roundToDouble()
        ? '${_minWorkDayPercent.toInt()}%'
        : '${_minWorkDayPercent.toStringAsFixed(0)}%';
    final stdLabel = _stdWorkHours == _stdWorkHours.roundToDouble()
        ? '${_stdWorkHours.toInt()}h'
        : '${_stdWorkHours.toStringAsFixed(1)}h';
    final items = <({String code, String label, Color fg})>[
      (
        code: 'X',
        label: 'Đủ công (≥ $pctLabel × $stdLabel)',
        fg: HrmPageChrome.chipDark
      ),
      (code: 'X/2', label: 'Nửa công (< $pctLabel)', fg: HrmPageChrome.chip),
      (code: 'V', label: 'Vắng', fg: HrmPageChrome.chipMid),
      (code: 'T', label: 'Đi trễ', fg: HrmPageChrome.chipLight),
      (code: 'S', label: 'Về sớm', fg: HrmPageChrome.chipSoft),
      (code: '!', label: 'Thiếu chấm', fg: HrmPageChrome.chipMuted),
      (code: 'P', label: 'Phép', fg: HrmPageChrome.chip),
      (code: 'C', label: 'Chờ phép', fg: HrmPageChrome.chipSoft),
      (code: 'N', label: 'Nghỉ tuần', fg: HrmPageChrome.chipMuted),
      (code: 'L', label: 'Ngày lễ', fg: HrmPageChrome.chipMid),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HrmPageChrome.chip.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Chú thích'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: HrmPageChrome.chipDark,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final it in items)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: HrmPageChrome.chip.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tr(it.code),
                          style: TextStyle(
                            color: it.fg,
                            fontSize: it.code.length > 2 ? 10 : 11,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          tr(it.label),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: HrmPageChrome.textMuted,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('AttendanceReport');
    final canView = Provider.of<PermissionProvider>(context, listen: false)
        .canView('AttendanceReport');

    if (!canView) {
      return Scaffold(
        body: Center(child: Text(tr('Bạn không có quyền xem báo cáo chấm công'))),
      );
    }

    final calEmps = _filteredEmployees;
    final totalPages =
        (calEmps.length / _calEmpPageSize).ceil().clamp(1, 999999);
    final page = _page.clamp(1, totalPages);
    final start = (page - 1) * _calEmpPageSize;
    final pageRows = calEmps.skip(start).take(_calEmpPageSize).toList();

    return RegisterPageTopActions(
      actions: [
        if (canExport)
          HrmTopBarAction(
            icon: Icons.image_outlined,
            label: 'Xuất PNG',
            onPressed: calEmps.isEmpty ? null : _exportPng,
            pinOnMobile: false,
          ),
        if (canExport)
          HrmTopBarAction(
            icon: Icons.file_download_outlined,
            label: 'Xuất Excel',
            onPressed: calEmps.isEmpty ? null : _exportExcel,
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
                    kpi: _compactKpiBar(_buildKpis()),
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
                      statusFilter: _employeeDropdown(),
                      statusSummary: _selectedEmployeeId != null
                          ? 'NV đã chọn'
                          : 'Bảng lịch chấm công',
                      showTeamFilters: _teamView,
                      branchFilter: _teamView ? _branchFilter : null,
                      selectedBranchId: _selectedBranchId,
                      onBranchChanged: (v) async {
                        await _branchFilter.ensureEmployees(_api, branchId: v);
                        if (mounted) {
                          setState(() {
                            _selectedBranchId = v;
                            _page = 1;
                          });
                        }
                      },
                      selectedDepartmentId: _selectedDepartmentId,
                      onDepartmentChanged: (v) {
                        if (mounted) {
                          setState(() {
                            _selectedDepartmentId = v;
                            _page = 1;
                          });
                        }
                      },
                      empSearch: _empSearch,
                      onEmpSearchChanged: (v) => setState(() {
                        _empSearch = v;
                        _page = 1;
                      }),
                      empSuggestions: _empSuggestions,
                      onApply: () {
                        setState(() => _page = 1);
                        _load();
                      },
                      onClearFilters: _teamView
                          ? () => setState(() {
                                _empSearch = '';
                                _selectedBranchId = null;
                                _selectedDepartmentId = null;
                                _selectedEmployeeId = null;
                                _page = 1;
                              })
                          : null,
                    ),
                  ),
                  reportLoadErrorBanner(_loadError),
                  _calendarLegend(),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (pageRows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: ReportEmptyState(
                        title: 'Không có dữ liệu',
                        subtitle:
                            'Thử đổi khoảng thời gian hoặc bộ lọc nhân viên',
                      ),
                    )
                  else
                    _buildCalendarTable(pageRows),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_loading && calEmps.isNotEmpty)
            ReportPaginationBar(
              page: page,
              pageSize: _calEmpPageSize,
              totalCount: calEmps.length,
              onPageChanged: (p) => setState(() => _page = p),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildCalendarTable(List<Map<String, dynamic>> emps) {
    final days = _daysInRange;
    const nameW = 148.0;
    const dayW = 42.0;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              color: const Color(0xFFF8FAFC),
              child: Row(
                children: [
                  SizedBox(
                    width: nameW,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (_empSortColumn == 0) {
                            _empSortAscending = !_empSortAscending;
                          } else {
                            _empSortColumn = 0;
                            _empSortAscending = true;
                          }
                          _page = 1;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(tr('Nhân viên'),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                            ),
                            Icon(
                              _empSortColumn == 0
                                  ? (_empSortAscending
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward)
                                  : Icons.unfold_more,
                              size: 14,
                              color: _empSortColumn == 0
                                  ? const Color(0xFF0070F4)
                                  : Colors.grey.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  ...days.map((d) {
                    final isSun = d.weekday == DateTime.sunday;
                    final isSat = d.weekday == DateTime.saturday;
                    return SizedBox(
                      width: dayW,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Text(
                              tr(_fmtDay.format(d)),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: isSun
                                    ? const Color(0xFFDC2626)
                                    : isSat
                                        ? const Color(0xFFEA580C)
                                        : const Color(0xFF334155),
                              ),
                            ),
                            Text(
                              tr(_fmtWeekday.format(d)),
                              style: TextStyle(
                                fontSize: 9,
                                color: isSun
                                    ? const Color(0xFFDC2626)
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            ...List.generate(emps.length, (i) {
              final emp = emps[i];
              final id = emp['id']?.toString() ?? '';
              final code = emp['employeeCode']?.toString() ?? '';
              final name = emp['fullName']?.toString() ??
                  '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
              final keyId = id.isNotEmpty ? id : code;
              final zebra = i.isOdd;

              return Container(
                color: zebra ? const Color(0xFFFAFAFA) : Colors.white,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: nameW,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(name.isEmpty ? code : name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            if (code.isNotEmpty)
                              Text(tr(code),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ),
                    ...days.map((d) {
                      final cell =
                          _dayCells['$keyId|${_fmtDate.format(d)}'];
                      return SizedBox(
                        width: dayW,
                        height: 36,
                        child: Center(child: _buildDayCell(cell)),
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCell(Map<String, dynamic>? cell) {
    if (cell == null) return const SizedBox.shrink();

    final st = cell['status']?.toString() ?? '';
    final late = (cell['lateMinutes'] as int?) ?? 0;
    final early = (cell['earlyMinutes'] as int?) ?? 0;

    Color fg;
    String label;
    var bordered = true;

    switch (st) {
      case 'present':
        if (late > 0) {
          fg = HrmPageChrome.chipLight;
          label = 'T$late';
        } else if (early > 0) {
          fg = HrmPageChrome.chipSoft;
          label = 'S$early';
        } else {
          fg = HrmPageChrome.chipDark;
          label = 'X';
        }
        break;
      case 'halfDay':
        fg = late > 0 ? HrmPageChrome.chipLight : HrmPageChrome.chip;
        label = 'X/2';
        break;
      case 'missingPunch':
        fg = HrmPageChrome.chipMuted;
        label = '!';
        break;
      case 'unpaidAbsent':
        fg = HrmPageChrome.chipMid;
        label = 'V';
        break;
      case 'approvedLeave':
        fg = HrmPageChrome.chip;
        label = 'P';
        break;
      case 'pendingLeave':
        fg = HrmPageChrome.chipSoft;
        label = 'C';
        break;
      case 'weeklyOff':
        fg = HrmPageChrome.chipMuted;
        label = 'N';
        break;
      case 'holiday':
        fg = HrmPageChrome.chipMid;
        label = 'L';
        break;
      case 'future':
        fg = const Color(0xFFA1A1AA);
        label = '·';
        bordered = false;
        break;
      default:
        fg = Colors.grey;
        label = '';
        bordered = false;
    }

    final tip = _buildCellTooltip(cell);
    final box = Container(
      width: 34,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bordered ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: bordered
            ? Border.all(color: HrmPageChrome.chip.withValues(alpha: 0.45))
            : null,
      ),
      child: Text(
        tr(label),
        style: TextStyle(
          color: fg,
          fontSize: label.length > 3 ? 9 : 11,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );

    if (tip.isEmpty) return box;
    return Tooltip(
      message: tip,
      waitDuration: const Duration(milliseconds: 200),
      showDuration: const Duration(seconds: 8),
      preferBelow: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        height: 1.35,
      ),
      child: box,
    );
  }

  String _buildCellTooltip(Map<String, dynamic> cell) {
    final st = cell['status']?.toString() ?? '';
    final lines = <String>[];

    final hours = (cell['workHours'] as num?)?.toDouble() ?? 0;
    final std = (cell['stdWorkHours'] as num?)?.toDouble() ?? _stdWorkHours;
    final hoursTxt = hours > 0
        ? ' · ${hours == hours.roundToDouble() ? hours.toInt() : hours.toStringAsFixed(1)}h/${std == std.roundToDouble() ? std.toInt() : std.toStringAsFixed(1)}h'
        : '';
    final statusLine = switch (st) {
      'present' => 'Có đi làm (X)$hoursTxt',
      'halfDay' => 'Nửa công (X/2)$hoursTxt',
      'missingPunch' => 'Thiếu chấm (chưa ghép đủ cặp vào–ra)',
      'unpaidAbsent' => 'Vắng (V)',
      'approvedLeave' => 'Nghỉ phép',
      'pendingLeave' => 'Chờ duyệt phép',
      'weeklyOff' => 'Nghỉ tuần',
      'holiday' => 'Ngày lễ',
      'future' => 'Chưa tới ngày',
      _ => '',
    };
    if (statusLine.isNotEmpty) lines.add(statusLine);
    if (cell['hasIncompletePair'] == true && st != 'missingPunch') {
      lines.add('Lưu ý: còn ca thiếu giờ ra');
    }

    final pairs = (cell['pairs'] as List?) ?? const [];
    if (pairs.isNotEmpty) {
      for (var i = 0; i < pairs.length; i++) {
        final p = pairs[i];
        if (p is! Map) continue;
        final shift = p['shiftName']?.toString().trim() ?? '';
        final cin = p['checkIn'];
        final cout = p['checkOut'];
        final late = (p['lateMinutes'] as int?) ?? 0;
        final early = (p['earlyMinutes'] as int?) ?? 0;
        if (pairs.length > 1) {
          lines.add(shift.isNotEmpty ? '• $shift' : '• Ca ${i + 1}');
        } else if (shift.isNotEmpty) {
          lines.add('Ca: $shift');
        } else {
          lines.add('Ca làm việc');
        }
        lines.add(
            '  Vào: ${cin is DateTime ? _fmtTime.format(cin) : '—'}');
        lines.add(
            '  Ra: ${cout is DateTime ? _fmtTime.format(cout) : '—'}');
        if (late > 0) lines.add('  Trễ: ${late}p');
        if (early > 0) lines.add('  Về sớm: ${early}p');
      }
    } else {
      final shiftNames = (cell['shiftNames'] as List?)
              ?.map((e) => e.toString())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const <String>[];
      final punches = (cell['punchTimes'] as List?) ?? const [];
      if (shiftNames.isNotEmpty) {
        lines.add('Ca: ${shiftNames.join(', ')}');
      }
      if (punches.isNotEmpty) {
        lines.add('Lần chấm:');
        for (final t in punches) {
          if (t is DateTime) {
            lines.add('  ${_fmtTime.format(t)}');
          }
        }
      }
      final late = (cell['lateMinutes'] as int?) ?? 0;
      final early = (cell['earlyMinutes'] as int?) ?? 0;
      if (late > 0) lines.add('Trễ: ${late}p');
      if (early > 0) lines.add('Về sớm: ${early}p');
    }

    final recStatus = cell['recordStatus']?.toString();
    if (recStatus != null &&
        recStatus.isNotEmpty &&
        st != 'weeklyOff' &&
        st != 'holiday' &&
        st != 'unpaidAbsent' &&
        st != 'approvedLeave' &&
        st != 'pendingLeave' &&
        st != 'future') {
      // tránh trùng dòng trạng thái đã ghi
      if (!lines.any((l) => l.contains(recStatus))) {
        // bỏ qua — cặp ca đã đủ chi tiết
      }
    }

    return lines.join('\n');
  }
}
