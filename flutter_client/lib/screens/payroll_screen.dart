import 'package:flutter/material.dart';
import '../widgets/hrm_page_chrome.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/vietnamese_font.dart';
import '../utils/attendance_bootstrap_loader.dart';
import 'attendance/payroll_summary_tab.dart';
import 'main_layout.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

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
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadEmployeesAndBranches();
    ScreenRefreshNotifier.payroll.addListener(_onExternalRefresh);
  }

  Future<void> _loadEmployeesAndBranches() async {
    try {
      final emps = await _apiService.getEmployees(pageSize: 1000);
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
      final deviceList = await _apiService.getDevices(storeOnly: true);
      final parsedDevices = deviceList
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList();
      final deviceIds = parsedDevices.map((d) => d.id).toList();

      List<Attendance> allAttendances = [];
      if (deviceIds.isNotEmpty) {
        final now = DateTime.now();
        final fromDate = DateTime(now.year, now.month, 1);
        final bootstrap = await loadAttendanceBootstrap(
          _apiService,
          fromDate: fromDate,
          toDate: now,
          loadShiftMeta: false,
        );
        allAttendances = bootstrap.attendances;
      }

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

  List<Widget> _payrollPageChromeSections(bool isMobile) => [
        Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18,
                isMobile ? 14 : 24, isMobile ? 12 : 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.85),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payments,
                      color: Colors.white, size: isMobile ? 18 : 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tổng hợp lương',
                          style: vietnameseTextStyle(TextStyle(
                              color: Colors.white,
                              fontSize: isMobile ? 16 : 20,
                              fontWeight: FontWeight.bold))),
                      if (!isMobile)
                        Text('Bảng lương chi tiết nhân viên',
                            style: vietnameseTextStyle(TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 13))),
                    ],
                  ),
                ),
                if (isMobile)
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.more_vert,
                          size: 18, color: Colors.white),
                    ),
                    onSelected: (v) {
                      if (v == 'excel') {
                        _payrollTabKey.currentState?.exportToExcel();
                      }
                      if (v == 'png') {
                        _payrollTabKey.currentState?.exportToPng();
                      }
                      if (v == 'cols') {
                        _payrollTabKey.currentState?.showColumnSelectorDialog();
                      }
                    },
                    itemBuilder: (_) => [
                      if (Provider.of<PermissionProvider>(context,
                              listen: false)
                          .canExport('Payroll'))
                        PopupMenuItem(
                            value: 'excel',
                            child: Row(children: [
                              const Icon(Icons.table_chart_outlined, size: 18),
                              const SizedBox(width: 10),
                              Text('Xuất Excel', style: vietnameseTextStyle())
                            ])),
                      if (Provider.of<PermissionProvider>(context,
                              listen: false)
                          .canExport('Payroll'))
                        PopupMenuItem(
                            value: 'png',
                            child: Row(children: [
                              const Icon(Icons.image_outlined, size: 18),
                              const SizedBox(width: 10),
                              Text('Xuất PNG', style: vietnameseTextStyle())
                            ])),
                      PopupMenuItem(
                          value: 'cols',
                          child: Row(children: [
                            const Icon(Icons.view_column_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text('Chọn cột', style: vietnameseTextStyle())
                          ])),
                    ],
                  )
                else ...[
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canExport('Payroll')) ...[
                    _buildHeaderActionBtn(Icons.table_chart_outlined, 'Excel',
                        () {
                      _payrollTabKey.currentState?.exportToExcel();
                    }),
                    const SizedBox(width: 8),
                    _buildHeaderActionBtn(Icons.image_outlined, 'PNG', () {
                      _payrollTabKey.currentState?.exportToPng();
                    }),
                    const SizedBox(width: 8),
                  ],
                  _buildHeaderActionBtn(Icons.view_column_outlined, 'Cột', () {
                    _payrollTabKey.currentState?.showColumnSelectorDialog();
                  }),
                ],
              ],
            ),
          ),
          // ═══ Content ═══
          if (_branches.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          key: const ValueKey('branch_\$_selectedBranchId'),
                          value: _selectedBranchId,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF111827)),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              size: 18, color: Color(0xFF9CA3AF)),
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('T\u1ea5t c\u1ea3 chi nh\u00e1nh',
                                    style: TextStyle(fontSize: 13))),
                            ..._branches.map((b) => DropdownMenuItem<String?>(
                                value: b['id']?.toString(),
                                child: Text(b['name']?.toString() ?? '',
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
      ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isMobile = Responsive.isMobile(context);
    final chrome = _payrollPageChromeSections(isMobile);

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          if (!isMobile) ...chrome,
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : PayrollSummaryTab(
                    key: _payrollTabKey,
                    attendances: _filteredAttendances,
                    devices: _devices,
                    fromDate: DateTime(now.year, now.month, 1),
                    toDate: now,
                    branchId: _selectedBranchId,
                    mobileLeadingSections: isMobile ? chrome : null,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionBtn(
      IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
