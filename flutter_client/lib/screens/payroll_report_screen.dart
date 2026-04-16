import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/file_saver.dart' as file_saver;
import 'dart:convert';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../l10n/app_localizations.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

class PayrollReportScreen extends StatefulWidget {
  const PayrollReportScreen({super.key});

  @override
  State<PayrollReportScreen> createState() => _PayrollReportScreenState();
}

class _PayrollReportScreenState extends State<PayrollReportScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);
  final ApiService _apiService = ApiService();
  final _currFmt = NumberFormat('#,###', 'vi_VN');
  bool _isLoading = false;

  // ignore: unused_field
  List<Employee> _employees = [];
  List<Map<String, dynamic>> _salaryProfiles = [];
  List<Map<String, dynamic>> _employeeSalaryData = [];
  // ignore: unused_field
  Map<String, dynamic> _insuranceSettings = {};
  // ignore: unused_field
  Map<String, dynamic> _salarySettings = {};

  // Filters
  String? _selectedDepartment;
  bool _showMobileFilters = false;

  List<Map<String, dynamic>> get _filteredData {
    if (_selectedDepartment == null) return _employeeSalaryData;
    return _employeeSalaryData.where((e) => e['department'] == _selectedDepartment).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _apiService.getEmployees(pageSize: 500),
        _apiService.getSalaryProfiles(),
        _apiService.getEmployeeSalaryProfiles(),
        _apiService.getSalarySettings(),
        _apiService.getInsuranceSettings(),
      ]);

      final empResult = futures[0] as List;
      final empList = empResult.map((e) => Employee.fromJson(e as Map<String, dynamic>)).toList();
      final profiles = futures[1] as List;
      final empProfiles = futures[2] as List;
      final salSettings = futures[3] as Map<String, dynamic>;
      final insSettings = futures[4] as Map<String, dynamic>;

      // Build salary data per employee
      final salaryData = <Map<String, dynamic>>[];
      for (final emp in empList) {
        if (!emp.isActive) continue;
        
        // Find employee's salary profile
        final empProfile = empProfiles.firstWhere(
          (p) => p['employeeId']?.toString() == emp.id,
          orElse: () => <String, dynamic>{},
        );

        final profileId = empProfile['salaryProfileId']?.toString();
        Map<String, dynamic>? profile;
        if (profileId != null) {
          profile = profiles.firstWhere(
            (p) => p['id']?.toString() == profileId,
            orElse: () => <String, dynamic>{},
          ) as Map<String, dynamic>?;
        }

        final baseSalary = (empProfile['baseSalary'] ?? profile?['baseSalary'] ?? 0).toDouble();
        final allowances = (empProfile['totalAllowances'] ?? 0).toDouble();

        salaryData.add({
          'employeeId': emp.id,
          'employeeCode': emp.employeeCode,
          'fullName': emp.fullName,
          'department': emp.department ?? _l10n.unallocated,
          'position': emp.position ?? '',
          'baseSalary': baseSalary,
          'allowances': allowances,
          'grossSalary': baseSalary + allowances,
          'profileName': profile?['name'] ?? '',
        });
      }

      if (mounted) {
        setState(() {
          _employees = empList;
          _salaryProfiles = profiles.cast<Map<String, dynamic>>();
          _employeeSalaryData = salaryData;
          _salarySettings = salSettings;
          _insuranceSettings = insSettings;
        });
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi tải dữ liệu: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Stats
  double get _totalBaseSalary => _filteredData.fold(0, (s, e) => s + (e['baseSalary'] as double));
  double get _totalGross => _filteredData.fold(0, (s, e) => s + (e['grossSalary'] as double));
  double get _avgBaseSalary => _filteredData.isEmpty ? 0 : _totalBaseSalary / _filteredData.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 20),
                    if (!Responsive.isMobile(context) || _showMobileFilters)
                    _buildFilters(),
                    const SizedBox(height: 20),
                    _buildSummaryCards(),
                    const SizedBox(height: 24),
                    _buildChartsRow(),
                    const SizedBox(height: 24),
                    _buildSalaryTable(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final isMobile = Responsive.isMobile(context);
    return isMobile
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.payments, color: Color(0xFF1E3A5F), size: 24),
                const SizedBox(width: 10),
                Expanded(child: Text(_l10n.payrollReport, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                GestureDetector(
                  onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                  child: Stack(
                    children: [
                      Icon(
                        _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                        color: _showMobileFilters ? Colors.orange : const Color(0xFF71717A),
                        size: 22,
                      ),
                      if (_selectedDepartment != null)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _filteredData.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.download, size: 16),
                  label: Text(_l10n.exportCsv, style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        )
      : Row(
          children: [
            const Icon(Icons.payments, color: Color(0xFF1E3A5F), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(_l10n.payrollReport, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
            ElevatedButton.icon(
              onPressed: _filteredData.isEmpty ? null : _exportCsv,
              icon: const Icon(Icons.download, size: 18),
              label: Text(_l10n.exportCsv),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
            ),
          ],
        );
  }

  Widget _buildFilters() {
    final depts = _employeeSalaryData.map((e) => e['department'] as String).toSet().toList()..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedDepartment,
                decoration: InputDecoration(labelText: _l10n.department, border: const OutlineInputBorder(), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                items: [
                  DropdownMenuItem(value: null, child: Text(_l10n.allDepartments)),
                  ...depts.map((d) => DropdownMenuItem(value: d, child: Text(d, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _selectedDepartment = v),
              ),
            ),
            if (_selectedDepartment != null)
              TextButton.icon(
                onPressed: () => setState(() => _selectedDepartment = null),
                icon: const Icon(Icons.clear, size: 16),
                label: Text(_l10n.clearFilters),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final cards = [
      _card(_l10n.totalHeadcount, '${_filteredData.length}', Icons.people, const Color(0xFF1E3A5F)),
      _card(_l10n.totalBaseSalary, _currFmt.format(_totalBaseSalary), Icons.account_balance, const Color(0xFF0F2340)),
      _card(_l10n.totalGrossSalary, _currFmt.format(_totalGross), Icons.payments, const Color(0xFF2D5F8B)),
      _card(_l10n.avgBaseSalary, _currFmt.format(_avgBaseSalary), Icons.trending_up, const Color(0xFF1E3A5F)),
      _card(_l10n.salaryProfile, '${_salaryProfiles.length}', Icons.description, const Color(0xFF153058)),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 400) {
        return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c)).toList());
      }
      return Wrap(spacing: 16, runSpacing: 16, children: cards);
    });
  }

  Widget _card(String title, String value, IconData icon, Color color) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 400;
      return Container(
        width: narrow ? double.infinity : 180,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: narrow
            ? Row(children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade700))),
                Flexible(child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis)),
              ])
            : Column(children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(height: 8),
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(height: 4),
                Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade700), textAlign: TextAlign.center),
              ]),
      );
    });
  }

  Widget _buildChartsRow() {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 800;
      if (wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildDeptSalaryChart()),
            const SizedBox(width: 16),
            Expanded(child: _buildSalaryDistributionChart()),
          ],
        );
      }
      return Column(children: [
        _buildDeptSalaryChart(),
        const SizedBox(height: 16),
        _buildSalaryDistributionChart(),
      ]);
    });
  }

  Widget _buildDeptSalaryChart() {
    final deptTotals = <String, double>{};
    for (final e in _filteredData) {
      final d = e['department'] as String;
      deptTotals[d] = (deptTotals[d] ?? 0) + (e['grossSalary'] as double);
    }
    final sorted = deptTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();
    final colors = [const Color(0xFF153058), const Color(0xFF1E3A5F), const Color(0xFF2D5F8B), const Color(0xFF1E3A5F), const Color(0xFF0F2340), const Color(0xFF78909C), const Color(0xFF90CAF9), const Color(0xFF2D5F8B)];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l10n.salaryByDept, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: top.isEmpty
                  ? Center(child: Text(_l10n.noData))
                  : BarChart(BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: top.first.value * 1.15,
                      barGroups: top.asMap().entries.map((entry) => BarChartGroupData(x: entry.key, barRods: [
                        BarChartRodData(toY: entry.value.value, color: colors[entry.key % colors.length], width: 22, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
                      ])).toList(),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (v, _) {
                          if (v >= 1000000) return Text('${(v / 1000000).toStringAsFixed(0)}M', style: const TextStyle(fontSize: 10));
                          if (v >= 1000) return Text('${(v / 1000).toStringAsFixed(0)}K', style: const TextStyle(fontSize: 10));
                          return Text('${v.toInt()}', style: const TextStyle(fontSize: 10));
                        })),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 50, getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx >= 0 && idx < top.length) {
                            final name = top[idx].key;
                            return Padding(padding: const EdgeInsets.only(top: 8), child: RotatedBox(quarterTurns: -1, child: Text(name.length > 12 ? '${name.substring(0, 12)}...' : name, style: const TextStyle(fontSize: 10))));
                          }
                          return const SizedBox();
                        })),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: true, drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipItem: (group, groupIdx, rod, rodIdx) {
                        return BarTooltipItem('${top[group.x].key}\n${_currFmt.format(rod.toY)}đ', const TextStyle(color: Colors.white, fontSize: 12));
                      })),
                    )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalaryDistributionChart() {
    // Group by salary ranges
    final ranges = <String, int>{
      '< 5M': 0, '5-10M': 0, '10-15M': 0, '15-20M': 0, '20-30M': 0, '> 30M': 0,
    };
    for (final e in _filteredData) {
      final salary = (e['baseSalary'] as double) / 1000000;
      if (salary < 5) { ranges['< 5M'] = ranges['< 5M']! + 1; }
      else if (salary < 10) { ranges['5-10M'] = ranges['5-10M']! + 1; }
      else if (salary < 15) { ranges['10-15M'] = ranges['10-15M']! + 1; }
      else if (salary < 20) { ranges['15-20M'] = ranges['15-20M']! + 1; }
      else if (salary < 30) { ranges['20-30M'] = ranges['20-30M']! + 1; }
      else { ranges['> 30M'] = ranges['> 30M']! + 1; }
    }

    final colors = [const Color(0xFF1E3A5F), const Color(0xFF2D5F8B), const Color(0xFF0F2340), const Color(0xFF1E3A5F), const Color(0xFF153058), const Color(0xFF78909C)];
    final nonZero = ranges.entries.where((e) => e.value > 0).toList();
    final sections = nonZero.asMap().entries.map((entry) {
      return PieChartSectionData(
        value: entry.value.value.toDouble(),
        title: '${entry.value.key}\n${entry.value.value}',
        color: colors[entry.key % colors.length],
        radius: 80,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_l10n.salaryDistribution, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: sections.isEmpty
                  ? Center(child: Text(_l10n.noData))
                  : PieChart(PieChartData(sections: sections, centerSpaceRadius: 40, sectionsSpace: 2)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalaryTable() {
    final items = _filteredData;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Chi tiết lương (${items.length} nhân viên)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
              headingTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
              showCheckboxColumn: false,
              columns: [
                const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
                DataColumn(label: Expanded(child: Text(_l10n.employeeCode, textAlign: TextAlign.center))),
                DataColumn(label: Expanded(child: Text(_l10n.fullName, textAlign: TextAlign.center))),
                DataColumn(label: Expanded(child: Text(_l10n.department, textAlign: TextAlign.center))),
                DataColumn(label: Expanded(child: Text(_l10n.position, textAlign: TextAlign.center))),
                DataColumn(label: Expanded(child: Text(_l10n.salaryProfile, textAlign: TextAlign.center))),
                DataColumn(label: Expanded(child: Text(_l10n.baseSalary, textAlign: TextAlign.center))),
                DataColumn(label: Expanded(child: Text(_l10n.allowance, textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('Tổng gộp', textAlign: TextAlign.center))),
              ],
              rows: items.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                return DataRow(cells: [
                  DataCell(Center(child: Text('${i + 1}'))),
                  DataCell(Center(child: Text(e['employeeCode'] ?? ''))),
                  DataCell(Center(child: Text(e['fullName'] ?? ''))),
                  DataCell(Center(child: Text(e['department'] ?? ''))),
                  DataCell(Center(child: Text(e['position'] ?? ''))),
                  DataCell(Center(child: Text(e['profileName'] ?? ''))),
                  DataCell(Center(child: Text(_currFmt.format(e['baseSalary'] ?? 0)))),
                  DataCell(Center(child: Text(_currFmt.format(e['allowances'] ?? 0)))),
                  DataCell(Center(child: Text(_currFmt.format(e['grossSalary'] ?? 0), style: const TextStyle(fontWeight: FontWeight.bold)))),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln('STT,Mã NV,Họ tên,Phòng ban,Chức vụ,Hồ sơ lương,Lương cơ bản,Phụ cấp,Tổng gộp');
    for (var i = 0; i < _filteredData.length; i++) {
      final e = _filteredData[i];
      buf.writeln('${i + 1},${e['employeeCode']},"${e['fullName']}","${e['department']}","${e['position']}","${e['profileName']}",${(e['baseSalary'] as double).toInt()},${(e['allowances'] as double).toInt()},${(e['grossSalary'] as double).toInt()}');
    }
    final bytes = utf8.encode(buf.toString());
      await file_saver.saveFileBytes(bytes, 'bao_cao_luong_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv', 'text/csv;charset=utf-8');
    NotificationOverlayManager().showSuccess(title: 'Xuất báo cáo', message: 'Đã xuất báo cáo CSV');
  }
}
