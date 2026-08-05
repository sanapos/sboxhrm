import 'dart:convert';
import 'dart:math' as math;
// ignore_for_file: unused_element
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/web_canvas.dart' as web_canvas;
import 'package:flutter/material.dart';
import '../../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:provider/provider.dart';
import '../../utils/excel_report_builder.dart';
import '../../widgets/pinned_box_header_delegate.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../utils/attendance_correction_privilege.dart';
import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/attendance_frozen_employee_name_cell.dart';
import '../../widgets/hrm_collapsible_overview.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/attendance_correction_reason_field.dart';
import '../../widgets/attendance_delete_confirm_dialog.dart';
import '../../utils/attendance_date_range_presets.dart';
import '../../utils/attendance_leave_lookup.dart';
import '../../utils/absence_day_actions.dart';
import '../../utils/attendance_correction_submit.dart';
import '../../utils/attendance_record_resolver.dart';
import '../../utils/attendance_correction_dates.dart';
import '../../utils/attendance_viewport_preserve.dart';
import '../../utils/shift_records_calculator.dart';
import '../../utils/paid_leave_schedule_utils.dart';
import '../../utils/travel_hours_load_utils.dart';
import '../../utils/travel_eligibility_utils.dart';
import '../../utils/mobile_attendance_vertical_layout.dart';
import '../../widgets/synced_scroll_list_view.dart'
    show SyncedScrollListView, linkHorizontalScrollControllers;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class AttendanceByShiftTab extends StatefulWidget {
  final List<Attendance> attendances;
  final List<Device> devices;
  final DateTime fromDate;
  final DateTime toDate;
  final List<Map<String, dynamic>> shiftTemplates;
  final List<Map<String, dynamic>> shiftSalaryLevels;
  final List<Map<String, dynamic>> salaryProfiles;
  final List<dynamic> holidays;
  final int dayEndHour;
  final int dayEndMinute;
  final double minHoursForWorkDay;
  final bool decimalWorkDayEnabled;
  final double standardWorkHours;
  final List<dynamic> approvedLeaves;
  final List<Map<String, dynamic>>? employeesList;
  final VoidCallback? onDataChanged;
  final List<Widget>? mobileLeadingSections;
  final void Function(String preset)? onDateRangeChanged;

  /// Preset đang tải ở màn cha — giữ đồng bộ khi tab bị recreate sau loading.
  final String? dateRangePreset;

  /// Nếu false, ẩn nút thêm/sửa giờ chấm công.
  final bool allowCorrection;

  /// Admin / có quyền duyệt → backend tự động duyệt khi lưu.
  final bool directApplyCorrections;

  final Map<String, double> travelHoursByEmployeeKey;
  final Map<String, double> travelHoursByEmployeeDateKey;
  final Set<String> travelEligibleEmployeeKeys;

  /// Lịch làm việc (WorkSchedule) trong kỳ — dùng khi paidLeaveType=schedule.
  final List<Map<String, dynamic>> workSchedules;

  const AttendanceByShiftTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.fromDate,
    required this.toDate,
    this.shiftTemplates = const [],
    this.shiftSalaryLevels = const [],
    this.salaryProfiles = const [],
    this.holidays = const [],
    this.dayEndHour = 0,
    this.dayEndMinute = 0,
    this.minHoursForWorkDay = 0,
    this.decimalWorkDayEnabled = false,
    this.standardWorkHours = 8,
    this.approvedLeaves = const [],
    this.employeesList,
    this.onDataChanged,
    this.mobileLeadingSections,
    this.onDateRangeChanged,
    this.dateRangePreset,
    this.allowCorrection = true,
    this.directApplyCorrections = false,
    this.travelHoursByEmployeeKey = const {},
    this.travelHoursByEmployeeDateKey = const {},
    this.travelEligibleEmployeeKeys = const {},
    this.workSchedules = const [],
  });

  @override
  State<AttendanceByShiftTab> createState() => _AttendanceByShiftTabState();
}

class _AttendanceByShiftTabState extends State<AttendanceByShiftTab> {
  late String _selectedPreset;
  Set<String> _selectedEmployeeIds = {};
  // 'all' | 'valid' | 'late' | 'early' | 'late_early' | 'missing' | 'complete' | 'ot'
  String _shiftFilter = 'all';
  bool _showOverviewPanel = true;

  // Sorting
  final bool _sortAscending = false;
  int _rowsPerPage = 50;
  int _currentPage = 0;
  bool _isExporting = false;

  // Memoization cache for _shiftData (O(n) grouping + shift matching)
  List<_DailyShiftRecord>? _cachedShiftData;
  int? _cachedShiftFp;

  final ScrollController _listScrollController = ScrollController();
  final ScrollController _desktopTableHScrollHeader = ScrollController();
  final ScrollController _desktopTableHScrollBody = ScrollController();
  final AttendanceViewportPreserve _viewportPreserve =
      AttendanceViewportPreserve();
  bool _desktopScrollLinked = false;

  static const _tableInnerScrollPhysics = ClampingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  void _ensureDesktopTableScrollLinked() {
    if (_desktopScrollLinked) return;
    _desktopScrollLinked = true;
    linkHorizontalScrollControllers(
      _desktopTableHScrollHeader,
      _desktopTableHScrollBody,
    );
  }

  double _tableBodyViewportHeight(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final reserved = pad.top + pad.bottom + 240;
    return (mq.height - reserved).clamp(260.0, 520.0);
  }

  BoxDecoration get _tableCardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  // Cached lookup maps built from props
  Map<String, String> _employeeCodeToGuid = {};
  Map<String, List<String>> _employeeGuidToShiftTemplateIds = {};
  Map<String, Map<String, dynamic>> _shiftTemplateMap = {};
  Map<String, int> _employeeGuidToShiftsPerDay = {};
  // Rest day & holiday coefficient maps
  Map<String, String> _employeeCodeToWeeklyOffDays =
      {}; // empCode → 'Sunday' | 'Saturday,Sunday' etc.
  Map<String, String> _employeeCodeToPaidLeaveType = {};
  Map<String, double> _employeeCodeToHolidayMultiplier =
      {}; // empCode → 2.0 (x2) etc.
  Map<String, int> _employeeCodeToHolidayOvertimeType =
      {}; // empCode → 0=fixed, 1=legal coefficient
  Set<String> _scheduleDayOffKeys = {};
  Set<String> _scheduleWorkDayKeys = {};
  Set<String> _employeesWithSchedule = {};

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.dateRangePreset ?? 'month';
    _buildLookupMaps();
  }

  void _notifyDataChanged() {
    _viewportPreserve.capture(listScroll: _listScrollController);
    widget.onDataChanged?.call();
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _desktopTableHScrollHeader.dispose();
    _desktopTableHScrollBody.dispose();
    super.dispose();
  }

  bool _recordMatchesShiftStatusFilter(_DailyShiftRecord r) {
    switch (_shiftFilter) {
      case 'valid':
        return r.status == 'Hợp lệ';
      case 'late':
        return r.lateMinutes > 0;
      case 'early':
        return r.earlyMinutes > 0;
      case 'late_early':
        return r.lateMinutes > 0 && r.earlyMinutes > 0;
      case 'ot':
        return r.overtimeMinutes > 0;
      case 'missing':
        return r.status.contains('Thiếu chấm') ||
            r.status == 'Vắng' ||
            r.punchTimes.isEmpty ||
            r.punchTimes.length % 2 != 0;
      case 'complete':
        return !r.status.contains('Thiếu chấm') &&
            r.punchTimes.length >= 2 &&
            r.punchTimes.length % 2 == 0;
      default:
        return true;
    }
  }

  String _shiftStatusFilterLabel() {
    switch (_shiftFilter) {
      case 'valid':
        return 'Hợp lệ';
      case 'late':
        return 'Đi trễ';
      case 'early':
        return 'Về sớm';
      case 'late_early':
        return 'Đi trễ & Về sớm';
      case 'ot':
        return 'Tăng ca';
      case 'missing':
        return 'Thiếu chấm';
      case 'complete':
        return 'Đủ chấm công';
      default:
        return 'Tất cả trạng thái';
    }
  }

  int get _shiftFp => Object.hash(
        _selectedPreset,
        widget.dateRangePreset,
        widget.fromDate.millisecondsSinceEpoch,
        widget.toDate.millisecondsSinceEpoch,
        Object.hashAll(_selectedEmployeeIds),
        _shiftFilter,
        _sortAscending,
        identityHashCode(widget.attendances),
        widget.shiftTemplates.length,
        widget.salaryProfiles.length,
        widget.holidays.length,
        widget.employeesList?.length,
        widget.approvedLeaves.length,
        widget.workSchedules.length,
      );

  @override
  void didUpdateWidget(covariant AttendanceByShiftTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preset = widget.dateRangePreset;
    if (preset != null &&
        preset != _selectedPreset &&
        preset != oldWidget.dateRangePreset) {
      _selectedPreset = preset;
      _cachedShiftData = null;
      _currentPage = 0;
    }
    if (oldWidget.fromDate != widget.fromDate ||
        oldWidget.toDate != widget.toDate) {
      _cachedShiftData = null;
    }
    if (oldWidget.shiftTemplates != widget.shiftTemplates ||
        oldWidget.shiftSalaryLevels != widget.shiftSalaryLevels ||
        oldWidget.salaryProfiles != widget.salaryProfiles ||
        oldWidget.workSchedules != widget.workSchedules) {
      _buildLookupMaps(); // already nulls _cachedShiftData
    } else if (oldWidget.attendances != widget.attendances ||
        oldWidget.holidays != widget.holidays) {
      _cachedShiftData = null;
      _viewportPreserve.restore(listScroll: _listScrollController);
    }
  }

  void _buildLookupMaps() {
    _cachedShiftData = null; // lookup maps changed → results invalid
    // Build shift template map: shiftTemplateId → template data
    _shiftTemplateMap = {};
    for (final st in widget.shiftTemplates) {
      final id = st['id']?.toString() ?? '';
      if (id.isNotEmpty) _shiftTemplateMap[id] = st;
    }

    // Build a normalized shift name → templateId map for resolving names from
    // salary profile descriptions (e.g. "shifts:Ca sáng, Ca chiều")
    String normalizeShiftName(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final Map<String, String> shiftNameToId = {};
    for (final st in widget.shiftTemplates) {
      final id = st['id']?.toString() ?? '';
      final name = st['name']?.toString() ?? '';
      if (id.isNotEmpty && name.isNotEmpty) {
        shiftNameToId[normalizeShiftName(name)] = id;
      }
    }

    // Parse "k1:v1|k2:v2" description format used by salary profile UI
    String parseDescField(String? description, String key) {
      if (description == null || description.isEmpty) return '';
      for (final part in description.split('|')) {
        final idx = part.indexOf(':');
        if (idx <= 0) continue;
        if (part.substring(0, idx).trim() == key) {
          return part.substring(idx + 1).trim();
        }
      }
      return '';
    }

    // Build employeeCode → employeeGuid and employeeGuid → shiftsPerDay from salary profiles.
    // Also extract assigned shift names from profile description and map them to templateIds.
    _employeeCodeToGuid = {};
    _employeeGuidToShiftsPerDay = {};
    _employeeCodeToWeeklyOffDays = {};
    _employeeCodeToPaidLeaveType = {};
    _employeeCodeToHolidayMultiplier = {};
    _employeeCodeToHolidayOvertimeType = {};
    _employeeGuidToShiftTemplateIds = {};
    for (final profile in widget.salaryProfiles) {
      final shiftsPerDay = profile['shiftsPerDay'] as int? ?? 1;
      var weeklyOffDays = profile['weeklyOffDays']?.toString() ?? '';
      var paidLeaveType = profile['paidLeaveType']?.toString() ?? '';
      final nestedBenefit = profile['benefit'];
      if (paidLeaveType.isEmpty && nestedBenefit is Map) {
        paidLeaveType = nestedBenefit['paidLeaveType']?.toString() ?? '';
      }
      if (weeklyOffDays.isEmpty && nestedBenefit is Map) {
        weeklyOffDays = nestedBenefit['weeklyOffDays']?.toString() ?? '';
      }
      if (isSchedulePaidLeaveType(paidLeaveType) ||
          isFlatOffPaidLeaveType(paidLeaveType)) {
        weeklyOffDays = '';
      }
      final holidayMultiplier =
          (profile['holidayMultiplier'] as num?)?.toDouble() ?? 2.0;
      final holidayOvertimeType =
          (profile['holidayOvertimeType'] as num?)?.toInt() ?? 1;

      // Resolve shift names from profile description → list of templateIds
      final shiftsStr =
          parseDescField(profile['description']?.toString(), 'shifts');
      final List<String> profileShiftIds = [];
      if (shiftsStr.isNotEmpty) {
        for (final raw in shiftsStr.split(',')) {
          final norm = normalizeShiftName(raw);
          if (norm.isEmpty) continue;
          final id = shiftNameToId[norm];
          if (id != null && !profileShiftIds.contains(id)) {
            profileShiftIds.add(id);
          }
        }
      }

      final employees = profile['employees'] as List? ?? [];
      for (final emp in employees) {
        if (emp is Map<String, dynamic>) {
          final guid = emp['id']?.toString() ?? '';
          final code = emp['employeeCode']?.toString() ?? '';
          if (guid.isNotEmpty && code.isNotEmpty) {
            _employeeCodeToGuid[code] = guid;
            _employeeGuidToShiftsPerDay[guid] = shiftsPerDay;
            _employeeCodeToWeeklyOffDays[code] = weeklyOffDays;
            _employeeCodeToPaidLeaveType[code] = paidLeaveType;
            _employeeCodeToPaidLeaveType[guid] = paidLeaveType;
            _employeeCodeToHolidayMultiplier[code] = holidayMultiplier;
            _employeeCodeToHolidayOvertimeType[code] = holidayOvertimeType;
            if (profileShiftIds.isNotEmpty) {
              final list =
                  _employeeGuidToShiftTemplateIds.putIfAbsent(guid, () => []);
              for (final id in profileShiftIds) {
                if (!list.contains(id)) list.add(id);
              }
            }
          }
        }
      }
    }

    _scheduleDayOffKeys = buildScheduleDayOffKeys(
      widget.workSchedules,
      employeeCodeToGuid: _employeeCodeToGuid,
    );
    _scheduleWorkDayKeys = buildScheduleWorkDayKeys(
      widget.workSchedules,
      employeeCodeToGuid: _employeeCodeToGuid,
    );
    _employeesWithSchedule = buildEmployeesWithSchedule(widget.workSchedules);

    // Merge in legacy assignments from ShiftSalaryLevels (kept as a fallback
    // source so older configurations still resolve correctly).
    for (final ssl in widget.shiftSalaryLevels) {
      final shiftTemplateId = ssl['shiftTemplateId']?.toString() ?? '';
      if (shiftTemplateId.isEmpty) continue;
      final employeeIdsRaw = ssl['employeeIds'];
      List<String> empIds = [];
      if (employeeIdsRaw is String && employeeIdsRaw.isNotEmpty) {
        try {
          final parsed = json.decode(employeeIdsRaw);
          if (parsed is List) {
            empIds = parsed.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      } else if (employeeIdsRaw is List) {
        empIds = employeeIdsRaw.map((e) => e.toString()).toList();
      }
      for (final empGuid in empIds) {
        _employeeGuidToShiftTemplateIds.putIfAbsent(empGuid, () => []);
        if (!_employeeGuidToShiftTemplateIds[empGuid]!
            .contains(shiftTemplateId)) {
          _employeeGuidToShiftTemplateIds[empGuid]!.add(shiftTemplateId);
        }
      }
    }
  }

  /// Parse TimeSpan string "HH:mm:ss" to minutes since midnight
  int _parseTimeSpanToMinutes(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return 0;
    final parts = timeStr.split(':');
    if (parts.length < 2) return 0;
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// Convert DateTime to minutes since midnight
  int _dateTimeToMinutes(DateTime dt) {
    return dt.hour * 60 + dt.minute;
  }

  /// Find the best matching shift for a punch pair among assigned templates.
  Map<String, dynamic>? _findMatchingShift(
    int punchInMinutes,
    List<String> assignedShiftIds, {
    int? punchOutMinutes,
    Set<String> usedShiftIds = const {},
    int pairIndex = 0,
  }) {
    if (assignedShiftIds.isEmpty) return null;
    return findBestMatchingShift(
      punchInMinutes: punchInMinutes,
      punchOutMinutes: punchOutMinutes,
      candidateIds: assignedShiftIds,
      shiftTemplateMap: _shiftTemplateMap,
      usedShiftIds: usedShiftIds,
      pairIndex: pairIndex,
    );
  }

  void _addMissingPunchHint(
    List<_MissingPunchHint> hints,
    _MissingPunchHint hint,
  ) {
    final exists = hints.any((h) =>
        h.shiftName == hint.shiftName && h.isCheckIn == hint.isCheckIn);
    if (!exists) hints.add(hint);
  }

  Map<String, dynamic>? _shiftTemplateForName(String name) {
    final key = name.toLowerCase().trim();
    for (final st in _shiftTemplateMap.values) {
      final n = (st['name']?.toString() ?? '').toLowerCase().trim();
      if (n == key || key.contains(n) || n.contains(key)) return st;
    }
    return null;
  }

  void _enrichMissingPunchHints({
    required List<_MissingPunchHint> hints,
    required bool hasMissingPunch,
    required List<String> missingOutShiftNames,
    required List<DateTime> punchTimes,
    required List<String> candidateIds,
    required int shiftsPerDay,
  }) {
    if (!hasMissingPunch) return;

    for (final name in missingOutShiftNames) {
      final st = _shiftTemplateForName(name);
      if (st != null) {
        final endMin = _parseTimeSpanToMinutes(st['endTime']?.toString());
        _addMissingPunchHint(
          hints,
          _MissingPunchHint(
            shiftName: st['name']?.toString() ?? name,
            isCheckIn: false,
            suggestedTime:
                TimeOfDay(hour: endMin ~/ 60, minute: endMin % 60),
          ),
        );
      }
    }

    if (punchTimes.isEmpty && hints.isEmpty && candidateIds.isNotEmpty) {
      final ordered = candidateIds.toList()
        ..sort((a, b) {
          final sa = _parseTimeSpanToMinutes(
              _shiftTemplateMap[a]?['startTime']?.toString());
          final sb = _parseTimeSpanToMinutes(
              _shiftTemplateMap[b]?['startTime']?.toString());
          return sa.compareTo(sb);
        });
      final limit = shiftsPerDay.clamp(1, ordered.length);
      for (var i = 0; i < limit; i++) {
        final st = _shiftTemplateMap[ordered[i]];
        if (st == null) continue;
        final startMin = _parseTimeSpanToMinutes(st['startTime']?.toString());
        _addMissingPunchHint(
          hints,
          _MissingPunchHint(
            shiftName: st['name']?.toString() ?? 'Ca ${i + 1}',
            isCheckIn: true,
            suggestedTime:
                TimeOfDay(hour: startMin ~/ 60, minute: startMin % 60),
          ),
        );
      }
    }

    if (punchTimes.length.isOdd && hints.isEmpty) {
      final isIn = punchTimes.length.isEven;
      final last = punchTimes.last;
      _addMissingPunchHint(
        hints,
        _MissingPunchHint(
          shiftName: 'Ca hiện tại',
          isCheckIn: isIn,
          suggestedTime: TimeOfDay(hour: last.hour, minute: last.minute),
        ),
      );
    }
  }

  bool _statusHasMissingPunch(String status) =>
      status.contains('Thiếu chấm') ||
      status.contains('Thiếu ra') ||
      status == 'Vắng';

  void _onMissingStatusTap(_DailyShiftRecord record) {
    if (!widget.allowCorrection) return;
    if (!_statusHasMissingPunch(record.status)) return;

    if (record.status == 'Vắng' || record.punchTimes.isEmpty) {
      _showManualPunchDialog(record, isIn: true);
      return;
    }

    if (record.missingPunchHints.isEmpty) {
      _showManualPunchDialog(record);
      return;
    }
    if (record.missingPunchHints.length == 1) {
      final h = record.missingPunchHints.first;
      _showManualPunchDialog(
        record,
        isIn: h.isCheckIn,
        initialTime: h.suggestedTime,
        initialReason:
            'Bổ sung chấm ${h.isCheckIn ? "vào" : "ra"} ca ${h.shiftName}',
        shiftContextLabel: h.shiftName,
      );
      return;
    }
    _showMissingPunchQuickAddDialog(record);
  }

  void _showMissingPunchQuickAddDialog(_DailyShiftRecord record) {
    if (!widget.allowCorrection) return;
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Row(
          children: [
            Icon(Icons.playlist_add, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text(tr('Bổ sung chấm công thiếu'))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('${record.employeeName} · ${DateFormat('dd/MM/yyyy').format(record.date)}'),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                tr(record.status),
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
              const SizedBox(height: 16),
              Text(tr('Chọn gợi ý để thêm nhanh:'),
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 10),
              ...record.missingPunchHints.map((h) {
                final timeStr =
                    '${h.suggestedTime.hour.toString().padLeft(2, '0')}:${h.suggestedTime.minute.toString().padLeft(2, '0')}';
                final label =
                    '${h.isCheckIn ? "Vào" : "Ra"} $timeStr — ${h.shiftName}';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showManualPunchDialog(
                        record,
                        isIn: h.isCheckIn,
                        initialTime: h.suggestedTime,
                        initialReason:
                            'Bổ sung chấm ${h.isCheckIn ? "vào" : "ra"} ca ${h.shiftName}',
                        shiftContextLabel: h.shiftName,
                      );
                    },
                    icon: Icon(
                      h.isCheckIn ? Icons.login : Icons.logout,
                      size: 18,
                      color: h.isCheckIn ? Colors.green : Colors.red,
                    ),
                    label: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(tr(label)),
                    ),
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Đóng')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showManualPunchDialog(record);
            },
            child: Text(tr('Tùy chỉnh khác')),
          ),
        ],
      ),
    );
  }

  /// Check if a date is a weekly off day for a given employee
  bool _isWeeklyOffDay(DateTime date, String employeeCode) {
    final guid = _employeeCodeToGuid[employeeCode];
    final ids = <String>[
      employeeCode,
      if (guid != null && guid.isNotEmpty) guid,
    ];
    if (scheduleKeyHit(_scheduleDayOffKeys, date, ids)) return true;

    final paidLeaveType = _employeeCodeToPaidLeaveType[employeeCode] ??
        _employeeCodeToPaidLeaveType[guid ?? ''] ??
        '';
    if (isSchedulePaidLeaveType(paidLeaveType) ||
        isFlatOffPaidLeaveType(paidLeaveType)) {
      return false;
    }

    final weeklyOff =
        (_employeeCodeToWeeklyOffDays[employeeCode] ?? '').trim();
    if (weeklyOff.isEmpty) return false;
    final weekday = date.weekday; // 1=Mon, 7=Sun
    if (weeklyOff.contains('Sunday') && weekday == DateTime.sunday) return true;
    if (weeklyOff.contains('Saturday') && weekday == DateTime.saturday) {
      return true;
    }
    return false;
  }

  /// Check if a date is a holiday, returns the holiday's salaryRate or null.
  /// API stores GUIDs in `employeeIds`, so also try the employee's GUID.
  double? _getHolidayRate(DateTime date, String employeeCode) {
    final empGuid = _employeeCodeToGuid[employeeCode];
    for (final h in widget.holidays) {
      if (h is! Map<String, dynamic>) continue;
      final holidayDate = DateTime.tryParse(h['date']?.toString() ?? '');
      if (holidayDate == null) continue;
      final isRecurring = h['isRecurring'] == true;
      bool dateMatch = isRecurring
          ? holidayDate.month == date.month && holidayDate.day == date.day
          : holidayDate.year == date.year &&
              holidayDate.month == date.month &&
              holidayDate.day == date.day;
      if (!dateMatch) continue;
      // Check employee scope (combine codes + GUIDs)
      final employeeCodes = h['employeeCodes'] as List?;
      final employeeIds = h['employeeIds'] as List?;
      final scopeList = <String>[
        if (employeeCodes != null)
          ...employeeCodes.map((e) => e?.toString() ?? ''),
        if (employeeIds != null) ...employeeIds.map((e) => e?.toString() ?? ''),
      ].where((s) => s.isNotEmpty).toList();
      if (scopeList.isNotEmpty) {
        final inScope = scopeList
            .any((s) => s == employeeCode || (empGuid != null && s == empGuid));
        if (!inScope) continue;
      }
      return (h['salaryRate'] as num?)?.toDouble() ?? 3.0;
    }
    return null;
  }

  /// Get logical date: if punch time < dayEndTime, it belongs to the previous day
  DateTime _getLogicalDate(DateTime punchTime) =>
      AttendanceDateRangePresets.logicalWorkDay(
        punchTime,
        dayEndHour: widget.dayEndHour,
        dayEndMinute: widget.dayEndMinute,
      );

  /// Unique employees: punches + HR roster (để hiện NV chưa chấm).
  List<_EmployeeOption> get _allEmployees {
    final Map<String, _EmployeeOption> map = {};
    for (final att in widget.attendances) {
      final id = att.employeeId ?? att.enrollNumber ?? 'unknown';
      if (!map.containsKey(id)) {
        map[id] = _EmployeeOption(
          id: id,
          name: att.employeeName?.isNotEmpty == true
              ? att.employeeName!
              : (att.deviceUserName?.isNotEmpty == true
                  ? att.deviceUserName!
                  : '-'),
          code: att.employeeId ?? att.enrollNumber ?? '-',
        );
      }
    }
    final roster = widget.employeesList;
    if (roster != null) {
      for (final emp in roster) {
        final code = emp['employeeCode']?.toString() ?? '';
        final pin = emp['pin']?.toString() ?? '';
        final id = code.isNotEmpty ? code : (pin.isNotEmpty ? pin : '');
        if (id.isEmpty || map.containsKey(id)) continue;
        final name = emp['fullName']?.toString() ??
            emp['name']?.toString() ??
            emp['employeeName']?.toString() ??
            '-';
        map[id] = _EmployeeOption(
          id: id,
          name: name,
          code: code.isNotEmpty ? code : id,
        );
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  DateTimeRange get _selectedDateRange => AttendanceDateRangePresets.resolve(
        _selectedPreset,
        customFrom: widget.fromDate,
        customTo: widget.toDate,
      );

  /// Lọc attendances theo preset và selected employees
  List<Attendance> get _filteredAttendances {
    final range = _selectedDateRange;
    var result = widget.attendances.where((att) {
      final logical = _getLogicalDate(att.punchTime);
      return AttendanceDateRangePresets.isLogicalDayInRange(logical, range);
    }).toList();

    // Filter theo selected employees
    if (_selectedEmployeeIds.isNotEmpty) {
      result = result.where((att) {
        final id = att.employeeId ?? att.enrollNumber ?? 'unknown';
        return _selectedEmployeeIds.contains(id);
      }).toList();
    }

    return result;
  }

  List<_DailyShiftRecord> get _shiftData {
    final fp = _shiftFp;
    if (_cachedShiftData != null && _cachedShiftFp == fp) {
      return _cachedShiftData!;
    }
    final range = _selectedDateRange;
    final computed = computeDailyShiftRecords(
      attendances: _filteredAttendances,
      fromDate: range.start,
      toDate: range.end,
      shiftTemplates: widget.shiftTemplates,
      shiftSalaryLevels: widget.shiftSalaryLevels,
      salaryProfiles: widget.salaryProfiles
          .whereType<Map>()
          .map((p) => Map<String, dynamic>.from(p))
          .toList(),
      employeesList: widget.employeesList
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList(),
      holidays: widget.holidays,
      dayEndHour: widget.dayEndHour,
      dayEndMinute: widget.dayEndMinute,
      minHoursForWorkDay: widget.minHoursForWorkDay,
      decimalWorkDayEnabled: widget.decimalWorkDayEnabled,
      standardWorkHours: widget.standardWorkHours,
      scheduleDayOffKeys: _scheduleDayOffKeys,
    );
    final records = computed
        .map(
          (r) => _DailyShiftRecord(
            employeeId: r.employeeId,
            employeeName: r.employeeName,
            employeeCode: r.employeeCode,
            date: r.date,
            dayOfWeek: r.dayOfWeek,
            punchTimes: r.punchTimes,
            displayPunchTimes: List<DateTime>.from(r.punchTimes),
            attendanceIds: r.attendanceIds,
            shiftNames: r.shiftNames,
            lateMinutes: r.lateMinutes,
            earlyMinutes: r.earlyMinutes,
            overtimeMinutes: r.overtimeMinutes,
            workHours: r.workHours,
            decimalHours: r.decimalHours,
            status: r.status,
            statusColor: r.statusColor,
            workCount: r.workCount,
          ),
        )
        .toList();

    _appendUnpaidAbsentShiftPlaceholders(records);

    // Sort by employee name, then date
    records.sort((a, b) {
      final nameComp = a.employeeName.compareTo(b.employeeName);
      if (nameComp != 0) return nameComp;
      final cmp = a.date.compareTo(b.date);
      return _sortAscending ? cmp : -cmp;
    });

    final result = _shiftFilter == 'all'
        ? records
        : records.where(_recordMatchesShiftStatusFilter).toList();
    _cachedShiftData = result;
    _cachedShiftFp = fp;
    return result;
  }

  void _appendUnpaidAbsentShiftPlaceholders(List<_DailyShiftRecord> records) {
    final roster = widget.employeesList;
    if (roster == null || roster.isEmpty) return;

    final existing = <String>{};
    for (final r in records) {
      final dk = DateFormat('yyyy-MM-dd').format(r.date);
      existing.add('${r.employeeId}|$dk');
      if (r.employeeCode.isNotEmpty) existing.add('${r.employeeCode}|$dk');
    }

    final leaveCtx = _verticalShiftLeaveContext();
    final dates = attendanceDaysInRange(_selectedDateRange);

    for (final emp in roster) {
      final code = emp['employeeCode']?.toString() ?? '';
      final pin = emp['pin']?.toString() ?? '';
      final empId = code.isNotEmpty ? code : pin;
      if (empId.isEmpty) continue;

      if (_selectedEmployeeIds.isNotEmpty &&
          !_selectedEmployeeIds.contains(empId) &&
          !_selectedEmployeeIds.contains(code) &&
          !_selectedEmployeeIds.contains(pin)) {
        continue;
      }

      final name = emp['fullName']?.toString() ??
          emp['name']?.toString() ??
          emp['employeeName']?.toString() ??
          '-';
      final hrCode = code.isNotEmpty ? code : empId;
      final guid = _employeeCodeToGuid[hrCode] ??
          _employeeCodeToGuid[empId] ??
          emp['id']?.toString() ??
          '';
      final paidLeaveType = _employeeCodeToPaidLeaveType[hrCode] ??
          _employeeCodeToPaidLeaveType[empId] ??
          _employeeCodeToPaidLeaveType[guid] ??
          '';
      final scheduleMode = isSchedulePaidLeaveType(paidLeaveType);
      final hasAnySchedule = _employeesWithSchedule.contains(hrCode) ||
          _employeesWithSchedule.contains(empId) ||
          _employeesWithSchedule.contains(pin) ||
          (guid.isNotEmpty && _employeesWithSchedule.contains(guid));

      for (final date in dates) {
        final dateKey = DateFormat('yyyy-MM-dd').format(date);
        if (existing.contains('$empId|$dateKey') ||
            (code.isNotEmpty && existing.contains('$code|$dateKey')) ||
            (pin.isNotEmpty && existing.contains('$pin|$dateKey'))) {
          continue;
        }

        final ids = <String>[
          hrCode,
          empId,
          if (pin.isNotEmpty) pin,
          if (guid.isNotEmpty) guid,
        ];
        // Theo lịch: chỉ tạo Vắng trên ngày xếp ca làm; không có lịch → bỏ qua.
        if (scheduleMode) {
          if (!hasAnySchedule) continue;
          if (scheduleKeyHit(_scheduleDayOffKeys, date, ids)) continue;
          if (!scheduleKeyHit(_scheduleWorkDayKeys, date, ids)) continue;
        }

        final kind = leaveCtx.leaveLookup.classify(
          day: date,
          employeeCode: hrCode,
          employeeUserId: leaveCtx.empUserIdMap[hrCode] ??
              leaveCtx.empUserIdMap[empId],
          hrEmployeeId:
              leaveCtx.hrEmpIdMap[hrCode] ?? leaveCtx.hrEmpIdMap[empId],
          displayEmployeeId: empId,
          isHoliday: _getHolidayRate(date, hrCode) != null ||
              _getHolidayRate(date, empId) != null,
          isWeeklyOff: _isWeeklyOffDay(date, hrCode) ||
              _isWeeklyOffDay(date, empId),
        );
        if (kind != AbsenceCellKind.unpaidAbsent) continue;

        records.add(_DailyShiftRecord(
          employeeId: empId,
          employeeName: name,
          employeeCode: hrCode,
          date: date,
          dayOfWeek: _getDayOfWeekVN(date.weekday),
          punchTimes: const [],
          displayPunchTimes: const [],
          lateMinutes: 0,
          earlyMinutes: 0,
          overtimeMinutes: 0,
          workHours: 0,
          decimalHours: 0,
          status: 'Vắng',
          statusColor: const Color(0xFFEF4444),
          workCount: 0,
        ));
        existing.add('$empId|$dateKey');
      }
    }
  }

  _DailyShiftRecord _placeholderShiftForAbsent({
    required String empId,
    required String empName,
    required String empCode,
    required DateTime date,
  }) {
    return _DailyShiftRecord(
      employeeId: empId,
      employeeName: empName,
      employeeCode: empCode,
      date: date,
      dayOfWeek: _getDayOfWeekVN(date.weekday),
      punchTimes: const [],
      displayPunchTimes: const [],
      lateMinutes: 0,
      earlyMinutes: 0,
      overtimeMinutes: 0,
      workHours: 0,
      decimalHours: 0,
      status: 'Vắng',
      statusColor: const Color(0xFFEF4444),
      workCount: 0,
    );
  }

  String _getDayOfWeekVN(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'T2';
      case DateTime.tuesday:
        return 'T3';
      case DateTime.wednesday:
        return 'T4';
      case DateTime.thursday:
        return 'T5';
      case DateTime.friday:
        return 'T6';
      case DateTime.saturday:
        return 'T7';
      case DateTime.sunday:
        return 'CN';
      default:
        return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _shiftData;
    final range = _selectedDateRange;

    // Calculate totals for stats cards
    int totalLate = records.where((r) => r.lateMinutes > 0).length;
    int totalEarly = records.where((r) => r.earlyMinutes > 0).length;
    int totalOT = records.where((r) => r.overtimeMinutes > 0).length;
    double totalHours = records.fold(0.0, (sum, r) => sum + r.workHours);
    int totalRecords = records.length;
    final uniqueEmployees = records.map((r) => r.employeeId).toSet().length;

    final isMobileLayout = MediaQuery.sizeOf(context).width < 600;

    Widget buildOverviewSection() {
      return HrmCollapsibleOverview(
        expanded: _showOverviewPanel,
        onToggle: () =>
            setState(() => _showOverviewPanel = !_showOverviewPanel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatsRow(totalRecords, uniqueEmployees, totalHours,
                totalLate, totalEarly, totalOT),
            const SizedBox(height: 10),
            _buildFilters(range),
          ],
        ),
      );
    }

    Widget buildPageHeader() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.mobileLeadingSections != null) ...[
            ...widget.mobileLeadingSections!,
            const SizedBox(height: 12),
          ],
          buildOverviewSection(),
          const SizedBox(height: 12),
        ],
      );
    }

    if (isMobileLayout) {
      final useVerticalLayout = preferMobileVerticalAttendanceView(
        userRole: Provider.of<AuthProvider>(context, listen: false).userRole,
        uniqueEmployeeCount: uniqueEmployees,
      );
      return CustomScrollView(
        controller: _listScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(child: buildPageHeader()),
          ),
          if (records.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _buildEmptyTableCard()),
            )
          else if (useVerticalLayout)
            ..._buildMobileVerticalShiftSlivers(records)
          else
            ..._buildMobileEmployeeShiftSummarySlivers(records),
        ],
      );
    }

    return CustomScrollView(
      controller: _listScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: buildPageHeader(),
          ),
        ),
        ..._buildTableSlivers(records),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverToBoxAdapter(child: SizedBox(height: 8)),
        ),
      ],
    );
  }

  Widget _buildFilters(DateTimeRange range) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final datePreset = _buildDropdown<String>(
      value: _selectedPreset,
      items: [
        DropdownMenuItem(value: 'today', child: Text(tr('Hôm nay'))),
        DropdownMenuItem(value: 'yesterday', child: Text(tr('Hôm qua'))),
        DropdownMenuItem(value: 'week', child: Text(tr('Tuần này'))),
        DropdownMenuItem(value: 'lastWeek', child: Text(tr('Tuần trước'))),
        DropdownMenuItem(value: 'month', child: Text(tr('Tháng này'))),
        DropdownMenuItem(value: 'lastMonth', child: Text(tr('Tháng trước'))),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() {
            _selectedPreset = v;
            _currentPage = 0;
          });
          widget.onDateRangeChanged?.call(v);
        }
      },
      icon: Icons.calendar_today,
      width: isMobile ? 120 : null,
    );

    final dateRange = _buildDateRangeDisplay(range, compact: isMobile);

    final employeeFilter = _buildEmployeeFilter();

    final shiftFilter = _buildDropdown<String>(
      value: _shiftFilter,
      items: [
        DropdownMenuItem(value: 'all', child: Text(tr('Tất cả trạng thái'))),
        DropdownMenuItem(value: 'valid', child: Text(tr('Hợp lệ'))),
        DropdownMenuItem(value: 'late', child: Text(tr('Đi trễ'))),
        DropdownMenuItem(value: 'early', child: Text(tr('Về sớm'))),
        DropdownMenuItem(
            value: 'late_early', child: Text(tr('Đi trễ & Về sớm'))),
        DropdownMenuItem(value: 'ot', child: Text(tr('Tăng ca'))),
        DropdownMenuItem(value: 'missing', child: Text(tr('Thiếu chấm'))),
        DropdownMenuItem(value: 'complete', child: Text(tr('Đủ chấm công'))),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() {
            _shiftFilter = v;
            _currentPage = 0;
          });
        }
      },
      icon: Icons.filter_list_rounded,
      width: isMobile ? 168 : null,
    );

    final summaryChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_view_day,
              color: Theme.of(context).primaryColor, size: 16),
          const SizedBox(width: 6),
          Text(tr('Theo ca · ${_shiftData.length} bản ghi'),
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                Row(children: [summaryChip]),
                ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      datePreset,
                      const SizedBox(width: 8),
                      Expanded(child: dateRange),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: employeeFilter),
                      const SizedBox(width: 8),
                      Expanded(child: shiftFilter),
                    ],
                  ),
                ],
              ],
            )
          : Row(
              children: [
                Expanded(child: datePreset),
                const SizedBox(width: 12),
                Expanded(child: dateRange),
                const SizedBox(width: 12),
                Expanded(child: employeeFilter),
                const SizedBox(width: 12),
                Expanded(child: shiftFilter),
                const SizedBox(width: 12),
                summaryChip,
              ],
            ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    required IconData icon,
    double? width,
  }) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodyMedium?.color),
          dropdownColor: Theme.of(context).cardColor,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item.value,
                    child: Row(
                      children: [
                        Icon(icon, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: DefaultTextStyle(
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color),
                            overflow: TextOverflow.ellipsis,
                            child: item.child,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          selectedItemBuilder: (context) => items
              .map((item) => Row(
                    children: [
                      Icon(icon,
                          size: 14, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DefaultTextStyle(
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color),
                          overflow: TextOverflow.ellipsis,
                          child: item.child,
                        ),
                      ),
                    ],
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateRangeDisplay(DateTimeRange range, {bool compact = false}) {
    final fmt = compact ? DateFormat('dd/MM/yy') : DateFormat('dd/MM/yyyy');
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.date_range,
              size: 14, color: Theme.of(context).primaryColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              tr('${fmt.format(range.start)} \u2013 ${fmt.format(range.end)}'),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeFilter() {
    final employees = _allEmployees;
    final selectedCount = _selectedEmployeeIds.length;

    return InkWell(
      onTap: () => _showEmployeeSelectionDialog(employees),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 100),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selectedCount > 0
                ? Theme.of(context).primaryColor
                : const Color(0xFFE4E4E7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people,
                size: 14,
                color: selectedCount > 0
                    ? Theme.of(context).primaryColor
                    : Colors.grey[500]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tr(selectedCount == 0
                    ? 'Tất cả nhân viên (${employees.length})'
                    : '$selectedCount nhân viên đã chọn'),
                style: TextStyle(
                  fontSize: 12,
                  color: selectedCount > 0
                      ? Theme.of(context).primaryColor
                      : Colors.grey[600],
                  fontWeight:
                      selectedCount > 0 ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selectedCount > 0) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() {
                  _selectedEmployeeIds = {};
                  _currentPage = 0;
                }),
                child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  void _showEmployeeSelectionDialog(List<_EmployeeOption> employees) {
    final tempSelected = Set<String>.from(_selectedEmployeeIds);
    String searchText = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchText.isEmpty
                ? employees
                : employees
                    .where((e) =>
                        e.name
                            .toLowerCase()
                            .contains(searchText.toLowerCase()) ||
                        e.code.toLowerCase().contains(searchText.toLowerCase()))
                    .toList();

            return ScrollableAlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.people, color: Colors.blue, size: 22),
                  const SizedBox(width: 8),
                  Text(tr('Chọn nhân viên'),
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      if (tempSelected.length == employees.length) {
                        setDialogState(() => tempSelected.clear());
                      } else {
                        setDialogState(() =>
                            tempSelected.addAll(employees.map((e) => e.id)));
                      }
                    },
                    child: Text(
                      tr(tempSelected.length == employees.length
                          ? 'Bỏ chọn tất cả'
                          : 'Chọn tất cả'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              content: SizedBox(
                width: math
                    .min(380, MediaQuery.of(context).size.width - 32)
                    .toDouble(),
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: tr('Tìm nhân viên...'),
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) => setDialogState(() => searchText = v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text(tr('Đã chọn: ${tempSelected.length}/${employees.length}'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final emp = filtered[index];
                          final isSelected = tempSelected.contains(emp.id);
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  tempSelected.remove(emp.id);
                                } else {
                                  tempSelected.add(emp.id);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context)
                                        .primaryColor
                                        .withValues(alpha: 0.08)
                                    : null,
                                border: Border(
                                    bottom: BorderSide(
                                        color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 20,
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 10),
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(
                                        tr(emp.name.isNotEmpty
                                            ? emp.name[0].toUpperCase()
                                            : '?'),
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(tr(emp.name),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                        Text(tr(emp.code),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Hủy')),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _selectedEmployeeIds = tempSelected;
                      _currentPage = 0;
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Áp dụng')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManualPunchDialog(
    _DailyShiftRecord record, {
    bool? isIn,
    TimeOfDay? initialTime,
    String? initialReason,
    String? shiftContextLabel,
  }) {
    if (!widget.allowCorrection) return;
    DateTime selectedDate = record.date;
    final resolvedIsIn =
        isIn ?? (record.punchTimes.length).isEven;
    TimeOfDay selectedTime = initialTime ?? TimeOfDay.now();
    final int punchIndex = record.punchTimes.length + 1;
    final reasonController =
        TextEditingController(text: tr(initialReason ?? ''));
    final canFine = Provider.of<PermissionProvider>(context, listen: false)
        .canCreate('PenaltyTickets');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.blue),
              SizedBox(width: 8),
              Text(tr('Thêm chấm công')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thông tin nhân viên
                Card(
                  color: Colors.grey.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Nhân viên: ${record.employeeName}'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(tr('Mã NV: ${record.employeeCode}')),
                        Text(tr('${tr('Ngày: ')}${DateFormat('dd/MM/yyyy').format(selectedDate)}')),
                        if (shiftContextLabel != null &&
                            shiftContextLabel.isNotEmpty)
                          Text(tr('Ca: $shiftContextLabel'),
                              style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500)),
                        Text(tr('Lần chấm: $punchIndex (${resolvedIsIn ? "Vào" : "Ra"})')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn ngày (cho ca qua đêm)
                Text(tr('Ngày chấm công:'),
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: record.date,
                      lastDate: record.date.add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(tr(DateFormat('dd/MM/yyyy').format(selectedDate)),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        if (selectedDate != record.date) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(tr('Ngày hôm sau'),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade800)),
                          ),
                        ],
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn giờ
                Text(tr('Chọn giờ chấm công:'),
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                        context: ctx, initialTime: selectedTime);
                    if (picked != null) {
                      setDialogState(() => selectedTime = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(resolvedIsIn ? Icons.login : Icons.logout,
                            color: resolvedIsIn ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          tr('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const Icon(Icons.access_time),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AttendanceCorrectionReasonField(
                  controller: reasonController,
                  kind: AttendanceCorrectionReasonKind.add,
                  employeeName: record.employeeName,
                  employeeCode: record.employeeCode,
                  date: selectedDate,
                  timeText:
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  punchLabel: resolvedIsIn ? 'Vào' : 'Ra',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            if (canFine)
              OutlinedButton.icon(
                icon: const Icon(Icons.gavel, size: 16, color: Colors.orange),
                label: Text(tr('Thêm công và phạt'),
                    style: TextStyle(color: Colors.orange)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange)),
                onPressed: () async {
                  if (reasonController.text.trim().isEmpty) {
                    NotificationOverlayManager().showError(
                        title: 'Lỗi', message: tr('Vui lòng nhập lý do'));
                    return;
                  }
                  final timeStr =
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                  final api = ApiService();
                  final result = await api.createAttendanceCorrection(
                    action: 0,
                    pin: record.employeeCode,
                    employeeName: record.employeeName,
                    employeeCode: record.employeeCode,
                    newDate: DateTime(
                      selectedDate.year,
                      selectedDate.month,
                      selectedDate.day,
                    ),
                    newTime: '$timeStr:00',
                    newType: resolvedIsIn ? 'CheckIn' : 'CheckOut',
                    reason: reasonController.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (result['isSuccess'] != true) {
                    if (mounted) {
                      NotificationOverlayManager().showError(
                          title: 'Lỗi',
                          message: attendanceCorrectionErrorMessage(result));
                    }
                    return;
                  }
                  _notifyDataChanged();
                  final fined = await _createForgotCheckPenaltyTicket(
                    employeeCode: record.employeeCode,
                    employeeName: record.employeeName,
                    violationDate: selectedDate,
                  );
                  if (mounted) {
                    NotificationOverlayManager().showSuccess(
                        title: 'Thành công',
                        message: fined
                            ? 'Đã bổ sung chấm công và tạo phiếu phạt quên chấm công'
                            : 'Đã bổ sung chấm công (chưa tạo được phiếu phạt)');
                  }
                },
              ),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: Text(tr('Xác nhận')),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi', message: tr('Vui lòng nhập lý do'));
                  return;
                }
                final timeStr =
                    '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                final api = ApiService();
                final result = await api.createAttendanceCorrection(
                  action: 0,
                  pin: record.employeeCode,
                  employeeName: record.employeeName,
                  employeeCode: record.employeeCode,
                  newDate: DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                  ),
                  newTime: '$timeStr:00',
                  newType: resolvedIsIn ? 'CheckIn' : 'CheckOut',
                  reason: reasonController.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (result['isSuccess'] == true && mounted) {
                  final auth = Provider.of<AuthProvider>(context, listen: false);
                  final perm =
                      Provider.of<PermissionProvider>(context, listen: false);
                  final expectedDirect = canDirectAttendanceCorrection(
                    role: auth.user?.role,
                    allowManualSetting: true,
                    permissions: perm,
                  );
                  NotificationOverlayManager().showSuccess(
                      title: 'Thành công',
                      message: attendanceCorrectionSuccessMessage(
                        result,
                        expectedDirect: expectedDirect,
                      ));
                  _notifyDataChanged();
                } else if (mounted) {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi',
                      message: attendanceCorrectionErrorMessage(result));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Tạo phiếu phạt "Quên chấm công" theo mức phạt trong Thiết lập phạt, cho
  /// nhân viên [employeeCode] vào ngày [violationDate]. Dùng cho nút "Thêm
  /// công và phạt" khi bổ sung chấm công thủ công. Trả về `true` nếu tạo
  /// (và duyệt, nếu có quyền) thành công.
  Future<bool> _createForgotCheckPenaltyTicket({
    required String employeeCode,
    required String employeeName,
    required DateTime violationDate,
  }) async {
    try {
      final employeeId = _employeeCodeToGuid[employeeCode];
      if (employeeId == null || employeeId.isEmpty) {
        NotificationOverlayManager().showWarning(
            title: 'Không tạo được phiếu phạt',
            message: tr('Không xác định được hồ sơ nhân viên để tạo phiếu phạt'));
        return false;
      }

      final api = ApiService();
      final settingsResult = await api.getPenaltySettings();
      final amount = double.tryParse(
              (settingsResult['data']?['forgotCheckPenalty'] ?? 0)
                  .toString()) ??
          0;
      if (amount <= 0) {
        NotificationOverlayManager().showWarning(
            title: 'Không tạo được phiếu phạt',
            message: tr('Mức phạt "Quên chấm công" chưa được cấu hình (0đ). Vui lòng vào Thiết lập phạt để cài đặt.'));
        return false;
      }

      final createResult = await api.createPenaltyTicket({
        'employeeId': employeeId,
        'type': 'ForgotCheck',
        'amount': amount,
        'violationDate': violationDate.toIso8601String(),
        'description': 'Quên chấm công - bổ sung chấm công thủ công ($employeeName)',
      });
      if (createResult['isSuccess'] != true) {
        NotificationOverlayManager().showWarning(
            title: 'Không tạo được phiếu phạt',
            message: createResult['message'] ?? 'Có lỗi xảy ra');
        return false;
      }

      final ticketId = createResult['data']?['id']?.toString();
      final canApprovePenalty = mounted &&
          Provider.of<PermissionProvider>(context, listen: false)
              .canApprove('PenaltyTickets');
      if (ticketId != null && canApprovePenalty) {
        await api.approvePenaltyTicket(ticketId);
      }
      return true;
    } catch (e) {
      NotificationOverlayManager()
          .showWarning(title: 'Không tạo được phiếu phạt', message: e.toString());
      return false;
    }
  }

  /// Summary totals bar
  String _formatHoursMinutes(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '${h}h${m > 0 ? '${m}p' : ''}';
  }

  double _travelHoursForShiftRecord(_DailyShiftRecord r) {
    if (!isEmployeeTravelEligible(
      eligibleKeys: widget.travelEligibleEmployeeKeys,
      employeeId: r.employeeId,
      employeeCode: r.employeeCode,
    )) {
      return 0;
    }
    return lookupTravelHoursForDay(
      widget.travelHoursByEmployeeDateKey,
      date: r.date,
      employeeId: r.employeeId,
      employeeCode: r.employeeCode,
    );
  }

  double _travelHoursTotalForShiftEmployee({
    required String employeeId,
    required String employeeCode,
  }) {
    if (!isEmployeeTravelEligible(
      eligibleKeys: widget.travelEligibleEmployeeKeys,
      employeeId: employeeId,
      employeeCode: employeeCode,
    )) {
      return 0;
    }
    return lookupTravelHoursTotal(
      widget.travelHoursByEmployeeKey,
      employeeId: employeeId,
      employeeCode: employeeCode,
    );
  }

  Widget _buildTravelHoursCell(double hours, {bool bold = false}) {
    if (hours <= 0) {
      return Text(tr('—'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)));
    }
    return Text(
      tr(_formatHoursMinutes(hours)),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: HrmPageChrome.chipLight,
      ),
    );
  }

  Widget _buildColumnHeaderWithTotal(String title, String total, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(tr(title),
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: Color(0xFF71717A))),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(tr(total),
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }

  Widget _buildStatsRow(int totalRows, int uniqueEmployees, double totalHours,
      int totalLate, int totalEarly, int totalOT) {
    final cards = [
      _buildModernStatCard(
          'Bản ghi', '$totalRows', Icons.list_alt, HrmPageChrome.primaryNavy),
      _buildModernStatCard('Nhân viên', '$uniqueEmployees',
          Icons.people_outline, HrmPageChrome.primaryNavy),
      _buildModernStatCard('Tổng giờ', '${totalHours.toStringAsFixed(1)}h',
          Icons.schedule, HrmPageChrome.primaryNavy),
      _buildModernStatCard('Đi trễ', '$totalLate', Icons.timer_off_outlined,
          HrmPageChrome.chipLight),
      _buildModernStatCard(
          'Về sớm', '$totalEarly', Icons.exit_to_app, const Color(0xFFEF4444)),
      _buildModernStatCard(
          'Tăng ca', '$totalOT', Icons.more_time, HrmPageChrome.primaryNavy),
    ];
    final isMobile = MediaQuery.of(context).size.width < 768;
    if (isMobile) {
      // 3 columns x 2 rows
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 8),
              Expanded(child: cards[1]),
              const SizedBox(width: 8),
              Expanded(child: cards[2]),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: cards[3]),
              const SizedBox(width: 8),
              Expanded(child: cards[4]),
              const SizedBox(width: 8),
              Expanded(child: cards[5]),
            ],
          ),
        ],
      );
    }
    return Row(
      children: cards
          .map((c) => Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: c)))
          .toList(),
    );
  }

  Widget _buildModernStatCard(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(value),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: color),
                    overflow: TextOverflow.ellipsis),
                Text(tr(label),
                    style:
                        const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRecordDetail(_DailyShiftRecord record) {
    final dateStr = DateFormat('dd/MM/yyyy').format(record.date);
    final dayOfWeek = _getDayOfWeekVN(record.date.weekday);

    showAppSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      color: record.statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Center(
                      child: Text(tr(dayOfWeek.substring(0, 2)),
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: record.statusColor))),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tr(record.employeeName),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(tr('${record.employeeCode} · $dayOfWeek $dateStr'),
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 13)),
                    ])),
                // Badge ngắn (≤ 14 ký tự) thì giữ ở header. Badge dài ("Thiếu
                // ra Ca chiều", "Đi trễ • Thiếu ra Ca sáng") sẽ xuống dòng
                // riêng phía dưới để không chèn ép tên + ngày.
                if (record.status.length <= 14)
                  _buildStatusBadge(record.status, record.statusColor,
                      record: record),
              ]),
              if (record.status.length > 14) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildStatusBadge(record.status, record.statusColor,
                      record: record),
                ),
              ],
              if (_statusHasMissingPunch(record.status) &&
                  widget.allowCorrection &&
                  record.missingPunchHints.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: record.missingPunchHints.map((h) {
                    final t =
                        '${h.suggestedTime.hour.toString().padLeft(2, '0')}:${h.suggestedTime.minute.toString().padLeft(2, '0')}';
                    return ActionChip(
                      avatar: Icon(
                        h.isCheckIn ? Icons.login : Icons.logout,
                        size: 16,
                        color: h.isCheckIn ? Colors.green : Colors.red,
                      ),
                      label: Text(tr('Thêm ${h.isCheckIn ? "vào" : "ra"} $t — ${h.shiftName}')),
                      onPressed: () => _showManualPunchDialog(
                        record,
                        isIn: h.isCheckIn,
                        initialTime: h.suggestedTime,
                        initialReason:
                            'Bổ sung chấm ${h.isCheckIn ? "vào" : "ra"} ca ${h.shiftName}',
                        shiftContextLabel: h.shiftName,
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // Shift names
              if (record.shiftNames.isNotEmpty) ...[
                _detailRow('Ca làm việc', record.shiftNames.join(', ')),
                const SizedBox(height: 10),
              ],
              // Punch times
              _detailLabel('Giờ chấm công'),
              const SizedBox(height: 6),
              if (record.punchTimes.isEmpty && !widget.allowCorrection)
                Text(tr('Không có dữ liệu'),
                    style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13))
              else ...[
                ...List.generate(
                  record.punchTimes.isEmpty ? 1 : record.punchTimes.length,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: (i.isEven ? Colors.green : Colors.orange)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            i.isEven ? Icons.login : Icons.logout,
                            size: 15,
                            color: i.isEven ? Colors.green : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(tr('Lần ${i + 1} (${i.isEven ? "Vào" : "Ra"})'),
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ),
                        _buildPunchTimeCell(record, i),
                      ],
                    ),
                  ),
                ),
                if (widget.allowCorrection)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Icon(
                            record.punchTimes.length.isEven
                                ? Icons.login
                                : Icons.logout,
                            size: 15,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(tr('Lần ${record.punchTimes.length + 1} (${record.punchTimes.length.isEven ? "Vào" : "Ra"})'),
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey.shade700),
                          ),
                        ),
                        _buildPunchTimeCell(record, record.punchTimes.length),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // Summary grid
              Row(children: [
                Expanded(
                    child: _detailSummaryCard(
                        'Đi trễ', '${record.lateMinutes}P', Colors.orange)),
                const SizedBox(width: 8),
                Expanded(
                    child: _detailSummaryCard(
                        'Về sớm', '${record.earlyMinutes}P', Colors.red)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _detailSummaryCard('Tăng ca',
                        '${record.overtimeMinutes}P', Colors.purple)),
                const SizedBox(width: 8),
                Expanded(
                    child: _detailSummaryCard('Tổng giờ',
                        _formatHoursMinutes(record.workHours), Colors.green)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: _detailSummaryCard('Giờ (thập phân)',
                        record.decimalHours.toStringAsFixed(2), Colors.teal)),
                const SizedBox(width: 8),
                Expanded(
                    child: _detailSummaryCard(
                        'Công',
                        record.workCount == record.workCount.roundToDouble()
                            ? '${record.workCount.toInt()}'
                            : record.workCount.toStringAsFixed(2),
                        Colors.blue)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(children: [
      Text(tr(label),
          style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
      const Spacer(),
      Text(tr(value),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    ]);
  }

  Widget _detailLabel(String label) {
    return Text(tr(label),
        style: const TextStyle(
            color: Color(0xFF71717A),
            fontSize: 13,
            fontWeight: FontWeight.w500));
  }

  Widget _detailSummaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(label),
            style:
                TextStyle(color: color.withValues(alpha: 0.7), fontSize: 11)),
        const SizedBox(height: 2),
        Text(tr(value),
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 15, color: color)),
      ]),
    );
  }

  Widget _buildShiftDeckItem(_DailyShiftRecord record) {
    final dayOfWeek = _getDayOfWeekVN(record.date.weekday);
    final dateStr = DateFormat('dd/MM/yyyy').format(record.date);
    // Status dài (vd "Đi trễ • Thiếu ra Ca chiều", "Thiếu ra ca lúc 13:15")
    // sẽ xuống dòng riêng bên dưới để không chèn ép tên + chevron.
    final isLongStatus = record.status.length > 14;

    final statusBadge = _buildStatusBadge(
      record.status,
      record.statusColor,
      record: record,
    );

    return InkWell(
      onTap: () => _showRecordDetail(record),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: record.statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Center(
                child: Text(tr(dayOfWeek.substring(0, 2)),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: record.statusColor))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(record.employeeName),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                  tr([
                    dateStr,
                    record.shiftNames.join(', '),
                    '${record.workHours.toStringAsFixed(1)}h'
                  ].where((s) => s.isNotEmpty).join(' \u00b7 ')),
                  style:
                      const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (isLongStatus) ...[
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerLeft, child: statusBadge),
              ],
            ]),
          ),
          if (!isLongStatus) ...[
            statusBadge,
            const SizedBox(width: 4),
          ],
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  /// Pagination bar
  Widget _buildPaginationBar(
    int totalRows,
    int totalPages, {
    VoidCallback? onOpenFullscreen,
  }) {
    final startRow = totalRows == 0 ? 0 : _currentPage * _rowsPerPage + 1;
    final endRow = ((_currentPage + 1) * _rowsPerPage).clamp(0, totalRows);
    final primary = Theme.of(context).primaryColor;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final infoWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(tr('Hiển thị $startRow-$endRow / $totalRows'),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF16A34A)),
      ),
    );

    final rowsPerPageWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('Số dòng:'),
            style: TextStyle(fontSize: 12, color: Color(0xFFA1A1AA))),
        const SizedBox(width: 6),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            border: Border.all(color: const Color(0xFFE4E4E7)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rowsPerPage,
              isDense: true,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodyMedium?.color),
              items: [
                DropdownMenuItem(value: 20, child: Text(tr('20'))),
                DropdownMenuItem(value: 50, child: Text(tr('50'))),
                DropdownMenuItem(value: 100, child: Text(tr('100'))),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _rowsPerPage = v;
                    _currentPage = 0;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );

    final navWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPageNavBtn(Icons.first_page, _currentPage > 0,
            () => setState(() => _currentPage = 0)),
        const SizedBox(width: 4),
        _buildPageNavBtn(Icons.chevron_left, _currentPage > 0,
            () => setState(() => _currentPage--)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            tr('${_currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}'),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages - 1,
            () => setState(() => _currentPage++)),
        const SizedBox(width: 4),
        _buildPageNavBtn(Icons.last_page, _currentPage < totalPages - 1,
            () => setState(() => _currentPage = totalPages - 1)),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: isMobile
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                infoWidget,
                rowsPerPageWidget,
                navWidget,
              ],
            )
          : Row(
              children: [
                infoWidget,
                const SizedBox(width: 16),
                rowsPerPageWidget,
                if (onOpenFullscreen != null) ...[
                  const SizedBox(width: 8),
                  Tooltip(
                    message: tr('Xem toàn màn hình'),
                    child: Material(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: onOpenFullscreen,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fullscreen,
                                  size: 18, color: HrmPageChrome.chipMid),
                              SizedBox(width: 6),
                              Text(tr('Toàn màn hình'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: HrmPageChrome.chipMid,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                navWidget,
              ],
            ),
    );
  }

  Widget _buildPageNavBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: enabled ? const Color(0xFFF1F5F9) : const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon,
              size: 18,
              color:
                  enabled ? const Color(0xFF52525B) : const Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  /// Dialog sửa giờ chấm công
  void _showEditPunchDialog(_DailyShiftRecord record, int punchIndex) {
    if (!widget.allowCorrection) return;
    if (punchIndex >= record.punchTimes.length) return;
    final originalTime = record.punchTimes[punchIndex];
    final preferredId = punchIndex < record.attendanceIds.length
        ? record.attendanceIds[punchIndex]
        : null;
    final attendanceId = resolveAttendanceIdForPunch(
      attendances: widget.attendances,
      employeeKey: record.employeeId,
      employeeCode: record.employeeCode,
      workDate: record.date,
      punchTime: originalTime,
      preferredId: preferredId,
      logicalDayOf: _getLogicalDate,
    );
    DateTime selectedDate =
        DateTime(originalTime.year, originalTime.month, originalTime.day);
    TimeOfDay selectedTime =
        TimeOfDay(hour: originalTime.hour, minute: originalTime.minute);
    final bool isIn = punchIndex.isEven;
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.orange),
              SizedBox(width: 8),
              Text(tr('Sửa/Xóa chấm công')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thông tin nhân viên
                Card(
                  color: Colors.grey.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Nhân viên: ${record.employeeName}'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(tr('Mã NV: ${record.employeeCode}')),
                        Text(tr('${tr('Ngày: ')}${DateFormat('dd/MM/yyyy').format(record.date)}')),
                        Text(tr('Lần chấm: ${punchIndex + 1} (${isIn ? "Vào" : "Ra"})')),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(tr('Giờ hiện tại: ')),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isIn ? Colors.green : Colors.red)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tr(DateFormat('HH:mm').format(originalTime)),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isIn ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn ngày
                Text(tr('Ngày:'),
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: record.date,
                      lastDate: record.date.add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(tr(DateFormat('dd/MM/yyyy').format(selectedDate)),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        if (selectedDate !=
                            DateTime(record.date.year, record.date.month,
                                record.date.day)) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(tr('Ngày hôm sau'),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade800)),
                          ),
                        ],
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn giờ mới
                Text(tr('Sửa thành giờ mới:'),
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                        context: ctx, initialTime: selectedTime);
                    if (picked != null) {
                      setDialogState(() => selectedTime = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(isIn ? Icons.login : Icons.logout,
                            color: isIn ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          tr('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const Icon(Icons.access_time),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AttendanceCorrectionReasonField(
                  controller: reasonController,
                  kind: AttendanceCorrectionReasonKind.edit,
                  employeeName: record.employeeName,
                  employeeCode: record.employeeCode,
                  date: record.date,
                  originalTimeText: DateFormat('HH:mm').format(originalTime),
                  timeText:
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  punchLabel: isIn ? 'Vào' : 'Ra',
                ),
              ],
            ),
          ),
          actions: [
            // Nút xóa
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _confirmDeletePunch(record, punchIndex);
                });
              },
              icon: const Icon(Icons.delete, color: Colors.red),
              label: Text(tr('Xóa'), style: TextStyle(color: Colors.red)),
            ),
            const SizedBox(width: 16),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: Text(tr('Lưu')),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  NotificationOverlayManager().showError(
                      title: 'Lỗi', message: tr('Vui lòng nhập lý do'));
                  return;
                }
                final t =
                    '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
                final api = ApiService();
                final result = await api.createAttendanceCorrection(
                  action: 1,
                  pin: record.employeeCode,
                  employeeName: record.employeeName,
                  employeeCode: record.employeeCode,
                  attendanceId: attendanceId,
                  oldDate: DateTime(
                    originalTime.year,
                    originalTime.month,
                    originalTime.day,
                  ),
                  oldTime: correctionTimeOnly(originalTime),
                  newDate: DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                  ),
                  newTime: t,
                  newType: isIn ? 'CheckIn' : 'CheckOut',
                  reason: reasonController.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (result['isSuccess'] == true && mounted) {
                  final auth = Provider.of<AuthProvider>(ctx, listen: false);
                  final perm =
                      Provider.of<PermissionProvider>(ctx, listen: false);
                  final expectedDirect = canDirectAttendanceCorrection(
                    role: auth.user?.role,
                    allowManualSetting: true,
                    permissions: perm,
                  );
                  NotificationOverlayManager().showSuccess(
                      title: 'Thành công',
                      message: attendanceCorrectionSuccessMessage(
                        result,
                        expectedDirect: expectedDirect,
                      ));
                  _notifyDataChanged();
                } else if (mounted) {
                  final msg = result['message']?.toString();
                  NotificationOverlayManager().showError(
                      title: 'Lỗi',
                      message: msg != null && msg.isNotEmpty
                          ? msg
                          : 'Cập nhật thất bại');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePunch(
      _DailyShiftRecord record, int punchIndex) async {
    if (punchIndex >= record.punchTimes.length) return;
    final punchTime = record.punchTimes[punchIndex];
    final rowId = punchIndex < record.attendanceIds.length
        ? record.attendanceIds[punchIndex]
        : null;
    if (rowId != null && rowId.startsWith('manual_')) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: tr('Bản ghi chỉ có trên máy (thêm thủ công), không có trên server. Tải lại dữ liệu.'),
      );
      return;
    }

    Attendance? matchedLog;
    if (rowId != null && isValidAttendanceGuid(rowId)) {
      for (final a in widget.attendances) {
        if (a.id == rowId) {
          matchedLog = a;
          break;
        }
      }
    }
    matchedLog ??= findAttendanceForPunch(
      attendances: widget.attendances,
      employeeKey: record.employeeId,
      employeeCode: record.employeeCode,
      workDate: record.date,
      punchTime: punchTime,
      preferredId: rowId,
      logicalDayOf: _getLogicalDate,
    );

    final preferredId = matchedLog?.id ?? rowId;
    final punchRef = preferredId != null && isValidAttendanceGuid(preferredId)
        ? AttendancePunchRef(
            id: preferredId,
            pin: matchedLog?.pin?.trim().isNotEmpty == true
                ? matchedLog!.pin!.trim()
                : null,
          )
        : resolveAttendancePunchRef(
            attendances: widget.attendances,
            employeeKey: record.employeeId,
            employeeCode: record.employeeCode,
            workDate: record.date,
            punchTime: punchTime,
            preferredId: preferredId,
            logicalDayOf: _getLogicalDate,
          );

    final actualPunchTime = matchedLog?.punchTime ?? punchTime;
    final devicePin = matchedLog?.pin?.trim();
    final bool isIn = punchIndex.isEven;

    final reason = await showAttendanceDeleteConfirmDialog(
      context: context,
      employeeName: record.employeeName,
      employeeCode: record.employeeCode,
      date: record.date,
      punchIndex: punchIndex + 1,
      punchTime: punchTime,
      isIn: isIn,
      directApply: true,
    );
    if (reason == null || !mounted) return;

    if (punchRef == null || !isValidAttendanceGuid(punchRef.id)) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: tr('Không tìm thấy bản ghi trên server (ngày này có thể chưa có chấm công). Kéo xuống để tải lại.'),
      );
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final expectedDirect = canDirectAttendanceCorrection(
      role: auth.user?.role,
      allowManualSetting: true,
      permissions: perm,
    );
    final api = ApiService();
    final result = await submitAttendanceDelete(
      api: api,
      expectedDirect: expectedDirect,
      attendanceId: punchRef.id,
      createCorrection: () => api.createAttendanceCorrection(
        action: 2,
        pin: devicePin ?? punchRef.pin ?? record.employeeCode,
        employeeName: record.employeeName,
        employeeCode: record.employeeCode,
        attendanceId: punchRef.id,
        oldDate: DateTime(
          actualPunchTime.year,
          actualPunchTime.month,
          actualPunchTime.day,
        ),
        oldTime: correctionTimeOnly(actualPunchTime),
        reason: reason,
      ),
    );
    if (result['isSuccess'] == true && mounted) {
      NotificationOverlayManager().showSuccess(
          title: 'Thành công',
          message: result['directDelete'] == true
              ? 'Đã xóa chấm công'
              : attendanceCorrectionSuccessMessage(
                  result,
                  expectedDirect: expectedDirect,
                ));
      _notifyDataChanged();
    } else if (mounted) {
      NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: attendanceCorrectionErrorMessage(result));
    }
  }

  void _excelMergedText(
    excel_lib.Sheet sheet, {
    required int row,
    required int colStart,
    required int colEnd,
    required String text,
    excel_lib.CellStyle? style,
  }) {
    final cell = sheet.cell(
      excel_lib.CellIndex.indexByColumnRow(
          columnIndex: colStart, rowIndex: row),
    );
    cell.value = excel_lib.TextCellValue(text);
    if (style != null) cell.cellStyle = style;
    if (colEnd > colStart) {
      sheet.merge(
        excel_lib.CellIndex.indexByColumnRow(
            columnIndex: colStart, rowIndex: row),
        excel_lib.CellIndex.indexByColumnRow(columnIndex: colEnd, rowIndex: row),
      );
    }
  }

  void _excelSetCell(
    excel_lib.Sheet sheet,
    int row,
    int col,
    excel_lib.CellValue value, {
    excel_lib.CellStyle? style,
  }) {
    final cell = sheet.cell(
      excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = value;
    if (style != null) cell.cellStyle = style;
  }

  List<String> _shiftExcelDetailHeaders(int punchCols) {
    final headers = <String>['STT', 'Thứ', 'Ngày'];
    for (var i = 1; i <= punchCols; i++) {
      headers.add('Lần $i');
    }
    headers.addAll([
      'Đi trễ',
      'Về sớm',
      'Tăng ca',
      'Tổng giờ',
      'Đi đường',
      'Giờ thập phân',
      'Công',
      'Tên ca',
      'Trạng thái',
    ]);
    return headers;
  }

  String _excelColLetter(int colIndex) {
    var col = colIndex + 1;
    final buf = StringBuffer();
    while (col > 0) {
      final rem = (col - 1) % 26;
      buf.write(String.fromCharCode(65 + rem));
      col = (col - 1) ~/ 26;
    }
    return buf.toString().split('').reversed.join();
  }

  String _excelRef(int col, int row) => '${_excelColLetter(col)}${row + 1}';

  excel_lib.CellStyle _excelCenterStyle({
    bool bold = false,
    int fontSize = 11,
    String? backgroundHex,
    bool italic = false,
    excel_lib.NumFormat? numberFormat,
  }) {
    return excel_lib.CellStyle(
      bold: bold,
      italic: italic,
      fontSize: fontSize,
      horizontalAlign: excel_lib.HorizontalAlign.Center,
      verticalAlign: excel_lib.VerticalAlign.Center,
      backgroundColorHex: backgroundHex != null
          ? excel_lib.ExcelColor.fromHexString(backgroundHex)
          : excel_lib.ExcelColor.none,
      numberFormat: numberFormat ?? excel_lib.NumFormat.standard_0,
    );
  }

  excel_lib.CellStyle _excelLeftStyle({
    int fontSize = 11,
    bool italic = false,
  }) {
    return excel_lib.CellStyle(
      fontSize: fontSize,
      italic: italic,
      horizontalAlign: excel_lib.HorizontalAlign.Left,
      verticalAlign: excel_lib.VerticalAlign.Center,
    );
  }

  int _excelWriteEmployeeShiftBlock({
    required excel_lib.Sheet sheet,
    required int startRow,
    required List<_DailyShiftRecord> empRows,
    required _ShiftEmployeePeriodTotals totals,
    required Map<String, dynamic>? empInfo,
    required int punchCols,
    required DateTimeRange range,
    required int colCount,
    required bool isLastEmployee,
  }) {
    final titleStyle = ExcelReportBuilder.titleStyle();
    final infoStyle = _excelLeftStyle();
    final headerStyle = ExcelReportBuilder.headerStyle();
    final dataStyle = _excelCenterStyle();
    final numStyle =
        _excelCenterStyle(numberFormat: excel_lib.NumFormat.standard_2);
    final totalStyle = _excelCenterStyle(
      bold: true,
      backgroundHex: '#EFF6FF',
    );
    final sigTitleStyle = _excelCenterStyle(bold: true);
    final sigHintStyle = _excelCenterStyle(fontSize: 10, italic: true);

    final lastCol = colCount - 1;
    final punchStartCol = 3;
    final lateCol = punchStartCol + punchCols;
    final earlyCol = lateCol + 1;
    final otCol = earlyCol + 1;
    final totalHoursCol = otCol + 1;
    final travelCol = totalHoursCol + 1;
    final decimalCol = travelCol + 1;
    final workCol = decimalCol + 1;
    final shiftNameCol = workCol + 1;

    var row = startRow;

    _excelMergedText(
      sheet,
      row: row,
      colStart: 0,
      colEnd: lastCol,
      text: tr('BẢNG CHẤM CÔNG THEO CA'),
      style: titleStyle,
    );
    row++;

    _excelMergedText(
      sheet,
      row: row,
      colStart: 0,
      colEnd: lastCol,
      text:
          tr('Từ ngày ${DateFormat('dd/MM/yyyy').format(range.start)} đến ngày ${DateFormat('dd/MM/yyyy').format(range.end)}'),
      style: _excelCenterStyle(fontSize: 12),
    );
    row += 2;

    for (final line in _shiftExportInfoLines(empInfo, empRows.first)) {
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text: tr(line),
        style: infoStyle,
      );
      row++;
    }
    row++;

    final headerRow = row;
    final headers = _shiftExcelDetailHeaders(punchCols);
    ExcelReportBuilder.applyHeaderRow(sheet, headerRow, headers,
        style: headerStyle);
    row++;

    final firstDataRow = row;
    for (var i = 0; i < empRows.length; i++) {
      final r = empRows[i];
      var col = 0;
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.IntCellValue(i + 1),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.TextCellValue(r.dayOfWeek),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.TextCellValue(DateFormat('dd/MM/yyyy').format(r.date)),
        style: dataStyle,
      );

      for (var p = 0; p < punchCols; p++) {
        final punch = p < r.displayPunchTimes.length
            ? DateFormat('HH:mm').format(r.displayPunchTimes[p])
            : '';
        _excelSetCell(
          sheet,
          row,
          col++,
          excel_lib.TextCellValue(punch),
          style: dataStyle,
        );
      }

      _excelSetCell(
        sheet,
        row,
        col++,
        r.lateMinutes > 0
            ? excel_lib.IntCellValue(r.lateMinutes)
            : excel_lib.TextCellValue(''),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        r.earlyMinutes > 0
            ? excel_lib.IntCellValue(r.earlyMinutes)
            : excel_lib.TextCellValue(''),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        r.overtimeMinutes > 0
            ? excel_lib.IntCellValue(r.overtimeMinutes)
            : excel_lib.TextCellValue(''),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.TextCellValue(
            r.workHours > 0 ? _formatHoursMinutes(r.workHours) : ''),
        style: dataStyle,
      );
      final travelH = _travelHoursForShiftRecord(r);
      _excelSetCell(
        sheet,
        row,
        col++,
        travelH > 0
            ? excel_lib.TextCellValue(_formatHoursMinutes(travelH))
            : excel_lib.TextCellValue(''),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.DoubleCellValue(
            double.parse(r.decimalHours.toStringAsFixed(2))),
        style: numStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.DoubleCellValue(double.parse(r.workCount.toStringAsFixed(2))),
        style: numStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.TextCellValue(r.shiftNames.join(', ')),
        style: _excelLeftStyle(),
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.TextCellValue(r.status),
        style: dataStyle,
      );
      row++;
    }

    final lastDataRow = row - 1;
    final totalRow = row;

    _excelSetCell(sheet, totalRow, 0, excel_lib.TextCellValue(''),
        style: totalStyle);
    _excelSetCell(sheet, totalRow, 1, excel_lib.TextCellValue('TỔNG CỘNG'),
        style: totalStyle);

    if (empRows.isNotEmpty) {
      final punchCol = _excelRef(punchStartCol, firstDataRow);
      final punchEnd = _excelRef(punchStartCol, lastDataRow);
      _excelSetCell(
        sheet,
        totalRow,
        2,
        excel_lib.FormulaCellValue(
            '=COUNTIF($punchCol:$punchEnd,"<>")&" ngày"'),
        style: totalStyle,
      );

      for (final c in [lateCol, earlyCol, otCol, travelCol, decimalCol, workCol]) {
        final refStart = _excelRef(c, firstDataRow);
        final refEnd = _excelRef(c, lastDataRow);
        _excelSetCell(
          sheet,
          totalRow,
          c,
          excel_lib.FormulaCellValue('=SUM($refStart:$refEnd)'),
          style: totalStyle,
        );
      }

      _excelSetCell(
        sheet,
        totalRow,
        totalHoursCol,
        excel_lib.TextCellValue(
            totals.workHours > 0 ? _formatHoursMinutes(totals.workHours) : ''),
        style: totalStyle,
      );
      final travelTotal = _travelHoursTotalForShiftEmployee(
        employeeId: totals.employeeId,
        employeeCode: totals.employeeCode,
      );
      _excelSetCell(
        sheet,
        totalRow,
        travelCol,
        excel_lib.TextCellValue(
          travelTotal > 0 ? _formatHoursMinutes(travelTotal) : '',
        ),
        style: totalStyle,
      );
    } else {
      _excelSetCell(sheet, totalRow, 2,
          excel_lib.TextCellValue('${totals.presentDays} ngày'),
          style: totalStyle);
    }

    for (var p = 0; p < punchCols; p++) {
      _excelSetCell(sheet, totalRow, punchStartCol + p,
          excel_lib.TextCellValue(''), style: totalStyle);
    }
    _excelSetCell(sheet, totalRow, shiftNameCol, excel_lib.TextCellValue(''),
        style: totalStyle);
    _excelSetCell(sheet, totalRow, shiftNameCol + 1,
        excel_lib.TextCellValue(''), style: totalStyle);

    row = totalRow + 2;

    final part = (colCount / 3).floor().clamp(1, colCount);
    final sig1End = part - 1;
    final sig2Start = part;
    final sig2End = (part * 2 - 1).clamp(sig2Start, lastCol);
    final sig3Start = part * 2;
    _excelMergedText(sheet,
        row: row,
        colStart: 0,
        colEnd: sig1End,
        text: tr('Người lập'),
        style: sigTitleStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig2Start,
        colEnd: sig2End,
        text: tr('Nhân viên'),
        style: sigTitleStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig3Start,
        colEnd: lastCol,
        text: tr('Giám đốc'),
        style: sigTitleStyle);
    row += 4;
    _excelMergedText(sheet,
        row: row,
        colStart: 0,
        colEnd: sig1End,
        text: tr('(Ký, ghi rõ họ tên)'),
        style: sigHintStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig2Start,
        colEnd: sig2End,
        text: tr('(Ký, ghi rõ họ tên)'),
        style: sigHintStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig3Start,
        colEnd: lastCol,
        text: tr('(Ký, ghi rõ họ tên)'),
        style: sigHintStyle);
    row += 2;

    if (!isLastEmployee) row += 3;

    return row;
  }

  String? _excelFilterDescription() {
    final parts = <String>[];
    if (_selectedEmployeeIds.isNotEmpty) {
      parts.add('${_selectedEmployeeIds.length} nhân viên được chọn');
    }
    if (_shiftFilter != 'all') {
      parts.add(_shiftStatusFilterLabel());
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<String> _shiftPngDetailRowCells(
      _DailyShiftRecord r, int stt, int punchCols) {
    final cells = <String>[
      '$stt',
      r.dayOfWeek,
      DateFormat('dd/MM/yyyy').format(r.date),
    ];
    for (var p = 0; p < punchCols; p++) {
      cells.add(p < r.displayPunchTimes.length
          ? DateFormat('HH:mm').format(r.displayPunchTimes[p])
          : '');
    }
    cells.addAll([
      r.lateMinutes > 0 ? '${r.lateMinutes}P' : '',
      r.earlyMinutes > 0 ? '${r.earlyMinutes}P' : '',
      r.overtimeMinutes > 0 ? '${r.overtimeMinutes}P' : '',
      r.workHours > 0 ? _formatHoursMinutes(r.workHours) : '',
      _travelHoursForShiftRecord(r) > 0
          ? _formatHoursMinutes(_travelHoursForShiftRecord(r))
          : '',
      r.decimalHours > 0 ? r.decimalHours.toStringAsFixed(2) : '',
      r.workCount > 0 ? r.workCount.toStringAsFixed(2) : '',
      r.shiftNames.join(', '),
      r.status,
    ]);
    return cells;
  }

  List<String> _shiftPngTotalRowCells(
      _ShiftEmployeePeriodTotals totals, int punchCols) {
    final cells = <String>['', 'TỔNG CỘNG', '${totals.presentDays} ngày'];
    for (var p = 0; p < punchCols; p++) {
      cells.add('');
    }
    cells.addAll([
      totals.lateMinutes > 0 ? '${totals.lateMinutes}P' : '',
      totals.earlyMinutes > 0 ? '${totals.earlyMinutes}P' : '',
      totals.overtimeMinutes > 0 ? '${totals.overtimeMinutes}P' : '',
      totals.workHours > 0 ? _formatHoursMinutes(totals.workHours) : '',
      _travelHoursTotalForShiftEmployee(
                employeeId: totals.employeeId,
                employeeCode: totals.employeeCode) >
            0
        ? _formatHoursMinutes(_travelHoursTotalForShiftEmployee(
            employeeId: totals.employeeId, employeeCode: totals.employeeCode))
        : '',
      totals.decimalHours > 0 ? totals.decimalHours.toStringAsFixed(2) : '',
      totals.totalWork > 0 ? totals.totalWork.toStringAsFixed(2) : '',
      '',
      '',
    ]);
    return cells;
  }

  static const double _pngPad = 12.0;

  List<List<String>> _pngShiftBuildSampleRows({
    required List<String> orderedIds,
    required Map<String, List<_DailyShiftRecord>> byEmployee,
    required Map<String, _ShiftEmployeePeriodTotals> empTotals,
    required int punchCols,
  }) {
    final rows = <List<String>>[];
    for (final id in orderedIds) {
      final empRows = byEmployee[id] ?? [];
      for (var i = 0; i < empRows.length; i++) {
        rows.add(_shiftPngDetailRowCells(empRows[i], i + 1, punchCols));
      }
      final totals = empTotals[id];
      if (totals != null) {
        rows.add(_shiftPngTotalRowCells(totals, punchCols));
      }
    }
    return rows;
  }

  List<double> _pngShiftRawColWidths(
    List<String> headers,
    List<List<String>> allRows,
  ) {
    final widths = <double>[];
    for (var c = 0; c < headers.length; c++) {
      var w = headers[c].length * 8.0 + 20;
      for (final row in allRows) {
        if (c < row.length) {
          final cw = row[c].length * 7.0 + 20;
          if (cw > w) w = cw;
        }
      }
      // Cột trạng thái / tên ca cần rộng hơn để không đè chữ.
      final maxW = c >= headers.length - 2 ? 180.0 : 130.0;
      widths.add(w.clamp(52, maxW));
    }
    return widths;
  }

  String _pngFitText(
    dynamic ctx,
    String text,
    double maxWidth,
    String font,
  ) {
    if (text.isEmpty || maxWidth <= 8) return text;
    ctx.font = font;
    try {
      if (ctx.measureText(text).width <= maxWidth - 8) return text;
      var s = text;
      while (s.length > 1 && ctx.measureText('$s…').width > maxWidth - 8) {
        s = s.substring(0, s.length - 1);
      }
      return '$s…';
    } catch (_) {
      return text.length > 18 ? '${text.substring(0, 17)}…' : text;
    }
  }

  double _pngEmployeeBlockHeight({
    required int infoLineCount,
    required int dataRowCount,
    required bool addSpacer,
  }) {
    const titleH = 34.0;
    const periodH = 26.0;
    const infoH = 22.0;
    const gap = 10.0;
    const headerH = 34.0;
    const rowH = 28.0;
    const totalH = 30.0;
    const sigBlockH = 88.0;
    final spacerH = addSpacer ? 24.0 : 0.0;
    return titleH +
        periodH +
        gap +
        infoLineCount * infoH +
        gap +
        headerH +
        dataRowCount * rowH +
        totalH +
        gap +
        sigBlockH +
        spacerH;
  }

  void _pngDrawCenteredText(
    dynamic ctx,
    String text,
    double cx,
    double cy, {
    required String color,
    required String font,
    double maxWidth = 0,
  }) {
    final display = maxWidth > 0 ? _pngFitText(ctx, text, maxWidth, font) : text;
    ctx.fillStyle = color;
    ctx.font = font;
    ctx.textAlign = 'center';
    ctx.fillText(display, cx, cy);
    ctx.textAlign = 'left';
  }

  void _pngDrawShiftExport(
    dynamic ctx, {
    required double width,
    required double height,
    required Map<String, _ShiftEmployeePeriodTotals> empTotals,
    required List<String> orderedIds,
    required Map<String, List<_DailyShiftRecord>> byEmployee,
    required int punchCols,
    required DateTimeRange range,
    required List<double> colWidths,
    required double tableWidth,
    String? filterDesc,
  }) {
    const rowH = 28.0;
    const headerH = 34.0;
    const infoH = 22.0;
    const titleH = 34.0;
    const periodH = 26.0;
    const gap = 10.0;
    const sigBlockH = 88.0;
    const pad = _pngPad;

    final headers = _shiftExcelDetailHeaders(punchCols);

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, width, height);

    var y = pad;
    if (filterDesc != null) {
      _pngDrawCenteredText(ctx, 'Bộ lọc: $filterDesc', width / 2, y + 12,
          color: '#71717A', font: 'italic 11px Arial, sans-serif');
      y += 24;
    }

    final tableLeft = pad;
    final shiftNameCol = 3 + punchCols + 6;
    const cellFont = '11px Arial, sans-serif';
    const cellFontBold = 'bold 11px Arial, sans-serif';

    for (var ei = 0; ei < orderedIds.length; ei++) {
      final empId = orderedIds[ei];
      final empRows = byEmployee[empId] ?? [];
      final totals = empTotals[empId];
      if (empRows.isEmpty || totals == null) continue;
      final empInfo = _employeeInfoFor(empRows.first);
      final infoLines = _shiftExportInfoLines(empInfo, empRows.first);

      _pngDrawCenteredText(
          ctx, 'BẢNG CHẤM CÔNG THEO CA', width / 2, y + 20,
          color: '#0F172A', font: 'bold 16px Arial, sans-serif');
      y += titleH;

      _pngDrawCenteredText(
        ctx,
        'Từ ngày ${DateFormat('dd/MM/yyyy').format(range.start)} đến ngày ${DateFormat('dd/MM/yyyy').format(range.end)}',
        width / 2,
        y + 16,
        color: '#334155',
        font: '12px Arial, sans-serif',
      );
      y += periodH + gap;

      for (final line in infoLines) {
        ctx.fillStyle = '#334155';
        ctx.font = '11px Arial, sans-serif';
        ctx.textAlign = 'left';
        ctx.fillText(line, tableLeft + 8, y + 14);
        y += infoH;
      }
      y += gap;

      final tableTop = y;
      ctx.fillStyle = '#6366F1';
      ctx.fillRect(tableLeft, tableTop, tableWidth, headerH);
      var x = tableLeft;
      for (var c = 0; c < headers.length; c++) {
        _pngDrawCenteredText(
          ctx,
          headers[c],
          x + colWidths[c] / 2,
          tableTop + headerH / 2 + 5,
          color: '#FFFFFF',
          font: cellFontBold,
          maxWidth: colWidths[c],
        );
        x += colWidths[c];
      }
      y += headerH;

      for (var ri = 0; ri < empRows.length; ri++) {
        final cells =
            _shiftPngDetailRowCells(empRows[ri], ri + 1, punchCols);
        if (ri.isOdd) {
          ctx.fillStyle = '#F8FAFC';
          ctx.fillRect(tableLeft, y, tableWidth, rowH);
        }
        x = tableLeft;
        for (var c = 0; c < cells.length; c++) {
          final punchCol = c >= 3 && c < 3 + punchCols;
          String color = '#334155';
          if (punchCol && cells[c].isNotEmpty) {
            color = (c - 2).isOdd ? '#059669' : '#DC2626';
          } else if (c == cells.length - 4 && cells[c].isNotEmpty) {
            color = '#16A34A';
          } else if (c >= cells.length - 3 && cells[c].isNotEmpty) {
            color = '#1D4ED8';
          }
          if (c == shiftNameCol && cells[c].isNotEmpty) {
            ctx.fillStyle = color;
            ctx.font = cellFont;
            ctx.textAlign = 'left';
            ctx.fillText(
              _pngFitText(ctx, cells[c], colWidths[c] - 8, cellFont),
              x + 6,
              y + rowH / 2 + 5,
            );
            ctx.textAlign = 'left';
          } else {
            _pngDrawCenteredText(
              ctx,
              cells[c],
              x + colWidths[c] / 2,
              y + rowH / 2 + 5,
              color: color,
              font: cellFont,
              maxWidth: colWidths[c],
            );
          }
          x += colWidths[c];
        }
        ctx.strokeStyle = '#E2E8F0';
        ctx.beginPath();
        ctx.moveTo(tableLeft, y + rowH);
        ctx.lineTo(tableLeft + tableWidth, y + rowH);
        ctx.stroke();
        y += rowH;
      }

      final totalCells = _shiftPngTotalRowCells(totals, punchCols);
      ctx.fillStyle = '#EFF6FF';
      ctx.fillRect(tableLeft, y, tableWidth, rowH + 2);
      x = tableLeft;
      for (var c = 0; c < totalCells.length; c++) {
        _pngDrawCenteredText(
          ctx,
          totalCells[c],
          x + colWidths[c] / 2,
          y + rowH / 2 + 5,
          color: '#1D4ED8',
          font: cellFontBold,
          maxWidth: colWidths[c],
        );
        x += colWidths[c];
      }
      ctx.strokeStyle = '#93C5FD';
      ctx.beginPath();
      ctx.moveTo(tableLeft, y + rowH);
      ctx.lineTo(tableLeft + tableWidth, y + rowH);
      ctx.stroke();
      y += rowH + gap;

      final sigW = tableWidth / 3;
      final sigLabels = ['Người lập', 'Nhân viên', 'Giám đốc'];
      for (var si = 0; si < 3; si++) {
        final cx = tableLeft + sigW * si + sigW / 2;
        _pngDrawCenteredText(ctx, sigLabels[si], cx, y + 14,
            color: '#0F172A', font: 'bold 11px Arial, sans-serif');
      }
      y += 52;
      for (var si = 0; si < 3; si++) {
        final cx = tableLeft + sigW * si + sigW / 2;
        _pngDrawCenteredText(ctx, '(Ký, ghi rõ họ tên)', cx, y + 12,
            color: '#71717A', font: 'italic 10px Arial, sans-serif');
      }
      y += sigBlockH - 52;

      ctx.strokeStyle = '#CBD5E1';
      ctx.lineWidth = 1;
      ctx.strokeRect(tableLeft, tableTop, tableWidth, y - tableTop);

      if (ei < orderedIds.length - 1) y += 24;
    }
  }

  /// Export to Excel — mỗi nhân viên một khối: tiêu đề, thông tin, bảng chi tiết, ký.
  Future<void> exportToExcel() async {
    final records = _shiftData;
    if (records.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      final punchCols = _shiftPunchColCount(records);
      final colCount = 3 + punchCols + 9;
      final range = _selectedDateRange;

      final excelFile =
          ExcelReportBuilder.createWorkbook(sheetName: 'Theo ca');
      final sheet = excelFile['Theo ca'];

      sheet.setColumnWidth(0, 5);
      sheet.setColumnWidth(1, 10);
      sheet.setColumnWidth(2, 12);
      for (var i = 3; i < colCount; i++) {
        sheet.setColumnWidth(i, i < 3 + punchCols ? 9 : 11);
      }

      final empTotals = _employeeTotalsFrom(records);
      final byEmployee = <String, List<_DailyShiftRecord>>{};
      for (final r in records) {
        byEmployee.putIfAbsent(r.employeeId, () => []).add(r);
      }
      final orderedIds = _orderedUniqueEmployeeIds(records);

      var row = 0;
      final filterDesc = _excelFilterDescription();
      if (filterDesc != null) {
        _excelMergedText(
          sheet,
          row: row,
          colStart: 0,
          colEnd: colCount - 1,
          text: tr('Bộ lọc: $filterDesc'),
          style: _excelCenterStyle(fontSize: 10, italic: true),
        );
        row += 2;
      }

      for (var i = 0; i < orderedIds.length; i++) {
        final empId = orderedIds[i];
        final empRows = byEmployee[empId] ?? [];
        if (empRows.isEmpty) continue;
        final totals = empTotals[empId];
        if (totals == null) continue;
        row = _excelWriteEmployeeShiftBlock(
          sheet: sheet,
          startRow: row,
          empRows: empRows,
          totals: totals,
          empInfo: _employeeInfoFor(empRows.first),
          punchCols: punchCols,
          range: range,
          colCount: colCount,
          isLastEmployee: i == orderedIds.length - 1,
        );
      }

      final bytes = excelFile.encode();
      if (bytes != null) {
        final fileName =
            'Bang_cham_cong_theo_ca_${DateFormat('ddMMyyyy').format(range.start)}_${DateFormat('ddMMyyyy').format(range.end)}.xlsx';
        await file_saver.saveAndOpenFileBytes(bytes, fileName,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (mounted) {
          NotificationOverlayManager().showSuccess(
              title: 'Xuất Excel',
              message: tr('Đã lưu ${orderedIds.length} nhân viên vào Tải về/SBOX HRM: $fileName'));
        }
      }
    } catch (e) {
      debugPrint('Error exporting Excel: $e');
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Export to PNG — cùng bố cục Excel: từng nhân viên, thông tin, bảng, ký.
  Future<void> exportToPng() async {
    final records = _shiftData;
    if (records.isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Không có dữ liệu', message: tr('Không có dữ liệu để xuất'));
      return;
    }
    setState(() => _isExporting = true);

    try {
      final punchCols = _shiftPunchColCount(records);
      final range = _selectedDateRange;
      final empTotals = _employeeTotalsFrom(records);
      final byEmployee = <String, List<_DailyShiftRecord>>{};
      for (final r in records) {
        byEmployee.putIfAbsent(r.employeeId, () => []).add(r);
      }
      final orderedIds = _orderedUniqueEmployeeIds(records);
      final filterDesc = _excelFilterDescription();

      final headers = _shiftExcelDetailHeaders(punchCols);
      final sampleRows = _pngShiftBuildSampleRows(
        orderedIds: orderedIds,
        byEmployee: byEmployee,
        empTotals: empTotals,
        punchCols: punchCols,
      );
      final rawColWidths = _pngShiftRawColWidths(headers, sampleRows);
      final naturalTableW =
          rawColWidths.fold<double>(0, (sum, w) => sum + w);
      final totalWidth = math.max(1100.0, naturalTableW + 2 * _pngPad);
      final tableWidth = totalWidth - 2 * _pngPad;
      final scale = tableWidth / naturalTableW;
      final colWidths = rawColWidths.map((w) => w * scale).toList();

      var totalHeight = _pngPad;
      if (filterDesc != null) totalHeight += 24;
      for (var i = 0; i < orderedIds.length; i++) {
        final empRows = byEmployee[orderedIds[i]] ?? [];
        if (empRows.isEmpty) continue;
        final infoCount = _shiftExportInfoLines(
                _employeeInfoFor(empRows.first), empRows.first)
            .length;
        totalHeight += _pngEmployeeBlockHeight(
          infoLineCount: infoCount,
          dataRowCount: empRows.length + 1,
          addSpacer: i < orderedIds.length - 1,
        );
      }
      totalHeight += _pngPad + 16;

      void drawFn(dynamic ctx) => _pngDrawShiftExport(
            ctx,
            width: totalWidth,
            height: totalHeight,
            empTotals: empTotals,
            orderedIds: orderedIds,
            byEmployee: byEmployee,
            punchCols: punchCols,
            range: range,
            colWidths: colWidths,
            tableWidth: tableWidth,
            filterDesc: filterDesc,
          );

      final rangeLabel =
          '${DateFormat('ddMMyyyy').format(range.start)}_${DateFormat('ddMMyyyy').format(range.end)}';
      final fileName = 'Bang_cham_cong_theo_ca_$rangeLabel.png';

      final dataUrl = web_canvas.renderToPngDataUrl(
        width: totalWidth.toInt(),
        height: totalHeight.toInt(),
        draw: drawFn,
      );

      if (dataUrl != null) {
        await file_saver.saveAndOpenDataUrl(dataUrl, fileName);
        if (mounted) {
          NotificationOverlayManager().showSuccess(
              title: 'Xuất PNG',
              message: tr('Đã lưu ${orderedIds.length} nhân viên vào Ảnh/SBOX HRM: $fileName'));
        }
      } else {
        final pngBytes = await web_canvas.renderToPngBytes(
          width: totalWidth.toInt(),
          height: totalHeight.toInt(),
          draw: drawFn,
        );
        if (pngBytes != null && mounted) {
          await file_saver.saveAndOpenFileBytes(
              pngBytes, fileName, 'image/png');
          NotificationOverlayManager().showSuccess(
              title: 'Xuất PNG',
              message: tr('Đã lưu ${orderedIds.length} nhân viên vào Ảnh/SBOX HRM: $fileName'));
        } else if (mounted) {
          NotificationOverlayManager()
              .showError(title: 'Lỗi', message: tr('Không thể xuất PNG'));
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: tr('Lỗi xuất PNG: $e'));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  List<Widget> _buildTableSlivers(List<_DailyShiftRecord> records) {
    if (records.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(child: _buildEmptyTableCard()),
        ),
      ];
    }
    return _buildDesktopShiftSlivers(records);
  }

  Widget _buildEmptyTableCard() {
    return Container(
      height: 200,
      decoration: _tableCardDecoration,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFCBD5E1)),
            SizedBox(height: 12),
            Text(tr('Không có dữ liệu'),
                style: TextStyle(color: Color(0xFFA1A1AA))),
          ],
        ),
      ),
    );
  }

  static final DateFormat _shiftDateKeyFmt = DateFormat('yyyy-MM-dd');

  String _shiftRecordRowKey(_DailyShiftRecord r) =>
      '${r.employeeId}|${_shiftDateKeyFmt.format(r.date)}';

  int _shiftPunchColCount(List<_DailyShiftRecord> records) {
    var maxPunches = records.fold(
        0, (m, r) => r.punchTimes.length > m ? r.punchTimes.length : m);
    if (maxPunches < 4) maxPunches = 4;
    return maxPunches.isEven ? maxPunches : maxPunches + 1;
  }

  int _shiftTableColumnCount(int punchCols) => 5 + punchCols + 9;

  Map<int, TableColumnWidth> _shiftDesktopColumnWidths(int punchCols) {
    final widths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(44),
      1: const FixedColumnWidth(150),
      2: const FixedColumnWidth(90),
      3: const FixedColumnWidth(56),
      4: const FixedColumnWidth(96),
    };
    for (var i = 0; i < punchCols; i++) {
      widths[5 + i] = const FixedColumnWidth(64);
    }
    final base = 5 + punchCols;
    widths[base] = const FixedColumnWidth(64);
    widths[base + 1] = const FixedColumnWidth(64);
    widths[base + 2] = const FixedColumnWidth(64);
    widths[base + 3] = const FixedColumnWidth(72);
    widths[base + 4] = const FixedColumnWidth(68);
    widths[base + 5] = const FixedColumnWidth(68);
    widths[base + 6] = const FixedColumnWidth(56);
    widths[base + 7] = const FixedColumnWidth(120);
    widths[base + 8] = const FixedColumnWidth(140);
    return widths;
  }

  double _shiftDesktopTableMinWidth(int punchCols) {
    var w = 44.0 + 150 + 90 + 56 + 96 + punchCols * 64.0;
    w += 64 * 3 + 72 + 68 * 2 + 56 + 120 + 140;
    return w;
  }

  /// Co giãn tỷ lệ từng cột để bảng khớp [targetWidth] (fullscreen).
  Map<int, TableColumnWidth> _shiftColumnWidthsForTargetWidth(
    int punchCols,
    double targetWidth,
  ) {
    final base = _shiftDesktopColumnWidths(punchCols);
    final keys = base.keys.toList()..sort();
    final baseValues = keys
        .map((k) => (base[k]! as FixedColumnWidth).value)
        .toList();
    final baseTotal = baseValues.fold<double>(0, (s, w) => s + w);
    if (baseTotal <= 0 || targetWidth <= 0) return base;
    final scale = targetWidth / baseTotal;
    final result = <int, TableColumnWidth>{};
    for (var i = 0; i < keys.length; i++) {
      result[keys[i]] = FixedColumnWidth(baseValues[i] * scale);
    }
    return result;
  }

  Widget _shiftTableCell(Widget child, {Alignment alignment = Alignment.center}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Align(alignment: alignment, child: child),
    );
  }

  Widget _shiftHeaderText(String text) => Text(
        tr(text),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF52525B),
        ),
      );

  List<String> _shiftDetailHeaders(int punchCols) {
    final headers = <String>['STT', 'Tên nhân viên', 'Mã nhân viên', 'Thứ', 'Ngày'];
    for (var i = 1; i <= punchCols; i++) {
      headers.add('Lần $i');
    }
    headers.addAll([
      'Đi trễ',
      'Về sớm',
      'Tăng ca',
      'Tổng giờ',
      'Đi đường',
      'Giờ thập phân',
      'Công',
      'Tên ca',
      'Trạng thái',
    ]);
    return headers;
  }

  Map<String, Map<String, int>> _employeeDaySttMap(
      List<_DailyShiftRecord> records) {
    final map = <String, Map<String, int>>{};
    final counters = <String, int>{};
    for (final r in records) {
      final n = (counters[r.employeeId] ?? 0) + 1;
      counters[r.employeeId] = n;
      map.putIfAbsent(r.employeeId, () => {})[_shiftRecordRowKey(r)] = n;
    }
    return map;
  }

  Map<String, _ShiftEmployeePeriodTotals> _employeeTotalsFrom(
      List<_DailyShiftRecord> records) {
    final map = <String, _ShiftEmployeePeriodTotals>{};
    for (final r in records) {
      map
          .putIfAbsent(
            r.employeeId,
            () => _ShiftEmployeePeriodTotals(
              employeeId: r.employeeId,
              employeeName: r.employeeName,
              employeeCode: r.employeeCode,
            ),
          )
          .add(r);
    }
    return map;
  }

  Map<String, String> _employeeLastRowKeys(List<_DailyShiftRecord> records) {
    final last = <String, String>{};
    for (final r in records) {
      last[r.employeeId] = _shiftRecordRowKey(r);
    }
    return last;
  }

  Map<String, Map<String, dynamic>> _employeeInfoLookup() {
    final map = <String, Map<String, dynamic>>{};
    final list = widget.employeesList;
    if (list == null) return map;
    for (final emp in list) {
      void reg(String? key) {
        if (key != null && key.isNotEmpty) map[key] = emp;
      }
      reg(emp['employeeCode']?.toString());
      reg(emp['pin']?.toString());
      reg(emp['id']?.toString());
      reg(emp['applicationUserId']?.toString());
    }
    return map;
  }

  Map<String, dynamic>? _employeeInfoFor(_DailyShiftRecord r) {
    final lookup = _employeeInfoLookup();
    return lookup[r.employeeId] ??
        lookup[r.employeeCode] ??
        lookup[r.employeeId];
  }

  String _employeeDisplayName(Map<String, dynamic>? info, _DailyShiftRecord r) {
    if (info == null) return r.employeeName;
    final fn = info['firstName']?.toString() ?? '';
    final ln = info['lastName']?.toString() ?? '';
    final full = '$fn $ln'.trim();
    return full.isNotEmpty ? full : r.employeeName;
  }

  List<String> _shiftExportInfoLines(
    Map<String, dynamic>? empInfo,
    _DailyShiftRecord sample,
  ) {
    final displayName = _employeeDisplayName(empInfo, sample);
    final department = empInfo?['department']?.toString() ??
        empInfo?['departmentName']?.toString() ??
        '';
    final phone =
        empInfo?['phoneNumber']?.toString() ?? empInfo?['phone']?.toString() ?? '';
    final branch = empInfo?['branchName']?.toString() ?? '';
    final position = empInfo?['position']?.toString() ?? '';
    final pin = empInfo?['pin']?.toString() ?? '';
    final lines = <String>[
      'Họ và tên: ${displayName.isNotEmpty ? displayName : '—'}',
      'Mã nhân viên: ${sample.employeeCode.isNotEmpty ? sample.employeeCode : '—'}',
    ];
    if (pin.isNotEmpty && pin != sample.employeeCode) {
      lines.add('Mã chấm công (PIN): $pin');
    }
    lines.addAll([
      'Phòng ban: ${department.isNotEmpty ? department : '—'}',
      'Số điện thoại: ${phone.isNotEmpty ? phone : '—'}',
    ]);
    if (branch.isNotEmpty) lines.add('Chi nhánh: $branch');
    if (position.isNotEmpty) lines.add('Chức vụ: $position');
    return lines;
  }

  List<String> _orderedUniqueEmployeeIds(List<_DailyShiftRecord> records) {
    final seen = <String>{};
    final order = <String>[];
    for (final r in records) {
      if (seen.add(r.employeeId)) order.add(r.employeeId);
    }
    return order;
  }

  TableRow _buildShiftHeaderTableRow(int punchCols) {
    final cells = _shiftDetailHeaders(punchCols)
        .map((h) => _shiftTableCell(_shiftHeaderText(h)))
        .toList();
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
      children: cells,
    );
  }

  Widget _buildShiftPunchCell(_DailyShiftRecord r, int punchIndex) {
    return Center(child: _buildPunchTimeCell(r, punchIndex));
  }

  /// Ô giờ chấm — click để thêm (ô trống kế tiếp) hoặc sửa/xóa (đã có giờ).
  Widget _buildPunchTimeCell(_DailyShiftRecord record, int punchIndex) {
    final isIn = punchIndex.isEven;

    if (punchIndex < record.punchTimes.length) {
      final displayTime = punchIndex < record.displayPunchTimes.length
          ? record.displayPunchTimes[punchIndex]
          : record.punchTimes[punchIndex];
      if (!widget.allowCorrection) {
        return Text(
          tr(DateFormat('HH:mm').format(displayTime)),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isIn ? HrmPageChrome.chip : const Color(0xFFDC2626),
          ),
        );
      }
      return InkWell(
        onTap: () => _showEditPunchDialog(record, punchIndex),
        borderRadius: BorderRadius.circular(4),
        child: _buildPunchTimeBadge(displayTime, isIn),
      );
    }

    if (widget.allowCorrection && punchIndex == record.punchTimes.length) {
      return InkWell(
        onTap: () => _showManualPunchDialog(record),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
                color: Colors.grey.withValues(alpha: 0.3),
                style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.add, size: 14, color: Colors.grey),
        ),
      );
    }

    return Text(tr('—'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)));
  }

  TableRow _buildShiftEmployeeSubtotalRow(
    _ShiftEmployeePeriodTotals totals,
    int punchCols,
  ) {
    final cells = <Widget>[
      _shiftTableCell(const SizedBox.shrink()),
      _shiftTableCell(
        Text(tr('Σ ${totals.employeeName}'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
      ),
      _shiftTableCell(Text(tr(totals.employeeCode),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)))),
      _shiftTableCell(Text(tr('Tổng'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.blue.shade700))),
      _shiftTableCell(Text(tr('${totals.presentDays} ngày'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
    ];
    for (var i = 0; i < punchCols; i++) {
      cells.add(_shiftTableCell(Text(tr('—'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)))));
    }
    cells.addAll([
      _shiftTableCell(Text(tr(totals.lateMinutes > 0 ? '${totals.lateMinutes}P' : '—'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
      _shiftTableCell(Text(tr(totals.earlyMinutes > 0 ? '${totals.earlyMinutes}P' : '—'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
      _shiftTableCell(Text(tr(totals.overtimeMinutes > 0 ? '${totals.overtimeMinutes}P' : '—'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
      _shiftTableCell(Text(
          tr(totals.workHours > 0 ? _formatHoursMinutes(totals.workHours) : '—'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: totals.workHours > 0 ? Colors.green : const Color(0xFFA1A1AA)))),
      _shiftTableCell(_buildTravelHoursCell(
        _travelHoursTotalForShiftEmployee(
          employeeId: totals.employeeId,
          employeeCode: totals.employeeCode,
        ),
        bold: true,
      )),
      _shiftTableCell(Text(
          tr(totals.decimalHours > 0 ? totals.decimalHours.toStringAsFixed(2) : '—'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: totals.decimalHours > 0
                  ? Colors.blue.shade700
                  : const Color(0xFFA1A1AA)))),
      _shiftTableCell(Text(
          tr(totals.totalWork > 0 ? totals.totalWork.toStringAsFixed(2) : '—'),
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: totals.totalWork > 0
                  ? Colors.blue.shade700
                  : const Color(0xFFA1A1AA)))),
      _shiftTableCell(Text(tr('—'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)))),
      _shiftTableCell(Text(tr('—'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)))),
    ]);
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFEFF6FF)),
      children: cells,
    );
  }

  List<TableRow> _buildShiftDataTableRows(
    List<_DailyShiftRecord> paged,
    List<_DailyShiftRecord> allRecords,
    int punchCols,
    Map<String, Map<String, int>> daySttMap,
  ) {
    final empTotals = _employeeTotalsFrom(allRecords);
    final empLastKeys = _employeeLastRowKeys(allRecords);
    final rows = <TableRow>[];

    for (final r in paged) {
      final stt = daySttMap[r.employeeId]?[_shiftRecordRowKey(r)] ?? 1;
      final cells = <Widget>[
        _shiftTableCell(Text(tr('$stt'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)))),
        _shiftTableCell(
          InkWell(
            onTap: () => _showRecordDetail(r),
            child: Text(tr(r.employeeName),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ),
        _shiftTableCell(Text(tr(r.employeeCode),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
        _shiftTableCell(Text(tr(r.dayOfWeek),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        _shiftTableCell(Text(tr(DateFormat('dd/MM/yyyy').format(r.date)),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
      ];
      for (var i = 0; i < punchCols; i++) {
        cells.add(_shiftTableCell(_buildShiftPunchCell(r, i)));
      }
      cells.addAll([
        _shiftTableCell(Text(tr(r.lateMinutes > 0 ? '${r.lateMinutes}P' : '—'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
        _shiftTableCell(Text(tr(r.earlyMinutes > 0 ? '${r.earlyMinutes}P' : '—'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
        _shiftTableCell(Text(tr(r.overtimeMinutes > 0 ? '${r.overtimeMinutes}P' : '—'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11))),
        _shiftTableCell(Text(
            tr(r.workHours > 0 ? _formatHoursMinutes(r.workHours) : '—'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: r.workHours > 0 ? Colors.green : Colors.grey))),
        _shiftTableCell(_buildTravelHoursCell(_travelHoursForShiftRecord(r))),
        _shiftTableCell(Text(
            tr(r.decimalHours > 0 ? r.decimalHours.toStringAsFixed(2) : '—'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                color: r.decimalHours > 0
                    ? Colors.blue.shade700
                    : Colors.grey))),
        _shiftTableCell(Text(
            tr(r.workCount > 0 ? r.workCount.toStringAsFixed(2) : '—'),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: r.workCount > 0 ? Colors.blue.shade700 : Colors.grey))),
        _shiftTableCell(
          Text(tr(r.shiftNames.join(', ')),
              textAlign: TextAlign.left,
              style: const TextStyle(fontSize: 10)),
          alignment: Alignment.centerLeft,
        ),
        _shiftTableCell(
          Center(
            child: _buildStatusBadge(r.status, r.statusColor, record: r),
          ),
        ),
      ]);
      rows.add(TableRow(children: cells));

      if (empLastKeys[r.employeeId] == _shiftRecordRowKey(r)) {
        final totals = empTotals[r.employeeId];
        if (totals != null) {
          rows.add(_buildShiftEmployeeSubtotalRow(totals, punchCols));
        }
      }
    }
    return rows;
  }

  Widget _buildShiftDesktopTable({
    required Map<int, TableColumnWidth> columnWidths,
    required List<TableRow> rows,
  }) {
    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade200, width: 0.5),
        verticalInside: BorderSide(color: Colors.grey.shade200, width: 0.5),
      ),
      children: rows,
    );
  }

  void _openDetailTableFullscreen({
    required List<_DailyShiftRecord> allRecords,
    required int punchCols,
  }) {
    if (allRecords.isEmpty) return;
    final vBody = ScrollController();
    final daySttMap = _employeeDaySttMap(allRecords);
    final headerRow = _buildShiftHeaderTableRow(punchCols);
    final dataRows = _buildShiftDataTableRows(
      allRecords,
      allRecords,
      punchCols,
      daySttMap,
    );

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: const Color(0xFFFAFAFA),
          appBar: AppBar(
            title: Text(tr('Bảng chấm công theo ca'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            leading: IconButton(
              tooltip: tr('Thoát chế độ toàn màn hình'),
              icon: const Icon(Icons.fullscreen_exit),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialogCtx),
                icon: const Icon(Icons.close, size: 18),
                label: Text(tr('Thoát')),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final viewportWidth = constraints.maxWidth;
              final columnWidths =
                  _shiftColumnWidthsForTargetWidth(punchCols, viewportWidth);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: viewportWidth,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFAFAFA),
                      border: Border(
                          bottom: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: _buildShiftDesktopTable(
                      columnWidths: columnWidths,
                      rows: [headerRow],
                    ),
                  ),
                  Expanded(
                    child: Scrollbar(
                      thumbVisibility: true,
                      controller: vBody,
                      child: SingleChildScrollView(
                        controller: vBody,
                        primary: false,
                        child: SizedBox(
                          width: viewportWidth,
                          child: _buildShiftDesktopTable(
                            columnWidths: columnWidths,
                            rows: dataRows,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border:
                          Border(top: BorderSide(color: Color(0xFFE4E4E7))),
                    ),
                    child: Text(tr('${allRecords.length} bản ghi · ${daySttMap.length} nhân viên'),
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ).whenComplete(vBody.dispose);
  }

  List<Widget> _buildDesktopShiftSlivers(List<_DailyShiftRecord> records) {
    _ensureDesktopTableScrollLinked();
    final totalRows = records.length;
    final totalPages = (totalRows / _rowsPerPage).ceil();
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalRows);
    final paged = totalRows > 0
        ? records.sublist(startIndex, endIndex)
        : <_DailyShiftRecord>[];
    final punchCols = _shiftPunchColCount(records);
    final columnWidths = _shiftDesktopColumnWidths(punchCols);
    final tableMinWidth = _shiftDesktopTableMinWidth(punchCols);
    final daySttMap = _employeeDaySttMap(records);
    final headerRow = _buildShiftHeaderTableRow(punchCols);
    final dataRows = _buildShiftDataTableRows(
      paged,
      records,
      punchCols,
      daySttMap,
    );
    const headerH = 44.0;

    Widget buildHeaderTable() => _buildShiftDesktopTable(
          columnWidths: columnWidths,
          rows: [headerRow],
        );
    Widget buildBodyTable() => _buildShiftDesktopTable(
          columnWidths: columnWidths,
          rows: dataRows,
        );

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverPersistentHeader(
          pinned: true,
          delegate: PinnedBoxHeaderDelegate(
            extent: headerH,
            backgroundColor: const Color(0xFFFAFAFA),
            child: LayoutBuilder(
              builder: (context, constraints) => Scrollbar(
                thumbVisibility: true,
                controller: _desktopTableHScrollHeader,
                child: SingleChildScrollView(
                  controller: _desktopTableHScrollHeader,
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: math.max(constraints.maxWidth, tableMinWidth),
                    ),
                    child: buildHeaderTable(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: Container(
              decoration: _tableCardDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final bodyH = _tableBodyViewportHeight(context);
                      return SizedBox(
                        height: bodyH,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            primary: false,
                            physics: _tableInnerScrollPhysics,
                            child: Scrollbar(
                              thumbVisibility: true,
                              controller: _desktopTableHScrollBody,
                              notificationPredicate: (n) =>
                                  n.depth == 1 && n is ScrollUpdateNotification,
                              child: SingleChildScrollView(
                                controller: _desktopTableHScrollBody,
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: math.max(
                                        constraints.maxWidth, tableMinWidth),
                                  ),
                                  child: buildBodyTable(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  _buildPaginationBar(
                    totalRows,
                    totalPages,
                    onOpenFullscreen: () => _openDetailTableFullscreen(
                      allRecords: records,
                      punchCols: punchCols,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverToBoxAdapter(child: SizedBox(height: 8)),
      ),
    ];
  }

  ({
    AttendanceLeaveLookup leaveLookup,
    Map<String, String> empUserIdMap,
    Map<String, String> hrEmpIdMap,
  }) _verticalShiftLeaveContext() {
    final leaveLookup = AttendanceLeaveLookup.fromLeaves(
      widget.approvedLeaves,
      employeesList: widget.employeesList,
      includePending: true,
    );
    final empUserIdMap = <String, String>{};
    final hrEmpIdMap = <String, String>{};
    if (widget.employeesList != null) {
      for (final e in widget.employeesList!) {
        final code = e['employeeCode']?.toString() ?? '';
        final appId = e['applicationUserId']?.toString() ?? '';
        final hrId = e['id']?.toString() ?? '';
        if (code.isNotEmpty) {
          if (appId.isNotEmpty) empUserIdMap[code] = appId;
          if (hrId.isNotEmpty) hrEmpIdMap[code] = hrId;
        }
      }
    }
    return (
      leaveLookup: leaveLookup,
      empUserIdMap: empUserIdMap,
      hrEmpIdMap: hrEmpIdMap,
    );
  }

  String _verticalShiftPunchText(_DailyShiftRecord r) {
    final p1 =
        r.displayPunchTimes.isNotEmpty ? r.displayPunchTimes.first : null;
    final p2 = r.displayPunchTimes.length >= 2 ? r.displayPunchTimes[1] : null;
    final inStr = p1 != null ? DateFormat('HH:mm').format(p1) : '—';
    final outStr = p2 != null ? DateFormat('HH:mm').format(p2) : '—';
    final lines = <String>['$inStr·$outStr'];
    if (r.shiftNames.isNotEmpty) {
      lines.add(r.shiftNames.join(' · '));
    }
    return lines.join('\n');
  }

  String _verticalShiftMinutesLabel(int minutes) =>
      minutes > 0 ? '${minutes}p' : '—';

  String _verticalShiftWorkCountLabel(double workCount) {
    if (workCount <= 0) return '—';
    return workCount % 1 == 0
        ? workCount.toInt().toString()
        : workCount.toStringAsFixed(2);
  }

  Widget _verticalShiftAbsenceCell({
    required DateTime date,
    required String empId,
    required String empName,
    required String empCode,
    required AttendanceLeaveLookup leaveLookup,
    required Map<String, String> empUserIdMap,
    required Map<String, String> hrEmpIdMap,
  }) {
    final kind = leaveLookup.classify(
      day: date,
      employeeCode: empCode,
      employeeUserId: empUserIdMap[empCode] ?? empUserIdMap[empId],
      hrEmployeeId: hrEmpIdMap[empCode] ?? hrEmpIdMap[empId],
      displayEmployeeId: empId,
      isHoliday: _getHolidayRate(date, empCode) != null,
      isWeeklyOff: _isWeeklyOffDay(date, empCode),
    );
    final label = switch (kind) {
      AbsenceCellKind.holiday => ('Lễ', HrmPageChrome.chipMid),
      AbsenceCellKind.weeklyOff => ('Nghỉ', HrmPageChrome.chipSoft),
      AbsenceCellKind.approvedLeave => ('Phép', HrmPageChrome.chipLight),
      AbsenceCellKind.pendingLeave => ('Chờ phép', HrmPageChrome.chipDark),
      AbsenceCellKind.unpaidAbsent => ('Vắng', const Color(0xFFEF4444)),
    };
    return mobileAttendanceAbsenceLabel(
      label.$1,
      color: label.$2,
      onTap: kind == AbsenceCellKind.unpaidAbsent
          ? () {
              AbsenceDayActions.showForAbsentDay(
                context: context,
                api: ApiService(),
                employeeName: empName,
                employeeCode: empCode,
                displayEmployeeId: empId,
                applicationUserId:
                    empUserIdMap[empCode] ?? empUserIdMap[empId],
                hrEmployeeId: hrEmpIdMap[empCode] ?? hrEmpIdMap[empId],
                date: date,
                employees: widget.employeesList,
                onCompleted: _notifyDataChanged,
                onAddWork: widget.allowCorrection
                    ? () {
                        final record = _placeholderShiftForAbsent(
                          empId: empId,
                          empName: empName,
                          empCode: empCode,
                          date: date,
                        );
                        _showManualPunchDialog(record, isIn: true);
                      }
                    : null,
              );
            }
          : null,
    );
  }

  MobileAttendanceShiftVerticalTable _buildVerticalShiftTable({
    required String empId,
    required String empName,
    required String empCode,
    required List<_DailyShiftRecord> records,
    String? title,
  }) {
    final dates = attendanceDaysInRange(_selectedDateRange);
    final lookup = <String, _DailyShiftRecord>{};
    for (final r in records) {
      if (r.employeeId == empId) {
        lookup[DateFormat('yyyy-MM-dd').format(r.date)] = r;
      }
    }
    final leaveCtx = _verticalShiftLeaveContext();
    final today = DateTime.now();

    final rows = dates.map((date) {
      final record = lookup[DateFormat('yyyy-MM-dd').format(date)];
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      return MobileAttendanceShiftVerticalRow(
        day: attendanceVerticalDateShort(date),
        weekday: attendanceVerticalWeekdayShort(date),
        attendance: record == null
            ? _verticalShiftAbsenceCell(
                date: date,
                empId: empId,
                empName: empName,
                empCode: empCode,
                leaveLookup: leaveCtx.leaveLookup,
                empUserIdMap: leaveCtx.empUserIdMap,
                hrEmpIdMap: leaveCtx.hrEmpIdMap,
              )
            : mobileAttendancePunchText(_verticalShiftPunchText(record)),
        totalWork: record != null
            ? _verticalShiftWorkCountLabel(record.workCount)
            : '—',
        totalHours: record != null && record.workHours > 0
            ? _formatHoursMinutes(record.workHours)
            : '—',
        travelHours: record != null
            ? (_travelHoursForShiftRecord(record) > 0
                ? _formatHoursMinutes(_travelHoursForShiftRecord(record))
                : '—')
            : '—',
        late: record != null
            ? _verticalShiftMinutesLabel(record.lateMinutes)
            : '—',
        early: record != null
            ? _verticalShiftMinutesLabel(record.earlyMinutes)
            : '—',
        overtime: record != null
            ? _verticalShiftMinutesLabel(record.overtimeMinutes)
            : '—',
        isToday: isToday,
        onTap: record != null ? () => _showRecordDetail(record) : null,
      );
    }).toList();

    var totalWork = 0.0;
    var totalHours = 0.0;
    var totalTravel = 0.0;
    var lateMinutes = 0;
    var earlyMinutes = 0;
    var overtimeMinutes = 0;
    var presentDays = 0;
    for (final r in records) {
      if (r.employeeId != empId) continue;
      totalWork += r.workCount;
      totalHours += r.workHours;
      totalTravel += _travelHoursForShiftRecord(r);
      lateMinutes += r.lateMinutes;
      earlyMinutes += r.earlyMinutes;
      overtimeMinutes += r.overtimeMinutes;
      if (r.displayPunchTimes.isNotEmpty) presentDays++;
    }

    final totalRow = rows.isEmpty
        ? null
        : MobileAttendanceShiftVerticalRow(
            day: 'TỔNG',
            weekday: 'CỘNG',
            attendance: Center(
              child: Text(
                tr(presentDays > 0 ? '$presentDays ngày' : '—'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E40AF),
                ),
              ),
            ),
            totalWork:
                totalWork > 0 ? _verticalShiftWorkCountLabel(totalWork) : '—',
            totalHours: totalHours > 0
                ? _formatHoursMinutes(totalHours)
                : '—',
            travelHours: totalTravel > 0
                ? _formatHoursMinutes(totalTravel)
                : '—',
            late: _verticalShiftMinutesLabel(lateMinutes),
            early: _verticalShiftMinutesLabel(earlyMinutes),
            overtime: _verticalShiftMinutesLabel(overtimeMinutes),
          );

    return MobileAttendanceShiftVerticalTable(
      title: title ?? 'Bảng dọc · $empName',
      rows: rows,
      totalRow: totalRow,
    );
  }

  void _showEmployeeVerticalShiftSheet({
    required String empId,
    required String empName,
    required String empCode,
    required List<_DailyShiftRecord> records,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: HrmPageChrome.background,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(empName), overflow: TextOverflow.ellipsis),
                Text(tr('Mã $empCode'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: _buildVerticalShiftTable(
              empId: empId,
              empName: empName,
              empCode: empCode,
              records: records,
              title: 'Chi tiết theo ca',
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMobileVerticalShiftSlivers(List<_DailyShiftRecord> records) {
    if (records.isEmpty) return const [];
    final empId = records.first.employeeId;
    final empName = records.first.employeeName;
    final empCode = records.first.employeeCode;

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        sliver: SliverToBoxAdapter(
          child: _buildVerticalShiftTable(
            empId: empId,
            empName: empName,
            empCode: empCode,
            records: records,
          ),
        ),
      ),
    ];
  }

  // ─── Mobile: danh sách NV theo ca (tap xem chi tiết) ─────────────────────

  String _mobileShiftEmployeeInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String first(String s) => s.isNotEmpty ? s[0] : '';
    if (parts.length == 1) return first(parts[0]).toUpperCase();
    return '${first(parts[0])}${first(parts.last)}'.toUpperCase();
  }

  Widget _mobileShiftMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(height: 3),
            Text(
              tr(value),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              tr(label),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 8,
                color: color.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_DailyShiftRecord> _shiftRecordsForEmployee(
    List<_DailyShiftRecord> records,
    String empId,
  ) =>
      records.where((r) => r.employeeId == empId).toList();

  List<Widget> _buildMobileEmployeeShiftSummarySlivers(
    List<_DailyShiftRecord> records,
  ) {
    final empMap = <String, String>{};
    final empCodeMap = <String, String>{};
    for (final r in records) {
      empMap[r.employeeId] = r.employeeName;
      empCodeMap[r.employeeId] = r.employeeCode;
    }
    final roster = widget.employeesList;
    if (roster != null) {
      for (final emp in roster) {
        final code = emp['employeeCode']?.toString() ?? '';
        final pin = emp['pin']?.toString() ?? '';
        final id = code.isNotEmpty ? code : pin;
        if (id.isEmpty || empMap.containsKey(id)) continue;
        if (_selectedEmployeeIds.isNotEmpty &&
            !_selectedEmployeeIds.contains(id) &&
            !_selectedEmployeeIds.contains(code) &&
            !_selectedEmployeeIds.contains(pin)) {
          continue;
        }
        empMap[id] = emp['fullName']?.toString() ??
            emp['name']?.toString() ??
            emp['employeeName']?.toString() ??
            '-';
        empCodeMap[id] = code.isNotEmpty ? code : id;
      }
    }
    final employees = empMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final dates = attendanceDaysInRange(_selectedDateRange);

    double totalHoursFor(String empId) => _shiftRecordsForEmployee(records, empId)
        .fold<double>(0.0, (sum, r) => sum + r.workHours);

    double totalWorkFor(String empId) => _shiftRecordsForEmployee(records, empId)
        .fold<double>(0.0, (sum, r) => sum + r.workCount);

    double totalTravelFor(String empId) =>
        _shiftRecordsForEmployee(records, empId).fold<double>(
            0.0, (sum, r) => sum + _travelHoursForShiftRecord(r));

    int presentDaysFor(String empId) => _shiftRecordsForEmployee(records, empId)
        .where((r) => r.displayPunchTimes.isNotEmpty)
        .length;

    int lateMinutesFor(String empId) => _shiftRecordsForEmployee(records, empId)
        .fold<int>(0, (sum, r) => sum + r.lateMinutes);

    int earlyMinutesFor(String empId) => _shiftRecordsForEmployee(records, empId)
        .fold<int>(0, (sum, r) => sum + r.earlyMinutes);

    int overtimeFor(String empId) => _shiftRecordsForEmployee(records, empId)
        .fold<int>(0, (sum, r) => sum + r.overtimeMinutes);

    int lateDaysFor(String empId) => _shiftRecordsForEmployee(records, empId)
        .where((r) => r.lateMinutes > 0)
        .length;

    String shiftNamesFor(String empId) {
      final names = <String>{};
      for (final r in _shiftRecordsForEmployee(records, empId)) {
        names.addAll(r.shiftNames);
      }
      if (names.isEmpty) return '';
      final list = names.toList()..sort();
      if (list.length <= 2) return list.join(' · ');
      return '${list.take(2).join(' · ')} +${list.length - 2}';
    }

    int expectedDaysFor(String empId) {
      final code = empCodeMap[empId] ?? '';
      return dates.where((d) => !_isWeeklyOffDay(d, code)).length;
    }

    String formatWork(double w) => w <= 0
        ? '—'
        : (w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(2));

    final grandHours =
        employees.fold<double>(0.0, (s, e) => s + totalHoursFor(e.key));
    final grandWork =
        employees.fold<double>(0.0, (s, e) => s + totalWorkFor(e.key));
    final grandLate =
        employees.fold<int>(0, (s, e) => s + lateMinutesFor(e.key));
    final grandEarly =
        employees.fold<int>(0, (s, e) => s + earlyMinutesFor(e.key));
    final grandOt =
        employees.fold<int>(0, (s, e) => s + overtimeFor(e.key));

    Widget buildEmployeeCard(int index) {
      final empId = employees[index].key;
      final empName = employees[index].value;
      final empCode = empCodeMap[empId] ?? empId;
      final hours = totalHoursFor(empId);
      final travel = totalTravelFor(empId);
      final work = totalWorkFor(empId);
      final present = presentDaysFor(empId);
      final lateMin = lateMinutesFor(empId);
      final earlyMin = earlyMinutesFor(empId);
      final otMin = overtimeFor(empId);
      final lateDays = lateDaysFor(empId);
      final expected = expectedDaysFor(empId);
      final shifts = shiftNamesFor(empId);
      final workRatio = expected > 0 ? (work / expected).clamp(0.0, 1.0) : 0.0;
      final workColor = work <= 0
          ? const Color(0xFFA1A1AA)
          : (expected > 0 && work >= expected
              ? const Color(0xFF16A34A)
              : HrmPageChrome.chipMid);

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showEmployeeVerticalShiftSheet(
              empId: empId,
              empName: empName,
              empCode: empCode,
              records: _shiftRecordsForEmployee(records, empId),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE4E4E7)),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            HrmPageChrome.primaryNavy.withValues(alpha: 0.12),
                        child: Text(
                          tr(_mobileShiftEmployeeInitials(empName)),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: HrmPageChrome.primaryNavy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(empName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF18181B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr(empCode),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF71717A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (lateDays > 0)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: HrmPageChrome.chipLight
                                    .withValues(alpha: 0.35)),
                          ),
                          child: Text(tr('Trễ $lateDays'),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: HrmPageChrome.chipDark,
                            ),
                          ),
                        ),
                      const Icon(Icons.chevron_right,
                          color: Color(0xFF94A3B8), size: 22),
                    ],
                  ),
                  if (shifts.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.work_history_rounded,
                            size: 13, color: Colors.grey.shade600),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            tr('Ca: $shifts'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _mobileShiftMetricChip(
                        icon: Icons.schedule_rounded,
                        label: 'Giờ làm',
                        value: hours > 0 ? _formatHoursMinutes(hours) : '—',
                        color: HrmPageChrome.chipMid,
                      ),
                      const SizedBox(width: 6),
                      _mobileShiftMetricChip(
                        icon: Icons.directions_car_rounded,
                        label: 'Đi đường',
                        value: travel > 0 ? _formatHoursMinutes(travel) : '—',
                        color: HrmPageChrome.chipMid,
                      ),
                      const SizedBox(width: 6),
                      _mobileShiftMetricChip(
                        icon: Icons.calendar_today_rounded,
                        label: 'Công ca',
                        value: formatWork(work),
                        color: workColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _mobileShiftMetricChip(
                        icon: Icons.fingerprint_rounded,
                        label: 'Có chấm',
                        value: present > 0 ? '$present ngày' : '—',
                        color: const Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 6),
                      _mobileShiftMetricChip(
                        icon: Icons.more_time_rounded,
                        label: 'Đi trễ',
                        value: lateMin > 0 ? '${lateMin}p' : '—',
                        color: HrmPageChrome.chipLight,
                      ),
                      const SizedBox(width: 6),
                      _mobileShiftMetricChip(
                        icon: Icons.logout_rounded,
                        label: 'Về sớm',
                        value: earlyMin > 0 ? '${earlyMin}p' : '—',
                        color: const Color(0xFFEF4444),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _mobileShiftMetricChip(
                        icon: Icons.bolt_rounded,
                        label: 'Tăng ca',
                        value: otMin > 0 ? '${otMin}p' : '—',
                        color: HrmPageChrome.chipSoft,
                      ),
                    ],
                  ),
                  if (expected > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: workRatio,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE4E4E7),
                              color: workColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(tr('${formatWork(work)}/$expected công'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: workColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildGrandTotalCard() {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
              const Color(0xFFDBEAFE),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF93C5FD)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Tổng cộng'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: HrmPageChrome.primaryNavy,
                        ),
                      ),
                      Text(tr('${employees.length} nhân viên'),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      tr(grandHours > 0 ? _formatHoursMinutes(grandHours) : '—'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: HrmPageChrome.chipMid,
                      ),
                    ),
                    Text(tr('tổng giờ'),
                        style:
                            TextStyle(fontSize: 9, color: Color(0xFF71717A))),
                    const SizedBox(height: 4),
                    Text(
                      tr(formatWork(grandWork)),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: HrmPageChrome.chipMid,
                      ),
                    ),
                    Text(tr('tổng công ca'),
                        style:
                            TextStyle(fontSize: 9, color: Color(0xFF71717A))),
                  ],
                ),
              ],
            ),
            if (grandLate > 0 || grandEarly > 0 || grandOt > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (grandLate > 0)
                    _shiftSummaryBadge(
                        'Đi trễ ${grandLate}p', HrmPageChrome.chipLight),
                  if (grandEarly > 0)
                    _shiftSummaryBadge(
                        'Về sớm ${grandEarly}p', const Color(0xFFEF4444)),
                  if (grandOt > 0)
                    _shiftSummaryBadge(
                        'Tăng ca ${grandOt}p', HrmPageChrome.chipSoft),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.groups_rounded,
                    size: 18, color: HrmPageChrome.primaryNavy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('Danh sách nhân viên'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tr('${employees.length} NV'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: HrmPageChrome.primaryNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        sliver: SliverToBoxAdapter(
          child: Text(tr('Chạm thẻ để xem chi tiết: điểm danh, ca, đi trễ, về sớm theo ngày'),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildEmployeeCard(index),
            childCount: employees.length,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        sliver: SliverToBoxAdapter(child: buildGrandTotalCard()),
      ),
    ];
  }

  Widget _shiftSummaryBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        tr(label),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
  Widget _buildDayBadge(String day, int weekday) {
    final color = weekday == DateTime.sunday
        ? Colors.red
        : weekday == DateTime.saturday
            ? Colors.orange
            : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(tr(day),
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }

  /// Punch time badge with background, border and icon matching summary tab style
  Widget _buildPunchTimeBadge(DateTime time, bool isIn) {
    final color = isIn ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isIn ? Icons.login : Icons.logout, size: 12, color: color),
          const SizedBox(width: 3),
          Text(
            tr(DateFormat('HH:mm').format(time)),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
          const SizedBox(width: 2),
          Icon(Icons.edit, size: 10, color: color.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  Widget _buildShiftNameBadge(String? name) {
    if (name == null || name.isEmpty) {
      return Text(tr('-'), style: TextStyle(fontSize: 12));
    }
    // Assign colors based on common shift name patterns
    Color color = Colors.blue;
    final lower = name.toLowerCase();
    if (lower.contains('sáng') || lower.contains('sang')) {
      color = Colors.blue;
    } else if (lower.contains('chiều') || lower.contains('chieu')) {
      color = Colors.purple;
    } else if (lower.contains('tối') || lower.contains('toi')) {
      color = Colors.indigo;
    } else if (lower.contains('đêm') ||
        lower.contains('dem') ||
        lower.contains('qua đêm')) {
      color = Colors.deepPurple;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(tr(name),
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }

  Widget _buildMinutesBadge(int minutes, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr('${minutes}P'),
        style:
            TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }

  Widget _buildHoursBadge(double hours) {
    if (hours <= 0) return Text(tr('-'), style: TextStyle(fontSize: 12));
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr('${h}h${m > 0 ? '${m}p' : ''}'),
        style: const TextStyle(
            color: Colors.green, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }

  Widget _buildStatusBadge(
    String status,
    Color color, {
    _DailyShiftRecord? record,
  }) {
    IconData icon = Icons.check_circle;
    if (status == 'Vắng') {
      icon = Icons.add_circle_outline;
    }
    if (status.contains('Thiếu chấm') || status.contains('Thiếu ra')) {
      icon = Icons.touch_app;
    }
    if (status.contains('Đi trễ')) icon = Icons.timer_off;
    if (status.contains('Về sớm')) icon = Icons.exit_to_app;
    if (status.contains('Đi trễ') && status.contains('Về sớm')) {
      icon = Icons.warning;
    }
    if (status.contains('Tăng ca ngày nghỉ')) icon = Icons.event_busy;
    if (status.contains('Tăng ca ngày lễ')) icon = Icons.celebration;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(tr(status),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 11)),
          ),
        ],
      ),
    );

    final tappable = record != null &&
        widget.allowCorrection &&
        _statusHasMissingPunch(status);
    if (!tappable) return badge;

    return Tooltip(
      message: record.status == 'Vắng'
          ? 'Bấm để thêm công'
          : 'Bấm để bổ sung chấm công thiếu',
      child: InkWell(
        onTap: () => _onMissingStatusTap(record),
        borderRadius: BorderRadius.circular(4),
        child: badge,
      ),
    );
  }

  Widget _buildWorkCountBadge(double count) {
    final color = count > 0 ? Colors.blue : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr(count == count.roundToDouble()
            ? '${count.toInt()}'
            : count.toStringAsFixed(2)),
        style:
            TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildDecimalHoursBadge(double hours) {
    if (hours <= 0) return Text(tr('-'), style: TextStyle(fontSize: 12));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr(hours.toStringAsFixed(2)),
        style: const TextStyle(
            color: Colors.teal, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}

class _ShiftEmployeePeriodTotals {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  int lateMinutes = 0;
  int earlyMinutes = 0;
  int overtimeMinutes = 0;
  double workHours = 0;
  double decimalHours = 0;
  double totalWork = 0;
  int presentDays = 0;

  _ShiftEmployeePeriodTotals({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
  });

  void add(_DailyShiftRecord r) {
    lateMinutes += r.lateMinutes;
    earlyMinutes += r.earlyMinutes;
    overtimeMinutes += r.overtimeMinutes;
    workHours += r.workHours;
    decimalHours += r.decimalHours;
    totalWork += r.workCount;
    if (r.punchTimes.isNotEmpty) presentDays++;
  }
}

class _DailyShiftRecord {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final DateTime date;
  final String dayOfWeek;
  final List<DateTime> punchTimes;
  final List<DateTime> displayPunchTimes;
  final List<String> attendanceIds;
  final List<String> shiftNames;
  final int lateMinutes;
  final int earlyMinutes;
  final int overtimeMinutes;
  final double workHours;
  final double decimalHours;
  final String status;
  final Color statusColor;
  final double workCount;
  final List<_MissingPunchHint> missingPunchHints;

  _DailyShiftRecord({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.date,
    required this.dayOfWeek,
    required this.punchTimes,
    required this.displayPunchTimes,
    this.attendanceIds = const [],
    this.shiftNames = const [],
    required this.lateMinutes,
    required this.earlyMinutes,
    required this.overtimeMinutes,
    required this.workHours,
    required this.decimalHours,
    required this.status,
    required this.statusColor,
    required this.workCount,
    this.missingPunchHints = const [],
  });
}

class _MissingPunchHint {
  final String shiftName;
  final bool isCheckIn;
  final TimeOfDay suggestedTime;

  const _MissingPunchHint({
    required this.shiftName,
    required this.isCheckIn,
    required this.suggestedTime,
  });
}

class _EmployeeOption {
  final String id;
  final String name;
  final String code;
  _EmployeeOption({required this.id, required this.name, required this.code});
}
