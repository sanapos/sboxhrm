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

class _PayrollReportScreenState extends State<PayrollReportScreen>
    with SingleTickerProviderStateMixin {
  AppLocalizations get _l10n => AppLocalizations.of(context);
  final ApiService _apiService = ApiService();
  final _currFmt = NumberFormat('#,###', 'vi_VN');
  late TabController _tabController;

  bool _isLoading = false;

  List<Employee> _employees = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _salaryProfiles = [];
  List<Map<String, dynamic>> _employeeSalaryData = [];
  List<Map<String, dynamic>> _payslips = [];
  List<Map<String, dynamic>> _yearPayslips = [];

  // Filters
  int _selectedYear = DateTime.now().year;
  int? _selectedMonth;
  String? _selectedDepartment;
  String? _selectedStatus;
  String _searchText = '';
  final _searchCtrl = TextEditingController();
  bool _showMobileFilters = false;

  // Sorting (Payslips tab)
  String _sortColumn = 'netSalary';
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _apiService.getEmployees(pageSize: 500),
        _apiService.getSalaryProfiles(),
        _apiService.getEmployeeSalaryProfiles(),
        _apiService.getStorePayslips(
            year: _selectedYear, month: _selectedMonth),
        _apiService.getStorePayslips(year: _selectedYear),
      ]);

      final empResult = futures[0] as List;
      final empList = empResult
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();
      final profiles = futures[1] as List;
      final empProfiles = futures[2] as List;
      final payslipResp = futures[3] as Map<String, dynamic>;
      final yearResp = futures[4] as Map<String, dynamic>;

      final payslips = <Map<String, dynamic>>[];
      if (payslipResp['isSuccess'] == true && payslipResp['data'] is List) {
        for (final p in (payslipResp['data'] as List)) {
          payslips.add(Map<String, dynamic>.from(p as Map));
        }
      }

      final yearPayslips = <Map<String, dynamic>>[];
      if (yearResp['isSuccess'] == true && yearResp['data'] is List) {
        for (final p in (yearResp['data'] as List)) {
          yearPayslips.add(Map<String, dynamic>.from(p as Map));
        }
      }

      final salaryData = <Map<String, dynamic>>[];
      for (final emp in empList) {
        if (!emp.isActive) continue;
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
        final baseSalary =
            (empProfile['baseSalary'] ?? profile?['baseSalary'] ?? 0)
                .toDouble();
        final allowances = (empProfile['totalAllowances'] ?? 0).toDouble();
        salaryData.add({
          'employeeId': emp.id,
          'employeeCode': emp.employeeCode,
          'fullName': emp.fullName,
          'department': emp.department ?? 'Chưa phân công',
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
          _payslips = payslips;
          _yearPayslips = yearPayslips;
        });
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Lỗi tải dữ liệu: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _deptOf(String? empId) {
    if (empId == null) return 'Chưa phân công';
    for (final e in _employees) {
      if (e.id == empId) return e.department ?? 'Chưa phân công';
    }
    return 'Chưa phân công';
  }

  String _codeOf(String? empId) {
    if (empId == null) return '';
    for (final e in _employees) {
      if (e.id == empId) return e.employeeCode;
    }
    return '';
  }

  List<Map<String, dynamic>> get _filteredPayslips {
    return _payslips.where((p) {
      if (_selectedDepartment != null) {
        final empId = p['employeeUserId']?.toString();
        if (_deptOf(empId) != _selectedDepartment) return false;
      }
      if (_selectedStatus != null) {
        if ((p['statusName'] ?? '').toString() != _selectedStatus) {
          return false;
        }
      }
      if (_searchText.isNotEmpty) {
        final name = (p['employeeName'] ?? '').toString().toLowerCase();
        if (!name.contains(_searchText.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredSalaryData {
    return _employeeSalaryData.where((e) {
      if (_selectedDepartment != null &&
          e['department'] != _selectedDepartment) return false;
      if (_searchText.isNotEmpty) {
        final name = (e['fullName'] ?? '').toString().toLowerCase();
        if (!name.contains(_searchText.toLowerCase())) return false;
      }
      return true;
    }).toList();
  }

  double get _totBase =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['baseSalary']));
  double get _totOvertime =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['overtimePay']));
  double get _totHoliday =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['holidayPay']));
  double get _totNight =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['nightShiftPay']));
  double get _totAllow =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['allowances']));
  double get _totBonus =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['bonus']));
  double get _totSocial =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['socialInsurance']));
  double get _totHealth =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['healthInsurance']));
  double get _totUnemp =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['unemploymentInsurance']));
  double get _totTax =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['tax']));
  double get _totDeduct =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['deductions']));
  double get _totGross =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['grossSalary']));
  double get _totNet =>
      _filteredPayslips.fold(0.0, (s, p) => s + _d(p['netSalary']));
  double get _totInsurance => _totSocial + _totHealth + _totUnemp;

  int get _paidCount => _filteredPayslips
      .where((p) => (p['statusName'] ?? '') == 'Paid')
      .length;
  int get _draftCount => _filteredPayslips
      .where((p) => (p['statusName'] ?? '') == 'Draft')
      .length;

  double get _profileTotBase =>
      _filteredSalaryData.fold(0.0, (s, e) => s + _d(e['baseSalary']));
  double get _profileTotAllow =>
      _filteredSalaryData.fold(0.0, (s, e) => s + _d(e['allowances']));
  double get _profileTotGross =>
      _filteredSalaryData.fold(0.0, (s, e) => s + _d(e['grossSalary']));

  EdgeInsets get _tabPad => Responsive.isMobile(context)
      ? const EdgeInsets.all(12)
      : const EdgeInsets.all(20);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                if (!Responsive.isMobile(context) || _showMobileFilters)
                  _buildFilters(),
                _buildTabBar(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDashboardTab(),
                        _buildTrendTab(),
                        _buildDepartmentTab(),
                        _buildPayslipListTab(),
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
    final title = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.payments, color: Color(0xFF1E3A5F), size: 22),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_l10n.payrollReport,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                _selectedMonth == null
                    ? 'Cả năm $_selectedYear'
                    : 'Tháng ${_selectedMonth.toString().padLeft(2, '0')}/$_selectedYear',
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF71717A)),
              ),
            ],
          ),
        ),
      ],
    );

    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      child: isMobile
          ? Row(children: [
              Expanded(child: title),
              IconButton(
                tooltip: 'Bộ lọc',
                onPressed: () => setState(
                    () => _showMobileFilters = !_showMobileFilters),
                icon: Icon(
                  _showMobileFilters
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  color: _showMobileFilters
                      ? Colors.orange
                      : const Color(0xFF71717A),
                ),
              ),
              IconButton(
                tooltip: 'Xuất CSV',
                onPressed: _exportCsv,
                icon: const Icon(Icons.download, color: Color(0xFF1E3A5F)),
              ),
            ])
          : Row(children: [
              Expanded(child: title),
              ElevatedButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download, size: 18),
                label: const Text('Xuất CSV'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                    foregroundColor: Colors.white),
              ),
            ]),
    );
  }

  Widget _buildFilters() {
    final depts = _employeeSalaryData
        .map((e) => e['department'] as String)
        .toSet()
        .toList()
      ..sort();
    final years = <int>{};
    for (final p in _yearPayslips) {
      final y = p['year'];
      if (y is int) years.add(y);
    }
    years.add(DateTime.now().year);
    years.add(_selectedYear);
    final yearList = years.toList()..sort();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<int>(
              initialValue: _selectedYear,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Năm',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: yearList
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedYear = v);
                  _loadData();
                }
              },
            ),
          ),
          SizedBox(
            width: 140,
            child: DropdownButtonFormField<int?>(
              initialValue: _selectedMonth,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Tháng',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('Cả năm')),
                for (int m = 1; m <= 12; m++)
                  DropdownMenuItem<int?>(
                      value: m,
                      child: Text('Tháng ${m.toString().padLeft(2, '0')}')),
              ],
              onChanged: (v) {
                setState(() => _selectedMonth = v);
                _loadData();
              },
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedDepartment,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Phòng ban',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: [
                const DropdownMenuItem<String>(
                    value: null, child: Text('Tất cả')),
                ...depts.map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(d, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => _selectedDepartment = v),
            ),
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              initialValue: _selectedStatus,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Trạng thái',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              items: const [
                DropdownMenuItem<String>(value: null, child: Text('Tất cả')),
                DropdownMenuItem<String>(
                    value: 'Draft', child: Text('Nháp')),
                DropdownMenuItem<String>(
                    value: 'Approved', child: Text('Đã duyệt')),
                DropdownMenuItem<String>(
                    value: 'Paid', child: Text('Đã thanh toán')),
              ],
              onChanged: (v) => setState(() => _selectedStatus = v),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'Tìm nhân viên',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchText = v),
            ),
          ),
          if (_selectedDepartment != null ||
              _selectedStatus != null ||
              _searchText.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedDepartment = null;
                  _selectedStatus = null;
                  _searchText = '';
                  _searchCtrl.clear();
                });
              },
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Xoá lọc'),
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        return TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1E3A5F),
          unselectedLabelColor: const Color(0xFFA1A1AA),
          indicatorColor: const Color(0xFF1E3A5F),
          indicatorWeight: 3,
          isScrollable: narrow,
          tabAlignment:
              narrow ? TabAlignment.start : TabAlignment.fill,
          labelPadding: narrow
              ? const EdgeInsets.symmetric(horizontal: 16)
              : const EdgeInsets.symmetric(horizontal: 8),
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: const [
            Tab(text: 'Tổng quan', icon: Icon(Icons.dashboard, size: 18)),
            Tab(text: 'Xu hướng', icon: Icon(Icons.show_chart, size: 18)),
            Tab(text: 'Phòng ban', icon: Icon(Icons.business, size: 18)),
            Tab(text: 'Phiếu lương', icon: Icon(Icons.list_alt, size: 18)),
          ],
        );
      }),
    );
  }

  // ================== TAB 1: DASHBOARD ==================
  Widget _buildDashboardTab() {
    final hasPayslips = _filteredPayslips.isNotEmpty;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: _tabPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasPayslips) _buildNoPayslipBanner(),
          _buildSummaryCards(hasPayslips),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildBreakdownChart(hasPayslips)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildDeptBarChart(hasPayslips)),
                ],
              );
            }
            return Column(children: [
              _buildBreakdownChart(hasPayslips),
              const SizedBox(height: 12),
              _buildDeptBarChart(hasPayslips),
            ]);
          }),
          const SizedBox(height: 12),
          _buildTopEarners(hasPayslips),
        ],
      ),
    );
  }

  Widget _buildNoPayslipBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Chưa có phiếu lương trong kỳ này. Hiển thị theo hồ sơ lương cấu hình.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ]),
    );
  }

  Widget _buildSummaryCards(bool hasPayslips) {
    final totBase = hasPayslips ? _totBase : _profileTotBase;
    final totAllow = hasPayslips ? _totAllow : _profileTotAllow;
    final totGross = hasPayslips ? _totGross : _profileTotGross;
    final totNet = hasPayslips ? _totNet : _profileTotGross;
    final count =
        hasPayslips ? _filteredPayslips.length : _filteredSalaryData.length;

    final cards = <_CardData>[
      _CardData('Số NV / phiếu', '$count', Icons.people,
          const Color(0xFF1E3A5F)),
      _CardData('Tổng thực lãnh', _fmtMoney(totNet),
          Icons.account_balance_wallet, const Color(0xFF047857)),
      _CardData('Tổng gộp', _fmtMoney(totGross), Icons.payments,
          const Color(0xFF2D5F8B)),
      _CardData('Lương cơ bản', _fmtMoney(totBase), Icons.account_balance,
          const Color(0xFF0F2340)),
      _CardData('Phụ cấp', _fmtMoney(totAllow), Icons.card_giftcard,
          Colors.teal),
      if (hasPayslips) ...[
        _CardData('Tăng ca', _fmtMoney(_totOvertime + _totHoliday + _totNight),
            Icons.timer, Colors.orange.shade700),
        _CardData(
            'Thưởng', _fmtMoney(_totBonus), Icons.star, Colors.amber.shade800),
        _CardData('BHXH+BHYT+BHTN', _fmtMoney(_totInsurance),
            Icons.health_and_safety, Colors.red.shade600),
        _CardData('Thuế TNCN', _fmtMoney(_totTax), Icons.receipt_long,
            Colors.purple.shade600),
        _CardData('Khấu trừ khác', _fmtMoney(_totDeduct),
            Icons.remove_circle_outline, Colors.red.shade400),
        _CardData('Đã thanh toán', '$_paidCount', Icons.check_circle,
            Colors.green.shade600),
        _CardData('Phiếu nháp', '$_draftCount', Icons.drafts,
            Colors.grey.shade600),
      ],
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      int cols;
      if (w >= 1100) {
        cols = 4;
      } else if (w >= 560) {
        cols = 3;
      } else {
        cols = 2;
      }
      const spacing = 10.0;
      final cardW = (w - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final c in cards) SizedBox(width: cardW, child: _summaryCard(c)),
        ],
      );
    });
  }

  Widget _summaryCard(_CardData d) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: d.color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: d.color.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(d.icon, color: d.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(d.title,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF52525B),
                        fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.value,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: d.color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownChart(bool hasPayslips) {
    if (!hasPayslips) {
      return _chartCard(
          'Cấu trúc lương',
          SizedBox(
            height: 260,
            child: Center(
                child: Text('Chưa có dữ liệu phiếu lương',
                    style: TextStyle(color: Colors.grey.shade600))),
          ));
    }
    final items = <MapEntry<String, double>>[
      MapEntry('Lương cơ bản', _totBase),
      MapEntry('Tăng ca', _totOvertime + _totHoliday + _totNight),
      MapEntry('Phụ cấp', _totAllow),
      MapEntry('Thưởng', _totBonus),
      MapEntry('BH + Thuế', _totInsurance + _totTax),
      MapEntry('Khấu trừ khác', _totDeduct),
    ].where((e) => e.value > 0).toList();

    final colors = [
      const Color(0xFF1E3A5F),
      Colors.orange.shade700,
      Colors.teal,
      Colors.amber.shade700,
      Colors.red.shade400,
      Colors.grey.shade600,
    ];

    final total = items.fold(0.0, (s, e) => s + e.value);
    final sections = items.asMap().entries.map((entry) {
      return PieChartSectionData(
        value: entry.value.value,
        title: '',
        color: colors[entry.key % colors.length],
        radius: 70,
      );
    }).toList();

    return _chartCard(
      'Cấu trúc lương',
      SizedBox(
        height: 260,
        child: Row(
          children: [
            SizedBox(
              width: 150,
              child: PieChart(PieChartData(
                  sections: sections,
                  centerSpaceRadius: 38,
                  sectionsSpace: 2)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ListView(
                children: items.asMap().entries.map((entry) {
                  final pct =
                      total > 0 ? (entry.value.value / total * 100) : 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: colors[entry.key % colors.length],
                              shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(entry.value.key,
                            style: const TextStyle(fontSize: 11.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${pct.toStringAsFixed(1)}%',
                          style: const TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ]),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeptBarChart(bool hasPayslips) {
    final deptTotals = <String, double>{};
    if (hasPayslips) {
      for (final p in _filteredPayslips) {
        final d = _deptOf(p['employeeUserId']?.toString());
        deptTotals[d] = (deptTotals[d] ?? 0) + _d(p['netSalary']);
      }
    } else {
      for (final e in _filteredSalaryData) {
        final d = e['department'] as String;
        deptTotals[d] = (deptTotals[d] ?? 0) + _d(e['grossSalary']);
      }
    }
    final sorted = deptTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(8).toList();

    final colors = [
      const Color(0xFF1E3A5F),
      const Color(0xFF2D5F8B),
      Colors.teal,
      Colors.orange.shade700,
      Colors.purple.shade400,
      Colors.green.shade600,
      Colors.red.shade400,
      Colors.indigo,
    ];

    return _chartCard(
      hasPayslips ? 'Thực lãnh theo phòng ban' : 'Lương gộp theo phòng ban',
      SizedBox(
        height: 260,
        child: top.isEmpty
            ? const Center(child: Text('Không có dữ liệu'))
            : BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: top.first.value * 1.15,
                barGroups: top
                    .asMap()
                    .entries
                    .map((e) => BarChartGroupData(x: e.key, barRods: [
                          BarChartRodData(
                              toY: e.value.value,
                              color: colors[e.key % colors.length],
                              width: 18,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4))),
                        ]))
                    .toList(),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (v, _) {
                            if (v >= 1000000) {
                              return Text(
                                  '${(v / 1000000).toStringAsFixed(0)}M',
                                  style: const TextStyle(fontSize: 9));
                            }
                            if (v >= 1000) {
                              return Text(
                                  '${(v / 1000).toStringAsFixed(0)}K',
                                  style: const TextStyle(fontSize: 9));
                            }
                            return Text('${v.toInt()}',
                                style: const TextStyle(fontSize: 9));
                          })),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 60,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= 0 && idx < top.length) {
                              final n = top[idx].key;
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: RotatedBox(
                                    quarterTurns: -1,
                                    child: Text(
                                        n.length > 10
                                            ? '${n.substring(0, 10)}…'
                                            : n,
                                        style: const TextStyle(fontSize: 9))),
                              );
                            }
                            return const SizedBox();
                          })),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData:
                    const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (g, gi, rod, ri) {
                  return BarTooltipItem(
                      '${top[g.x].key}\n${_currFmt.format(rod.toY)}đ',
                      const TextStyle(color: Colors.white, fontSize: 11));
                })),
              )),
      ),
    );
  }

  Widget _buildTopEarners(bool hasPayslips) {
    List<Map<String, dynamic>> data;
    if (hasPayslips) {
      final agg = <String, Map<String, dynamic>>{};
      for (final p in _filteredPayslips) {
        final id = p['employeeUserId']?.toString() ?? '';
        final prev = agg[id];
        if (prev == null) {
          agg[id] = {'name': p['employeeName'], 'net': _d(p['netSalary'])};
        } else {
          prev['net'] = (prev['net'] as double) + _d(p['netSalary']);
        }
      }
      data = agg.values.toList()
        ..sort((a, b) => (b['net'] as double).compareTo(a['net'] as double));
    } else {
      data = _filteredSalaryData
          .map((e) => {'name': e['fullName'], 'net': _d(e['grossSalary'])})
          .toList()
        ..sort((a, b) => (b['net'] as double).compareTo(a['net'] as double));
    }
    final top = data.take(10).toList();

    return _chartCard(
      'Top 10 lương cao nhất',
      Column(
        children: top.asMap().entries.map((e) {
          final i = e.key;
          final it = e.value;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i < 3
                      ? Colors.amber.shade600
                      : const Color(0xFF1E3A5F).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: i < 3
                            ? Colors.white
                            : const Color(0xFF1E3A5F))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${it['name']}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(_fmtMoney(it['net'] as double),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF047857))),
            ]),
          );
        }).toList(),
      ),
    );
  }

  // ================== TAB 2: TREND ==================
  Widget _buildTrendTab() {
    final monthly = List.generate(
        12,
        (_) => <String, double>{
              'base': 0,
              'ot': 0,
              'allow': 0,
              'bonus': 0,
              'net': 0,
              'gross': 0,
              'count': 0,
            });
    for (final p in _yearPayslips) {
      if (_selectedDepartment != null) {
        if (_deptOf(p['employeeUserId']?.toString()) != _selectedDepartment) {
          continue;
        }
      }
      final m = (p['month'] is int) ? p['month'] as int : 0;
      if (m < 1 || m > 12) continue;
      final idx = m - 1;
      monthly[idx]['base'] = monthly[idx]['base']! + _d(p['baseSalary']);
      monthly[idx]['ot'] = monthly[idx]['ot']! +
          _d(p['overtimePay']) +
          _d(p['holidayPay']) +
          _d(p['nightShiftPay']);
      monthly[idx]['allow'] = monthly[idx]['allow']! + _d(p['allowances']);
      monthly[idx]['bonus'] = monthly[idx]['bonus']! + _d(p['bonus']);
      monthly[idx]['net'] = monthly[idx]['net']! + _d(p['netSalary']);
      monthly[idx]['gross'] = monthly[idx]['gross']! + _d(p['grossSalary']);
      monthly[idx]['count'] = monthly[idx]['count']! + 1;
    }

    final hasData = monthly.any((m) => m['count']! > 0);

    return SingleChildScrollView(
      padding: _tabPad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartCard(
            'Xu hướng lương 12 tháng năm $_selectedYear',
            SizedBox(
              height: 280,
              child: !hasData
                  ? const Center(child: Text('Chưa có dữ liệu'))
                  : LineChart(_buildLineChartData(monthly)),
            ),
          ),
          const SizedBox(height: 12),
          _chartCard('Chi tiết theo tháng', _buildMonthlyTable(monthly)),
        ],
      ),
    );
  }

  LineChartData _buildLineChartData(List<Map<String, double>> monthly) {
    List<FlSpot> spots(String key) =>
        List.generate(12, (i) => FlSpot(i + 1.0, monthly[i][key]!));

    double maxY = 0;
    for (final m in monthly) {
      if (m['net']! > maxY) maxY = m['net']!;
      if (m['gross']! > maxY) maxY = m['gross']!;
    }
    if (maxY == 0) maxY = 1;

    return LineChartData(
      minX: 1,
      maxX: 12,
      minY: 0,
      maxY: maxY * 1.15,
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) {
                  if (v >= 1000000) {
                    return Text('${(v / 1000000).toStringAsFixed(0)}M',
                        style: const TextStyle(fontSize: 9));
                  }
                  if (v >= 1000) {
                    return Text('${(v / 1000).toStringAsFixed(0)}K',
                        style: const TextStyle(fontSize: 9));
                  }
                  return Text('${v.toInt()}',
                      style: const TextStyle(fontSize: 9));
                })),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('T${v.toInt()}',
                          style: const TextStyle(fontSize: 10)),
                    ))),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
            spots: spots('gross'),
            color: const Color(0xFF2D5F8B),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            isCurved: true),
        LineChartBarData(
            spots: spots('net'),
            color: const Color(0xFF047857),
            barWidth: 2.5,
            dotData: const FlDotData(show: true),
            isCurved: true),
      ],
      lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(getTooltipItems: (spots) {
        return spots
            .map((s) => LineTooltipItem(
                'T${s.x.toInt()}: ${_currFmt.format(s.y)}đ',
                TextStyle(color: s.bar.color, fontSize: 11)))
            .toList();
      })),
    );
  }

  Widget _buildMonthlyTable(List<Map<String, double>> monthly) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
        headingTextStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E3A5F)),
        dataTextStyle: const TextStyle(fontSize: 12),
        columns: const [
          DataColumn(label: Text('Tháng')),
          DataColumn(label: Text('Số NV'), numeric: true),
          DataColumn(label: Text('Lương CB'), numeric: true),
          DataColumn(label: Text('Tăng ca'), numeric: true),
          DataColumn(label: Text('Phụ cấp'), numeric: true),
          DataColumn(label: Text('Thưởng'), numeric: true),
          DataColumn(label: Text('Gộp'), numeric: true),
          DataColumn(label: Text('Thực lãnh'), numeric: true),
        ],
        rows: List.generate(12, (i) {
          final m = monthly[i];
          return DataRow(cells: [
            DataCell(Text('T${(i + 1).toString().padLeft(2, '0')}')),
            DataCell(Text('${m['count']!.toInt()}')),
            DataCell(Text(_fmtMoney(m['base']!))),
            DataCell(Text(_fmtMoney(m['ot']!))),
            DataCell(Text(_fmtMoney(m['allow']!))),
            DataCell(Text(_fmtMoney(m['bonus']!))),
            DataCell(Text(_fmtMoney(m['gross']!))),
            DataCell(Text(_fmtMoney(m['net']!),
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF047857)))),
          ]);
        }),
      ),
    );
  }

  // ================== TAB 3: DEPARTMENT ==================
  Widget _buildDepartmentTab() {
    final hasPayslips = _filteredPayslips.isNotEmpty;
    final deptAgg = <String, Map<String, double>>{};

    Map<String, double> blank() => {
          'count': 0,
          'base': 0,
          'ot': 0,
          'allow': 0,
          'bonus': 0,
          'insurance': 0,
          'tax': 0,
          'gross': 0,
          'net': 0,
        };

    if (hasPayslips) {
      for (final p in _filteredPayslips) {
        final d = _deptOf(p['employeeUserId']?.toString());
        final m = deptAgg.putIfAbsent(d, blank);
        m['count'] = m['count']! + 1;
        m['base'] = m['base']! + _d(p['baseSalary']);
        m['ot'] = m['ot']! +
            _d(p['overtimePay']) +
            _d(p['holidayPay']) +
            _d(p['nightShiftPay']);
        m['allow'] = m['allow']! + _d(p['allowances']);
        m['bonus'] = m['bonus']! + _d(p['bonus']);
        m['insurance'] = m['insurance']! +
            _d(p['socialInsurance']) +
            _d(p['healthInsurance']) +
            _d(p['unemploymentInsurance']);
        m['tax'] = m['tax']! + _d(p['tax']);
        m['gross'] = m['gross']! + _d(p['grossSalary']);
        m['net'] = m['net']! + _d(p['netSalary']);
      }
    } else {
      for (final e in _filteredSalaryData) {
        final d = e['department'] as String;
        final m = deptAgg.putIfAbsent(d, blank);
        m['count'] = m['count']! + 1;
        m['base'] = m['base']! + _d(e['baseSalary']);
        m['allow'] = m['allow']! + _d(e['allowances']);
        m['gross'] = m['gross']! + _d(e['grossSalary']);
        m['net'] = m['net']! + _d(e['grossSalary']);
      }
    }

    final sorted = deptAgg.entries.toList()
      ..sort((a, b) => b.value['net']!.compareTo(a.value['net']!));

    return SingleChildScrollView(
      padding: _tabPad,
      child: _chartCard(
        'Tổng hợp theo phòng ban',
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A5F)),
            dataTextStyle: const TextStyle(fontSize: 12),
            columns: const [
              DataColumn(label: Text('Phòng ban')),
              DataColumn(label: Text('Số NV'), numeric: true),
              DataColumn(label: Text('Lương CB'), numeric: true),
              DataColumn(label: Text('Tăng ca'), numeric: true),
              DataColumn(label: Text('Phụ cấp'), numeric: true),
              DataColumn(label: Text('Thưởng'), numeric: true),
              DataColumn(label: Text('BH'), numeric: true),
              DataColumn(label: Text('Thuế'), numeric: true),
              DataColumn(label: Text('Gộp'), numeric: true),
              DataColumn(label: Text('Thực lãnh'), numeric: true),
            ],
            rows: sorted.map((e) {
              final m = e.value;
              return DataRow(cells: [
                DataCell(Text(e.key,
                    style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(Text('${m['count']!.toInt()}')),
                DataCell(Text(_fmtMoney(m['base']!))),
                DataCell(Text(_fmtMoney(m['ot']!))),
                DataCell(Text(_fmtMoney(m['allow']!))),
                DataCell(Text(_fmtMoney(m['bonus']!))),
                DataCell(Text(_fmtMoney(m['insurance']!))),
                DataCell(Text(_fmtMoney(m['tax']!))),
                DataCell(Text(_fmtMoney(m['gross']!))),
                DataCell(Text(_fmtMoney(m['net']!),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF047857)))),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ================== TAB 4: PAYSLIPS ==================
  Widget _buildPayslipListTab() {
    final isMobile = Responsive.isMobile(context);
    final items = [..._filteredPayslips];

    items.sort((a, b) {
      int cmp = 0;
      switch (_sortColumn) {
        case 'name':
          cmp = (a['employeeName'] ?? '')
              .toString()
              .compareTo((b['employeeName'] ?? '').toString());
          break;
        case 'gross':
          cmp = _d(a['grossSalary']).compareTo(_d(b['grossSalary']));
          break;
        case 'netSalary':
        default:
          cmp = _d(a['netSalary']).compareTo(_d(b['netSalary']));
      }
      return _sortAscending ? cmp : -cmp;
    });

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined,
                  size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text('Chưa có phiếu lương trong kỳ này',
                  style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    if (isMobile) {
      return ListView.builder(
        padding: _tabPad,
        itemCount: items.length,
        itemBuilder: (_, i) => _payslipCard(items[i]),
      );
    }

    return SingleChildScrollView(
      padding: _tabPad,
      child: _chartCard(
        'Danh sách phiếu lương (${items.length})',
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
            headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E3A5F)),
            dataTextStyle: const TextStyle(fontSize: 12),
            columns: const [
              DataColumn(label: Text('Kỳ')),
              DataColumn(label: Text('Nhân viên')),
              DataColumn(label: Text('Lương CB'), numeric: true),
              DataColumn(label: Text('Tăng ca'), numeric: true),
              DataColumn(label: Text('Phụ cấp'), numeric: true),
              DataColumn(label: Text('Thưởng'), numeric: true),
              DataColumn(label: Text('Khấu trừ'), numeric: true),
              DataColumn(label: Text('Gộp'), numeric: true),
              DataColumn(label: Text('Thực lãnh'), numeric: true),
              DataColumn(label: Text('Trạng thái')),
            ],
            rows: items.map((p) {
              final ot = _d(p['overtimePay']) +
                  _d(p['holidayPay']) +
                  _d(p['nightShiftPay']);
              final deduct = _d(p['deductions']) +
                  _d(p['socialInsurance']) +
                  _d(p['healthInsurance']) +
                  _d(p['unemploymentInsurance']) +
                  _d(p['tax']);
              return DataRow(cells: [
                DataCell(Text(
                    'T${p['month'].toString().padLeft(2, '0')}/${p['year']}')),
                DataCell(Text('${p['employeeName'] ?? ''}')),
                DataCell(Text(_fmtMoney(_d(p['baseSalary'])))),
                DataCell(Text(_fmtMoney(ot))),
                DataCell(Text(_fmtMoney(_d(p['allowances'])))),
                DataCell(Text(_fmtMoney(_d(p['bonus'])))),
                DataCell(Text(_fmtMoney(deduct))),
                DataCell(Text(_fmtMoney(_d(p['grossSalary'])))),
                DataCell(Text(_fmtMoney(_d(p['netSalary'])),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF047857)))),
                DataCell(_statusChip(p['statusName']?.toString() ?? 'Draft')),
              ]);
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _payslipCard(Map<String, dynamic> p) {
    final ot = _d(p['overtimePay']) +
        _d(p['holidayPay']) +
        _d(p['nightShiftPay']);
    final deduct = _d(p['deductions']) +
        _d(p['socialInsurance']) +
        _d(p['healthInsurance']) +
        _d(p['unemploymentInsurance']) +
        _d(p['tax']);
    final empId = p['employeeUserId']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${p['employeeName'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis),
            ),
            _statusChip(p['statusName']?.toString() ?? 'Draft'),
          ]),
          const SizedBox(height: 2),
          Text(
              '${_codeOf(empId)} · ${_deptOf(empId)} · T${p['month'].toString().padLeft(2, '0')}/${p['year']}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)),
              overflow: TextOverflow.ellipsis),
          const Divider(height: 16),
          _kv('Lương cơ bản', _fmtMoney(_d(p['baseSalary']))),
          _kv('Tăng ca', _fmtMoney(ot)),
          _kv('Phụ cấp', _fmtMoney(_d(p['allowances']))),
          _kv('Thưởng', _fmtMoney(_d(p['bonus']))),
          _kv('Khấu trừ', _fmtMoney(deduct), color: Colors.red.shade600),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF047857).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Thực lãnh',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(_fmtMoney(_d(p['netSalary'])),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF047857))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
          Text(v,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color c;
    String label;
    switch (status) {
      case 'Paid':
        c = Colors.green.shade600;
        label = 'Đã TT';
        break;
      case 'Approved':
        c = Colors.blue.shade600;
        label = 'Đã duyệt';
        break;
      case 'Draft':
      default:
        c = Colors.grey.shade600;
        label = 'Nháp';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.bold, color: c)),
    );
  }

  Widget _chartCard(String title, Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F))),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  String _fmtMoney(double v) {
    if (v >= 1000000000) {
      return '${(v / 1000000000).toStringAsFixed(2)} tỷ';
    }
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}tr';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return _currFmt.format(v);
  }

  void _exportCsv() async {
    final buf = StringBuffer();
    if (_filteredPayslips.isNotEmpty) {
      buf.writeln(
          'STT,Mã NV,Họ tên,Phòng ban,Kỳ,Lương CB,Tăng ca,Phụ cấp,Thưởng,BHXH,BHYT,BHTN,Thuế,Khấu trừ,Gộp,Thực lãnh,Trạng thái');
      for (var i = 0; i < _filteredPayslips.length; i++) {
        final p = _filteredPayslips[i];
        final empId = p['employeeUserId']?.toString();
        buf.writeln(
            '${i + 1},${_codeOf(empId)},"${p['employeeName'] ?? ''}","${_deptOf(empId)}",T${p['month'].toString().padLeft(2, '0')}/${p['year']},${_d(p['baseSalary']).toInt()},${(_d(p['overtimePay']) + _d(p['holidayPay']) + _d(p['nightShiftPay'])).toInt()},${_d(p['allowances']).toInt()},${_d(p['bonus']).toInt()},${_d(p['socialInsurance']).toInt()},${_d(p['healthInsurance']).toInt()},${_d(p['unemploymentInsurance']).toInt()},${_d(p['tax']).toInt()},${_d(p['deductions']).toInt()},${_d(p['grossSalary']).toInt()},${_d(p['netSalary']).toInt()},${p['statusName'] ?? ''}');
      }
    } else {
      buf.writeln(
          'STT,Mã NV,Họ tên,Phòng ban,Chức vụ,Hồ sơ lương,Lương CB,Phụ cấp,Gộp');
      for (var i = 0; i < _filteredSalaryData.length; i++) {
        final e = _filteredSalaryData[i];
        buf.writeln(
            '${i + 1},${e['employeeCode']},"${e['fullName']}","${e['department']}","${e['position']}","${e['profileName']}",${_d(e['baseSalary']).toInt()},${_d(e['allowances']).toInt()},${_d(e['grossSalary']).toInt()}');
      }
    }
    final bytes = utf8.encode(buf.toString());
    final suffix = _selectedMonth == null
        ? '${_selectedYear}_all'
        : '${_selectedYear}_${_selectedMonth!.toString().padLeft(2, '0')}';
    await file_saver.saveFileBytes(
        bytes, 'bao_cao_luong_$suffix.csv', 'text/csv;charset=utf-8');
    if (mounted) {
      NotificationOverlayManager()
          .showSuccess(title: 'Xuất báo cáo', message: 'Đã xuất báo cáo CSV');
    }
  }
}

class _CardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _CardData(this.title, this.value, this.icon, this.color);
}
