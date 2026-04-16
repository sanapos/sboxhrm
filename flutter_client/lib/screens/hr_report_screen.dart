import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/responsive_helper.dart';
import '../utils/file_saver.dart' as file_saver;
import 'dart:convert';
import '../services/api_service.dart';
import '../models/employee.dart';
import '../models/department.dart';
import '../l10n/app_localizations.dart';
import '../widgets/notification_overlay.dart';

class HrReportScreen extends StatefulWidget {
  const HrReportScreen({super.key});

  @override
  State<HrReportScreen> createState() => _HrReportScreenState();
}

class _HrReportScreenState extends State<HrReportScreen>
    with SingleTickerProviderStateMixin {
  AppLocalizations get _l10n => AppLocalizations.of(context);
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<Employee> _employees = [];
  // ignore: unused_field
  List<Department> _departments = [];
  late TabController _tabController;

  // Filters
  String? _selectedDepartment;
  String? _selectedStatus;
  String? _selectedGender;

  // Sorting
  String _sortColumn = 'joinDate';
  bool _sortAscending = false;

  // Mobile UI state
  bool _showMobileFilters = false;

  // Active employees only
  List<Employee> get _activeEmployees =>
      _employees.where((e) => e.isActive).toList();

  List<Employee> get _filteredEmployees {
    return _employees.where((e) {
      if (_selectedDepartment != null && e.department != _selectedDepartment) {
        return false;
      }
      if (_selectedGender != null) {
        final g = e.gender?.toLowerCase();
        if (_selectedGender == 'male' && g != 'male' && e.gender != 'Nam') {
          return false;
        }
        if (_selectedGender == 'female' && g != 'female' && e.gender != 'Nữ') {
          return false;
        }
      }
      if (_selectedStatus != null) {
        if (_selectedStatus == 'Active' && !e.isActive) { return false; }
        if (_selectedStatus == 'Inactive' && e.isActive) { return false; }
      }
      return true;
    }).toList();
  }

  // ===== Computed Stats =====
  int get _totalEmployees => _filteredEmployees.length;
  int get _activeCount => _filteredEmployees.where((e) => e.isActive).length;
  int get _maleCount => _filteredEmployees
      .where((e) => e.gender?.toLowerCase() == 'male' || e.gender == 'Nam')
      .length;
  int get _femaleCount => _filteredEmployees
      .where((e) => e.gender?.toLowerCase() == 'female' || e.gender == 'Nữ')
      .length;

  int get _singleCount => _filteredEmployees.where((e) {
        final s = e.maritalStatus?.toLowerCase();
        return s == 'single' || s == 'độc thân';
      }).length;

  int get _marriedCount => _filteredEmployees.where((e) {
        final s = e.maritalStatus?.toLowerCase();
        return s == 'married' || s == 'đã kết hôn';
      }).length;

  // Birthdays this month
  List<Employee> get _birthdaysThisMonth {
    final now = DateTime.now();
    return _activeEmployees.where((e) {
      if (e.dateOfBirth == null) return false;
      return e.dateOfBirth!.month == now.month;
    }).toList()
      ..sort((a, b) => a.dateOfBirth!.day.compareTo(b.dateOfBirth!.day));
  }

  // Upcoming birthdays (next 30 days)
  List<Employee> get _upcomingBirthdays {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _activeEmployees.where((e) {
      if (e.dateOfBirth == null) return false;
      var bday = DateTime(now.year, e.dateOfBirth!.month, e.dateOfBirth!.day);
      if (bday.isBefore(today)) {
        bday = DateTime(now.year + 1, e.dateOfBirth!.month, e.dateOfBirth!.day);
      }
      final diff = bday.difference(today).inDays;
      return diff >= 0 && diff <= 30;
    }).toList()
      ..sort((a, b) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        var bdayA =
            DateTime(now.year, a.dateOfBirth!.month, a.dateOfBirth!.day);
        var bdayB =
            DateTime(now.year, b.dateOfBirth!.month, b.dateOfBirth!.day);
        if (bdayA.isBefore(today)) {
          bdayA =
              DateTime(now.year + 1, a.dateOfBirth!.month, a.dateOfBirth!.day);
        }
        if (bdayB.isBefore(today)) {
          bdayB =
              DateTime(now.year + 1, b.dateOfBirth!.month, b.dateOfBirth!.day);
        }
        return bdayA.compareTo(bdayB);
      });
  }

  // Birthdays by month (for chart)
  Map<int, int> get _birthdaysByMonth {
    final map = <int, int>{};
    for (int i = 1; i <= 12; i++) {
      map[i] = 0;
    }
    for (final e in _activeEmployees) {
      if (e.dateOfBirth != null) {
        map[e.dateOfBirth!.month] = (map[e.dateOfBirth!.month] ?? 0) + 1;
      }
    }
    return map;
  }

  // Seniority groups
  Map<String, List<Employee>> get _seniorityGroups {
    final now = DateTime.now();
    final groups = <String, List<Employee>>{
      _l10n.tenureUnder1Year: [],
      _l10n.tenure1To3: [],
      _l10n.tenure3To5: [],
      _l10n.tenure5To10: [],
      _l10n.tenureOver10: [],
    };
    for (final e in _activeEmployees) {
      if (e.joinDate == null) continue;
      final years = now.difference(e.joinDate!).inDays / 365.25;
      if (years < 1) {
        groups[_l10n.tenureUnder1Year]!.add(e);
      } else if (years < 3) {
        groups[_l10n.tenure1To3]!.add(e);
      } else if (years < 5) {
        groups[_l10n.tenure3To5]!.add(e);
      } else if (years < 10) {
        groups[_l10n.tenure5To10]!.add(e);
      } else {
        groups[_l10n.tenureOver10]!.add(e);
      }
    }
    return groups;
  }

  // Hometown by province
  Map<String, int> get _hometownStats {
    final map = <String, int>{};
    for (final e in _filteredEmployees) {
      final ht = e.hometown;
      if (ht != null && ht.isNotEmpty) {
        map[ht] = (map[ht] ?? 0) + 1;
      } else {
        map[_l10n.notUpdated] = (map[_l10n.notUpdated] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
        map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  // Education level stats
  Map<String, int> get _educationStats {
    final map = <String, int>{};
    for (final e in _filteredEmployees) {
      final el = e.educationLevel;
      if (el != null && el.isNotEmpty) {
        map[el] = (map[el] ?? 0) + 1;
      } else {
        map[_l10n.notUpdated] = (map[_l10n.notUpdated] ?? 0) + 1;
      }
    }
    return Map.fromEntries(
        map.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final empResult = await _apiService.getEmployees(pageSize: 500);
      final empList = empResult
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() => _employees = empList);
      }

      try {
        final deptResult = await _apiService.getDepartments();
        final deptData = deptResult['data'];
        final deptItems = deptData is List
            ? deptData
            : (deptData is Map ? (deptData['items'] as List? ?? []) : []);
        final deptList = deptItems
            .map((d) => Department.fromJson(d as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() => _departments = deptList);
        }
      } catch (_) {
        // Departments are optional, don't block employee data
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi tải dữ liệu: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                if (!Responsive.isMobile(context) || _showMobileFilters) _buildFilters(),
                _buildTabBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildBirthdayTab(),
                      _buildDemographicsTab(),
                      _buildEmployeeListTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ===== HEADER =====
  Widget _buildHeader() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 20, isMobile ? 16 : 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.assessment, color: Colors.teal.shade700, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_l10n.hrReport,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF18181B))),
                    if (!isMobile)
                      Text(_l10n.hrReportSubtitleLong,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF71717A))),
                  ],
                ),
              ),
              if (!isMobile) ...[
                ElevatedButton.icon(
                  onPressed: _filteredEmployees.isEmpty ? null : _exportCsv,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(_l10n.exportCsv),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal, foregroundColor: Colors.white),
                ),
              ],
            ],
          ),
          if (isMobile) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
                  icon: Stack(
                    children: [
                      Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18),
                      if (_selectedDepartment != null || _selectedGender != null || _selectedStatus != null)
                        Positioned(right: 0, top: 0, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                    ],
                  ),
                  label: Text(_showMobileFilters ? 'Ẩn lọc' : 'Bộ lọc'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _filteredEmployees.isEmpty ? null : _exportCsv,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text(_l10n.exportCsv),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===== FILTERS =====
  Widget _buildFilters() {
    final deptNames = _employees
        .map((e) => e.department)
        .where((d) => d != null && d.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              key: ValueKey('dept_$_selectedDepartment'),
              initialValue: _selectedDepartment,
              decoration: InputDecoration(
                  labelText: _l10n.department,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: [
                DropdownMenuItem<String>(
                    value: null, child: Text(_l10n.allDepartments)),
                ...deptNames.map((d) => DropdownMenuItem<String>(
                    value: d,
                    child: Text(d!, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => _selectedDepartment = v),
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              key: ValueKey('gender_$_selectedGender'),
              initialValue: _selectedGender,
              decoration: InputDecoration(
                  labelText: _l10n.gender,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: [
                DropdownMenuItem<String>(value: null, child: Text(_l10n.all)),
                const DropdownMenuItem<String>(
                    value: 'male', child: Text('Nam')),
                const DropdownMenuItem<String>(
                    value: 'female', child: Text('Nữ')),
              ],
              onChanged: (v) => setState(() => _selectedGender = v),
            ),
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              key: ValueKey('status_$_selectedStatus'),
              initialValue: _selectedStatus,
              decoration: const InputDecoration(
                  labelText: 'Trạng thái',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
              items: [
                DropdownMenuItem<String>(value: null, child: Text(_l10n.all)),
                const DropdownMenuItem<String>(
                    value: 'Active', child: Text('Đang làm việc')),
                const DropdownMenuItem<String>(
                    value: 'Inactive', child: Text('Ngừng làm việc')),
              ],
              onChanged: (v) => setState(() => _selectedStatus = v),
            ),
          ),
          if (_selectedDepartment != null ||
              _selectedGender != null ||
              _selectedStatus != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _selectedDepartment = null;
                _selectedGender = null;
                _selectedStatus = null;
              }),
              icon: const Icon(Icons.clear, size: 16),
              label: Text(_l10n.clearFilters),
            ),
        ],
      ),
    );
  }

  // ===== TAB BAR =====
  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.teal.shade700,
        unselectedLabelColor: const Color(0xFFA1A1AA),
        indicatorColor: Colors.teal,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: const [
          Tab(text: 'Tổng quan', icon: Icon(Icons.dashboard, size: 18)),
          Tab(text: 'Sinh nhật', icon: Icon(Icons.cake, size: 18)),
          Tab(text: 'Nhân khẩu học', icon: Icon(Icons.pie_chart, size: 18)),
          Tab(text: 'Danh sách', icon: Icon(Icons.list_alt, size: 18)),
        ],
      ),
    );
  }

  // ===========================================================
  // TAB 1: TỔNG QUAN
  // ===========================================================
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildDepartmentChart()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildSeniorityChart()),
                ],
              );
            }
            return Column(children: [
              _buildDepartmentChart(),
              const SizedBox(height: 16),
              _buildSeniorityChart(),
            ]);
          }),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildGenderPieChart()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMaritalStatusChart()),
                ],
              );
            }
            return Column(children: [
              _buildGenderPieChart(),
              const SizedBox(height: 16),
              _buildMaritalStatusChart(),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final newThisMonth = _filteredEmployees.where((e) {
      if (e.joinDate == null) return false;
      final now = DateTime.now();
      return e.joinDate!.year == now.year && e.joinDate!.month == now.month;
    }).length;

    // Average seniority
    double avgSeniority = 0;
    final withJoinDate =
        _activeEmployees.where((e) => e.joinDate != null).toList();
    if (withJoinDate.isNotEmpty) {
      final totalDays = withJoinDate.fold<int>(
          0, (sum, e) => sum + DateTime.now().difference(e.joinDate!).inDays);
      avgSeniority = totalDays / withJoinDate.length / 365.25;
    }

    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _summaryCard(_l10n.totalHeadcount, '$_totalEmployees', Icons.people,
            Colors.blue),
        _summaryCard(
            'Đang làm việc', '$_activeCount', Icons.check_circle, Colors.green),
        _summaryCard('Nam', '$_maleCount', Icons.male, Colors.indigo),
        _summaryCard('Nữ', '$_femaleCount', Icons.female, Colors.pink),
        _summaryCard('Độc thân', '$_singleCount', Icons.person, Colors.orange),
        _summaryCard('Có gia đình', '$_marriedCount', Icons.family_restroom,
            Colors.purple),
        _summaryCard(
            'Mới trong tháng', '$newThisMonth', Icons.person_add, Colors.teal),
        _summaryCard('TB thâm niên', '${avgSeniority.toStringAsFixed(1)} năm',
            Icons.timeline, Colors.amber.shade800),
        _summaryCard('Sinh nhật tháng này', '${_birthdaysThisMonth.length}',
            Icons.cake, Colors.red),
      ],
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 165,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(title,
              style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  // ===== Department Chart =====
  Widget _buildDepartmentChart() {
    final deptCounts = <String, int>{};
    for (final e in _filteredEmployees) {
      final d = e.department ?? _l10n.unallocated;
      deptCounts[d] = (deptCounts[d] ?? 0) + 1;
    }
    final sorted = deptCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();
    final colors = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.green,
      Colors.red,
      Colors.indigo,
      Colors.amber
    ];

    return _chartCard(
      title: 'Nhân sự theo phòng ban',
      icon: Icons.business,
      child: SizedBox(
        height: 260,
        child: top.isEmpty
            ? Center(child: Text(_l10n.noData))
            : BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (top.first.value * 1.2).toDouble(),
                barGroups: top.asMap().entries.map((entry) {
                  return BarChartGroupData(x: entry.key, barRods: [
                    BarChartRodData(
                        toY: entry.value.value.toDouble(),
                        color: colors[entry.key % colors.length],
                        width: 22,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4))),
                  ]);
                }).toList(),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}',
                              style: const TextStyle(fontSize: 11)))),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 50,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= 0 && idx < top.length) {
                              final name = top[idx].key;
                              return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: RotatedBox(
                                      quarterTurns: -1,
                                      child: Text(
                                          name.length > 12
                                              ? '${name.substring(0, 12)}...'
                                              : name,
                                          style:
                                              const TextStyle(fontSize: 10))));
                            }
                            return const SizedBox();
                          })),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (top.first.value / 4)
                        .ceilToDouble()
                        .clamp(1, double.infinity)),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIdx, rod, rodIdx) =>
                      BarTooltipItem(
                          '${top[group.x].key}\n${rod.toY.toInt()} người',
                          const TextStyle(color: Colors.white, fontSize: 12)),
                )),
              )),
      ),
    );
  }

  // ===== Seniority Chart =====
  Widget _buildSeniorityChart() {
    final groups = _seniorityGroups;
    final labels = groups.keys.toList();
    final colors = [
      Colors.green.shade400,
      Colors.blue.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.red.shade400
    ];
    final maxVal =
        groups.values.map((l) => l.length).fold(0, (a, b) => a > b ? a : b);

    return _chartCard(
      title: 'Thâm niên làm việc',
      icon: Icons.timeline,
      child: SizedBox(
        height: 260,
        child: maxVal == 0
            ? Center(child: Text(_l10n.noData))
            : BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxVal * 1.2).toDouble(),
                barGroups: labels.asMap().entries.map((entry) {
                  return BarChartGroupData(x: entry.key, barRods: [
                    BarChartRodData(
                        toY: groups[entry.value]!.length.toDouble(),
                        color: colors[entry.key % colors.length],
                        width: 28,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4))),
                  ]);
                }).toList(),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}',
                              style: const TextStyle(fontSize: 11)))),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 40,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= 0 && idx < labels.length) {
                              return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(labels[idx],
                                      style: const TextStyle(fontSize: 10),
                                      textAlign: TextAlign.center));
                            }
                            return const SizedBox();
                          })),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        (maxVal / 4).ceilToDouble().clamp(1, double.infinity)),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIdx, rod, rodIdx) =>
                      BarTooltipItem(
                          '${labels[group.x]}\n${rod.toY.toInt()} người',
                          const TextStyle(color: Colors.white, fontSize: 12)),
                )),
              )),
      ),
    );
  }

  // ===== Gender Pie Chart =====
  Widget _buildGenderPieChart() {
    final otherCount = _totalEmployees - _maleCount - _femaleCount;
    final sections = <PieChartSectionData>[];
    if (_maleCount > 0) {
      sections.add(PieChartSectionData(
          value: _maleCount.toDouble(),
          title: 'Nam\n$_maleCount',
          color: Colors.blue.shade400,
          radius: 75,
          titleStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)));
    }
    if (_femaleCount > 0) {
      sections.add(PieChartSectionData(
          value: _femaleCount.toDouble(),
          title: 'Nữ\n$_femaleCount',
          color: Colors.pink.shade400,
          radius: 75,
          titleStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)));
    }
    if (otherCount > 0) {
      sections.add(PieChartSectionData(
          value: otherCount.toDouble(),
          title: 'Khác\n$otherCount',
          color: Colors.grey.shade400,
          radius: 75,
          titleStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)));
    }

    return _chartCard(
      title: 'Tỷ lệ giới tính',
      icon: Icons.wc,
      child: SizedBox(
        height: 240,
        child: sections.isEmpty
            ? Center(child: Text(_l10n.noData))
            : PieChart(PieChartData(
                sections: sections, centerSpaceRadius: 35, sectionsSpace: 2)),
      ),
    );
  }

  // ===== Marital Status Chart =====
  Widget _buildMaritalStatusChart() {
    final otherCount = _totalEmployees - _singleCount - _marriedCount;
    final sections = <PieChartSectionData>[];
    if (_singleCount > 0) {
      sections.add(PieChartSectionData(
          value: _singleCount.toDouble(),
          title: 'Độc thân\n$_singleCount',
          color: Colors.orange.shade400,
          radius: 75,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)));
    }
    if (_marriedCount > 0) {
      sections.add(PieChartSectionData(
          value: _marriedCount.toDouble(),
          title: 'Có gia đình\n$_marriedCount',
          color: Colors.purple.shade400,
          radius: 75,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)));
    }
    if (otherCount > 0) {
      sections.add(PieChartSectionData(
          value: otherCount.toDouble(),
          title: 'Khác\n$otherCount',
          color: Colors.grey.shade400,
          radius: 75,
          titleStyle: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)));
    }

    return _chartCard(
      title: 'Tình trạng hôn nhân',
      icon: Icons.favorite,
      child: SizedBox(
        height: 240,
        child: sections.isEmpty
            ? Center(child: Text(_l10n.noData))
            : PieChart(PieChartData(
                sections: sections, centerSpaceRadius: 35, sectionsSpace: 2)),
      ),
    );
  }

  // ===========================================================
  // TAB 2: SINH NHẬT
  // ===========================================================
  Widget _buildBirthdayTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Birthday summary cards
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _summaryCard('Sinh nhật tháng này',
                  '${_birthdaysThisMonth.length}', Icons.cake, Colors.red),
              _summaryCard('Sắp đến (30 ngày)', '${_upcomingBirthdays.length}',
                  Icons.event, Colors.orange),
            ],
          ),
          const SizedBox(height: 24),

          // Upcoming birthdays list
          _buildUpcomingBirthdaysList(),
          const SizedBox(height: 24),

          // Birthday by month chart
          _buildBirthdayByMonthChart(),
          const SizedBox(height: 24),

          // Full birthday calendar table
          _buildBirthdayCalendarTable(),
        ],
      ),
    );
  }

  Widget _buildUpcomingBirthdaysList() {
    final upcoming = _upcomingBirthdays;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _chartCard(
      title: 'Sinh nhật sắp đến (30 ngày tới)',
      icon: Icons.celebration,
      child: upcoming.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text('Không có sinh nhật sắp đến',
                      style: TextStyle(color: Color(0xFFA1A1AA)))))
          : Column(
              children: upcoming.map((e) {
                var bday = DateTime(
                    now.year, e.dateOfBirth!.month, e.dateOfBirth!.day);
                if (bday.isBefore(today)) {
                  bday = DateTime(
                      now.year + 1, e.dateOfBirth!.month, e.dateOfBirth!.day);
                }
                final daysLeft = bday.difference(today).inDays;
                final age = now.year - e.dateOfBirth!.year;
                final isToday = daysLeft == 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 2),
                  decoration: BoxDecoration(
                    color: isToday ? Colors.red.shade50 : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          isToday ? Colors.red.shade100 : Colors.teal.shade50,
                      backgroundImage:
                          e.avatarUrl != null && e.avatarUrl!.isNotEmpty
                              ? NetworkImage(e.avatarUrl!)
                              : null,
                      onBackgroundImageError: e.avatarUrl != null && e.avatarUrl!.isNotEmpty ? (_, __) {} : null,
                      child: e.avatarUrl == null || e.avatarUrl!.isEmpty
                          ? Text(e.firstName.isNotEmpty ? e.firstName[0] : '?',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: isToday ? Colors.red : Colors.teal))
                          : null,
                    ),
                    title: Row(
                      children: [
                        Text(e.fullName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                        if (isToday) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('HÔM NAY',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                        '${e.department ?? ''} • ${DateFormat('dd/MM').format(e.dateOfBirth!)} • Tròn $age tuổi',
                        style: const TextStyle(fontSize: 11)),
                    trailing: Text(
                      isToday ? '🎂' : 'Còn $daysLeft ngày',
                      style: TextStyle(
                          fontSize: isToday ? 20 : 12,
                          color: isToday ? null : const Color(0xFF71717A),
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildBirthdayByMonthChart() {
    final data = _birthdaysByMonth;
    final monthNames = [
      'T1',
      'T2',
      'T3',
      'T4',
      'T5',
      'T6',
      'T7',
      'T8',
      'T9',
      'T10',
      'T11',
      'T12'
    ];
    final maxVal = data.values.fold(0, (a, b) => a > b ? a : b);
    final now = DateTime.now();

    return _chartCard(
      title: 'Sinh nhật theo tháng trong năm',
      icon: Icons.calendar_month,
      child: SizedBox(
        height: 220,
        child: maxVal == 0
            ? Center(child: Text(_l10n.noData))
            : BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxVal * 1.3).toDouble(),
                barGroups: List.generate(12, (i) {
                  final isCurrentMonth = i + 1 == now.month;
                  return BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: (data[i + 1] ?? 0).toDouble(),
                      color: isCurrentMonth ? Colors.red : Colors.teal.shade300,
                      width: 18,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ]);
                }),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}',
                              style: const TextStyle(fontSize: 10)))),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= 0 && idx < 12) {
                              final isCurrentMonth = idx + 1 == now.month;
                              return Text(monthNames[idx],
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isCurrentMonth
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color:
                                          isCurrentMonth ? Colors.red : null));
                            }
                            return const SizedBox();
                          })),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval:
                        (maxVal / 3).ceilToDouble().clamp(1, double.infinity)),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIdx, rod, rodIdx) =>
                      BarTooltipItem(
                          'Tháng ${group.x + 1}\n${rod.toY.toInt()} người',
                          const TextStyle(color: Colors.white, fontSize: 12)),
                )),
              )),
      ),
    );
  }

  Widget _buildBirthdayCalendarTable() {
    // Group by month
    final byMonth = <int, List<Employee>>{};
    for (final e in _activeEmployees) {
      if (e.dateOfBirth != null) {
        byMonth.putIfAbsent(e.dateOfBirth!.month, () => []);
        byMonth[e.dateOfBirth!.month]!.add(e);
      }
    }
    for (final list in byMonth.values) {
      list.sort((a, b) => a.dateOfBirth!.day.compareTo(b.dateOfBirth!.day));
    }

    final monthNames = [
      '',
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12'
    ];
    final now = DateTime.now();

    return _chartCard(
      title: 'Lịch sinh nhật trong năm',
      icon: Icons.calendar_today,
      child: Column(
        children: List.generate(12, (i) {
          final month = i + 1;
          final emps = byMonth[month] ?? [];
          if (emps.isEmpty) return const SizedBox.shrink();
          final isCurrentMonth = month == now.month;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color:
                  isCurrentMonth ? Colors.red.shade50 : const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: isCurrentMonth
                      ? Colors.red.shade200
                      : const Color(0xFFE4E4E7)),
            ),
            child: ExpansionTile(
              initiallyExpanded: isCurrentMonth,
              tilePadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Row(
                children: [
                  Text(monthNames[month],
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isCurrentMonth ? Colors.red.shade700 : null)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: isCurrentMonth ? Colors.red : Colors.teal,
                        borderRadius: BorderRadius.circular(10)),
                    child: Text('${emps.length}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              children: emps.map((e) {
                final age = now.year - e.dateOfBirth!.year;
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundImage:
                        e.avatarUrl != null && e.avatarUrl!.isNotEmpty
                            ? NetworkImage(e.avatarUrl!)
                            : null,
                    onBackgroundImageError: e.avatarUrl != null && e.avatarUrl!.isNotEmpty ? (_, __) {} : null,
                    child: e.avatarUrl == null || e.avatarUrl!.isEmpty
                        ? Icon(
                            e.gender?.toLowerCase() == 'female' ||
                                    e.gender?.toLowerCase() == 'nữ'
                                ? Icons.woman_rounded
                                : Icons.man_rounded,
                            size: 18,
                          )
                        : null,
                  ),
                  title: Text(e.fullName, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${e.department ?? ''} • ${e.position ?? ''}',
                      style: const TextStyle(fontSize: 11)),
                  trailing: Text(
                      '${DateFormat('dd/MM').format(e.dateOfBirth!)} ($age tuổi)',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF71717A))),
                );
              }).toList(),
            ),
          );
        }),
      ),
    );
  }

  // ===========================================================
  // TAB 3: NHÂN KHẨU HỌC
  // ===========================================================
  Widget _buildDemographicsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildHometownChart()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildEducationChart()),
                ],
              );
            }
            return Column(children: [
              _buildHometownChart(),
              const SizedBox(height: 16),
              _buildEducationChart(),
            ]);
          }),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildHometownTable()),
                  const SizedBox(width: 16),
                  Expanded(child: _buildEducationTable()),
                ],
              );
            }
            return Column(children: [
              _buildHometownTable(),
              const SizedBox(height: 16),
              _buildEducationTable(),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _buildHometownChart() {
    final stats = _hometownStats;
    final top =
        stats.entries.where((e) => e.key != _l10n.notUpdated).take(10).toList();
    final colors = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.green,
      Colors.red,
      Colors.indigo,
      Colors.amber,
      Colors.cyan,
      Colors.brown
    ];

    return _chartCard(
      title: 'Quê quán theo tỉnh thành',
      icon: Icons.location_city,
      child: SizedBox(
        height: 280,
        child: top.isEmpty
            ? const Center(
                child: Text('Chưa có dữ liệu quê quán',
                    style: TextStyle(color: Color(0xFFA1A1AA))))
            : BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (top.first.value * 1.2).toDouble(),
                barGroups: top.asMap().entries.map((entry) {
                  return BarChartGroupData(x: entry.key, barRods: [
                    BarChartRodData(
                        toY: entry.value.value.toDouble(),
                        color: colors[entry.key % colors.length],
                        width: 20,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4))),
                  ]);
                }).toList(),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}',
                              style: const TextStyle(fontSize: 11)))),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 60,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= 0 && idx < top.length) {
                              final name = top[idx].key;
                              return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: RotatedBox(
                                      quarterTurns: -1,
                                      child: Text(
                                          name.length > 14
                                              ? '${name.substring(0, 14)}...'
                                              : name,
                                          style:
                                              const TextStyle(fontSize: 10))));
                            }
                            return const SizedBox();
                          })),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: (top.first.value / 4)
                        .ceilToDouble()
                        .clamp(1, double.infinity)),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIdx, rod, rodIdx) =>
                      BarTooltipItem(
                          '${top[group.x].key}\n${rod.toY.toInt()} người',
                          const TextStyle(color: Colors.white, fontSize: 12)),
                )),
              )),
      ),
    );
  }

  Widget _buildEducationChart() {
    final stats = _educationStats;
    final items =
        stats.entries.where((e) => e.key != _l10n.notUpdated).toList();
    final total = items.fold<int>(0, (sum, e) => sum + e.value);
    final colors = [
      Colors.blue.shade400,
      Colors.teal.shade400,
      Colors.orange.shade400,
      Colors.purple.shade400,
      Colors.green.shade400,
      Colors.red.shade400,
      Colors.indigo.shade400
    ];

    final sections = items.asMap().entries.map((entry) {
      final pct = total > 0
          ? (entry.value.value / total * 100).toStringAsFixed(0)
          : '0';
      return PieChartSectionData(
        value: entry.value.value.toDouble(),
        title: '${entry.value.key}\n${entry.value.value} ($pct%)',
        color: colors[entry.key % colors.length],
        radius: 80,
        titleStyle: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
      );
    }).toList();

    return _chartCard(
      title: 'Trình độ học vấn',
      icon: Icons.school,
      child: SizedBox(
        height: 280,
        child: sections.isEmpty
            ? const Center(
                child: Text('Chưa có dữ liệu trình độ',
                    style: TextStyle(color: Color(0xFFA1A1AA))))
            : PieChart(PieChartData(
                sections: sections, centerSpaceRadius: 30, sectionsSpace: 2)),
      ),
    );
  }

  Widget _buildHometownTable() {
    final stats = _hometownStats;
    return _chartCard(
      title: 'Chi tiết quê quán',
      icon: Icons.map,
      child: stats.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text(_l10n.noData)))
          : Column(
              children: stats.entries.map((entry) {
                final pct = _filteredEmployees.isNotEmpty
                    ? (entry.value / _filteredEmployees.length * 100)
                        .toStringAsFixed(1)
                    : '0';
                return ListTile(
                  dense: true,
                  leading: Icon(
                      entry.key == _l10n.notUpdated
                          ? Icons.help_outline
                          : Icons.location_on,
                      size: 18,
                      color: entry.key == _l10n.notUpdated
                          ? Colors.grey
                          : Colors.teal),
                  title: Text(entry.key, style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${entry.value} người',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('$pct%',
                            style: TextStyle(
                                fontSize: 10, color: Colors.teal.shade700)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildEducationTable() {
    final stats = _educationStats;
    return _chartCard(
      title: 'Chi tiết trình độ học vấn',
      icon: Icons.school,
      child: stats.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(20),
              child: Center(child: Text(_l10n.noData)))
          : Column(
              children: stats.entries.map((entry) {
                final pct = _filteredEmployees.isNotEmpty
                    ? (entry.value / _filteredEmployees.length * 100)
                        .toStringAsFixed(1)
                    : '0';
                return ListTile(
                  dense: true,
                  leading: Icon(
                      entry.key == _l10n.notUpdated
                          ? Icons.help_outline
                          : Icons.school,
                      size: 18,
                      color: entry.key == _l10n.notUpdated
                          ? Colors.grey
                          : Colors.blue),
                  title: Text(entry.key, style: const TextStyle(fontSize: 13)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${entry.value} người',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('$pct%',
                            style: TextStyle(
                                fontSize: 10, color: Colors.blue.shade700)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  // ===========================================================
  // TAB 4: DANH SÁCH
  // ===========================================================
  Widget _buildEmployeeListTab() {
    final items = _filteredEmployees;
    // Sort
    items.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'dateOfBirth':
          cmp = (a.dateOfBirth ?? DateTime(2000))
              .compareTo(b.dateOfBirth ?? DateTime(2000));
          break;
        case 'joinDate':
        default:
          cmp = (a.joinDate ?? DateTime(2000))
              .compareTo(b.joinDate ?? DateTime(2000));
      }
      return _sortAscending ? cmp : -cmp;
    });
    final now = DateTime.now();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Danh sách nhân sự (${items.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return _buildMobileHrCardList(items);
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    sortColumnIndex: _sortColumn == 'dateOfBirth'
                        ? 4
                        : (_sortColumn == 'joinDate' ? 10 : null),
                    sortAscending: _sortAscending,
                    headingRowColor:
                        WidgetStateProperty.all(const Color(0xFFFAFAFA)),
                    headingTextStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF52525B)),
                    dataTextStyle:
                        const TextStyle(fontSize: 12, color: Color(0xFF334155)),
                    showCheckboxColumn: false,
                    columns: [
                      const DataColumn(label: Text('STT')),
                      DataColumn(label: Text(_l10n.employeeCode)),
                      DataColumn(label: Text(_l10n.fullName)),
                      DataColumn(label: Text(_l10n.gender)),
                      DataColumn(
                          label: const Text('Ngày sinh'),
                          onSort: (_, asc) => setState(() {
                                _sortColumn = 'dateOfBirth';
                                _sortAscending = asc;
                              })),
                      const DataColumn(label: Text('Quê quán')),
                      const DataColumn(label: Text('Trình độ')),
                      const DataColumn(label: Text('Hôn nhân')),
                      DataColumn(label: Text(_l10n.department)),
                      DataColumn(label: Text(_l10n.position)),
                      DataColumn(
                          label: const Text('Ngày vào'),
                          onSort: (_, asc) => setState(() {
                                _sortColumn = 'joinDate';
                                _sortAscending = asc;
                              })),
                      const DataColumn(label: Text('Thâm niên')),
                      const DataColumn(label: Text('SĐT')),
                      const DataColumn(label: Text('Trạng thái')),
                    ],
                    rows: items.asMap().entries.map((entry) {
                      final i = entry.key;
                      final e = entry.value;
                      // Calculate seniority
                      String seniority = '';
                      if (e.joinDate != null) {
                        final diff = now.difference(e.joinDate!);
                        final years = diff.inDays ~/ 365;
                        final months = (diff.inDays % 365) ~/ 30;
                        if (years > 0) {
                          seniority = '${years}n ${months}t';
                        } else {
                          seniority = '$months tháng';
                        }
                      }
                      return DataRow(cells: [
                        DataCell(Text('${i + 1}')),
                        DataCell(Text(e.employeeCode)),
                        DataCell(Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundImage:
                                  e.avatarUrl != null && e.avatarUrl!.isNotEmpty
                                      ? NetworkImage(e.avatarUrl!)
                                      : null,
                              onBackgroundImageError: e.avatarUrl != null && e.avatarUrl!.isNotEmpty ? (_, __) {} : null,
                              child: e.avatarUrl == null || e.avatarUrl!.isEmpty
                                  ? Icon(
                                      e.gender?.toLowerCase() == 'female' ||
                                              e.gender?.toLowerCase() == 'nữ'
                                          ? Icons.woman_rounded
                                          : Icons.man_rounded,
                                      size: 16,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Text(e.fullName),
                          ],
                        )),
                        DataCell(Text(e.genderDisplay)),
                        DataCell(Text(e.dateOfBirth != null
                            ? DateFormat('dd/MM/yyyy').format(e.dateOfBirth!)
                            : '')),
                        DataCell(Text(e.hometown ?? '')),
                        DataCell(Text(e.educationLevelDisplay)),
                        DataCell(Text(e.maritalStatusDisplay)),
                        DataCell(Text(e.department ?? '')),
                        DataCell(Text(e.position ?? '')),
                        DataCell(Text(e.joinDate != null
                            ? DateFormat('dd/MM/yyyy').format(e.joinDate!)
                            : '')),
                        DataCell(Text(seniority)),
                        DataCell(Text(e.phone ?? '')),
                        DataCell(_statusChip(e.workStatusDisplay,
                            e.isActive ? Colors.green : Colors.red)),
                      ]);
                    }).toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileHrCardList(List<Employee> items) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final e = items[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundImage: e.avatarUrl != null && e.avatarUrl!.isNotEmpty ? NetworkImage(e.avatarUrl!) : null,
                      onBackgroundImageError: e.avatarUrl != null && e.avatarUrl!.isNotEmpty ? (_, __) {} : null,
                      child: e.avatarUrl == null || e.avatarUrl!.isEmpty
                          ? Icon(e.gender?.toLowerCase() == 'female' || e.gender?.toLowerCase() == 'nữ' ? Icons.woman_rounded : Icons.man_rounded, size: 18)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.fullName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF18181B)), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            '${e.employeeCode} · ${e.department ?? ''} · ${e.position ?? ''}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    _statusChip(e.workStatusDisplay, e.isActive ? Colors.green : Colors.red),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================
  // SHARED WIDGETS
  // ===========================================================
  Widget _chartCard(
      {required String title, required IconData icon, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: Colors.teal.shade600),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF18181B))),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.4))),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }

  void _exportCsv() async {
    final buf = StringBuffer();
    buf.writeln(
        'STT,Mã NV,Họ tên,Giới tính,Ngày sinh,Quê quán,Trình độ,Hôn nhân,Phòng ban,Chức vụ,Ngày vào làm,Thâm niên,Trạng thái,SĐT');
    final now = DateTime.now();
    for (var i = 0; i < _filteredEmployees.length; i++) {
      final e = _filteredEmployees[i];
      String seniority = '';
      if (e.joinDate != null) {
        final years = now.difference(e.joinDate!).inDays ~/ 365;
        final months = (now.difference(e.joinDate!).inDays % 365) ~/ 30;
        seniority = years > 0 ? '$years năm $months tháng' : '$months tháng';
      }
      buf.writeln(
          '${i + 1},${e.employeeCode},"${e.fullName}",${e.genderDisplay},${e.dateOfBirth != null ? DateFormat('dd/MM/yyyy').format(e.dateOfBirth!) : ""},"${e.hometown ?? ""}","${e.educationLevelDisplay}",${e.maritalStatusDisplay},"${e.department ?? ""}","${e.position ?? ""}",${e.joinDate != null ? DateFormat('dd/MM/yyyy').format(e.joinDate!) : ""},"$seniority",${e.workStatusDisplay},${e.phone ?? ""}');
    }
    final bytes = utf8.encode(buf.toString());
    await file_saver.saveFileBytes(bytes, 'bao_cao_nhan_su_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv', 'text/csv;charset=utf-8');
    NotificationOverlayManager().showSuccess(title: 'Xuất báo cáo', message: 'Đã xuất báo cáo CSV');
  }
}
