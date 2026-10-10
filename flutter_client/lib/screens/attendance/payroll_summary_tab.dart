import '../../utils/branch_filter_helper.dart';
import '../payroll_pay/payroll_pay_page.dart';
import '../../widgets/attendance/punch_cells.dart';
import 'dart:convert';
import '../../utils/work_schedule_load_utils.dart';
import 'dart:math' as math;
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/web_canvas.dart' as web_canvas;

import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../models/employee.dart';
import '../../models/hr_finance.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/hrm_collapsible_overview.dart';
import '../../widgets/report_salary_setup_hint.dart';
import '../../utils/excel_report_builder.dart';
import '../../widgets/synced_scroll_list_view.dart'
    show HorizontallySyncedClip;
import '../../utils/shift_records_calculator.dart';
import 'package:payroll_engine/payroll/payroll_engine.dart';
import 'package:payroll_engine/payroll/payroll_finalize.dart';
import '../../utils/paid_leave_schedule_utils.dart';
import '../../utils/allowance_calculator.dart';
import '../../utils/travel_hours_calculator.dart';
import '../../utils/travel_hours_load_utils.dart';
import '../../utils/travel_salary_utils.dart';
import '../../utils/standard_work_days_utils.dart';
import '../../utils/attendance_bootstrap_loader.dart';
import '../../utils/salary_profile_load_utils.dart';
import '../../utils/overtime_hourly_base_utils.dart';
import '../../utils/pit_tax_utils.dart';
import '../../models/mobile_attendance.dart';
import '../../utils/mobile_attendance_vertical_layout.dart';
import '../main_layout.dart' show NavigationNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_table.dart';
import '../../widgets/sbox/sbox_report.dart';
import '../../widgets/sbox/sbox_charts.dart';
// ═══════════════════════════════════════════════════════════════
//  PayrollColumn – định nghĩa 1 cột bảng lương
// ═══════════════════════════════════════════════════════════════
class PayrollColumn {
  final String key;
  final String label;
  final bool defaultVisible;
  bool visible;

  PayrollColumn({
    required this.key,
    required this.label,
    this.defaultVisible = true,
    bool? visible,
  }) : visible = visible ?? defaultVisible;
}

// ═══════════════════════════════════════════════════════════════
//  PayrollSummaryTab
// ═══════════════════════════════════════════════════════════════
class PayrollSummaryTab extends StatefulWidget {
  final List<Attendance> attendances;
  final List<Device> devices;
  final DateTime fromDate;
  final DateTime toDate;
  final String? branchId;
  final List<Widget>? mobileLeadingSections;

  const PayrollSummaryTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.fromDate,
    required this.toDate,
    this.branchId,
    this.mobileLeadingSections,
  });

  @override
  State<PayrollSummaryTab> createState() => PayrollSummaryTabState();
}

class PayrollSummaryTabState extends State<PayrollSummaryTab> {
  final ApiService _apiService = ApiService();
  final _currencyFmt = NumberFormat('#,###', 'vi_VN');
  final GlobalKey _tableKey = GlobalKey();

  // ═══ Dữ liệu + công thức: PayrollEngine (gói dùng chung với máy chủ) ═══
  late final PayrollEngine _engine = PayrollEngine(api: _apiService, log: debugPrint);
  final ValueNotifier<String?> _payrollHoveredRow = ValueNotifier<String?>(null);

  // ═══ State ═══
  bool _isLoading = true;
  bool _isFinalizing = false;
  bool _showOverviewPanel = true;
  bool _payrollFiltersExpanded = true;
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _selectedPeriod = 'thisMonth';
  String _sortColumn = 'code';
  bool _sortAscending = true;
  Set<String> _selectedEmployeeIds = {}; // empty = all employees
  String? _selectedDepartment; // null = all departments

  // ═══ Pagination ═══
  int _currentPage = 1;
  int _rowsPerPage = 20;

  // ═══ Columns ═══
  List<PayrollColumn> _columns = [];
  bool _columnsInitialized = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // Scroll controllers for synced scrolling
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _desktopTableHScrollBody = ScrollController();
  final ScrollController _desktopTableVScroll = ScrollController();

  static const _employeeSignColumnKey = 'employeeSign';

  /// Ký cuối bảng (không gồm NV — NV ký ở cột [employeeSign] từng dòng).
  static const _payrollFooterSignatureLabels = [
    'Người lập',
    'Kế toán',
    'Thủ quỹ',
    'Giám đốc',
  ];

  // Cache
  List<Map<String, dynamic>>? _cachedPayrollData;

  /// Cấu hình làm sai công / lương (vd ca đêm kết thúc sau giờ chốt ngày).
  List<String> _configWarnings = const [];

  /// Bảng lương do MÁY CHỦ tính (số chính thức, cùng công thức). null = máy chủ cũ / lỗi → số tính trên máy.
  List<Map<String, dynamic>>? _serverRows;
  int _serverFetchSeq = 0;

  // ──────── Lifecycle ────────
  @override
  void initState() {
    super.initState();
    _fromDate = widget.fromDate;
    _toDate = widget.toDate;
    _loadPayrollData();
  }

  @override
  void didUpdateWidget(PayrollSummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!DateUtils.isSameDay(oldWidget.fromDate, widget.fromDate) ||
        !DateUtils.isSameDay(oldWidget.toDate, widget.toDate)) {
      // Màn cha đổi tháng: tải lại toàn bộ cho kỳ mới.
      _fromDate = widget.fromDate;
      _toDate = widget.toDate;
      _loadPayrollData();
      return;
    }
    _syncEngineContext();
    if (oldWidget.attendances != widget.attendances) {
      // Chấm công mới (máy chấm / app): trước đây vẫn tính trên danh sách cũ đã tải lúc mở màn
      // → bảng lương không tự cập nhật. Kỳ nằm trong tháng màn cha thì lấy luôn dữ liệu mới.
      final fromDay = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
      final toEnd = DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
      if (_engine.parentAttendancesCoverPeriod(fromDay, toEnd)) {
        _engine.periodAttendances = widget.attendances.where((a) {
          final t = a.attendanceTime;
          return !t.isBefore(fromDay) && !t.isAfter(toEnd);
        }).toList();
      }
    }
    if (oldWidget.attendances != widget.attendances) _refreshServerRowsInBackground();
    if (oldWidget.branchId != widget.branchId ||
        oldWidget.attendances != widget.attendances) {
      _cachedPayrollData = null;
      _engine.cachedShiftRecords = null;
      _engine.shiftRecordsByEmpKey = null;
      if (oldWidget.branchId != widget.branchId) {
        _selectedDepartment = null;
        _pruneEmployeeSelectionToPool();
        _currentPage = 1;
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine.salaryTypeLabels = {0: _l10n.hourly, 1: _l10n.monthly, 2: _l10n.daily, 3: 'Ca'};
    if (!_columnsInitialized) {
      _columnsInitialized = true;
      _initColumns();
    }
  }

  List<PayrollColumn> _defaultPayrollColumns() {
    return [
      PayrollColumn(key: 'stt', label: 'STT'),
      PayrollColumn(key: 'name', label: _l10n.employeeName),
      PayrollColumn(key: 'code', label: _l10n.employeeCode),
      PayrollColumn(
        key: 'department',
        label: _l10n.department,
        defaultVisible: false,
      ),
      PayrollColumn(key: 'salaryType', label: _l10n.salaryType),
      PayrollColumn(key: 'standardDays', label: _l10n.standardWorkDays),
      PayrollColumn(key: 'workDays', label: _l10n.totalWorkDays),
      // Ngày lễ + nghỉ có lương đã duyệt được trả (lương tháng / ngày) — ẩn khi không có.
      PayrollColumn(key: 'paidDaysCredit', label: 'Lễ / phép có lương'),
      PayrollColumn(key: 'totalHours', label: _l10n.totalHours),
      PayrollColumn(
        key: 'otTotalHours',
        label: _l10n.overtime,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'travelHours',
        label: 'Đi đường (giờ)',
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'travelSalary',
        label: 'Lương đi đường',
        defaultVisible: false,
      ),
      PayrollColumn(key: 'baseSalary', label: _l10n.baseSalary),
      PayrollColumn(key: 'workSalary', label: 'Lương theo công'),
      PayrollColumn(key: 'completionSalary', label: _l10n.completionSalary),
      PayrollColumn(
        key: 'dailySalary',
        label: _l10n.dailySalary,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'shiftSalary',
        label: _l10n.shiftSalary,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'hourlySalary',
        label: _l10n.hourSalary,
        defaultVisible: false,
      ),
      PayrollColumn(key: 'otSalary', label: _l10n.overtimeSalary),
      PayrollColumn(key: 'allowanceFixed', label: 'PC cố định'),
      PayrollColumn(key: 'allowanceDaily', label: 'PC theo ngày'),
      PayrollColumn(key: 'allowanceShift', label: 'PC theo ca'),
      PayrollColumn(key: 'allowanceQualified', label: 'Ngày/ca đủ ĐK PC'),
      PayrollColumn(key: 'totalAllowance', label: 'Tổng PC kỳ'),
      PayrollColumn(key: 'bonus', label: _l10n.bonusAmount),
      PayrollColumn(
        key: 'kpiSalary',
        label: _l10n.kpiSalary,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'productionAmount',
        label: 'Sản lượng',
        defaultVisible: false,
      ),
      PayrollColumn(key: 'leavePayout', label: 'Tiền phép năm'),
      // Tổng lương trước các khoản trừ / thực nhận
      PayrollColumn(key: 'totalSalary', label: _l10n.totalSalary),
      PayrollColumn(
        key: 'penalty',
        label: _l10n.penaltyAmount,
        defaultVisible: false,
      ),
      PayrollColumn(key: 'bhxh', label: 'BHXH', defaultVisible: false),
      PayrollColumn(key: 'pit', label: 'TNCN', defaultVisible: false),
      PayrollColumn(
        key: 'advance',
        label: _l10n.advancePaid,
        defaultVisible: true,
      ),
      PayrollColumn(key: 'netSalary', label: _l10n.netSalary),
      PayrollColumn(
        key: _employeeSignColumnKey,
        label: 'Ký tên',
        defaultVisible: false,
      ),
    ];
  }

  /// Đảm bảo Đi đường / Lương đi đường đứng trước Lương cơ bản (kể cả prefs cũ).
  void _ensureTravelColumnsBeforeBaseSalary() {
    const travelKeys = ['travelHours', 'travelSalary'];
    final travelCols = <PayrollColumn>[];
    for (final key in travelKeys) {
      final idx = _columns.indexWhere((c) => c.key == key);
      if (idx >= 0) travelCols.add(_columns.removeAt(idx));
    }
    if (travelCols.isEmpty) return;
    final baseIdx = _columns.indexWhere((c) => c.key == 'baseSalary');
    if (baseIdx < 0) {
      _columns.addAll(travelCols);
      return;
    }
    _columns.insertAll(baseIdx, travelCols);
  }

  void _initColumns() {
    _columns = _defaultPayrollColumns();
    _loadColumnPreferences();
  }

  /// Cột lõi luôn hiện trên bảng (dù số liệu = 0).
  static const _payrollCoreColumnKeys = {
    'stt',
    'name',
    'code',
    'netSalary',
  };

  /// Có giá trị hiển thị trong kỳ (số ≠ 0 hoặc text khác rỗng).
  bool _columnHasDisplayData(String key, List<Map<String, dynamic>> data) {
    if (data.isEmpty) return false;
    for (final row in data) {
      final v = row[key];
      if (v == null) continue;
      if (v is num) {
        if (v != 0) return true;
        continue;
      }
      final s = v.toString().trim();
      if (s.isNotEmpty && s != '—' && s != '-' && s != '0' && s != '0.0') {
        return true;
      }
    }
    return false;
  }

  /// Hiện cột lõi + cột có dữ liệu trong kỳ. Ẩn cột store không dùng (toàn 0/rỗng)
  /// để dành chỗ các cột có số liệu — kể cả khi prefs còn bật cột trống.
  List<PayrollColumn> _visiblePayrollColumns(
      [List<Map<String, dynamic>>? data]) {
    final scan = data ?? _cachedPayrollData;
    final visible = <PayrollColumn>[];
    for (final c in _columns) {
      if (c.key == _employeeSignColumnKey) {
        if (c.visible) visible.add(c);
        continue;
      }
      if (_payrollCoreColumnKeys.contains(c.key)) {
        visible.add(c);
        continue;
      }
      if (!_engine.showTravelPayrollColumns &&
          (c.key == 'travelHours' || c.key == 'travelSalary')) {
        continue;
      }
      if (scan == null) {
        // Chưa có dữ liệu: theo prefs/defaultVisible.
        if (c.visible) visible.add(c);
        continue;
      }
      if (_columnHasDisplayData(c.key, scan)) {
        visible.add(c);
      }
    }
    return visible;
  }

  Future<void> _loadColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('payroll_columns_v11');
      if (saved != null) {
        final List<dynamic> list = jsonDecode(saved);
        // Rebuild _columns in saved order, preserving visibility
        final orderedCols = <PayrollColumn>[];
        final remaining = List<PayrollColumn>.from(_columns);
        for (final item in list) {
          final key = item['key'] as String;
          final visible = item['visible'] as bool;
          final idx = remaining.indexWhere((c) => c.key == key);
          if (idx >= 0) {
            remaining[idx].visible = visible;
            orderedCols.add(remaining.removeAt(idx));
          }
        }
        // Append any new columns not in saved preferences
        orderedCols.addAll(remaining);
        _columns = orderedCols;
        _ensureTravelColumnsBeforeBaseSalary();
        await _saveColumnPreferences();
      }
    } catch (_) {}
  }

  Future<void> _saveColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list =
          _columns.map((c) => {'key': c.key, 'visible': c.visible}).toList();
      await prefs.setString('payroll_columns_v11', jsonEncode(list));
    } catch (_) {}
  }

  @override
  void dispose() {
    _payrollHoveredRow.dispose();
    _searchController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _desktopTableHScrollBody.dispose();
    _desktopTableVScroll.dispose();
    super.dispose();
  }

  /// Dùng cho test: bảng lương đã tính (null khi đang tải).
  @visibleForTesting
  List<Map<String, dynamic>>? debugPayrollRows() => _isLoading ? null : _buildPayrollData();

  bool _isEmployeeRole(BuildContext context) {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole.trim();
    return role.toLowerCase() == 'employee';
  }

  /// Nạp dữ liệu kỳ đang chọn vào bộ tính lương dùng chung.
  Future<void> _loadPayrollData() async {
    setState(() => _isLoading = true);
    _cachedPayrollData = null;
    _serverRows = null;
    _syncEngineContext();
    _engine
      ..fromDate = _fromDate
      ..toDate = _toDate
      ..isEmployeeRole = mounted && _isEmployeeRole(context);
    // Số chính thức do máy chủ tính; dữ liệu chi tiết (chấm công từng ngày, phiếu…) vẫn nạp trên máy.
    final server = _fetchServerRows();
    await _engine.loadPayrollData();
    _configWarnings = _engine.configWarnings();
    await server;
    if (mounted) setState(() => _isLoading = false);
  }

  Widget _configWarningBanner() => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SboxColors.dangerSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SboxColors.danger.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: SboxColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Cấu hình làm sai công'), style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.dangerText)),
              for (final w in _configWarnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr(w), style: const TextStyle(fontSize: 13, color: SboxColors.slate800)),
                ),
            ]),
          ),
        ]),
      );

  /// Lấy bảng lương máy chủ tính cho kỳ đang xem (bỏ kết quả cũ nếu kỳ đã đổi).
  Future<void> _fetchServerRows() async {
    final seq = ++_serverFetchSeq;
    final from = _fromDate, to = _toDate;
    final res = await _apiService.getPayrollSummaryServer(from, to);
    if (!mounted || seq != _serverFetchSeq) return;
    final data = res['data'];
    if (res['isSuccess'] == true && data is Map && data['rows'] is List) {
      _serverRows = [
        for (final r in data['rows'] as List)
          if (r is Map) Map<String, dynamic>.from(r),
      ];
    } else {
      _serverRows = null;
    }
    _cachedPayrollData = null;
  }

  /// Chấm công mới → tính lại trên máy chủ (chạy nền, không chặn màn hình).
  void _refreshServerRowsInBackground() {
    if (_isLoading) return;
    _fetchServerRows().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Màn cha (tháng đang chọn + chấm công đã tải) → bộ tính lương.
  void _syncEngineContext() {
    _engine
      ..parentAttendances = widget.attendances
      ..parentFrom = widget.fromDate
      ..parentTo = widget.toDate;
  }

  // ──────── Build payroll rows ────────
  List<Map<String, dynamic>> _buildPayrollData() {
    if (_cachedPayrollData != null) return _cachedPayrollData!;
    // Số máy chủ tính (chính thức); máy chủ cũ / lỗi → tính trên máy bằng cùng công thức.
    final server = _serverRows;
    final List<Map<String, dynamic>> rows;
    if (server != null) {
      final byId = {for (final e in _engine.employees) e.id: e};
      rows = [
        for (final r in server)
          if (widget.branchId == null ||
              (byId['${r['employeeId']}'] != null &&
                  BranchFilterHelper.inBranch(byId['${r['employeeId']}']!.branchId, widget.branchId)))
            r,
      ];
    } else {
      rows = _engine.computeRows(
        includeEmployee: widget.branchId == null
            ? null
            : (e) => BranchFilterHelper.inBranch(e.branchId, widget.branchId),
      );
    }

    // Sort
    rows.sort((a, b) {
      final aVal = a[_sortColumn];
      final bVal = b[_sortColumn];
      int cmp = 0;
      if (aVal is num && bVal is num) {
        cmp = aVal.compareTo(bVal);
      } else {
        cmp = (aVal?.toString() ?? '').compareTo(bVal?.toString() ?? '');
      }
      return _sortAscending ? cmp : -cmp;
    });

    // Filter
    var result = rows;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = rows.where((r) {
        return (r['code'] as String).toLowerCase().contains(q) ||
            (r['name'] as String).toLowerCase().contains(q) ||
            (r['department'] as String).toLowerCase().contains(q);
      }).toList();
    }

    // Filter by department
    if (_selectedDepartment != null && _selectedDepartment!.isNotEmpty) {
      result = result
          .where((r) => r['department']?.toString() == _selectedDepartment)
          .toList();
    }

    // Filter by selected employees
    if (_selectedEmployeeIds.isNotEmpty) {
      result = result.where((r) {
        final code = r['code']?.toString() ?? '';
        final emp = _engine.findEmployee(code);
        return _selectedEmployeeIds.contains(emp?.id) ||
            _selectedEmployeeIds.contains(code);
      }).toList();
    }

    _cachedPayrollData = result;
    return result;
  }

  List<Employee> _employeesInBranch() {
    if (widget.branchId == null) return _engine.employees;
    return _engine.employees.where((e) => BranchFilterHelper.inBranch(e.branchId, widget.branchId)).toList();
  }

  List<String> _availableDepartments() {
    final depts = _employeesInBranch()
        .map((e) => e.department?.trim())
        .where((d) => d != null && d.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    depts.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return depts;
  }

  /// Nhân viên trong phạm vi lọc (chi nhánh + phòng ban) — dùng cho dialog chọn NV.
  List<Employee> _payrollEmployeePool() {
    var pool = _employeesInBranch();
    if (_selectedDepartment != null && _selectedDepartment!.isNotEmpty) {
      pool = pool.where((e) => e.department == _selectedDepartment).toList();
    }
    pool.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return pool;
  }

  void _pruneEmployeeSelectionToPool() {
    if (_selectedEmployeeIds.isEmpty) return;
    final poolIds = _payrollEmployeePool().map((e) => e.id).toSet();
    _selectedEmployeeIds.removeWhere((id) => !poolIds.contains(id));
  }

  bool _canFinalizePayroll() {
    if (!mounted) return false;
    if (_isEmployeeRole(context)) return false;
    return context.read<PermissionProvider>().canExport('Payroll');
  }

  List<Map<String, dynamic>> _payrollRowsForFinalize({required bool allInTable}) {
    final cached = _cachedPayrollData;
    _cachedPayrollData = null;
    final savedIds = Set<String>.from(_selectedEmployeeIds);
    if (allInTable) _selectedEmployeeIds.clear();
    final rows = List<Map<String, dynamic>>.from(_buildPayrollData());
    _selectedEmployeeIds = savedIds;
    _cachedPayrollData = cached;
    return rows;
  }

  Future<void> _showFinalizePayrollDialog() async {
    final hasSelection = _selectedEmployeeIds.isNotEmpty;
    final selectedCount = hasSelection ? _selectedEmployeeIds.length : 0;
    final allCount = _payrollRowsForFinalize(allInTable: true).length;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Chốt lương')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('${tr('Kỳ: ')}${DateFormat('dd/MM/yyyy').format(_fromDate)} — '
              '${DateFormat('dd/MM/yyyy').format(_toDate)}'),
            ),
            const SizedBox(height: 8),
            Text(tr('Sau khi chốt, hệ thống tạo phiếu lương tại menu Phiếu lương.'),
              style: TextStyle(fontSize: 13, color: SboxColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Hủy')),
          ),
          if (hasSelection)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'selected'),
              child: Text(tr('Chốt $selectedCount NV đã chọn')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: Text(tr('Chốt tất cả ($allCount NV)')),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final rows = choice == 'selected' && hasSelection
        ? _payrollRowsForFinalize(allInTable: false)
        : _payrollRowsForFinalize(allInTable: true);
    if (rows.isEmpty) {
      appNotification.showWarning(
        title: 'Chốt lương',
        message: tr('Không có nhân viên để chốt lương'),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xác nhận chốt lương')),
        content: Text(tr('${tr('Tạo phiếu lương cho ')}${rows.length} nhân viên?\n'
          'Phiếu đã tồn tại cùng kỳ sẽ được cập nhật.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Chốt lương')),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _finalizePayrollRows(rows);
  }

  Future<void> _finalizePayrollRows(List<Map<String, dynamic>> rows) async {
    setState(() => _isFinalizing = true);
    try {
      final skipped = <String>[];
      final ids = <String>[
        for (final r in rows)
          if ((r['employeeId']?.toString() ?? '').isNotEmpty) r['employeeId'].toString(),
      ];
      // Máy chủ tự tính lại số và tạo phiếu — app chỉ gửi kỳ + danh sách nhân viên.
      var res = await _apiService.finalizePayrollServer(from: _fromDate, to: _toDate, employeeIds: ids);
      if (res['statusCode'] == 404) {
        // Máy chủ cũ: gửi số đã tính trên máy (cùng công thức).
        final batch = buildPayrollFinalizeBatch(_engine, rows);
        skipped.addAll(batch.skipped);
        if (batch.items.isEmpty) {
          appNotification.showWarning(
            title: 'Chốt lương',
            message: tr('Không có NV hợp lệ (thiếu hồ sơ hoặc bảng lương)'),
          );
          return;
        }
        res = await _apiService.finalizePayroll(batch.request);
      }

      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = res['data'] as Map<String, dynamic>? ?? {};
        final created = (data['created'] as num?)?.toInt() ?? 0;
        final updated = (data['updated'] as num?)?.toInt() ?? 0;
        final skipCount = (data['skipped'] as num?)?.toInt() ?? 0;
        final serverErrors = (data['errors'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            [];
        var msg = 'Chốt lương: $created mới, $updated cập nhật';
        if (skipCount > 0) msg += ', $skipCount bỏ qua';
        final warnings = (data['warnings'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
        final payslipIds = (data['payslipIds'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
        if (warnings.isNotEmpty) msg += '\n${warnings.take(3).join('\n')}';
        if (skipped.isNotEmpty) {
          msg += '\n${skipped.length} NV thiếu hồ sơ/bảng lương (phía app)';
        }
        if (serverErrors.isNotEmpty) {
          msg += '\n${serverErrors.take(3).join('\n')}';
        }
        appNotification.showSuccess(title: 'Chốt lương', message: msg);
        if (payslipIds.isNotEmpty && mounted) {
          final payNow = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(tr('Đã chốt ${payslipIds.length} phiếu lương')),
              content: Text(tr('Trả lương ngay? Có thể trả tiền mặt, chuyển khoản, kết hợp hoặc xuất file chuyển lương cho ngân hàng.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Để sau'))),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(tr('Trả lương')),
                ),
              ],
            ),
          );
          if (payNow == true && mounted) await openPayrollPay(context, payslipIds);
        }
      } else {
        final data = res['data'] as Map<String, dynamic>? ?? {};
        final serverErrors = (data['errors'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            [];
        var msg = res['message']?.toString() ?? 'Chốt lương thất bại';
        if (serverErrors.isNotEmpty) {
          msg += '\n${serverErrors.take(3).join('\n')}';
        }
        appNotification.showError(title: 'Chốt lương', message: msg);
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Chốt lương',
          message: tr('Lỗi: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  Widget _buildFinalizeButton() {
    if (!_canFinalizePayroll()) return const SizedBox.shrink();
    return FilledButton.icon(
      onPressed: _isFinalizing ? null : _showFinalizePayrollDialog,
      icon: _isFinalizing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.lock_outline, size: 18),
      label: Text(tr(_isFinalizing ? 'Đang chốt...' : 'Chốt lương')),
      style: FilledButton.styleFrom(
        backgroundColor: SboxColors.success,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  // ──────── Public methods (called from PayrollScreen AppBar) ────────

  void showColumnSelectorDialog() {
    // Work on a temporary copy of columns so we can reorder without affecting state until apply
    var tempColumns = _columns
        .map((c) => PayrollColumn(
              key: c.key,
              label: c.label,
              defaultVisible: c.defaultVisible,
              visible: c.visible,
            ))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          // Exclude frozen columns from reordering
          final reorderableCols =
              tempColumns.where((c) => !_frozenKeys.contains(c.key)).toList();

          return ScrollableAlertDialog(
            title: Row(
              children: [
                const Icon(Icons.view_column, color: SboxColors.brand500),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr('Chọn & sắp xếp cột'),
                        style: TextStyle(fontSize: 16))),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      tempColumns = _defaultPayrollColumns()
                          .map((c) => PayrollColumn(
                                key: c.key,
                                label: c.label,
                                defaultVisible: c.defaultVisible,
                                visible: c.defaultVisible,
                              ))
                          .toList();
                    });
                  },
                  child: Text(tr('Mặc định'), style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            content: SizedBox(
              width: math
                  .min(460, MediaQuery.of(context).size.width - 32)
                  .toDouble(),
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Frozen columns (not reorderable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(tr('Cột cố định (không thể di chuyển)'),
                        style: TextStyle(
                            fontSize: 11, color: SboxColors.slate500)),
                  ),
                  ...tempColumns.where((c) => _frozenKeys.contains(c.key)).map(
                        (col) => Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: SboxColors.slate100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 14, color: SboxColors.slate400),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(tr(col.label),
                                      style: const TextStyle(
                                          fontSize: 13, color: SboxColors.slate500))),
                            ],
                          ),
                        ),
                      ),
                  const Divider(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(tr('Kéo để sắp xếp thứ tự cột'),
                        style: TextStyle(
                            fontSize: 11, color: SboxColors.slate500)),
                  ),
                  // Reorderable columns
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: reorderableCols.length,
                      onReorder: (oldIndex, newIndex) {
                        setDialogState(() {
                          if (newIndex > oldIndex) newIndex--;
                          // Find in tempColumns (skip frozen ones)
                          final nonFrozen = tempColumns
                              .where((c) => !_frozenKeys.contains(c.key))
                              .toList();
                          final item = nonFrozen.removeAt(oldIndex);
                          nonFrozen.insert(newIndex, item);
                          // Rebuild tempColumns: frozen first, then reordered non-frozen
                          final frozen = tempColumns
                              .where((c) => _frozenKeys.contains(c.key))
                              .toList();
                          tempColumns = [...frozen, ...nonFrozen];
                        });
                      },
                      itemBuilder: (_, i) {
                        final col = reorderableCols[i];
                        return Container(
                          key: ValueKey(col.key),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: col.visible
                                ? SboxColors.brand50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: col.visible
                                  ? SboxColors.brand200
                                  : SboxColors.slate200,
                              width: 0.5,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.only(left: 8, right: 0),
                            leading: Checkbox(
                              value: col.visible,
                              onChanged: (v) =>
                                  setDialogState(() => col.visible = v ?? true),
                              visualDensity: VisualDensity.compact,
                            ),
                            title: Text(tr(col.label),
                                style: const TextStyle(fontSize: 13)),
                            trailing: ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Icon(Icons.drag_handle,
                                    size: 18, color: SboxColors.slate400),
                              ),
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
                child: Text(tr('Hủy')),
              ),
              FilledButton(
                onPressed: () {
                  // Apply order and visibility from tempColumns
                  _columns = tempColumns.map((t) {
                    final orig = _columns.firstWhere((c) => c.key == t.key,
                        orElse: () => t);
                    orig.visible = t.visible;
                    return orig;
                  }).toList();
                  _saveColumnPreferences();
                  _cachedPayrollData = null;
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: Text(tr('Áp dụng')),
              ),
            ],
          );
        },
      ),
    );
  }

  void _excelMergedText(
    excel_lib.Sheet sheet, {
    required int row,
    required int colStart,
    required int colEnd,
    required String text,
    excel_lib.CellStyle? style,
  }) {
    final cell = sheet.cell(
      excel_lib.CellIndex.indexByColumnRow(
          columnIndex: colStart, rowIndex: row),
    );
    cell.value = excel_lib.TextCellValue(text);
    if (style != null) cell.cellStyle = style;
    if (colEnd > colStart) {
      sheet.merge(
        excel_lib.CellIndex.indexByColumnRow(
            columnIndex: colStart, rowIndex: row),
        excel_lib.CellIndex.indexByColumnRow(columnIndex: colEnd, rowIndex: row),
      );
    }
  }

  void _excelSetCell(
    excel_lib.Sheet sheet,
    int row,
    int col,
    excel_lib.CellValue value, {
    excel_lib.CellStyle? style,
  }) {
    final cell = sheet.cell(
      excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = value;
    if (style != null) cell.cellStyle = style;
  }

  excel_lib.CellStyle _excelCenterStyle({
    bool bold = false,
    int fontSize = 11,
    String? backgroundHex,
    bool italic = false,
    excel_lib.NumFormat? numberFormat,
  }) {
    return excel_lib.CellStyle(
      bold: bold,
      italic: italic,
      fontSize: fontSize,
      horizontalAlign: excel_lib.HorizontalAlign.Center,
      verticalAlign: excel_lib.VerticalAlign.Center,
      backgroundColorHex: backgroundHex != null
          ? excel_lib.ExcelColor.fromHexString(backgroundHex)
          : excel_lib.ExcelColor.none,
      numberFormat: numberFormat ?? excel_lib.NumFormat.standard_0,
    );
  }

  excel_lib.CellStyle _excelLeftStyle({int fontSize = 11}) {
    return excel_lib.CellStyle(
      fontSize: fontSize,
      horizontalAlign: excel_lib.HorizontalAlign.Left,
      verticalAlign: excel_lib.VerticalAlign.Center,
    );
  }

  void _excelWritePayrollSignatures(
    excel_lib.Sheet sheet, {
    required int row,
    required int colCount,
  }) {
    final sigTitleStyle = _excelCenterStyle(bold: true);
    final sigHintStyle = _excelCenterStyle(fontSize: 10, italic: true);
    final part = (colCount / _payrollFooterSignatureLabels.length)
        .floor()
        .clamp(1, colCount);
    for (var i = 0; i < _payrollFooterSignatureLabels.length; i++) {
      final start = i * part;
      final end = i == _payrollFooterSignatureLabels.length - 1
          ? colCount - 1
          : math.min((i + 1) * part - 1, colCount - 1);
      _excelMergedText(
        sheet,
        row: row,
        colStart: start,
        colEnd: end,
        text: tr(_payrollFooterSignatureLabels[i]),
        style: sigTitleStyle,
      );
    }
    row += 2;
    for (var i = 0; i < _payrollFooterSignatureLabels.length; i++) {
      final start = i * part;
      final end = i == _payrollFooterSignatureLabels.length - 1
          ? colCount - 1
          : math.min((i + 1) * part - 1, colCount - 1);
      _excelMergedText(
        sheet,
        row: row,
        colStart: start,
        colEnd: end,
        text: tr('(Ký, ghi rõ họ tên)'),
        style: sigHintStyle,
      );
    }
  }

  void exportToExcel() async {
    try {
      final data = _buildPayrollData();
      if (data.isEmpty) {
        appNotification.showError(
            title: 'Lỗi', message: tr('Không có dữ liệu để xuất'));
        return;
      }

      final visibleCols = _visiblePayrollColumns(data);
      final colCount = visibleCols.length;
      final fit = _excelPayrollFit(visibleCols, data);
      final bodyFont = fit.font;
      final wb = ExcelReportBuilder.createWorkbook(sheetName: 'Tổng hợp lương');
      final sheet = wb['Tổng hợp lương'];
      sheet.setDefaultRowHeight(15);
      final headerStyle = excel_lib.CellStyle(
        bold: true,
        fontSize: bodyFont,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#6366F1'),
        fontColorHex: excel_lib.ExcelColor.white,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        verticalAlign: excel_lib.VerticalAlign.Center,
        textWrapping: excel_lib.TextWrapping.WrapText,
      );
      final leftStyle = _excelLeftStyle(fontSize: bodyFont);
      final totalStyle = _excelCenterStyle(
        bold: true,
        fontSize: bodyFont,
        backgroundHex: '#EFF6FF',
        numberFormat: excel_lib.NumFormat.standard_49,
      );
      for (var i = 0; i < fit.widths.length; i++) {
        sheet.setColumnWidth(i, fit.widths[i]);
      }

      var row = 0;
      final lastCol = colCount - 1;
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text: tr('BẢNG TỔNG HỢP LƯƠNG'),
        style: _excelCenterStyle(bold: true, fontSize: bodyFont + 4),
      );
      row++;
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text:
            tr('Kỳ lương: ${DateFormat('dd/MM/yyyy').format(_fromDate)} – ${DateFormat('dd/MM/yyyy').format(_toDate)}'),
        style: _excelCenterStyle(fontSize: bodyFont + 1),
      );
      row++;
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text:
            tr('Xuất lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}  |  ${data.length} nhân viên'),
        style: _excelCenterStyle(fontSize: bodyFont, italic: true),
      );
      row++;
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text: 'CB: cơ bản    HT: hoàn thành    TC: tăng ca    PC: phụ cấp',
        style: _excelCenterStyle(fontSize: math.max(6, bodyFont - 1), italic: true),
      );
      row++;

      final headerRow = row;
      ExcelReportBuilder.applyHeaderRow(
        sheet,
        headerRow,
        visibleCols
            .map((c) => _excelPayrollHeader(c.key, c.label))
            .toList(),
        style: headerStyle,
      );
      sheet.setRowHeight(headerRow, bodyFont * 2 + 14);
      row++;

      final firstDataRow = row;
      final signStyle = _excelCenterStyle(fontSize: bodyFont);
      for (var i = 0; i < data.length; i++) {
        final emp = data[i];
        for (var c = 0; c < visibleCols.length; c++) {
          final col = visibleCols[c];
          if (col.key == _employeeSignColumnKey) {
            _excelSetCell(
              sheet,
              row,
              c,
              excel_lib.TextCellValue(''),
              style: signStyle,
            );
          } else {
            final value = _excelCellValue(col.key, emp, i);
            _excelSetCell(
              sheet,
              row,
              c,
              value,
              style: _isPayrollLeftAlignKey(col.key)
                  ? leftStyle
                  : _excelNumericStyle(col.key, value, fontSize: bodyFont),
            );
          }
        }
        sheet.setRowHeight(row, 15);
        row++;
      }
      final lastDataRow = row - 1;
      final totalRow = row;

      for (var c = 0; c < visibleCols.length; c++) {
        final col = visibleCols[c];
        if (col.key == 'stt') {
          _excelSetCell(sheet, totalRow, c, excel_lib.TextCellValue(''),
              style: totalStyle);
        } else if (col.key == 'name') {
          _excelSetCell(sheet, totalRow, c,
              excel_lib.TextCellValue('TỔNG CỘNG'), style: totalStyle);
        } else if (col.key == 'code') {
          _excelSetCell(sheet, totalRow, c,
              excel_lib.TextCellValue('${data.length} NV'), style: totalStyle);
        } else if (col.key == _employeeSignColumnKey) {
          _excelSetCell(sheet, totalRow, c, excel_lib.TextCellValue(''),
              style: totalStyle);
        } else if (_isPayrollNumericKey(col.key) && lastDataRow >= firstDataRow) {
          final totalValue = _excelTotalCellValue(col.key, data);
          _excelSetCell(
            sheet,
            totalRow,
            c,
            totalValue,
            style: _excelNumericStyle(
              col.key,
              totalValue,
              bold: true,
              fontSize: bodyFont,
              backgroundHex: '#EFF6FF',
            ),
          );
        } else {
          _excelSetCell(sheet, totalRow, c, excel_lib.TextCellValue(''),
              style: totalStyle);
        }
      }

      sheet.setRowHeight(totalRow, 15);
      row = totalRow + 2;
      _excelWritePayrollSignatures(sheet, row: row, colCount: colCount);

      final encoded = wb.encode();
      final pagesTall = math.max(1, (data.length / 32).ceil());
      final bytes = encoded == null
          ? null
          : ExcelReportBuilder.fitSheetToA4Landscape(
              encoded,
              pagesTall: pagesTall,
            );
      if (bytes != null) {
        final fn =
            'Bang_tong_hop_luong_${DateFormat('ddMMyyyy').format(_fromDate)}_${DateFormat('ddMMyyyy').format(_toDate)}.xlsx';
        await file_saver.saveAndOpenFileBytes(
            bytes,
            fn,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(
            title: 'Xuất Excel',
            message: tr('Đã lưu $fn. Mở Báo cáo → Quản lý tài liệu tải xuống'));
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
    }
  }

  excel_lib.CellValue _excelCellValue(
      String key, Map<String, dynamic> row, int index) {
    switch (key) {
      case 'stt':
        return excel_lib.IntCellValue(index + 1);
      case 'code':
      case 'name':
      case 'department':
      case 'position':
      case 'salaryType':
        return excel_lib.TextCellValue(row[key]?.toString() ?? '');
      case _employeeSignColumnKey:
        return excel_lib.TextCellValue('');
      case 'workDays':
      case 'paidLeaveDays':
      case 'lateCount':
      case 'earlyCount':
      case 'lateMinutes':
      case 'earlyMinutes':
      case 'absentDays':
        return excel_lib.IntCellValue((row[key] as num?)?.toInt() ?? 0);
      case 'standardDays':
        return _excelDayValue((row[key] as num?)?.toDouble() ?? 0);
      default:
        return _excelMeasureCell(key, (row[key] as num?)?.toDouble() ?? 0);
    }
  }

  static const _payrollHourKeys = {
    'totalHours',
    'standardHours',
    'otTotalHours',
    'travelHours',
    'otHoursWeekday',
    'otHoursWeekend',
    'otHoursHoliday',
  };

  static const _payrollDeductionKeys = {
    'penalty',
    'bhxh',
    'bhyt',
    'bhtn',
    'unionFee',
    'totalInsurance',
    'pit',
  };

  excel_lib.CellValue _excelDayValue(double value) {
    if (value == value.roundToDouble()) {
      return excel_lib.IntCellValue(value.toInt());
    }
    return excel_lib.DoubleCellValue(double.parse(value.toStringAsFixed(1)));
  }

  excel_lib.CellValue _excelMeasureCell(String key, double value) {
    if (_payrollHourKeys.contains(key)) {
      return excel_lib.DoubleCellValue(double.parse(value.toStringAsFixed(1)));
    }
    if (_payrollDeductionKeys.contains(key)) {
      if (value == 0) return excel_lib.IntCellValue(0);
      return excel_lib.IntCellValue(-value.round());
    }
    return excel_lib.IntCellValue(value.round());
  }

  excel_lib.NumFormat _excelNumberFormat(
      String key, excel_lib.CellValue value) {
    if (_payrollHourKeys.contains(key) || value is excel_lib.DoubleCellValue) {
      // numFmtId 48 của Excel là ##0.0E+0 (dạng khoa học), không phải 1 chữ số thập phân.
      return excel_lib.NumFormat.custom(formatCode: '0.0');
    }
    if (_payrollDeductionKeys.contains(key) || _isPayrollMoneyKey(key)) {
      return excel_lib.NumFormat.standard_3;
    }
    return excel_lib.NumFormat.standard_1;
  }

  excel_lib.CellStyle _excelNumericStyle(
    String key,
    excel_lib.CellValue value, {
    bool bold = false,
    int fontSize = 11,
    String? backgroundHex,
  }) {
    return _excelCenterStyle(
      bold: bold,
      fontSize: fontSize,
      backgroundHex: backgroundHex,
      numberFormat: _excelNumberFormat(key, value),
    );
  }

  excel_lib.CellValue _excelTotalCellValue(
      String key, List<Map<String, dynamic>> data) {
    final total = data.fold<double>(
        0, (s, r) => s + ((r[key] as num?) ?? 0).toDouble());
    if (key == 'standardDays' ||
        key == 'workDays' ||
        key == 'paidLeaveDays' ||
        key == 'absentDays' ||
        key == 'lateCount' ||
        key == 'earlyCount' ||
        key == 'lateMinutes' ||
        key == 'earlyMinutes') {
      return _excelDayValue(total);
    }
    return _excelMeasureCell(key, total);
  }

  bool _isPayrollMoneyKey(String key) {
    return _isPayrollNumericKey(key) &&
        !_payrollHourKeys.contains(key) &&
        !_payrollDeductionKeys.contains(key) &&
        key != 'standardDays' &&
        key != 'workDays' &&
        key != 'paidLeaveDays' &&
        key != 'absentDays' &&
        key != 'lateCount' &&
        key != 'earlyCount' &&
        key != 'lateMinutes' &&
        key != 'earlyMinutes';
  }

  /// Tiêu đề Excel: xuống dòng, viết tắt chỗ tên dài hơn bề rộng cột số.
  static const _excelPayrollHeaderByKey = <String, String>{
    'stt': 'STT',
    'name': 'Họ tên',
    'code': 'Mã\nNV',
    'department': 'Phòng\nban',
    'position': 'Chức\nvụ',
    'salaryType': 'Loại\nlương',
    'standardDays': 'Công\nchuẩn',
    'workDays': 'Tổng\ncông',
    'totalHours': 'Tổng\ngiờ',
    'otTotalHours': 'Giờ\nTC',
    'travelHours': 'Giờ\nđi đường',
    'travelSalary': 'Lương\nđi đường',
    'baseSalary': 'Lương\nCB',
    'workSalary': 'Lương\ncông',
    'completionSalary': 'Lương\nHT',
    'dailySalary': 'Lương\nngày',
    'shiftSalary': 'Lương\nca',
    'hourlySalary': 'Lương\ngiờ',
    'otSalary': 'Lương\nTC',
    'allowanceFixed': 'PC\ncố định',
    'allowanceDaily': 'PC\ntheo ngày',
    'allowanceShift': 'PC\ntheo ca',
    'allowanceQualified': 'Ngày/ca\nđủ ĐK PC',
    'totalAllowance': 'Tổng\nPC',
    'bonus': 'Thưởng',
    'kpiSalary': 'Lương\nKPI',
    'productionAmount': 'Sản\nlượng',
    'leavePayout': 'Tiền\nphép',
    'totalSalary': 'Tổng\nlương',
    'penalty': 'Phạt',
    'bhxh': 'BHXH',
    'bhyt': 'BHYT',
    'bhtn': 'BHTN',
    'unionFee': 'Phí\nCĐ',
    'totalInsurance': 'Tổng\nBH',
    'pit': 'TNCN',
    'advance': 'Ứng\nlương',
    'netSalary': 'Thực\nnhận',
    'employeeSign': 'Ký\ntên',
  };

  String _excelPayrollHeader(String key, String label) {
    final preset = _excelPayrollHeaderByKey[key];
    if (preset != null) return preset;
    final words = label.trim().split(RegExp(r'\s+'));
    if (words.length < 2 || label.length <= 8) return label;
    var best = 1;
    var bestDiff = 1 << 30;
    var leftLen = 0;
    for (var i = 0; i < words.length - 1; i++) {
      leftLen += words[i].length + (i == 0 ? 0 : 1);
      final rightLen = label.length - leftLen - 1;
      final diff = (leftLen - rightLen).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i + 1;
      }
    }
    return '${words.take(best).join(' ')}\n${words.skip(best).join(' ')}';
  }

  /// Cỡ chữ và bề rộng cột để cả bảng vừa khổ A4 ngang, số không bị ######.
  ({int font, List<double> widths}) _excelPayrollFit(
    List<PayrollColumn> cols,
    List<Map<String, dynamic>> data,
  ) {
    final totals = _pngPayrollTotalCells(data, cols);
    final chars = <int>[];
    for (var c = 0; c < cols.length; c++) {
      final col = cols[c];
      var longest = 1;
      for (var i = 0; i < data.length; i++) {
        final text = _pngPayrollCellText(col.key, data[i], i);
        if (text.length > longest) longest = text.length;
      }
      if (c < totals.length && totals[c].length > longest) {
        longest = totals[c].length;
      }
      final header = _excelPayrollHeader(col.key, col.label);
      var headerNeed = 1;
      for (final line in header.split('\n')) {
        if (line.length > headerNeed) headerNeed = line.length;
      }
      headerNeed = headerNeed.clamp(3, 12);
      final textCol = _isPayrollLeftAlignKey(col.key) ||
          col.key == 'stt' ||
          col.key == _employeeSignColumnKey;
      final valueNeed = textCol ? longest.clamp(3, 16) : longest.clamp(3, 14);
      chars.add(math.max(headerNeed, valueNeed));
    }
    const budget = 145.0;
    double widthSum(int font) {
      final scale = font / 11.0;
      var sum = 0.0;
      for (final n in chars) {
        sum += n * scale + 1.1;
      }
      return sum;
    }

    var font = 10;
    while (font > 6 && widthSum(font) > budget) {
      font--;
    }
    final scale = font / 11.0;
    final raw = [for (final n in chars) n * scale + 1.1];
    final sum = raw.fold<double>(0, (a, b) => a + b);
    final fitScale = sum <= 0 ? 1.0 : budget / sum;
    return (
      font: font,
      widths: [for (final w in raw) w * fitScale],
    );
  }

  String _pngPayrollCellText(String key, Map<String, dynamic> row, int index) {
    if (key == 'stt') return '${index + 1}';
    if (key == _employeeSignColumnKey) return '';
    return _formatCellValue(key, row, index);
  }

  List<String> _pngPayrollTotalCells(
    List<Map<String, dynamic>> data,
    List<PayrollColumn> visibleCols,
  ) {
    return visibleCols.map((col) {
      if (col.key == 'stt') return '';
      if (col.key == 'name') return 'TỔNG CỘNG';
      if (col.key == 'code') return '${data.length} NV';
      if (!_isPayrollNumericKey(col.key)) return '';
      final total = data.fold<double>(
          0, (s, r) => s + ((r[col.key] as num?) ?? 0).toDouble());
      if (total == 0) return '';
      if (col.key == 'penalty' ||
          col.key == 'bhxh' ||
          col.key == 'totalInsurance' ||
          col.key == 'pit') {
        return '-${_currencyFmt.format(total.round())}';
      }
      if (col.key == 'totalHours' || col.key == 'otTotalHours') {
        return total.toStringAsFixed(1);
      }
      if (col.key == 'workDays' ||
          col.key == 'standardDays' ||
          col.key == 'lateCount' ||
          col.key == 'earlyCount') {
        return total == total.roundToDouble()
            ? '${total.toInt()}'
            : total.toStringAsFixed(1);
      }
      return _currencyFmt.format(total.round());
    }).toList();
  }

  static const double _pngPad = 12.0;

  void _pngDrawPayrollExport(
    dynamic ctx, {
    required double width,
    required double height,
    required List<Map<String, dynamic>> data,
    required List<PayrollColumn> visibleCols,
    required List<double> colWidths,
    required double tableWidth,
    required double fontPx,
  }) {
    final rowH = 16 + fontPx;
    final headerH = 20 + fontPx;
    const titleH = 34.0;
    const periodH = 26.0;
    const gap = 10.0;
    const sigBlockH = 88.0;
    const pad = _pngPad;
    final cellFont = '${fontPx.round()}px Arial, sans-serif';
    final cellFontBold = 'bold ${fontPx.round()}px Arial, sans-serif';

    final headers = visibleCols.map((c) => c.label).toList();
    final tableLeft = pad;

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, width, height);

    var y = pad;
    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 16px Arial, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('BẢNG TỔNG HỢP LƯƠNG', width / 2, y + 20);
    y += titleH;
    ctx.fillStyle = '#334155';
    ctx.font = '12px Arial, sans-serif';
    ctx.fillText('${tr('Kỳ lương: ')}${DateFormat('dd/MM/yyyy').format(_fromDate)} – ${DateFormat('dd/MM/yyyy').format(_toDate)}',
      width / 2,
      y + 16,
    );
    y += periodH + gap;

    final tableTop = y;
    ctx.fillStyle = '#6366F1';
    ctx.fillRect(tableLeft, tableTop, tableWidth, headerH);
    var x = tableLeft;
    for (var c = 0; c < headers.length; c++) {
      ctx.fillStyle = '#FFFFFF';
      ctx.font = cellFontBold;
      ctx.textAlign = 'center';
      ctx.fillText(headers[c], x + colWidths[c] / 2, tableTop + headerH / 2 + 5);
      x += colWidths[c];
    }
    y += headerH;

    for (var ri = 0; ri < data.length; ri++) {
      if (ri.isOdd) {
        ctx.fillStyle = '#F8FAFC';
        ctx.fillRect(tableLeft, y, tableWidth, rowH);
      }
      x = tableLeft;
      for (var c = 0; c < visibleCols.length; c++) {
        final col = visibleCols[c];
        final text = _pngPayrollCellText(col.key, data[ri], ri);
        String fillColor = '#334155';
        if (col.key == 'netSalary') {
          fillColor = '#1D4ED8';
        } else if (col.key == 'totalSalary') {
          fillColor = '#15803D';
        } else if (col.key == 'penalty' ||
            col.key == 'totalInsurance' ||
            col.key == 'pit') {
          final v = (data[ri][col.key] as num?)?.toDouble() ?? 0;
          if (v > 0) fillColor = '#DC2626';
        } else if (col.key == 'bonus') {
          final v = (data[ri][col.key] as num?)?.toDouble() ?? 0;
          if (v > 0) fillColor = '#15803D';
        }
        ctx.fillStyle = fillColor;
        ctx.font = cellFont;
        if (_isPayrollLeftAlignKey(col.key)) {
          ctx.textAlign = 'left';
          ctx.fillText(text, x + 6, y + rowH / 2 + 5);
        } else {
          ctx.textAlign = 'center';
          ctx.fillText(text, x + colWidths[c] / 2, y + rowH / 2 + 5);
        }
        x += colWidths[c];
      }
      ctx.strokeStyle = '#E2E8F0';
      ctx.beginPath();
      ctx.moveTo(tableLeft, y + rowH);
      ctx.lineTo(tableLeft + tableWidth, y + rowH);
      ctx.stroke();
      y += rowH;
    }

    final totalCells = _pngPayrollTotalCells(data, visibleCols);
    ctx.fillStyle = '#EFF6FF';
    ctx.fillRect(tableLeft, y, tableWidth, rowH + 2);
    x = tableLeft;
    for (var c = 0; c < totalCells.length; c++) {
      ctx.fillStyle = '#1D4ED8';
      ctx.font = cellFontBold;
      ctx.textAlign = 'center';
      ctx.fillText(totalCells[c], x + colWidths[c] / 2, y + rowH / 2 + 5);
      x += colWidths[c];
    }
    y += rowH + gap;

    final sigW = tableWidth / _payrollFooterSignatureLabels.length;
    for (var si = 0; si < _payrollFooterSignatureLabels.length; si++) {
      final cx = tableLeft + sigW * si + sigW / 2;
      ctx.fillStyle = '#0F172A';
      ctx.font = cellFontBold;
      ctx.textAlign = 'center';
      ctx.fillText(_payrollFooterSignatureLabels[si], cx, y + 14);
    }
    y += 52;
    for (var si = 0; si < _payrollFooterSignatureLabels.length; si++) {
      final cx = tableLeft + sigW * si + sigW / 2;
      ctx.fillStyle = '#71717A';
      ctx.font = 'italic 10px Arial, sans-serif';
      ctx.fillText('(Ký, ghi rõ họ tên)', cx, y + 12);
    }
    y += sigBlockH - 52;

    ctx.strokeStyle = '#CBD5E1';
    ctx.lineWidth = 1;
    ctx.strokeRect(tableLeft, tableTop, tableWidth, y - tableTop);
    ctx.textAlign = 'left';
  }

  Future<void> exportToPng() async {
    try {
      final data = _buildPayrollData();
      if (data.isEmpty) {
        appNotification.showError(
            title: 'Lỗi', message: tr('Không có dữ liệu để xuất'));
        return;
      }

      final visibleCols = _visiblePayrollColumns(data);
      final sampleRows = <List<String>>[];
      for (var i = 0; i < data.length; i++) {
        sampleRows.add(visibleCols
            .map((c) => _pngPayrollCellText(c.key, data[i], i))
            .toList());
      }
      sampleRows.add(_pngPayrollTotalCells(data, visibleCols));

      final rawColWidths = <double>[];
      for (var c = 0; c < visibleCols.length; c++) {
        var w = visibleCols[c].label.length * 7.2 + 16;
        for (final row in sampleRows) {
          if (c < row.length) {
            final cw = row[c].length * 6.6 + 14;
            if (cw > w) w = cw;
          }
        }
        final cap = math.max(40.0, w);
        rawColWidths.add(w.clamp(40.0, cap));
      }
      final naturalTableW = rawColWidths.fold<double>(0, (s, w) => s + w);
      const maxTableW = 2200.0;
      final fittedTableW = naturalTableW.clamp(960.0, maxTableW);
      final scale = naturalTableW <= 0 ? 1.0 : fittedTableW / naturalTableW;
      final fontPx = (11.0 * math.min(1.0, scale)).clamp(6.0, 11.0);
      final colWidths = rawColWidths.map((w) => w * scale).toList();
      final totalWidth = fittedTableW + 2 * _pngPad;
      final tableWidth = fittedTableW;

      final rowH = 16 + fontPx;
      final headerH = 20 + fontPx;
      const titleH = 34.0;
      const periodH = 26.0;
      const gap = 10.0;
      const sigBlockH = 88.0;
      final totalHeight = _pngPad +
          titleH +
          periodH +
          gap +
          headerH +
          data.length * rowH +
          rowH +
          gap +
          sigBlockH +
          _pngPad +
          16;

      void drawCanvas(dynamic ctx) => _pngDrawPayrollExport(
            ctx,
            width: totalWidth,
            height: totalHeight,
            data: data,
            visibleCols: visibleCols,
            colWidths: colWidths,
            tableWidth: tableWidth,
            fontPx: fontPx,
          );

      final fileName =
          'Bang_tong_hop_luong_${DateFormat('ddMMyyyy').format(_fromDate)}_${DateFormat('ddMMyyyy').format(_toDate)}.png';

      final dataUrl = web_canvas.renderToPngDataUrl(
        width: totalWidth.toInt(),
        height: totalHeight.toInt(),
        draw: drawCanvas,
      );

      if (dataUrl != null) {
        await file_saver.saveAndOpenDataUrl(dataUrl, fileName);
      } else {
        final pngBytes = await web_canvas.renderToPngBytes(
          width: totalWidth.toInt(),
          height: totalHeight.toInt(),
          draw: drawCanvas,
        );
        if (pngBytes != null) {
          await file_saver.saveAndOpenFileBytes(
              pngBytes, fileName, 'image/png');
        } else {
          appNotification.showError(
              title: 'Lỗi', message: tr('Không thể xuất PNG'));
          return;
        }
      }
      appNotification.showSuccess(
          title: 'Xuất PNG',
          message: tr('Đã lưu $fileName. Mở Báo cáo → Quản lý tài liệu tải xuống'));
    } catch (e) {
      appNotification.showError(title: 'Lỗi', message: tr('Không thể xuất PNG: $e'));
    }
  }

  // ──────── Date range / period ────────
  void _setPeriod(String period) {
    final now = DateTime.now();
    setState(() {
      _selectedPeriod = period;
      _cachedPayrollData = null;
      _currentPage = 1;
      switch (period) {
        case 'thisMonth':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = now;
          break;
        case 'lastMonth':
          final firstThis = DateTime(now.year, now.month, 1);
          final lastDayPrev = firstThis.subtract(const Duration(days: 1));
          _fromDate = DateTime(lastDayPrev.year, lastDayPrev.month, 1);
          _toDate = DateTime(lastDayPrev.year, lastDayPrev.month,
              lastDayPrev.day, 23, 59, 59);
          break;
        case 'thisWeek':
          // Monday of current week
          final weekday = now.weekday; // 1=Mon, 7=Sun
          _fromDate = now.subtract(Duration(days: weekday - 1));
          _fromDate = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
          _toDate = now;
          break;
        case 'lastWeek':
          final weekday = now.weekday;
          final thisMonday = now.subtract(Duration(days: weekday - 1));
          _fromDate = thisMonday.subtract(const Duration(days: 7));
          _fromDate = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
          _toDate = thisMonday.subtract(const Duration(days: 1));
          _toDate =
              DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
          break;
        case 'today':
          _fromDate = DateTime(now.year, now.month, now.day);
          _toDate = now;
          break;
        case 'yesterday':
          final yd = now.subtract(const Duration(days: 1));
          _fromDate = DateTime(yd.year, yd.month, yd.day);
          _toDate = DateTime(yd.year, yd.month, yd.day, 23, 59, 59);
          break;
        case 'custom':
          break;
      }
    });
    if (period != 'custom') {
      _loadPayrollData();
    }
  }

  Future<void> _pickSingleDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: appUiLocale(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_fromDate.isAfter(_toDate)) {
            _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
          }
        } else {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
          if (_toDate.isBefore(_fromDate)) {
            _fromDate = DateTime(picked.year, picked.month, picked.day);
          }
        }
        _selectedPeriod = 'custom';
        _cachedPayrollData = null;
        _currentPage = 1;
      });
      _loadPayrollData();
    }
  }

  // ──────── Employee detail dialog ────────
  void _showEmployeeDetail(Map<String, dynamic> row) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleRow = Row(
      children: [
        CircleAvatar(
          backgroundColor: SboxColors.brand100,
          child: Text(
            tr((row['name'] as String).isNotEmpty
                ? (row['name'] as String)[0].toUpperCase()
                : '?'),
            style: TextStyle(
                color: SboxColors.brand700, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(row['name'] ?? ''), style: const TextStyle(fontSize: 16)),
              Text(tr('${row['code']} • ${row['department']}'),
                  style: TextStyle(fontSize: 12, color: SboxColors.slate600)),
            ],
          ),
        ),
      ],
    );

    final contentBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('Chấm công', [
          _detailRow('Tổng công', '${row['workDays']}'),
          _detailRow('Công chuẩn', '${row['standardDays']}'),
          _detailRow('Ngày phép', '${row['paidLeaveDays']}'),
          _detailRow('Ngày vắng', '${row['absentDays']} ngày'),
          _detailRow(
              'Tổng giờ', '${(row['totalHours'] as num).toStringAsFixed(1)}h'),
          _detailRow('Giờ chuẩn',
              '${(row['standardHours'] as num).toStringAsFixed(1)}h'),
          _detailRow(
              'Tăng ca', '${(row['otTotalHours'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca ngày thường',
              '${(row['otHoursWeekday'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca cuối tuần',
              '${(row['otHoursWeekend'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca ngày lễ',
              '${(row['otHoursHoliday'] as num).toStringAsFixed(1)}h'),
          if (_engine.showTravelPayrollColumns)
            _detailRow(
                'Đi đường',
                '${(row['travelHours'] as num?)?.toStringAsFixed(1) ?? '0'}h'),
          _detailRow(
              'Đi trễ', '${row['lateCount']} lần (${row['lateMinutes']} phút)'),
          _detailRow('Về sớm',
              '${row['earlyCount']} lần (${row['earlyMinutes']} phút)'),
        ]),
        _detailSection('Thu nhập', [
          _detailRow('Loại lương', row['salaryType']),
          _detailRow('Lương cơ bản', _fmtCurrency(row['baseSalary'])),
          _detailRow('Lương theo công', _fmtCurrency(row['workSalary'])),
          _detailRow(
              'Lương hoàn thành (mức tháng)',
              _fmtCurrency(row['completionSalaryConfigured'] ??
                  row['completionSalary'])),
          _detailRow('Lương HT theo công',
              _fmtCurrency(row['completionSalaryEarned'])),
          _detailRow('Lương theo ngày', _fmtCurrency(row['dailySalary'])),
          _detailRow('Lương theo ca', _fmtCurrency(row['shiftSalary'])),
          _detailRow('Lương theo giờ', _fmtCurrency(row['hourlySalary'])),
          _detailRow('Lương tăng ca', _fmtCurrency(row['otSalary'])),
          if (_engine.showTravelPayrollColumns)
            _detailRow('Lương đi đường', _fmtCurrency(row['travelSalary'])),
          _detailRow('Phụ cấp cố định', _fmtCurrency(row['allowanceFixed'])),
          _detailRow('Phụ cấp theo ngày (mức/ngày)',
              _fmtCurrency(row['allowanceDaily'])),
          _detailRow('Phụ cấp theo ca',
              _fmtCurrency(row['allowanceShift'])),
          _detailRow('Tổng PC kỳ (công, giờ, ca)',
              _fmtCurrency(row['totalAllowance']),
              color: Colors.green.shade700),
          _detailRow('Phụ cấp khác', _fmtCurrency(row['otherAllowance'])),
          _detailRow('Thưởng', _fmtCurrency(row['bonus']), color: Colors.green),
        ]),
        _detailSection('Khấu trừ', [
          _detailRow('Phạt giao dịch', _fmtDeduction(row['penaltyTransactions'] ?? row['penalty']),
              color: Colors.red),
          _detailRow('Phạt đi trễ / vắng', _fmtDeduction(row['latePenalty']),
              color: Colors.red),
          _detailRow('Tổng phạt', _fmtDeduction(row['penalty']),
              color: Colors.red),
          _detailRow('Mức đóng bảo hiểm', _fmtCurrency(row['insuranceSalary'])),
          _detailRow('BHXH (${(_engine.insuranceSettings['bhxhEmployeeRate'] ?? 8)}%)',
              _fmtDeduction(row['bhxhPart']),
              color: Colors.red),
          _detailRow(
              'BHYT (${(_engine.insuranceSettings['bhytEmployeeRate'] ?? 1.5)}%)',
              _fmtDeduction(row['bhytPart']),
              color: Colors.red),
          _detailRow('BHTN (${(_engine.insuranceSettings['bhtnEmployeeRate'] ?? 1)}%)',
              _fmtDeduction(row['bhtnPart']),
              color: Colors.red),
          _detailRow(
              'Đoàn phí (${(_engine.insuranceSettings['unionFeeEmployeeRate'] ?? 1)}%)',
              _fmtDeduction(row['unionFeePart']),
              color: Colors.red),
          _detailRow('Tổng BHXH NLĐ đóng', _fmtDeduction(row['totalInsurance']),
              color: Colors.red),
          _detailRow('TNCN', _fmtDeduction(row['pit']), color: Colors.red),
          _detailRow('Ứng lương', _fmtCurrency(row['advance'])),
        ]),
        const Divider(thickness: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('THỰC NHẬN'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(tr(_fmtCurrency(row['netSalary'])),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: SboxColors.brand700)),
            ],
          ),
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
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
                title: Text(tr(row['name'] ?? 'Chi tiết'),
                    overflow: TextOverflow.ellipsis),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 16),
                    contentBody,
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
        builder: (ctx) => ScrollableAlertDialog(
          title: titleRow,
          content: SizedBox(
            width: math
                .min(500, MediaQuery.of(context).size.width - 32)
                .toDouble(),
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
          ],
        ),
      );
    }
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(tr(title),
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: SboxColors.brand700)),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr(label),
              style: TextStyle(fontSize: 13, color: SboxColors.slate700)),
          Text(tr(value),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  String _fmtCurrency(dynamic val) {
    final v = PayrollEngine.toDouble(val);
    if (v == 0) return '0';
    return '${_currencyFmt.format(v.round())} đ';
  }

  String _fmtDeduction(dynamic val) {
    final v = PayrollEngine.toDouble(val);
    if (v == 0) return '0';
    return '-${_currencyFmt.format(v.round())} đ';
  }

  // ──────── Build ────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(tr('Đang tính toán lương...'),
                style: TextStyle(color: SboxColors.slate500)),
          ],
        ),
      );
    }

    final payrollData = _buildPayrollData();
    final isMobile = Responsive.isMobile(context);

    final toolbarBlock = <Widget>[
      if (isMobile && widget.mobileLeadingSections != null) ...[
        ...widget.mobileLeadingSections!,
        const SizedBox(height: 12),
      ],
      HrmCollapsibleOverview(
        expanded: _showOverviewPanel,
        onToggle: () =>
            setState(() => _showOverviewPanel = !_showOverviewPanel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPayrollInsight(payrollData),
            _buildSummaryCards(payrollData),
            const SizedBox(height: 12),
            _buildToolbar(),
          ],
        ),
      ),
      if (_engine.notConfiguredSalaryCount > 0 && !_isEmployeeRole(context))
        ReportSalarySetupBanner(
          notConfiguredCount: _engine.notConfiguredSalaryCount,
          dense: isMobile,
          onOpenSalarySettings: () => NavigationNotifier.goToSalarySettings(),
        ),
      if (_configWarnings.isNotEmpty && !_isEmployeeRole(context)) _configWarningBanner(),
      const SizedBox(height: 12),
    ];

    final summaryBlock = <Widget>[];

    Widget emptyPayrollWidget() =>
        _engine.notConfiguredSalaryCount > 0 && !_isEmployeeRole(context)
        ? ReportSalarySetupEmptyState(
            notConfiguredCount: _engine.notConfiguredSalaryCount,
            onOpenSalarySettings: () =>
                NavigationNotifier.goToSalarySettings(),
          )
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 64, color: SboxColors.slate300),
                const SizedBox(height: 12),
                Text(tr('Không có dữ liệu lương'),
                    style: TextStyle(
                        color: SboxColors.slate500, fontSize: 16)),
                const SizedBox(height: 4),
                Text(tr('Hãy kiểm tra khoảng thời gian hoặc bộ lọc nhân viên'),
                    style: TextStyle(
                        color: SboxColors.slate400, fontSize: 12)),
              ],
            ),
          );

    if (isMobile) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...toolbarBlock,
            ...summaryBlock,
            const SizedBox(height: 12),
            if (payrollData.isEmpty)
              emptyPayrollWidget()
            else
              RepaintBoundary(
                key: _tableKey,
                child: _buildCompactPayrollList(payrollData),
              ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...toolbarBlock,
          ...summaryBlock,
          const SizedBox(height: 12),
          Expanded(
            child: payrollData.isEmpty
                ? emptyPayrollWidget()
                : RepaintBoundary(
                    key: _tableKey,
                    // Web/desktop: bảng đủ cột (cuộn ngang). Mobile: danh sách rút gọn.
                    child: _buildUnifiedPayrollTable(payrollData),
                  ),
          ),
        ],
      ),
    );
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'thisMonth':
        return 'Tháng này';
      case 'lastMonth':
        return 'Tháng trước';
      case 'thisWeek':
        return 'Tuần này';
      case 'lastWeek':
        return 'Tuần trước';
      case 'today':
        return 'Hôm nay';
      case 'yesterday':
        return 'Hôm qua';
      case 'custom':
        return 'Tùy chọn';
      default:
        return period;
    }
  }

  String _payrollFilterSummary() {
    final parts = <String>[
      _periodLabel(_selectedPeriod),
      '${DateFormat('dd/MM/yy').format(_fromDate)} — ${DateFormat('dd/MM/yy').format(_toDate)}',
    ];
    if (_selectedDepartment != null && _selectedDepartment!.isNotEmpty) {
      parts.add(_selectedDepartment!);
    }
    if (_selectedEmployeeIds.isEmpty) {
      parts.add('Tất cả NV (${_payrollEmployeePool().length})');
    } else {
      parts.add('${_selectedEmployeeIds.length} NV đã chọn');
    }
    if (_searchQuery.trim().isNotEmpty) {
      parts.add('Tìm: ${_searchQuery.trim()}');
    }
    return parts.join(' · ');
  }

  void _resetPayrollFilters() {
    _setPeriod('thisMonth');
    _searchController.clear();
    setState(() {
      _selectedDepartment = null;
      _selectedEmployeeIds.clear();
      _searchQuery = '';
      _cachedPayrollData = null;
      _currentPage = 1;
    });
  }

  void _showEmployeeFilterDialog() {
    final pool = _payrollEmployeePool();
    final tempSelected = Set<String>.from(_selectedEmployeeIds);
    String filterQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final filtered = pool.where((e) {
            if (filterQuery.isEmpty) return true;
            final q = filterQuery.toLowerCase();
            return e.fullName.toLowerCase().contains(q) ||
                e.employeeCode.toLowerCase().contains(q) ||
                (e.department ?? '').toLowerCase().contains(q);
          }).toList();

          return ScrollableAlertDialog(
            title: Row(
              children: [
                const Icon(Icons.people, color: SboxColors.brand500, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(tr('Chọn nhân viên'), style: TextStyle(fontSize: 16))),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      if (tempSelected.length == pool.length) {
                        tempSelected.clear();
                      } else {
                        tempSelected
                          ..clear()
                          ..addAll(pool.map((e) => e.id));
                      }
                    });
                  },
                  child: Text(
                    tr(tempSelected.length == pool.length
                        ? 'Bỏ chọn tất cả'
                        : 'Chọn tất cả'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: math
                  .min(400, MediaQuery.of(context).size.width - 32)
                  .toDouble(),
              height: 450,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: tr('Tìm nhân viên...'),
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setDialogState(() => filterQuery = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final emp = filtered[i];
                        final isSelected = tempSelected.contains(emp.id);
                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                tempSelected.add(emp.id);
                              } else {
                                tempSelected.remove(emp.id);
                              }
                            });
                          },
                          title: Text(tr(emp.fullName),
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            tr('${emp.employeeCode} • ${emp.department ?? ''}'),
                            style: TextStyle(
                                fontSize: 11, color: SboxColors.slate600),
                          ),
                          secondary: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected
                                ? SboxColors.brand100
                                : SboxColors.slate200,
                            child: Text(
                              tr(emp.fullName.isNotEmpty
                                  ? emp.fullName[0].toUpperCase()
                                  : '?'),
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? SboxColors.brand700
                                    : SboxColors.slate600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tr(tempSelected.isEmpty
                          ? 'Hiển thị tất cả nhân viên (${pool.length})'
                          : 'Đã chọn ${tempSelected.length}/${pool.length} nhân viên'),
                      style:
                          TextStyle(fontSize: 12, color: SboxColors.slate600),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Hủy')),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _selectedEmployeeIds = tempSelected;
                    _cachedPayrollData = null;
                    _currentPage = 1;
                  });
                  Navigator.pop(ctx);
                },
                child: Text(tr('Áp dụng')),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final periodDropdown = PopupMenuButton<String>(
      onSelected: (period) {
        if (period == 'custom') {
          setState(() => _selectedPeriod = 'custom');
        } else {
          _setPeriod(period);
        }
      },
      itemBuilder: (_) => [
        _periodMenuItem('thisMonth', 'Tháng này', Icons.calendar_today),
        _periodMenuItem('lastMonth', 'Tháng trước', Icons.calendar_month),
        _periodMenuItem('thisWeek', 'Tuần này', Icons.view_week),
        _periodMenuItem('lastWeek', 'Tuần trước', Icons.view_week_outlined),
        _periodMenuItem('today', 'Hôm nay', Icons.today),
        _periodMenuItem('yesterday', 'Hôm qua', Icons.event),
        const PopupMenuDivider(),
        _periodMenuItem('custom', 'Tùy chọn khác...', Icons.date_range),
      ],
      child: Container(
        width: isMobile ? double.infinity : null,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: SboxColors.slate50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 14, color: Theme.of(context).primaryColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr(_periodLabel(_selectedPeriod)),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).primaryColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 18, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );

    Widget _datePill(DateTime date, bool isFrom) => InkWell(
          onTap: () => _pickSingleDate(isFrom: isFrom),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: SboxColors.slate50,
              border: Border.all(color: SboxColors.slate200),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today,
                    size: 13, color: SboxColors.slate600),
                const SizedBox(width: 6),
                // full format for desktop, compact for mobile
                Text(
                  tr(isMobile
                      ? DateFormat('dd/MM/yy').format(date)
                      : DateFormat('dd/MM/yyyy').format(date)),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        );

    final fromDate = _datePill(_fromDate, true);

    final dateSep =
        Text(tr('—'), style: TextStyle(color: SboxColors.slate400, fontSize: 13));

    final toDate = _datePill(_toDate, false);

    final poolCount = _payrollEmployeePool().length;
    final employeeFilter = InkWell(
      onTap: _showEmployeeFilterDialog,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _selectedEmployeeIds.isNotEmpty
              ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
              : SboxColors.slate50,
          border: Border.all(
            color: _selectedEmployeeIds.isNotEmpty
                ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
                : SboxColors.slate200,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.people_outline,
                size: 14,
                color: _selectedEmployeeIds.isNotEmpty
                    ? Theme.of(context).primaryColor
                    : SboxColors.slate600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tr(_selectedEmployeeIds.isEmpty
                    ? 'Tất cả NV ($poolCount)'
                    : '${_selectedEmployeeIds.length} NV đã chọn'),
                style: TextStyle(
                  fontSize: 13,
                  color: _selectedEmployeeIds.isNotEmpty
                      ? Theme.of(context).primaryColor
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedEmployeeIds.isNotEmpty) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedEmployeeIds.clear();
                    _cachedPayrollData = null;
                    _currentPage = 1;
                  });
                },
                child: Icon(Icons.close,
                    size: 14, color: Theme.of(context).primaryColor),
              ),
            ],
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18,
                color: _selectedEmployeeIds.isNotEmpty
                    ? Theme.of(context).primaryColor
                    : SboxColors.slate500),
          ],
        ),
      ),
    );

    final departmentFilter = Container(
      width: double.infinity,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _selectedDepartment != null
            ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
            : SboxColors.slate50,
        border: Border.all(
          color: _selectedDepartment != null
              ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
              : SboxColors.slate200,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _availableDepartments().contains(_selectedDepartment)
              ? _selectedDepartment
              : null,
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down,
              size: 18,
              color: _selectedDepartment != null
                  ? Theme.of(context).primaryColor
                  : SboxColors.slate500),
          hint: Row(
            children: [
              Icon(Icons.business_outlined,
                  size: 14, color: SboxColors.slate600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr('Phòng ban'),
                  style: TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          selectedItemBuilder: (_) => [
            Row(
              children: [
                Icon(Icons.business_outlined,
                    size: 14,
                    color: Theme.of(context).primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(tr('Phòng ban'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            ..._availableDepartments().map(
              (d) => Row(
                children: [
                  Icon(Icons.business_outlined,
                      size: 14, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr(d),
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(tr(_l10n.allDepartments),
                  style: const TextStyle(fontSize: 13)),
            ),
            ..._availableDepartments().map(
              (d) => DropdownMenuItem<String?>(
                value: d,
                child: Text(tr(d),
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() {
              _selectedDepartment = v;
              _pruneEmployeeSelectionToPool();
              _cachedPayrollData = null;
              _currentPage = 1;
            });
          },
        ),
      ),
    );

    final searchField = SizedBox(
      height: 36,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: tr('Tìm nhanh...'),
          hintStyle: TextStyle(color: SboxColors.slate400, fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 16, color: SboxColors.slate400),
          filled: true,
          fillColor: SboxColors.slate50,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SboxColors.slate200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: SboxColors.slate200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Theme.of(context).primaryColor),
          ),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (v) {
          _cachedPayrollData = null;
          setState(() {
            _searchQuery = v;
            _currentPage = 1;
          });
        },
      ),
    );

    final recordCount = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        tr('${_buildPayrollData().length} NV'),
        style: const TextStyle(
            fontSize: 12,
            color: HrmPageChrome.primaryNavy,
            fontWeight: FontWeight.w600),
      ),
    );

    final filterFields = isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              periodDropdown,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: fromDate),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: dateSep,
                  ),
                  Expanded(child: toDate),
                ],
              ),
              const SizedBox(height: 8),
              departmentFilter,
              const SizedBox(height: 8),
              employeeFilter,
              const SizedBox(height: 8),
              searchField,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  periodDropdown,
                  fromDate,
                  dateSep,
                  toDate,
                  SizedBox(width: 200, child: departmentFilter),
                  SizedBox(width: 220, child: employeeFilter),
                  SizedBox(width: 240, child: searchField),
                ],
              ),
            ],
          );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _payrollFiltersExpanded,
          onExpansionChanged: (v) => setState(() => _payrollFiltersExpanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(tr('Bộ lọc'),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            tr(_payrollFilterSummary()),
            style: TextStyle(fontSize: 12, color: SboxColors.slate600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              recordCount,
              const SizedBox(width: 4),
              Icon(
                _payrollFiltersExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: SboxColors.slate600,
                size: 22,
              ),
            ],
          ),
          children: [
            filterFields,
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: _resetPayrollFilters,
                  child: Text(tr('Xóa lọc')),
                ),
                const Spacer(),
                if (_canFinalizePayroll()) _buildFinalizeButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _periodMenuItem(
      String value, String label, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: _selectedPeriod == value
                  ? SboxColors.brand500
                  : SboxColors.slate600),
          const SizedBox(width: 8),
          Text(tr(label),
              style: TextStyle(
                fontSize: 13,
                fontWeight: _selectedPeriod == value
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: _selectedPeriod == value ? SboxColors.brand500 : null,
              )),
        ],
      ),
    );
  }

  /// Biểu đồ đầu bảng lương: cơ cấu thu nhập / khấu trừ + thực lĩnh cao nhất.
  Widget _buildPayrollInsight(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox.shrink();
    double sum(String k) => data.fold<double>(0, (s, r) => s + ((r[k] as num?) ?? 0).toDouble());
    return SboxInsightPanel(
      charts: [
        SboxChartCard(
          title: 'Cơ cấu thu nhập',
          child: SboxDonutChart(
            centerValue: SboxFmt.compact(sum('netSalary')),
            centerLabel: 'Thực lĩnh',
            slices: [
              SboxSlice('Lương theo công', sum('workSalary')),
              SboxSlice('Phụ cấp', sum('totalAllowance'), color: SboxColors.success),
              SboxSlice('Thưởng', sum('bonus'), color: SboxColors.violet),
              SboxSlice('Lương KPI', sum('kpiSalary'), color: SboxColors.warning),
            ],
          ),
        ),
        SboxChartCard(
          title: 'Các khoản trừ',
          child: SboxBarChart(
            labels: const ['Bảo hiểm', 'Phạt', 'Ứng lương'],
            series: [
              SboxSeries(name: 'Khấu trừ', values: [sum('totalInsurance'), sum('penalty'), sum('advance')], color: SboxColors.danger),
            ],
          ),
        ),
        if (data.length > 1)
          SboxChartCard(
            title: 'Thực lĩnh cao nhất',
            wide: true,
            child: SboxRankList(
              maxItems: 8,
              items: [
                for (final r in data)
                  SboxSlice('${r['employeeName'] ?? r['fullName'] ?? r['name'] ?? '—'}', ((r['netSalary'] as num?) ?? 0).toDouble(),
                      caption: '${((r['workDays'] as num?) ?? 0)} công'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    final totalNet = data.fold<double>(
        0, (s, r) => s + ((r['netSalary'] as num?) ?? 0).toDouble());
    final totalWorkSalary = data.fold<double>(
        0, (s, r) => s + ((r['workSalary'] as num?) ?? 0).toDouble());
    final totalAllowance = data.fold<double>(
        0, (s, r) => s + ((r['totalAllowance'] as num?) ?? 0).toDouble());
    final totalBonus = data.fold<double>(
        0, (s, r) => s + ((r['bonus'] as num?) ?? 0).toDouble());
    final totalPenalty = data.fold<double>(
        0, (s, r) => s + ((r['penalty'] as num?) ?? 0).toDouble());
    final totalIns = data.fold<double>(
        0, (s, r) => s + ((r['totalInsurance'] as num?) ?? 0).toDouble());
    final totalAdv = data.fold<double>(
        0, (s, r) => s + ((r['advance'] as num?) ?? 0).toDouble());
    final totalKpiSalary = data.fold<double>(
        0, (s, r) => s + ((r['kpiSalary'] as num?) ?? 0).toDouble());
    final avgWorkDays = data.isEmpty
        ? 0
        : data.fold<int>(
                0, (s, r) => s + ((r['workDays'] as num?) ?? 0).toInt()) ~/
            data.length;

    final isMobile = MediaQuery.of(context).size.width < 768;

    final items = [
      _SummaryItem(
          'Tổng lương theo công',
          _currencyFmt.format(totalWorkSalary.round()),
          HrmPageChrome.primaryNavy,
          Icons.account_balance_wallet_outlined),
      _SummaryItem('Phụ cấp', _currencyFmt.format(totalAllowance.round()),
          const Color(0xFF2D5F8B), Icons.card_giftcard_outlined),
      _SummaryItem('Thưởng', _currencyFmt.format(totalBonus.round()),
          SboxColors.violet, Icons.emoji_events_outlined),
      _SummaryItem('Phạt', _currencyFmt.format(totalPenalty.round()),
          SboxColors.danger, Icons.gavel_outlined),
      _SummaryItem('Bảo hiểm', _currencyFmt.format(totalIns.round()),
          SboxColors.warning, Icons.health_and_safety_outlined),
      _SummaryItem('Ứng lương', _currencyFmt.format(totalAdv.round()),
          HrmPageChrome.primaryNavy, Icons.payments_outlined),
      _SummaryItem('KPI', _currencyFmt.format(totalKpiSalary.round()),
          const Color(0xFFEC4899), Icons.flag_outlined),
      _SummaryItem('Ngày công TB', '$avgWorkDays ngày', const Color(0xFF14B8A6),
          Icons.event_available_outlined),
    ];
    final netItem = _SummaryItem(
        'THỰC NHẬN',
        _currencyFmt.format(totalNet.round()),
        SboxColors.success,
        Icons.savings_outlined);

    if (isMobile) {
      // Mobile: 2-column grid + full-width net salary
      return Column(
        children: [
          for (int i = 0; i < items.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: i < items.length - 2 ? 6 : 0),
              child: Row(
                children: [
                  Expanded(child: _mobileSummaryChip(items[i])),
                  const SizedBox(width: 6),
                  Expanded(
                      child: i + 1 < items.length
                          ? _mobileSummaryChip(items[i + 1])
                          : const SizedBox.shrink()),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _mobileSummaryChip(netItem, highlight: true),
        ],
      );
    }

    // Desktop: Net hero card on top + flexible Wrap of summary tiles below.
    // Tiles wrap to 2-3 rows naturally so labels/values are never truncated.
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        // Choose how many tiles per row based on width to keep 3-row max.
        // 8 items → 4 cols (2 rows) >= 1100, 3 cols (3 rows) >= 820, else 2 cols.
        final perRow = w >= 1100 ? 4 : (w >= 820 ? 3 : 2);
        const spacing = 10.0;
        final tileWidth = (w - spacing * (perRow - 1)) / perRow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _netHeroCard(netItem),
            const SizedBox(height: 10),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final it in items)
                  SizedBox(width: tileWidth, child: _summaryTile(it)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _netHeroCard(_SummaryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [item.color.withValues(alpha: 0.95), SboxColors.payHover],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: item.color.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(item.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('${item.label} (tổng toàn công ty)'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr('${item.value} ₫'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(_SummaryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr(item.label),
                  style: TextStyle(
                    fontSize: 11,
                    color: SboxColors.slate600,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    tr(item.value),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: item.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSummaryChip(_SummaryItem item, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? item.color.withValues(alpha: 0.12)
            : item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: item.color.withValues(alpha: highlight ? 0.3 : 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: highlight ? 32 : 26,
            height: highlight ? 32 : 26,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: highlight ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(item.icon, color: item.color, size: highlight ? 18 : 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(item.label),
                    style: TextStyle(
                        fontSize: 10,
                        color: item.color.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(tr(item.value),
                      style: TextStyle(
                          fontSize: highlight ? 15 : 12,
                          fontWeight: FontWeight.bold,
                          color: item.color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Fixed/frozen column keys (always shown, pinned left)
  static const _frozenKeys = {'stt', 'name'};

  Widget _buildPagination(
    int totalRows,
    int totalPages, {
    VoidCallback? onOpenFullscreen,
  }) {
    return SboxPager(
      page: _currentPage,
      pageSize: _rowsPerPage,
      total: totalRows,
      onPage: (p) => setState(() => _currentPage = p),
      onPageSize: (v) => setState(() {
        _rowsPerPage = v;
        _currentPage = 1;
      }),
      extra: [
        if (onOpenFullscreen != null)
          TextButton.icon(
            onPressed: onOpenFullscreen,
            icon: const Icon(Icons.fullscreen_rounded, size: 18),
            label: Text(tr('Toàn màn hình')),
          ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildTable(
      List<Map<String, dynamic>> data, List<PayrollColumn> visibleCols) {
    final frozenCols =
        visibleCols.where((c) => _frozenKeys.contains(c.key)).toList();
    final scrollableCols =
        visibleCols.where((c) => !_frozenKeys.contains(c.key)).toList();

    const double rowHeight = 44;
    const double headerHeight = 46;
    const double cellPadding = 10;

    double colWidth(PayrollColumn col) {
      switch (col.key) {
        case 'stt':
          return 44;
        case 'code':
          return 110;
        case 'name':
          return 170;
        case 'department':
          return 110;
        case 'salaryType':
          return 90;
        case 'standardDays':
          return 90;
        case 'workDays':
          return 78;
        case 'totalHours':
          return 74;
        case 'otTotalHours':
          return 70;
        default:
          return 118;
      }
    }

    final frozenWidth = frozenCols.fold<double>(0, (s, c) => s + colWidth(c));

    Widget buildCell(
        String key, Map<String, dynamic> row, int index, double width) {
      final isEven = index.isEven;
      return InkWell(
        onTap: () => _showEmployeeDetail(row),
        child: Container(
          width: width,
          height: rowHeight,
          alignment: key == 'name' ||
                  key == 'code' ||
                  key == 'department' ||
                  key == 'salaryType'
              ? Alignment.centerLeft
              : Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: cellPadding),
          decoration: BoxDecoration(
            color: isEven ? Colors.white : const Color(0xFFFAFBFC),
            border: const Border(
                bottom: BorderSide(color: SboxColors.slate200, width: 0.5)),
          ),
          child: Text(
            tr(_formatCellValue(key, row, index)),
            style: TextStyle(
              fontSize: 12,
              fontWeight: key == 'netSalary'
                  ? FontWeight.bold
                  : (key == 'name' ? FontWeight.w600 : FontWeight.normal),
              color: _getCellColor(key, row),
            ),
            maxLines: key == 'name' ? 1 : null,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    Widget buildHeaderCell(PayrollColumn col, double width) {
      final isCurrentSort = _sortColumn == col.key;
      return InkWell(
        onTap: () {
          setState(() {
            if (_sortColumn == col.key) {
              _sortAscending = !_sortAscending;
            } else {
              _sortColumn = col.key;
              _sortAscending = true;
            }
            _cachedPayrollData = null;
          });
        },
        child: Container(
          width: width,
          height: headerHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: cellPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(tr(col.label),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: SboxColors.slate500),
                    overflow: TextOverflow.ellipsis),
              ),
              if (isCurrentSort)
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: SboxColors.brand700,
                ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      key: _tableKey,
      child: Container(
        color: Colors.white,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                // ── Frozen columns (left) ──
                SizedBox(
                  width: frozenWidth,
                  child: Column(
                    children: [
                      // Frozen header
                      Container(
                        color: SboxColors.slate50,
                        child: Row(
                          children: frozenCols
                              .map((c) => buildHeaderCell(c, colWidth(c)))
                              .toList(),
                        ),
                      ),
                      // Frozen data rows
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: ListView.builder(
                            controller: _verticalScrollController,
                            itemCount: data.length,
                            itemExtent: rowHeight,
                            itemBuilder: (_, i) {
                              final row = data[i];
                              return Container(
                                color: i.isEven
                                    ? Colors.white
                                    : SboxColors.slate50,
                                child: Row(
                                  children: frozenCols
                                      .map((c) =>
                                          buildCell(c.key, row, i, colWidth(c)))
                                      .toList(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider between frozen and scrollable
                Container(width: 1, color: SboxColors.slate300),
                // ── Scrollable columns (right) ──
                Expanded(
                  child: Scrollbar(
                    controller: _horizontalScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrollableCols.fold<double>(
                            0, (s, c) => s + colWidth(c)),
                        child: Column(
                          children: [
                            // Scrollable header
                            Container(
                              color: SboxColors.slate50,
                              child: Row(
                                children: scrollableCols
                                    .map((c) => buildHeaderCell(c, colWidth(c)))
                                    .toList(),
                              ),
                            ),
                            // Scrollable data rows (synced with frozen vertical scroll)
                            Expanded(
                              child: _SyncedListView(
                                mainController: _verticalScrollController,
                                itemCount: data.length,
                                itemExtent: rowHeight,
                                itemBuilder: (_, i) {
                                  final row = data[i];
                                  return Container(
                                    color: i.isEven
                                        ? Colors.white
                                        : SboxColors.slate50,
                                    child: Row(
                                      children: scrollableCols
                                          .map((c) => buildCell(
                                              c.key, row, i, colWidth(c)))
                                          .toList(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color? _getCellColor(String key, Map<String, dynamic> row) {
    switch (key) {
      case 'netSalary':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val >= 0 ? SboxColors.brand700 : Colors.red;
      case 'penalty':
      case 'latePenalty':
      case 'bhxh':
      case 'bhyt':
      case 'bhtn':
      case 'unionFee':
      case 'totalInsurance':
      case 'pit':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val > 0 ? Colors.red : null;
      case 'bonus':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val > 0 ? Colors.green.shade700 : null;
      case 'advance':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val > 0 ? Colors.orange.shade700 : null;
      default:
        return null;
    }
  }

  String _formatCellValue(String key, Map<String, dynamic> row, int index) {
    switch (key) {
      case 'allowanceQualified':
        final days = (row['allowanceDays'] as num?)?.toDouble() ?? 0;
        final shifts = (row['allowanceShiftCount'] as num?)?.toInt() ?? 0;
        final miss = (row['allowanceMisses'] as List?)?.length ?? 0;
        final d = days == days.roundToDouble() ? '${days.toInt()}' : days.toStringAsFixed(1);
        return [
          if (days > 0) '$d ngày',
          if (shifts > 0) '$shifts ca',
          if (miss > 0) '−$miss',
        ].join(' · ');
      case _employeeSignColumnKey:
        return '';
      case 'stt':
        return '${(_currentPage - 1) * _rowsPerPage + index + 1}';
      case 'code':
      case 'name':
      case 'department':
      case 'position':
      case 'salaryType':
        return row[key]?.toString() ?? '';
      case 'paidLeaveDays':
      case 'absentDays':
      case 'lateCount':
      case 'earlyCount':
        return '${(row[key] as num?)?.toInt() ?? 0}';
      // Công có thể lẻ (nửa công, nghỉ nửa ca) — trước đây cắt mất phần lẻ (19,5 → 19).
      case 'workDays':
      case 'paidDaysCredit':
      case 'standardDays':
        final sd = (row[key] as num?)?.toDouble() ?? 0;
        return sd == sd.roundToDouble()
            ? '${sd.toInt()}'
            : sd.toStringAsFixed(1);
      case 'totalHours':
      case 'standardHours':
      case 'otTotalHours':
      case 'travelHours':
      case 'otHoursWeekday':
      case 'otHoursWeekend':
      case 'otHoursHoliday':
        return (row[key] as num?)?.toStringAsFixed(1) ?? '0';
      case 'lateMinutes':
      case 'earlyMinutes':
        return '${(row[key] as num?)?.toInt() ?? 0}';
      case 'bhxh':
        if (row['insuranceSkipped'] == true) return 'Không đóng (<14 ngày)';
        final ins = (row[key] as num?)?.toDouble() ?? 0;
        return ins == 0 ? '0' : '-${_currencyFmt.format(ins.round())}';
      case 'penalty':
      case 'bhyt':
      case 'bhtn':
      case 'unionFee':
      case 'totalInsurance':
      case 'pit':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        if (val == 0) return '0';
        return '-${_currencyFmt.format(val.round())}';
      default:
        final val = (row[key] as num?)?.toDouble() ?? 0;
        if (val == 0) return '0';
        return _currencyFmt.format(val.round());
    }
  }

  Widget _buildPayrollHorizontalClip({
    required double tableMinWidth,
    required Widget child,
    required ScrollController hController,
  }) {
    return HorizontallySyncedClip(
      controller: hController,
      contentWidth: tableMinWidth,
      child: child,
    );
  }

  double _payrollColWidth(PayrollColumn col) {
    switch (col.key) {
      case 'stt':
        return 48;
      case 'code':
        return 96;
      case 'name':
        return 168;
      case 'department':
        return 112;
      case 'salaryType':
        return 88;
      case 'standardDays':
      case 'workDays':
      case 'paidDaysCredit':
        return 72;
      case 'totalHours':
      case 'otTotalHours':
        return 76;
      case 'workSalary':
      case 'netSalary':
      case 'totalSalary':
        return 124;
      case _employeeSignColumnKey:
        return 96;
      default:
        return 104;
    }
  }

  Map<int, TableColumnWidth> _payrollDesktopColumnWidths(
      List<PayrollColumn> visibleCols) {
    final widths = <int, TableColumnWidth>{};
    for (var i = 0; i < visibleCols.length; i++) {
      widths[i] = FixedColumnWidth(_payrollColWidth(visibleCols[i]));
    }
    return widths;
  }

  double _payrollDesktopTableMinWidth(List<PayrollColumn> visibleCols) {
    return visibleCols.fold<double>(0, (s, c) => s + _payrollColWidth(c));
  }

  bool _isPayrollNumericKey(String key) {
    return !{
      'stt',
      'code',
      'name',
      'department',
      'position',
      'salaryType',
      _employeeSignColumnKey,
    }.contains(key);
  }

  bool _isPayrollLeftAlignKey(String key) {
    return {'name', 'code', 'department', 'salaryType'}.contains(key);
  }

  Widget _payrollTableCell(
    Widget child, {
    Alignment alignment = Alignment.center,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Align(alignment: alignment, child: child),
    );
  }

  Widget _payrollHeaderText(String text) => Text(
        tr(text),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: SboxColors.slate600,
        ),
      );

  TableRow _buildPayrollHeaderRow(List<PayrollColumn> visibleCols) {
    return TableRow(
      decoration: const BoxDecoration(color: SboxColors.slate50),
      children: visibleCols
          .map((c) => _payrollTableCell(_payrollHeaderText(c.label)))
          .toList(),
    );
  }

  TableRow _buildPayrollDataRow(
    Map<String, dynamic> row,
    int index,
    List<PayrollColumn> visibleCols, {
    int? absoluteStt,
  }) {
    return TableRow(
      children: visibleCols.map((col) {
        final align = _isPayrollLeftAlignKey(col.key)
            ? Alignment.centerLeft
            : Alignment.center;
        final color = _getCellColor(col.key, row);
        if (col.key == _employeeSignColumnKey) {
          return _payrollTableCell(
            Container(
              height: 28,
              decoration: BoxDecoration(
                border: Border.all(color: SboxColors.slate200),
                borderRadius: BorderRadius.circular(4),
                color: SboxColors.slate50,
              ),
            ),
          );
        }
        final cellText = col.key == 'stt' && absoluteStt != null
            ? '$absoluteStt'
            : _formatCellValue(col.key, row, index);
        final misses = col.key == 'allowanceQualified' ? (row['allowanceMisses'] as List?) : null;
        if (misses != null && misses.isNotEmpty) {
          return _payrollTableCell(
            Tooltip(
              message: '${tr('Không đủ thời gian làm trong ca')}:\n${misses.take(15).join('\n')}'
                  '${misses.length > 15 ? '\n… +${misses.length - 15}' : ''}',
              child: Text(tr(cellText),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: SboxColors.warningText, decoration: TextDecoration.underline)),
            ),
          );
        }
        return _payrollTableCell(
          Text(
            tr(cellText),
            textAlign:
                _isPayrollLeftAlignKey(col.key) ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: col.key == 'netSalary' ? 13 : 12,
              fontWeight: col.key == 'netSalary' || col.key == 'totalSalary'
                  ? FontWeight.w700
                  : (col.key == 'name' ? FontWeight.w600 : FontWeight.normal),
              color: col.key == 'netSalary' && PayrollEngine.toDouble(row['netSalary']) < 0
                  ? SboxColors.danger
                  : col.key == 'netSalary'
                      ? SboxColors.brand700
                      : (color ?? SboxColors.slate900),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: col.key == 'name' ? 1 : null,
            overflow: TextOverflow.ellipsis,
          ),
          alignment: align,
        );
      }).toList(),
    );
  }

  String _payrollTotalCellText(
    PayrollColumn col,
    List<Map<String, dynamic>> allData,
  ) {
    if (col.key == 'stt' || col.key == _employeeSignColumnKey) return '';
    if (col.key == 'name') return 'TỔNG CỘNG';
    if (col.key == 'code') return '${allData.length} NV';
    if (!_isPayrollNumericKey(col.key)) return '—';

    final total = allData.fold<double>(
        0, (s, r) => s + ((r[col.key] as num?) ?? 0).toDouble());
    if (total == 0) return '—';
    if (col.key == 'workDays' ||
        col.key == 'standardDays' ||
        col.key == 'lateCount' ||
        col.key == 'earlyCount' ||
        col.key == 'lateMinutes' ||
        col.key == 'earlyMinutes' ||
        col.key == 'absentDays') {
      return total == total.roundToDouble()
          ? '${total.toInt()}'
          : total.toStringAsFixed(1);
    }
    if (col.key == 'totalHours' ||
        col.key == 'otTotalHours' ||
        col.key == 'travelHours' ||
        col.key == 'standardHours') {
      return total.toStringAsFixed(1);
    }
    if (col.key == 'penalty' ||
        col.key == 'bhxh' ||
        col.key == 'bhyt' ||
        col.key == 'bhtn' ||
        col.key == 'unionFee' ||
        col.key == 'totalInsurance' ||
        col.key == 'pit') {
      return total == 0 ? '—' : '-${_currencyFmt.format(total.round())}';
    }
    return _currencyFmt.format(total.round());
  }

  TableRow _buildPayrollTotalRow(
    List<Map<String, dynamic>> allData,
    List<PayrollColumn> visibleCols,
  ) {
    return TableRow(
      decoration: const BoxDecoration(color: SboxColors.brand50),
      children: visibleCols.map((col) {
        final text = _payrollTotalCellText(col, allData);
        return _payrollTableCell(
          Text(
            tr(text),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: col.key == 'netSalary'
                  ? SboxColors.brand800
                  : SboxColors.brand800,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPayrollDesktopTable({
    required Map<int, TableColumnWidth> columnWidths,
    required List<TableRow> rows,
  }) {
    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: SboxColors.slate200, width: 0.5),
        verticalInside: BorderSide(color: SboxColors.slate200, width: 0.5),
      ),
      children: rows,
    );
  }

  Widget _buildBottomHorizontalScrollBar(double tableMinWidth) {
    return Container(
      height: 18,
      decoration: const BoxDecoration(
        color: SboxColors.slate50,
        border: Border(top: BorderSide(color: SboxColors.slate200)),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        controller: _desktopTableHScrollBody,
        child: SingleChildScrollView(
          controller: _desktopTableHScrollBody,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: tableMinWidth, height: 1),
        ),
      ),
    );
  }

  void _openPayrollTableFullscreen(
    List<Map<String, dynamic>> allData,
    List<PayrollColumn> visibleCols,
  ) {
    if (allData.isEmpty) return;
    final vBody = ScrollController();
    final headerRow = _buildPayrollHeaderRow(visibleCols);
    final dataRows = allData
        .asMap()
        .entries
        .map((e) => _buildPayrollDataRow(
              e.value,
              e.key,
              visibleCols,
              absoluteStt: e.key + 1,
            ))
        .toList();
    dataRows.add(_buildPayrollTotalRow(allData, visibleCols));

    final hScroll = ScrollController();
    final columnWidths = _payrollDesktopColumnWidths(visibleCols);
    final tableMinWidth = _payrollDesktopTableMinWidth(visibleCols);
    const headerH = 44.0;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: SboxColors.slate50,
          appBar: AppBar(
            title: Text(tr('Bảng tổng hợp lương'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            leading: IconButton(
              tooltip: tr('Thoát chế độ toàn màn hình'),
              icon: const Icon(Icons.fullscreen_exit),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialogCtx),
                icon: const Icon(Icons.close, size: 18),
                label: Text(tr('Thoát')),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: headerH,
                decoration: const BoxDecoration(
                  color: SboxColors.slate50,
                  border: Border(bottom: BorderSide(color: SboxColors.slate200)),
                ),
                child: _buildPayrollHorizontalClip(
                  tableMinWidth: tableMinWidth,
                  hController: hScroll,
                  child: _buildPayrollDesktopTable(
                    columnWidths: columnWidths,
                    rows: [headerRow],
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  controller: vBody,
                  child: SingleChildScrollView(
                    controller: vBody,
                    primary: false,
                    child: _buildPayrollHorizontalClip(
                      tableMinWidth: tableMinWidth,
                      hController: hScroll,
                      child: _buildPayrollDesktopTable(
                        columnWidths: columnWidths,
                        rows: dataRows,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                height: 18,
                decoration: const BoxDecoration(
                  color: SboxColors.slate50,
                  border: Border(top: BorderSide(color: SboxColors.slate200)),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  controller: hScroll,
                  child: SingleChildScrollView(
                    controller: hScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: tableMinWidth, height: 1),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: SboxColors.slate200)),
                ),
                child: Text(
                  tr('${allData.length} nhân viên · Kỳ ${DateFormat('dd/MM/yyyy').format(_fromDate)} – ${DateFormat('dd/MM/yyyy').format(_toDate)}'),
                  style:
                      TextStyle(fontSize: 12, color: SboxColors.slate600),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      vBody.dispose();
      hScroll.dispose();
    });
  }

  Widget _buildCompactPayrollList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart, size: 56, color: SboxColors.slate200),
            const SizedBox(height: 12),
            Text(tr('Không có dữ liệu'),
                style: TextStyle(color: SboxColors.slate500)),
          ],
        ),
      );
    }


    final totalPages = math.max(1, (data.length / _rowsPerPage).ceil());
    if (_currentPage > totalPages) _currentPage = totalPages;
    if (_currentPage < 1) _currentPage = 1;
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = math.min(start + _rowsPerPage, data.length);
    final paged = data.sublist(start, end);

    String money(dynamic v) => _fmtCurrency(v);
    double d(String k, Map<String, dynamic> r) => PayrollEngine.toDouble(r[k]);
    String num1(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

    Widget line(String label, String value, {Color? color, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(
              child: Text(tr(label), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
            ),
            Text(tr(value),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: color ?? SboxColors.slate800)),
          ]),
        );

    Widget group(String title, IconData icon, Color color, List<Widget> lines, {Widget? total}) {
      if (lines.isEmpty && total == null) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(tr(title), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 2),
          ...lines,
          if (total != null) ...[const Divider(height: 10), total],
        ]),
      );
    }

    Widget chip(String text, Color color, IconData icon) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(tr(text), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ]),
        );

    Widget buildCard(Map<String, dynamic> row, int index) {
      final name = row['name']?.toString() ?? '';
      final parts = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
      final initials = parts.isEmpty
          ? '?'
          : parts.length == 1
              ? parts.first.characters.first.toUpperCase()
              : (parts[parts.length - 2].characters.first + parts.last.characters.first).toUpperCase();
      final gross = d('totalSalary', row);
      final ded = d('totalDeduction', row);
      final net = d('netSalary', row);
      final workDays = d('workDays', row), stdDays = d('standardDays', row);
      final ot = d('otTotalHours', row);
      final lateCount = d('lateCount', row), absent = d('absentDays', row);
      final dedRatio = gross > 0 ? (ded / gross).clamp(0.0, 1.0) : 0.0;
      final subtitle = [
        row['department']?.toString() ?? '',
        row['salaryType']?.toString() ?? '',
      ].where((x) => x.isNotEmpty).join(' · ');

      final income = <Widget>[
        for (final (k, label) in const [
          ('workSalary', 'Lương theo công'),
          ('completionSalary', 'Lương hoàn thành'),
          ('otSalary', 'Tăng ca'),
          ('travelSalary', 'Đi đường / công tác'),
          ('totalAllowance', 'Phụ cấp'),
          ('bonus', 'Thưởng'),
          ('kpiSalary', 'Lương KPI'),
          ('commission', 'Hoa hồng'),
          ('productionAmount', 'Lương sản phẩm'),
          ('leavePayout', 'Tiền phép năm chưa nghỉ'),
        ])
          if (d(k, row) != 0) line(label, money(row[k])),
      ];
      final deductions = <Widget>[
        for (final (k, label) in const [
          ('totalInsurance', 'Bảo hiểm (BHXH, BHYT, BHTN)'),
          ('pit', 'Thuế TNCN'),
          ('penalty', 'Phạt'),
          ('advance', 'Tạm ứng'),
        ])
          if (d(k, row) != 0) line(label, '−${money(row[k])}', color: SboxColors.danger),
      ];
      final attendance = <Widget>[
        line('Công thực tế / chuẩn', '${num1(workDays)} / ${num1(stdDays)}'),
        if (d('totalHours', row) > 0) line('Giờ làm', '${num1(d('totalHours', row))} giờ'),
        if (ot > 0)
          line('Tăng ca',
              '${num1(ot)} giờ (thường ${num1(d('otHoursWeekday', row))} · nghỉ ${num1(d('otHoursWeekend', row))} · lễ ${num1(d('otHoursHoliday', row))})'),
        if (lateCount > 0) line('Đi muộn', '${num1(lateCount)} lần · ${num1(d('lateMinutes', row))} phút'),
        if (d('earlyCount', row) > 0) line('Về sớm', '${num1(d('earlyCount', row))} lần · ${num1(d('earlyMinutes', row))} phút'),
        if (absent > 0) line('Vắng', '${num1(absent)} ngày', color: SboxColors.danger),
        if (d('paidLeaveDays', row) > 0) line('Nghỉ hưởng lương', '${num1(d('paidLeaveDays', row))} ngày'),
        if (d('allowanceDays', row) > 0 || d('allowanceShiftCount', row) > 0)
          line('Đủ điều kiện phụ cấp', _formatCellValue('allowanceQualified', row, 0)),
        for (final m in ((row['allowanceMisses'] as List?) ?? const []).take(10))
          line('Không tính PC', '$m', color: SboxColors.warningText),
      ];

      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: Container(
          margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: net < 0 ? SboxColors.danger.withValues(alpha: 0.5) : SboxColors.slate200),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: SboxColors.brand50,
              child: Text(initials,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SboxColors.brand700)),
            ),
            title: Row(children: [
              Expanded(
                child: Text(tr(name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: SboxColors.slate900)),
              ),
              Text(tr(money(net)),
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15, color: net < 0 ? SboxColors.danger : SboxColors.brand700)),
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (subtitle.isNotEmpty)
                Text(tr(subtitle), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
              const SizedBox(height: 6),
              // Thanh tỉ lệ: phần còn nhận (xanh) / khấu trừ (đỏ) trên tổng thu nhập
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Row(children: [
                  Expanded(
                    flex: ((1 - dedRatio) * 1000).round().clamp(1, 1000),
                    child: Container(height: 5, color: SboxColors.success),
                  ),
                  if (dedRatio > 0)
                    Expanded(
                      flex: (dedRatio * 1000).round().clamp(1, 1000),
                      child: Container(height: 5, color: SboxColors.danger.withValues(alpha: 0.7)),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 5, runSpacing: 4, children: [
                chip('${num1(workDays)}/${num1(stdDays)} công', SboxColors.brand600, Icons.calendar_today_rounded),
                if (ot > 0) chip('OT ${num1(ot)}h', SboxColors.violet, Icons.bolt_rounded),
                if (lateCount > 0) chip('Muộn ${num1(lateCount)}', SboxColors.warning, Icons.more_time_rounded),
                if (absent > 0) chip('Vắng ${num1(absent)}', SboxColors.danger, Icons.event_busy_rounded),
                if (_engine.showTravelPayrollColumns && d('travelHours', row) > 0)
                  chip('Đi đường ${num1(d('travelHours', row))}h', SboxColors.warning, Icons.directions_car_rounded),
                if (net < 0) chip('Thực nhận âm', SboxColors.danger, Icons.warning_amber_rounded),
              ]),
            ]),
            children: [
              group('Thu nhập', Icons.add_circle_outline_rounded, SboxColors.success, income,
                  total: line('Tổng thu nhập', money(gross), bold: true, color: SboxColors.success)),
              group('Khấu trừ', Icons.remove_circle_outline_rounded, SboxColors.danger, deductions,
                  total: deductions.isEmpty ? null : line('Tổng khấu trừ', '−${money(ded)}', bold: true, color: SboxColors.danger)),
              group('Chấm công', Icons.fact_check_outlined, SboxColors.brand600, attendance),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [SboxColors.brand700, SboxColors.brand500]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Text(tr('THỰC NHẬN'), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
                  const Spacer(),
                  Text(tr(money(net)), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                ]),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showEmployeeDetail(row),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(tr('Xem chi tiết đầy đủ')),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget sortChips() {
      Widget c(String key, String label, bool defaultAsc) {
        final sel = _sortColumn == key;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(tr(sel ? '$label ${_sortAscending ? '↑' : '↓'}' : label)),
            selected: sel,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => setState(() {
              if (sel) {
                _sortAscending = !_sortAscending;
              } else {
                _sortColumn = key;
                _sortAscending = defaultAsc;
              }
              _cachedPayrollData = null;
              _currentPage = 1;
            }),
          ),
        );
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(children: [
          Text(tr('Sắp xếp: '), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          c('netSalary', 'Thực nhận', false),
          c('name', 'Tên', true),
          c('workDays', 'Công', false),
          c('otTotalHours', 'Tăng ca', false),
          c('totalDeduction', 'Khấu trừ', false),
        ]),
      );
    }

    final tiles = <Widget>[
      sortChips(),
      for (final entry in paged.asMap().entries) buildCard(entry.value, start + entry.key),
    ];

    final totalNet = data.fold<double>(
      0,
      (sum, row) => sum + PayrollEngine.toDouble(row['netSalary']),
    );
    final isMobile = MediaQuery.of(context).size.width < 600;
    final listView = ListView(
      padding: EdgeInsets.zero,
      shrinkWrap: isMobile,
      physics: isMobile
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      children: tiles,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SboxColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('Bảng lương'),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Text(
                  tr('${data.length} NV'),
                  style: TextStyle(fontSize: 12, color: SboxColors.slate600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: SboxColors.slate200),
          if (isMobile)
            listView
          else
            Expanded(child: listView),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: SboxColors.brand50.withValues(alpha: 0.35),
              border: const Border(
                top: BorderSide(color: SboxColors.slate200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(tr('TỔNG THỰC NHẬN'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Text(
                  tr(_fmtCurrency(totalNet)),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: SboxColors.brand800,
                  ),
                ),
              ],
            ),
          ),
          _buildPagination(data.length, totalPages),
        ],
      ),
    );
  }

  Widget _buildUnifiedPayrollTable(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart, size: 56, color: SboxColors.slate200),
            const SizedBox(height: 12),
            Text(tr('Không có dữ liệu'),
                style: TextStyle(color: SboxColors.slate500)),
          ],
        ),
      );
    }

    final visibleCols = _visiblePayrollColumns(data);
    final totalPages = math.max(1, (data.length / _rowsPerPage).ceil());
    if (_currentPage > totalPages) _currentPage = totalPages;
    if (_currentPage < 1) _currentPage = 1;
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = math.min(start + _rowsPerPage, data.length);
    final paged = data.sublist(start, end);

    // Cột cố định: STT + Tên bên trái, Thực nhận bên phải; phần giữa cuộn ngang.
    const leftKeys = {'stt', 'name'};
    const rightKeys = {'netSalary'};
    final leftCols = visibleCols.where((c) => leftKeys.contains(c.key)).toList();
    final rightCols = visibleCols.where((c) => rightKeys.contains(c.key)).toList();
    final midCols = visibleCols
        .where((c) => !leftKeys.contains(c.key) && !rightKeys.contains(c.key))
        .toList();
    final leftW = _payrollDesktopTableMinWidth(leftCols);
    final rightW = _payrollDesktopTableMinWidth(rightCols);
    final midW = _payrollDesktopTableMinWidth(midCols);
    const headerH = 44.0, groupH = 26.0, rowH = 40.0, totalH = 44.0;

    Widget fixH(Widget c, double h) => SizedBox(height: h, child: c);

    TableRow headerFor(List<PayrollColumn> cols) {
      final r = _buildPayrollHeaderRow(cols);
      return TableRow(decoration: r.decoration, children: [for (final c in r.children) fixH(c, headerH)]);
    }

    List<TableRow> bodyFor(List<PayrollColumn> cols) {
      final rows = <TableRow>[];
      for (final e in paged.asMap().entries) {
        final rowKey = 'p${start + e.key}';
        final r = _buildPayrollDataRow(e.value, e.key, cols);
        rows.add(TableRow(
          decoration: BoxDecoration(color: e.key.isEven ? Colors.white : const Color(0xFFF7FAFC)),
          children: [
            for (final c in r.children)
              HoverRowCell(rowKey: rowKey, hovered: _payrollHoveredRow, child: fixH(c, rowH)),
          ],
        ));
      }
      final t = _buildPayrollTotalRow(data, cols);
      rows.add(TableRow(
        decoration: const BoxDecoration(
          color: SboxColors.brand50,
          border: Border(top: BorderSide(color: SboxColors.brand200, width: 2)),
        ),
        children: [for (final c in t.children) fixH(c, totalH)],
      ));
      return rows;
    }

    Widget tableFor(List<PayrollColumn> cols, List<TableRow> rows) =>
        _buildPayrollDesktopTable(columnWidths: _payrollDesktopColumnWidths(cols), rows: rows);

    Widget headerBlock(List<PayrollColumn> cols) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [_payrollGroupHeader(cols, groupH), tableFor(cols, [headerFor(cols)])],
        );

    const frozenShadowR = [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(3, 0))];
    const frozenShadowL = [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(-3, 0))];

    Widget frozen(double w, Widget child, List<BoxShadow> shadow) => Container(
          width: w,
          decoration: BoxDecoration(color: Colors.white, boxShadow: shadow),
          child: child,
        );

    Widget threePart({required Widget Function(List<PayrollColumn>) build}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leftCols.isNotEmpty) frozen(leftW, build(leftCols), frozenShadowR),
            Expanded(
              child: _buildPayrollHorizontalClip(
                tableMinWidth: midW,
                hController: _desktopTableHScrollBody,
                child: build(midCols),
              ),
            ),
            if (rightCols.isNotEmpty) frozen(rightW, build(rightCols), frozenShadowL),
          ],
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SboxColors.slate200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: groupH + headerH, child: threePart(build: headerBlock)),
          const Divider(height: 1, color: SboxColors.slate200),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              controller: _desktopTableVScroll,
              child: SingleChildScrollView(
                controller: _desktopTableVScroll,
                primary: false,
                child: threePart(build: (cols) => tableFor(cols, bodyFor(cols))),
              ),
            ),
          ),
          _buildPagination(
            data.length,
            totalPages,
            onOpenFullscreen: () =>
                _openPayrollTableFullscreen(data, visibleCols),
          ),
          Padding(
            padding: EdgeInsets.only(left: leftW, right: rightW),
            child: _buildBottomHorizontalScrollBar(midW),
          ),
        ],
      ),
    );
  }

  /// Nhóm cột bảng lương (tiêu đề tầng trên).
  static String _payrollGroupOf(String key) {
    const info = {'stt', 'name', 'code', 'department', 'salaryType'};
    const att = {'standardDays', 'workDays', 'totalHours', 'otTotalHours', 'travelHours', 'standardHours',
      'lateCount', 'lateMinutes', 'earlyCount', 'earlyMinutes', 'absentDays', 'paidLeaveDays'};
    const ded = {'penalty', 'latePenalty', 'bhxh', 'bhyt', 'bhtn', 'unionFee', 'totalInsurance', 'pit', 'advance',
      'totalDeduction'};
    if (info.contains(key)) return 'Nhân viên';
    if (att.contains(key)) return 'Chấm công';
    if (ded.contains(key)) return 'Khấu trừ';
    if (key == 'netSalary') return 'Thực nhận';
    if (key == _employeeSignColumnKey) return 'Ký nhận';
    return 'Thu nhập';
  }

  static (Color, Color) _payrollGroupColors(String g) => switch (g) {
        'Chấm công' => (const Color(0xFFE8F4FA), SboxColors.brand700),
        'Thu nhập' => (const Color(0xFFE9F8EF), const Color(0xFF15803D)),
        'Khấu trừ' => (const Color(0xFFFDECEC), const Color(0xFFB91C1C)),
        'Thực nhận' => (SboxColors.brand600, Colors.white),
        _ => (SboxColors.slate100, SboxColors.slate700),
      };

  /// Tiêu đề tầng trên: gộp các cột liền nhau cùng nhóm thành 1 khối màu.
  Widget _payrollGroupHeader(List<PayrollColumn> cols, double height) {
    final blocks = <(String, double)>[];
    for (final c in cols) {
      final g = _payrollGroupOf(c.key);
      final w = _payrollColWidth(c);
      if (blocks.isNotEmpty && blocks.last.$1 == g) {
        blocks[blocks.length - 1] = (g, blocks.last.$2 + w);
      } else {
        blocks.add((g, w));
      }
    }
    return SizedBox(
      height: height,
      child: Row(children: [
        for (final (g, w) in blocks)
          Container(
            width: w,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _payrollGroupColors(g).$1,
              border: const Border(right: BorderSide(color: Colors.white, width: 2)),
            ),
            child: Text(tr(g.toUpperCase()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                    color: _payrollGroupColors(g).$2)),
          ),
      ]),
    );
  }

  // ──────── Vertical payroll layout (mobile) ────────
  List<PayrollColumn> _mobilePayrollDetailColumns() {
    final visible = _visiblePayrollColumns(_cachedPayrollData)
        .where((c) => !{
              'stt',
              'name',
              'code',
              'department',
              _employeeSignColumnKey,
            }.contains(c.key))
        .toList();
    return visible;
  }

  List<PayrollColumn> _mobileVerticalPayrollColumns() {
    return _mobilePayrollDetailColumns()
        .where((c) => !{'salaryType', 'position'}.contains(c.key))
        .toList();
  }

  Color _payrollCellDisplayColor(String key, Map<String, dynamic> row) {
    final c = _getCellColor(key, row);
    if (c != null) return c;
    switch (key) {
      case 'netSalary':
        return SboxColors.brand700;
      case 'totalSalary':
        return SboxColors.payHover;
      case 'totalDeduction':
        return Colors.red.shade700;
      default:
        return SboxColors.slate900;
    }
  }

  Widget _buildVerticalPayrollTable(List<Map<String, dynamic>> data) {
    final cols = _mobileVerticalPayrollColumns();
    if (cols.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(tr('Chưa có cột dữ liệu hiển thị.\nVui lòng bật thêm cột trong cài đặt bảng lương.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SboxColors.slate500),
          ),
        ),
      );
    }
    final headers = cols.map((c) => c.label).toList();
    final widths = cols.map((c) => _payrollColWidth(c)).toList();

    final rows = data.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;
      final code = row['code']?.toString() ?? '';
      final dept = row['department']?.toString() ?? '';
      return MobilePayrollVerticalRow(
        employeeName: row['name']?.toString() ?? '',
        employeeSubtitle: '$code${dept.isNotEmpty ? ' · $dept' : ''}',
        cells: cols
            .map((c) => _formatCellValue(c.key, row, index))
            .toList(),
        cellColors:
            cols.map((c) => _payrollCellDisplayColor(c.key, row)).toList(),
        onTap: () => _showEmployeeDetail(row),
      );
    }).toList();

    final totalRow = rows.isEmpty
        ? null
        : MobilePayrollVerticalRow(
            employeeName: 'TỔNG CỘNG',
            employeeSubtitle: '${data.length} NV',
            cells: cols.map((c) => _payrollTotalCellText(c, data)).toList(),
            cellColors: cols.map((c) {
              final text = _payrollTotalCellText(c, data);
              if (text.isEmpty || text == '—') return null;
              if (c.key == 'netSalary') return SboxColors.brand800;
              if (c.key == 'totalSalary') return SboxColors.payHover;
              if (c.key == 'totalDeduction') return Colors.red.shade700;
              return SboxColors.brand800;
            }).toList(),
          );

    return MobilePayrollVerticalTable(
      title: 'Tổng hợp lương',
      headers: headers,
      columnWidths: widths,
      rows: rows,
      totalRow: totalRow,
    );
  }
}

class _SummaryItem {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _SummaryItem(this.label, this.value, this.color, this.icon);
}

/// A ListView that follows the scroll position of a main ScrollController.
class _SyncedListView extends StatefulWidget {
  final ScrollController mainController;
  final int itemCount;
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;

  const _SyncedListView({
    required this.mainController,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
  });

  @override
  State<_SyncedListView> createState() => _SyncedListViewState();
}

class _SyncedListViewState extends State<_SyncedListView> {
  late final ScrollController _followerController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _followerController = ScrollController();
    widget.mainController.addListener(_onMainScroll);
    _followerController.addListener(_onFollowerScroll);
  }

  void _onMainScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (_followerController.hasClients && widget.mainController.hasClients) {
      _followerController.jumpTo(widget.mainController.offset);
    }
    _isSyncing = false;
  }

  void _onFollowerScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (widget.mainController.hasClients && _followerController.hasClients) {
      widget.mainController.jumpTo(_followerController.offset);
    }
    _isSyncing = false;
  }

  @override
  void dispose() {
    widget.mainController.removeListener(_onMainScroll);
    _followerController.removeListener(_onFollowerScroll);
    _followerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        controller: _followerController,
        itemCount: widget.itemCount,
        itemExtent: widget.itemExtent,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}
