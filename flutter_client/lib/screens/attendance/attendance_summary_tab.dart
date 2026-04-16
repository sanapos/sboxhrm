import 'dart:math' as math;
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/web_canvas.dart' as web_canvas;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../widgets/notification_overlay.dart';
import '../../utils/responsive_helper.dart';

/// Model cho yêu cầu chỉnh sửa chấm công
class AttendanceCorrectionRequest {
  final String id;
  final String employeeName;
  final String employeeCode;
  final String? pin; // PIN/mã chấm công gốc
  final String? attendanceId; // ID bản ghi attendance gốc
  final String? employeeUserId;
  final DateTime requestDate;
  final DateTime correctionDate;
  final String reason;
  final String correctionType; // 'add', 'edit', 'delete'
  final String requestedTime;
  final int punchIndex; // Lần chấm công (1-10)
  final DateTime? originalTime; // Thời gian cũ (nếu sửa/xóa)
  final String? newType;
  final String? approverId;
  final String? approverName;

  AttendanceCorrectionRequest({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    this.pin,
    this.attendanceId,
    this.employeeUserId,
    required this.requestDate,
    required this.correctionDate,
    required this.reason,
    required this.correctionType,
    required this.requestedTime,
    required this.punchIndex,
    this.originalTime,
    this.newType,
    this.approverId,
    this.approverName,
  });
}

class AttendanceSummaryTab extends StatefulWidget {
  final List<Attendance> attendances;
  final List<Device> devices;
  final DateTime fromDate;
  final DateTime toDate;
  final Function(AttendanceCorrectionRequest)? onCorrectionRequest;
  final int dayEndHour;
  final int dayEndMinute;

  const AttendanceSummaryTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.fromDate,
    required this.toDate,
    this.onCorrectionRequest,
    this.dayEndHour = 0,
    this.dayEndMinute = 0,
  });

  @override
  State<AttendanceSummaryTab> createState() => _AttendanceSummaryTabState();
}

class _AttendanceSummaryTabState extends State<AttendanceSummaryTab> {
  String _selectedPreset = 'month';
  Set<String> _selectedEmployeeIds = {}; // Set of selected employee IDs for multi-select
  int _rowsPerPage = 50;
  int _currentPage = 0;
  bool _isExporting = false;
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;
  final GlobalKey _tableKey = GlobalKey();
  String _shiftFilter = 'all'; // 'all' | 'missing' | 'complete'

  // Sorting
  String _sortColumn = 'name';
  bool _sortAscending = true;

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

  /// Get unique employees from all attendances (not filtered by date)
  List<_EmployeeOption> get _allEmployees {
    final Map<String, _EmployeeOption> map = {};
    for (final att in widget.attendances) {
      final id = att.employeeId ?? att.enrollNumber ?? 'unknown';
      if (!map.containsKey(id)) {
        final name = att.employeeName?.isNotEmpty == true
            ? att.employeeName!
            : (att.deviceUserName?.isNotEmpty == true
                ? att.deviceUserName!
                : '-');
        final code = att.employeeId?.isNotEmpty == true
            ? att.employeeId!
            : (att.enrollNumber ?? '-');
        map[id] = _EmployeeOption(
          id: id,
          name: name,
          code: code,
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
          end: DateTime(
              yesterday.year, yesterday.month, yesterday.day, 23, 59, 59),
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
          end: DateTime(
              lastSunday.year, lastSunday.month, lastSunday.day, 23, 59, 59),
        );
      case 'month':
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case 'lastMonth':
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        final lastDayOfLastMonth = DateTime(now.year, now.month, 0);
        return DateTimeRange(
          start: lastMonth,
          end: DateTime(lastDayOfLastMonth.year, lastDayOfLastMonth.month,
              lastDayOfLastMonth.day, 23, 59, 59),
        );
      default:
        return DateTimeRange(start: widget.fromDate, end: widget.toDate);
    }
  }

  /// Lọc attendances theo preset và search
  List<Attendance> get _filteredAttendances {
    final range = _selectedDateRange;
    var result = widget.attendances.where((att) {
      return att.punchTime
              .isAfter(range.start.subtract(const Duration(seconds: 1))) &&
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

  /// Tạo dữ liệu tổng hợp theo ngày - mỗi dòng là 1 nhân viên + 1 ngày
  List<_DailySummary> get _dailySummaryData {
    // Sử dụng _filteredAttendances thay vì widget.attendances
    final filteredData = _filteredAttendances;

    // Group attendances by employee + date
    final Map<String, List<Attendance>> groupedByEmployeeDate = {};

    for (final att in filteredData) {
      final employeeKey = att.employeeId ?? att.enrollNumber ?? 'unknown';
      final logicalDate = _getLogicalDate(att.punchTime);
      final dateKey = DateFormat('yyyy-MM-dd').format(logicalDate);
      final key = '$employeeKey|$dateKey';
      groupedByEmployeeDate.putIfAbsent(key, () => []).add(att);
    }

    // Create daily summary for each employee + date
    final summaries = <_DailySummary>[];

    groupedByEmployeeDate.forEach((key, attendances) {
      if (attendances.isEmpty) return;

      // Sort by time ascending
      attendances.sort((a, b) => a.punchTime.compareTo(b.punchTime));

      final first = attendances.first;
      final date = _getLogicalDate(first.punchTime);

      // Get punch times (up to 10) và IDs tương ứng
      final punches = <DateTime?>[];
      final punchIds = <String?>[];
      for (int i = 0; i < 10; i++) {
        if (attendances.length > i) {
          punches.add(attendances[i].punchTime);
          punchIds.add(attendances[i].id);
        } else {
          punches.add(null);
          punchIds.add(null);
        }
      }

      // Calculate shift hours (5 shifts max)
      // Ca 1: Lần 2 - Lần 1
      // Ca 2: Lần 4 - Lần 3
      // Ca 3: Lần 6 - Lần 5
      // Ca 4: Lần 8 - Lần 7
      // Ca 5: Lần 10 - Lần 9
      List<double> shiftHours = [];
      for (int i = 0; i < 5; i++) {
        final punchIn = punches[i * 2];
        final punchOut = punches[i * 2 + 1];
        if (punchIn != null && punchOut != null) {
          shiftHours.add(punchOut.difference(punchIn).inMinutes / 60.0);
        } else {
          shiftHours.add(0);
        }
      }

      final totalShiftHours = shiftHours.fold(0.0, (sum, h) => sum + h);

      // Xác định tên & mã nhân viên đúng
      final empName = first.employeeName?.isNotEmpty == true
          ? first.employeeName!
          : (first.deviceUserName?.isNotEmpty == true
              ? first.deviceUserName!
              : '-');
      final empCode = first.employeeId?.isNotEmpty == true
          ? first.employeeId!
          : (first.enrollNumber ?? '-');

      summaries.add(_DailySummary(
        employeeId: empCode,
        employeeName: empName,
        employeeCode: empCode,
        pin: first.enrollNumber,
        date: date,
        punch1: punches[0],
        punch2: punches[1],
        punch3: punches[2],
        punch4: punches[3],
        punch5: punches[4],
        punch6: punches[5],
        punch7: punches[6],
        punch8: punches[7],
        punch9: punches[8],
        punch10: punches[9],
        punchId1: punchIds[0],
        punchId2: punchIds[1],
        punchId3: punchIds[2],
        punchId4: punchIds[3],
        punchId5: punchIds[4],
        punchId6: punchIds[5],
        punchId7: punchIds[6],
        punchId8: punchIds[7],
        punchId9: punchIds[8],
        punchId10: punchIds[9],
        shift1Hours: shiftHours[0],
        shift2Hours: shiftHours[1],
        shift3Hours: shiftHours[2],
        shift4Hours: shiftHours[3],
        shift5Hours: shiftHours[4],
        totalHours: totalShiftHours,
        totalPunches: attendances.length,
      ));
    });

    // Sort: default by employee name then date
    summaries.sort((a, b) {
      int cmp;
      if (_sortColumn == 'date') {
        cmp = a.date.compareTo(b.date);
        if (cmp == 0) cmp = a.employeeName.compareTo(b.employeeName);
      } else if (_sortColumn == 'name') {
        cmp = a.employeeName.compareTo(b.employeeName);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      } else if (_sortColumn == 'code') {
        cmp = a.employeeCode.compareTo(b.employeeCode);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      } else if (_sortColumn == 'totalHours') {
        cmp = a.totalHours.compareTo(b.totalHours);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      } else {
        cmp = a.employeeName.compareTo(b.employeeName);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      }
      return _sortAscending ? cmp : -cmp;
    });

    // Lọc theo trạng thái ca
    if (_shiftFilter == 'missing') {
      // Ca thiếu chấm công: số lần chấm lẻ (thiếu vào hoặc ra)
      return summaries.where((s) => s.totalPunches % 2 != 0 || s.totalPunches < 2).toList();
    } else if (_shiftFilter == 'complete') {
      // Ca đủ chấm công: số lần chấm chẵn >= 2
      return summaries.where((s) => s.totalPunches >= 2 && s.totalPunches % 2 == 0).toList();
    }

    return summaries;
  }

  String _getDayOfWeekVN(int weekday) {
    switch (weekday) {
      case 1:
        return 'Thứ 2';
      case 2:
        return 'Thứ 3';
      case 3:
        return 'Thứ 4';
      case 4:
        return 'Thứ 5';
      case 5:
        return 'Thứ 6';
      case 6:
        return 'Thứ 7';
      case 7:
        return 'CN';
      default:
        return '-';
    }
  }

  Color _getDayColor(int weekday) {
    if (weekday == 7) return Colors.red;
    if (weekday == 6) return Colors.orange;
    return Colors.grey;
  }

  String _formatHours(double hours) {
    if (hours <= 0) return '-';
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  String _formatDecimalHours(double hours) {
    if (hours <= 0) return '-';
    return hours.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final summaries = _dailySummaryData;
    final range = _selectedDateRange;

    // Calculate totals for summary bar
    double totalHours = summaries.fold(0.0, (sum, s) => sum + s.totalHours);
    final uniqueEmployees = summaries.map((s) => s.employeeId).toSet().length;
    int totalShifts = 0;
    for (final s in summaries) {
      if (s.shift1Hours > 0) totalShifts++;
      if (s.shift2Hours > 0) totalShifts++;
      if (s.shift3Hours > 0) totalShifts++;
      if (s.shift4Hours > 0) totalShifts++;
      if (s.shift5Hours > 0) totalShifts++;
    }

    // Pagination
    final totalRows = summaries.length;
    final totalPages = (totalRows / _rowsPerPage).ceil();
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalRows);
    final pagedSummaries = totalRows > 0 ? summaries.sublist(startIndex, endIndex) : <_DailySummary>[];

    // Tìm số lần chấm công tối đa thực tế trong dữ liệu
    int actualMaxPunches = 0;
    for (final s in summaries) {
      if (s.totalPunches > actualMaxPunches) actualMaxPunches = s.totalPunches;
    }
    // Mặc định hiển thị 2 lần (Lần 1, Lần 2) và 1 ca
    // Nếu có lần 3 → hiển thị 4 lần + 2 ca
    // Nếu có lần 5 → hiển thị 6 lần + 3 ca, v.v.
    int maxPunches = 2; // Mặc định: Lần 1, Lần 2
    if (actualMaxPunches > 2) {
      // Làm tròn lên số chẵn gần nhất
      maxPunches = ((actualMaxPunches + 1) ~/ 2) * 2;
    }
    if (maxPunches > 10) maxPunches = 10;
    int maxShifts = maxPunches ~/ 2; // Mỗi cặp lần = 1 ca
    if (maxShifts > 5) maxShifts = 5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stat cards row
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
              _buildStatsRow(totalRows, uniqueEmployees, totalHours, totalShifts),
            ],
          ] else ...[
            _buildStatsRow(totalRows, uniqueEmployees, totalHours, totalShifts),
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
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: summaries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text('Không có dữ liệu',
                              style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
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
                                  itemCount: summaries.length,
                                  itemBuilder: (_, index) {
                                    final summary = summaries[index];
                                    final dateStr = DateFormat('dd/MM/yyyy').format(summary.date);
                                    final dayOfWeek = _getDayOfWeekVN(summary.date.weekday);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFE4E4E7)),
                                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                                        ),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(12),
                                          onTap: () => _showRowDetailDialog(summary, maxPunches, maxShifts),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                            child: Row(children: [
                                              Container(
                                                width: 36, height: 36,
                                                decoration: BoxDecoration(color: _getDayColor(summary.date.weekday).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                                child: Center(child: Text(dayOfWeek.substring(0, 2), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _getDayColor(summary.date.weekday)))),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  Text(summary.employeeName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                  const SizedBox(height: 2),
                                                  Text([summary.employeeCode, dateStr].join(' \u00b7 '),
                                                    style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                                                ]),
                                              ),
                                              _buildHoursBadge(summary.totalHours, Colors.green, isBold: true),
                                              const SizedBox(width: 4),
                                              const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
                                            ]),
                                          ),
                                        ),
                                      ),
                                    );
                                    },
                                  ),
                              ),
                            ],
                          );
                        }
                        // Tạo columns động
                        final columns = <DataColumn>[
                          const DataColumn(
                              label: Expanded(child: Text('STT', textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Color(0xFF71717A))))),
                          DataColumn(
                              label: const Expanded(child: Text('Tên nhân viên', textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Color(0xFF71717A)))),
                              onSort: (_, asc) { setState(() { _sortColumn = 'name'; _sortAscending = asc; }); }),
                          DataColumn(
                              label: const Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Color(0xFF71717A)))),
                              onSort: (_, asc) { setState(() { _sortColumn = 'code'; _sortAscending = asc; }); }),
                          const DataColumn(
                              label: Expanded(child: Text('Thứ', textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Color(0xFF71717A))))),
                          DataColumn(
                              label: const Expanded(child: Text('Ngày', textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Color(0xFF71717A)))),
                              onSort: (_, asc) { setState(() { _sortColumn = 'date'; _sortAscending = asc; }); }),
                        ];

                        // Thêm cột cho các lần chấm công (động theo maxPunches)
                        for (int i = 1; i <= maxPunches; i++) {
                          columns.add(DataColumn(
                              label: Expanded(child: Text('Lần $i', textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Color(0xFF71717A))))));
                        }

                        // Thêm cột cho các ca (động theo maxShifts)
                        final shiftColors = [
                          Colors.teal,
                          Colors.indigo,
                          Colors.purple,
                          Colors.orange,
                          Colors.brown
                        ];
                        for (int i = 1; i <= maxShifts; i++) {
                          columns.add(DataColumn(
                              label: Expanded(child: Text('Giờ ca $i', textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                      color: Color(0xFF71717A))))));
                        }

                        // Cột tổng giờ
                        columns.add(DataColumn(
                            label: const Expanded(child: Text('Tổng giờ', textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Color(0xFF71717A)))),
                            onSort: (_, asc) { setState(() { _sortColumn = 'totalHours'; _sortAscending = asc; }); }));

                        // Cột giờ thập phân
                        columns.add(const DataColumn(
                            label: Expanded(child: Text('Giờ thập phân', textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: Color(0xFF71717A))))));

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
                                        child: RepaintBoundary(
                                          key: _tableKey,
                                          child: DataTable(
                                          showCheckboxColumn: false,
                                          sortColumnIndex: _sortColumn == 'name' ? 1 : _sortColumn == 'code' ? 2 : _sortColumn == 'totalHours' ? (5 + maxPunches + maxShifts) : 4,
                                          sortAscending: _sortAscending,
                                          headingRowColor: WidgetStateProperty.all(
                                            const Color(0xFFFAFAFA),
                                          ),
                                          dataRowColor: WidgetStateProperty.resolveWith((states) {
                                            if (states.contains(WidgetState.hovered)) {
                                              return Theme.of(context).primaryColor.withValues(alpha: 0.04);
                                            }
                                            return null;
                                          }),
                                          columnSpacing: 16,
                                          horizontalMargin: 12,
                                          headingRowHeight: 44,
                                          dataRowMinHeight: 40,
                                          dataRowMaxHeight: 46,
                                          dividerThickness: 0.5,
                                          columns: columns,
                                          rows: pagedSummaries.asMap().entries.map((entry) {
                                            final index = entry.key;
                                            final summary = entry.value;
                                            final dayOfWeek =
                                                _getDayOfWeekVN(summary.date.weekday);

                                            // Tạo cells động
                                            final cells = <DataCell>[
                                              DataCell(Center(child: Text('${startIndex + index + 1}',
                                                  style: const TextStyle(
                                                      fontSize: 12, color: Colors.grey)))),
                                              DataCell(Center(child: Text(summary.employeeName,
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500)))),
                                              DataCell(Center(child: Text(summary.employeeCode,
                                                  style: const TextStyle(fontSize: 12)))),
                                              DataCell(Center(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        _getDayColor(summary.date.weekday)
                                                            .withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    dayOfWeek,
                                                    style: TextStyle(
                                                      color: _getDayColor(
                                                          summary.date.weekday),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              )),
                                              DataCell(Center(child: Text(
                                                  DateFormat('dd/MM/yyyy')
                                                      .format(summary.date),
                                                  style: const TextStyle(fontSize: 12)))),
                                            ];

                                            // Thêm cells cho các lần chấm công
                                            for (int i = 1; i <= maxPunches; i++) {
                                              final isIn =
                                                  i % 2 == 1; // Lẻ = vào, chẵn = ra
                                              cells.add(DataCell(Center(child: _buildPunchTime(
                                                summary.getPunch(i),
                                                isIn: isIn,
                                                summary: summary,
                                                punchIndex: i,
                                              ))));
                                            }

                                            // Thêm cells cho các ca
                                            for (int i = 1; i <= maxShifts; i++) {
                                              cells.add(DataCell(Center(child: _buildHoursBadge(
                                                  summary.getShiftHours(i),
                                                  shiftColors[i - 1]))));
                                            }

                                            // Cell tổng giờ
                                            cells.add(DataCell(Center(child: _buildHoursBadge(
                                                summary.totalHours, Colors.green,
                                                isBold: true))));

                                            // Cell giờ thập phân
                                            cells.add(DataCell(Center(child: Text(
                                              _formatDecimalHours(summary.totalHours),
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: summary.totalHours > 0 ? Colors.blue.shade700 : Colors.grey,
                                              ),
                                            ))));

                                            return DataRow(
                                              cells: cells,
                                              onSelectChanged: (_) => _showRowDetailDialog(summary, maxPunches, maxShifts),
                                            );
                                          }).toList(),
                                        ),
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
            ),),
          ),
        ],
      ),
    );
  }

  /// Stats cards row
  Widget _buildStatsRow(int totalRows, int uniqueEmployees, double totalHours, int totalShifts) {
    final cards = [
      _buildModernStatCard('Bản ghi', '$totalRows', Icons.list_alt, const Color(0xFF1E3A5F)),
      _buildModernStatCard('Nhân viên', '$uniqueEmployees', Icons.people, const Color(0xFF0F2340)),
      _buildModernStatCard('Tổng giờ', '${_formatHours(totalHours)} (${totalHours.toStringAsFixed(1)}h)', Icons.schedule, const Color(0xFF1E3A5F)),
      _buildModernStatCard('Số ca', '$totalShifts', Icons.work_history, const Color(0xFFF59E0B)),
    ];
    final isMobile = MediaQuery.of(context).size.width < 768;
    if (isMobile) {
      return Wrap(spacing: 10, runSpacing: 10, children: cards);
    }
    return Row(
      children: cards.map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: c))).toList(),
    );
  }

  Widget _buildModernStatCard(String label, String value, IconData icon, Color color) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth < 600 ? (screenWidth - 52) / 2 : null;
    return SizedBox(
      width: cardWidth,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Pagination bar
  Widget _buildPaginationBar(int totalRows, int totalPages) {
    final startRow = totalRows == 0 ? 0 : _currentPage * _rowsPerPage + 1;
    final endRow = ((_currentPage + 1) * _rowsPerPage).clamp(0, totalRows);

    final recordsInfo = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.format_list_numbered, size: 13, color: Colors.green.shade600),
          const SizedBox(width: 4),
          Text(
            'Hiển thị $startRow-$endRow / $totalRows bản ghi',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.green.shade700),
          ),
        ],
      ),
    );

    final rowsPerPage = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Số dòng:', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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

    final pageNav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPageNavBtn(Icons.first_page, _currentPage > 0 ? () => setState(() => _currentPage = 0) : null),
        _buildPageNavBtn(Icons.chevron_left, _currentPage > 0 ? () => setState(() => _currentPage--) : null),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${_currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null),
        _buildPageNavBtn(Icons.last_page, _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500) {
            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [recordsInfo, rowsPerPage],
                ),
                const SizedBox(height: 8),
                pageNav,
              ],
            );
          }
          return Row(
            children: [
              recordsInfo,
              const SizedBox(width: 16),
              rowsPerPage,
              const Spacer(),
              pageNav,
            ],
          );
        },
      ),
    );
  }

  Widget _buildPageNavBtn(IconData icon, VoidCallback? onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: onPressed != null ? const Color(0xFFFAFAFA) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32, height: 32,
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: onPressed != null ? Colors.grey.shade700 : Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  /// Export to Excel
  Future<void> exportToExcel() async {
    final summaries = _dailySummaryData;
    if (summaries.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      // Tìm maxPunches/maxShifts
      int actualMaxPunches = 0;
      for (final s in summaries) {
        if (s.totalPunches > actualMaxPunches) actualMaxPunches = s.totalPunches;
      }
      int maxPunches = 2;
      if (actualMaxPunches > 2) {
        maxPunches = ((actualMaxPunches + 1) ~/ 2) * 2;
      }
      if (maxPunches > 10) maxPunches = 10;
      int maxShifts = maxPunches ~/ 2;
      if (maxShifts > 5) maxShifts = 5;

      final excelFile = excel_lib.Excel.createExcel();
      final sheet = excelFile['Chấm công'];

      // Headers
      final headers = <String>['STT', 'Tên nhân viên', 'Mã nhân viên', 'Thứ', 'Ngày'];
      for (int i = 1; i <= maxPunches; i++) {
        headers.add('Lần $i');
      }
      for (int i = 1; i <= maxShifts; i++) {
        headers.add('Giờ ca $i');
      }
      headers.addAll(['Tổng giờ', 'Giờ thập phân']);

      for (int i = 0; i < headers.length; i++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
            excel_lib.TextCellValue(headers[i]);
      }

      // Data rows
      for (int idx = 0; idx < summaries.length; idx++) {
        final s = summaries[idx];
        int col = 0;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.IntCellValue(idx + 1);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(s.employeeName);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(s.employeeCode);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(_getDayOfWeekVN(s.date.weekday));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(DateFormat('dd/MM/yyyy').format(s.date));

        for (int i = 1; i <= maxPunches; i++) {
          final punch = s.getPunch(i);
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
              excel_lib.TextCellValue(punch != null ? DateFormat('HH:mm').format(punch) : '');
        }

        for (int i = 1; i <= maxShifts; i++) {
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
              excel_lib.TextCellValue(_formatHours(s.getShiftHours(i)));
        }

        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.TextCellValue(_formatHours(s.totalHours));
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: idx + 1)).value =
            excel_lib.DoubleCellValue(double.parse(s.totalHours.toStringAsFixed(2)));
      }

      final bytes = excelFile.encode();
      if (bytes != null) {
        final range = _selectedDateRange;
        final fileName = 'Tong_hop_cham_cong_${DateFormat('ddMMyyyy').format(range.start)}_${DateFormat('ddMMyyyy').format(range.end)}.xlsx';
        await file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      }
    } catch (e) {
      debugPrint('Error exporting Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Export to PNG - vẽ toàn bộ dữ liệu bằng HTML Canvas (không phụ thuộc vào widget tree)
  Future<void> exportToPng() async {
    final summaries = _dailySummaryData;
    if (summaries.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Không có dữ liệu', message: 'Không có dữ liệu để xuất');
      return;
    }

    setState(() => _isExporting = true);

    try {
      // Tính maxPunches & maxShifts giống logic build()
      int actualMaxPunches = 0;
      for (final s in summaries) {
        if (s.totalPunches > actualMaxPunches) actualMaxPunches = s.totalPunches;
      }
      int maxPunches = 2;
      if (actualMaxPunches > 2) {
        maxPunches = ((actualMaxPunches + 1) ~/ 2) * 2;
      }
      if (maxPunches > 10) maxPunches = 10;
      int maxShifts = maxPunches ~/ 2;
      if (maxShifts > 5) maxShifts = 5;

      // Xây dựng headers
      final headers = <String>['STT', 'Tên nhân viên', 'Mã nhân viên', 'Thứ', 'Ngày'];
      for (int i = 1; i <= maxPunches; i++) {
        headers.add('Lần $i');
      }
      for (int i = 1; i <= maxShifts; i++) {
        headers.add('Giờ ca $i');
      }
      headers.addAll(['Tổng giờ', 'Giờ thập phân']);

      // Xây dựng rows
      final rows = <List<String>>[];
      for (int idx = 0; idx < summaries.length; idx++) {
        final s = summaries[idx];
        final row = <String>[
          '${idx + 1}',
          s.employeeName,
          s.employeeCode,
          _getDayOfWeekVN(s.date.weekday),
          DateFormat('dd/MM/yyyy').format(s.date),
        ];
        for (int i = 1; i <= maxPunches; i++) {
          final punch = s.getPunch(i);
          row.add(punch != null ? DateFormat('HH:mm').format(punch) : '');
        }
        for (int i = 1; i <= maxShifts; i++) {
          row.add(_formatHours(s.getShiftHours(i)));
        }
        row.add(_formatHours(s.totalHours));
        row.add(_formatDecimalHours(s.totalHours));
        rows.add(row);
      }

      // Tính kích thước canvas
      const double cellPadding = 12;
      const double fontSize = 13;
      const double headerFontSize = 14;
      const double rowHeight = 32;
      const double headerHeight = 40;
      const double titleHeight = 50;

      // Tính chiều rộng mỗi cột
      final colWidths = <double>[];
      for (int c = 0; c < headers.length; c++) {
        double maxW = headers[c].length * 9.0 + cellPadding * 2;
        for (final row in rows) {
          final w = row[c].length * 8.0 + cellPadding * 2;
          if (w > maxW) maxW = w;
        }
        if (c == 1) maxW = maxW.clamp(150, 250); // Tên nhân viên
        colWidths.add(maxW.clamp(60, 250));
      }

      final totalWidth = colWidths.fold(0.0, (sum, w) => sum + w) + 2;
      final totalHeight = titleHeight + headerHeight + rows.length * rowHeight + 2;

      // Tạo canvas
      final dataUrl = web_canvas.renderToPngDataUrl(
        width: totalWidth.toInt(),
        height: totalHeight.toInt(),
        draw: (ctx) {
          // Background trắng
          ctx.fillStyle = '#FFFFFF';
          ctx.fillRect(0, 0, totalWidth, totalHeight);

          // Tiêu đề
          ctx.fillStyle = '#1a1a1a';
          ctx.font = 'bold 16px Arial, sans-serif';
          final range = _selectedDateRange;
          final title = 'Tổng hợp chấm công - ${DateFormat('dd/MM/yyyy').format(range.start)} đến ${DateFormat('dd/MM/yyyy').format(range.end)}';
          ctx.fillText(title, 10, 30);

          // Vẽ header
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
            // Vẽ đường kẻ cột
            ctx.strokeStyle = '#E2E8F0';
            ctx.beginPath();
            ctx.moveTo(x + colWidths[c], headerY);
            ctx.lineTo(x + colWidths[c], totalHeight);
            ctx.stroke();
            x += colWidths[c];
          }

          // Vẽ rows
          for (int r = 0; r < rows.length; r++) {
            final rowY = titleHeight + headerHeight + r * rowHeight;

            // Alternate row color
            if (r % 2 == 1) {
              ctx.fillStyle = '#F8FAFC';
              ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
            }

            // Border dưới mỗi hàng
            ctx.strokeStyle = '#E2E8F0';
            ctx.beginPath();
            ctx.moveTo(1, rowY + rowHeight);
            ctx.lineTo(totalWidth - 1, rowY + rowHeight);
            ctx.stroke();

            x = 1;
            for (int c = 0; c < rows[r].length; c++) {
              final cellText = rows[r][c];
              // Màu cho lần chấm vào (lẻ) và ra (chẵn)
              if (c >= 5 && c < 5 + maxPunches && cellText.isNotEmpty) {
                final punchIndex = c - 4; // 1-based
                ctx.fillStyle = punchIndex % 2 == 1 ? '#059669' : '#DC2626'; // Xanh=vào, Đỏ=ra
              } else if (c >= 5 + maxPunches && c < 5 + maxPunches + maxShifts && cellText != '-') {
                ctx.fillStyle = '#0D9488'; // Teal cho ca
              } else if (c == headers.length - 2 && cellText != '-') {
                ctx.fillStyle = '#16A34A'; // Xanh lá cho tổng giờ
              } else if (c == headers.length - 1 && cellText != '-') {
                ctx.fillStyle = '#1D4ED8'; // Xanh dương cho giờ thập phân
              } else {
                ctx.fillStyle = '#334155';
              }
              ctx.font = '${fontSize}px Arial, sans-serif';
              ctx.fillText(cellText, x + cellPadding, rowY + rowHeight / 2 + 5);
              x += colWidths[c];
            }
          }

          // Border ngoài
          ctx.strokeStyle = '#CBD5E1';
          ctx.lineWidth = 1;
          ctx.strokeRect(1, titleHeight, totalWidth - 2, totalHeight - titleHeight - 1);
        },
      );

      if (dataUrl != null) {
        final fileName = 'Tong_hop_cham_cong_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
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
          final title = 'Tổng hợp chấm công - ${DateFormat('dd/MM/yyyy').format(range.start)} đến ${DateFormat('dd/MM/yyyy').format(range.end)}';
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
            if (r % 2 == 1) {
              ctx.fillStyle = '#F8FAFC';
              ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
            }
            ctx.strokeStyle = '#E2E8F0';
            ctx.beginPath();
            ctx.moveTo(1, rowY + rowHeight);
            ctx.lineTo(totalWidth - 1, rowY + rowHeight);
            ctx.stroke();
            x = 1;
            for (int c = 0; c < rows[r].length; c++) {
              final cellText = rows[r][c];
              if (c >= 5 && c < 5 + maxPunches && cellText.isNotEmpty) {
                final punchIndex = c - 4;
                ctx.fillStyle = punchIndex % 2 == 1 ? '#059669' : '#DC2626';
              } else if (c >= 5 + maxPunches && c < 5 + maxPunches + maxShifts && cellText != '-') {
                ctx.fillStyle = '#0D9488';
              } else if (c == headers.length - 2 && cellText != '-') {
                ctx.fillStyle = '#16A34A';
              } else if (c == headers.length - 1 && cellText != '-') {
                ctx.fillStyle = '#1D4ED8';
              } else {
                ctx.fillStyle = '#334155';
              }
              ctx.font = '${fontSize}px Arial, sans-serif';
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
          final fileName = 'Tong_hop_cham_cong_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
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

  /// Employee multi-select filter button
  Widget _buildEmployeeFilter() {
    final employees = _allEmployees;
    final selectedCount = _selectedEmployeeIds.length;

    return InkWell(
      onTap: () => _showEmployeeSelectionDialog(employees),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
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

  /// Show employee multi-select dialog
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
                    // Search box
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
                    // Info bar
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
                    // Employee list
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

  /// Show vertical detail popup for a row
  void _showRowDetailDialog(_DailySummary summary, int maxPunches, int maxShifts) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final detailContent = Column(
      children: [
        // Punch times
        for (int i = 1; i <= maxPunches; i++)
          if (summary.getPunch(i) != null)
            _buildDetailRow(
              'Lần $i (${i % 2 == 1 ? "Vào" : "Ra"})',
              DateFormat('HH:mm:ss').format(summary.getPunch(i)!),
              icon: i % 2 == 1 ? Icons.login : Icons.logout,
              iconColor: i % 2 == 1 ? Colors.green : Colors.orange,
            ),
        if (summary.totalPunches > 0)
          const Divider(height: 24),
        // Shift hours
        for (int i = 1; i <= maxShifts; i++)
          if (summary.getShiftHours(i) > 0)
            _buildDetailRow(
              'Giờ ca $i',
              _formatHours(summary.getShiftHours(i)),
              icon: Icons.schedule,
              iconColor: [Colors.teal, Colors.indigo, Colors.purple, Colors.orange, Colors.brown][i - 1],
            ),
        const Divider(height: 24),
        // Totals
        _buildDetailRow(
          'Tổng giờ',
          _formatHours(summary.totalHours),
          icon: Icons.timer,
          iconColor: Colors.green,
          isBold: true,
        ),
        _buildDetailRow(
          'Giờ thập phân',
          _formatDecimalHours(summary.totalHours),
          icon: Icons.onetwothree,
          iconColor: Colors.blue.shade700,
          isBold: true,
        ),
        _buildDetailRow(
          'Tổng lần chấm',
          '${summary.totalPunches}',
          icon: Icons.fingerprint,
          iconColor: Colors.purple,
        ),
      ],
    );

    if (isMobile) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                title: Text(summary.employeeName, overflow: TextOverflow.ellipsis),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            summary.employeeName.isNotEmpty ? summary.employeeName[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(summary.employeeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              Text('Mã: ${summary.employeeCode}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Date info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text(
                            '${_getDayOfWeekVN(summary.date.weekday)}, ${DateFormat('dd/MM/yyyy').format(summary.date)}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    detailContent,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 600),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blue.shade100,
                          child: Text(
                            summary.employeeName.isNotEmpty ? summary.employeeName[0].toUpperCase() : '?',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(summary.employeeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              Text('Mã: ${summary.employeeCode}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    ),
                  ),
                  // Date info
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: Colors.grey.shade600),
                        const SizedBox(width: 8),
                        Text(
                          '${_getDayOfWeekVN(summary.date.weekday)}, ${DateFormat('dd/MM/yyyy').format(summary.date)}',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  // Detail rows
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: detailContent,
                    ),
                  ),
                  // Footer
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Đóng'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Widget _buildDetailRow(String label, String value, {IconData? icon, Color? iconColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: (iconColor ?? Colors.grey).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? Colors.black : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // Filter bar
  Widget _buildFilters(DateTimeRange range) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final datePreset = _buildDropdown<String>(
      value: _selectedPreset,
      width: isMobile ? 120 : null,
      icon: Icons.calendar_today,
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
    );

    final dateRange = _buildDateRangeDisplay(range);

    final employeeFilter = _buildEmployeeFilter();

    final shiftFilter = _buildDropdown<String>(
      value: _shiftFilter,
      width: isMobile ? 150 : null,
      icon: Icons.warning_amber_rounded,
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả ca')),
        DropdownMenuItem(value: 'missing', child: Text('Thiếu chấm công')),
        DropdownMenuItem(value: 'complete', child: Text('Đủ chấm công')),
      ],
      onChanged: (v) {
        if (v != null) setState(() { _shiftFilter = v; _currentPage = 0; });
      },
    );

    final recordCount = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart, color: Theme.of(context).primaryColor, size: 14),
          const SizedBox(width: 5),
          Text(
            '${_dailySummaryData.length} bản ghi',
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
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                Row(
                  children: [
                    recordCount,
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
                recordCount,
              ],
            ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    double? width,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                        )),
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
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color),
                        overflow: TextOverflow.ellipsis,
                        child: item.child,
                      )),
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
          Text(
            '${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị thời gian chấm công - có thể click để sửa/xóa
  Widget _buildPunchTime(
    DateTime? time, {
    required bool isIn,
    required _DailySummary summary,
    required int punchIndex,
  }) {
    if (time == null) {
      // Ô trống - hiển thị nút + để thêm
      return InkWell(
        onTap: () => _showAddPunchDialog(summary, punchIndex, isIn),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
                color: Colors.grey.withValues(alpha: 0.3), style: BorderStyle.solid),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(Icons.add, size: 14, color: Colors.grey),
        ),
      );
    }

    // Có dữ liệu - click để sửa/xóa
    return InkWell(
      onTap: () => _showEditPunchDialog(summary, punchIndex, time, isIn),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIn ? Icons.login : Icons.logout,
              size: 12,
              color: isIn ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 3),
            Text(
              DateFormat('HH:mm').format(time),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isIn ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.edit,
              size: 10,
              color: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  /// Hiển thị dialog thêm chấm công mới
  void _showAddPunchDialog(_DailySummary summary, int punchIndex, bool isIn) {
    TimeOfDay selectedTime = TimeOfDay.now();
    DateTime selectedDate = summary.date;
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                        Text('Nhân viên: ${summary.employeeName}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Mã NV: ${summary.employeeCode}'),
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
                      context: context,
                      initialDate: selectedDate,
                      firstDate: summary.date,
                      lastDate: summary.date.add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
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
                        Text(
                          DateFormat('dd/MM/yyyy').format(selectedDate),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (selectedDate != summary.date) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Ngày hôm sau', style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
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
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
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
                        Icon(isIn ? Icons.login : Icons.logout,
                            color: isIn ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
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

                // Lý do
                const Text('Lý do bổ sung:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Nhập lý do (bắt buộc)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  appNotification.showError(
                      title: 'Lỗi', message: 'Vui lòng nhập lý do');
                  return;
                }

                final requestedTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final request = AttendanceCorrectionRequest(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  employeeName: summary.employeeName,
                  employeeCode: summary.employeeCode,
                  pin: summary.pin,
                  attendanceId: null, // Thêm mới nên không có ID cũ
                  requestDate: DateTime.now(),
                  correctionDate: selectedDate,
                  reason: reasonController.text.trim(),
                  correctionType: 'add',
                  requestedTime: DateFormat('HH:mm').format(requestedTime),
                  punchIndex: punchIndex,
                );

                widget.onCorrectionRequest?.call(request);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.send),
              label: const Text('Gửi yêu cầu'),
            ),
          ],
        ),
      ),
    );
  }

  /// Hiển thị dialog sửa/xóa chấm công
  void _showEditPunchDialog(
      _DailySummary summary, int punchIndex, DateTime currentTime, bool isIn) {
    TimeOfDay selectedTime =
        TimeOfDay(hour: currentTime.hour, minute: currentTime.minute);
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                        Text('Nhân viên: ${summary.employeeName}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text('Mã NV: ${summary.employeeCode}'),
                        Text(
                            'Ngày: ${DateFormat('dd/MM/yyyy').format(summary.date)}'),
                        Text('Lần chấm: $punchIndex (${isIn ? "Vào" : "Ra"})'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Text('Giờ hiện tại: '),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isIn ? Colors.green : Colors.red)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                DateFormat('HH:mm').format(currentTime),
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

                // Chọn giờ mới
                const Text('Sửa thành giờ mới:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
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
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
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

                // Lý do
                const Text('Lý do chỉnh sửa:',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Nhập lý do (bắt buộc)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Nút xóa
            TextButton.icon(
              onPressed: () =>
                  _confirmDeletePunch(summary, punchIndex, currentTime, isIn),
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text('Xóa', style: TextStyle(color: Colors.red)),
            ),
            // Dùng SizedBox thay cho Spacer trong AlertDialog actions
            const SizedBox(width: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  appNotification.showError(
                      title: 'Lỗi', message: 'Vui lòng nhập lý do');
                  return;
                }

                final requestedTime = DateTime(
                  summary.date.year,
                  summary.date.month,
                  summary.date.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final request = AttendanceCorrectionRequest(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  employeeName: summary.employeeName,
                  employeeCode: summary.employeeCode,
                  pin: summary.pin,
                  attendanceId:
                      summary.getPunchId(punchIndex), // ID của punch đang sửa
                  requestDate: DateTime.now(),
                  correctionDate: summary.date,
                  reason: reasonController.text.trim(),
                  correctionType: 'edit',
                  requestedTime: DateFormat('HH:mm').format(requestedTime),
                  punchIndex: punchIndex,
                  originalTime: currentTime,
                );

                widget.onCorrectionRequest?.call(request);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.send),
              label: const Text('Gửi yêu cầu sửa'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog xác nhận xóa chấm công
  void _confirmDeletePunch(
      _DailySummary summary, int punchIndex, DateTime currentTime, bool isIn) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
            const Text('Bạn có chắc muốn yêu cầu xóa lần chấm công này?'),
            const SizedBox(height: 8),
            Card(
              color: Colors.red.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nhân viên: ${summary.employeeName}'),
                    Text(
                        'Ngày: ${DateFormat('dd/MM/yyyy').format(summary.date)}'),
                    Text(
                        'Lần chấm: $punchIndex - ${DateFormat('HH:mm').format(currentTime)}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Lý do xóa:',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Nhập lý do (bắt buộc)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                appNotification.showError(
                    title: 'Lỗi', message: 'Vui lòng nhập lý do');
                return;
              }

              final request = AttendanceCorrectionRequest(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                employeeName: summary.employeeName,
                employeeCode: summary.employeeCode,
                pin: summary.pin,
                attendanceId:
                    summary.getPunchId(punchIndex), // ID của punch đang xóa
                requestDate: DateTime.now(),
                correctionDate: summary.date,
                reason: reasonController.text.trim(),
                correctionType: 'delete',
                requestedTime: DateFormat('HH:mm').format(currentTime),
                punchIndex: punchIndex,
                originalTime: currentTime,
              );

              widget.onCorrectionRequest?.call(request);
              Navigator.pop(context); // Đóng dialog xác nhận
              Navigator.pop(context); // Đóng dialog edit
            },
            icon: const Icon(Icons.delete),
            label: const Text('Xóa'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildHoursBadge(double hours, Color color, {bool isBold = false}) {
    if (hours <= 0) {
      return const Text('-',
          style: TextStyle(fontSize: 12, color: Colors.grey));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _formatHours(hours),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailySummary {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? pin; // PIN/mã chấm công
  final DateTime date;
  final DateTime? punch1;
  final DateTime? punch2;
  final DateTime? punch3;
  final DateTime? punch4;
  final DateTime? punch5;
  final DateTime? punch6;
  final DateTime? punch7;
  final DateTime? punch8;
  final DateTime? punch9;
  final DateTime? punch10;
  // Lưu attendance IDs tương ứng với mỗi punch (để có thể xác định chính xác bản ghi)
  final String? punchId1;
  final String? punchId2;
  final String? punchId3;
  final String? punchId4;
  final String? punchId5;
  final String? punchId6;
  final String? punchId7;
  final String? punchId8;
  final String? punchId9;
  final String? punchId10;
  final double shift1Hours;
  final double shift2Hours;
  final double shift3Hours;
  final double shift4Hours;
  final double shift5Hours;
  final double totalHours;
  final int totalPunches; // Tổng số lần chấm công

  _DailySummary({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.pin,
    required this.date,
    this.punch1,
    this.punch2,
    this.punch3,
    this.punch4,
    this.punch5,
    this.punch6,
    this.punch7,
    this.punch8,
    this.punch9,
    this.punch10,
    this.punchId1,
    this.punchId2,
    this.punchId3,
    this.punchId4,
    this.punchId5,
    this.punchId6,
    this.punchId7,
    this.punchId8,
    this.punchId9,
    this.punchId10,
    required this.shift1Hours,
    required this.shift2Hours,
    this.shift3Hours = 0,
    this.shift4Hours = 0,
    this.shift5Hours = 0,
    required this.totalHours,
    this.totalPunches = 0,
  });

  // Lấy punch time theo index (1-10)
  DateTime? getPunch(int index) {
    switch (index) {
      case 1:
        return punch1;
      case 2:
        return punch2;
      case 3:
        return punch3;
      case 4:
        return punch4;
      case 5:
        return punch5;
      case 6:
        return punch6;
      case 7:
        return punch7;
      case 8:
        return punch8;
      case 9:
        return punch9;
      case 10:
        return punch10;
      default:
        return null;
    }
  }

  // Lấy attendance ID theo punch index (1-10)
  String? getPunchId(int index) {
    switch (index) {
      case 1:
        return punchId1;
      case 2:
        return punchId2;
      case 3:
        return punchId3;
      case 4:
        return punchId4;
      case 5:
        return punchId5;
      case 6:
        return punchId6;
      case 7:
        return punchId7;
      case 8:
        return punchId8;
      case 9:
        return punchId9;
      case 10:
        return punchId10;
      default:
        return null;
    }
  }

  // Lấy shift hours theo index (1-5)
  double getShiftHours(int index) {
    switch (index) {
      case 1:
        return shift1Hours;
      case 2:
        return shift2Hours;
      case 3:
        return shift3Hours;
      case 4:
        return shift4Hours;
      case 5:
        return shift5Hours;
      default:
        return 0;
    }
  }
}

class _EmployeeOption {
  final String id;
  final String name;
  final String code;
  _EmployeeOption({required this.id, required this.name, required this.code});
}
