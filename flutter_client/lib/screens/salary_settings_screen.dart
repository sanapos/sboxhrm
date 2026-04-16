import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'allowance_settings_screen.dart';

class SalarySettingsScreen extends StatefulWidget {
  const SalarySettingsScreen({super.key});

  @override
  State<SalarySettingsScreen> createState() => _SalarySettingsScreenState();
}

class _SalarySettingsScreenState extends State<SalarySettingsScreen> {
  final ApiService _apiService = ApiService();
  final _currencyFormat = NumberFormat('#,###', 'vi_VN');
  List<Map<String, dynamic>> _employeeSalaries = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _salaryProfiles = [];
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _allowances = [];
  Map<String, dynamic> _insuranceSettings = {};
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'all';
  String _filterSalaryType = 'all';
  String _filterInsurance = 'all';
  String _filterAttendance = 'all';
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load all data in parallel
      final results = await Future.wait([
        _apiService.getEmployees(),
        _apiService.getSalaryProfiles(),
        _apiService.getShifts(),
        _apiService.getAllowanceSettings(),
        _apiService.getInsuranceSettings(),
      ]);
      final employees = results[0] as List;
      final profiles = results[1] as List;
      final shifts = results[2] as List;
      final allowances = results[3] as List;
      final insuranceSettings = results[4] as Map<String, dynamic>?;

      // Load all employee salary profiles in parallel
      final profileFutures = employees.map((emp) {
        final id = emp['id']?.toString() ?? '';
        return _apiService.getEmployeeSalaryProfile(id);
      }).toList();
      final allProfiles = await Future.wait(profileFutures);

      // Merge employee data with their salary profiles
      final employeeSalaries = <Map<String, dynamic>>[];

      for (int i = 0; i < employees.length; i++) {
        final employee = Map<String, dynamic>.from(employees[i]);
        final empSalaryProfile = allProfiles[i];

        employeeSalaries.add({
          'id': employee['id'],
          'employeeCode':
              employee['employeeCode'] ?? employee['phoneNumber'] ?? '',
          'fullName':
              '${employee['lastName'] ?? ''} ${employee['firstName'] ?? ''}'
                  .trim(),
          'firstName': employee['firstName'] ?? '',
          'lastName': employee['lastName'] ?? '',
          'department': employee['department'],
          'position': employee['position'],
          'photoUrl': employee['photoUrl'],
          // Salary profile data
          'salaryProfile': empSalaryProfile,
          'benefitId': empSalaryProfile?['benefitId'],
          'benefit': empSalaryProfile?['benefit'],
          'salaryType': empSalaryProfile?['benefit']?['rateType'] ?? 1,
          'baseSalary': empSalaryProfile?['benefit']?['rate'] ?? 0,
          'fixedAllowance':
              empSalaryProfile?['benefit']?['mealAllowance'] ?? 0,
          'dailyAllowance':
              empSalaryProfile?['benefit']?['responsibilityAllowance'] ?? 0,
          'paidDayOff':
              empSalaryProfile?['benefit']?['weeklyOffDays'] ?? 'Sunday',
          'attendanceType': empSalaryProfile?['benefit']?['attendanceMode'] ?? 'checkin',
          'shifts': _parseDescriptionField(empSalaryProfile?['benefit']?['description'], 'shifts'),
          'shiftsPerDay': empSalaryProfile?['benefit']?['shiftsPerDay'] ?? 1,
          'isConfigured': empSalaryProfile != null,
        });
      }

      setState(() {
        _employeeSalaries = employeeSalaries;
        _salaryProfiles =
            profiles.map((p) => Map<String, dynamic>.from(p)).toList();
        _shifts = shifts.map((s) => Map<String, dynamic>.from(s)).toList();
        _allowances =
            allowances.map((a) => Map<String, dynamic>.from(a)).toList();
        _insuranceSettings = insuranceSettings ?? {};
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    var list = _employeeSalaries;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      list = list.where((emp) {
        final name = emp['fullName']?.toString().toLowerCase() ?? '';
        final code = emp['employeeCode']?.toString().toLowerCase() ?? '';
        return name.contains(_searchQuery.toLowerCase()) ||
            code.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Apply type filter
    if (_filterType == 'configured') {
      list = list.where((emp) => emp['isConfigured'] == true).toList();
    } else if (_filterType == 'notConfigured') {
      list = list.where((emp) => emp['isConfigured'] != true).toList();
    }

    // Apply salary type filter
    if (_filterSalaryType != 'all') {
      list = list.where((emp) => emp['salaryType']?.toString() == _filterSalaryType).toList();
    }

    // Apply insurance filter
    if (_filterInsurance != 'all') {
      list = list.where((emp) {
        final benefit = emp['benefit'] as Map<String, dynamic>?;
        return (benefit?['socialInsuranceType'] ?? 0).toString() == _filterInsurance;
      }).toList();
    }

    // Apply attendance filter
    if (_filterAttendance != 'all') {
      list = list.where((emp) => emp['attendanceType']?.toString() == _filterAttendance).toList();
    }

    return list;
  }

  int get _totalEmployees => _employeeSalaries.length;
  int get _configuredCount =>
      _employeeSalaries.where((e) => e['isConfigured'] == true).length;
  int get _notConfiguredCount =>
      _employeeSalaries.where((e) => e['isConfigured'] != true).length;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Modern gradient header
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 12 : 24, isMobile ? 12 : 18, isMobile ? 12 : 24, isMobile ? 10 : 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                if (!isMobile) ...[
                  Material(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.arrow_back, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (!isMobile)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.payments_outlined, size: 22, color: Colors.white),
                  ),
                if (!isMobile) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thiết lập Lương',
                        style: TextStyle(fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (!isMobile)
                        Text(
                          'Quản lý cấu hình lương nhân viên',
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                ),
                if (isMobile)
                  GestureDetector(
                    onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Stack(
                        children: [
                          Icon(
                            _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                            size: 18,
                            color: _showMobileFilters ? Colors.orange : Colors.white,
                          ),
                          if (_searchQuery.isNotEmpty || _filterType != 'all' || _filterSalaryType != 'all' || _filterInsurance != 'all' || _filterAttendance != 'all')
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
                  ),
                if (isMobile)
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.more_vert, size: 18, color: Colors.white),
                    ),
                    onSelected: (v) {
                      if (v == 'add') _showAddEmployeeDialog();
                      if (v == 'allowance') {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AllowanceSettingsScreen()),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      if (Provider.of<PermissionProvider>(context, listen: false).canCreate('SalarySettings'))
                      const PopupMenuItem(value: 'add', child: Row(children: [Icon(Icons.add, size: 18), SizedBox(width: 10), Text('Thêm mới')])),
                      const PopupMenuItem(value: 'allowance', child: Row(children: [Icon(Icons.card_giftcard, size: 18), SizedBox(width: 10), Text('Thêm phụ cấp')])),
                    ],
                  )
                else ...[
                  _buildHeaderActionBtn(Icons.card_giftcard, 'Thêm phụ cấp', () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AllowanceSettingsScreen()),
                    );
                  }),
                  const SizedBox(width: 8),
                  _buildHeaderActionBtn(Icons.file_download_outlined, 'Xuất', () {
                    appNotification.showInfo(
                      title: 'Thông báo',
                      message: 'Chức năng xuất dữ liệu đang được phát triển',
                    );
                  }),
                  const SizedBox(width: 8),
                  if (Provider.of<PermissionProvider>(context, listen: false).canCreate('SalarySettings'))
                  Material(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => _showAddEmployeeDialog(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 20, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Thêm mới', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const LoadingWidget()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
                      children: [
                        _buildStatisticsRow(),
                        const SizedBox(height: 24),
                        if (!Responsive.isMobile(context) || _showMobileFilters)
                        _buildSearchAndFilter(),
                        const SizedBox(height: 24),
                        if (_filteredEmployees.isEmpty)
                          const EmptyState(
                            icon: Icons.person_off,
                            title: 'Không có nhân viên',
                            description: 'Thêm nhân viên để thiết lập lương',
                          )
                        else
                          _buildEmployeeGrid(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionBtn(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildStatisticsRow() {
    final isMobile = Responsive.isMobile(context);
    return Row(
      children: [
        _buildStatCard('Tổng nhân viên', '$_totalEmployees', Icons.groups, const Color(0xFF1E3A5F), isMobile),
        SizedBox(width: isMobile ? 8 : 16),
        _buildStatCard('Đã thiết lập', '$_configuredCount', Icons.check_circle, const Color(0xFF1E3A5F), isMobile),
        SizedBox(width: isMobile ? 8 : 16),
        _buildStatCard('Chưa thiết lập', '$_notConfiguredCount', Icons.warning_amber, const Color(0xFFF59E0B), isMobile),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isMobile) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20, vertical: isMobile ? 10 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isMobile
            ? Column(
                children: [
                  Icon(icon, color: color, size: 20),
                  const SizedBox(height: 6),
                  Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
                  Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 10, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
                ],
              )
            : Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
                      Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    final isMobile = Responsive.isMobile(context);
    final hasFilters = _searchQuery.isNotEmpty || _filterType != 'all' || _filterSalaryType != 'all' || _filterInsurance != 'all' || _filterAttendance != 'all';

    final searchBox = SizedBox(
      height: 40,
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Tìm theo tên hoặc mã nhân viên...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.grey[400], size: 18),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );

    final filterDropdown = _buildFilterDropdown(
      value: _filterType,
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả')),
        DropdownMenuItem(value: 'configured', child: Text('Đã thiết lập')),
        DropdownMenuItem(value: 'notConfigured', child: Text('Chưa thiết lập')),
      ],
      onChanged: (value) => setState(() => _filterType = value ?? 'all'),
    );

    final clearBtn = hasFilters
        ? Material(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => setState(() {
                _searchQuery = '';
                _searchController.clear();
                _filterType = 'all';
                _filterSalaryType = 'all';
                _filterInsurance = 'all';
                _filterAttendance = 'all';
              }),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off, size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 4),
                    Text('Xóa lọc', style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          )
        : null;

    final salaryTypeDropdown = _buildFilterDropdown(
      value: _filterSalaryType,
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả loại lương')),
        DropdownMenuItem(value: '1', child: Text('Lương tháng')),
        DropdownMenuItem(value: '2', child: Text('Lương ngày')),
        DropdownMenuItem(value: '3', child: Text('Lương ca')),
        DropdownMenuItem(value: '0', child: Text('Lương giờ')),
      ],
      onChanged: (value) => setState(() => _filterSalaryType = value ?? 'all'),
    );

    final insuranceDropdown = _buildFilterDropdown(
      value: _filterInsurance,
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả BHXH')),
        DropdownMenuItem(value: '0', child: Text('Chưa đóng BHXH')),
        DropdownMenuItem(value: '1', child: Text('Đóng lương cơ bản')),
        DropdownMenuItem(value: '2', child: Text('LCB và Lương HT')),
        DropdownMenuItem(value: '3', child: Text('Lương tối thiểu vùng')),
        DropdownMenuItem(value: '4', child: Text('Mức lương khác')),
      ],
      onChanged: (value) => setState(() => _filterInsurance = value ?? 'all'),
    );

    final attendanceDropdown = _buildFilterDropdown(
      value: _filterAttendance,
      items: const [
        DropdownMenuItem(value: 'all', child: Text('Tất cả chấm công')),
        DropdownMenuItem(value: 'checkin', child: Text('Chấm vào')),
        DropdownMenuItem(value: 'checkout', child: Text('Chấm ra')),
        DropdownMenuItem(value: 'both', child: Text('Chấm vào & Chấm ra')),
        DropdownMenuItem(value: 'any', child: Text('Chấm bất kỳ')),
        DropdownMenuItem(value: 'none', child: Text('Không chấm công')),
      ],
      onChanged: (value) => setState(() => _filterAttendance = value ?? 'all'),
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 16),
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
                searchBox,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: filterDropdown),
                    if (clearBtn != null) ...[
                      const SizedBox(width: 8),
                      clearBtn,
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                salaryTypeDropdown,
                const SizedBox(height: 8),
                insuranceDropdown,
                const SizedBox(height: 8),
                attendanceDropdown,
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    Expanded(flex: 2, child: searchBox),
                    const SizedBox(width: 12),
                    Expanded(child: filterDropdown),
                    if (clearBtn != null) ...[
                      const SizedBox(width: 12),
                      clearBtn,
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: salaryTypeDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: insuranceDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: attendanceDropdown),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Color(0xFF71717A), size: 18),
          style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
          dropdownColor: Colors.white,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildEmployeeGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 1200
            ? 4
            : constraints.maxWidth > 800
                ? 3
                : constraints.maxWidth > 500
                    ? 2
                    : 1;

        if (crossAxisCount == 1) {
          return Column(
            children: List.generate(_filteredEmployees.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 12, right: 12),
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
                child: _buildEmpDeckItem(_filteredEmployees[i]),
              ),
            )),
          );
        }

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: _filteredEmployees.map((employee) {
            final cardWidth =
                (constraints.maxWidth - (crossAxisCount - 1) * 16) /
                    crossAxisCount;
            return SizedBox(
              width: cardWidth,
              child: _buildEmployeeCard(employee),
            );
          }).toList(),
        );
      },
    );
  }

  String _parseDescriptionField(String? description, String key) {
    if (description == null || description.isEmpty) return '';
    final parts = description.split('|');
    for (final part in parts) {
      final kv = part.split(':');
      if (kv.length >= 2 && kv[0].trim() == key) {
        return kv.sublist(1).join(':').trim();
      }
    }
    return '';
  }

  String _getSalaryTypeName(dynamic type) {
    switch (type?.toString()) {
      case '1': return 'Lương tháng';
      case '2': return 'Lương ngày';
      case '3': return 'Lương ca';
      case '0': return 'Lương giờ';
      default: return 'Lương tháng';
    }
  }

  Widget _buildEmpDeckItem(Map<String, dynamic> employee) {
    final isConfigured = employee['isConfigured'] == true;
    final salaryType = _getSalaryTypeName(employee['salaryType']);
    final baseSalary = (employee['baseSalary'] as num?)?.toDouble() ?? 0;
    final name = employee['fullName'] ?? 'N/A';
    final code = employee['employeeCode'] ?? '';
    final formatter = NumberFormat('#,###', 'vi_VN');

    return InkWell(
      onTap: () => _showViewDialog(employee),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          _buildAvatar(employee),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isConfigured ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(isConfigured ? salaryType : 'Chưa TL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isConfigured ? Colors.green : Colors.orange)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  code,
                  '${formatter.format(baseSalary)} đ',
                ].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> employee) {
    final isConfigured = employee['isConfigured'] == true;
    final salaryType = _getSalaryTypeName(employee['salaryType']);
    final baseSalary = (employee['baseSalary'] as num?)?.toDouble() ?? 0;
    // Calculate allowance totals dynamically from assigned allowances
    final employeeId = employee['id']?.toString() ?? '';
    final fixedAllowance = _calculateEmployeeAllowanceTotal(employeeId, 0);
    final dailyAllowance = _calculateEmployeeAllowanceTotal(employeeId, 1);
    final shifts = employee['shifts']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with avatar and name
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildAvatar(employee),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee['fullName'] ?? 'N/A',
                        style: const TextStyle(
                          color: Color(0xFF18181B),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        employee['employeeCode'] ?? '',
                        style: const TextStyle(
                            color: Color(0xFF1E3A5F), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // Salary type badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isConfigured
                        ? const Color(0xFF0F2340).withValues(alpha: 0.1)
                        : const Color(0xFF71717A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 12,
                        color: isConfigured
                            ? const Color(0xFF0F2340)
                            : const Color(0xFF71717A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConfigured ? salaryType : 'Chưa TL',
                        style: TextStyle(
                          color: isConfigured
                              ? const Color(0xFF0F2340)
                              : const Color(0xFF71717A),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE4E4E7), height: 1),

          // Salary details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildInfoRow(Icons.attach_money, 'Lương cơ bản',
                    _formatCurrency(baseSalary), const Color(0xFF1E3A5F)),
                const SizedBox(height: 8),
                _buildTappableInfoRow(Icons.card_giftcard, 'Phụ cấp cố định',
                    _formatCurrency(fixedAllowance), const Color(0xFFEC4899),
                    () => _showViewAllowanceDetail(
                      allowanceType: 0,
                      employeeId: employeeId,
                      onChanged: () => setState(() {}),
                    )),
                const SizedBox(height: 8),
                _buildTappableInfoRow(Icons.calendar_view_day, 'Phụ cấp theo ngày',
                    _formatCurrency(dailyAllowance), const Color(0xFFF59E0B),
                    () => _showViewAllowanceDetail(
                      allowanceType: 1,
                      employeeId: employeeId,
                      onChanged: () => setState(() {}),
                    )),
                const SizedBox(height: 8),
                _buildInfoRow(
                  Icons.access_time,
                  'Ca làm việc',
                  shifts.isNotEmpty
                      ? (shifts.length > 25
                          ? '${shifts.substring(0, 25)}...'
                          : shifts)
                      : '-',
                  const Color(0xFF71717A),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE4E4E7), height: 1),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: () => _showViewDialog(employee),
                  icon: const Icon(Icons.visibility_outlined,
                      color: Color(0xFF71717A), size: 20),
                  tooltip: 'Xem chi tiết',
                ),
                if (Provider.of<PermissionProvider>(context, listen: false).canEdit('SalarySettings'))
                IconButton(
                  onPressed: () => _showEditDialog(employee),
                  icon: const Icon(Icons.edit_outlined,
                      color: Color(0xFF1E3A5F), size: 20),
                  tooltip: 'Chỉnh sửa',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(Map<String, dynamic> employee) {
    final name = employee['fullName']?.toString() ?? '';
    final gender = employee['gender']?.toString().toLowerCase() ?? '';
    final photoUrl = employee['photoUrl']?.toString();
    final color = _getAvatarColor(name);

    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(_apiService.getFileUrl(photoUrl)),
        onBackgroundImageError: (_, __) {},
        backgroundColor: color,
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: color,
      child: Icon(
        gender == 'female' || gender == 'nữ' ? Icons.woman_rounded : Icons.man_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF1E3A5F),
      const Color(0xFF1E3A5F),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF0F2340),
      const Color(0xFFEC4899),
      const Color(0xFF2D5F8B),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Widget _buildInfoRow(
      IconData icon, String label, String value, Color valueColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFA1A1AA)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildTappableInfoRow(
      IconData icon, String label, String value, Color valueColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFFA1A1AA)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 16, color: valueColor.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return '-';
    return '${amount.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        )} đ';
  }

  void _showViewDialog(Map<String, dynamic> employee) {
    final isMobile = Responsive.isMobile(context);
    final employeeId = employee['id']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setViewState) {
        final formContent = SingleChildScrollView(
          padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailItem('Mã nhân viên', employee['employeeCode'] ?? '-'),
              _buildDetailItem('Loại lương', _getSalaryTypeName(employee['salaryType'])),
              _buildDetailItem('Lương cơ bản', _formatCurrency((employee['baseSalary'] as num?)?.toDouble() ?? 0)),
              _buildTappableDetailItem(
                'Phụ cấp cố định',
                _formatCurrency(_calculateEmployeeAllowanceTotal(employeeId, 0)),
                () => _showViewAllowanceDetail(
                  allowanceType: 0,
                  employeeId: employeeId,
                  onChanged: () => setViewState(() {}),
                ),
              ),
              _buildTappableDetailItem(
                'Phụ cấp theo ngày',
                _formatCurrency(_calculateEmployeeAllowanceTotal(employeeId, 1)),
                () => _showViewAllowanceDetail(
                  allowanceType: 1,
                  employeeId: employeeId,
                  onChanged: () => setViewState(() {}),
                ),
              ),
              ..._buildSalaryTypeDetails(employee),
              const Divider(color: Color(0xFFE4E4E7), height: 24),
              _buildDetailItem('Chấm công', _getAttendanceModeName(employee['attendanceType'])),
              _buildDetailItem('Ca làm việc', (employee['shifts']?.toString().isNotEmpty == true) ? employee['shifts'].toString() : '-'),
              _buildDetailItem('Số ca / 1 công', (employee['shiftsPerDay'] ?? 1).toString()),
              _buildDetailItem('Ngày nghỉ có lương', _getPaidLeaveTypeDisplayName(employee['benefit']?['paidLeaveType'] ?? employee['paidDayOff'])),
            ],
          ),
        );
        final actionButtons = [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng', style: TextStyle(color: Color(0xFF71717A))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditDialog(employee);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Chỉnh sửa'),
          ),
        ];
        if (isMobile) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Scaffold(
                appBar: AppBar(
                  title: Text(employee['fullName'] ?? 'Chi tiết'),
                  leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ),
                body: formContent,
                bottomNavigationBar: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actionButtons,
                  ),
                ),
              ),
            ),
          );
        }
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.person, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  employee['fullName'] ?? 'Chi tiết',
                  style: const TextStyle(
                      color: Color(0xFF18181B),
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: math.min(500, MediaQuery.of(context).size.width - 32),
            child: formContent,
          ),
          actions: actionButtons,
        );
          },
        );
      },
    );
  }

  List<Widget> _buildSalaryTypeDetails(Map<String, dynamic> employee) {
    final benefit = employee['benefit'] as Map<String, dynamic>?;
    final salaryType = (employee['salaryType'] ?? 1).toString();
    final widgets = <Widget>[];
    final socialInsType = (benefit?['socialInsuranceType'] ?? 0).toString();
    final rawInsuranceSalary = (benefit?['insuranceSalary'] as num?)?.toDouble() ?? 0;
    // For type 3 (regional min wage), compute from insurance settings
    final insuranceSalaryVal = socialInsType == '3'
        ? _calculateInsuranceSalary('3', 0, 0, 0)
        : rawInsuranceSalary;

    if (salaryType == '1') {
      // Lương tháng
      widgets.add(_buildDetailItem('Lương hoàn thành CV', _formatCurrency((benefit?['completionSalary'] as num?)?.toDouble() ?? 0)));
      widgets.add(_buildDetailItem('Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem('Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
      widgets.add(_buildDetailItem('Tăng ca ngày nghỉ', _getOvertimeDisplayName((benefit?['holidayOvertimeType'] ?? 1).toString())));
      if ((benefit?['holidayOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem('Tiền công ngày tăng ca', _formatCurrency((benefit?['holidayOvertimeDailyRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem('Tăng ca làm thêm giờ', _getHourlyOvertimeDisplayName((benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem('Tiền giờ tăng ca', _formatCurrency((benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ?? 0)));
      }
    } else if (salaryType == '2') {
      // Lương ngày
      widgets.add(_buildDetailItem('Lương cố định ngày', _formatCurrency((benefit?['dailyFixedRate'] as num?)?.toDouble() ?? 0)));
      widgets.add(_buildDetailItem('Tăng ca ngày nghỉ', _getOvertimeDisplayName((benefit?['holidayOvertimeType'] ?? 1).toString())));
      if ((benefit?['holidayOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem('Tiền công ngày tăng ca', _formatCurrency((benefit?['holidayOvertimeDailyRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem('Tăng ca làm thêm giờ', _getHourlyOvertimeDisplayName((benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem('Tiền giờ tăng ca', _formatCurrency((benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem('Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem('Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
    } else if (salaryType == '3') {
      // Lương ca
      final shiftSalaryType = (benefit?['shiftSalaryType'] ?? 0).toString();
      widgets.add(_buildDetailItem('Kiểu tính lương', shiftSalaryType == '0' ? 'Lương ca cố định' : 'Lương theo ca'));
      if (shiftSalaryType == '0') {
        widgets.add(_buildDetailItem('Tiền lương mỗi ca', _formatCurrency((benefit?['fixedShiftRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem('Tăng ca ngày nghỉ', _getOvertimeDisplayName((benefit?['holidayOvertimeType'] ?? 1).toString())));
      if ((benefit?['holidayOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem('Tiền công ngày tăng ca', _formatCurrency((benefit?['holidayOvertimeDailyRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem('Tăng ca làm thêm giờ', _getHourlyOvertimeDisplayName((benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem('Tiền giờ tăng ca', _formatCurrency((benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem('Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem('Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
    } else if (salaryType == '0') {
      // Lương giờ
      widgets.add(_buildDetailItem('Lương theo giờ', _formatCurrency((benefit?['rate'] as num?)?.toDouble() ?? 0)));
      widgets.add(_buildDetailItem('Tăng ca làm thêm giờ', _getHourlyOvertimeDisplayName((benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem('Tiền giờ tăng ca', _formatCurrency((benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem('Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem('Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
    }

    return widgets;
  }

  String _getAttendanceModeName(dynamic mode) {
    switch (mode?.toString()) {
      case 'checkin': return 'Chấm vào';
      case 'checkout': return 'Chấm ra';
      case 'both': return 'Chấm vào & Chấm ra';
      case 'any': return 'Chấm bất kỳ';
      case 'none': return 'Không chấm công';
      default: return 'Chấm vào';
    }
  }

  String _getOvertimeDisplayName(String type) {
    switch (type) {
      case '0': return 'Cố định ngày';
      case '1': return 'Hệ số tăng ca theo luật';
      default: return 'Hệ số tăng ca theo luật';
    }
  }

  String _getHourlyOvertimeDisplayName(String type) {
    switch (type) {
      case '0': return 'Cố định giờ';
      case '1': return 'Hệ số tăng ca theo luật';
      case '2': return 'Không tính tăng ca';
      default: return 'Hệ số tăng ca theo luật';
    }
  }

  String _getSocialInsuranceName(String type) {
    switch (type) {
      case '0': return 'Chưa đóng BHXH';
      case '1': return 'Đóng lương cơ bản';
      case '2': return 'Lương cơ bản và Lương hoàn thành';
      case '3': return 'Lương tối thiểu vùng';
      case '4': return 'Mức lương khác';
      default: return 'Chưa đóng BHXH';
    }
  }

  Widget _buildInsuranceSalaryDisplay(
    String socialInsuranceType,
    TextEditingController baseSalaryController,
    TextEditingController completionSalaryController,
    TextEditingController insuranceSalaryController,
  ) {
    String label;
    String amount;
    switch (socialInsuranceType) {
      case '1':
        final base = double.tryParse(baseSalaryController.text.replaceAll('.', '')) ?? 0;
        label = 'Mức lương đóng BHXH (Lương CB)';
        amount = _formatNumber(base);
        break;
      case '2':
        final base = double.tryParse(baseSalaryController.text.replaceAll('.', '')) ?? 0;
        final comp = double.tryParse(completionSalaryController.text.replaceAll('.', '')) ?? 0;
        label = 'Mức lương đóng BHXH (CB + HT)';
        amount = _formatNumber(base + comp);
        break;
      case '3':
        final region = (_insuranceSettings['defaultRegion'] as num?)?.toInt() ?? 1;
        double regionSalary;
        String regionName;
        switch (region) {
          case 1:
            regionSalary = (_insuranceSettings['minSalaryRegion1'] as num?)?.toDouble() ?? 4960000;
            regionName = 'Vùng I';
            break;
          case 2:
            regionSalary = (_insuranceSettings['minSalaryRegion2'] as num?)?.toDouble() ?? 4410000;
            regionName = 'Vùng II';
            break;
          case 3:
            regionSalary = (_insuranceSettings['minSalaryRegion3'] as num?)?.toDouble() ?? 3860000;
            regionName = 'Vùng III';
            break;
          case 4:
            regionSalary = (_insuranceSettings['minSalaryRegion4'] as num?)?.toDouble() ?? 3450000;
            regionName = 'Vùng IV';
            break;
          default:
            regionSalary = (_insuranceSettings['minSalaryRegion1'] as num?)?.toDouble() ?? 4960000;
            regionName = 'Vùng I';
        }
        label = 'Mức lương đóng BHXH ($regionName)';
        amount = _formatNumber(regionSalary);
        break;
      case '4':
        final custom = double.tryParse(insuranceSalaryController.text.replaceAll('.', '')) ?? 0;
        label = 'Mức lương đóng BHXH';
        amount = _formatNumber(custom);
        break;
      default:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFF1E3A5F)),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
          const Spacer(),
          Text(amount, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF18181B))),
        ],
      ),
    );
  }

  double _calculateInsuranceSalary(String socialInsType, double baseSalary, double completionSalary, double customAmount) {
    switch (socialInsType) {
      case '1': return baseSalary;
      case '2': return baseSalary + completionSalary;
      case '3':
        final region = (_insuranceSettings['defaultRegion'] as num?)?.toInt() ?? 1;
        switch (region) {
          case 1: return (_insuranceSettings['minSalaryRegion1'] as num?)?.toDouble() ?? 4960000;
          case 2: return (_insuranceSettings['minSalaryRegion2'] as num?)?.toDouble() ?? 4410000;
          case 3: return (_insuranceSettings['minSalaryRegion3'] as num?)?.toDouble() ?? 3860000;
          case 4: return (_insuranceSettings['minSalaryRegion4'] as num?)?.toDouble() ?? 3450000;
          default: return (_insuranceSettings['minSalaryRegion1'] as num?)?.toDouble() ?? 4960000;
        }
      case '4': return customAmount;
      default: return 0;
    }
  }

  String _getPaidLeaveTypeDisplayName(dynamic value) {
    switch (value?.toString()) {
      case 'sunday': return 'Chủ nhật';
      case 'saturday': return 'Thứ bảy';
      case 'sat-sun': return 'Thứ 7 & Chủ nhật';
      case 'sat-afternoon-sun': return 'Chiều thứ 7 & Chủ nhật';
      case 'off-1': return 'Nghỉ 1 ngày/tháng';
      case 'off-2': return 'Nghỉ 2 ngày/tháng';
      case 'off-3': return 'Nghỉ 3 ngày/tháng';
      case 'off-4': return 'Nghỉ 4 ngày/tháng';
      case 'Sunday': return 'Chủ nhật';
      case 'Saturday': return 'Thứ bảy';
      case 'Saturday,Sunday': return 'Thứ 7 & Chủ nhật';
      case 'leave': return 'Theo nghỉ phép';
      default: return value?.toString() ?? 'Chủ nhật';
    }
  }

  Widget _buildTappableDetailItem(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(
                label,
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 14),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1E3A5F),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new, size: 14, color: Color(0xFF1E3A5F)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showViewAllowanceDetail({
    required int allowanceType,
    required String employeeId,
    required VoidCallback onChanged,
  }) {
    final isMobileView = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final assignedAllowances = _allowances.where((a) {
              final type = a['type'] is int ? a['type'] : int.tryParse(a['type']?.toString() ?? '0') ?? 0;
              final isActive = a['isActive'] ?? true;
              return type == allowanceType && isActive && _isAllowanceAssignedToEmployee(a, employeeId);
            }).toList();

            double total = 0;
            for (var allowance in assignedAllowances) {
              total += (allowance['amount'] as num).toDouble();
            }

            final headerRow = Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    allowanceType == 0 ? Icons.lock : Icons.calendar_today,
                    color: const Color(0xFF1E3A5F),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        allowanceType == 0
                            ? 'Chi tiết phụ cấp cố định'
                            : 'Chi tiết phụ cấp theo ngày',
                        style: const TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${assignedAllowances.length} khoản phụ cấp',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!isMobileView)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF71717A)),
                  ),
              ],
            );

            final listContent = assignedAllowances.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'Chưa có phụ cấp ${allowanceType == 0 ? 'cố định' : 'theo ngày'} nào được gán',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: !isMobileView,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: assignedAllowances.length,
                    itemBuilder: (context, index) {
                      final allowance = assignedAllowances[index];
                      final amount = (allowance['amount'] as num).toDouble();
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Color(0xFF1E3A5F),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          allowance['name'] ?? '',
                          style: const TextStyle(
                            color: Color(0xFF18181B),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: allowance['code'] != null && allowance['code'].toString().isNotEmpty
                            ? Text(
                                'Mã: ${allowance['code']}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              )
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_currencyFormat.format(amount)} đ',
                            style: const TextStyle(
                              color: Color(0xFF1E3A5F),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  );

            final totalFooter = Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFA),
                border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tổng cộng:',
                          style: TextStyle(
                            color: Color(0xFF18181B),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_currencyFormat.format(total)} đ',
                          style: const TextStyle(
                            color: Color(0xFF1E3A5F),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AllowanceSettingsScreen()),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Thêm phụ cấp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E3A5F),
                            side: const BorderSide(color: Color(0xFF1E3A5F)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Đóng'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            if (isMobileView) {
              return Dialog(
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(allowanceType == 0 ? 'Phụ cấp cố định' : 'Phụ cấp theo ngày'),
                      leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ),
                    body: Column(
                      children: [
                        Padding(padding: const EdgeInsets.all(16), child: headerRow),
                        Expanded(child: listContent),
                      ],
                    ),
                    bottomNavigationBar: totalFooter,
                  ),
                ),
              );
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              contentPadding: EdgeInsets.zero,
              content: SizedBox(
                width: math.min(500, MediaQuery.of(context).size.width - 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(padding: const EdgeInsets.all(20), child: headerRow),
                    const Divider(height: 1, color: Color(0xFFE4E4E7)),
                    Flexible(child: listContent),
                    totalFooter,
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF71717A), fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  color: Color(0xFF18181B),
                  fontWeight: FontWeight.w500,
                  fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> employee) {
    final nameController =
        TextEditingController(text: employee['fullName'] ?? '');
    final codeController =
        TextEditingController(text: employee['employeeCode'] ?? '');

    final benefit = employee['benefit'] as Map<String, dynamic>? ?? {};

    // Salary type: 0=Hourly, 1=Monthly, 2=Daily, 3=Shift
    String salaryType = (benefit['rateType'] ?? employee['salaryType'] ?? 1).toString();
    if (!['0', '1', '2', '3'].contains(salaryType)) salaryType = '1';

    // Monthly fields
    final baseSalaryController = TextEditingController(
        text: _formatNumber((benefit['rate'] as num?)?.toDouble() ?? (employee['baseSalary'] as num?)?.toDouble() ?? 0));
    final completionSalaryController = TextEditingController(
        text: _formatNumber((benefit['completionSalary'] as num?)?.toDouble() ?? 0));

    // Holiday overtime
    String holidayOvertimeType = (benefit['holidayOvertimeType'] ?? 1).toString();
    final holidayOvertimeDailyRateController = TextEditingController(
        text: _formatNumber((benefit['holidayOvertimeDailyRate'] as num?)?.toDouble() ?? 0));

    // Hourly overtime
    String hourlyOvertimeType = (benefit['hourlyOvertimeType'] ?? 1).toString();
    final hourlyOvertimeFixedRateController = TextEditingController(
        text: _formatNumber((benefit['hourlyOvertimeFixedRate'] as num?)?.toDouble() ?? 0));

    // Social insurance
    String socialInsuranceType = (benefit['socialInsuranceType'] ?? 0).toString();
    // Validate socialInsuranceType for non-Monthly salary types
    if (salaryType != '1' && (socialInsuranceType == '1' || socialInsuranceType == '2')) {
      socialInsuranceType = '0';
    }
    final insuranceSalaryController = TextEditingController(
        text: _formatNumber((benefit['insuranceSalary'] as num?)?.toDouble() ?? 0));

    // Daily fields
    final dailyFixedRateController = TextEditingController(
        text: _formatNumber((benefit['dailyFixedRate'] as num?)?.toDouble() ?? 0));

    // Shift fields
    String shiftSalaryType = (benefit['shiftSalaryType'] ?? 0).toString();
    final fixedShiftRateController = TextEditingController(
        text: _formatNumber((benefit['fixedShiftRate'] as num?)?.toDouble() ?? 0));

    // Hourly fields
    final hourlyRateController = TextEditingController(
        text: _formatNumber((benefit['rate'] as num?)?.toDouble() ?? 0));

    // Common fields
    // Calculate totals from individual allowances assigned to this employee
    final employeeId = employee['id']?.toString() ?? '';
    final calcFixedTotal = _calculateEmployeeAllowanceTotal(employeeId, 0);
    final calcDailyTotal = _calculateEmployeeAllowanceTotal(employeeId, 1);
    // Always use calculated total from assigned allowances (fields are read-only)
    final fixedVal = calcFixedTotal;
    final dailyVal = calcDailyTotal;
    final fixedAllowanceController = TextEditingController(
        text: _formatNumber(fixedVal));
    final dailyAllowanceController = TextEditingController(
        text: _formatNumber(dailyVal));

    String paidLeaveType = benefit['paidLeaveType']?.toString() ?? 'sunday';
    if (!['sunday', 'saturday', 'sat-sun', 'sat-afternoon-sun', 'off-1', 'off-2', 'off-3', 'off-4'].contains(paidLeaveType)) {
      // Map old WeeklyOffDays to new PaidLeaveType
      final oldPaidDayOff = benefit['weeklyOffDays']?.toString() ?? employee['paidDayOff']?.toString() ?? '';
      if (oldPaidDayOff.contains('Saturday') && oldPaidDayOff.contains('Sunday')) {
        paidLeaveType = 'sat-sun';
      } else if (oldPaidDayOff.contains('Saturday')) {
        paidLeaveType = 'saturday';
      } else {
        paidLeaveType = 'sunday';
      }
    }

    String attendanceMode = benefit['attendanceMode']?.toString() ?? 'checkin';
    if (!['none', 'checkin', 'checkout', 'both', 'any'].contains(attendanceMode)) {
      attendanceMode = 'checkin';
    }

    List<String> selectedShifts = [];
    if (employee['shifts'] != null && employee['shifts'].toString().isNotEmpty) {
      selectedShifts = employee['shifts'].toString().split(', ');
    }

    String shiftsPerDay = (benefit['shiftsPerDay'] ?? employee['shiftsPerDay'] ?? 1).toString();
    if (!['1', '2', '3', '4'].contains(shiftsPerDay)) shiftsPerDay = '1';

    final isMobileEdit = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: isMobileEdit ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Employee info (read-only)
                  Row(
                    children: [
                      Expanded(child: _buildReadOnlyField('Tên nhân viên:', nameController.text)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildReadOnlyField('Mã nhân viên:', codeController.text)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // === LOẠI LƯƠNG ===
                  _buildDropdownField(
                    label: 'Loại lương:',
                    value: salaryType,
                    items: const [
                      DropdownMenuItem(value: '1', child: Text('Lương tháng')),
                      DropdownMenuItem(value: '2', child: Text('Lương ngày')),
                      DropdownMenuItem(value: '3', child: Text('Lương ca')),
                      DropdownMenuItem(value: '0', child: Text('Lương giờ')),
                    ],
                    onChanged: (value) => setDialogState(() {
                      final oldType = salaryType;
                      salaryType = value ?? '1';
                      // Reset socialInsuranceType if switching away from Monthly
                      // Monthly supports '0','1','2','3','4' but others only '0','3','4'
                      if (oldType == '1' && salaryType != '1') {
                        if (socialInsuranceType == '1' || socialInsuranceType == '2') {
                          socialInsuranceType = '0';
                        }
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFE4E4E7)),
                  const SizedBox(height: 8),

                  // === DYNAMIC FIELDS BY SALARY TYPE ===

                  // ====== LƯƠNG THÁNG ======
                  if (salaryType == '1') ...[
                    Row(
                      children: [
                        Expanded(child: _buildTextField(label: 'Lương cơ bản:', controller: baseSalaryController, keyboardType: TextInputType.number)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildTextField(label: 'Lương hoàn thành:', controller: completionSalaryController, keyboardType: TextInputType.number)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tăng ca ngày nghỉ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tăng ca ngày nghỉ:',
                            value: holidayOvertimeType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Cố định ngày')),
                              DropdownMenuItem(value: '1', child: Text('Hệ số tăng ca theo luật')),
                            ],
                            onChanged: (value) => setDialogState(() => holidayOvertimeType = value ?? '1'),
                          ),
                        ),
                        if (holidayOvertimeType == '0') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Tiền công ngày tăng ca:', controller: holidayOvertimeDailyRateController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tăng ca làm thêm giờ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tăng ca làm thêm giờ:',
                            value: hourlyOvertimeType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Cố định giờ')),
                              DropdownMenuItem(value: '1', child: Text('Hệ số tăng ca theo luật')),
                              DropdownMenuItem(value: '2', child: Text('Không tính tăng ca')),
                            ],
                            onChanged: (value) => setDialogState(() => hourlyOvertimeType = value ?? '1'),
                          ),
                        ),
                        if (hourlyOvertimeType == '0') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Tiền giờ tăng ca:', controller: hourlyOvertimeFixedRateController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Đóng BHXH
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Đóng bảo hiểm xã hội:',
                            value: socialInsuranceType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Chưa đóng BHXH')),
                              DropdownMenuItem(value: '1', child: Text('Đóng lương cơ bản')),
                              DropdownMenuItem(value: '2', child: Text('Lương cơ bản và Lương hoàn thành')),
                              DropdownMenuItem(value: '3', child: Text('Lương tối thiểu vùng')),
                              DropdownMenuItem(value: '4', child: Text('Mức lương khác')),
                            ],
                            onChanged: (value) => setDialogState(() => socialInsuranceType = value ?? '0'),
                          ),
                        ),
                        if (socialInsuranceType == '4') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Mức lương đóng BHXH:', controller: insuranceSalaryController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    if (socialInsuranceType != '0') ...[
                      const SizedBox(height: 8),
                      _buildInsuranceSalaryDisplay(socialInsuranceType, baseSalaryController, completionSalaryController, insuranceSalaryController),
                    ],
                  ],

                  // ====== LƯƠNG NGÀY ======
                  if (salaryType == '2') ...[
                    _buildTextField(label: 'Lương cố định ngày:', controller: dailyFixedRateController, keyboardType: TextInputType.number),
                    const SizedBox(height: 16),

                    // Tăng ca ngày nghỉ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tăng ca ngày nghỉ:',
                            value: holidayOvertimeType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Cố định ngày')),
                              DropdownMenuItem(value: '1', child: Text('Hệ số tăng ca theo luật')),
                            ],
                            onChanged: (value) => setDialogState(() => holidayOvertimeType = value ?? '1'),
                          ),
                        ),
                        if (holidayOvertimeType == '0') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Tiền công ngày tăng ca:', controller: holidayOvertimeDailyRateController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tăng ca làm thêm giờ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tăng ca làm thêm giờ:',
                            value: hourlyOvertimeType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Cố định giờ')),
                              DropdownMenuItem(value: '1', child: Text('Hệ số tăng ca theo luật')),
                              DropdownMenuItem(value: '2', child: Text('Không tính tăng ca')),
                            ],
                            onChanged: (value) => setDialogState(() => hourlyOvertimeType = value ?? '1'),
                          ),
                        ),
                        if (hourlyOvertimeType == '0') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Tiền giờ tăng ca:', controller: hourlyOvertimeFixedRateController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Đóng BHXH cho lương ngày
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Đóng bảo hiểm xã hội:',
                            value: socialInsuranceType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Chưa đóng BHXH')),
                              DropdownMenuItem(value: '3', child: Text('Lương tối thiểu vùng')),
                              DropdownMenuItem(value: '4', child: Text('Mức lương khác')),
                            ],
                            onChanged: (value) => setDialogState(() => socialInsuranceType = value ?? '0'),
                          ),
                        ),
                        if (socialInsuranceType == '4') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Mức lương đóng BHXH:', controller: insuranceSalaryController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    if (socialInsuranceType != '0') ...[                      const SizedBox(height: 8),
                      _buildInsuranceSalaryDisplay(socialInsuranceType, baseSalaryController, completionSalaryController, insuranceSalaryController),
                    ],
                  ],

                  // ====== LƯƠNG CA ======
                  if (salaryType == '3') ...[
                    _buildDropdownField(
                      label: 'Kiểu tính lương:',
                      value: shiftSalaryType,
                      items: const [
                        DropdownMenuItem(value: '0', child: Text('Lương ca cố định')),
                        DropdownMenuItem(value: '1', child: Text('Lương theo ca')),
                      ],
                      onChanged: (value) => setDialogState(() => shiftSalaryType = value ?? '0'),
                    ),
                    const SizedBox(height: 16),
                    if (shiftSalaryType == '0')
                      _buildTextField(label: 'Tiền lương mỗi ca:', controller: fixedShiftRateController, keyboardType: TextInputType.number),
                    if (shiftSalaryType == '1')
                      _buildShiftSalaryLevelsInfo(),
                    const SizedBox(height: 16),

                    // Tăng ca ngày nghỉ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tăng ca ngày nghỉ:',
                            value: holidayOvertimeType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Cố định ngày')),
                              DropdownMenuItem(value: '1', child: Text('Hệ số tăng ca theo luật')),
                            ],
                            onChanged: (value) => setDialogState(() => holidayOvertimeType = value ?? '1'),
                          ),
                        ),
                        if (holidayOvertimeType == '0') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Tiền công ngày tăng ca:', controller: holidayOvertimeDailyRateController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Tăng ca làm thêm giờ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tăng ca làm thêm giờ:',
                            value: hourlyOvertimeType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Cố định giờ')),
                              DropdownMenuItem(value: '1', child: Text('Hệ số tăng ca theo luật')),
                              DropdownMenuItem(value: '2', child: Text('Không tính tăng ca')),
                            ],
                            onChanged: (value) => setDialogState(() => hourlyOvertimeType = value ?? '1'),
                          ),
                        ),
                        if (hourlyOvertimeType == '0') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Tiền giờ tăng ca:', controller: hourlyOvertimeFixedRateController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Đóng BHXH cho lương ca
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Đóng bảo hiểm xã hội:',
                            value: socialInsuranceType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Chưa đóng BHXH')),
                              DropdownMenuItem(value: '3', child: Text('Lương tối thiểu vùng')),
                              DropdownMenuItem(value: '4', child: Text('Mức lương khác')),
                            ],
                            onChanged: (value) => setDialogState(() => socialInsuranceType = value ?? '0'),
                          ),
                        ),
                        if (socialInsuranceType == '4') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Mức lương đóng BHXH:', controller: insuranceSalaryController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    if (socialInsuranceType != '0') ...[                      const SizedBox(height: 8),
                      _buildInsuranceSalaryDisplay(socialInsuranceType, baseSalaryController, completionSalaryController, insuranceSalaryController),
                    ],
                  ],

                  // ====== LƯƠNG GIỜ ======
                  if (salaryType == '0') ...[
                    _buildTextField(label: 'Lương theo giờ:', controller: hourlyRateController, keyboardType: TextInputType.number),
                    const SizedBox(height: 16),

                    // Tăng ca làm thêm giờ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tăng ca làm thêm giờ:',
                            value: hourlyOvertimeType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Cố định giờ')),
                              DropdownMenuItem(value: '1', child: Text('Hệ số tăng ca theo luật')),
                              DropdownMenuItem(value: '2', child: Text('Không tính tăng ca')),
                            ],
                            onChanged: (value) => setDialogState(() => hourlyOvertimeType = value ?? '1'),
                          ),
                        ),
                        if (hourlyOvertimeType == '0') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Tiền giờ tăng ca:', controller: hourlyOvertimeFixedRateController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Đóng BHXH cho lương giờ
                    Row(
                      children: [
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Đóng bảo hiểm xã hội:',
                            value: socialInsuranceType,
                            items: const [
                              DropdownMenuItem(value: '0', child: Text('Chưa đóng BHXH')),
                              DropdownMenuItem(value: '3', child: Text('Lương tối thiểu vùng')),
                              DropdownMenuItem(value: '4', child: Text('Mức lương khác')),
                            ],
                            onChanged: (value) => setDialogState(() => socialInsuranceType = value ?? '0'),
                          ),
                        ),
                        if (socialInsuranceType == '4') ...[
                          const SizedBox(width: 16),
                          Expanded(child: _buildTextField(label: 'Mức lương đóng BHXH:', controller: insuranceSalaryController, keyboardType: TextInputType.number)),
                        ],
                      ],
                    ),
                    if (socialInsuranceType != '0') ...[                      const SizedBox(height: 8),
                      _buildInsuranceSalaryDisplay(socialInsuranceType, baseSalaryController, completionSalaryController, insuranceSalaryController),
                    ],
                  ],

                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFFE4E4E7)),
                  const SizedBox(height: 8),

                  // === COMMON FIELDS ===

                  // Phụ cấp
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextFieldWithIcon(
                          label: 'Phụ cấp cố định:',
                          controller: fixedAllowanceController,
                          keyboardType: TextInputType.number,
                          readOnly: true,
                          onCalculatePressed: () => _showAllowancePickerDialog(
                            allowanceType: 0,
                            controller: fixedAllowanceController,
                            setDialogState: setDialogState,
                            employeeId: employeeId,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextFieldWithIcon(
                          label: 'Phụ cấp theo ngày:',
                          controller: dailyAllowanceController,
                          keyboardType: TextInputType.number,
                          readOnly: true,
                          onCalculatePressed: () => _showAllowancePickerDialog(
                            allowanceType: 1,
                            controller: dailyAllowanceController,
                            setDialogState: setDialogState,
                            employeeId: employeeId,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Ngày nghỉ có lương & Chấm công
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField(
                          label: 'Ngày nghỉ có lương:',
                          value: paidLeaveType,
                          items: const [
                            DropdownMenuItem(value: 'sunday', child: Text('Chủ nhật')),
                            DropdownMenuItem(value: 'saturday', child: Text('Thứ bảy')),
                            DropdownMenuItem(value: 'sat-sun', child: Text('Thứ bảy & Chủ nhật')),
                            DropdownMenuItem(value: 'sat-afternoon-sun', child: Text('Chiều thứ 7 & Chủ nhật')),
                            DropdownMenuItem(value: 'off-1', child: Text('Nghỉ 1 ngày/tháng')),
                            DropdownMenuItem(value: 'off-2', child: Text('Nghỉ 2 ngày/tháng')),
                            DropdownMenuItem(value: 'off-3', child: Text('Nghỉ 3 ngày/tháng')),
                            DropdownMenuItem(value: 'off-4', child: Text('Nghỉ 4 ngày/tháng')),
                          ],
                          onChanged: (value) => setDialogState(() => paidLeaveType = value ?? 'sunday'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDropdownField(
                          label: 'Chấm công:',
                          value: attendanceMode,
                          items: const [
                            DropdownMenuItem(value: 'none', child: Text('Không chấm công')),
                            DropdownMenuItem(value: 'checkin', child: Text('Chấm vào')),
                            DropdownMenuItem(value: 'checkout', child: Text('Chấm ra')),
                            DropdownMenuItem(value: 'both', child: Text('Chấm vào & Chấm ra')),
                            DropdownMenuItem(value: 'any', child: Text('Chấm bất kỳ trong ca')),
                          ],
                          onChanged: (value) => setDialogState(() => attendanceMode = value ?? 'checkin'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Ca làm việc & Số ca / 1 công
                  Row(
                    children: [
                      Expanded(
                        child: _buildShiftSelector(
                          selectedShifts: selectedShifts,
                          onChanged: (shifts) => setDialogState(() => selectedShifts = shifts),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDropdownField(
                          label: 'Số ca / 1 công:',
                          value: shiftsPerDay,
                          items: const [
                            DropdownMenuItem(value: '1', child: Text('1')),
                            DropdownMenuItem(value: '2', child: Text('2')),
                            DropdownMenuItem(value: '3', child: Text('3')),
                            DropdownMenuItem(value: '4', child: Text('4')),
                          ],
                          onChanged: (value) => setDialogState(() => shiftsPerDay = value ?? '1'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          Future<void> onSave() async {
                Navigator.pop(dialogContext);

                try {
                  // Build benefit data based on salary type
                  final rateType = int.parse(salaryType);
                  double rate = 0;

                  if (rateType == 1) {
                    rate = double.tryParse(baseSalaryController.text.replaceAll('.', '')) ?? 0;
                  } else if (rateType == 0) {
                    rate = double.tryParse(hourlyRateController.text.replaceAll('.', '')) ?? 0;
                  } else if (rateType == 2) {
                    rate = double.tryParse(dailyFixedRateController.text.replaceAll('.', '')) ?? 0;
                  } else if (rateType == 3) {
                    final shiftType = int.parse(shiftSalaryType);
                    if (shiftType == 0) {
                      rate = double.tryParse(fixedShiftRateController.text.replaceAll('.', '')) ?? 0;
                    } else {
                      // Shift template: use 1 as placeholder to pass validation
                      rate = 1;
                    }
                  }

                  final fixedAllowance = double.tryParse(fixedAllowanceController.text.replaceAll('.', '')) ?? 0;
                  final dailyAllowance = double.tryParse(dailyAllowanceController.text.replaceAll('.', '')) ?? 0;

                  // Map paidLeaveType to weeklyOffDays for backward compatibility
                  String weeklyOffDays = 'Sunday';
                  if (paidLeaveType == 'saturday') {
                    weeklyOffDays = 'Saturday';
                  } else if (paidLeaveType == 'sat-sun') {
                    weeklyOffDays = 'Saturday,Sunday';
                  } else if (paidLeaveType == 'sat-afternoon-sun') {
                    weeklyOffDays = 'Saturday,Sunday';
                  }

                  // Build description with shifts info
                  final descParts = <String>[];
                  descParts.add('attendanceType:$attendanceMode');
                  if (selectedShifts.isNotEmpty) {
                    descParts.add('shifts:${selectedShifts.join(', ')}');
                  }
                  descParts.add('shiftsPerDay:$shiftsPerDay');
                  final description = descParts.join('|');

                  final benefitData = {
                    'name': 'Lương ${employee['fullName']}',
                    'description': description,
                    'rateType': rateType,
                    'rate': rate,
                    'currency': 'VND',
                    'mealAllowance': fixedAllowance,
                    'responsibilityAllowance': dailyAllowance,
                    'weeklyOffDays': weeklyOffDays,
                    // New fields
                    'completionSalary': double.tryParse(completionSalaryController.text.replaceAll('.', '')) ?? 0,
                    'holidayOvertimeType': int.parse(holidayOvertimeType),
                    'holidayOvertimeDailyRate': double.tryParse(holidayOvertimeDailyRateController.text.replaceAll('.', '')) ?? 0,
                    'hourlyOvertimeType': int.parse(hourlyOvertimeType),
                    'hourlyOvertimeFixedRate': double.tryParse(hourlyOvertimeFixedRateController.text.replaceAll('.', '')) ?? 0,
                    'socialInsuranceType': int.parse(socialInsuranceType),
                    'insuranceSalary': _calculateInsuranceSalary(
                      socialInsuranceType,
                      rate,
                      double.tryParse(completionSalaryController.text.replaceAll('.', '')) ?? 0,
                      double.tryParse(insuranceSalaryController.text.replaceAll('.', '')) ?? 0,
                    ),
                    'dailyFixedRate': double.tryParse(dailyFixedRateController.text.replaceAll('.', '')) ?? 0,
                    'shiftSalaryType': int.parse(shiftSalaryType),
                    'fixedShiftRate': double.tryParse(fixedShiftRateController.text.replaceAll('.', '')) ?? 0,
                    'shiftsPerDay': int.parse(shiftsPerDay),
                    'attendanceMode': attendanceMode,
                    'paidLeaveType': paidLeaveType,
                    'isActive': true,
                  };

                  Map<String, dynamic> result;
                  String? benefitId = employee['benefitId']?.toString();

                  if (benefitId != null && benefitId.isNotEmpty) {
                    result = await _apiService.updateSalaryProfile(benefitId, benefitData);
                  } else {
                    result = await _apiService.createSalaryProfile(benefitData);
                    if (result['isSuccess'] == true && result['data'] != null) {
                      benefitId = result['data']['id']?.toString();
                    }
                  }

                  if (result['isSuccess'] == true && benefitId != null) {
                    // Only assign if not already assigned to this benefit
                    final existingBenefitId = employee['benefitId']?.toString();
                    if (existingBenefitId != null && existingBenefitId == benefitId) {
                      // Already assigned, just reload
                      appNotification.showSuccess(
                        title: 'Thành công',
                        message: 'Đã cập nhật thiết lập lương',
                      );
                      _loadData();
                    } else {
                    final assignResult = await _apiService.assignSalaryProfile({
                      'employeeId': employee['id'],
                      'benefitId': benefitId,
                      'effectiveDate': DateTime.now().toIso8601String(),
                    });

                    if (assignResult['isSuccess'] == true) {
                      appNotification.showSuccess(
                        title: 'Thành công',
                        message: 'Đã cập nhật thiết lập lương',
                      );
                      _loadData();
                    } else {
                      appNotification.showError(
                        title: 'Lỗi',
                        message: assignResult['message'] ?? 'Không thể gán profile lương',
                      );
                    }
                    }
                  } else {
                    appNotification.showError(
                      title: 'Lỗi',
                      message: result['message'] ?? 'Không thể lưu thiết lập',
                    );
                  }
                } catch (e) {
                  appNotification.showError(
                    title: 'Lỗi',
                    message: 'Có lỗi xảy ra: $e',
                  );
                }
              }
          if (isMobileEdit) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Chỉnh sửa thiết lập lương'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(dialogContext)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy')),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text('Lưu'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.edit, color: Color(0xFF1E3A5F)),
                const SizedBox(width: 8),
                const Text(
                  'Chỉnh sửa thiết lập lương',
                  style: TextStyle(
                      color: Color(0xFF18181B),
                      fontWeight: FontWeight.bold,
                      fontSize: 18),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF71717A)),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(550, MediaQuery.of(context).size.width - 64),
              child: formContent,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Lưu'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildShiftSalaryLevelsInfo() {
    // Show info about configured shift salary levels
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF1E3A5F), size: 16),
              SizedBox(width: 8),
              Text(
                'Mức lương theo ca đã thiết lập',
                style: TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_shifts.isEmpty)
            const Text('Chưa có ca làm việc nào', style: TextStyle(color: Color(0xFF71717A), fontSize: 12))
          else
            ..._shifts.map((shift) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '• ${shift['name']} (${shift['startTime']} - ${shift['endTime']})',
                style: const TextStyle(color: Color(0xFF18181B), fontSize: 12),
              ),
            )),
          const SizedBox(height: 4),
          const Text(
            'Cấu hình mức lương theo ca tại mục Thiết lập ca',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 11, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
              color: Color(0xFF18181B),
              fontSize: 14,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    final isNumeric = keyboardType == TextInputType.number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
          onChanged: isNumeric ? (_) => _formatControllerNumber(controller) : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF1E3A5F), width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFieldWithIcon({
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    VoidCallback? onCalculatePressed,
  }) {
    final isNumeric = keyboardType == TextInputType.number;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                readOnly: readOnly,
                style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                onChanged: (isNumeric && !readOnly) ? (_) => _formatControllerNumber(controller) : null,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: readOnly ? const Color(0xFFEEF2F6) : const Color(0xFFFAFAFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF1E3A5F), width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
              ),
              child: IconButton(
                icon: const Icon(Icons.calculate, color: Color(0xFF1E3A5F)),
                onPressed: onCalculatePressed,
                tooltip: 'Chọn phụ cấp từ danh sách',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Calculate total allowances for an employee by type
  double _calculateEmployeeAllowanceTotal(String employeeId, int allowanceType) {
    double total = 0;
    for (final a in _allowances) {
      final type = a['type'] is int ? a['type'] : int.tryParse(a['type']?.toString() ?? '0') ?? 0;
      final isActive = a['isActive'] ?? true;
      if (type != allowanceType || !isActive) continue;

      if (_isAllowanceAssignedToEmployee(a, employeeId)) {
        total += (a['amount'] as num?)?.toDouble() ?? 0;
      }
    }
    return total;
  }

  // Check if an allowance is assigned to an employee
  bool _isAllowanceAssignedToEmployee(Map<String, dynamic> allowance, String employeeId) {
    final employeeIdsRaw = allowance['employeeIds'];
    if (employeeIdsRaw == null) return true; // null = all employees

    List<String> ids = [];
    if (employeeIdsRaw is List) {
      ids = employeeIdsRaw.map((e) => e.toString()).toList();
    } else if (employeeIdsRaw is String && employeeIdsRaw.isNotEmpty) {
      try {
        final parsed = jsonDecode(employeeIdsRaw);
        if (parsed is List) {
          ids = parsed.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return ids.contains(employeeId);
  }

  // Show dialog to select allowances and calculate total
  void _showAllowancePickerDialog({
    required int allowanceType, // 0 = Fixed, 1 = Daily
    required TextEditingController controller,
    required StateSetter setDialogState,
    String employeeId = '',
  }) {
    final isMobileAllowance = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            // Filter allowances by type and assigned to this employee
            final assignedAllowances = _allowances.where((a) {
              final type = a['type'] is int ? a['type'] : int.tryParse(a['type']?.toString() ?? '0') ?? 0;
              final isActive = a['isActive'] ?? true;
              return type == allowanceType && isActive && _isAllowanceAssignedToEmployee(a, employeeId);
            }).toList();

            // Calculate total
            double total = 0;
            for (var allowance in assignedAllowances) {
              total += (allowance['amount'] as num).toDouble();
            }

            final headerRow = Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    allowanceType == 0 ? Icons.lock : Icons.calendar_today,
                    color: const Color(0xFF1E3A5F),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        allowanceType == 0
                            ? 'Chi tiết phụ cấp cố định'
                            : 'Chi tiết phụ cấp theo ngày',
                        style: const TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${assignedAllowances.length} khoản phụ cấp',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!isMobileAllowance)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF71717A)),
                  ),
              ],
            );
            final listContent = assignedAllowances.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'Chưa có phụ cấp ${allowanceType == 0 ? 'cố định' : 'theo ngày'} nào được gán',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: !isMobileAllowance,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: assignedAllowances.length,
                    itemBuilder: (context, index) {
                      final allowance = assignedAllowances[index];
                      final amount = (allowance['amount'] as num).toDouble();

                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Color(0xFF1E3A5F),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          allowance['name'] ?? '',
                          style: const TextStyle(
                            color: Color(0xFF18181B),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: allowance['code'] != null && allowance['code'].toString().isNotEmpty
                            ? Text(
                                'Mã: ${allowance['code']}',
                                style: TextStyle(color: Colors.grey[600], fontSize: 12),
                              )
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_currencyFormat.format(amount)} đ',
                            style: const TextStyle(
                              color: Color(0xFF1E3A5F),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    },
                  );
            final totalFooter = Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFFAFAFA),
                border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tổng cộng:',
                          style: TextStyle(
                            color: Color(0xFF18181B),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${_currencyFormat.format(total)} đ',
                          style: const TextStyle(
                            color: Color(0xFF1E3A5F),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AllowanceSettingsScreen()),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Thêm phụ cấp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1E3A5F),
                            side: const BorderSide(color: Color(0xFF1E3A5F)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Đóng'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
            if (isMobileAllowance) {
              return Dialog(
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(allowanceType == 0 ? 'Phụ cấp cố định' : 'Phụ cấp theo ngày'),
                      leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ),
                    body: Column(
                      children: [
                        Padding(padding: const EdgeInsets.all(16), child: headerRow),
                        Expanded(child: listContent),
                      ],
                    ),
                    bottomNavigationBar: totalFooter,
                  ),
                ),
              );
            }
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Container(
                width: math.min(450, MediaQuery.of(context).size.width - 32),
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.7),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                      ),
                      child: headerRow,
                    ),
                    Flexible(child: listContent),
                    totalFooter,
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddAllowanceDialog({
    int? allowanceType,
    required String employeeId,
    required VoidCallback onCreated,
  }) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;
    int selectedType = allowanceType ?? 0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setAddState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.add_circle_outline, color: const Color(0xFF1E3A5F), size: 24),
                  const SizedBox(width: 8),
                  Text(
                    allowanceType != null
                        ? (allowanceType == 0 ? 'Thêm phụ cấp cố định' : 'Thêm phụ cấp theo ngày')
                        : 'Thêm phụ cấp mới',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (allowanceType == null) ...[
                      DropdownButtonFormField<int>(
                        value: selectedType,
                        decoration: InputDecoration(
                          labelText: 'Loại phụ cấp *',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Phụ cấp cố định')),
                          DropdownMenuItem(value: 1, child: Text('Phụ cấp theo ngày')),
                          DropdownMenuItem(value: 2, child: Text('Phụ cấp theo giờ')),
                          DropdownMenuItem(value: 3, child: Text('Phụ cấp khác')),
                        ],
                        onChanged: (v) => setAddState(() => selectedType = v ?? 0),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Tên phụ cấp *',
                        hintText: 'VD: Phụ cấp ăn trưa',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên phụ cấp' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: 'Số tiền (VNĐ) *',
                        hintText: 'VD: 500000',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        suffixText: 'đ',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Vui lòng nhập số tiền';
                        final amount = double.tryParse(v.replaceAll('.', '').replaceAll(',', ''));
                        if (amount == null || amount <= 0) return 'Số tiền không hợp lệ';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setAddState(() => isSubmitting = true);
                          try {
                            final amount = double.parse(
                              amountController.text.replaceAll('.', '').replaceAll(',', ''),
                            );
                            final data = {
                              'name': nameController.text.trim(),
                              'type': selectedType,
                              'amount': amount,
                              'currency': 'VND',
                              'isActive': true,
                              'employeeIds': employeeId.isNotEmpty ? [employeeId] : [],
                            };
                            final result = await _apiService.createAllowanceSetting(data);
                            if (result['isSuccess'] == true) {
                              if (context.mounted) Navigator.pop(context);
                              onCreated();
                              appNotification.showSuccess(
                                title: 'Thành công',
                                message: 'Đã thêm phụ cấp "${nameController.text.trim()}"',
                              );
                            } else {
                              setAddState(() => isSubmitting = false);
                              appNotification.showError(
                                title: 'Lỗi',
                                message: result['message'] ?? 'Không thể tạo phụ cấp',
                              );
                            }
                          } catch (e) {
                            setAddState(() => isSubmitting = false);
                            appNotification.showError(
                              title: 'Lỗi',
                              message: 'Có lỗi xảy ra: $e',
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Tạo phụ cấp'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE4E4E7)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down,
                  color: Color(0xFF71717A)),
              style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
              dropdownColor: Colors.white,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShiftSelector({
    required List<String> selectedShifts,
    required void Function(List<String>) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ca làm việc:',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _showShiftPickerDialog(selectedShifts, onChanged),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedShifts.isEmpty
                        ? 'Chọn ca làm việc'
                        : selectedShifts.join(', '),
                    style: TextStyle(
                      color: selectedShifts.isEmpty
                          ? Colors.grey[400]
                          : const Color(0xFF18181B),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down, color: Color(0xFF71717A)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showShiftPickerDialog(
      List<String> currentShifts, void Function(List<String>) onChanged) {
    final selected = List<String>.from(currentShifts);
    final isMobileShift = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final shiftList = _shifts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa có ca làm việc nào',
                      style: TextStyle(color: Color(0xFF71717A))),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _shifts.map((shift) {
                    final shiftName = shift['name']?.toString() ?? '';
                    final isSelected = selected.contains(shiftName);
                    return CheckboxListTile(
                      title: Text(shiftName,
                          style: const TextStyle(color: Color(0xFF18181B))),
                      subtitle: Text(
                        '${shift['startTime'] ?? ''} - ${shift['endTime'] ?? ''}',
                        style: const TextStyle(
                            color: Color(0xFF71717A), fontSize: 12),
                      ),
                      value: isSelected,
                      activeColor: const Color(0xFF1E3A5F),
                      onChanged: (value) {
                        setDialogState(() {
                          if (value == true) {
                            selected.add(shiftName);
                          } else {
                            selected.remove(shiftName);
                          }
                        });
                      },
                    );
                  }).toList(),
                );
          final actionButtons = [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onChanged(selected);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Xác nhận'),
            ),
          ];
          if (isMobileShift) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: const Text('Chọn ca làm việc'),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: shiftList,
                  ),
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actionButtons,
                    ),
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Chọn ca làm việc',
                style: TextStyle(color: Color(0xFF18181B))),
            content: SizedBox(
              width: 300,
              child: shiftList,
            ),
            actions: actionButtons,
          );
        },
      ),
    );
  }

  void _showAddEmployeeDialog() {
    // Redirect to employee screen or show a message
    appNotification.showInfo(
      title: 'Thông báo',
      message: 'Vui lòng thêm nhân viên từ màn hình Quản lý Nhân sự',
    );
  }

  void _formatControllerNumber(TextEditingController controller) {
    final rawText = controller.text.replaceAll('.', '');
    if (rawText.isEmpty) return;
    final number = double.tryParse(rawText);
    if (number == null) return;
    final formatted = _formatNumber(number);
    if (formatted != controller.text) {
      final cursorOffset = controller.selection.baseOffset;
      final oldLength = controller.text.length;
      controller.text = formatted;
      final newLength = formatted.length;
      final newOffset = (cursorOffset + (newLength - oldLength)).clamp(0, newLength);
      controller.selection = TextSelection.collapsed(offset: newOffset);
    }
  }

  String _formatNumber(double number) {
    return number.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
  }
}
