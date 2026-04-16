import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../l10n/app_localizations.dart';
import '../utils/file_saver.dart' as file_saver;
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

class AttendanceReportScreen extends StatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  State<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends State<AttendanceReportScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  String _reportType = 'daily';

  // Filters
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  Map<String, dynamic>? _reportData;
  List<dynamic> _trendData = [];

  // Sorting
  String _sortColumn = 'checkInTime';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadTrends();
  }

  Future<void> _loadTrends() async {
    try {
      final result = await _apiService.getAttendanceTrends(days: 30);
      if (mounted) {
        setState(() => _trendData = result);
      }
    } catch (e) {
      debugPrint('Load trends error: $e');
    }
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> result;
      switch (_reportType) {
        case 'daily':
          result = await _apiService.getDailyAttendanceReport(date: _selectedDate);
          break;
        case 'monthly':
          result = await _apiService.getMonthlyAttendanceReport(year: _selectedYear, month: _selectedMonth);
          break;
        case 'late-early':
          result = await _apiService.getLateEarlyReport(startDate: _startDate, endDate: _endDate);
          break;
        case 'department':
          result = await _apiService.getDepartmentSummaryReport(year: _selectedYear, month: _selectedMonth);
          break;
        case 'overtime':
          result = await _apiService.getOvertimeReport(startDate: _startDate, endDate: _endDate);
          break;
        case 'leave':
          result = await _apiService.getLeaveReport(startDate: _startDate, endDate: _endDate);
          break;
        default:
          result = {'isSuccess': false};
      }
      if (result['isSuccess'] == true && mounted) {
        setState(() => _reportData = result['data']);
      } else if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? _l10n.loadError);
      }
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> result;
      String fileName;
      switch (_reportType) {
        case 'daily':
          result = await _apiService.exportDailyReportExcel(date: _selectedDate);
          fileName = 'cc_hang_ngay_${DateFormat('yyyyMMdd').format(_selectedDate)}.xlsx';
          break;
        case 'monthly':
          result = await _apiService.exportMonthlyReportExcel(year: _selectedYear, month: _selectedMonth);
          fileName = 'cc_thang_${_selectedYear}_$_selectedMonth.xlsx';
          break;
        case 'late-early':
          result = await _apiService.exportLateEarlyReportExcel(startDate: _startDate, endDate: _endDate);
          fileName = 'di_muon_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        case 'department':
          result = await _apiService.exportDepartmentSummaryExcel(year: _selectedYear, month: _selectedMonth);
          fileName = 'phong_ban_${_selectedYear}_$_selectedMonth.xlsx';
          break;
        case 'overtime':
          result = await _apiService.exportOvertimeReportExcel(startDate: _startDate, endDate: _endDate);
          fileName = 'tang_ca_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        case 'leave':
          result = await _apiService.exportLeaveReportExcel(startDate: _startDate, endDate: _endDate);
          fileName = 'nghi_phep_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        default:
          return;
      }
      final excelData = (result['data'] as List?)?.cast<int>();
      if (excelData != null && mounted) {
        await file_saver.saveFileBytes(excelData, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        NotificationOverlayManager().showSuccess(title: 'Xuất Excel', message: _l10n.excelExported);
      }
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xuất: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildReportTypeSelector(),
                        const SizedBox(height: 16),
                        _buildDateFilter(),
                        const SizedBox(height: 20),
                        if (_trendData.isNotEmpty) ...[
                          _buildTrendChart(),
                          const SizedBox(height: 20),
                        ],
                        if (_reportData != null) ...[
                          _buildSummaryCards(),
                          const SizedBox(height: 20),
                          _buildDataTable(),
                        ] else
                          _buildEmptyState(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 14),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule, color: Color(0xFF1E3A5F), size: 24),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_l10n.attendanceReport, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_reportData != null)
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _exportExcel,
                      icon: const Icon(Icons.table_chart, size: 16),
                      label: Text(_l10n.exportExcel, style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    ),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _loadReport,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: Text(_l10n.generateReport, style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  ),
                ],
              ),
            ],
          )
        : Row(
            children: [
              const Icon(Icons.schedule, color: Color(0xFF1E3A5F), size: 26),
              const SizedBox(width: 10),
              Expanded(child: Text(_l10n.attendanceReport, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              if (_reportData != null) ...[  
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _exportExcel,
                  icon: const Icon(Icons.table_chart, size: 18),
                  label: Text(_l10n.exportExcel),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
                ),
                const SizedBox(width: 8),
              ],
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadReport,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(_l10n.generateReport),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
              ),
            ],
          ),
    );
  }

  Widget _buildReportTypeSelector() {
    final types = [
      {'id': 'daily', 'name': _l10n.dailyReport, 'icon': Icons.today},
      {'id': 'monthly', 'name': _l10n.monthlyReport, 'icon': Icons.calendar_month},
      {'id': 'late-early', 'name': _l10n.lateEarlyReport, 'icon': Icons.schedule},
      {'id': 'department', 'name': _l10n.byDeptReport, 'icon': Icons.business},
      {'id': 'overtime', 'name': 'Tăng ca', 'icon': Icons.more_time},
      {'id': 'leave', 'name': 'Nghỉ phép', 'icon': Icons.event_busy},
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_l10n.reportType, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              children: types.map((t) {
                final selected = _reportType == t['id'];
                return InkWell(
                  onTap: () => setState(() {
                    _reportType = t['id'] as String;
                    _reportData = null;
                  }),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 160,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected ? Colors.blue.withValues(alpha: 0.1) : Colors.grey.shade50,
                      border: Border.all(color: selected ? Colors.blue : Colors.grey.shade300, width: selected ? 2 : 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(children: [
                      Icon(t['icon'] as IconData, color: selected ? Colors.blue : Colors.grey, size: 28),
                      const SizedBox(height: 6),
                      Text(t['name'] as String, textAlign: TextAlign.center, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? Colors.blue : Colors.black87, fontSize: 13)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateFilter() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l10n.period, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildDateControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateControls() {
    switch (_reportType) {
      case 'daily':
        return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Ngày: '),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
            onPressed: () async {
              final date = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (date != null) setState(() => _selectedDate = date);
            },
          ),
        ]);
      case 'monthly':
      case 'department':
        return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Tháng: '),
          DropdownButton<int>(
            value: _selectedMonth,
            items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('Tháng ${i + 1}'))),
            onChanged: (v) { if (v != null) setState(() => _selectedMonth = v); },
          ),
          const Text('Năm: '),
          DropdownButton<int>(
            value: _selectedYear,
            items: List.generate(5, (i) => DropdownMenuItem(value: DateTime.now().year - i, child: Text('${DateTime.now().year - i}'))),
            onChanged: (v) { if (v != null) setState(() => _selectedYear = v); },
          ),
        ]);
      case 'late-early':
      case 'overtime':
      case 'leave':
        return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Từ: '),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
            onPressed: () async {
              final date = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (date != null) setState(() => _startDate = date);
            },
          ),
          const Text('Đến: '),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(DateFormat('dd/MM/yyyy').format(_endDate)),
            onPressed: () async {
              final date = await showDatePicker(context: context, initialDate: _endDate, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (date != null) setState(() => _endDate = date);
            },
          ),
        ]);
      default:
        return const SizedBox();
    }
  }

  Widget _buildTrendChart() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l10n.trend30Days, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(children: [
              _legendDot(Colors.green, _l10n.present),
              const SizedBox(width: 16),
              _legendDot(Colors.red, 'Vắng'),
              const SizedBox(width: 16),
              _legendDot(Colors.orange, 'Đi muộn'),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10)))),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, interval: (_trendData.length / 6).ceilToDouble().clamp(1, double.infinity), getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx >= 0 && idx < _trendData.length) {
                        final d = DateTime.tryParse(_trendData[idx]['date'] ?? '');
                        if (d != null) return Padding(padding: const EdgeInsets.only(top: 6), child: Text(DateFormat('dd/MM').format(d), style: const TextStyle(fontSize: 9)));
                      }
                      return const SizedBox();
                    })),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    _lineData(Colors.green, _trendData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value['present'] ?? e.value['totalCheckIns'] ?? 0) as num).toDouble())).toList()),
                    _lineData(Colors.red, _trendData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value['absent'] ?? e.value['absences'] ?? 0) as num).toDouble())).toList()),
                    _lineData(Colors.orange, _trendData.asMap().entries.map((e) => FlSpot(e.key.toDouble(), ((e.value['late'] ?? e.value['lateArrivals'] ?? 0) as num).toDouble())).toList()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LineChartBarData _lineData(Color color, List<FlSpot> spots) {
    return LineChartBarData(spots: spots, isCurved: true, color: color, barWidth: 2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)));
  }

  Widget _legendDot(Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12)),
    ]);
  }

  Widget _buildSummaryCards() {
    final data = _reportData!;
    List<Widget> cards;
    switch (_reportType) {
      case 'daily':
        cards = [
          _card(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
          _card(_l10n.present, '${data['present'] ?? 0}', Icons.check_circle, Colors.green),
          _card('Đi muộn', '${data['late'] ?? 0}', Icons.schedule, Colors.orange),
          _card('Về sớm', '${data['earlyLeave'] ?? 0}', Icons.exit_to_app, Colors.amber),
          _card('Vắng mặt', '${data['absent'] ?? 0}', Icons.person_off, Colors.red),
          _card('Tỷ lệ CC', '${data['attendanceRate'] ?? 0}%', Icons.percent, Colors.indigo),
        ];
        break;
      case 'monthly':
        cards = [
          _card(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
          _card('Ngày làm việc', '${data['workingDays'] ?? 0}', Icons.calendar_today, Colors.green),
          _card('Tháng', '${data['month']}/${data['year']}', Icons.date_range, Colors.teal),
        ];
        break;
      case 'late-early':
        cards = [
          _card(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
          _card('NV vi phạm', '${data['employeesWithIssues'] ?? 0}', Icons.warning, Colors.orange),
          _card('Lần muộn', '${data['totalLateCount'] ?? 0}', Icons.schedule, Colors.red),
          _card('Phút muộn', '${data['totalLateMinutes'] ?? 0}', Icons.timer, Colors.red.shade700),
          _card('Lần về sớm', '${data['totalEarlyLeaveCount'] ?? 0}', Icons.exit_to_app, Colors.amber),
        ];
        break;
      case 'department':
        cards = [
          _card(_l10n.department, '${data['totalDepartments'] ?? 0}', Icons.business, Colors.blue),
          _card(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}', Icons.people, Colors.green),
          _card('Ngày LV', '${data['workingDays'] ?? 0}', Icons.calendar_today, Colors.teal),
        ];
        break;
      case 'overtime':
        cards = [
          _card(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
          _card('NV tăng ca', '${data['employeesWithOvertime'] ?? 0}', Icons.person, Colors.orange),
          _card('Tổng phút', '${data['totalOvertimeMinutes'] ?? 0}', Icons.timer, Colors.red),
          _card('Tổng giờ', '${(data['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}h', Icons.more_time, Colors.deepOrange),
        ];
        break;
      case 'leave':
        cards = [
          _card(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
          _card('NV nghỉ phép', '${data['employeesWithLeave'] ?? 0}', Icons.person_off, Colors.orange),
          _card('Tổng đơn', '${data['totalLeaveRequests'] ?? 0}', Icons.description, Colors.purple),
          _card('Tổng ngày', '${data['totalLeaveDays'] ?? 0}', Icons.event_busy, Colors.red),
        ];
        break;
      default:
        cards = [];
    }
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 400) {
        return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList());
      }
      return Wrap(spacing: 14, runSpacing: 14, children: cards);
    });
  }

  Widget _card(String title, String value, IconData icon, Color color) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 400;
      return Container(
        width: narrow ? double.infinity : 155,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: narrow
            ? Row(children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
              ])
            : Column(children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(height: 6),
                Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade700), textAlign: TextAlign.center),
              ]),
      );
    });
  }

  Widget _buildDataTable() {
    final items = List<dynamic>.from((_reportData?['items'] as List?) ?? []);
    if (items.isEmpty) return Card(child: Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(_l10n.noData))));

    // Sort for daily report
    if (_reportType == 'daily') {
      items.sort((a, b) {
        final ma = a as Map<String, dynamic>;
        final mb = b as Map<String, dynamic>;
        final da = DateTime.tryParse(ma[_sortColumn]?.toString() ?? '');
        final db = DateTime.tryParse(mb[_sortColumn]?.toString() ?? '');
        final cmp = (da ?? DateTime(1900)).compareTo(db ?? DateTime(1900));
        return _sortAscending ? cmp : -cmp;
      });
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Chi tiết (${items.length} bản ghi)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              headingTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
              showCheckboxColumn: false,
              sortColumnIndex: _reportType == 'daily' ? (_sortColumn == 'checkInTime' ? 4 : _sortColumn == 'checkOutTime' ? 5 : null) : null,
              sortAscending: _sortAscending,
              columns: _columns(),
              rows: items.asMap().entries.map((entry) => _row(entry.key, entry.value)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  List<DataColumn> _columns() {
    switch (_reportType) {
      case 'daily':
        return [const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.employeeCode, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.fullName, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.department, textAlign: TextAlign.center))), DataColumn(label: const Expanded(child: Text('Giờ vào', textAlign: TextAlign.center)), onSort: (_, asc) { setState(() { _sortColumn = 'checkInTime'; _sortAscending = asc; }); }), DataColumn(label: const Expanded(child: Text('Giờ ra', textAlign: TextAlign.center)), onSort: (_, asc) { setState(() { _sortColumn = 'checkOutTime'; _sortAscending = asc; }); }), const DataColumn(label: Expanded(child: Text('Đi muộn', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Về sớm', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Trạng thái', textAlign: TextAlign.center)))];
      case 'monthly':
        return [const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.employeeCode, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.fullName, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.department, textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Ngày làm', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Ngày muộn', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Ngày nghỉ', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Ngày vắng', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Số giờ', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Tỷ lệ CC', textAlign: TextAlign.center)))];
      case 'late-early':
        return [const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.employeeCode, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.fullName, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.department, textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Lần muộn', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Phút muộn', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Lần về sớm', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Phút về sớm', textAlign: TextAlign.center)))];
      case 'department':
        return [const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.department, textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Số NV', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Tổng CC', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Đi muộn', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Tổng giờ', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('TB giờ/ngày', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Tỷ lệ CC', textAlign: TextAlign.center)))];
      case 'overtime':
        return [const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.employeeCode, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.fullName, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.department, textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Ngày tăng ca', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Phút tăng ca', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Giờ tăng ca', textAlign: TextAlign.center)))];
      case 'leave':
        return [const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.employeeCode, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.fullName, textAlign: TextAlign.center))), DataColumn(label: Expanded(child: Text(_l10n.department, textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Loại nghỉ', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Tổng ngày', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Đã dùng', textAlign: TextAlign.center))), const DataColumn(label: Expanded(child: Text('Còn lại', textAlign: TextAlign.center)))];
      default:
        return [];
    }
  }

  DataRow _row(int idx, dynamic item) {
    final m = item as Map<String, dynamic>;
    switch (_reportType) {
      case 'daily':
        return DataRow(cells: [DataCell(Center(child: Text('${idx + 1}'))), DataCell(Center(child: Text(m['employeeCode'] ?? ''))), DataCell(Center(child: Text(m['employeeName'] ?? ''))), DataCell(Center(child: Text(m['departmentName'] ?? ''))), DataCell(Center(child: Text(_fmtTime(m['checkInTime'])))), DataCell(Center(child: Text(_fmtTime(m['checkOutTime'])))), DataCell(Center(child: Text('${m['lateMinutes'] ?? 0}p'))), DataCell(Center(child: Text('${m['earlyLeaveMinutes'] ?? 0}p'))), DataCell(Center(child: _statusChip(m['status'] ?? '')))]);
      case 'monthly':
        return DataRow(cells: [DataCell(Center(child: Text('${idx + 1}'))), DataCell(Center(child: Text(m['employeeCode'] ?? ''))), DataCell(Center(child: Text(m['employeeName'] ?? ''))), DataCell(Center(child: Text(m['departmentName'] ?? ''))), DataCell(Center(child: Text('${m['totalDaysWorked'] ?? 0}'))), DataCell(Center(child: Text('${m['totalLateDays'] ?? 0}'))), DataCell(Center(child: Text('${m['totalLeaveDays'] ?? 0}'))), DataCell(Center(child: Text('${m['totalAbsentDays'] ?? 0}'))), DataCell(Center(child: Text('${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'))), DataCell(Center(child: Text('${m['attendanceRate'] ?? 0}%')))]);
      case 'late-early':
        return DataRow(cells: [DataCell(Center(child: Text('${idx + 1}'))), DataCell(Center(child: Text(m['employeeCode'] ?? ''))), DataCell(Center(child: Text(m['employeeName'] ?? ''))), DataCell(Center(child: Text(m['departmentName'] ?? ''))), DataCell(Center(child: Text('${m['lateCount'] ?? 0}'))), DataCell(Center(child: Text('${m['totalLateMinutes'] ?? 0}'))), DataCell(Center(child: Text('${m['earlyLeaveCount'] ?? 0}'))), DataCell(Center(child: Text('${m['totalEarlyMinutes'] ?? 0}')))]);
      case 'department':
        return DataRow(cells: [DataCell(Center(child: Text('${idx + 1}'))), DataCell(Center(child: Text(m['departmentName'] ?? ''))), DataCell(Center(child: Text('${m['employeeCount'] ?? 0}'))), DataCell(Center(child: Text('${m['totalAttendance'] ?? 0}'))), DataCell(Center(child: Text('${m['totalLateCount'] ?? 0}'))), DataCell(Center(child: Text('${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'))), DataCell(Center(child: Text('${(m['averageWorkedHoursPerDay'] ?? 0).toStringAsFixed(1)}h'))), DataCell(Center(child: Text('${m['attendanceRate'] ?? 0}%')))]);
      case 'overtime':
        return DataRow(cells: [DataCell(Center(child: Text('${idx + 1}'))), DataCell(Center(child: Text(m['employeeCode'] ?? ''))), DataCell(Center(child: Text(m['employeeName'] ?? ''))), DataCell(Center(child: Text(m['departmentName'] ?? ''))), DataCell(Center(child: Text('${m['overtimeDays'] ?? 0}'))), DataCell(Center(child: Text('${m['totalOvertimeMinutes'] ?? 0}'))), DataCell(Center(child: Text('${(m['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}h')))]);
      case 'leave':
        return DataRow(cells: [DataCell(Center(child: Text('${idx + 1}'))), DataCell(Center(child: Text(m['employeeCode'] ?? ''))), DataCell(Center(child: Text(m['employeeName'] ?? ''))), DataCell(Center(child: Text(m['departmentName'] ?? ''))), DataCell(Center(child: Text(m['leaveType'] ?? ''))), DataCell(Center(child: Text('${m['totalDays'] ?? 0}'))), DataCell(Center(child: Text('${m['usedDays'] ?? 0}'))), DataCell(Center(child: Text('${m['remainingDays'] ?? 0}')))]);
      default:
        return const DataRow(cells: []);
    }
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    try { return DateFormat('HH:mm').format(DateTime.parse(iso)); } catch (_) { return '--:--'; }
  }

  Widget _statusChip(String status) {
    Color color;
    if (status.contains('Đúng giờ')) { color = Colors.green; }
    else if (status.contains('muộn') || status.contains('Muộn')) { color = Colors.orange; }
    else if (status.contains('sớm') || status.contains('Sớm')) { color = Colors.amber; }
    else if (status.contains('Vắng')) { color = Colors.red; }
    else if (status.contains('phép') || status.contains('Nghỉ')) { color = Colors.purple; }
    else { color = Colors.grey; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: const TextStyle(fontSize: 11, color: Colors.white)),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.assessment_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Chọn loại báo cáo và nhấn "Tạo báo cáo"', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
