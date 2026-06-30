import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'allowance_settings_screen.dart';
import '../utils/allowance_calculator.dart';

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
  List<Map<String, dynamic>> _branches = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'all';
  String _filterSalaryType = 'all';
  String _filterInsurance = 'all';
  String _filterAttendance = 'all';
  String? _filterBranchId;
  final ScrollController _salaryTableHScroll = ScrollController();
  final ScrollController _salaryTableVScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _salaryTableHScroll.dispose();
    _salaryTableVScroll.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load all data in parallel
      final results = await Future.wait([
        _apiService.getEmployeesForSelect(),
        _apiService.getSalaryProfiles(),
        _apiService.getShifts(),
        _apiService.getAllowanceSettings(),
        _apiService.getInsuranceSettings(),
        _apiService.getBranchesForSelect(),
      ]);
      final employees = results[0] as List;
      final profiles = results[1] as List;
      final shifts = results[2] as List;
      final allowances = results[3] as List;
      final insuranceSettings = results[4] as Map<String, dynamic>?;
      final brResult = results[5] as Map<String, dynamic>;
      List<Map<String, dynamic>> branches = [];
      if (brResult['isSuccess'] != false) {
        final brData = brResult['data'];
        if (brData is List) {
          branches =
              brData.map((b) => Map<String, dynamic>.from(b as Map)).toList();
        }
      }

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
          'branchId': employee['branchId']?.toString() ?? '',
          // Salary profile data
          'salaryProfile': empSalaryProfile,
          'benefitId': empSalaryProfile?['benefitId'],
          'benefit': empSalaryProfile?['benefit'],
          'salaryType': _parseSalaryRateType(
              empSalaryProfile?['benefit']?['rateType']),
          'baseSalary': empSalaryProfile?['benefit']?['rate'] ?? 0,
          'fixedAllowance': empSalaryProfile?['benefit']?['mealAllowance'] ?? 0,
          'dailyAllowance':
              empSalaryProfile?['benefit']?['responsibilityAllowance'] ?? 0,
          'paidDayOff':
              empSalaryProfile?['benefit']?['weeklyOffDays'] ?? 'Sunday',
          'attendanceType':
              empSalaryProfile?['benefit']?['attendanceMode'] ?? 'checkin',
          'shifts': _parseDescriptionField(
              empSalaryProfile?['benefit']?['description'], 'shifts'),
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
        _branches = branches;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    var list = _employeeSalaries;

    // Apply branch filter
    if (_filterBranchId != null) {
      list = list
          .where((emp) => emp['branchId']?.toString() == _filterBranchId)
          .toList();
    }

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
      list = list
          .where((emp) =>
              _salaryRateTypeKey(emp['salaryType']) == _filterSalaryType)
          .toList();
    }

    // Apply insurance filter
    if (_filterInsurance != 'all') {
      list = list.where((emp) {
        final benefit = emp['benefit'] as Map<String, dynamic>?;
        return (benefit?['socialInsuranceType'] ?? 0).toString() ==
            _filterInsurance;
      }).toList();
    }

    // Apply attendance filter
    if (_filterAttendance != 'all') {
      list = list
          .where(
              (emp) => emp['attendanceType']?.toString() == _filterAttendance)
          .toList();
    }

    return list;
  }

  int get _totalEmployees => _employeeSalaries.length;
  int get _configuredCount =>
      _employeeSalaries.where((e) => e['isConfigured'] == true).length;
  int get _notConfiguredCount =>
      _employeeSalaries.where((e) => e['isConfigured'] != true).length;

  /// Backend JsonStringEnumConverter: "Hourly"|"Monthly"|"Daily"|"Shift" hoặc int 0..3.
  static int _parseSalaryRateType(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      switch (v) {
        case 'Hourly':
          return 0;
        case 'Monthly':
          return 1;
        case 'Daily':
          return 2;
        case 'Shift':
          return 3;
        default:
          return int.tryParse(v) ?? 1;
      }
    }
    return 1;
  }

  static String _salaryRateTypeKey(dynamic v) =>
      _parseSalaryRateType(v).toString();

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          if (!isMobile)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const AllowanceSettingsScreen()),
                      );
                    },
                    icon: const Icon(Icons.card_giftcard, size: 18),
                    label: const Text('Phụ cấp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HrmPageChrome.primaryNavy,
                      side: const BorderSide(color: HrmPageChrome.primaryNavy),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      appNotification.showInfo(
                        title: 'Thông báo',
                        message: 'Chức năng xuất dữ liệu đang được phát triển',
                      );
                    },
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Xuất'),
                  ),
                  const SizedBox(width: 8),
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canCreate('SalarySettings'))
                    FilledButton.icon(
                      onPressed: () => _showAddEmployeeDialog(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm mới'),
                      style: FilledButton.styleFrom(
                        backgroundColor: HrmPageChrome.primaryNavy,
                      ),
                    ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const LoadingWidget()
                : _buildSalaryMainContent(isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsRow() {
    final chips = [
      _buildSetupStatusChip(
        type: 'all',
        label: 'Tất cả',
        count: _totalEmployees,
        color: const Color(0xFF64748B),
      ),
      _buildSetupStatusChip(
        type: 'configured',
        label: 'Đã thiết lập',
        count: _configuredCount,
        color: HrmPageChrome.primaryNavy,
      ),
      _buildSetupStatusChip(
        type: 'notConfigured',
        label: 'Chưa thiết lập',
        count: _notConfiguredCount,
        color: const Color(0xFFF59E0B),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          chips[i],
        ],
      ]),
    );
  }

  Widget _buildSetupStatusChip({
    required String type,
    required String label,
    required int count,
    required Color color,
  }) {
    final selected = _filterType == type;
    return ChoiceChip(
      label: Text(
        '$label · $count',
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? color : const Color(0xFF475569),
        ),
      ),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => setState(() => _filterType = type),
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: selected
            ? color.withValues(alpha: 0.5)
            : const Color(0xFFE4E4E7),
      ),
      selectedColor: color.withValues(alpha: 0.12),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  int get _activeFilterCount {
    var n = 0;
    if (_filterSalaryType != 'all') n++;
    if (_filterInsurance != 'all') n++;
    if (_filterAttendance != 'all') n++;
    return n;
  }

  void _showMobileFilterSheet() {
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4E4E7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Bộ lọc',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF18181B),
                ),
              ),
              const SizedBox(height: 16),
              _buildFilterDropdown(
                value: _filterSalaryType,
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('Tất cả loại lương')),
                  DropdownMenuItem(value: '1', child: Text('Lương tháng')),
                  DropdownMenuItem(value: '2', child: Text('Lương ngày')),
                  DropdownMenuItem(value: '3', child: Text('Lương ca')),
                  DropdownMenuItem(value: '0', child: Text('Lương giờ')),
                ],
                onChanged: (value) =>
                    setState(() => _filterSalaryType = value ?? 'all'),
              ),
              const SizedBox(height: 10),
              _buildFilterDropdown(
                value: _filterInsurance,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Tất cả BHXH')),
                  DropdownMenuItem(
                      value: '0', child: Text('Chưa đóng BHXH')),
                  DropdownMenuItem(
                      value: '1', child: Text('Đóng lương cơ bản')),
                  DropdownMenuItem(
                      value: '2', child: Text('LCB và Lương HT')),
                  DropdownMenuItem(
                      value: '3', child: Text('Lương tối thiểu vùng')),
                  DropdownMenuItem(
                      value: '4', child: Text('Mức lương khác')),
                ],
                onChanged: (value) =>
                    setState(() => _filterInsurance = value ?? 'all'),
              ),
              const SizedBox(height: 10),
              _buildFilterDropdown(
                value: _filterAttendance,
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('Tất cả chấm công')),
                  DropdownMenuItem(value: 'checkin', child: Text('Chấm vào')),
                  DropdownMenuItem(value: 'checkout', child: Text('Chấm ra')),
                  DropdownMenuItem(
                      value: 'both', child: Text('Chấm vào & Chấm ra')),
                  DropdownMenuItem(value: 'any', child: Text('Chấm bất kỳ')),
                  DropdownMenuItem(
                      value: 'none', child: Text('Không chấm công')),
                ],
                onChanged: (value) =>
                    setState(() => _filterAttendance = value ?? 'all'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_activeFilterCount > 0 ||
                      _searchQuery.isNotEmpty ||
                      _filterBranchId != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                            _filterSalaryType = 'all';
                            _filterInsurance = 'all';
                            _filterAttendance = 'all';
                            _filterBranchId = null;
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text('Xóa lọc'),
                      ),
                    ),
                  if (_activeFilterCount > 0 ||
                      _searchQuery.isNotEmpty ||
                      _filterBranchId != null)
                    const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: HrmPageChrome.primaryNavy,
                      ),
                      child: const Text('Áp dụng'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchAndFilter() {
    final isMobile = Responsive.isMobile(context);
    final hasFilters = _searchQuery.isNotEmpty ||
        _filterSalaryType != 'all' ||
        _filterInsurance != 'all' ||
        _filterAttendance != 'all' ||
        _filterBranchId != null;

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
            borderSide:
                BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );

    final clearBtn = hasFilters
        ? Material(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => setState(() {
                _searchQuery = '';
                _searchController.clear();
                _filterSalaryType = 'all';
                _filterInsurance = 'all';
                _filterAttendance = 'all';
                _filterBranchId = null;
              }),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_alt_off,
                        size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 4),
                    Text('Xóa lọc',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
                            fontWeight: FontWeight.w500)),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildBranchDropdown(),
                const SizedBox(height: 8),
                searchBox,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showMobileFilterSheet,
                        icon: Icon(
                          Icons.tune,
                          size: 18,
                          color: hasFilters
                              ? HrmPageChrome.primaryNavy
                              : const Color(0xFF71717A),
                        ),
                        label: Text(
                          _activeFilterCount > 0
                              ? 'Bộ lọc ($_activeFilterCount)'
                              : 'Bộ lọc',
                          style: TextStyle(
                            fontSize: 13,
                            color: hasFilters
                                ? HrmPageChrome.primaryNavy
                                : const Color(0xFF334155),
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: BorderSide(
                            color: hasFilters
                                ? HrmPageChrome.primaryNavy
                                : const Color(0xFFE4E4E7),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    if (clearBtn != null) ...[
                      const SizedBox(width: 8),
                      clearBtn,
                    ],
                  ],
                ),
              ],
            )
          : Column(
              children: [
                if (_branches.isNotEmpty) ...[
                  _buildBranchDropdown(),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(child: searchBox),
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

  Widget _buildBranchDropdown() {
    final hasBranches = _branches.isNotEmpty;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _filterBranchId != null
            ? HrmPageChrome.primaryNavy.withValues(alpha: 0.06)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _filterBranchId != null
              ? HrmPageChrome.primaryNavy.withValues(alpha: 0.35)
              : const Color(0xFFE4E4E7),
        ),
      ),
      child: Row(children: [
        Icon(
          Icons.account_tree_outlined,
          size: 16,
          color: _filterBranchId != null
              ? HrmPageChrome.primaryNavy
              : const Color(0xFF6B7280),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: hasBranches ? _filterBranchId : null,
              isExpanded: true,
              isDense: true,
              style: TextStyle(
                fontSize: 13,
                color: hasBranches
                    ? const Color(0xFF111827)
                    : const Color(0xFF9CA3AF),
              ),
              icon: const Icon(Icons.keyboard_arrow_down,
                  size: 18, color: Color(0xFF9CA3AF)),
              items: [
                const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Tất cả chi nhánh',
                        style: TextStyle(fontSize: 13))),
                ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b['id']?.toString(),
                    child: Text(b['name']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)))),
              ],
              onChanged:
                  hasBranches ? (v) => setState(() => _filterBranchId = v) : null,
            ),
          ),
        ),
        if (_filterBranchId != null)
          InkWell(
            onTap: () => setState(() => _filterBranchId = null),
            child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 14, color: Color(0xFF9CA3AF))),
          ),
      ]),
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
          icon: const Icon(Icons.keyboard_arrow_down,
              color: Color(0xFF71717A), size: 18),
          style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
          dropdownColor: Colors.white,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSalaryMainContent(bool isMobile) {
    final tableMode = Responsive.preferTableListLayout(context);
    final pad = EdgeInsets.fromLTRB(
      isMobile ? 12 : 24,
      isMobile ? 8 : 24,
      isMobile ? 12 : 24,
      isMobile ? 16 : 24,
    );

    if (tableMode) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildStatisticsRow(),
              SizedBox(height: isMobile ? 12 : 16),
              _buildSearchAndFilter(),
              SizedBox(height: isMobile ? 12 : 16),
              if (_filteredEmployees.isEmpty)
                const Expanded(
                  child: EmptyState(
                    icon: Icons.person_off,
                    title: 'Không có nhân viên',
                    description: 'Thêm nhân viên để thiết lập lương',
                  ),
                )
              else
                Expanded(child: _buildSalaryEmployeesDataTable()),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: pad,
        children: [
          _buildStatisticsRow(),
          SizedBox(height: isMobile ? 12 : 24),
          _buildSearchAndFilter(),
          SizedBox(height: isMobile ? 12 : 24),
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
    );
  }

  static const _salaryTableHeaderStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 13,
    color: Color(0xFF71717A),
  );

  Widget _buildSalaryEmployeesDataTable() {
    final employees = _filteredEmployees;
    DataColumn col(String label, {double? width}) => DataColumn(
          label: SizedBox(
            width: width,
            child: Text(label, style: _salaryTableHeaderStyle),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                controller: _salaryTableVScroll,
                child: SingleChildScrollView(
                  controller: _salaryTableVScroll,
                  primary: false,
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: Scrollbar(
                      thumbVisibility: true,
                      controller: _salaryTableHScroll,
                      child: SingleChildScrollView(
                        controller: _salaryTableHScroll,
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: _salaryEmployeesTableMinWidth,
                          ),
                          child: DataTable(
                    headingRowColor:
                        WidgetStateProperty.all(const Color(0xFFFAFAFA)),
                    dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                        (states) {
                      if (states.contains(WidgetState.hovered)) {
                        return const Color(0xFFF1F5F9);
                      }
                      return null;
                    }),
                    dividerThickness: 0.5,
                    showCheckboxColumn: false,
                    headingRowHeight: 44,
                    dataRowMinHeight: 44,
                    dataRowMaxHeight: 96,
                    columns: [
                      col('Mã NV', width: 88),
                      col('Họ và tên', width: 180),
                      col('Loại lương', width: 110),
                      col('Lương CB', width: 120),
                      col('Phụ cấp cố định', width: 120),
                      col('Ca làm việc', width: _salaryShiftsColumnWidth),
                      col('Số ca/công', width: 88),
                      col('Trạng thái', width: 110),
                      const DataColumn(label: Text('')),
                    ],
                    rows: employees.map((employee) {
                      final isConfigured = employee['isConfigured'] == true;
                      final salaryType =
                          _getSalaryTypeName(employee['salaryType']);
                      final baseSalary =
                          (employee['baseSalary'] as num?)?.toDouble() ?? 0;
                      final employeeId = employee['id']?.toString() ?? '';
                      final fixedAllowance =
                          _calculateEmployeeAllowanceTotal(employeeId, 0,
                              employee: employee);
                      final shifts = employee['shifts']?.toString() ?? '';
                      final shiftsPerDay =
                          (employee['shiftsPerDay'] as num?)?.toInt() ?? 1;
                      final name =
                          employee['fullName']?.toString().trim().isNotEmpty ==
                                  true
                              ? employee['fullName'].toString()
                              : 'N/A';
                      final code = employee['employeeCode']?.toString() ?? '';
                      return DataRow(
                        onSelectChanged: (_) => _showViewDialog(employee),
                        cells: [
                          DataCell(Text(
                            code.isNotEmpty ? code : '—',
                            style: const TextStyle(
                              color: HrmPageChrome.primaryNavy,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          )),
                          DataCell(Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          )),
                          DataCell(Text(
                            isConfigured ? salaryType : '—',
                            style: const TextStyle(fontSize: 12),
                          )),
                          DataCell(Text(
                            baseSalary > 0
                                ? _formatCurrency(baseSalary)
                                : '—',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isConfigured
                                  ? const Color(0xFF059669)
                                  : const Color(0xFF71717A),
                            ),
                          )),
                          DataCell(Text(
                            fixedAllowance > 0
                                ? _formatCurrency(fixedAllowance)
                                : '—',
                            style: const TextStyle(fontSize: 12),
                          )),
                          DataCell(
                            SizedBox(
                              width: _salaryShiftsColumnWidth,
                              child: _buildSalaryShiftsText(shifts),
                            ),
                          ),
                          DataCell(Text(
                            shifts.isNotEmpty ? '$shiftsPerDay' : '—',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          )),
                          DataCell(_buildSalaryStatusChip(
                            isConfigured: isConfigured,
                            label:
                                isConfigured ? 'Đã thiết lập' : 'Chưa thiết lập',
                          )),
                          DataCell(_buildSalaryTableActions(employee)),
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
            ),
            _buildSalaryTableBottomHScroll(),
          ],
        ),
      ),
    );
  }

  Widget _buildSalaryTableBottomHScroll() {
    return Container(
      height: 18,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        controller: _salaryTableHScroll,
        child: SingleChildScrollView(
          controller: _salaryTableHScroll,
          scrollDirection: Axis.horizontal,
          child: const SizedBox(
            width: _salaryEmployeesTableMinWidth,
            height: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildSalaryTableActions(Map<String, dynamic> employee) {
    final canEdit = Provider.of<PermissionProvider>(context, listen: false)
        .canEdit('SalarySettings');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.visibility_outlined,
              size: 20, color: Color(0xFF71717A)),
          tooltip: 'Xem chi tiết',
          onPressed: () => _showViewDialog(employee),
          visualDensity: VisualDensity.compact,
        ),
        if (canEdit)
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 20, color: HrmPageChrome.primaryNavy),
            tooltip: 'Chỉnh sửa',
            onPressed: () => _showEditDialog(employee),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _buildEmployeeGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = Responsive.isMobile(context);
        final crossAxisCount = constraints.maxWidth > 1200
            ? 4
            : constraints.maxWidth > 800
                ? 3
                : constraints.maxWidth > 500
                    ? 2
                    : 1;

        final employees = _filteredEmployees;
        final groupByBranch =
            _branches.isNotEmpty && _filterBranchId == null && !isMobile;

        // ── Grouped mode (desktop / chưa lọc chi nhánh) ─────
        if (groupByBranch) {
          final Map<String, List<Map<String, dynamic>>> groupMap = {};
          for (final emp in employees) {
            final key = (emp['branchId']?.toString() ?? '').isNotEmpty
                ? emp['branchId'].toString()
                : '__none__';
            groupMap.putIfAbsent(key, () => []).add(emp);
          }
          final branchOrder =
              _branches.map((b) => b['id']?.toString() ?? '').toList();
          final sortedKeys = groupMap.keys.toList()
            ..sort((a, b) {
              if (a == '__none__') return 1;
              if (b == '__none__') return -1;
              final ai = branchOrder.indexOf(a);
              final bi = branchOrder.indexOf(b);
              if (ai == -1 && bi == -1) return a.compareTo(b);
              if (ai == -1) return 1;
              if (bi == -1) return -1;
              return ai.compareTo(bi);
            });

          String resolveName(String key) {
            if (key == '__none__') return 'Chưa có chi nhánh';
            return _branches
                    .firstWhere((b) => b['id']?.toString() == key,
                        orElse: () => {'name': key})['name']
                    ?.toString() ??
                key;
          }

          Widget cardSlot(Map<String, dynamic> emp) {
            if (crossAxisCount == 1) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: 8,
                  left: isMobile ? 0 : 12,
                  right: isMobile ? 0 : 12,
                ),
                child: _buildMobileEmployeeListTile(emp),
              );
            }
            final cardWidth =
                (constraints.maxWidth - (crossAxisCount - 1) * 16) /
                    crossAxisCount;
            return SizedBox(
              width: cardWidth,
              child: _buildEmployeeCard(emp),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: sortedKeys.map((key) {
              final emps = groupMap[key]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBranchGroupHeader(resolveName(key), emps.length),
                  crossAxisCount == 1
                      ? Column(children: emps.map(cardSlot).toList())
                      : Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: emps.map(cardSlot).toList(),
                        ),
                  const SizedBox(height: 16),
                ],
              );
            }).toList(),
          );
        }

        // ── Flat mode (mobile hoặc đã lọc chi nhánh) ─────────
        if (crossAxisCount == 1) {
          return Column(
            children: List.generate(
              employees.length,
              (i) => Padding(
                padding: EdgeInsets.only(
                  bottom: 8,
                  left: isMobile ? 0 : 12,
                  right: isMobile ? 0 : 12,
                ),
                child: _buildMobileEmployeeListTile(employees[i]),
              ),
            ),
          );
        }

        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: employees.map((employee) {
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

  Widget _buildBranchGroupHeader(String name, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color:
                      Theme.of(context).primaryColor.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_tree_outlined,
                    size: 14, color: Theme.of(context).primaryColor),
                const SizedBox(width: 6),
                Text(
                  name,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).primaryColor),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                  thickness: 1)),
        ],
      ),
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
    switch (_parseSalaryRateType(type)) {
      case 1:
        return 'Lương tháng';
      case 2:
        return 'Lương ngày';
      case 3:
        return 'Lương ca';
      case 0:
        return 'Lương giờ';
      default:
        return 'Lương tháng';
    }
  }

  Widget _buildMobileEmployeeListTile(Map<String, dynamic> employee) {
    final isConfigured = employee['isConfigured'] == true;
    final salaryType = _getSalaryTypeName(employee['salaryType']);
    final baseSalary = (employee['baseSalary'] as num?)?.toDouble() ?? 0;
    final name = employee['fullName']?.toString().trim().isNotEmpty == true
        ? employee['fullName'].toString()
        : 'N/A';
    final code = employee['employeeCode']?.toString() ?? '';
    final formatter = NumberFormat('#,###', 'vi_VN');
    final salaryLabel =
        baseSalary > 0 ? '${formatter.format(baseSalary)} đ' : '—';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _showViewDialog(employee),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hàng 1: chỉ tên — tối đa không gian hiển thị
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  height: 1.25,
                  color: Color(0xFF0F172A),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Hàng 2: mã NV + loại lương
              Row(
                children: [
                  Expanded(
                    child: Text(
                      code.isNotEmpty ? code : '—',
                      style: const TextStyle(
                        fontSize: 12,
                        color: HrmPageChrome.primaryNavy,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSalaryStatusChip(
                    isConfigured: isConfigured,
                    label: isConfigured ? salaryType : 'Chưa thiết lập',
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Hàng 3: lương cơ bản + mở chi tiết
              Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 15, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Lương CB: $salaryLabel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isConfigured
                            ? const Color(0xFF059669)
                            : const Color(0xFF71717A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 20, color: Color(0xFFCBD5E1)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const double _salaryShiftsColumnWidth = 300;
  static const double _salaryEmployeesTableMinWidth =
      88 + 180 + 110 + 120 + 120 + _salaryShiftsColumnWidth + 88 + 110 + 56;

  String _formatShiftsDisplay(String? raw) {
    final shifts = raw?.toString().trim() ?? '';
    if (shifts.isEmpty) return '—';
    return shifts.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');
  }

  Widget _buildSalaryShiftsText(String? raw, {TextAlign align = TextAlign.start}) {
    final text = _formatShiftsDisplay(raw);
    if (text == '—') {
      return Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)));
    }
    return Tooltip(
      message: text,
      waitDuration: const Duration(milliseconds: 350),
      child: Text(
        text,
        textAlign: align,
        style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF3F3F46)),
        softWrap: true,
      ),
    );
  }

  Widget _buildSalaryShiftsInfoBlock(String? raw) {
    final text = _formatShiftsDisplay(raw);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.access_time, size: 16, color: Color(0xFFA1A1AA)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ca làm việc',
                style: TextStyle(color: Color(0xFF71717A), fontSize: 12),
              ),
              const SizedBox(height: 4),
              _buildSalaryShiftsText(raw),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSalaryStatusChip({
    required bool isConfigured,
    required String label,
  }) {
    final color =
        isConfigured ? HrmPageChrome.primaryNavy : const Color(0xFFF59E0B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildEmployeeCard(Map<String, dynamic> employee) {
    final isConfigured = employee['isConfigured'] == true;
    final salaryType = _getSalaryTypeName(employee['salaryType']);
    final baseSalary = (employee['baseSalary'] as num?)?.toDouble() ?? 0;
    // Calculate allowance totals dynamically from assigned allowances
    final employeeId = employee['id']?.toString() ?? '';
    final fixedAllowance =
        _calculateEmployeeAllowanceTotal(employeeId, 0, employee: employee);
    final dailyAllowance =
        _calculateEmployeeAllowanceTotal(employeeId, 1, employee: employee);
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
                            color: HrmPageChrome.primaryNavy, fontSize: 12),
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
                        ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
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
                            ? HrmPageChrome.primaryNavy
                            : const Color(0xFF71717A),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isConfigured ? salaryType : 'Chưa TL',
                        style: TextStyle(
                          color: isConfigured
                              ? HrmPageChrome.primaryNavy
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
                    _formatCurrency(baseSalary), HrmPageChrome.primaryNavy),
                const SizedBox(height: 8),
                _buildTappableInfoRow(
                    Icons.card_giftcard,
                    'Phụ cấp cố định',
                    _formatCurrency(fixedAllowance),
                    const Color(0xFFEC4899),
                    () => _showViewAllowanceDetail(
                          allowanceType: 0,
                          employeeId: employeeId,
                          employeeCode: employee['employeeCode']?.toString(),
                          onChanged: () => setState(() {}),
                        )),
                const SizedBox(height: 8),
                _buildTappableInfoRow(
                    Icons.calendar_view_day,
                    'Phụ cấp theo ngày',
                    _formatCurrency(dailyAllowance),
                    const Color(0xFFF59E0B),
                    () => _showViewAllowanceDetail(
                          allowanceType: 1,
                          employeeId: employeeId,
                          employeeCode: employee['employeeCode']?.toString(),
                          onChanged: () => setState(() {}),
                        )),
                const SizedBox(height: 8),
                _buildSalaryShiftsInfoBlock(shifts),
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
                if (Provider.of<PermissionProvider>(context, listen: false)
                    .canEdit('SalarySettings'))
                  IconButton(
                    onPressed: () => _showEditDialog(employee),
                    icon: const Icon(Icons.edit_outlined,
                        color: HrmPageChrome.primaryNavy, size: 20),
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
        backgroundImage: _apiService.storeImageProvider(photoUrl),
        onBackgroundImageError: (_, __) {},
        backgroundColor: color,
      );
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: color,
      child: Icon(
        gender == 'female' || gender == 'nữ'
            ? Icons.woman_rounded
            : Icons.man_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }

  Color _getAvatarColor(String name) {
    final colors = [
      HrmPageChrome.primaryNavy,
      HrmPageChrome.primaryNavy,
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      HrmPageChrome.primaryNavy,
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

  Widget _buildTappableInfoRow(IconData icon, String label, String value,
      Color valueColor, VoidCallback onTap) {
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
          Icon(Icons.chevron_right,
              size: 16, color: valueColor.withValues(alpha: 0.5)),
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
            final formBody = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailItem(
                    'Mã nhân viên', employee['employeeCode'] ?? '-'),
                _buildDetailItem(
                    'Loại lương', _getSalaryTypeName(employee['salaryType'])),
                _buildDetailItem(
                    'Lương cơ bản',
                    _formatCurrency(
                        (employee['baseSalary'] as num?)?.toDouble() ?? 0)),
                _buildTappableDetailItem(
                  'Phụ cấp cố định',
                  _formatCurrency(
                      _calculateEmployeeAllowanceTotal(employeeId, 0,
                          employee: employee)),
                  () => _showViewAllowanceDetail(
                    allowanceType: 0,
                    employeeId: employeeId,
                    employeeCode: employee['employeeCode']?.toString(),
                    onChanged: () => setViewState(() {}),
                  ),
                ),
                _buildTappableDetailItem(
                  'Phụ cấp theo ngày',
                  _formatCurrency(
                      _calculateEmployeeAllowanceTotal(employeeId, 1,
                          employee: employee)),
                  () => _showViewAllowanceDetail(
                    allowanceType: 1,
                    employeeId: employeeId,
                    employeeCode: employee['employeeCode']?.toString(),
                    onChanged: () => setViewState(() {}),
                  ),
                ),
                ..._buildSalaryTypeDetails(employee),
                const Divider(color: Color(0xFFE4E4E7), height: 24),
                _buildDetailItem('Chấm công',
                    _getAttendanceModeName(employee['attendanceType'])),
                _buildDetailItem(
                    'Ca làm việc',
                    _formatShiftsDisplay(employee['shifts']?.toString())),
                _buildDetailItem('Số ca / 1 công',
                    (employee['shiftsPerDay'] ?? 1).toString()),
                _buildDetailItem(
                    'Ngày nghỉ có lương',
                    _getPaidLeaveTypeDisplayName(employee['benefit']
                            ?['paidLeaveType'] ??
                        employee['paidDayOff'])),
                _buildDetailItem(
                  'Ngày nghỉ không lương / tháng',
                  (employee['benefit']?['unpaidLeaveDays'] ?? 0).toString(),
                ),
                if (_isMonthlySalaryEmployee(employee)) ...[
                  _buildDetailItem(
                    'Phép năm / năm',
                    _formatLeaveDaysEntitlement(
                        employee['benefit']?['paidLeaveDays']),
                  ),
                  _buildDetailItem(
                    'Phép năm còn lại',
                    _formatLeaveDaysBalance(
                        employee['salaryProfile']?['balancedPaidLeaveDays']),
                  ),
                ],
                if (_parseSalaryRateType(employee['salaryType']) == 3 &&
                    (employee['benefit']?['shiftSalaryType'] ?? 0).toString() ==
                        '1') ...[
                  const SizedBox(height: 12),
                  _buildShiftSalaryLevelsInfo(),
                ],
              ],
            );
            final formContent = isMobile
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16), child: formBody)
                : formBody;
            final canEditSalary =
                Provider.of<PermissionProvider>(context, listen: false)
                    .canEdit('SalarySettings');
            final actionButtons = [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng',
                    style: TextStyle(color: Color(0xFF71717A))),
              ),
              if (canEditSalary)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showEditDialog(employee);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
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
                      leading: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context)),
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
            return ScrollableAlertDialog(
              backgroundColor: Colors.white,
              maxContentWidth: 560,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.person, color: HrmPageChrome.primaryNavy),
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
                width: math.min(560, MediaQuery.of(context).size.width - 32),
                child: formBody,
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
    final salaryTypeKey =
        _salaryRateTypeKey(employee['salaryType'] ?? benefit?['rateType']);
    final widgets = <Widget>[];
    final socialInsType = (benefit?['socialInsuranceType'] ?? 0).toString();
    final rawInsuranceSalary =
        (benefit?['insuranceSalary'] as num?)?.toDouble() ?? 0;
    // For type 3 (regional min wage), compute from insurance settings
    final insuranceSalaryVal = socialInsType == '3'
        ? _calculateInsuranceSalary('3', 0, 0, 0)
        : rawInsuranceSalary;

    if (salaryTypeKey == '1') {
      // Lương tháng
      widgets.add(_buildDetailItem(
          'Lương hoàn thành CV',
          _formatCurrency(
              (benefit?['completionSalary'] as num?)?.toDouble() ?? 0)));
      widgets.add(_buildDetailItem(
          'Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem(
            'Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
      widgets.add(_buildDetailItem(
          'Tăng ca ngày nghỉ',
          _getOvertimeDisplayName(
              (benefit?['holidayOvertimeType'] ?? 1).toString())));
      if ((benefit?['holidayOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem(
            'Tiền công ngày tăng ca',
            _formatCurrency(
                (benefit?['holidayOvertimeDailyRate'] as num?)?.toDouble() ??
                    0)));
      }
      widgets.add(_buildDetailItem(
          'Tăng ca làm thêm giờ',
          _getHourlyOvertimeDisplayName(
              (benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem(
            'Tiền giờ tăng ca',
            _formatCurrency(
                (benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ??
                    0)));
      }
    } else if (salaryTypeKey == '2') {
      // Lương ngày
      widgets.add(_buildDetailItem(
          'Lương cố định ngày',
          _formatCurrency(
              (benefit?['dailyFixedRate'] as num?)?.toDouble() ?? 0)));
      widgets.add(_buildDetailItem(
          'Tăng ca ngày nghỉ',
          _getOvertimeDisplayName(
              (benefit?['holidayOvertimeType'] ?? 1).toString())));
      if ((benefit?['holidayOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem(
            'Tiền công ngày tăng ca',
            _formatCurrency(
                (benefit?['holidayOvertimeDailyRate'] as num?)?.toDouble() ??
                    0)));
      }
      widgets.add(_buildDetailItem(
          'Tăng ca làm thêm giờ',
          _getHourlyOvertimeDisplayName(
              (benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem(
            'Tiền giờ tăng ca',
            _formatCurrency(
                (benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ??
                    0)));
      }
      widgets.add(_buildDetailItem(
          'Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem(
            'Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
    } else if (salaryTypeKey == '3') {
      // Lương ca
      final shiftSalaryType = (benefit?['shiftSalaryType'] ?? 0).toString();
      widgets.add(_buildDetailItem('Kiểu tính lương',
          shiftSalaryType == '0' ? 'Lương ca cố định' : 'Lương theo ca'));
      if (shiftSalaryType == '0') {
        widgets.add(_buildDetailItem(
            'Tiền lương mỗi ca',
            _formatCurrency(
                (benefit?['fixedShiftRate'] as num?)?.toDouble() ?? 0)));
      }
      widgets.add(_buildDetailItem(
          'Tăng ca ngày nghỉ',
          _getOvertimeDisplayName(
              (benefit?['holidayOvertimeType'] ?? 1).toString())));
      if ((benefit?['holidayOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem(
            'Tiền công ngày tăng ca',
            _formatCurrency(
                (benefit?['holidayOvertimeDailyRate'] as num?)?.toDouble() ??
                    0)));
      }
      widgets.add(_buildDetailItem(
          'Tăng ca làm thêm giờ',
          _getHourlyOvertimeDisplayName(
              (benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem(
            'Tiền giờ tăng ca',
            _formatCurrency(
                (benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ??
                    0)));
      }
      widgets.add(_buildDetailItem(
          'Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem(
            'Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
    } else if (salaryTypeKey == '0') {
      // Lương giờ
      widgets.add(_buildDetailItem('Lương theo giờ',
          _formatCurrency((benefit?['rate'] as num?)?.toDouble() ?? 0)));
      widgets.add(_buildDetailItem(
          'Tăng ca làm thêm giờ',
          _getHourlyOvertimeDisplayName(
              (benefit?['hourlyOvertimeType'] ?? 1).toString())));
      if ((benefit?['hourlyOvertimeType'] ?? 1).toString() == '0') {
        widgets.add(_buildDetailItem(
            'Tiền giờ tăng ca',
            _formatCurrency(
                (benefit?['hourlyOvertimeFixedRate'] as num?)?.toDouble() ??
                    0)));
      }
      widgets.add(_buildDetailItem(
          'Đóng BHXH', _getSocialInsuranceName(socialInsType)));
      if (socialInsType != '0') {
        widgets.add(_buildDetailItem(
            'Mức lương đóng BHXH', _formatCurrency(insuranceSalaryVal)));
      }
    }

    return widgets;
  }

  String _getAttendanceModeName(dynamic mode) {
    switch (mode?.toString()) {
      case 'checkin':
        return 'Chấm vào';
      case 'checkout':
        return 'Chấm ra';
      case 'both':
        return 'Chấm vào & Chấm ra';
      case 'any':
        return 'Chấm bất kỳ';
      case 'none':
        return 'Không chấm công';
      default:
        return 'Chấm vào';
    }
  }

  String _getOvertimeDisplayName(String type) {
    switch (type) {
      case '0':
        return 'Cố định ngày';
      case '1':
        return 'Hệ số tăng ca theo luật';
      default:
        return 'Hệ số tăng ca theo luật';
    }
  }

  String _getHourlyOvertimeDisplayName(String type) {
    switch (type) {
      case '0':
        return 'Cố định giờ';
      case '1':
        return 'Hệ số tăng ca theo luật';
      case '2':
        return 'Không tính tăng ca';
      default:
        return 'Hệ số tăng ca theo luật';
    }
  }

  String _getSocialInsuranceName(String type) {
    switch (type) {
      case '0':
        return 'Chưa đóng BHXH';
      case '1':
        return 'Đóng lương cơ bản';
      case '2':
        return 'Lương cơ bản và Lương hoàn thành';
      case '3':
        return 'Lương tối thiểu vùng';
      case '4':
        return 'Mức lương khác';
      default:
        return 'Chưa đóng BHXH';
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
        final base =
            double.tryParse(baseSalaryController.text.replaceAll('.', '')) ?? 0;
        label = 'Mức lương đóng BHXH (Lương CB)';
        amount = _formatNumber(base);
        break;
      case '2':
        final base =
            double.tryParse(baseSalaryController.text.replaceAll('.', '')) ?? 0;
        final comp = double.tryParse(
                completionSalaryController.text.replaceAll('.', '')) ??
            0;
        label = 'Mức lương đóng BHXH (CB + HT)';
        amount = _formatNumber(base + comp);
        break;
      case '3':
        final region =
            (_insuranceSettings['defaultRegion'] as num?)?.toInt() ?? 1;
        double regionSalary;
        String regionName;
        switch (region) {
          case 1:
            regionSalary =
                (_insuranceSettings['minSalaryRegion1'] as num?)?.toDouble() ??
                    4960000;
            regionName = 'Vùng I';
            break;
          case 2:
            regionSalary =
                (_insuranceSettings['minSalaryRegion2'] as num?)?.toDouble() ??
                    4410000;
            regionName = 'Vùng II';
            break;
          case 3:
            regionSalary =
                (_insuranceSettings['minSalaryRegion3'] as num?)?.toDouble() ??
                    3860000;
            regionName = 'Vùng III';
            break;
          case 4:
            regionSalary =
                (_insuranceSettings['minSalaryRegion4'] as num?)?.toDouble() ??
                    3450000;
            regionName = 'Vùng IV';
            break;
          default:
            regionSalary =
                (_insuranceSettings['minSalaryRegion1'] as num?)?.toDouble() ??
                    4960000;
            regionName = 'Vùng I';
        }
        label = 'Mức lương đóng BHXH ($regionName)';
        amount = _formatNumber(regionSalary);
        break;
      case '4':
        final custom = double.tryParse(
                insuranceSalaryController.text.replaceAll('.', '')) ??
            0;
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
        border:
            Border.all(color: HrmPageChrome.primaryNavy.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: HrmPageChrome.primaryNavy),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
          const Spacer(),
          Text(amount,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF18181B))),
        ],
      ),
    );
  }

  double _calculateInsuranceSalary(String socialInsType, double baseSalary,
      double completionSalary, double customAmount) {
    switch (socialInsType) {
      case '1':
        return baseSalary;
      case '2':
        return baseSalary + completionSalary;
      case '3':
        final region =
            (_insuranceSettings['defaultRegion'] as num?)?.toInt() ?? 1;
        switch (region) {
          case 1:
            return (_insuranceSettings['minSalaryRegion1'] as num?)
                    ?.toDouble() ??
                4960000;
          case 2:
            return (_insuranceSettings['minSalaryRegion2'] as num?)
                    ?.toDouble() ??
                4410000;
          case 3:
            return (_insuranceSettings['minSalaryRegion3'] as num?)
                    ?.toDouble() ??
                3860000;
          case 4:
            return (_insuranceSettings['minSalaryRegion4'] as num?)
                    ?.toDouble() ??
                3450000;
          default:
            return (_insuranceSettings['minSalaryRegion1'] as num?)
                    ?.toDouble() ??
                4960000;
        }
      case '4':
        return customAmount;
      default:
        return 0;
    }
  }

  bool _isMonthlySalaryEmployee(Map<String, dynamic> employee) {
    final rateType = employee['benefit']?['rateType'] ??
        employee['salaryType'] ??
        employee['salaryProfile']?['benefit']?['rateType'];
    return _parseSalaryRateType(rateType) == 1;
  }

  String _formatLeaveDaysEntitlement(dynamic value) {
    if (value == null) return '12 ngày (mặc định)';
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    if (n == null) return '—';
    return '${n == n.truncateToDouble() ? n.toInt() : n} ngày';
  }

  String _formatLeaveDaysBalance(dynamic value) {
    if (value == null) return 'Chưa gán hồ sơ lương tháng';
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    if (n == null) return '—';
    return '${n == n.truncateToDouble() ? n.toInt() : n} ngày';
  }

  String _getPaidLeaveTypeDisplayName(dynamic value) {
    switch (value?.toString()) {
      case 'sunday':
        return 'Chủ nhật';
      case 'saturday':
        return 'Thứ bảy';
      case 'sat-sun':
        return 'Thứ 7 & Chủ nhật';
      case 'sat-afternoon-sun':
        return 'Chiều thứ 7 & Chủ nhật';
      case 'off-1':
        return 'Nghỉ 1 ngày/tháng';
      case 'off-2':
        return 'Nghỉ 2 ngày/tháng';
      case 'off-3':
        return 'Nghỉ 3 ngày/tháng';
      case 'off-4':
        return 'Nghỉ 4 ngày/tháng';
      case 'Sunday':
        return 'Chủ nhật';
      case 'Saturday':
        return 'Thứ bảy';
      case 'Saturday,Sunday':
        return 'Thứ 7 & Chủ nhật';
      case 'leave':
        return 'Theo nghỉ phép';
      default:
        return value?.toString() ?? 'Chủ nhật';
    }
  }

  Widget _buildTappableDetailItem(
      String label, String value, VoidCallback onTap) {
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
                      color: HrmPageChrome.primaryNavy,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.open_in_new,
                      size: 14, color: HrmPageChrome.primaryNavy),
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
    String? employeeCode,
  }) {
    final isMobileView = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final assignedAllowances = _allowances.where((a) {
              final type = a['type'] is int
                  ? a['type']
                  : int.tryParse(a['type']?.toString() ?? '0') ?? 0;
              final isActive = a['isActive'] ?? true;
              return type == allowanceType &&
                  isActive &&
                  _isAllowanceAssignedToEmployee(a, employeeId,
                      employeeCode: employeeCode);
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
                    color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    allowanceType == 0 ? Icons.lock : Icons.calendar_today,
                    color: HrmPageChrome.primaryNavy,
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
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.grey[400]),
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
                            color:
                                HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: HrmPageChrome.primaryNavy,
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
                        subtitle: allowance['code'] != null &&
                                allowance['code'].toString().isNotEmpty
                            ? Text(
                                'Mã: ${allowance['code']}',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              )
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_currencyFormat.format(amount)} đ',
                            style: const TextStyle(
                              color: HrmPageChrome.primaryNavy,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              HrmPageChrome.primaryNavy.withValues(alpha: 0.3)),
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
                            color: HrmPageChrome.primaryNavy,
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
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const AllowanceSettingsScreen()),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Thêm phụ cấp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: HrmPageChrome.primaryNavy,
                            side: const BorderSide(color: HrmPageChrome.primaryNavy),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy,
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                      title: Text(allowanceType == 0
                          ? 'Phụ cấp cố định'
                          : 'Phụ cấp theo ngày'),
                      leading: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context)),
                    ),
                    body: Column(
                      children: [
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: headerRow),
                        Expanded(child: listContent),
                      ],
                    ),
                    bottomNavigationBar: totalFooter,
                  ),
                ),
              );
            }

            return ScrollableAlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              contentPadding: EdgeInsets.zero,
              content: SizedBox(
                width: math.min(500, MediaQuery.of(context).size.width - 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(20), child: headerRow),
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
                  fontSize: 14,
                  height: 1.4),
              softWrap: true,
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
    String salaryType = _salaryRateTypeKey(
        benefit['rateType'] ?? employee['salaryType']);

    // Monthly fields
    final baseSalaryController = TextEditingController(
        text: _formatNumber((benefit['rate'] as num?)?.toDouble() ??
            (employee['baseSalary'] as num?)?.toDouble() ??
            0));
    final completionSalaryController = TextEditingController(
        text: _formatNumber(
            (benefit['completionSalary'] as num?)?.toDouble() ?? 0));

    // Holiday overtime
    String holidayOvertimeType =
        (benefit['holidayOvertimeType'] ?? 1).toString();
    final holidayOvertimeDailyRateController = TextEditingController(
        text: _formatNumber(
            (benefit['holidayOvertimeDailyRate'] as num?)?.toDouble() ?? 0));

    // Hourly overtime
    String hourlyOvertimeType = (benefit['hourlyOvertimeType'] ?? 1).toString();
    final hourlyOvertimeFixedRateController = TextEditingController(
        text: _formatNumber(
            (benefit['hourlyOvertimeFixedRate'] as num?)?.toDouble() ?? 0));

    // Social insurance
    String socialInsuranceType =
        (benefit['socialInsuranceType'] ?? 0).toString();
    // Validate socialInsuranceType for non-Monthly salary types
    if (salaryType != '1' &&
        (socialInsuranceType == '1' || socialInsuranceType == '2')) {
      socialInsuranceType = '0';
    }
    final insuranceSalaryController = TextEditingController(
        text: _formatNumber(
            (benefit['insuranceSalary'] as num?)?.toDouble() ?? 0));

    // Daily fields
    final dailyFixedRateController = TextEditingController(
        text: _formatNumber(
            (benefit['dailyFixedRate'] as num?)?.toDouble() ?? 0));

    // Shift fields
    String shiftSalaryType = (benefit['shiftSalaryType'] ?? 0).toString();
    final fixedShiftRateController = TextEditingController(
        text: _formatNumber(
            (benefit['fixedShiftRate'] as num?)?.toDouble() ?? 0));

    // Hourly fields
    final hourlyRateController = TextEditingController(
        text: _formatNumber((benefit['rate'] as num?)?.toDouble() ?? 0));

    // Common fields
    // Calculate totals from individual allowances assigned to this employee
    final employeeId = employee['id']?.toString() ?? '';
    final calcFixedTotal =
        _calculateEmployeeAllowanceTotal(employeeId, 0, employee: employee);
    final calcDailyTotal =
        _calculateEmployeeAllowanceTotal(employeeId, 1, employee: employee);
    // Always use calculated total from assigned allowances (fields are read-only)
    final fixedVal = calcFixedTotal;
    final dailyVal = calcDailyTotal;
    final fixedAllowanceController =
        TextEditingController(text: _formatNumber(fixedVal));
    final dailyAllowanceController =
        TextEditingController(text: _formatNumber(dailyVal));

    final paidLeaveDaysController = TextEditingController(
      text: benefit['paidLeaveDays']?.toString() ??
          (_parseSalaryRateType(
                      benefit['rateType'] ?? employee['salaryType']) ==
                  1
              ? '12'
              : '0'),
    );
    final unpaidLeaveDaysController = TextEditingController(
      text: (benefit['unpaidLeaveDays'] ?? 0).toString(),
    );

    String paidLeaveType = benefit['paidLeaveType']?.toString() ?? 'sunday';
    if (![
      'sunday',
      'saturday',
      'sat-sun',
      'sat-afternoon-sun',
      'off-1',
      'off-2',
      'off-3',
      'off-4'
    ].contains(paidLeaveType)) {
      // Map old WeeklyOffDays to new PaidLeaveType
      final oldPaidDayOff = benefit['weeklyOffDays']?.toString() ??
          employee['paidDayOff']?.toString() ??
          '';
      if (oldPaidDayOff.contains('Saturday') &&
          oldPaidDayOff.contains('Sunday')) {
        paidLeaveType = 'sat-sun';
      } else if (oldPaidDayOff.contains('Saturday')) {
        paidLeaveType = 'saturday';
      } else {
        paidLeaveType = 'sunday';
      }
    }

    String attendanceMode = benefit['attendanceMode']?.toString() ?? 'checkin';
    if (!['none', 'checkin', 'checkout', 'both', 'any']
        .contains(attendanceMode)) {
      attendanceMode = 'checkin';
    }

    List<String> selectedShifts = [];
    if (employee['shifts'] != null &&
        employee['shifts'].toString().isNotEmpty) {
      selectedShifts = employee['shifts'].toString().split(', ');
    }

    String shiftsPerDay =
        (benefit['shiftsPerDay'] ?? employee['shiftsPerDay'] ?? 1).toString();
    if (!['1', '2', '3', '4'].contains(shiftsPerDay)) shiftsPerDay = '1';

    final isMobileEdit = Responsive.isMobile(context);
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final formBody = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // Employee info (read-only)
                Row(
                  children: [
                    Expanded(
                        child: _buildReadOnlyField(
                            'Tên nhân viên:', nameController.text)),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _buildReadOnlyField(
                            'Mã nhân viên:', codeController.text)),
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
                      if (socialInsuranceType == '1' ||
                          socialInsuranceType == '2') {
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
                      Expanded(
                          child: _buildTextField(
                              label: 'Lương cơ bản:',
                              controller: baseSalaryController,
                              keyboardType: TextInputType.number)),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _buildTextField(
                              label: 'Lương hoàn thành:',
                              controller: completionSalaryController,
                              keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Cố định ngày')),
                            DropdownMenuItem(
                                value: '1',
                                child: Text('Hệ số tăng ca theo luật')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => holidayOvertimeType = value ?? '1'),
                        ),
                      ),
                      if (holidayOvertimeType == '0') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Tiền công ngày tăng ca:',
                                controller: holidayOvertimeDailyRateController,
                                keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Cố định giờ')),
                            DropdownMenuItem(
                                value: '1',
                                child: Text('Hệ số tăng ca theo luật')),
                            DropdownMenuItem(
                                value: '2', child: Text('Không tính tăng ca')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => hourlyOvertimeType = value ?? '1'),
                        ),
                      ),
                      if (hourlyOvertimeType == '0') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Tiền giờ tăng ca:',
                                controller: hourlyOvertimeFixedRateController,
                                keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Chưa đóng BHXH')),
                            DropdownMenuItem(
                                value: '1', child: Text('Đóng lương cơ bản')),
                            DropdownMenuItem(
                                value: '2',
                                child:
                                    Text('Lương cơ bản và Lương hoàn thành')),
                            DropdownMenuItem(
                                value: '3',
                                child: Text('Lương tối thiểu vùng')),
                            DropdownMenuItem(
                                value: '4', child: Text('Mức lương khác')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => socialInsuranceType = value ?? '0'),
                        ),
                      ),
                      if (socialInsuranceType == '4') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Mức lương đóng BHXH:',
                                controller: insuranceSalaryController,
                                keyboardType: TextInputType.number)),
                      ],
                    ],
                  ),
                  if (socialInsuranceType != '0') ...[
                    const SizedBox(height: 8),
                    _buildInsuranceSalaryDisplay(
                        socialInsuranceType,
                        baseSalaryController,
                        completionSalaryController,
                        insuranceSalaryController),
                  ],
                ],

                // ====== LƯƠNG NGÀY ======
                if (salaryType == '2') ...[
                  _buildTextField(
                      label: 'Lương cố định ngày:',
                      controller: dailyFixedRateController,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 16),

                  // Tăng ca ngày nghỉ
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField(
                          label: 'Tăng ca ngày nghỉ:',
                          value: holidayOvertimeType,
                          items: const [
                            DropdownMenuItem(
                                value: '0', child: Text('Cố định ngày')),
                            DropdownMenuItem(
                                value: '1',
                                child: Text('Hệ số tăng ca theo luật')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => holidayOvertimeType = value ?? '1'),
                        ),
                      ),
                      if (holidayOvertimeType == '0') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Tiền công ngày tăng ca:',
                                controller: holidayOvertimeDailyRateController,
                                keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Cố định giờ')),
                            DropdownMenuItem(
                                value: '1',
                                child: Text('Hệ số tăng ca theo luật')),
                            DropdownMenuItem(
                                value: '2', child: Text('Không tính tăng ca')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => hourlyOvertimeType = value ?? '1'),
                        ),
                      ),
                      if (hourlyOvertimeType == '0') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Tiền giờ tăng ca:',
                                controller: hourlyOvertimeFixedRateController,
                                keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Chưa đóng BHXH')),
                            DropdownMenuItem(
                                value: '3',
                                child: Text('Lương tối thiểu vùng')),
                            DropdownMenuItem(
                                value: '4', child: Text('Mức lương khác')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => socialInsuranceType = value ?? '0'),
                        ),
                      ),
                      if (socialInsuranceType == '4') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Mức lương đóng BHXH:',
                                controller: insuranceSalaryController,
                                keyboardType: TextInputType.number)),
                      ],
                    ],
                  ),
                  if (socialInsuranceType != '0') ...[
                    const SizedBox(height: 8),
                    _buildInsuranceSalaryDisplay(
                        socialInsuranceType,
                        baseSalaryController,
                        completionSalaryController,
                        insuranceSalaryController),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          label: 'Phép năm (ngày/năm):',
                          controller: paidLeaveDaysController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildTextField(
                          label: 'Phép không lương (ngày/năm):',
                          controller: unpaidLeaveDaysController,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Khi gán hồ sơ lương tháng, số phép năm được đưa vào quỹ nghỉ phép của nhân viên.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                    ),
                  ),
                ],

                // ====== LƯƠNG CA ======
                if (salaryType == '3') ...[
                  _buildDropdownField(
                    label: 'Kiểu tính lương:',
                    value: shiftSalaryType,
                    items: const [
                      DropdownMenuItem(
                          value: '0', child: Text('Lương ca cố định')),
                      DropdownMenuItem(
                          value: '1', child: Text('Lương theo ca')),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => shiftSalaryType = value ?? '0'),
                  ),
                  const SizedBox(height: 16),
                  if (shiftSalaryType == '0')
                    _buildTextField(
                        label: 'Tiền lương mỗi ca:',
                        controller: fixedShiftRateController,
                        keyboardType: TextInputType.number),
                  if (shiftSalaryType == '1') _buildShiftSalaryLevelsInfo(),
                  const SizedBox(height: 16),

                  // Tăng ca ngày nghỉ
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField(
                          label: 'Tăng ca ngày nghỉ:',
                          value: holidayOvertimeType,
                          items: const [
                            DropdownMenuItem(
                                value: '0', child: Text('Cố định ngày')),
                            DropdownMenuItem(
                                value: '1',
                                child: Text('Hệ số tăng ca theo luật')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => holidayOvertimeType = value ?? '1'),
                        ),
                      ),
                      if (holidayOvertimeType == '0') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Tiền công ngày tăng ca:',
                                controller: holidayOvertimeDailyRateController,
                                keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Cố định giờ')),
                            DropdownMenuItem(
                                value: '1',
                                child: Text('Hệ số tăng ca theo luật')),
                            DropdownMenuItem(
                                value: '2', child: Text('Không tính tăng ca')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => hourlyOvertimeType = value ?? '1'),
                        ),
                      ),
                      if (hourlyOvertimeType == '0') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Tiền giờ tăng ca:',
                                controller: hourlyOvertimeFixedRateController,
                                keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Chưa đóng BHXH')),
                            DropdownMenuItem(
                                value: '3',
                                child: Text('Lương tối thiểu vùng')),
                            DropdownMenuItem(
                                value: '4', child: Text('Mức lương khác')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => socialInsuranceType = value ?? '0'),
                        ),
                      ),
                      if (socialInsuranceType == '4') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Mức lương đóng BHXH:',
                                controller: insuranceSalaryController,
                                keyboardType: TextInputType.number)),
                      ],
                    ],
                  ),
                  if (socialInsuranceType != '0') ...[
                    const SizedBox(height: 8),
                    _buildInsuranceSalaryDisplay(
                        socialInsuranceType,
                        baseSalaryController,
                        completionSalaryController,
                        insuranceSalaryController),
                  ],
                ],

                // ====== LƯƠNG GIỜ ======
                if (salaryType == '0') ...[
                  _buildTextField(
                      label: 'Lương theo giờ:',
                      controller: hourlyRateController,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 16),

                  // Tăng ca làm thêm giờ
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownField(
                          label: 'Tăng ca làm thêm giờ:',
                          value: hourlyOvertimeType,
                          items: const [
                            DropdownMenuItem(
                                value: '0', child: Text('Cố định giờ')),
                            DropdownMenuItem(
                                value: '1',
                                child: Text('Hệ số tăng ca theo luật')),
                            DropdownMenuItem(
                                value: '2', child: Text('Không tính tăng ca')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => hourlyOvertimeType = value ?? '1'),
                        ),
                      ),
                      if (hourlyOvertimeType == '0') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Tiền giờ tăng ca:',
                                controller: hourlyOvertimeFixedRateController,
                                keyboardType: TextInputType.number)),
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
                            DropdownMenuItem(
                                value: '0', child: Text('Chưa đóng BHXH')),
                            DropdownMenuItem(
                                value: '3',
                                child: Text('Lương tối thiểu vùng')),
                            DropdownMenuItem(
                                value: '4', child: Text('Mức lương khác')),
                          ],
                          onChanged: (value) => setDialogState(
                              () => socialInsuranceType = value ?? '0'),
                        ),
                      ),
                      if (socialInsuranceType == '4') ...[
                        const SizedBox(width: 16),
                        Expanded(
                            child: _buildTextField(
                                label: 'Mức lương đóng BHXH:',
                                controller: insuranceSalaryController,
                                keyboardType: TextInputType.number)),
                      ],
                    ],
                  ),
                  if (socialInsuranceType != '0') ...[
                    const SizedBox(height: 8),
                    _buildInsuranceSalaryDisplay(
                        socialInsuranceType,
                        baseSalaryController,
                        completionSalaryController,
                        insuranceSalaryController),
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
                          DropdownMenuItem(
                              value: 'sunday', child: Text('Chủ nhật')),
                          DropdownMenuItem(
                              value: 'saturday', child: Text('Thứ bảy')),
                          DropdownMenuItem(
                              value: 'sat-sun',
                              child: Text('Thứ bảy & Chủ nhật')),
                          DropdownMenuItem(
                              value: 'sat-afternoon-sun',
                              child: Text('Chiều thứ 7 & Chủ nhật')),
                          DropdownMenuItem(
                              value: 'off-1', child: Text('Nghỉ 1 ngày/tháng')),
                          DropdownMenuItem(
                              value: 'off-2', child: Text('Nghỉ 2 ngày/tháng')),
                          DropdownMenuItem(
                              value: 'off-3', child: Text('Nghỉ 3 ngày/tháng')),
                          DropdownMenuItem(
                              value: 'off-4', child: Text('Nghỉ 4 ngày/tháng')),
                        ],
                        onChanged: (value) => setDialogState(
                            () => paidLeaveType = value ?? 'sunday'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDropdownField(
                        label: 'Chấm công:',
                        value: attendanceMode,
                        items: const [
                          DropdownMenuItem(
                              value: 'none', child: Text('Không chấm công')),
                          DropdownMenuItem(
                              value: 'checkin', child: Text('Chấm vào')),
                          DropdownMenuItem(
                              value: 'checkout', child: Text('Chấm ra')),
                          DropdownMenuItem(
                              value: 'both', child: Text('Chấm vào & Chấm ra')),
                          DropdownMenuItem(
                              value: 'any',
                              child: Text('Chấm bất kỳ trong ca')),
                        ],
                        onChanged: (value) => setDialogState(
                            () => attendanceMode = value ?? 'checkin'),
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
                        onChanged: (shifts) =>
                            setDialogState(() => selectedShifts = shifts),
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
                        onChanged: (value) =>
                            setDialogState(() => shiftsPerDay = value ?? '1'),
                      ),
                    ),
                  ],
                ),
              ],
            );
          final formContent = isMobileEdit
              ? SingleChildScrollView(
                  padding: const EdgeInsets.all(16), child: formBody)
              : formBody;
          Future<void> onSave() async {
            Navigator.pop(dialogContext);

            try {
              // Build benefit data based on salary type
              final rateType = int.parse(salaryType);
              double rate = 0;

              if (rateType == 1) {
                rate = double.tryParse(
                        baseSalaryController.text.replaceAll('.', '')) ??
                    0;
              } else if (rateType == 0) {
                rate = double.tryParse(
                        hourlyRateController.text.replaceAll('.', '')) ??
                    0;
              } else if (rateType == 2) {
                rate = double.tryParse(
                        dailyFixedRateController.text.replaceAll('.', '')) ??
                    0;
              } else if (rateType == 3) {
                final shiftType = int.parse(shiftSalaryType);
                if (shiftType == 0) {
                  rate = double.tryParse(
                          fixedShiftRateController.text.replaceAll('.', '')) ??
                      0;
                } else {
                  // Shift template: use 1 as placeholder to pass validation
                  rate = 1;
                }
              }

              final fixedAllowance = double.tryParse(
                      fixedAllowanceController.text.replaceAll('.', '')) ??
                  0;
              final dailyAllowance = double.tryParse(
                      dailyAllowanceController.text.replaceAll('.', '')) ??
                  0;

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
                'completionSalary': double.tryParse(
                        completionSalaryController.text.replaceAll('.', '')) ??
                    0,
                'holidayOvertimeType': int.parse(holidayOvertimeType),
                'holidayOvertimeDailyRate': double.tryParse(
                        holidayOvertimeDailyRateController.text
                            .replaceAll('.', '')) ??
                    0,
                'hourlyOvertimeType': int.parse(hourlyOvertimeType),
                'hourlyOvertimeFixedRate': double.tryParse(
                        hourlyOvertimeFixedRateController.text
                            .replaceAll('.', '')) ??
                    0,
                'socialInsuranceType': int.parse(socialInsuranceType),
                'insuranceSalary': _calculateInsuranceSalary(
                  socialInsuranceType,
                  rate,
                  double.tryParse(completionSalaryController.text
                          .replaceAll('.', '')) ??
                      0,
                  double.tryParse(
                          insuranceSalaryController.text.replaceAll('.', '')) ??
                      0,
                ),
                'dailyFixedRate': double.tryParse(
                        dailyFixedRateController.text.replaceAll('.', '')) ??
                    0,
                'shiftSalaryType': int.parse(shiftSalaryType),
                'fixedShiftRate': double.tryParse(
                        fixedShiftRateController.text.replaceAll('.', '')) ??
                    0,
                'shiftsPerDay': int.parse(shiftsPerDay),
                'attendanceMode': attendanceMode,
                'paidLeaveType': paidLeaveType,
                'isActive': true,
              };

              if (rateType == 1) {
                benefitData['paidLeaveDays'] =
                    int.tryParse(paidLeaveDaysController.text.trim()) ?? 0;
                benefitData['unpaidLeaveDays'] =
                    int.tryParse(unpaidLeaveDaysController.text.trim()) ?? 0;
              }

              Map<String, dynamic> result;
              String? benefitId = employee['benefitId']?.toString();

              if (benefitId != null && benefitId.isNotEmpty) {
                result = await _apiService.updateSalaryProfile(
                    benefitId, benefitData);
              } else {
                result = await _apiService.createSalaryProfile(benefitData);
                if (result['isSuccess'] == true && result['data'] != null) {
                  benefitId = result['data']['id']?.toString();
                }
              }

              if (result['isSuccess'] == true && benefitId != null) {
                // Only assign if not already assigned to this benefit
                final existingBenefitId = employee['benefitId']?.toString();
                if (existingBenefitId != null &&
                    existingBenefitId == benefitId) {
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
                      message: assignResult['message'] ??
                          'Không thể gán profile lương',
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
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(dialogContext)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Hủy')),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onSave,
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text('Lưu'),
                          style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            maxContentWidth: 620,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.edit, color: HrmPageChrome.primaryNavy),
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
              width: math.min(620, MediaQuery.of(context).size.width - 64),
              child: formBody,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Hủy',
                    style: TextStyle(color: Color(0xFF71717A))),
              ),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Lưu'),
                style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
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
        border:
            Border.all(color: HrmPageChrome.primaryNavy.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: HrmPageChrome.primaryNavy, size: 16),
              SizedBox(width: 8),
              Text(
                'Mức lương theo ca đã thiết lập',
                style: TextStyle(
                    color: HrmPageChrome.primaryNavy,
                    fontWeight: FontWeight.w600,
                    fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_shifts.isEmpty)
            const Text('Chưa có ca làm việc nào',
                style: TextStyle(color: Color(0xFF71717A), fontSize: 12))
          else
            ..._shifts.map((shift) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${shift['name']} (${shift['startTime']} - ${shift['endTime']})',
                    style:
                        const TextStyle(color: Color(0xFF18181B), fontSize: 12),
                  ),
                )),
          const SizedBox(height: 4),
          const Text(
            'Cấu hình mức lương theo ca tại mục Thiết lập ca',
            style: TextStyle(
                color: Color(0xFF71717A),
                fontSize: 11,
                fontStyle: FontStyle.italic),
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
          onChanged:
              isNumeric ? (_) => _formatControllerNumber(controller) : null,
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
              borderSide: const BorderSide(color: HrmPageChrome.primaryNavy, width: 2),
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
                onChanged: (isNumeric && !readOnly)
                    ? (_) => _formatControllerNumber(controller)
                    : null,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: readOnly
                      ? const Color(0xFFEEF2F6)
                      : const Color(0xFFFAFAFA),
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
                        const BorderSide(color: HrmPageChrome.primaryNavy, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: HrmPageChrome.primaryNavy.withValues(alpha: 0.3)),
              ),
              child: IconButton(
                icon: const Icon(Icons.calculate, color: HrmPageChrome.primaryNavy),
                onPressed: onCalculatePressed,
                tooltip: 'Chọn phụ cấp từ danh sách',
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _calculateEmployeeAllowanceTotal(
    String employeeId,
    int allowanceType, {
    Map<String, dynamic>? employee,
  }) {
    final benefit = employee?['benefit'] as Map<String, dynamic>?;
    return AllowanceCalculator.sumForEmployee(
      allowances: _allowances,
      employeeId: employeeId,
      employeeCode: employee?['employeeCode']?.toString(),
      allowanceType: allowanceType,
      benefitFallback: benefit ??
          (employee != null
              ? {
                  'mealAllowance': employee['fixedAllowance'],
                  'responsibilityAllowance': employee['dailyAllowance'],
                }
              : null),
    );
  }

  bool _isAllowanceAssignedToEmployee(
      Map<String, dynamic> allowance, String employeeId,
      {String? employeeCode}) {
    return AllowanceCalculator.isAssignedToEmployee(
      allowance,
      employeeId,
      employeeCode: employeeCode,
    );
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
              final type = a['type'] is int
                  ? a['type']
                  : int.tryParse(a['type']?.toString() ?? '0') ?? 0;
              final isActive = a['isActive'] ?? true;
              return type == allowanceType &&
                  isActive &&
                  _isAllowanceAssignedToEmployee(a, employeeId);
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
                    color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    allowanceType == 0 ? Icons.lock : Icons.calendar_today,
                    color: HrmPageChrome.primaryNavy,
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
                          Icon(Icons.inbox_outlined,
                              size: 48, color: Colors.grey[400]),
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
                            color:
                                HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: HrmPageChrome.primaryNavy,
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
                        subtitle: allowance['code'] != null &&
                                allowance['code'].toString().isNotEmpty
                            ? Text(
                                'Mã: ${allowance['code']}',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12),
                              )
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_currencyFormat.format(amount)} đ',
                            style: const TextStyle(
                              color: HrmPageChrome.primaryNavy,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              HrmPageChrome.primaryNavy.withValues(alpha: 0.3)),
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
                            color: HrmPageChrome.primaryNavy,
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
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const AllowanceSettingsScreen()),
                            );
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Thêm phụ cấp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: HrmPageChrome.primaryNavy,
                            side: const BorderSide(color: HrmPageChrome.primaryNavy),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: HrmPageChrome.primaryNavy,
                            padding: const EdgeInsets.symmetric(vertical: 12),
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
                      title: Text(allowanceType == 0
                          ? 'Phụ cấp cố định'
                          : 'Phụ cấp theo ngày'),
                      leading: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context)),
                    ),
                    body: Column(
                      children: [
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: headerRow),
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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
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
                        border: Border(
                            bottom: BorderSide(color: Color(0xFFE4E4E7))),
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

  // ignore: unused_element
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
            return ScrollableAlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.add_circle_outline,
                      color: HrmPageChrome.primaryNavy, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    allowanceType != null
                        ? (allowanceType == 0
                            ? 'Thêm phụ cấp cố định'
                            : 'Thêm phụ cấp theo ngày')
                        : 'Thêm phụ cấp mới',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
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
                        initialValue: selectedType,
                        decoration: InputDecoration(
                          labelText: 'Loại phụ cấp *',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 0, child: Text('Phụ cấp cố định')),
                          DropdownMenuItem(
                              value: 1, child: Text('Phụ cấp theo ngày')),
                          DropdownMenuItem(
                              value: 2, child: Text('Phụ cấp theo giờ')),
                          DropdownMenuItem(
                              value: 3, child: Text('Phụ cấp khác')),
                        ],
                        onChanged: (v) =>
                            setAddState(() => selectedType = v ?? 0),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Tên phụ cấp *',
                        hintText: 'VD: Phụ cấp ăn trưa',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Vui lòng nhập tên phụ cấp'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: 'Số tiền (VNĐ) *',
                        hintText: 'VD: 500000',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        suffixText: 'đ',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Vui lòng nhập số tiền';
                        }
                        final amount = double.tryParse(
                            v.replaceAll('.', '').replaceAll(',', ''));
                        if (amount == null || amount <= 0) {
                          return 'Số tiền không hợp lệ';
                        }
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
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setAddState(() => isSubmitting = true);
                          try {
                            final amount = double.parse(
                              amountController.text
                                  .replaceAll('.', '')
                                  .replaceAll(',', ''),
                            );
                            final data = {
                              'name': nameController.text.trim(),
                              'type': selectedType,
                              'amount': amount,
                              'currency': 'VND',
                              'isActive': true,
                              'employeeIds':
                                  employeeId.isNotEmpty ? [employeeId] : [],
                            };
                            final result =
                                await _apiService.createAllowanceSetting(data);
                            if (result['isSuccess'] == true) {
                              if (context.mounted) Navigator.pop(context);
                              onCreated();
                              appNotification.showSuccess(
                                title: 'Thành công',
                                message:
                                    'Đã thêm phụ cấp "${nameController.text.trim()}"',
                              );
                            } else {
                              setAddState(() => isSubmitting = false);
                              appNotification.showError(
                                title: 'Lỗi',
                                message: result['message'] ??
                                    'Không thể tạo phụ cấp',
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
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
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
                      activeColor: HrmPageChrome.primaryNavy,
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
              child:
                  const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                onChanged(selected);
              },
              style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy,
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
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
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
          return ScrollableAlertDialog(
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
      final newOffset =
          (cursorOffset + (newLength - oldLength)).clamp(0, newLength);
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
