import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';

class ShiftRegistrationScreen extends StatefulWidget {
  const ShiftRegistrationScreen({super.key});

  @override
  State<ShiftRegistrationScreen> createState() => _ShiftRegistrationScreenState();
}

class _ShiftRegistrationScreenState extends State<ShiftRegistrationScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;

  List<dynamic> _shifts = [];
  List<dynamic> _employees = [];
  List<Map<String, dynamic>> _workSchedules = [];
  List<Map<String, dynamic>> _pendingRegistrations = [];

  late DateTime _weekStart;

  // Pagination
  int _empPage = 1;
  final int _empPageSize = 50;

  /// Employees that have at least one schedule in the current week
  List<dynamic> get _activeEmployees {
    final activeIds = <String>{};
    for (final ws in _workSchedules) {
      final id = ws['employeeUserId']?.toString();
      if (id != null) activeIds.add(id);
    }
    // Also include employees with pending registrations
    for (final r in _pendingRegistrations) {
      final id = r['employeeUserId']?.toString();
      if (id != null) activeIds.add(id);
    }
    return _employees.where((e) {
      final id = e['userId']?.toString() ?? e['id']?.toString();
      return activeIds.contains(id);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
    _loadData();
  }

  List<DateTime> get _weekDays => List.generate(7, (i) => _weekStart.add(Duration(days: i)));

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final fromDate = _weekStart;
      final toDate = _weekStart.add(const Duration(days: 6));

      final results = await Future.wait([
        _apiService.getShifts(),
        _apiService.getWorkSchedules(fromDate: fromDate, toDate: toDate, pageSize: 500),
        _apiService.getScheduleRegistrations(fromDate: fromDate, toDate: toDate, pageSize: 500),
        _apiService.getEmployees(pageSize: 500),
      ]);

      setState(() {
        _shifts = results[0] as List<dynamic>;
        final wsResult = results[1] as Map<String, dynamic>;
        if (wsResult['isSuccess'] == true) {
          final d = wsResult['data'];
          if (d is List) {
            _workSchedules = List<Map<String, dynamic>>.from(d);
          } else if (d is Map && d['items'] != null) {
            _workSchedules = List<Map<String, dynamic>>.from(d['items']);
          }
        }
        final regResult = results[2] as Map<String, dynamic>;
        if (regResult['isSuccess'] == true) {
          final d = regResult['data'];
          if (d is List) {
            _pendingRegistrations = List<Map<String, dynamic>>.from(d);
          } else if (d is Map && d['items'] != null) {
            _pendingRegistrations = List<Map<String, dynamic>>.from(d['items']);
          }
        }
        _employees = results[3] as List<dynamic>;
      });
    } catch (e) {
      debugPrint('Error loading shift data: $e');
    }
    setState(() => _isLoading = false);
  }

  void _changeWeek(int delta) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * delta)));
    _loadData();
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _weekStart = now.subtract(Duration(days: now.weekday - 1));
      _weekStart = DateTime(_weekStart.year, _weekStart.month, _weekStart.day);
    });
    _loadData();
  }

  // ── Data helpers ──

  List<Map<String, dynamic>> _getEmployeesForShiftDay(dynamic shift, DateTime date) {
    final shiftId = shift['id']?.toString();
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _workSchedules.where((ws) {
      return ws['shiftId']?.toString() == shiftId && ws['date']?.toString().substring(0, 10) == dateStr;
    }).toList();
  }

  List<Map<String, dynamic>> _getShiftsForEmployeeDay(dynamic employee, DateTime date) {
    final empId = employee['userId']?.toString() ?? employee['id']?.toString();
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _workSchedules.where((ws) {
      return ws['employeeUserId']?.toString() == empId && ws['date']?.toString().substring(0, 10) == dateStr;
    }).toList();
  }

  List<Map<String, dynamic>> _getPendingForShiftDay(dynamic shift, DateTime date) {
    final shiftId = shift['id']?.toString();
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _pendingRegistrations.where((r) {
      return r['shiftId']?.toString() == shiftId && r['date']?.toString().substring(0, 10) == dateStr && (r['status']?.toString().toLowerCase()) == 'pending';
    }).toList();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final pendingCount = _pendingRegistrations.where((r) => (r['status']?.toString().toLowerCase()) == 'pending').length;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          _buildWeekNavigator(),
          if (pendingCount > 0) _buildPendingBanner(pendingCount),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _shifts.isEmpty
                    ? _buildEmptyState()
                    : _buildBothTables(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0891B2), Color(0xFF2D5F8B)])),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.calendar_view_week, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Lịch ca làm việc', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              Text('Phân ca và phê duyệt theo tuần', style: TextStyle(color: Colors.white70, fontSize: 14)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekNavigator() {
    final endDate = _weekStart.add(const Duration(days: 6));
    final label = '${DateFormat('dd/MM').format(_weekStart)} - ${DateFormat('dd/MM/yyyy').format(endDate)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(onPressed: () => _changeWeek(-1), icon: const Icon(Icons.chevron_left), tooltip: 'Tuần trước'),
          Expanded(child: InkWell(onTap: _goToToday, child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))),
          TextButton(onPressed: _goToToday, child: const Text('Hôm nay')),
          IconButton(onPressed: () => _changeWeek(1), icon: const Icon(Icons.chevron_right), tooltip: 'Tuần sau'),
        ],
      ),
    );
  }

  Widget _buildPendingBanner(int count) {
    return InkWell(
      onTap: _showPendingRegistrations,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFEF3C7),
        child: Row(
          children: [
            const Icon(Icons.pending_actions, color: Color(0xFFF59E0B), size: 20),
            const SizedBox(width: 8),
            Text('Có $count yêu cầu đăng ký ca chờ duyệt', style: const TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w500)),
            const Spacer(),
            const Text('Xem →', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.event_busy, size: 64, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('Chưa có ca làm việc nào', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        const SizedBox(height: 8),
        Text('Vui lòng tạo ca trong phần Cài đặt ca', style: TextStyle(color: Colors.grey[400], fontSize: 14)),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  //  TWO TABLES
  // ══════════════════════════════════════════════

  Widget _buildBothTables() {
    final dayNames = ['THỨ 2', 'THỨ 3', 'THỨ 4', 'THỨ 5', 'THỨ 6', 'THỨ 7', 'CN'];
    final days = _weekDays;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── TABLE 1: Ca cố định → chọn NV theo thứ ──
          _buildSectionTitle(Icons.work_history, 'Theo ca làm việc', 'Ca cố định → chọn nhân viên theo thứ', const Color(0xFF0891B2)),
          const SizedBox(height: 8),
          _buildShiftTable(dayNames, days, todayStr),

          const SizedBox(height: 24),

          // ── TABLE 2: NV cố định → chọn ca theo thứ ──
          _buildSectionTitle(Icons.people, 'Theo nhân viên', 'Nhân viên cố định → chọn ca theo thứ', const Color(0xFF0F2340)),
          const SizedBox(height: 8),
          _buildEmployeeTable(dayNames, days, todayStr),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title, String subtitle, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
            Text(subtitle, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ]),
        ),
      ],
    );
  }

  // ── TABLE 1: Shift rows ──

  Widget _buildShiftTable(List<String> dayNames, List<DateTime> days, String todayStr) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 24),
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade300, width: 1),
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          columnWidths: {0: const FixedColumnWidth(140), for (int i = 1; i <= 7; i++) i: const FlexColumnWidth(1)},
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF0891B2)),
              children: [
                _headerCell('Ca làm việc'),
                for (int i = 0; i < 7; i++) _dayHeaderCell(dayNames[i], days[i], DateFormat('yyyy-MM-dd').format(days[i]) == todayStr, const Color(0xFF0891B2)),
              ],
            ),
            for (final shift in _shifts) _shiftRow(shift, days, todayStr),
          ],
        ),
      ),
    );
  }

  TableRow _shiftRow(dynamic shift, List<DateTime> days, String todayStr) {
    final shiftName = shift['name'] ?? '';
    final startTime = _fmtTime(shift['startTime']);
    final endTime = _fmtTime(shift['endTime']);
    return TableRow(children: [
      TableCell(child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(color: Color(0xFFF0F9FF)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shiftName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 2),
          Text('$startTime - $endTime', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        ]),
      )),
      for (final day in days) _shiftDayCell(shift, day, DateFormat('yyyy-MM-dd').format(day) == todayStr),
    ]);
  }

  Widget _shiftDayCell(dynamic shift, DateTime date, bool isToday) {
    final employees = _getEmployeesForShiftDay(shift, date);
    final pending = _getPendingForShiftDay(shift, date);
    return TableCell(
      child: InkWell(
        onTap: () => _showShiftCellActions(shift, date, employees, pending),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: isToday ? const Color(0xFFF0FDFA) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...employees.map((ws) => _chip(ws['employeeName'] ?? ws['employeeCode'] ?? '?', const Color(0xFF1E3A5F))),
            ...pending.map((r) => _chip(r['employeeName'] ?? '?', const Color(0xFFF59E0B), isPending: true)),
            if (employees.isEmpty && pending.isEmpty) Center(child: Icon(Icons.add_circle_outline, size: 16, color: Colors.grey[300])),
          ]),
        ),
      ),
    );
  }

  // ── TABLE 2: Employee rows ──

  Widget _buildEmployeeTable(List<String> dayNames, List<DateTime> days, String todayStr) {
    final emps = _activeEmployees;
    final totalPages = (emps.length / _empPageSize).ceil();
    final safePage = _empPage.clamp(1, totalPages == 0 ? 1 : totalPages);
    final startIdx = (safePage - 1) * _empPageSize;
    final endIdx = (startIdx + _empPageSize).clamp(0, emps.length);
    final pageEmps = emps.sublist(startIdx, endIdx);
    return Column(children: [
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 24),
        child: Table(
          border: TableBorder.all(color: Colors.grey.shade300, width: 1),
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          columnWidths: {0: const FixedColumnWidth(160), for (int i = 1; i <= 7; i++) i: const FlexColumnWidth(1)},
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFF0F2340)),
              children: [
                _headerCell('Nhân viên'),
                for (int i = 0; i < 7; i++) _dayHeaderCell(dayNames[i], days[i], DateFormat('yyyy-MM-dd').format(days[i]) == todayStr, const Color(0xFF0F2340)),
              ],
            ),
            for (final emp in pageEmps) _employeeRow(emp, days, todayStr),
            // "Add employee" row
            TableRow(children: [
              TableCell(child: InkWell(
                onTap: _showAddEmployeeToTable,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  child: Row(children: [
                    Icon(Icons.person_add, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Text('Thêm nhân viên...', style: TextStyle(color: Colors.grey[500], fontSize: 12, fontStyle: FontStyle.italic)),
                  ]),
                ),
              )),
              for (int i = 0; i < 7; i++) const TableCell(child: SizedBox(height: 36)),
            ]),
          ],
        ),
      ),
    ),
    if (totalPages > 1)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(icon: const Icon(Icons.first_page), onPressed: safePage > 1 ? () => setState(() => _empPage = 1) : null),
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: safePage > 1 ? () => setState(() => _empPage--) : null),
            Text('Trang $safePage / $totalPages (${emps.length} nhân viên)', style: const TextStyle(fontSize: 13)),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: safePage < totalPages ? () => setState(() => _empPage++) : null),
            IconButton(icon: const Icon(Icons.last_page), onPressed: safePage < totalPages ? () => setState(() => _empPage = totalPages) : null),
          ],
        ),
      ),
    ]);
  }

  TableRow _employeeRow(dynamic emp, List<DateTime> days, String todayStr) {
    final name = emp['fullName'] ?? emp['name'] ?? '';
    final code = emp['employeeCode'] ?? emp['code'] ?? '';
    return TableRow(children: [
      TableCell(child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(color: Color(0xFFF5F3FF)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis),
          if (code.toString().isNotEmpty) Text(code.toString(), style: TextStyle(color: Colors.grey[500], fontSize: 11)),
        ]),
      )),
      for (final day in days) _employeeDayCell(emp, day, DateFormat('yyyy-MM-dd').format(day) == todayStr),
    ]);
  }

  Widget _employeeDayCell(dynamic emp, DateTime date, bool isToday) {
    final shifts = _getShiftsForEmployeeDay(emp, date);
    return TableCell(
      child: InkWell(
        onTap: () => _showEmployeeCellActions(emp, date, shifts),
        child: Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: isToday ? const Color(0xFFFAF5FF) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...shifts.map((ws) {
              final sName = ws['shiftName'] ?? '';
              return _chip(sName.toString(), const Color(0xFF0F2340));
            }),
            if (shifts.isEmpty) Center(child: Icon(Icons.add_circle_outline, size: 16, color: Colors.grey[300])),
          ]),
        ),
      ),
    );
  }

  // ── Shared widgets ──

  Widget _headerCell(String text) {
    return TableCell(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
    ));
  }

  Widget _dayHeaderCell(String dayName, DateTime date, bool isToday, Color baseColor) {
    return TableCell(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: isToday ? BoxDecoration(color: Colors.white.withValues(alpha: 0.15)) : null,
      child: Column(children: [
        Text(dayName, style: TextStyle(color: isToday ? Colors.yellow : Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
        Text(DateFormat('dd/MM').format(date), style: TextStyle(color: isToday ? Colors.yellow.shade200 : Colors.white70, fontSize: 11)),
      ]),
    ));
  }

  Widget _chip(String name, Color color, {bool isPending = false}) {
    final short = name.length > 12 ? '${name.substring(0, 12)}…' : name;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: isPending ? Border.all(color: color.withValues(alpha: 0.5), width: 1, strokeAlign: BorderSide.strokeAlignInside) : null,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isPending) ...[Icon(Icons.schedule, size: 10, color: color), const SizedBox(width: 2)],
        Flexible(child: Text(short, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ══════════════════════════════════════════════
  //  ACTIONS — Table 1 (Shift cell)
  // ══════════════════════════════════════════════

  void _showShiftCellActions(dynamic shift, DateTime date, List<Map<String, dynamic>> employees, List<Map<String, dynamic>> pending) {
    final shiftName = shift['name'] ?? '';
    final dateStr = DateFormat('dd/MM/yyyy (EEEE)', 'vi').format(date);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5, minChildSize: 0.3, maxChildSize: 0.85, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shiftName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              ])),
              FilledButton.icon(
                onPressed: () { Navigator.pop(ctx); _showAssignEmployeeDialog(shift, date); },
                icon: const Icon(Icons.person_add, size: 18),
                label: const Text('Thêm NV'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0891B2)),
              ),
            ]),
          ),
          const Divider(height: 24),
          Expanded(child: ListView(controller: scrollCtrl, padding: const EdgeInsets.all(16), children: [
            if (employees.isNotEmpty) ...[
              const Text('Nhân viên đã phân ca', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              ...employees.map(_buildScheduleTile),
              const SizedBox(height: 16),
            ],
            if (pending.isNotEmpty) ...[
              const Text('Yêu cầu chờ duyệt', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFFF59E0B))),
              const SizedBox(height: 8),
              ...pending.map(_buildPendingTile),
            ],
            if (employees.isEmpty && pending.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Column(children: [
                Icon(Icons.person_off, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('Chưa có nhân viên nào', style: TextStyle(color: Colors.grey[500])),
              ])),
          ])),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  ACTIONS — Table 2 (Employee cell)
  // ══════════════════════════════════════════════

  void _showEmployeeCellActions(dynamic emp, DateTime date, List<Map<String, dynamic>> shifts) {
    final empName = emp['fullName'] ?? emp['name'] ?? '';
    final dateStr = DateFormat('dd/MM/yyyy (EEEE)', 'vi').format(date);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5, minChildSize: 0.3, maxChildSize: 0.85, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(empName.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
              ])),
              FilledButton.icon(
                onPressed: () { Navigator.pop(ctx); _showAssignShiftDialog(emp, date); },
                icon: const Icon(Icons.work_history, size: 18),
                label: const Text('Thêm ca'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F2340)),
              ),
            ]),
          ),
          const Divider(height: 24),
          Expanded(child: ListView(controller: scrollCtrl, padding: const EdgeInsets.all(16), children: [
            if (shifts.isNotEmpty) ...[
              const Text('Ca đã phân', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              ...shifts.map((ws) => Card(
                margin: const EdgeInsets.only(bottom: 8), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF0F2340).withValues(alpha: 0.1),
                    child: const Icon(Icons.work, color: Color(0xFF0F2340), size: 18),
                  ),
                  title: Text(ws['shiftName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('${_fmtTime(ws['shiftStartTime'])} - ${_fmtTime(ws['shiftEndTime'])}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => _removeWorkSchedule(ws['id']?.toString())),
                ),
              )),
            ],
            if (shifts.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 32), child: Column(children: [
                Icon(Icons.work_off, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 8),
                Text('Chưa có ca nào', style: TextStyle(color: Colors.grey[500])),
              ])),
          ])),
        ]),
      ),
    );
  }

  // ── Shared tiles ──

  Widget _buildScheduleTile(Map<String, dynamic> ws) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8), elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
          child: Text((ws['employeeName'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold)),
        ),
        title: Text(ws['employeeName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(ws['employeeCode'] ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => _removeWorkSchedule(ws['id']?.toString())),
      ),
    );
  }

  Widget _buildPendingTile(Map<String, dynamic> reg) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8), elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFFDE68A))),
      color: const Color(0xFFFFFBEB),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
          child: Text((reg['employeeName'] ?? '?')[0].toUpperCase(), style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
        ),
        title: Text(reg['employeeName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(reg['note'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), onPressed: () => _rejectRegistration(reg['id']?.toString())),
          IconButton(icon: const Icon(Icons.check, color: Color(0xFF1E3A5F), size: 20), onPressed: () => _approveRegistration(reg['id']?.toString())),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  DIALOGS
  // ══════════════════════════════════════════════

  /// Table 1: Assign employee to a shift+date
  void _showAssignEmployeeDialog(dynamic shift, DateTime date) {
    final shiftName = shift['name'] ?? '';
    final shiftId = shift['id']?.toString();
    final searchCtrl = TextEditingController();
    List<dynamic> filtered = List.from(_employees);
    final assignedIds = _getEmployeesForShiftDay(shift, date).map((ws) => ws['employeeUserId']?.toString()).toSet();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        void filter() {
          final q = searchCtrl.text.toLowerCase();
          setDialogState(() {
            filtered = _employees.where((e) {
              final n = (e['fullName'] ?? e['name'] ?? '').toString().toLowerCase();
              final c = (e['employeeCode'] ?? e['code'] ?? '').toString().toLowerCase();
              return n.contains(q) || c.contains(q);
            }).toList();
          });
        }
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Thêm NV vào $shiftName'),
            Text(DateFormat('dd/MM/yyyy').format(date), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          ]),
          content: SizedBox(width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(), height: 400, child: Column(children: [
            TextField(controller: searchCtrl, decoration: InputDecoration(hintText: 'Tìm nhân viên...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true), onChanged: (_) => filter()),
            const SizedBox(height: 12),
            Expanded(child: filtered.isEmpty ? const Center(child: Text('Không tìm thấy')) : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final emp = filtered[i];
                final empId = emp['userId']?.toString() ?? emp['id']?.toString() ?? '';
                final done = assignedIds.contains(empId);
                final name = emp['fullName'] ?? emp['name'] ?? '';
                final code = emp['employeeCode'] ?? emp['code'] ?? '';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: done ? Colors.grey[200] : const Color(0xFF0891B2).withValues(alpha: 0.1),
                    child: Text(name.toString().isNotEmpty ? name.toString()[0].toUpperCase() : '?', style: TextStyle(color: done ? Colors.grey : const Color(0xFF0891B2), fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name.toString(), style: TextStyle(color: done ? Colors.grey : null)),
                  subtitle: Text(code.toString(), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  trailing: done ? const Chip(label: Text('Đã phân', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFE5E7EB)) : const Icon(Icons.add_circle_outline, color: Color(0xFF0891B2)),
                  onTap: done ? null : () async { Navigator.pop(ctx); await _assignEmployeeToShift(empId, shiftId, date); },
                );
              },
            )),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
        );
      }),
    );
  }

  /// Table 2: Assign shift to an employee+date
  void _showAssignShiftDialog(dynamic emp, DateTime date) {
    final empName = emp['fullName'] ?? emp['name'] ?? '';
    final empId = emp['userId']?.toString() ?? emp['id']?.toString() ?? '';
    final assignedShiftIds = _getShiftsForEmployeeDay(emp, date).map((ws) => ws['shiftId']?.toString()).toSet();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Chọn ca cho $empName'),
          Text(DateFormat('dd/MM/yyyy').format(date), style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        ]),
        content: SizedBox(
          width: 400,
          height: 300,
          child: _shifts.isEmpty
              ? const Center(child: Text('Chưa có ca nào'))
              : ListView.builder(
                  itemCount: _shifts.length,
                  itemBuilder: (ctx, i) {
                    final shift = _shifts[i];
                    final sId = shift['id']?.toString();
                    final done = assignedShiftIds.contains(sId);
                    final sName = shift['name'] ?? '';
                    final sTime = '${_fmtTime(shift['startTime'])} - ${_fmtTime(shift['endTime'])}';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: done ? Colors.grey[200] : const Color(0xFF0F2340).withValues(alpha: 0.1),
                        child: Icon(Icons.work, color: done ? Colors.grey : const Color(0xFF0F2340), size: 18),
                      ),
                      title: Text(sName.toString(), style: TextStyle(color: done ? Colors.grey : null, fontWeight: FontWeight.w500)),
                      subtitle: Text(sTime, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                      trailing: done ? const Chip(label: Text('Đã phân', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFE5E7EB)) : const Icon(Icons.add_circle_outline, color: Color(0xFF0F2340)),
                      onTap: done ? null : () async { Navigator.pop(ctx); await _assignEmployeeToShift(empId, sId, date); },
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  /// Add employee to table 2 by picking from full list then assigning a shift
  void _showAddEmployeeToTable() {
    // Just show the first shift cell dialog for today or first day of week
    final today = DateTime.now();
    DateTime targetDate = _weekDays.first;
    for (final d in _weekDays) {
      if (d.year == today.year && d.month == today.month && d.day == today.day) {
        targetDate = d;
        break;
      }
    }

    final searchCtrl = TextEditingController();
    List<dynamic> filtered = List.from(_employees);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        void filter() {
          final q = searchCtrl.text.toLowerCase();
          setDialogState(() {
            filtered = _employees.where((e) {
              final n = (e['fullName'] ?? e['name'] ?? '').toString().toLowerCase();
              final c = (e['employeeCode'] ?? e['code'] ?? '').toString().toLowerCase();
              return n.contains(q) || c.contains(q);
            }).toList();
          });
        }
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Chọn nhân viên'),
          content: SizedBox(width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(), height: 400, child: Column(children: [
            TextField(controller: searchCtrl, decoration: InputDecoration(hintText: 'Tìm nhân viên...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true), onChanged: (_) => filter()),
            const SizedBox(height: 12),
            Expanded(child: filtered.isEmpty ? const Center(child: Text('Không tìm thấy')) : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final emp = filtered[i];
                final name = emp['fullName'] ?? emp['name'] ?? '';
                final code = emp['employeeCode'] ?? emp['code'] ?? '';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF0F2340).withValues(alpha: 0.1),
                    child: Text(name.toString().isNotEmpty ? name.toString()[0].toUpperCase() : '?', style: const TextStyle(color: Color(0xFF0F2340), fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name.toString()),
                  subtitle: Text(code.toString(), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                  onTap: () { Navigator.pop(ctx); _showAssignShiftDialog(emp, targetDate); },
                );
              },
            )),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
        );
      }),
    );
  }

  // ══════════════════════════════════════════════
  //  API calls
  // ══════════════════════════════════════════════

  Future<void> _assignEmployeeToShift(String employeeId, String? shiftId, DateTime date) async {
    try {
      final data = {'employeeUserId': employeeId, 'shiftId': shiftId, 'date': date.toIso8601String(), 'isDayOff': false};
      final result = await _apiService.createWorkSchedule(data);
      if (mounted) {
        if (result['isSuccess'] == true) {
          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã phân ca thành công');
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi phân ca');
        }
      }
      _loadData();
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  Future<void> _removeWorkSchedule(String? id) async {
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phân ca'),
        content: const Text('Bạn có chắc muốn xóa phân ca này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Xóa')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _apiService.deleteWorkSchedule(id);
      if (mounted) NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa phân ca');
      if (mounted) Navigator.of(context).pop();
      _loadData();
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  Future<void> _approveRegistration(String? id) async {
    if (id == null) return;
    try {
      final result = await _apiService.approveScheduleRegistration(id, {'isApproved': true});
      if (mounted) {
        if (result['isSuccess'] == true) {
          NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã duyệt');
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
      if (mounted) Navigator.of(context).pop();
      _loadData();
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  Future<void> _rejectRegistration(String? id) async {
    if (id == null) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Từ chối đăng ký'),
        content: SingleChildScrollView(child: TextField(controller: reasonCtrl, decoration: InputDecoration(labelText: 'Lý do từ chối', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Từ chối')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _apiService.approveScheduleRegistration(id, {'isApproved': false, 'rejectionReason': reasonCtrl.text});
      if (mounted) {
        if (result['isSuccess'] == true) {
          NotificationOverlayManager().showWarning(title: 'Từ chối', message: 'Đã từ chối');
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
      if (mounted) Navigator.of(context).pop();
      _loadData();
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  void _showPendingRegistrations() {
    final pending = _pendingRegistrations.where((r) => (r['status']?.toString().toLowerCase()) == 'pending').toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.85, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(margin: const EdgeInsets.only(top: 8), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.pending_actions, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text('Yêu cầu chờ duyệt (${pending.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
          ),
          const Divider(height: 24),
          Expanded(
            child: pending.isEmpty
                ? const Center(child: Text('Không có yêu cầu chờ duyệt'))
                : ListView.builder(
                    controller: scrollCtrl, padding: const EdgeInsets.all(16), itemCount: pending.length,
                    itemBuilder: (ctx, i) {
                      final r = pending[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15), child: const Icon(Icons.person, color: Color(0xFFF59E0B), size: 20)),
                          title: Text(r['employeeName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text('${r['shiftName'] ?? ''} - ${_fmtDate(r['date'])}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 20), onPressed: () { Navigator.pop(ctx); _rejectRegistration(r['id']?.toString()); }),
                            IconButton(icon: const Icon(Icons.check, color: Color(0xFF1E3A5F), size: 20), onPressed: () { Navigator.pop(ctx); _approveRegistration(r['id']?.toString()); }),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  // ── Formatters ──

  String _fmtTime(dynamic t) {
    if (t == null) return '--:--';
    final parts = t.toString().split(':');
    if (parts.length >= 2) return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    return t.toString();
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }
}
