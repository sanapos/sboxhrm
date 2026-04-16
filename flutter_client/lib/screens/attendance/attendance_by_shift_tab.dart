import 'dart:convert';
import 'dart:math' as math;
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/web_canvas.dart' as web_canvas;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../services/api_service.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/notification_overlay.dart';

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
  final VoidCallback? onDataChanged;

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
    this.onDataChanged,
  });

  @override
  State<AttendanceByShiftTab> createState() => _AttendanceByShiftTabState();
}

class _AttendanceByShiftTabState extends State<AttendanceByShiftTab> {
  String _selectedPreset = 'month';
  Set<String> _selectedEmployeeIds = {};
  String _shiftFilter = 'all'; // 'all' | 'missing' | 'complete'
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;

  // Sorting
  bool _sortAscending = false;
  int _rowsPerPage = 50;
  int _currentPage = 0;
  bool _isExporting = false;
  final Set<int> _expandedCardIndices = {};

  // Cached lookup maps built from props
  Map<String, String> _employeeCodeToGuid = {};
  Map<String, List<String>> _employeeGuidToShiftTemplateIds = {};
  Map<String, Map<String, dynamic>> _shiftTemplateMap = {};
  Map<String, int> _employeeGuidToShiftsPerDay = {};
  // Rest day & holiday coefficient maps
  Map<String, String> _employeeCodeToWeeklyOffDays = {}; // empCode → 'Sunday' | 'Saturday,Sunday' etc.
  Map<String, double> _employeeCodeToHolidayMultiplier = {}; // empCode → 2.0 (x2) etc.
  Map<String, int> _employeeCodeToHolidayOvertimeType = {}; // empCode → 0=fixed, 1=legal coefficient

  @override
  void initState() {
    super.initState();
    _buildLookupMaps();
  }

  @override
  void didUpdateWidget(covariant AttendanceByShiftTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shiftTemplates != widget.shiftTemplates ||
        oldWidget.shiftSalaryLevels != widget.shiftSalaryLevels ||
        oldWidget.salaryProfiles != widget.salaryProfiles) {
      _buildLookupMaps();
    }
  }

  void _buildLookupMaps() {
    // Build shift template map: shiftTemplateId → template data
    _shiftTemplateMap = {};
    for (final st in widget.shiftTemplates) {
      final id = st['id']?.toString() ?? '';
      if (id.isNotEmpty) _shiftTemplateMap[id] = st;
    }

    // Build employeeCode → employeeGuid and employeeGuid → shiftsPerDay from salary profiles
    _employeeCodeToGuid = {};
    _employeeGuidToShiftsPerDay = {};
    _employeeCodeToWeeklyOffDays = {};
    _employeeCodeToHolidayMultiplier = {};
    _employeeCodeToHolidayOvertimeType = {};
    for (final profile in widget.salaryProfiles) {
      final shiftsPerDay = profile['shiftsPerDay'] as int? ?? 1;
      final weeklyOffDays = profile['weeklyOffDays']?.toString() ?? 'Sunday';
      final holidayMultiplier = (profile['holidayMultiplier'] as num?)?.toDouble() ?? 2.0;
      final holidayOvertimeType = (profile['holidayOvertimeType'] as num?)?.toInt() ?? 1;
      final employees = profile['employees'] as List? ?? [];
      for (final emp in employees) {
        if (emp is Map<String, dynamic>) {
          final guid = emp['id']?.toString() ?? '';
          final code = emp['employeeCode']?.toString() ?? '';
          if (guid.isNotEmpty && code.isNotEmpty) {
            _employeeCodeToGuid[code] = guid;
            _employeeGuidToShiftsPerDay[guid] = shiftsPerDay;
            _employeeCodeToWeeklyOffDays[code] = weeklyOffDays;
            _employeeCodeToHolidayMultiplier[code] = holidayMultiplier;
            _employeeCodeToHolidayOvertimeType[code] = holidayOvertimeType;
          }
        }
      }
    }

    // Build employeeGuid → list of assigned shiftTemplateIds from shift salary levels
    _employeeGuidToShiftTemplateIds = {};
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
        if (!_employeeGuidToShiftTemplateIds[empGuid]!.contains(shiftTemplateId)) {
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

  /// Find the best matching shift template for a punch-in time
  Map<String, dynamic>? _findMatchingShift(int punchInMinutes, List<String> assignedShiftIds) {
    if (assignedShiftIds.isEmpty) return null;

    Map<String, dynamic>? bestMatch;
    int bestDistance = 999999;

    for (final stId in assignedShiftIds) {
      final st = _shiftTemplateMap[stId];
      if (st == null) continue;
      if (st['isActive'] == false) continue;

      final startMinutes = _parseTimeSpanToMinutes(st['startTime']?.toString());
      
      // Distance calculation considering cross-midnight
      int dist = (punchInMinutes - startMinutes).abs();
      if (dist > 720) dist = 1440 - dist; // wrap around midnight

      if (dist < bestDistance) {
        bestDistance = dist;
        bestMatch = st;
      }
    }

    // Fallback: if best match is too far (> 180 min / 3h), search ALL shift templates
    if (bestDistance > 180) {
      for (final st in _shiftTemplateMap.values) {
        if (st['isActive'] == false) continue;
        final startMinutes = _parseTimeSpanToMinutes(st['startTime']?.toString());
        int dist = (punchInMinutes - startMinutes).abs();
        if (dist > 720) dist = 1440 - dist;
        if (dist < bestDistance) {
          bestDistance = dist;
          bestMatch = st;
        }
      }
    }

    return bestMatch;
  }

  /// Check if a date is a weekly off day for a given employee
  bool _isWeeklyOffDay(DateTime date, String employeeCode) {
    final weeklyOff = _employeeCodeToWeeklyOffDays[employeeCode] ?? 'Sunday';
    final weekday = date.weekday; // 1=Mon, 7=Sun
    if (weeklyOff.contains('Sunday') && weekday == DateTime.sunday) return true;
    if (weeklyOff.contains('Saturday') && weekday == DateTime.saturday) return true;
    return false;
  }

  /// Check if a date is a holiday, returns the holiday's salaryRate or null
  double? _getHolidayRate(DateTime date, String employeeCode) {
    for (final h in widget.holidays) {
      if (h is! Map<String, dynamic>) continue;
      final holidayDate = DateTime.tryParse(h['date']?.toString() ?? '');
      if (holidayDate == null) continue;
      final isRecurring = h['isRecurring'] == true;
      bool dateMatch = isRecurring
          ? holidayDate.month == date.month && holidayDate.day == date.day
          : holidayDate.year == date.year && holidayDate.month == date.month && holidayDate.day == date.day;
      if (!dateMatch) continue;
      // Check employee scope
      final employeeCodes = h['employeeCodes'] as List?;
      final employeeIds = h['employeeIds'] as List?;
      final scopeList = employeeCodes ?? employeeIds;
      if (scopeList != null && scopeList.isNotEmpty) {
        if (!scopeList.any((code) => code?.toString() == employeeCode)) continue;
      }
      return (h['salaryRate'] as num?)?.toDouble() ?? 3.0;
    }
    return null;
  }

  /// Get logical date: if punch time < dayEndTime, it belongs to the previous day
  DateTime _getLogicalDate(DateTime punchTime) {
    final dayEnd = widget.dayEndHour * 60 + widget.dayEndMinute;
    if (dayEnd > 0) {
      final punchMinutes = punchTime.hour * 60 + punchTime.minute;
      if (punchMinutes < dayEnd) {
        final prev = punchTime.subtract(const Duration(days: 1));
        return DateTime(prev.year, prev.month, prev.day);
      }
    }
    return DateTime(punchTime.year, punchTime.month, punchTime.day);
  }

  /// Get unique employees from all attendances
  List<_EmployeeOption> get _allEmployees {
    final Map<String, _EmployeeOption> map = {};
    for (final att in widget.attendances) {
      final id = att.employeeId ?? att.enrollNumber ?? 'unknown';
      if (!map.containsKey(id)) {
        map[id] = _EmployeeOption(
          id: id,
          name: att.employeeName?.isNotEmpty == true ? att.employeeName! : (att.deviceUserName?.isNotEmpty == true ? att.deviceUserName! : '-'),
          code: att.employeeId ?? att.enrollNumber ?? '-',
        );
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // Lấy ngày bắt đầu và kết thúc theo preset đã chọn
  DateTimeRange get _selectedDateRange {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (_selectedPreset) {
      case 'today':
        return DateTimeRange(start: today, end: now);
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: yesterday,
          end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59),
        );
      case 'week':
        final weekday = now.weekday;
        final thisMonday = today.subtract(Duration(days: weekday - 1));
        return DateTimeRange(start: thisMonday, end: now);
      case 'lastWeek':
        final weekday = now.weekday;
        final thisMonday = today.subtract(Duration(days: weekday - 1));
        final lastMonday = thisMonday.subtract(const Duration(days: 7));
        final lastSunday = thisMonday.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: lastMonday,
          end: DateTime(lastSunday.year, lastSunday.month, lastSunday.day, 23, 59, 59),
        );
      case 'month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case 'lastMonth':
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        final lastDayOfLastMonth = DateTime(now.year, now.month, 0);
        return DateTimeRange(
          start: lastMonth,
          end: DateTime(lastDayOfLastMonth.year, lastDayOfLastMonth.month, lastDayOfLastMonth.day, 23, 59, 59),
        );
      default:
        return DateTimeRange(start: widget.fromDate, end: widget.toDate);
    }
  }

  /// Lọc attendances theo preset và selected employees
  List<Attendance> get _filteredAttendances {
    final range = _selectedDateRange;
    var result = widget.attendances.where((att) {
      return att.punchTime.isAfter(range.start.subtract(const Duration(seconds: 1))) &&
             att.punchTime.isBefore(range.end.add(const Duration(seconds: 1)));
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
    final filteredData = _filteredAttendances;
    // Group attendances by employee and logical date (using day_end_time)
    final Map<String, Map<String, List<Attendance>>> groupedByEmployeeAndDate = {};
    
    for (final att in filteredData) {
      final employeeKey = att.employeeId ?? att.enrollNumber ?? 'unknown';
      final logicalDate = _getLogicalDate(att.punchTime);
      final dateKey = DateFormat('yyyy-MM-dd').format(logicalDate);
      
      groupedByEmployeeAndDate.putIfAbsent(employeeKey, () => {});
      groupedByEmployeeAndDate[employeeKey]!.putIfAbsent(dateKey, () => []).add(att);
    }
    
    final records = <_DailyShiftRecord>[];
    
    groupedByEmployeeAndDate.forEach((employeeCode, dateMap) {
      dateMap.forEach((dateStr, dayAttendances) {
        if (dayAttendances.isEmpty) return;
        
        dayAttendances.sort((a, b) => a.punchTime.compareTo(b.punchTime));
        final first = dayAttendances.first;
        final date = DateTime.parse(dateStr);
        
        // Collect all punch times and attendance IDs for display/edit
        final punchTimes = dayAttendances.map((a) => a.punchTime).toList();
        final attendanceIds = dayAttendances.map((a) => a.id).toList();
        
        // Lookup employee info
        final empGuid = _employeeCodeToGuid[employeeCode] ?? '';
        final assignedShiftIds = _employeeGuidToShiftTemplateIds[empGuid] ?? [];
        final shiftsPerDay = _employeeGuidToShiftsPerDay[empGuid] ?? 1;
        final candidateIds = assignedShiftIds.isNotEmpty
            ? assignedShiftIds
            : _shiftTemplateMap.keys.toList();

        // Pair punches: odd=IN, even=OUT, each pair = 1 shift
        // Then aggregate totals across all pairs
        int totalLate = 0;
        int totalEarly = 0;
        int totalOT = 0;
        double totalWorkHours = 0;
        double totalDecimalHours = 0;
        double totalWorkCount = 0;
        bool hasMissingPunch = false;
        final shiftNames = <String>[];

        for (int i = 0; i < dayAttendances.length; i += 2) {
          final punchIn = dayAttendances[i].punchTime;
          final punchOut = (i + 1 < dayAttendances.length) ? dayAttendances[i + 1].punchTime : null;

          final punchInMinutes = _dateTimeToMinutes(punchIn);
          final matchedShift = _findMatchingShift(punchInMinutes, candidateIds);
          
          if (matchedShift != null) {
            final name = matchedShift['name']?.toString() ?? '';
            if (name.isNotEmpty && !shiftNames.contains(name)) {
              shiftNames.add(name);
            }
          }

          if (punchOut == null) {
            hasMissingPunch = true;
            continue;
          }

          final punchOutMinutes = _dateTimeToMinutes(punchOut);
          final actualWorkedMinutes = punchOut.difference(punchIn).inMinutes;

          if (matchedShift != null) {
            final shiftStartMin = _parseTimeSpanToMinutes(matchedShift['startTime']?.toString());
            final shiftEndMin = _parseTimeSpanToMinutes(matchedShift['endTime']?.toString());
            final isCrossMidnight = shiftStartMin > shiftEndMin;
            final shiftDurationMin = isCrossMidnight
                ? (1440 - shiftStartMin + shiftEndMin)
                : (shiftEndMin - shiftStartMin);

            // Late
            int lateCalc = 0;
            if (isCrossMidnight) {
              if (punchInMinutes >= shiftStartMin) {
                lateCalc = punchInMinutes - shiftStartMin;
              } else if (punchInMinutes < shiftEndMin) {
                lateCalc = (1440 - shiftStartMin) + punchInMinutes;
              }
            } else {
              if (punchInMinutes > shiftStartMin) {
                lateCalc = punchInMinutes - shiftStartMin;
              }
            }
            if (lateCalc > 0) totalLate += lateCalc;

            // Early
            int earlyCalc = 0;
            if (isCrossMidnight) {
              if (punchOutMinutes <= shiftEndMin) {
                earlyCalc = shiftEndMin - punchOutMinutes;
              } else if (punchOutMinutes >= shiftStartMin) {
                earlyCalc = (1440 - punchOutMinutes) + shiftEndMin;
              }
            } else {
              if (punchOutMinutes < shiftEndMin) {
                earlyCalc = shiftEndMin - punchOutMinutes;
              }
            }

            // Overtime – only count if extra minutes exceed shift's "Tính tăng ca" threshold
            int extraMin = 0;
            final overtimeThreshold = (matchedShift['breakTimeMinutes'] as num?)?.toInt() ?? 0;
            if (isCrossMidnight) {
              if (punchOutMinutes > shiftEndMin && punchOutMinutes < shiftStartMin) {
                extraMin = punchOutMinutes - shiftEndMin;
              }
            } else {
              if (punchOutMinutes > shiftEndMin) {
                extraMin = punchOutMinutes - shiftEndMin;
              }
            }
            if (extraMin > overtimeThreshold) {
              totalOT += extraMin;
              earlyCalc = 0;
            } else {
              extraMin = 0;
            }
            if (earlyCalc > 0) totalEarly += earlyCalc;

            // Hours
            if (lateCalc <= 0 && earlyCalc <= 0 && extraMin <= 0) {
              totalWorkHours += shiftDurationMin / 60.0;
            } else {
              totalWorkHours += actualWorkedMinutes / 60.0;
            }
            totalDecimalHours += actualWorkedMinutes / 60.0;
            totalWorkCount += shiftsPerDay > 0 ? 1.0 / shiftsPerDay : 1.0;
          } else {
            totalWorkHours += actualWorkedMinutes / 60.0;
            totalDecimalHours += actualWorkedMinutes / 60.0;
            totalWorkCount += shiftsPerDay > 0 ? 1.0 / shiftsPerDay : 1.0;
          }
        }

        // Check if this is a weekly off day or a holiday for the employee
        final isRestDay = _isWeeklyOffDay(date, employeeCode);
        final holidayRate = _getHolidayRate(date, employeeCode);
        final isHoliday = holidayRate != null;
        final holidayOvertimeType = _employeeCodeToHolidayOvertimeType[employeeCode] ?? 1;
        final holidayMultiplier = _employeeCodeToHolidayMultiplier[employeeCode] ?? 2.0;

        // Apply coefficients based on day type
        if ((isRestDay || isHoliday) && totalWorkCount > 0) {
          if (isHoliday) {
            // Ngày lễ: luôn nhân hệ số từ thiết lập ngày lễ (salaryRate)
            totalWorkCount *= holidayRate;
            totalWorkHours *= holidayRate;
            totalDecimalHours *= holidayRate;
          } else if (isRestDay) {
            // Ngày nghỉ hàng tuần: theo holidayOvertimeType
            if (holidayOvertimeType == 1) {
              // Theo quy định pháp luật → nhân hệ số (x2, x3)
              totalWorkCount *= holidayMultiplier;
              totalWorkHours *= holidayMultiplier;
              totalDecimalHours *= holidayMultiplier;
            }
            // holidayOvertimeType == 0: cố định theo ngày tăng ca → không nhân hệ số
          }
        }

        // Determine combined status
        String status;
        Color statusColor;
        if (hasMissingPunch && totalWorkCount == 0) {
          status = 'Thiếu chấm';
          statusColor = Colors.grey;
        } else if (isHoliday && totalWorkCount > 0) {
          // Ngày lễ mà có chấm công → Tăng ca ngày lễ
          status = 'Tăng ca ngày lễ';
          statusColor = Colors.deepOrange;
          if (totalLate > 0) status = 'Đi trễ - $status';
          if (totalEarly > 0) status = '$status - Về sớm';
        } else if (isRestDay && totalWorkCount > 0) {
          // Ngày nghỉ mà có chấm công → Tăng ca ngày nghỉ
          status = 'Tăng ca ngày nghỉ';
          statusColor = Colors.purple;
          if (totalLate > 0) status = 'Đi trễ - $status';
          if (totalEarly > 0) status = '$status - Về sớm';
        } else if (totalLate > 0 && totalEarly > 0) {
          status = 'Đi trễ - Về sớm';
          statusColor = Colors.red;
        } else if (totalLate > 0) {
          status = 'Đi trễ';
          statusColor = Colors.orange;
        } else if (totalEarly > 0) {
          status = 'Về sớm';
          statusColor = Colors.red;
        } else if (totalWorkCount > 0) {
          status = 'Hợp lệ';
          statusColor = Colors.green;
        } else {
          status = 'Thiếu chấm';
          statusColor = Colors.grey;
        }
        if (hasMissingPunch && totalWorkCount > 0) {
          status += ' (lẻ)';
        }

        records.add(_DailyShiftRecord(
          employeeId: employeeCode,
          employeeName: first.employeeName?.isNotEmpty == true ? first.employeeName! : (first.deviceUserName?.isNotEmpty == true ? first.deviceUserName! : '-'),
          employeeCode: first.employeeId ?? first.enrollNumber ?? '-',
          date: date,
          dayOfWeek: _getDayOfWeekVN(date.weekday),
          punchTimes: punchTimes,
          attendanceIds: attendanceIds,
          shiftNames: shiftNames,
          lateMinutes: totalLate,
          earlyMinutes: totalEarly,
          overtimeMinutes: totalOT,
          workHours: totalWorkHours,
          decimalHours: totalDecimalHours,
          status: status,
          statusColor: statusColor,
          workCount: totalWorkCount,
        ));
      });
    });
    
    // Sort by employee name, then date
    records.sort((a, b) {
      final nameComp = a.employeeName.compareTo(b.employeeName);
      if (nameComp != 0) return nameComp;
      final cmp = a.date.compareTo(b.date);
      return _sortAscending ? cmp : -cmp;
    });

    // Filter by shift status
    if (_shiftFilter == 'missing') {
      return records.where((r) => r.status.contains('Thiếu chấm') || r.punchTimes.length % 2 != 0).toList();
    } else if (_shiftFilter == 'complete') {
      return records.where((r) => !r.status.contains('Thiếu chấm') && r.punchTimes.length >= 2 && r.punchTimes.length % 2 == 0).toList();
    }

    return records;
  }

  String _getDayOfWeekVN(int weekday) {
    switch (weekday) {
      case DateTime.monday: return 'T2';
      case DateTime.tuesday: return 'T3';
      case DateTime.wednesday: return 'T4';
      case DateTime.thursday: return 'T5';
      case DateTime.friday: return 'T6';
      case DateTime.saturday: return 'T7';
      case DateTime.sunday: return 'CN';
      default: return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final records = _shiftData;
    final range = _selectedDateRange;
    
    // Calculate totals
    int totalLate = records.where((r) => r.lateMinutes > 0).length;
    int totalEarly = records.where((r) => r.earlyMinutes > 0).length;
    int totalOT = records.where((r) => r.overtimeMinutes > 0).length;
    double totalHours = records.fold(0.0, (sum, r) => sum + r.workHours);
    int totalRecords = records.length;
    final uniqueEmployees = records.map((r) => r.employeeId).toSet().length;

    // Sum totals for column headers
    int sumLateMinutes = records.fold(0, (sum, r) => sum + r.lateMinutes);
    int sumEarlyMinutes = records.fold(0, (sum, r) => sum + r.earlyMinutes);
    int sumOTMinutes = records.fold(0, (sum, r) => sum + r.overtimeMinutes);
    double sumWorkHours = records.fold(0.0, (sum, r) => sum + r.workHours);
    double sumDecimalHours = records.fold(0.0, (sum, r) => sum + r.decimalHours);
    double sumWorkCount = records.fold(0.0, (sum, r) => sum + r.workCount);

    // Pagination
    final totalRows = records.length;
    final totalPages = (totalRows / _rowsPerPage).ceil();
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalRows);
    final pagedRecords = totalRows > 0 ? records.sublist(startIndex, endIndex) : <_DailyShiftRecord>[];

    // Compute dynamic punch column count: max punches across all records, rounded up to even, min 4
    int maxPunches = records.fold(0, (m, r) => r.punchTimes.length > m ? r.punchTimes.length : m);
    if (maxPunches < 4) maxPunches = 4;
    // Round up to even so that odd-punch rows get a "+" slot at the next even position
    final punchColCount = maxPunches.isEven ? maxPunches : maxPunches + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stats cards
          if (Responsive.isMobile(context)) ...[
            InkWell(
              onTap: () => setState(() => _showMobileSummary = !_showMobileSummary),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text('Tổng quan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue.shade700)),
                    const Spacer(),
                    Icon(_showMobileSummary ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.blue.shade700),
                  ],
                ),
              ),
            ),
            if (_showMobileSummary) ...[
              const SizedBox(height: 8),
              _buildStatsRow(totalRecords, uniqueEmployees, totalHours, totalLate, totalEarly, totalOT),
            ],
          ] else ...[
            _buildStatsRow(totalRecords, uniqueEmployees, totalHours, totalLate, totalEarly, totalOT),
          ],
          const SizedBox(height: 12),

          // Filter bar
          _buildFilters(range),
          const SizedBox(height: 12),

          // Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              child: records.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 56, color: Color(0xFFCBD5E1)),
                          SizedBox(height: 12),
                          Text('Không có dữ liệu',
                              style: TextStyle(color: Color(0xFFA1A1AA))),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobileLayout = constraints.maxWidth < 600;
                        if (isMobileLayout) {
                          return Column(
                            children: [
                              Expanded(
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  itemCount: records.length,
                                  itemBuilder: (_, index) {
                                    final record = records[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFE4E4E7)),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                                        ),
                                        child: _buildShiftDeckItem(record),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Expanded(
                              child: Scrollbar(
                                thumbVisibility: true,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: Scrollbar(
                                      thumbVisibility: true,
                                      notificationPredicate: (n) => n.depth == 0,
                                      child: SingleChildScrollView(
                                        child: DataTable(
                                          showCheckboxColumn: false,
                                          sortColumnIndex: 4,
                                          sortAscending: _sortAscending,
                                          headingRowColor: WidgetStateProperty.all(
                                            const Color(0xFFFAFAFA),
                                          ),
                                          dataRowColor: WidgetStateProperty.resolveWith<Color?>((states) {
                                            if (states.contains(WidgetState.hovered)) {
                                              return const Color(0xFFF1F5F9);
                                            }
                                            return null;
                                          }),
                                          dividerThickness: 0.5,
                                          columnSpacing: 16,
                                          horizontalMargin: 12,
                                          headingRowHeight: 44,
                                          dataRowMinHeight: 40,
                                          dataRowMaxHeight: 46,
                                          columns: [
                                            const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                                            const DataColumn(label: Expanded(child: Text('Tên nhân viên', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                                            const DataColumn(label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                                            const DataColumn(label: Expanded(child: Text('Thứ', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                                            DataColumn(label: const Expanded(child: Text('Ngày', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A)))), onSort: (_, asc) { setState(() { _sortAscending = asc; }); }),
                                            ...List.generate(punchColCount, (i) => DataColumn(
                                              label: Expanded(child: Text('Lần ${i + 1}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A)))),
                                            )),
                                            DataColumn(label: _buildColumnHeaderWithTotal('Đi trễ', '${sumLateMinutes}P', Colors.orange)),
                                            DataColumn(label: _buildColumnHeaderWithTotal('Về sớm', '${sumEarlyMinutes}P', Colors.red)),
                                            DataColumn(label: _buildColumnHeaderWithTotal('Tăng ca', '${sumOTMinutes}P', Colors.purple)),
                                            DataColumn(label: _buildColumnHeaderWithTotal('Tổng giờ', _formatHoursMinutes(sumWorkHours), Colors.green)),
                                            DataColumn(label: _buildColumnHeaderWithTotal('Giờ (thập phân)', sumDecimalHours.toStringAsFixed(2), Colors.teal)),
                                            DataColumn(label: _buildColumnHeaderWithTotal('Công', sumWorkCount == sumWorkCount.roundToDouble() ? '${sumWorkCount.toInt()}' : sumWorkCount.toStringAsFixed(2), Colors.blue)),
                                            const DataColumn(label: Expanded(child: Text('Tên ca', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                                            const DataColumn(label: Expanded(child: Text('Trạng thái', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                                          ],
                                          rows: pagedRecords.asMap().entries.map((entry) {
                                            final index = entry.key;
                                            final record = entry.value;

                                            return DataRow(
                                              cells: [
                                                DataCell(Center(child: Text('${startIndex + index + 1}', style: const TextStyle(fontSize: 12, color: Colors.grey)))),
                                                DataCell(Center(child: Text(record.employeeName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)))),
                                                DataCell(Center(child: Text(record.employeeCode, style: const TextStyle(fontSize: 12)))),
                                                DataCell(Center(child: _buildDayBadge(record.dayOfWeek, record.date.weekday))),
                                                DataCell(Center(child: Text(DateFormat('dd/MM/yyyy').format(record.date), style: const TextStyle(fontSize: 12)))),
                                                // Dynamic punch time cells
                                                ...List.generate(punchColCount, (i) {
                                                  if (i < record.punchTimes.length) {
                                                    // Has punch data: clickable for editing
                                                    final isIn = i.isEven; // Chẵn=Vào(xanh), Lẻ=Ra(đỏ)
                                                    return DataCell(Center(
                                                      child: InkWell(
                                                        onTap: () => _showEditPunchDialog(record, i),
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: _buildPunchTimeBadge(record.punchTimes[i], isIn),
                                                      ),
                                                    ));
                                                  } else {
                                                    // Empty slot → show "+" button to add punch (neutral style)
                                                    return DataCell(Center(
                                                      child: InkWell(
                                                        onTap: () => _showManualPunchDialog(record),
                                                        borderRadius: BorderRadius.circular(4),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: const Icon(Icons.add, size: 14, color: Colors.grey),
                                                        ),
                                                      ),
                                                    ));
                                                  }
                                                }),
                                                DataCell(Center(child: record.lateMinutes > 0 ? _buildMinutesBadge(record.lateMinutes, Colors.orange) : const Text('-', style: TextStyle(fontSize: 12)))),
                                                DataCell(Center(child: record.earlyMinutes > 0 ? _buildMinutesBadge(record.earlyMinutes, Colors.red) : const Text('-', style: TextStyle(fontSize: 12)))),
                                                DataCell(Center(child: record.overtimeMinutes > 0 ? _buildMinutesBadge(record.overtimeMinutes, Colors.purple) : const Text('-', style: TextStyle(fontSize: 12)))),
                                                DataCell(Center(child: _buildHoursBadge(record.workHours))),
                                                DataCell(Center(child: _buildDecimalHoursBadge(record.decimalHours))),
                                                DataCell(Center(child: _buildWorkCountBadge(record.workCount))),
                                                DataCell(Center(child: _buildShiftNameBadge(record.shiftNames.isNotEmpty ? record.shiftNames.join(', ') : null))),
                                                DataCell(Center(child: _buildStatusBadge(record.status, record.statusColor))),
                                              ],
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Pagination bar
                            _buildPaginationBar(totalRows, totalPages),
                          ],
                        );
                      },
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(DateTimeRange range) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final datePreset = _buildDropdown<String>(
      value: _selectedPreset,
      items: const [
        DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
        DropdownMenuItem(value: 'yesterday', child: Text('Hôm qua')),
        DropdownMenuItem(value: 'week', child: Text('Tuần này')),
        DropdownMenuItem(value: 'lastWeek', child: Text('Tuần trước')),
        DropdownMenuItem(value: 'month', child: Text('Tháng này')),
        DropdownMenuItem(value: 'lastMonth', child: Text('Tháng trước')),
      ],
      onChanged: (v) {
        if (v != null) setState(() { _selectedPreset = v; _currentPage = 0; });
      },
      icon: Icons.calendar_today,
      width: isMobile ? 120 : null,
    );

    final dateRange = _buildDateRangeDisplay(range);

    final employeeFilter = _buildEmployeeFilter();

    final shiftFilter = _buildDropdown<String>(
      value: _shiftFilter,
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả ca')),
        DropdownMenuItem(value: 'missing', child: Text('Thiếu chấm công')),
        DropdownMenuItem(value: 'complete', child: Text('Đủ chấm công')),
      ],
      onChanged: (v) {
        if (v != null) setState(() { _shiftFilter = v; _currentPage = 0; });
      },
      icon: Icons.warning_amber_rounded,
      width: isMobile ? 150 : null,
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
          Icon(Icons.calendar_view_day, color: Theme.of(context).primaryColor, size: 16),
          const SizedBox(width: 6),
          Text(
            'Theo ca · ${_shiftData.length} bản ghi',
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
                Row(
                  children: [
                    summaryChip,
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: _showMobileFilters ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _showMobileFilters ? Theme.of(context).primaryColor.withValues(alpha: 0.3) : const Color(0xFFE4E4E7)),
                        ),
                        child: Stack(
                          children: [
                            Center(child: Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18, color: _showMobileFilters ? Theme.of(context).primaryColor : Colors.grey.shade600)),
                            if (_selectedPreset != 'month' || _selectedEmployeeIds.isNotEmpty || _shiftFilter != 'all')
                              Positioned(top: 4, right: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_showMobileFilters) ...[
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
          style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
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
                            style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
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
                      Icon(icon, size: 14, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: DefaultTextStyle(
                          style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
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

  Widget _buildDateRangeDisplay(DateTimeRange range) {
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
          Icon(Icons.date_range, size: 14, color: Theme.of(context).primaryColor),
          const SizedBox(width: 6),
          Text(
            '${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}',
            style: const TextStyle(fontSize: 12),
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
            color: selectedCount > 0 ? Theme.of(context).primaryColor : const Color(0xFFE4E4E7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people, size: 14, color: selectedCount > 0 ? Theme.of(context).primaryColor : Colors.grey[500]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                selectedCount == 0
                    ? 'Tất cả nhân viên (${employees.length})'
                    : '$selectedCount nhân viên đã chọn',
                style: TextStyle(
                  fontSize: 12,
                  color: selectedCount > 0 ? Theme.of(context).primaryColor : Colors.grey[600],
                  fontWeight: selectedCount > 0 ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selectedCount > 0) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() { _selectedEmployeeIds = {}; _currentPage = 0; }),
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
                : employees.where((e) =>
                    e.name.toLowerCase().contains(searchText.toLowerCase()) ||
                    e.code.toLowerCase().contains(searchText.toLowerCase())).toList();

            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.people, color: Colors.blue, size: 22),
                  const SizedBox(width: 8),
                  const Text('Chọn nhân viên', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      if (tempSelected.length == employees.length) {
                        setDialogState(() => tempSelected.clear());
                      } else {
                        setDialogState(() => tempSelected.addAll(employees.map((e) => e.id)));
                      }
                    },
                    child: Text(
                      tempSelected.length == employees.length ? 'Bỏ chọn tất cả' : 'Chọn tất cả',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              content: SizedBox(
                width: math.min(380, MediaQuery.of(context).size.width - 32).toDouble(),
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Tìm nhân viên...',
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) => setDialogState(() => searchText = v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text('Đã chọn: ${tempSelected.length}/${employees.length}',
                              style: TextStyle(fontSize: 12, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
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
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? Theme.of(context).primaryColor.withValues(alpha: 0.08) : null,
                                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                    size: 20,
                                    color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                                  ),
                                  const SizedBox(width: 10),
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(emp.name.isNotEmpty ? emp.name[0].toUpperCase() : '?',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(emp.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                        Text(emp.code, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() { _selectedEmployeeIds = tempSelected; _currentPage = 0; });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Áp dụng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManualPunchDialog(_DailyShiftRecord record) {
    DateTime selectedDate = record.date;
    TimeOfDay selectedTime = TimeOfDay.now();
    final int punchIndex = record.punchTimes.length + 1;
    final bool isIn = (record.punchTimes.length).isEven;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_circle, color: Colors.blue),
              SizedBox(width: 8),
              Text('Thêm chấm công'),
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
                        Text('Nhân viên: ${record.employeeName}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Mã NV: ${record.employeeCode}'),
                        Text('Ngày: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                        Text('Lần chấm: $punchIndex (${isIn ? "Vào" : "Ra"})'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn ngày (cho ca qua đêm)
                const Text('Ngày chấm công:',
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
                    if (picked != null) setDialogState(() => selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(DateFormat('dd/MM/yyyy').format(selectedDate),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (selectedDate != record.date) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Ngày hôm sau',
                                style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
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
                const Text('Chọn giờ chấm công:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: selectedTime);
                    if (picked != null) setDialogState(() => selectedTime = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(isIn ? Icons.login : Icons.logout,
                            color: isIn ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const Icon(Icons.access_time),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Xác nhận'),
              onPressed: () async {
                final punchTime = DateTime(
                  selectedDate.year, selectedDate.month, selectedDate.day,
                  selectedTime.hour, selectedTime.minute,
                );
                final api = ApiService();
                final success = await api.createManualAttendance(
                  employeeId: record.employeeCode,
                  punchTime: punchTime,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (success && mounted) {
                  NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Chấm công thủ công thành công');
                  widget.onDataChanged?.call();
                } else if (mounted) {
                  NotificationOverlayManager().showError(title: 'Lỗi', message: 'Chấm công thất bại');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Summary totals bar
  String _formatHoursMinutes(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return '${h}h${m > 0 ? '${m}p' : ''}';
  }

  Widget _buildColumnHeaderWithTotal(String title, String total, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(total, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }

  Widget _buildStatsRow(int totalRows, int uniqueEmployees, double totalHours, int totalLate, int totalEarly, int totalOT) {
    final cards = [
      _buildModernStatCard('Bản ghi', '$totalRows', Icons.list_alt, const Color(0xFF1E3A5F)),
      _buildModernStatCard('Nhân viên', '$uniqueEmployees', Icons.people_outline, const Color(0xFF0F2340)),
      _buildModernStatCard('Tổng giờ', '${totalHours.toStringAsFixed(1)}h', Icons.schedule, const Color(0xFF1E3A5F)),
      _buildModernStatCard('Đi trễ', '$totalLate', Icons.timer_off_outlined, const Color(0xFFF59E0B)),
      _buildModernStatCard('Về sớm', '$totalEarly', Icons.exit_to_app, const Color(0xFFEF4444)),
      _buildModernStatCard('Tăng ca', '$totalOT', Icons.more_time, const Color(0xFF0F2340)),
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
      children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: c))).toList(),
    );
  }

  Widget _buildModernStatCard(String label, String value, IconData icon, Color color) {
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
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
                Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftDeckItem(_DailyShiftRecord record) {
    final dayOfWeek = _getDayOfWeekVN(record.date.weekday);
    final dateStr = DateFormat('dd/MM/yyyy').format(record.date);

    return InkWell(
      onTap: () {
        final cardKey = record.date.millisecondsSinceEpoch ^ record.employeeId.hashCode;
        setState(() {
          if (_expandedCardIndices.contains(cardKey)) {
            _expandedCardIndices.remove(cardKey);
          } else {
            _expandedCardIndices.add(cardKey);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: record.statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Center(child: Text(dayOfWeek.substring(0, 2), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: record.statusColor))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(record.employeeName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([dateStr, record.shiftNames.join(', '), '${record.workHours.toStringAsFixed(1)}h'].where((s) => s.isNotEmpty).join(' \u00b7 '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: record.statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(record.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: record.statusColor)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  /// Pagination bar
  Widget _buildPaginationBar(int totalRows, int totalPages) {
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
      child: Text(
        'Hiển thị $startRow-$endRow / $totalRows',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF16A34A)),
      ),
    );

    final rowsPerPageWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Số dòng:', style: TextStyle(fontSize: 12, color: Color(0xFFA1A1AA))),
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
              style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyMedium?.color),
              items: const [
                DropdownMenuItem(value: 20, child: Text('20')),
                DropdownMenuItem(value: 50, child: Text('50')),
                DropdownMenuItem(value: 100, child: Text('100')),
              ],
              onChanged: (v) {
                if (v != null) setState(() { _rowsPerPage = v; _currentPage = 0; });
              },
            ),
          ),
        ),
      ],
    );

    final navWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPageNavBtn(Icons.first_page, _currentPage > 0, () => setState(() => _currentPage = 0)),
        const SizedBox(width: 4),
        _buildPageNavBtn(Icons.chevron_left, _currentPage > 0, () => setState(() => _currentPage--)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages - 1, () => setState(() => _currentPage++)),
        const SizedBox(width: 4),
        _buildPageNavBtn(Icons.last_page, _currentPage < totalPages - 1, () => setState(() => _currentPage = totalPages - 1)),
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
          child: Icon(icon, size: 18, color: enabled ? const Color(0xFF52525B) : const Color(0xFFCBD5E1)),
        ),
      ),
    );
  }

  /// Dialog sửa giờ chấm công
  void _showEditPunchDialog(_DailyShiftRecord record, int punchIndex) {
    if (punchIndex >= record.attendanceIds.length) return;
    final attendanceId = record.attendanceIds[punchIndex];
    final originalTime = record.punchTimes[punchIndex];
    DateTime selectedDate = DateTime(originalTime.year, originalTime.month, originalTime.day);
    TimeOfDay selectedTime = TimeOfDay(hour: originalTime.hour, minute: originalTime.minute);
    final bool isIn = punchIndex.isEven;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.orange),
              SizedBox(width: 8),
              Text('Sửa/Xóa chấm công'),
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
                        Text('Nhân viên: ${record.employeeName}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Mã NV: ${record.employeeCode}'),
                        Text('Ngày: ${DateFormat('dd/MM/yyyy').format(record.date)}'),
                        Text('Lần chấm: ${punchIndex + 1} (${isIn ? "Vào" : "Ra"})'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('Giờ hiện tại: '),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                DateFormat('HH:mm').format(originalTime),
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
                const Text('Ngày:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedDate,
                      firstDate: record.date,
                      lastDate: record.date.add(const Duration(days: 1)),
                    );
                    if (picked != null) setDialogState(() => selectedDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(DateFormat('dd/MM/yyyy').format(selectedDate),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (selectedDate != DateTime(record.date.year, record.date.month, record.date.day)) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Ngày hôm sau',
                                style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
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
                const Text('Sửa thành giờ mới:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(context: ctx, initialTime: selectedTime);
                    if (picked != null) setDialogState(() => selectedTime = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const Icon(Icons.access_time),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Nút xóa
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _confirmDeletePunch(record, punchIndex);
              },
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text('Xóa', style: TextStyle(color: Colors.red)),
            ),
            const SizedBox(width: 16),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Lưu'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () async {
                final newTime = DateTime(
                  selectedDate.year, selectedDate.month, selectedDate.day,
                  selectedTime.hour, selectedTime.minute,
                );
                final api = ApiService();
                final success = await api.updateAttendance(attendanceId, attendanceTime: newTime);
                if (ctx.mounted) Navigator.pop(ctx);
                if (success && mounted) {
                  NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã cập nhật giờ chấm công');
                  widget.onDataChanged?.call();
                } else if (mounted) {
                  NotificationOverlayManager().showError(title: 'Lỗi', message: 'Cập nhật thất bại');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePunch(_DailyShiftRecord record, int punchIndex) {
    if (punchIndex >= record.attendanceIds.length) return;
    final attendanceId = record.attendanceIds[punchIndex];
    final punchTime = record.punchTimes[punchIndex];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Xác nhận xóa'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bạn có chắc muốn xóa lần chấm công này?'),
            const SizedBox(height: 8),
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nhân viên: ${record.employeeName}'),
                    Text('Ngày: ${DateFormat('dd/MM/yyyy').format(record.date)}'),
                    Text('Lần chấm: ${punchIndex + 1} - ${DateFormat('HH:mm').format(punchTime)}'),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton.icon(
            icon: const Icon(Icons.delete),
            label: const Text('Xóa'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final api = ApiService();
              final success = await api.deleteAttendance(attendanceId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (success && mounted) {
                NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa chấm công');
                widget.onDataChanged?.call();
              } else if (mounted) {
                NotificationOverlayManager().showError(title: 'Lỗi', message: 'Xóa thất bại');
              }
            },
          ),
        ],
      ),
    );
  }

  /// Export to Excel
  Future<void> exportToExcel() async {
    final records = _shiftData;
    if (records.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      int maxPunches = records.fold(0, (m, r) => r.punchTimes.length > m ? r.punchTimes.length : m);
      if (maxPunches < 4) maxPunches = 4;
      final punchColCount = maxPunches.isEven ? maxPunches : maxPunches + 1;

      final excelFile = excel_lib.Excel.createExcel();
      final sheet = excelFile['Theo ca'];

      final headers = <String>['STT', 'Tên nhân viên', 'Mã nhân viên', 'Thứ', 'Ngày'];
      for (int i = 1; i <= punchColCount; i++) {
        headers.add('Lần $i');
      }
      headers.addAll(['Đi trễ', 'Về sớm', 'Tăng ca', 'Tổng giờ', 'Giờ (thập phân)', 'Công', 'Tên ca', 'Trạng thái']);

      for (int i = 0; i < headers.length; i++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
            excel_lib.TextCellValue(headers[i]);
      }

      for (int idx = 0; idx < records.length; idx++) {
        final r = records[idx];
        int col = 0;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.IntCellValue(idx + 1);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.employeeName);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.employeeCode);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.dayOfWeek);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(DateFormat('dd/MM/yyyy').format(r.date));

        for (int i = 0; i < punchColCount; i++) {
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
              excel_lib.TextCellValue(i < r.punchTimes.length ? DateFormat('HH:mm').format(r.punchTimes[i]) : '');
        }

        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.lateMinutes > 0 ? '${r.lateMinutes}P' : '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.earlyMinutes > 0 ? '${r.earlyMinutes}P' : '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.overtimeMinutes > 0 ? '${r.overtimeMinutes}P' : '');
        final h = r.workHours.floor();
        final m = ((r.workHours - h) * 60).round();
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.workHours > 0 ? '${h}h${m > 0 ? '${m}p' : ''}' : '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.DoubleCellValue(double.parse(r.decimalHours.toStringAsFixed(2)));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.workCount == r.workCount.roundToDouble() ? '${r.workCount.toInt()}' : r.workCount.toStringAsFixed(2));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.shiftNames.join(', '));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(r.status);
      }

      // Summary totals row
      final totalRow = records.length + 1;
      int sumLate = records.fold(0, (s, r) => s + r.lateMinutes);
      int sumEarly = records.fold(0, (s, r) => s + r.earlyMinutes);
      int sumOT = records.fold(0, (s, r) => s + r.overtimeMinutes);
      double sumHours = records.fold(0.0, (s, r) => s + r.workHours);
      double sumDecimal = records.fold(0.0, (s, r) => s + r.decimalHours);
      double sumWork = records.fold(0.0, (s, r) => s + r.workCount);

      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow)).value =
          excel_lib.TextCellValue('TỔNG');
      int tCol = 5 + punchColCount; // skip STT, Name, Code, Day, Date, punches
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: tCol++, rowIndex: totalRow)).value =
          excel_lib.TextCellValue('${sumLate}P');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: tCol++, rowIndex: totalRow)).value =
          excel_lib.TextCellValue('${sumEarly}P');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: tCol++, rowIndex: totalRow)).value =
          excel_lib.TextCellValue('${sumOT}P');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: tCol++, rowIndex: totalRow)).value =
          excel_lib.TextCellValue(_formatHoursMinutes(sumHours));
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: tCol++, rowIndex: totalRow)).value =
          excel_lib.DoubleCellValue(double.parse(sumDecimal.toStringAsFixed(2)));
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: tCol++, rowIndex: totalRow)).value =
          excel_lib.TextCellValue(sumWork == sumWork.roundToDouble() ? '${sumWork.toInt()}' : sumWork.toStringAsFixed(2));

      final bytes = excelFile.encode();
      if (bytes != null) {
        final range = _selectedDateRange;
        final fileName = 'Tong_hop_theo_ca_${DateFormat('ddMMyyyy').format(range.start)}_${DateFormat('ddMMyyyy').format(range.end)}.xlsx';
        await file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
    } catch (e) {
      debugPrint('Error exporting Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Export to PNG
  Future<void> exportToPng() async {
    final records = _shiftData;
    if (records.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Không có dữ liệu', message: 'Không có dữ liệu để xuất');
      return;
    }
    setState(() => _isExporting = true);

    try {
      int maxPunches = records.fold(0, (m, r) => r.punchTimes.length > m ? r.punchTimes.length : m);
      if (maxPunches < 4) maxPunches = 4;
      final punchColCount = maxPunches.isEven ? maxPunches : maxPunches + 1;

      final headers = <String>['STT', 'Tên nhân viên', 'Mã nhân viên', 'Thứ', 'Ngày'];
      for (int i = 1; i <= punchColCount; i++) {
        headers.add('Lần $i');
      }
      headers.addAll(['Đi trễ', 'Về sớm', 'Tăng ca', 'Tổng giờ', 'Giờ (thập phân)', 'Công', 'Tên ca', 'Trạng thái']);

      final rows = <List<String>>[];
      for (int idx = 0; idx < records.length; idx++) {
        final r = records[idx];
        final row = <String>['${idx + 1}', r.employeeName, r.employeeCode, r.dayOfWeek, DateFormat('dd/MM/yyyy').format(r.date)];
        for (int i = 0; i < punchColCount; i++) {
          row.add(i < r.punchTimes.length ? DateFormat('HH:mm').format(r.punchTimes[i]) : '');
        }
        final h = r.workHours.floor();
        final m = ((r.workHours - h) * 60).round();
        row.add(r.lateMinutes > 0 ? '${r.lateMinutes}P' : '');
        row.add(r.earlyMinutes > 0 ? '${r.earlyMinutes}P' : '');
        row.add(r.overtimeMinutes > 0 ? '${r.overtimeMinutes}P' : '');
        row.add(r.workHours > 0 ? '${h}h${m > 0 ? '${m}p' : ''}' : '');
        row.add(r.decimalHours > 0 ? r.decimalHours.toStringAsFixed(2) : '');
        row.add(r.workCount == r.workCount.roundToDouble() ? '${r.workCount.toInt()}' : r.workCount.toStringAsFixed(2));
        row.add(r.shiftNames.join(', '));
        row.add(r.status);
        rows.add(row);
      }

      // Add summary totals row
      int pngSumLate = records.fold(0, (s, r) => s + r.lateMinutes);
      int pngSumEarly = records.fold(0, (s, r) => s + r.earlyMinutes);
      int pngSumOT = records.fold(0, (s, r) => s + r.overtimeMinutes);
      double pngSumHours = records.fold(0.0, (s, r) => s + r.workHours);
      double pngSumDecimal = records.fold(0.0, (s, r) => s + r.decimalHours);
      double pngSumWork = records.fold(0.0, (s, r) => s + r.workCount);
      final totalRow = List.filled(headers.length, '');
      totalRow[0] = 'TỔNG';
      final tColStart = 5 + punchColCount;
      totalRow[tColStart] = '${pngSumLate}P';
      totalRow[tColStart + 1] = '${pngSumEarly}P';
      totalRow[tColStart + 2] = '${pngSumOT}P';
      totalRow[tColStart + 3] = _formatHoursMinutes(pngSumHours);
      totalRow[tColStart + 4] = pngSumDecimal.toStringAsFixed(2);
      totalRow[tColStart + 5] = pngSumWork == pngSumWork.roundToDouble() ? '${pngSumWork.toInt()}' : pngSumWork.toStringAsFixed(2);
      rows.add(totalRow);

      const double cellPadding = 12;
      const double fontSize = 13;
      const double headerFontSize = 14;
      const double rowHeight = 32;
      const double headerHeight = 40;
      const double titleHeight = 50;

      final colWidths = <double>[];
      for (int c = 0; c < headers.length; c++) {
        double maxW = headers[c].length * 9.0 + cellPadding * 2;
        for (final row in rows) {
          if (c < row.length) {
            final w = row[c].length * 8.0 + cellPadding * 2;
            if (w > maxW) maxW = w;
          }
        }
        if (c == 1) maxW = maxW.clamp(150, 250);
        colWidths.add(maxW.clamp(60, 250));
      }

      final totalWidth = colWidths.fold(0.0, (sum, w) => sum + w) + 2;
      final totalHeight = titleHeight + headerHeight + rows.length * rowHeight + 2;

      final dataUrl = web_canvas.renderToPngDataUrl(
        width: totalWidth.toInt(),
        height: totalHeight.toInt(),
        draw: (ctx) {
          ctx.fillStyle = '#FFFFFF';
          ctx.fillRect(0, 0, totalWidth, totalHeight);

          ctx.fillStyle = '#1a1a1a';
          ctx.font = 'bold 16px Arial, sans-serif';
          final range = _selectedDateRange;
          final title = 'Tổng hợp theo ca - ${DateFormat('dd/MM/yyyy').format(range.start)} đến ${DateFormat('dd/MM/yyyy').format(range.end)}';
          ctx.fillText(title, 10, 30);

          double x = 1;
          const headerY = titleHeight;
          ctx.fillStyle = '#F0F4F8';
          ctx.fillRect(1, headerY, totalWidth - 2, headerHeight);
          ctx.strokeStyle = '#CBD5E1';
          ctx.lineWidth = 1;
          ctx.strokeRect(1, headerY, totalWidth - 2, headerHeight);

          for (int c = 0; c < headers.length; c++) {
            ctx.fillStyle = '#334155';
            ctx.font = 'bold ${headerFontSize}px Arial, sans-serif';
            ctx.fillText(headers[c], x + cellPadding, headerY + headerHeight / 2 + 5);
            ctx.strokeStyle = '#E2E8F0';
            ctx.beginPath();
            ctx.moveTo(x + colWidths[c], headerY);
            ctx.lineTo(x + colWidths[c], totalHeight);
            ctx.stroke();
            x += colWidths[c];
          }

          for (int r = 0; r < rows.length; r++) {
            final rowY = titleHeight + headerHeight + r * rowHeight;
            final isLastRow = r == rows.length - 1; // Summary totals row
            if (isLastRow) {
              ctx.fillStyle = '#EBF5FF';
              ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
            } else if (r % 2 == 1) {
              ctx.fillStyle = '#F8FAFC';
              ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
            }
            ctx.strokeStyle = '#E2E8F0';
            ctx.beginPath();
            ctx.moveTo(1, rowY + rowHeight);
            ctx.lineTo(totalWidth - 1, rowY + rowHeight);
            ctx.stroke();

            x = 1;
            for (int c = 0; c < rows[r].length && c < colWidths.length; c++) {
              final cellText = rows[r][c];
              if (isLastRow) {
                ctx.fillStyle = '#1E40AF';
                ctx.font = 'bold ${fontSize}px Arial, sans-serif';
              } else if (c >= 5 && c < 5 + punchColCount && cellText.isNotEmpty) {
                final punchIdx = c - 5;
                ctx.fillStyle = punchIdx % 2 == 0 ? '#059669' : '#DC2626'; // Xanh=vào, Đỏ=ra
                ctx.font = '${fontSize}px Arial, sans-serif';
              } else {
                ctx.fillStyle = '#334155';
                ctx.font = '${fontSize}px Arial, sans-serif';
              }
              ctx.fillText(cellText, x + cellPadding, rowY + rowHeight / 2 + 5);
              x += colWidths[c];
            }
          }

          ctx.strokeStyle = '#CBD5E1';
          ctx.lineWidth = 1;
          ctx.strokeRect(1, titleHeight, totalWidth - 2, totalHeight - titleHeight - 1);
        },
      );

      if (dataUrl != null) {
        final fileName = 'Tong_hop_theo_ca_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
        await file_saver.saveDataUrl(dataUrl, fileName);

        if (mounted) {
          NotificationOverlayManager().showSuccess(title: 'Xuất PNG', message: 'Đã xuất ảnh PNG: $fileName');
        }
      } else {
        // Mobile fallback: use async renderer with same draw callback
        final drawFn = (dynamic ctx) {
          ctx.fillStyle = '#FFFFFF';
          ctx.fillRect(0, 0, totalWidth, totalHeight);
          ctx.fillStyle = '#1a1a1a';
          ctx.font = 'bold 16px Arial, sans-serif';
          final range = _selectedDateRange;
          final title = 'Tổng hợp theo ca - ${DateFormat('dd/MM/yyyy').format(range.start)} đến ${DateFormat('dd/MM/yyyy').format(range.end)}';
          ctx.fillText(title, 10, 30);
          double x = 1;
          const hdrY = titleHeight;
          ctx.fillStyle = '#F0F4F8';
          ctx.fillRect(1, hdrY, totalWidth - 2, headerHeight);
          ctx.strokeStyle = '#CBD5E1';
          ctx.lineWidth = 1;
          ctx.strokeRect(1, hdrY, totalWidth - 2, headerHeight);
          for (int c = 0; c < headers.length; c++) {
            ctx.fillStyle = '#334155';
            ctx.font = 'bold ${headerFontSize}px Arial, sans-serif';
            ctx.fillText(headers[c], x + cellPadding, hdrY + headerHeight / 2 + 5);
            ctx.strokeStyle = '#E2E8F0';
            ctx.beginPath();
            ctx.moveTo(x + colWidths[c], hdrY);
            ctx.lineTo(x + colWidths[c], totalHeight);
            ctx.stroke();
            x += colWidths[c];
          }
          for (int r = 0; r < rows.length; r++) {
            final rowY = titleHeight + headerHeight + r * rowHeight;
            final isLastRow = r == rows.length - 1;
            if (isLastRow) {
              ctx.fillStyle = '#EBF5FF';
              ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
            } else if (r % 2 == 1) {
              ctx.fillStyle = '#F8FAFC';
              ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
            }
            ctx.strokeStyle = '#E2E8F0';
            ctx.beginPath();
            ctx.moveTo(1, rowY + rowHeight);
            ctx.lineTo(totalWidth - 1, rowY + rowHeight);
            ctx.stroke();
            x = 1;
            for (int c = 0; c < rows[r].length && c < colWidths.length; c++) {
              final cellText = rows[r][c];
              if (isLastRow) {
                ctx.fillStyle = '#1E40AF';
                ctx.font = 'bold ${fontSize}px Arial, sans-serif';
              } else if (c >= 5 && c < 5 + punchColCount && cellText.isNotEmpty) {
                final punchIdx = c - 5;
                ctx.fillStyle = punchIdx % 2 == 0 ? '#059669' : '#DC2626';
                ctx.font = '${fontSize}px Arial, sans-serif';
              } else {
                ctx.fillStyle = '#334155';
                ctx.font = '${fontSize}px Arial, sans-serif';
              }
              ctx.fillText(cellText, x + cellPadding, rowY + rowHeight / 2 + 5);
              x += colWidths[c];
            }
          }
          ctx.strokeStyle = '#CBD5E1';
          ctx.lineWidth = 1;
          ctx.strokeRect(1, titleHeight, totalWidth - 2, totalHeight - titleHeight - 1);
        };
        final pngBytes = await web_canvas.renderToPngBytes(
          width: totalWidth.toInt(),
          height: totalHeight.toInt(),
          draw: drawFn,
        );
        if (pngBytes != null && mounted) {
          final fileName = 'Tong_hop_theo_ca_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
          await file_saver.saveFileBytes(pngBytes, fileName, 'image/png');
          NotificationOverlayManager().showSuccess(title: 'Xuất PNG', message: 'Đã xuất ảnh PNG: $fileName');
        } else if (mounted) {
          NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể xuất PNG');
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xuất PNG: $e');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildDayBadge(String day, int weekday) {
    final color = weekday == DateTime.sunday ? Colors.red : 
                  weekday == DateTime.saturday ? Colors.orange : Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(day, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
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
            DateFormat('HH:mm').format(time),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
          const SizedBox(width: 2),
          Icon(Icons.edit, size: 10, color: color.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  Widget _buildShiftNameBadge(String? name) {
    if (name == null || name.isEmpty) return const Text('-', style: TextStyle(fontSize: 12));
    // Assign colors based on common shift name patterns
    Color color = Colors.blue;
    final lower = name.toLowerCase();
    if (lower.contains('sáng') || lower.contains('sang')) {
      color = Colors.blue;
    } else if (lower.contains('chiều') || lower.contains('chieu')) {
      color = Colors.purple;
    } else if (lower.contains('tối') || lower.contains('toi')) {
      color = Colors.indigo;
    } else if (lower.contains('đêm') || lower.contains('dem') || lower.contains('qua đêm')) {
      color = Colors.deepPurple;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(name, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
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
        '${minutes}P',
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }

  Widget _buildHoursBadge(double hours) {
    if (hours <= 0) return const Text('-', style: TextStyle(fontSize: 12));
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${h}h${m > 0 ? '${m}p' : ''}',
        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }

  Widget _buildStatusBadge(String status, Color color) {
    IconData icon = Icons.check_circle;
    if (status.contains('Thiếu chấm')) icon = Icons.help;
    if (status.contains('Đi trễ')) icon = Icons.timer_off;
    if (status.contains('Về sớm')) icon = Icons.exit_to_app;
    if (status.contains('Đi trễ') && status.contains('Về sớm')) icon = Icons.warning;
    if (status.contains('Tăng ca ngày nghỉ')) icon = Icons.event_busy;
    if (status.contains('Tăng ca ngày lễ')) icon = Icons.celebration;
    
    return Container(
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
          Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
        ],
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
        count == count.roundToDouble() ? '${count.toInt()}' : count.toStringAsFixed(2),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _buildDecimalHoursBadge(double hours) {
    if (hours <= 0) return const Text('-', style: TextStyle(fontSize: 12));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        hours.toStringAsFixed(2),
        style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.w600, fontSize: 11),
      ),
    );
  }
}

class _DailyShiftRecord {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final DateTime date;
  final String dayOfWeek;
  final List<DateTime> punchTimes;
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

  _DailyShiftRecord({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.date,
    required this.dayOfWeek,
    required this.punchTimes,
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
  });
}

class _EmployeeOption {
  final String id;
  final String name;
  final String code;
  _EmployeeOption({required this.id, required this.name, required this.code});
}
