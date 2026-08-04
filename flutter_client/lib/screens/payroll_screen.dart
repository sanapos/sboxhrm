import 'package:flutter/material.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_collapsible_overview.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import '../widgets/page_top_actions.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/attendance_bootstrap_loader.dart';
import 'attendance/payroll_summary_tab.dart';
import 'main_layout.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/salary_profile_load_utils.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màn hình Tổng hợp lương
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final ApiService _apiService = ApiService();
  final GlobalKey<PayrollSummaryTabState> _payrollTabKey = GlobalKey();

  List<Attendance> _attendances = [];
  List<Device> _devices = [];
  bool _isLoading = true;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];
  bool _showOverviewPanel = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadEmployeesAndBranches();
    ScreenRefreshNotifier.payroll.addListener(_onExternalRefresh);
  }

  Future<void> _loadEmployeesAndBranches() async {
    try {
      final emps = await _apiService.getEmployeesForSelect(pageSize: 1000);
      if (mounted) {
        setState(() => _employeesList =
            emps.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
    try {
      final br = await _apiService.getBranchesForSelect();
      final bd = br['data'];
      if (bd is List && mounted) {
        setState(() => _branches =
            bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
      }
    } catch (_) {}
  }

  List<Attendance> get _filteredAttendances {
    if (_selectedBranchId == null) return _attendances;
    final branchCodes = _employeesList
        .where((e) => e['branchId']?.toString() == _selectedBranchId)
        .map((e) => e['employeeCode']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet();
    return _attendances
        .where((a) => branchCodes.contains(a.employeeId))
        .toList();
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.payroll.removeListener(_onExternalRefresh);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final isEmployee = isEmployeeUserRole(
        context.read<AuthProvider>().user?.role,
      );
      List<Device> parsedDevices = [];
      if (!isEmployee) {
        final deviceList = await _apiService.getDevices(storeOnly: true);
        parsedDevices = deviceList
            .map((d) => Device.fromJson(d as Map<String, dynamic>))
            .toList();
      }

      final fromDate = DateTime(_selectedYear, _selectedMonth, 1);
      final toDate = DateTime(_selectedYear, _selectedMonth + 1, 0);
      List<Attendance> allAttendances = [];
      final bootstrap = await loadAttendanceBootstrap(
        _apiService,
        fromDate: fromDate,
        toDate: toDate,
        loadShiftMeta: false,
        preferSelfServiceApi: isEmployee,
      );
      allAttendances = bootstrap.attendances;

      if (mounted) {
        setState(() {
          _devices = parsedDevices;
          _attendances = allAttendances;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading payroll data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Widget> _payrollPageChromeSections(bool isMobile) {
    if (_branches.isEmpty) return const [];
    return [
      Padding(
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : 24,
          isMobile ? 8 : 16,
          isMobile ? 12 : 24,
          isMobile ? 4 : 8,
        ),
        child: HrmCollapsibleOverview(
          expanded: _showOverviewPanel,
          onToggle: () =>
              setState(() => _showOverviewPanel = !_showOverviewPanel),
          title: 'Bộ lọc',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedBranchId,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF111827)),
                      icon: const Icon(Icons.keyboard_arrow_down,
                          size: 18, color: Color(0xFF9CA3AF)),
                      items: [
                        DropdownMenuItem<String?>(
                            value: null,
                            child: Text(tr('Tất cả chi nhánh'),
                                style: const TextStyle(fontSize: 13))),
                        ..._branches.map((b) => DropdownMenuItem<String?>(
                            value: b['id']?.toString(),
                            child: Text(tr(b['name']?.toString() ?? ''),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)))),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedBranchId = v),
                    ),
                  ),
                ),
                if (_selectedBranchId != null)
                  InkWell(
                    onTap: () => setState(() => _selectedBranchId = null),
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 14, color: Color(0xFF9CA3AF)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _monthYearTopAction() {
    return PopupMenuButton<String>(
      tooltip: tr('Chọn tháng $_selectedMonth/$_selectedYear'),
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month, size: 20),
            const SizedBox(width: 4),
            Text(
              '$_selectedMonth/$_selectedYear',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      onSelected: (v) {
        final parts = v.split('/');
        if (parts.length != 2) return;
        final m = int.tryParse(parts[0]);
        final y = int.tryParse(parts[1]);
        if (m == null || y == null) return;
        setState(() {
          _selectedMonth = m;
          _selectedYear = y;
        });
        _loadData();
      },
      itemBuilder: (_) {
        final now = DateTime.now();
        return List.generate(12, (i) {
          final d = DateTime(now.year, now.month - i, 1);
          final label = '${d.month}/${d.year}';
          return PopupMenuItem(value: label, child: Text(tr('Tháng $label')));
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final fromDate = DateTime(_selectedYear, _selectedMonth, 1);
    final toDate = DateTime(_selectedYear, _selectedMonth + 1, 0);
    final chrome = _payrollPageChromeSections(isMobile);
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('Payroll');

    return RegisterPageTopActions(
      actions: [
        _monthYearTopAction(),
        if (canExport)
          HrmTopBarAction(
            icon: Icons.table_chart_outlined,
            label: 'Xuất Excel',
            onPressed: () => _payrollTabKey.currentState?.exportToExcel(),
          ),
        if (canExport)
          HrmTopBarAction(
            icon: Icons.image_outlined,
            label: 'Xuất PNG',
            onPressed: () => _payrollTabKey.currentState?.exportToPng(),
          ),
        HrmTopBarAction(
          icon: Icons.view_column_outlined,
          label: 'Chọn cột',
          onPressed: () =>
              _payrollTabKey.currentState?.showColumnSelectorDialog(),
        ),
      ],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final maxHeaderH =
                (constraints.maxHeight * 0.55).clamp(160.0, 560.0);
            return Column(
              children: [
                if (!isMobile && chrome.isNotEmpty)
                  HrmResponsiveListLayout.shrinkWrapHeader(
                    maxHeight: maxHeaderH,
                    children: chrome,
                  ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : PayrollSummaryTab(
                          key: _payrollTabKey,
                          attendances: _filteredAttendances,
                          devices: _devices,
                          fromDate: fromDate,
                          toDate: toDate,
                          branchId: _selectedBranchId,
                          mobileLeadingSections: isMobile ? chrome : null,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
