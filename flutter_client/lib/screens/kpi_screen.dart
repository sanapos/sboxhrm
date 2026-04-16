import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../utils/file_saver.dart' as file_saver;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class KpiScreen extends StatefulWidget {
  const KpiScreen({super.key});

  @override
  State<KpiScreen> createState() => _KpiScreenState();
}

class _KpiScreenState extends State<KpiScreen> with TickerProviderStateMixin {
  static const _accent = Color(0xFF1E3A5F);
  static const _green = Color(0xFF10B981);
  static const _blue = Color(0xFF3B82F6);
  static const _amber = Color(0xFFF59E0B);
  static const _red = Color(0xFFEF4444);
  static const _purple = Color(0xFF8B5CF6);

  final ApiService _api = ApiService();
  final _cur = NumberFormat('#,###', 'vi_VN');
  late TabController _tabCtrl;
  bool _loading = false;

  // --- Data ---
  List<Map<String, dynamic>> _periods = [];
  List<Map<String, dynamic>> _targets = [];
  List<Map<String, dynamic>> _salaries = [];
  List<Map<String, dynamic>> _employees = [];
  // ignore: unused_field
  Map<String, dynamic>? _dashboard;

  String? _selPeriodId;

  // --- GSheet Credentials ---
  bool _credentialsConfigured = false;
  // ignore: unused_field
  String? _serviceAccountEmail;
  bool _credentialsLoading = false;
  bool _creatingTemplate = false;

  // --- Filters ---
  String? _filterDepartment;
  String? _filterEmployeeId;

  // --- Mobile UI ---
  bool _showMobileFilters = false;

  // --- Export ---
  final GlobalKey _dashboardKey = GlobalKey();
  final GlobalKey _targetsKey = GlobalKey();
  final GlobalKey _salaryKey = GlobalKey();
  bool _isExporting = false;

  // Pagination
  int _salaryPage = 1;
  int _salaryPageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        final i = _tabCtrl.index;
        if (i >= 2 && _selPeriodId != null) _loadPeriodData();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final r = await Future.wait<dynamic>([
        _api.getKpiPeriods(),
        _api.getKpiDashboard(),
        _api.getEmployees(),
      ]);
      setState(() {
        if (r[0]['isSuccess'] == true) _periods = List<Map<String, dynamic>>.from(r[0]['data'] ?? []);
        if (r[1]['isSuccess'] == true) _dashboard = r[1]['data'];
        _employees = (r[2] is List) ? List<Map<String, dynamic>>.from(r[2]) : [];
        if (_periods.isNotEmpty && _selPeriodId == null) {
          _selPeriodId = _periods.first['id']?.toString();
        }
      });
      if (_selPeriodId != null) await _loadPeriodData();
      _loadCredentialsStatus();
    } catch (e) {
      debugPrint('Error loading KPI: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPeriodData() async {
    if (_selPeriodId == null) return;
    try {
      final r = await Future.wait([
        _api.getKpiEmployeeTargets(periodId: _selPeriodId),
        _api.getKpiSalaries(_selPeriodId!),
      ]);
      if (mounted) {
        setState(() {
          if (r[0]['isSuccess'] == true) _targets = List<Map<String, dynamic>>.from(r[0]['data'] ?? []);
          if (r[1]['isSuccess'] == true) _salaries = List<Map<String, dynamic>>.from(r[1]['data'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Load KPI data error: $e');
    }
  }

  // ------------------------------------------------
  //  BUILD
  // ------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(
        children: [
          _buildHeader(),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: TabBar(
              controller: _tabCtrl,
              isScrollable: true,
              labelColor: _accent,
              unselectedLabelColor: Colors.grey[500],
              indicatorColor: _accent,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: 'Tổng quan'),
                Tab(icon: Icon(Icons.calendar_month_rounded, size: 18), text: 'Chu kỳ'),
                Tab(icon: Icon(Icons.track_changes_rounded, size: 18), text: 'Chỉ tiêu & Tiến độ'),
                Tab(icon: Icon(Icons.account_balance_wallet_rounded, size: 18), text: 'Lương KPI'),
                Tab(icon: Icon(Icons.cloud_sync_rounded, size: 18), text: 'Cấu hình GSheet'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 48, height: 48,
                          child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(_accent)),
                        ),
                        const SizedBox(height: 16),
                        Text('Đang tải dữ liệu...', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                      ],
                    ),
                  )
                : TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildDashboardTab(theme),
                      _buildPeriodsTab(theme),
                      _buildTargetsTab(theme),
                      _buildSalaryTab(theme),
                      _buildGSheetConfigTab(theme),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final currentPeriod = _periods.isNotEmpty
        ? _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => _periods.first)
        : null;
    final periodStatus = currentPeriod != null ? _periodStatusInt(currentPeriod['status']) : -1;
    final statusLabel = periodStatus >= 0 ? _periodStatusLabel(periodStatus) : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2340), Color(0xFF1E3A5F), Color(0xFF2A5298)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up_rounded, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Quản lý KPI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3), overflow: TextOverflow.ellipsis),
                ),
                if (statusLabel.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _periodStatusColor(periodStatus).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Text(statusLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: IconButton(
                    icon: Stack(
                      children: [
                        Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, color: Colors.white, size: 18),
                        if (_filterDepartment != null || _filterEmployeeId != null)
                          Positioned(right: 0, top: 0, child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                      ],
                    ),
                    onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
                    tooltip: 'Bộ lọc',
                    constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            if (_periods.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: DropdownButton<String>(
                  value: _selPeriodId,
                  dropdownColor: const Color(0xFF0F2340),
                  isExpanded: true,
                  isDense: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  underline: const SizedBox(),
                  icon: const Icon(Icons.expand_more_rounded, color: Colors.white70, size: 18),
                  items: _periods.map((p) => DropdownMenuItem(
                    value: p['id']?.toString(),
                    child: Text(p['name'] ?? ''),
                  )).toList(),
                  onChanged: (v) {
                    setState(() => _selPeriodId = v);
                    _loadPeriodData();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------
  //  FILTERS & EXPORT HELPERS
  // ------------------------------------------------

  List<String> get _departments {
    final depts = <String>{};
    for (final t in _targets) {
      final d = t['department']?.toString();
      if (d != null && d.isNotEmpty) depts.add(d);
    }
    return depts.toList()..sort();
  }

  List<Map<String, dynamic>> get _filteredTargets {
    var list = _targets;
    if (_filterDepartment != null) {
      list = list.where((t) => t['department']?.toString() == _filterDepartment).toList();
    }
    if (_filterEmployeeId != null) {
      list = list.where((t) => t['employeeId']?.toString() == _filterEmployeeId).toList();
    }
    return list;
  }

  List<Map<String, dynamic>> get _filteredSalaries {
    if (_filterDepartment == null && _filterEmployeeId == null) return _salaries;
    final filteredEmpIds = _filteredTargets.map((t) => t['employeeId']?.toString()).toSet();
    return _salaries.where((s) => filteredEmpIds.contains(s['employeeId']?.toString())).toList();
  }

  Widget _buildFilterRow(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list_rounded, size: 18, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _filterDepartment,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Phòng ban',
                labelStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent)),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả', style: TextStyle(fontSize: 12))),
                ..._departments.map((d) => DropdownMenuItem(value: d, child: Text(d, style: const TextStyle(fontSize: 12)))),
              ],
              onChanged: (v) => setState(() { _filterDepartment = v; _filterEmployeeId = null; }),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _filterEmployeeId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Nhân viên',
                labelStyle: TextStyle(fontSize: 12, color: Colors.grey[500]),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _accent)),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả', style: TextStyle(fontSize: 12))),
                ...(_filterDepartment != null
                    ? _targets.where((t) => t['department']?.toString() == _filterDepartment)
                    : _targets
                ).map((t) => DropdownMenuItem(
                  value: t['employeeId']?.toString(),
                  child: Text(t['employeeName']?.toString() ?? '', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                )),
              ],
              onChanged: (v) => setState(() => _filterEmployeeId = v),
            ),
          ),
          if (_filterDepartment != null || _filterEmployeeId != null) ...[
            const SizedBox(width: 4),
            Container(
              decoration: BoxDecoration(color: _red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: IconButton(
                onPressed: () => setState(() { _filterDepartment = null; _filterEmployeeId = null; }),
                icon: const Icon(Icons.clear_rounded, size: 18, color: _red),
                tooltip: 'Xóa bộ lọc',
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _exportPng(GlobalKey key, String filePrefix) async {
    setState(() => _isExporting = true);
    try {
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        NotificationOverlayManager().showWarning(title: 'Lỗi', message: 'Không tìm thấy nội dung để chụp');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final pngBytes = byteData.buffer.asUint8List();
      final fileName = '${filePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
      await file_saver.saveFileBytes(pngBytes, fileName, 'image/png');
      if (mounted) NotificationOverlayManager().showSuccess(title: 'Xuất PNG', message: 'Đã xuất ảnh: $fileName');
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xuất PNG: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportTargetsExcel() async {
    final data = _filteredTargets;
    if (data.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Không có dữ liệu', message: 'Không có dữ liệu để xuất');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final workbook = excel_lib.Excel.createExcel();
      final sheet = workbook['Nhân viên'];
      if (workbook.sheets.containsKey('Sheet1')) workbook.delete('Sheet1');

      final headerStyle = excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#6366F1'),
        fontColorHex: excel_lib.ExcelColor.white,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        fontSize: 11,
      );

      // Headers gi?ng Google Sheet: Mã NV, Tên NV, Tổng KPI, Chỉ tiêu
      final headers = ['Mã NV', 'Tên NV', 'Tổng KPI', 'Chỉ tiêu'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel_lib.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }
      sheet.setColumnWidth(0, 18);
      sheet.setColumnWidth(1, 25);
      sheet.setColumnWidth(2, 18);
      sheet.setColumnWidth(3, 18);

      for (int i = 0; i < data.length; i++) {
        final t = data[i];
        final row = i + 1;
        final empCode = t['employeeCode']?.toString() ?? '';
        final empName = t['employeeName']?.toString() ?? '';
        final actual = ((t['actualValue'] ?? 0) as num).toDouble();
        final target = ((t['targetValue'] ?? 0) as num).toDouble();

        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = excel_lib.TextCellValue(empCode);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = excel_lib.TextCellValue(empName);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = excel_lib.DoubleCellValue(actual);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = excel_lib.DoubleCellValue(target);
      }

      final bytes = workbook.encode();
      if (bytes == null) throw Exception('Không thể tạo file');
      final fileName = 'KPI_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
      await file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (mounted) NotificationOverlayManager().showSuccess(title: 'Xuất Excel', message: 'Đã xuất Excel: $fileName');
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xuất Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportSalaryExcel() async {
    final targets = _filteredTargets;
    if (targets.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Không có dữ liệu', message: 'Không có dữ liệu để xuất');
      return;
    }
    setState(() => _isExporting = true);
    try {
      final workbook = excel_lib.Excel.createExcel();
      final sheet = workbook['Lương KPI'];
      if (workbook.sheets.containsKey('Sheet1')) workbook.delete('Sheet1');

      final headerStyle = excel_lib.CellStyle(
        bold: true,
        backgroundColorHex: excel_lib.ExcelColor.fromHexString('#6366F1'),
        fontColorHex: excel_lib.ExcelColor.white,
        horizontalAlign: excel_lib.HorizontalAlign.Center,
        fontSize: 11,
      );

      final headers = ['Mã NV', 'Tên NV', 'Tổng KPI', 'Chỉ tiêu', 'Tỷ lệ (%)', 'Thưởng/Phạt', 'Lương HT', 'Tổng thưởng'];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = excel_lib.TextCellValue(headers[i]);
        cell.cellStyle = headerStyle;
      }
      sheet.setColumnWidth(0, 18);
      sheet.setColumnWidth(1, 25);
      for (int c = 2; c < headers.length; c++) {
        sheet.setColumnWidth(c, 18);
      }

      for (int i = 0; i < targets.length; i++) {
        final t = targets[i];
        final tgt = ((t['targetValue'] ?? 0) as num).toDouble();
        final act = ((t['actualValue'] ?? 0) as num).toDouble();
        final pct = ((t['completionRate'] ?? 0) as num).toDouble();
        final completionSalary = ((t['completionSalary'] ?? 0) as num).toDouble();
        final tierBonuses = _calcTierBonuses(t);
        final penaltyBonus = _calcPenaltyBonus(t);
        final salaryHT = pct >= 100 ? completionSalary : (completionSalary * pct / 100);
        final totalTierBonus = tierBonuses.fold<double>(0, (s, b) => s + ((b['bonus'] as num?)?.toDouble() ?? 0));
        final totalSalary = math.max(0.0, salaryHT + penaltyBonus + totalTierBonus);

        final row = i + 1;
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = excel_lib.TextCellValue(t['employeeCode']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = excel_lib.TextCellValue(t['employeeName']?.toString() ?? '');
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = excel_lib.DoubleCellValue(act);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = excel_lib.DoubleCellValue(tgt);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = excel_lib.DoubleCellValue(pct);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = excel_lib.DoubleCellValue(penaltyBonus);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row)).value = excel_lib.DoubleCellValue(salaryHT);
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row)).value = excel_lib.DoubleCellValue(totalSalary);
      }

      final bytes = workbook.encode();
      if (bytes == null) throw Exception('Không thể tạo file');
      final fileName = 'Luong_KPI_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
      await file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      if (mounted) NotificationOverlayManager().showSuccess(title: 'Xuất Excel', message: 'Đã xuất Excel: $fileName');
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xuất Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ------------------------------------------------
  //  TAB 1: TỔNG QUAN
  // ------------------------------------------------

  Widget _buildDashboardTab(ThemeData theme) {
    final filteredTargets = _filteredTargets;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter row + export button
          Row(
            children: [
              if (!Responsive.isMobile(context) || _showMobileFilters)
                Expanded(child: _buildFilterRow(theme))
              else
                const Spacer(),
              const SizedBox(width: 12),
              if (Provider.of<PermissionProvider>(context, listen: false).canExport('KPI'))
              OutlinedButton.icon(
                onPressed: _isExporting ? null : () => _exportPng(_dashboardKey, 'TongQuan_KPI'),
                icon: const Icon(Icons.image, size: 18),
                label: Text(_isExporting ? 'Đang xuất...' : 'Xuất PNG'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: _dashboardKey,
            child: Container(
              color: theme.scaffoldBackgroundColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(builder: (context, constraints) {
                    final avgPct = filteredTargets.isNotEmpty
                        ? filteredTargets.map((t) => ((t['completionRate'] ?? 0) as num).toDouble()).reduce((a, b) => a + b) / filteredTargets.length
                        : 0.0;
                    final totalBonus = _filteredSalaries.fold<double>(0, (sum, s) => sum + ((s['kpiBonusAmount'] ?? 0) as num).toDouble());
                    final isMobile = constraints.maxWidth < 600;
                    final cards = [
                      _statCard('Nhân viên', '${filteredTargets.length}', Icons.people, _accent),
                      _statCard('Đạt mục tiêu', '${filteredTargets.where((t) => (t['completionRate'] ?? 0) >= 100).length}', Icons.check_circle, _green),
                      _statCard('Chưa đạt', '${filteredTargets.where((t) => (t['completionRate'] ?? 0) < 100 && t['actualValue'] != null).length}', Icons.warning_amber, _amber),
                      _statCard('Tiến độ TB', '${avgPct.toStringAsFixed(1)}%', Icons.analytics, _blue),
                      _statCard('Tổng thưởng', _cur.format(totalBonus), Icons.monetization_on, const Color(0xFF0F2340)),
                    ];
                    if (isMobile) {
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: cards.map((c) => SizedBox(width: (constraints.maxWidth - 10) / 2, child: c)).toList(),
                      );
                    }
                    return Row(children: [
                      for (int i = 0; i < cards.length; i++) ...[
                        if (i > 0) const SizedBox(width: 14),
                        Expanded(child: cards[i]),
                      ],
                    ]);
                  }),
                  const SizedBox(height: 24),
                  _buildProgressOverview(theme),
                  const SizedBox(height: 24),
                  _buildTopPerformers(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tính % tiến độ theo ngày trong chu k? (tính chính xác theo giờ)
  double _dayProgressPct() {
    final period = _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => {});
    if (period.isEmpty) return 0;
    try {
      final start = DateTime.parse(period['periodStart'].toString());
      final end = DateTime.parse(period['periodEnd'].toString());
      final now = DateTime.now();
      final totalHours = end.difference(start).inHours;
      if (totalHours <= 0) return 0;
      final elapsedHours = now.difference(start).inHours.clamp(0, totalHours);
      return (elapsedHours / totalHours * 100).clamp(0, 100);
    } catch (_) { return 0; }
  }

  Widget _buildProgressOverview(ThemeData theme) {
    final dayPct = _dayProgressPct();

    return _card('Tiến độ chỉ tiêu', Icons.trending_up, _accent, child: _filteredTargets.isEmpty
        ? const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Chưa có chỉ tiêu nào')))
        : LayoutBuilder(builder: (context, progConstraints) {
            final isNarrow = progConstraints.maxWidth < 500;
            return Column(children: [
            // Day progress legend
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Wrap(spacing: 12, runSpacing: 4, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 4, decoration: BoxDecoration(color: _amber, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text('Tiến độ ngày: ${dayPct.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, color: Color(0xFFD97706), fontWeight: FontWeight.w600)),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 4, decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text('Dưới tiến độ', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 4, decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text('Trên tiến độ', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 12, height: 4, decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 4),
                  Text('Vượt chỉ tiêu', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                ]),
              ]),
            ),
            ..._filteredTargets.take(8).map((t) {
              final pct = ((t['completionRate'] ?? 0) as num).toDouble();
              final name = t['employeeName'] ?? '';
              final target = (t['targetValue'] as num?)?.toDouble() ?? 0;
              final actual = (t['actualValue'] as num?)?.toDouble() ?? 0;
              final expectedValue = target * dayPct / 100;
              final Color color;
              if (pct >= 100) {
                color = _green;
              } else if (actual >= expectedValue) {
                color = _blue;
              } else {
                color = _red;
              }
              final behindSchedule = actual < expectedValue && pct < 100;
              if (isNarrow) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                      Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                    ]),
                    const SizedBox(height: 4),
                    Stack(children: [
                      Container(height: 16, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8))),
                      FractionallySizedBox(
                        widthFactor: (dayPct / 100).clamp(0, 1),
                        child: Container(height: 16, decoration: BoxDecoration(color: _amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8))),
                      ),
                      FractionallySizedBox(
                        widthFactor: (pct / 100).clamp(0, 1),
                        child: Container(
                          height: 16,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [color.withValues(alpha: 0.7), color]),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    Text('${_cur.format(actual)} / ${_cur.format(target)}', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                    if (behindSchedule) Text('Kỳ vọng: ${_cur.format(expectedValue)}', style: const TextStyle(color: Color(0xFFD97706), fontSize: 10)),
                  ]),
                );
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  SizedBox(width: 140, child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                  Expanded(child: Stack(children: [
                    // Background
                    Container(height: 16, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8))),
                    // Day progress marker (background fill)
                    Positioned(
                      left: 0, right: 0, top: 0, bottom: 0,
                      child: FractionallySizedBox(
                        widthFactor: (dayPct / 100).clamp(0, 1),
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    // Actual progress bar with gradient
                    FractionallySizedBox(
                      widthFactor: (pct / 100).clamp(0, 1),
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [color. withValues(alpha: 0.7), color]),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: pct > 15 ? Center(child: Text('${pct.toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700))) : null,
                      ),
                    ),
                    // Day progress line marker
                    Positioned(
                      left: 0, right: 0, top: 0, bottom: 0,
                      child: FractionallySizedBox(
                        widthFactor: (dayPct / 100).clamp(0, 1),
                        alignment: Alignment.centerLeft,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 2,
                            decoration: BoxDecoration(color: const Color(0xFFD97706), borderRadius: BorderRadius.circular(1)),
                          ),
                        ),
                      ),
                    ),
                  ])),
                  const SizedBox(width: 8),
                  SizedBox(width: 55, child: Text('${pct.toStringAsFixed(0)}%', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 13))),
                  const SizedBox(width: 8),
                  SizedBox(width: 120, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${_cur.format(actual)} / ${_cur.format(target)}', textAlign: TextAlign.right, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      if (behindSchedule) Text('Kỳ vọng: ${_cur.format(expectedValue)}', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFFD97706), fontSize: 10)),
                    ],
                  )),
                ]),
              );
            }),
          ]);
          }),
    );
  }

  Widget _buildTopPerformers(ThemeData theme) {
    final sorted = List<Map<String, dynamic>>.from(_filteredTargets.where((t) => t['actualValue'] != null));
    sorted.sort((a, b) => ((b['completionRate'] ?? 0) as num).compareTo((a['completionRate'] ?? 0) as num));
    final top = sorted.take(5).toList();
    return _card('Top hiệu suất', Icons.emoji_events, _amber, child: top.isEmpty
        ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Chưa có dữ liệu')))
        : LayoutBuilder(builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 500;
            return Column(children: top.asMap().entries.map((e) {
            final i = e.key;
            final t = e.value;
            final pct = ((t['completionRate'] ?? 0) as num).toDouble();
            final medals = ['🥇', '🥈', '🥉'];
            final rankColors = [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32), Colors.grey.shade300, Colors.grey.shade200];
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: i < 3
                    ? LinearGradient(colors: [rankColors[i].withValues(alpha: 0.08), Colors.white])
                    : null,
                color: i >= 3 ? Colors.white : null,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: i < 3 ? rankColors[i].withValues(alpha: 0.2) : Colors.grey.shade100),
              ),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      gradient: i < 3
                          ? LinearGradient(colors: [rankColors[i].withValues(alpha: 0.3), rankColors[i].withValues(alpha: 0.1)])
                          : null,
                      color: i >= 3 ? Colors.grey.shade100 : null,
                      shape: BoxShape.circle,
                    ),
                    child: Center(child: Text(i < 3 ? medals[i] : '${i + 1}', style: TextStyle(fontSize: i < 3 ? 20 : 14, fontWeight: FontWeight.w700))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['employeeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(t['department'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  )),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('${pct.toStringAsFixed(1)}%', style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16,
                      color: pct >= 100 ? _green : pct >= 70 ? _amber : _red,
                    )),
                  ),
                  if (!isMobile) ...[
                    _actionIconBtn(Icons.phone, 'Gọi điện', _green, () => _showActionConfirm(t, 'call')),
                    _actionIconBtn(Icons.description, 'Yêu cầu giải trình', _amber, () => _showActionConfirm(t, 'explain')),
                    _actionIconBtn(Icons.event, 'Lên lịch họp', _blue, () => _showActionConfirm(t, 'meeting')),
                    _actionIconBtn(Icons.assignment, 'Báo cáo', _accent, () => _showDailyReportDialog(t)),
                  ],
                ]),
                if (isMobile) Padding(
                  padding: const EdgeInsets.only(left: 52, top: 4),
                  child: Row(children: [
                    _actionIconBtn(Icons.phone, 'Gọi điện', _green, () => _showActionConfirm(t, 'call')),
                    _actionIconBtn(Icons.description, 'Yêu cầu giải trình', _amber, () => _showActionConfirm(t, 'explain')),
                    _actionIconBtn(Icons.event, 'Lên lịch họp', _blue, () => _showActionConfirm(t, 'meeting')),
                    _actionIconBtn(Icons.assignment, 'Báo cáo', _accent, () => _showDailyReportDialog(t)),
                  ]),
                ),
              ]),
            );
          }).toList());
          }),
    );
  }

  Widget _actionIconBtn(IconData icon, String tooltip, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(7),
              child: Icon(icon, size: 16, color: color),
            ),
          ),
        ),
      ),
    );
  }

  void _showActionConfirm(Map<String, dynamic> target, String actionType) {
    final name = target['employeeName'] ?? '';
    String title, content;
    IconData icon;
    Color color;

    switch (actionType) {
      case 'call':
        title = 'Gọi điện cho $name';
        content = 'Bạn muốn gọi điện cho nhân viên $name để trao đổi về tiến độ KPI?';
        icon = Icons.phone;
        color = _green;
        break;
      case 'explain':
        title = 'Yêu cầu giải trình';
        content = 'Gửi yêu cầu giải trình cho $name về tiến độ chỉ tiêu hiện tại?';
        icon = Icons.description;
        color = _amber;
        break;
      case 'meeting':
        title = 'Lên lịch họp với $name';
        content = 'Tạo lịch họp để đánh giá tiến độ KPI với $name?';
        icon = Icons.event;
        color = _blue;
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(
          width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(content, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            if (actionType == 'explain') ...[
              TextField(
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Nội dung yêu cầu (tùy chọn)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
              ),
            ],
            if (actionType == 'meeting') ...[
              ListTile(
                dense: true,
                leading: const Icon(Icons.calendar_today, size: 18),
                title: Text('Ngày: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}'),
                subtitle: Text('Gi?: ${DateFormat('HH:mm').format(DateTime.now().add(const Duration(hours: 1)))}'),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              NotificationOverlayManager().showInfo(title: 'Thông báo', message: actionType == 'call' ? 'Đã tạo nhắc nhở gọi điện $name'
                    : actionType == 'explain' ? 'Đã gửi yêu cầu giải trình cho $name'
                    : 'Đã lên lịch họp với $name');
            },
            icon: Icon(icon, size: 16),
            label: const Text('Xác nhận'),
            style: FilledButton.styleFrom(backgroundColor: color),
          ),
        ],
      ),
    );
  }

  void _showDailyReportDialog(Map<String, dynamic> target) {
    final name = target['employeeName'] ?? '';
    final isMobile = Responsive.isMobile(context);
    final dialogTitle = 'Báo cáo công việc - $name';

    showDialog(
      context: context,
      builder: (ctx) {
        final content = Column(children: [
          Row(children: [
            const Text('Tuần này', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _accent)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _showSubmitReportDialog(target);
              },
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Yêu cầu báo cáo', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: _accent),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 24),
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.assignment_outlined, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('Chưa có báo cáo nào', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
                const SizedBox(height: 8),
                Text('Nhấn "Yêu cầu báo cáo" để gửi yêu cầu cho nhân viên.', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              ]),
            ),
          ),
        ]);

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(dialogTitle, style: const TextStyle(fontSize: 16)),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ),
              body: Padding(padding: const EdgeInsets.all(16), child: content),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            const Icon(Icons.assignment, color: _accent, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(dialogTitle, style: const TextStyle(fontSize: 16))),
          ]),
          content: SizedBox(
            width: math.min(600, MediaQuery.of(context).size.width - 32).toDouble(),
            height: 450,
            child: content,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        );
      },
    );
  }

  void _showSubmitReportDialog(Map<String, dynamic> target) {
    final name = target['employeeName'] ?? '';
    final contentCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final isMobile = Responsive.isMobile(context);
    final dialogTitle = 'Yêu cầu báo cáo - $name';

    void onSubmit(BuildContext ctx) {
      Navigator.pop(ctx);
      NotificationOverlayManager().showInfo(title: 'Thông báo', message: 'Đã gửi yêu cầu báo cáo cho $name');
    }

    showDialog(
      context: context,
      builder: (ctx) {
        final formBody = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Gửi yêu cầu báo cáo công việc hàng ngày cho nhân viên $name. '
                'Nhân viên sẽ nhận thông báo và cần nộp báo cáo.',
                style: TextStyle(color: Colors.blue.shade700, fontSize: 11),
              )),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: contentCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Nội dung yêu cầu *',
              hintText: 'VD: Báo cáo tiến độ doanh số, khách hàng mới...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: noteCtrl,
            decoration: InputDecoration(
              labelText: 'Ghi chú (tùy chọn)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ]);

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(dialogTitle, style: const TextStyle(fontSize: 16)),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: () => onSubmit(ctx),
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Gửi yêu cầu'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(dialogTitle, style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: math.min(500, MediaQuery.of(context).size.width - 32).toDouble(),
            child: formBody,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () => onSubmit(ctx),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Gửi yêu cầu'),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------
  //  TAB 2: CHU KỲ
  // ------------------------------------------------

  Widget _buildPeriodsTab(ThemeData theme) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: _accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.calendar_month_rounded, color: _accent, size: 20),
          ),
          const SizedBox(width: 12),
          Text('Chu kỳ đánh giá', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
            child: Text('${_periods.length}', style: const TextStyle(color: _accent, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _showPeriodDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Tạo chu kỳ'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ]),
      ),
      Expanded(
        child: _periods.isEmpty
            ? _emptyState('Chưa có chu kỳ đánh giá', Icons.calendar_today)
            : Responsive.isMobile(context)
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _periods.length,
                  itemBuilder: (_, i) => Padding(
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
                      child: _buildPeriodDeckItem(_periods[i]),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _periods.length,
                  itemBuilder: (_, i) => _buildPeriodCard(_periods[i]),
                ),
      ),
    ]);
  }

  Widget _buildPeriodDeckItem(Map<String, dynamic> p) {
    final status = _periodStatusInt(p['status']);
    final statusLabel = _periodStatusLabel(status);
    final statusColor = _periodStatusColor(status);
    final isCurrent = p['id']?.toString() == _selPeriodId;
    final name = p['name']?.toString() ?? '';
    final start = DateTime.tryParse((p['startDate'] ?? '').toString());
    final end = DateTime.tryParse((p['endDate'] ?? '').toString());

    return InkWell(
      onTap: () {
        setState(() => _selPeriodId = p['id']?.toString());
        _loadPeriodData();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              status == 3 ? Icons.verified : status == 2 ? Icons.calculate : status == 1 ? Icons.lock : Icons.lock_open,
              color: statusColor, size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (isCurrent) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(6)),
                  child: const Text('ĐANG CHỌN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  if (start != null) '${start.day}/${start.month}/${start.year}',
                  if (end != null) '→ ${end.day}/${end.month}/${end.year}',
                ].join(' '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  Widget _buildPeriodCard(Map<String, dynamic> p) {
    final status = _periodStatusInt(p['status']);
    final statusLabel = _periodStatusLabel(status);
    final statusColor = _periodStatusColor(status);
    final isCurrent = p['id']?.toString() == _selPeriodId;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isCurrent ? _accent : Colors.grey.shade100, width: isCurrent ? 2 : 1),
          boxShadow: [
            if (isCurrent)
              BoxShadow(color: _accent.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 4))
            else
              BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                status == 0 ? Icons.lock_open_rounded : status == 1 ? Icons.lock_rounded : status == 2 ? Icons.calculate_rounded : Icons.verified_rounded,
                color: statusColor, size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (isCurrent) Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: _accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: const Text('ĐANG CHỌN', style: TextStyle(color: _accent, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ),
                Expanded(child: Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.date_range_rounded, size: 13, color: Colors.grey[400]),
                const SizedBox(width: 4),
                Text('${_fmtDate(p['periodStart'])} → ${_fmtDate(p['periodEnd'])}', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
              ]),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [statusColor.withValues(alpha: 0.15), statusColor.withValues(alpha: 0.05)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 14),
          // Status workflow steps
          Row(children: [
            _stepDot(0, status, 'Mở'),
            _stepLine(status >= 1),
            _stepDot(1, status, 'Khóa'),
            _stepLine(status >= 2),
            _stepDot(2, status, 'Tính lương'),
            _stepLine(status >= 3),
            _stepDot(3, status, 'Duyệt'),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            if (status == 0 && Provider.of<PermissionProvider>(context, listen: false).canApprove('KPI')) _chip('Khóa', Icons.lock_rounded, _amber, () => _updatePeriodStatus(p['id'], 1)),
            if (status == 1 && Provider.of<PermissionProvider>(context, listen: false).canApprove('KPI')) _chip('Mở lại', Icons.lock_open_rounded, Colors.grey, () => _updatePeriodStatus(p['id'], 0)),
            if (status == 1) _chip('Tính lương', Icons.calculate_rounded, _blue, () => _calculateSalary(p['id']?.toString())),
            if (status == 2 && Provider.of<PermissionProvider>(context, listen: false).canApprove('KPI')) _chip('Duyệt', Icons.verified_rounded, _green, () => _updatePeriodStatus(p['id'], 3)),
            const Spacer(),
            if (!isCurrent) TextButton.icon(
              onPressed: () {
                setState(() => _selPeriodId = p['id']?.toString());
                _loadPeriodData();
              },
              icon: const Icon(Icons.visibility_rounded, size: 16),
              label: const Text('Chọn', style: TextStyle(fontSize: 12)),
            ),
            if (Provider.of<PermissionProvider>(context, listen: false).canDelete('KPI'))
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              color: Colors.red.shade300,
              onPressed: () => _deleteItem(() => _api.deleteKpiPeriod(p['id'].toString())),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _stepDot(int step, int currentStatus, String label) {
    final isActive = currentStatus >= step;
    final isCurrent = currentStatus == step;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: isCurrent ? 22 : 16,
        height: isCurrent ? 22 : 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive ? _periodStatusColor(step) : Colors.grey.shade200,
          border: isCurrent ? Border.all(color: _periodStatusColor(step).withValues(alpha: 0.3), width: 3) : null,
        ),
        child: isActive ? const Icon(Icons.check, size: 10, color: Colors.white) : null,
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 9, color: isActive ? _periodStatusColor(step) : Colors.grey[400], fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
    ]);
  }

  Widget _stepLine(bool isActive) {
    return Expanded(child: Container(
      height: 2,
      margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
      decoration: BoxDecoration(
        color: isActive ? _green.withValues(alpha: 0.4) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(1),
      ),
    ));
  }

  int _periodStatusInt(dynamic s) {
    if (s is int) return s;
    final str = s?.toString() ?? '';
    if (str == 'Open' || str == '0') return 0;
    if (str == 'Locked' || str == '1') return 1;
    if (str == 'Calculated' || str == '2') return 2;
    if (str == 'Approved' || str == '3') return 3;
    return 0;
  }

  String _periodStatusLabel(int s) {
    switch (s) {
      case 0: return 'Mở';
      case 1: return 'Đã khóa';
      case 2: return 'Đã tính lương';
      case 3: return 'Đã duyệt';
      default: return 'Mở';
    }
  }

  Color _periodStatusColor(int s) {
    switch (s) {
      case 0: return _green;
      case 1: return _amber;
      case 2: return _blue;
      case 3: return const Color(0xFF0F2340);
      default: return Colors.grey;
    }
  }

  void _showPeriodDialog() {
    final nameCtrl = TextEditingController();
    final yearCtrl = TextEditingController(text: DateTime.now().year.toString());
    final monthCtrl = TextEditingController(text: DateTime.now().month.toString());
    DateTime startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
    DateTime endDate = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        Future<void> onSave() async {
          final data = {
            'name': nameCtrl.text.isNotEmpty ? nameCtrl.text : 'Tháng ${monthCtrl.text}/${yearCtrl.text}',
            'year': int.tryParse(yearCtrl.text) ?? DateTime.now().year,
            'month': int.tryParse(monthCtrl.text) ?? DateTime.now().month,
            'periodStart': startDate.toIso8601String(),
            'periodEnd': endDate.toIso8601String(),
            'frequency': 0,
          };
          final res = await _api.createKpiPeriod(data);
          if (ctx.mounted) Navigator.pop(ctx);
          if (res['isSuccess'] == true) await _loadData(showLoading: false);
        }

        final formBody = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field(nameCtrl, 'Tên chu kỳ (VD: Tháng 03/2026)'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(yearCtrl, 'Nam', number: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(monthCtrl, 'Tháng', number: true)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: ListTile(
              dense: true,
              title: Text('T?: ${DateFormat('dd/MM/yyyy').format(startDate)}'),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDate: startDate);
                if (d != null) ss(() => startDate = d);
              },
            )),
            Expanded(child: ListTile(
              dense: true,
              title: Text('Đến: ${DateFormat('dd/MM/yyyy').format(endDate)}'),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime(2030), initialDate: endDate);
                if (d != null) ss(() => endDate = d);
              },
            )),
          ]),
        ]);

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Tạo chu kỳ đánh giá'),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Tạo'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Tạo chu kỳ đánh giá'),
          content: SizedBox(
            width: math.min(450, MediaQuery.of(context).size.width - 32).toDouble(),
            child: formBody,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Tạo'),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _updatePeriodStatus(dynamic id, int status) async {
    await _api.updateKpiPeriodStatus(id.toString(), status.toString());
    await _loadData(showLoading: false);
  }

  Future<void> _calculateSalary(String? periodId) async {
    if (periodId == null) return;
    setState(() => _loading = true);
    final res = await _api.calculateKpiSalary(periodId);
    if (mounted) {
      setState(() => _loading = false);
      if (res['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã tính lương KPI');
        _loadPeriodData();
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi tính lương');
      }
    }
  }

  // ------------------------------------------------
  //  TAB 3: CHỈ TIÊU & TIẾN ĐỘ
  // ------------------------------------------------

  Widget _buildTargetsTab(ThemeData theme) {
    if (_selPeriodId == null) return _emptyState('Chọn chu kỳ ở header', Icons.calendar_today);
    final filtered = _filteredTargets;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.track_changes_rounded, color: _accent, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Chỉ tiêu & Tiến độ', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(width: 20),
          OutlinedButton.icon(
            onPressed: _showBatchUpdateDialog,
            icon: const Icon(Icons.edit_note_rounded, size: 18),
            label: const Text('Cập nhật doanh số'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          OutlinedButton.icon(
            onPressed: _importExcelActuals,
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Import Excel'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          OutlinedButton.icon(
            onPressed: _writeTargetsToGSheet,
            icon: const Icon(Icons.cloud_upload_rounded, size: 18),
            label: const Text('Ghi chỉ tiêu → GSheet'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), foregroundColor: _green),
          ),
          OutlinedButton.icon(
            onPressed: _isExporting ? null : _exportTargetsExcel,
            icon: const Icon(Icons.table_chart_rounded, size: 18),
            label: const Text('Xuất Excel'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          OutlinedButton.icon(
            onPressed: _isExporting ? null : () => _exportPng(_targetsKey, 'ChiTieu_KPI'),
            icon: const Icon(Icons.image_rounded, size: 18),
            label: const Text('Xuất PNG'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          FilledButton.icon(
            onPressed: Provider.of<PermissionProvider>(context, listen: false).canCreate('KPI') ? _showAddTargetDialog : null,
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('Giao chỉ tiêu'),
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ]),
      ),
      // Filters
      if (!Responsive.isMobile(context) || _showMobileFilters)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildFilterRow(theme),
        ),
      const SizedBox(height: 8),
      // Progress summary cards
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          final items = [
            _miniStat('Tổng NV', '${filtered.length}', _accent),
            _miniStat('Đạt ≥100%', '${filtered.where((t) => (t['completionRate'] ?? 0) >= 100).length}', _green),
            _miniStat('70-99%', '${filtered.where((t) { final p = (t['completionRate'] ?? 0) as num; return p >= 70 && p < 100; }).length}', _amber),
            _miniStat('<70%', '${filtered.where((t) { final p = (t['completionRate'] ?? 0) as num; return t['actualValue'] != null && p < 70; }).length}', _red),
            _miniStat('Chưa có DS', '${filtered.where((t) => t['actualValue'] == null).length}', Colors.grey),
          ];
          if (isMobile) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map((c) => SizedBox(width: (constraints.maxWidth - 8) / 2, child: c)).toList(),
            );
          }
          return Row(children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: items[i]),
            ],
          ]);
        }),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: filtered.isEmpty
            ? _emptyState('Chưa giao chỉ tiêu cho nhân viên nào', Icons.assignment_outlined)
            : RepaintBoundary(
                key: _targetsKey,
                child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final t = filtered[i];
                  final pct = ((t['completionRate'] ?? 0) as num).toDouble();
                  final color = pct >= 100 ? _green : pct >= 70 ? _amber : _red;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade100),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
                      ),
                      child: Row(children: [
                        SizedBox(
                          width: 50, height: 50,
                          child: Stack(alignment: Alignment.center, children: [
                            CircularProgressIndicator(
                              value: (pct / 100).clamp(0, 1),
                              strokeWidth: 5,
                              backgroundColor: Colors.grey.shade100,
                              valueColor: AlwaysStoppedAnimation(color),
                              strokeCap: StrokeCap.round,
                            ),
                            Text(pct.toStringAsFixed(0), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
                          ]),
                        ),
                        const SizedBox(width: 16),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t['employeeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 3),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: ((t['criteriaType'] ?? 0) == 0 ? _blue : _purple).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                                child: Text(t['criteriaType'] == 0 ? 'Doanh thu' : 'Point', style: TextStyle(color: (t['criteriaType'] ?? 0) == 0 ? _blue : _purple, fontSize: 10, fontWeight: FontWeight.w600)),
                              ),
                              const SizedBox(width: 6),
                              Text(t['department'] ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                              const SizedBox(width: 6),
                              Text('Lương HT: ${_cur.format(t['completionSalary'] ?? 0)}', style: TextStyle(color: Colors.grey[400], fontSize: 11)),
                            ]),
                          ],
                        )),
                        const SizedBox(width: 8),
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.flag_rounded, size: 12, color: Colors.grey[400]),
                            const SizedBox(width: 3),
                            Text(_cur.format(t['targetValue'] ?? 0), style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          ]),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)]),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(t['actualValue'] != null ? _cur.format(t['actualValue']) : 'chưa có',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: t['actualValue'] != null ? color : Colors.grey)),
                          ),
                        ]),
                        const SizedBox(width: 8),
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          if (Provider.of<PermissionProvider>(context, listen: false).canEdit('KPI'))
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, size: 18, color: _accent),
                            onPressed: () => _showEditTargetDialog(t),
                            tooltip: 'Sửa chỉ tiêu',
                            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                            padding: EdgeInsets.zero,
                          ),
                          if (Provider.of<PermissionProvider>(context, listen: false).canDelete('KPI'))
                          IconButton(
                            icon: Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red.shade300),
                            onPressed: () => _deleteItem(() => _api.deleteKpiEmployeeTarget(t['id'].toString())),
                            tooltip: 'Xóa',
                            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                            padding: EdgeInsets.zero,
                          ),
                        ]),
                      ]),
                    ),
                  );
                },
              ),
            ),
      ),
    ]);
  }

  // Parse bonusTiersJson to list of tier maps
  List<Map<String, dynamic>> _parseTiers(String? json) {
    if (json == null || json.isEmpty) {
      return [
        {'fromPct': 100, 'toPct': 120, 'rate': 0, 'rateType': 0},
        {'fromPct': 120, 'toPct': -1, 'rate': 0, 'rateType': 0},
      ];
    }
    try {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty && list.first.containsKey('milestonePercent')) {
        final sorted = list..sort((a, b) => ((a['milestonePercent'] ?? 0) as num).compareTo((b['milestonePercent'] ?? 0) as num));
        final migrated = <Map<String, dynamic>>[];
        for (int i = 0; i < sorted.length; i++) {
          final from = (sorted[i]['milestonePercent'] as num?)?.toDouble() ?? 0;
          final to = i + 1 < sorted.length ? (sorted[i + 1]['milestonePercent'] as num?)?.toDouble() ?? -1 : -1.0;
          migrated.add({'fromPct': from, 'toPct': to, 'rate': sorted[i]['bonusAmount'] ?? 0, 'rateType': 0});
        }
        return migrated;
      }
      return list;
    } catch (_) {
      return [{'fromPct': 100, 'toPct': 120, 'rate': 0, 'rateType': 0}];
    }
  }

  /// Parse penalty tiers JSON
  List<Map<String, dynamic>> _parsePenaltyTiers(String? json) {
    if (json == null || json.isEmpty || json == 'null') return [];
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Tính thưởng/phạt khi chưa đạt 100%
  double _calcPenaltyBonus(Map<String, dynamic> target) {
    final pTiers = _parsePenaltyTiers(target['penaltyTiersJson']?.toString());
    if (pTiers.isEmpty) return 0;
    final tgt = ((target['targetValue'] ?? 0) as num).toDouble();
    final act = ((target['actualValue'] ?? 0) as num).toDouble();
    final pct = tgt > 0 ? act / tgt * 100 : 0.0;
    if (pct >= 100) return 0;

    final cs = ((target['completionSalary'] ?? 0) as num).toDouble();
    for (final tier in pTiers) {
      final fromPct = ((tier['fromPct'] ?? 0) as num).toDouble();
      final toPct = ((tier['toPct'] ?? 100) as num).toDouble();
      final rate = ((tier['rate'] ?? 0) as num).toDouble();
      final rateType = ((tier['rateType'] ?? 0) as num).toInt();
      if (pct >= fromPct && pct < toPct) {
        // rateType 1 = % của CompletionSalary, rateType 0 = số tiền cố định
        return rateType == 1 ? (cs * rate / 100).roundToDouble() : rate;
      }
    }
    return 0;
  }

  String _tiersToJson(List<Map<String, dynamic>> tiers) {
    return jsonEncode(tiers.map((t) => {
      'fromPct': t['fromPct'] ?? 100,
      'toPct': t['toPct'] ?? -1,
      'rate': t['rate'] ?? 0,
      'rateType': t['rateType'] ?? 0,
    }).toList());
  }

  Widget _buildTiersEditor(List<Map<String, dynamic>> tiers, int rateType, int criteriaType, void Function(int) onRateTypeChanged, void Function(void Function()) ss) {
    String valueHeader;
    String hintText;
    String example;
    switch (rateType) {
      case 0: valueHeader = 'VNĐ/1 point vượt'; hintText = 'VNĐ/point'; example = 'Ví dụ: T? 100% → 120%, thưởng 50.000d cho mởi point vượt. Đến % nhập -1 hoặc 8 = không giới hạn.'; break;
      case 1: valueHeader = '% trên doanh thu vượt'; hintText = '% doanh thu'; example = 'Ví dụ: T? 100% → 120%, thưởng 5% trên phần doanh thu vượt chỉ tiêu.'; break;
      case 2: valueHeader = 'Giá trị VNĐ'; hintText = 'Số tiền VNĐ'; example = 'Ví dụ: Đạt ≥100%, thưởng cố định 2.000.000d.'; break;
      case 3: valueHeader = '% lương hoàn thành'; hintText = '%'; example = 'Ví dụ: Đạt ≥120%, thưởng 10% lương hoàn thành.'; break;
      default: valueHeader = 'Giá trị'; hintText = 'Nhập giá trị'; example = ''; break;
    }
    final dropdownItems = criteriaType == 1
        ? const [
            DropdownMenuItem(value: 0, child: Text('VNĐ/1 point vượt')),
            DropdownMenuItem(value: 3, child: Text('% lương hoàn thành')),
            DropdownMenuItem(value: 2, child: Text('Giá trị VNĐ')),
          ]
        : const [
            DropdownMenuItem(value: 1, child: Text('% doanh thu')),
            DropdownMenuItem(value: 3, child: Text('% lương hoàn thành')),
            DropdownMenuItem(value: 2, child: Text('Giá trị VNĐ')),
          ];
    // Ensure rateType is valid for current criteriaType
    final validValues = dropdownItems.map((e) => e.value).toSet();
    if (!validValues.contains(rateType)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onRateTypeChanged(dropdownItems.first.value!));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Bậc thưởng vượt chỉ tiêu (=100%)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const Spacer(),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<int>(
            initialValue: validValues.contains(rateType) ? rateType : dropdownItems.first.value,
            decoration: const InputDecoration(labelText: 'Kiểu thưởng', border: OutlineInputBorder(), isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            style: const TextStyle(fontSize: 11, color: Colors.black87),
            items: dropdownItems,
            onChanged: (v) => onRateTypeChanged(v ?? 0),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () => ss(() => tiers.add({'fromPct': tiers.isEmpty ? 100 : (tiers.last['toPct'] == -1 ? 120 : tiers.last['toPct']), 'toPct': -1, 'rate': 0, 'rateType': rateType})),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Thêm bậc', style: TextStyle(fontSize: 12)),
        ),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
            child: Row(children: [
              const Expanded(child: Text('Từ %', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              const Expanded(child: Text('Đến %', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              Expanded(flex: 2, child: Text(valueHeader, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              const SizedBox(width: 32),
            ]),
          ),
          if (tiers.isEmpty)
            const Padding(padding: EdgeInsets.all(12), child: Text('Chưa có bậc thưởng', style: TextStyle(color: Colors.grey, fontSize: 12)))
          else
            ...tiers.asMap().entries.map((e) {
              final i = e.key;
              final t = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                child: Row(children: [
                  Expanded(child: TextFormField(
                    initialValue: '${t['fromPct'] ?? 100}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => tiers[i]['fromPct'] = num.tryParse(v) ?? 0,
                  )),
                  Expanded(child: TextFormField(
                    initialValue: '${t['toPct'] == -1 ? '8' : t['toPct'] ?? 120}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6), hintText: '8 = -1'),
                    onChanged: (v) => tiers[i]['toPct'] = v == '8' ? -1 : (num.tryParse(v) ?? -1),
                  )),
                  Expanded(flex: 2, child: TextFormField(
                    initialValue: formatNumber(t['rate']),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      hintText: hintText),
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandSeparatorFormatter()],
                    onChanged: (v) => tiers[i]['rate'] = parseFormattedNumber(v) ?? 0,
                  )),
                  SizedBox(width: 32, child: IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    onPressed: () => ss(() => tiers.removeAt(i)),
                  )),
                ]),
              );
            }),
        ]),
      ),
      const SizedBox(height: 4),
      Text(example,
          style: TextStyle(color: Colors.grey[500], fontSize: 11, fontStyle: FontStyle.italic)),
    ]);
  }

  /// Editor cho các mởc thưởng/phạt khi chưa đạt 100%
  Widget _buildPenaltyTiersEditor(List<Map<String, dynamic>> tiers, int rateType, void Function(int) onRateTypeChanged, void Function(void Function()) ss) {
    const valueHeader = 'Số tiền VNĐ';
    const hintText = 'VNĐ (Âm=phạt)';
    const example = 'Số âm = phạt, số dương = thưởng. VD: Đạt 50-79% → phạt -500.000d.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Thưởng/Phạt dưới 100%', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFFEF4444))),
        const Spacer(),
        TextButton.icon(
          onPressed: () => ss(() => tiers.add({
            'fromPct': tiers.isEmpty ? 0 : (tiers.last['toPct'] ?? 50),
            'toPct': tiers.isEmpty ? 50 : 100,
            'rate': 0, 'rateType': 0,
          })),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Thêm mốc', style: TextStyle(fontSize: 12)),
        ),
      ]),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.red.shade200), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
            child: const Row(children: [
              Expanded(child: Text('Từ %', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              Expanded(child: Text('Đến %', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              Expanded(flex: 2, child: Text(valueHeader, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11))),
              SizedBox(width: 32),
            ]),
          ),
          if (tiers.isEmpty)
            Padding(padding: const EdgeInsets.all(12), child: Text('Chưa có mốc nào (lương tỷ lệ theo % đạt)', style: TextStyle(color: Colors.grey[500], fontSize: 12)))
          else
            ...tiers.asMap().entries.map((e) {
              final i = e.key;
              final t = e.value;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.red.shade100))),
                child: Row(children: [
                  Expanded(child: TextFormField(
                    initialValue: '${t['fromPct'] ?? 0}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => tiers[i]['fromPct'] = num.tryParse(v) ?? 0,
                  )),
                  Expanded(child: TextFormField(
                    initialValue: '${t['toPct'] ?? 100}',
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6)),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => tiers[i]['toPct'] = num.tryParse(v) ?? 100,
                  )),
                  Expanded(flex: 2, child: TextFormField(
                    initialValue: formatNumber(t['rate']),
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: (t['rate'] ?? 0) < 0 ? Colors.red : Colors.green),
                    decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 6),
                      hintText: hintText),
                    keyboardType: const TextInputType.numberWithOptions(signed: true),
                    inputFormatters: [ThousandSeparatorFormatter()],
                    onChanged: (v) => tiers[i]['rate'] = parseFormattedNumber(v) ?? 0,
                  )),
                  SizedBox(width: 32, child: IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.red),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                    onPressed: () => ss(() => tiers.removeAt(i)),
                  )),
                ]),
              );
            }),
        ]),
      ),
      const SizedBox(height: 4),
      Text(example,
          style: TextStyle(color: Colors.grey[500], fontSize: 11, fontStyle: FontStyle.italic)),
    ]);
  }

  void _showAddTargetDialog() {
    final selectedEmpIds = <String>{};
    final targetCtrl = TextEditingController();
    final salaryCtrl = TextEditingController();
    int criteriaType = 0;
    final tiers = <Map<String, dynamic>>[
      {'fromPct': 100, 'toPct': 120, 'rate': 0, 'rateType': 1},
      {'fromPct': 120, 'toPct': -1, 'rate': 0, 'rateType': 1},
    ];
    final penaltyTiers = <Map<String, dynamic>>[
      {'fromPct': 0, 'toPct': 50, 'rate': -1000000, 'rateType': 0},
      {'fromPct': 50, 'toPct': 80, 'rate': -500000, 'rateType': 0},
      {'fromPct': 80, 'toPct': 100, 'rate': 0, 'rateType': 0},
    ];
    int penaltyRateType = 0;
    int bonusRateType = 1;

    final assignedIds = _targets.map((t) => t['employeeId']?.toString()).toSet();
    final available = _employees.where((e) => !assignedIds.contains(e['id']?.toString())).toList();
    String searchText = '';
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        final filtered = available.where((e) {
          if (searchText.isEmpty) return true;
          final name = '${e['lastName'] ?? ''} ${e['firstName'] ?? ''} ${e['employeeCode'] ?? ''}'.toLowerCase();
          return name.contains(searchText.toLowerCase());
        }).toList();

        Future<void> onSave() async {
          final batch = selectedEmpIds.map((empId) => {
            'employeeId': empId,
            'criteriaType': criteriaType,
            'targetValue': parseFormattedNumber(targetCtrl.text) ?? 0,
            'completionSalary': parseFormattedNumber(salaryCtrl.text) ?? 0,
            'bonusTiersJson': _tiersToJson(tiers),
            'penaltyTiersJson': _tiersToJson(penaltyTiers),
          }).toList();
          final res = await _api.saveKpiEmployeeTargets(_selPeriodId!, batch);
          if (ctx.mounted) Navigator.pop(ctx);
          if (res['isSuccess'] == true) {
            if (mounted) NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã giao chỉ tiêu cho ${selectedEmpIds.length} nhân viên');
            _loadPeriodData();
          }
        }

        final formBody = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Tìm nhân viên...', prefixIcon: const Icon(Icons.search, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true,
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(onPressed: () => ss(() => selectedEmpIds.addAll(filtered.map((e) => e['id'].toString()))), child: const Text('Tất cả', style: TextStyle(fontSize: 11))),
                      TextButton(onPressed: () => ss(() => selectedEmpIds.clear()), child: const Text('Bỏ chọn', style: TextStyle(fontSize: 11))),
                    ]),
                  ),
                  onChanged: (v) => ss(() => searchText = v),
                ),
              ),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final e = filtered[i];
                    final id = e['id'].toString();
                    return CheckboxListTile(
                      value: selectedEmpIds.contains(id),
                      onChanged: (v) => ss(() => v == true ? selectedEmpIds.add(id) : selectedEmpIds.remove(id)),
                      title: Text('${e['lastName'] ?? ''} ${e['firstName'] ?? ''} (${e['employeeCode'] ?? ''})', style: const TextStyle(fontSize: 13)),
                      dense: true, controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              if (selectedEmpIds.isNotEmpty) Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Đã chọn ${selectedEmpIds.length} nhân viên', style: const TextStyle(color: _accent, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: criteriaType,
            decoration: InputDecoration(labelText: 'Loại chỉ tiêu', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            items: const [
              DropdownMenuItem(value: 0, child: Text('Doanh thu')),
              DropdownMenuItem(value: 1, child: Text('Point')),
            ],
            onChanged: (v) => ss(() {
              criteriaType = v ?? 0;
              final defaultBonusType = criteriaType == 1 ? 0 : 1;
              bonusRateType = defaultBonusType;
              for (final t in tiers) { t['rateType'] = defaultBonusType; }
            }),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(targetCtrl, 'Chỉ tiêu (s?)', number: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(salaryCtrl, 'Lương khi đạt 100%', number: true)),
          ]),
          const SizedBox(height: 16),
          _buildPenaltyTiersEditor(penaltyTiers, penaltyRateType, (v) => ss(() { penaltyRateType = v; for (final t in penaltyTiers) { t['rateType'] = v; } }), ss),
          const SizedBox(height: 16),
          _buildTiersEditor(tiers, bonusRateType, criteriaType, (v) => ss(() { bonusRateType = v; for (final t in tiers) { t['rateType'] = v; } }), ss),
        ]);

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Giao chỉ tiêu cho nhân viên'),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: selectedEmpIds.isEmpty ? null : onSave,
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: Text('Giao (${selectedEmpIds.length})'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Giao chỉ tiêu cho nhân viên'),
          content: SizedBox(
            width: math.min(620, MediaQuery.of(context).size.width - 32).toDouble(),
            child: SingleChildScrollView(child: formBody),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: selectedEmpIds.isEmpty ? null : onSave,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: Text('Giao (${selectedEmpIds.length})'),
            ),
          ],
        );
      }),
    );
  }

  void _showEditTargetDialog(Map<String, dynamic> t) {
    final targetCtrl = TextEditingController(text: formatNumber(t['targetValue']));
    final actualCtrl = TextEditingController(text: formatNumber(t['actualValue']));
    final salaryCtrl = TextEditingController(text: formatNumber(t['completionSalary']));
    final notesCtrl = TextEditingController(text: t['notes'] ?? '');
    final tiers = _parseTiers(t['bonusTiersJson']?.toString());
    final penaltyTiers = _parsePenaltyTiers(t['penaltyTiersJson']?.toString());
    int penaltyRateType = penaltyTiers.isNotEmpty ? ((penaltyTiers.first['rateType'] ?? 1) as num).toInt() : 1;
    int bonusRateType = tiers.isNotEmpty ? ((tiers.first['rateType'] ?? 0) as num).toInt() : 0;
    final isMobile = Responsive.isMobile(context);
    final dialogTitle = 'Sửa chỉ tiêu: ${t['employeeName'] ?? ''}';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        Future<void> onSave() async {
          final data = {
            'id': t['id'],
            'employeeId': t['employeeId'],
            'criteriaType': t['criteriaType'],
            'targetValue': parseFormattedNumber(targetCtrl.text) ?? 0,
            'actualValue': actualCtrl.text.isNotEmpty ? parseFormattedNumber(actualCtrl.text) : null,
            'completionSalary': parseFormattedNumber(salaryCtrl.text) ?? 0,
            'bonusTiersJson': _tiersToJson(tiers),
            'penaltyTiersJson': _tiersToJson(penaltyTiers),
            'notes': notesCtrl.text,
          };
          final res = await _api.saveKpiEmployeeTargets(_selPeriodId!, [data]);
          if (ctx.mounted) Navigator.pop(ctx);
          if (res['isSuccess'] == true) await _loadPeriodData();
        }

        final formBody = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: _field(targetCtrl, 'Chỉ tiêu', number: true)),
            const SizedBox(width: 12),
            Expanded(child: _field(actualCtrl, 'Thực tế', number: true)),
          ]),
          const SizedBox(height: 12),
          _field(salaryCtrl, 'Lương khi đạt 100%', number: true),
          const SizedBox(height: 16),
          _buildPenaltyTiersEditor(penaltyTiers, penaltyRateType, (v) => ss(() { penaltyRateType = v; for (final pt in penaltyTiers) { pt['rateType'] = v; } }), ss),
          const SizedBox(height: 16),
          _buildTiersEditor(tiers, bonusRateType, ((t['criteriaType'] ?? 0) as num).toInt(), (v) => ss(() { bonusRateType = v; for (final bt in tiers) { bt['rateType'] = v; } }), ss),
          const SizedBox(height: 12),
          _field(notesCtrl, 'Ghi chú'),
        ]);

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: Text(dialogTitle, style: const TextStyle(fontSize: 16)),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Cập nhật'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(dialogTitle),
          content: SizedBox(
            width: math.min(560, MediaQuery.of(context).size.width - 32).toDouble(),
            child: SingleChildScrollView(child: formBody),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Cập nhật'),
            ),
          ],
        );
      }),
    );
  }

  void _showBatchUpdateDialog() {
    final controllers = <String, TextEditingController>{};
    for (final t in _targets) {
      controllers[t['id'].toString()] = TextEditingController(text: formatNumber(t['actualValue']));
    }
    final isMobile = Responsive.isMobile(context);

    Future<void> onSave(BuildContext ctx) async {
      final updates = <Map<String, dynamic>>[];
      for (final t in _targets) {
        final id = t['id'].toString();
        final val = parseFormattedNumber(controllers[id]?.text ?? '');
        updates.add({
          'id': t['id'],
          'employeeId': t['employeeId'],
          'criteriaType': t['criteriaType'],
          'targetValue': t['targetValue'],
          'actualValue': val,
          'completionSalary': t['completionSalary'],
          'bonusTiersJson': t['bonusTiersJson'],
          'penaltyTiersJson': t['penaltyTiersJson'],
          'notes': t['notes'],
        });
      }
      final res = await _api.saveKpiEmployeeTargets(_selPeriodId!, updates);
      if (ctx.mounted) Navigator.pop(ctx);
      if (res['isSuccess'] == true) await _loadPeriodData();
    }

    Widget buildList() {
      return ListView.builder(
        shrinkWrap: !isMobile,
        physics: isMobile ? null : const NeverScrollableScrollPhysics(),
        itemCount: _targets.length,
        itemBuilder: (_, i) {
          final t = _targets[i];
          final id = t['id'].toString();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: isMobile
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t['employeeName'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Mục tiêu: ${_cur.format(t['targetValue'] ?? 0)}', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                    const SizedBox(height: 4),
                    TextField(
                      controller: controllers[id],
                      decoration: InputDecoration(labelText: 'Thực tế', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandSeparatorFormatter()],
                    ),
                    const Divider(height: 16),
                  ])
                : Row(children: [
                    Expanded(flex: 2, child: Text(t['employeeName'] ?? '', style: const TextStyle(fontSize: 13))),
                    Expanded(child: Text('Mục tiêu: ${_cur.format(t['targetValue'] ?? 0)}', style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
                    Expanded(child: TextField(
                      controller: controllers[id],
                      decoration: InputDecoration(labelText: 'Thực tế', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true),
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandSeparatorFormatter()],
                    )),
                  ]),
          );
        },
      );
    }

    showDialog(
      context: context,
      builder: (ctx) {
        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Cập nhật doanh số hàng loạt'),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: () => onSave(ctx),
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Lưu tất cả'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: buildList(),
              ),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Cập nhật doanh số hàng loạt'),
          content: SizedBox(
            width: math.min(600, MediaQuery.of(context).size.width - 32).toDouble(),
            height: 500,
            child: buildList(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () => onSave(ctx),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Lưu tất cả'),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------
  //  TAB 4: LƯƠNG KPI
  // ------------------------------------------------

  /// Tính thưởng từng bậc cho 1 target
  List<Map<String, dynamic>> _calcTierBonuses(Map<String, dynamic> target) {
    final tiers = _parseTiers(target['bonusTiersJson']?.toString());
    final tgt = ((target['targetValue'] ?? 0) as num).toDouble();
    final act = ((target['actualValue'] ?? 0) as num).toDouble();
    final pct = tgt > 0 ? act / tgt * 100 : 0.0;
    final cs = ((target['completionSalary'] ?? 0) as num).toDouble();

    return tiers.map((tier) {
      final fromPct = ((tier['fromPct'] ?? 0) as num).toDouble();
      final toPct = ((tier['toPct'] ?? -1) as num).toDouble();
      final rate = ((tier['rate'] ?? 0) as num).toDouble();
      final rateType = ((tier['rateType'] ?? 0) as num).toInt();

      double bonus = 0;
      if (pct >= 100 && pct > fromPct) {
        if (rateType == 2) {
          // Giá trị VNĐ: fixed VND amount
          bonus = rate;
        } else if (rateType == 3) {
          // % lương HT
          bonus = cs * rate / 100;
        } else {
          final fromVal = tgt * fromPct / 100;
          final toVal = toPct < 0 ? act : tgt * toPct / 100;
          final inBand = (act < toVal ? act : toVal) - fromVal;
          if (inBand > 0) {
            bonus = rateType == 1 ? inBand * rate / 100 : inBand * rate;
          }
        }
      }
      return {
        'fromPct': fromPct,
        'toPct': toPct,
        'rate': rate,
        'rateType': rateType,
        'bonus': bonus,
      };
    }).toList();
  }

  /// Tìm s? b?c thưởng t?i da trong tất cả targets
  int get _maxTierCount {
    int mx = 0;
    for (final t in _targets) {
      final tiers = _parseTiers(t['bonusTiersJson']?.toString());
      if (tiers.length > mx) mx = tiers.length;
    }
    return mx;
  }

  Widget _buildSalaryTab(ThemeData theme) {
    if (_selPeriodId == null) return _emptyState('Chọn chu kỳ ở header', Icons.calendar_today);

    final maxTiers = _maxTierCount;

    return LayoutBuilder(builder: (context, constraints) {
    final tableMinWidth = constraints.maxWidth > 0 ? constraints.maxWidth : MediaQuery.of(context).size.width - 40;
    final filteredTgts = _filteredTargets;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.account_balance_wallet_rounded, color: _accent, size: 20),
            ),
            const SizedBox(width: 12),
            Text('Bảng lương KPI', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _isExporting ? null : _exportSalaryExcel,
            icon: const Icon(Icons.table_chart_rounded, size: 18),
            label: const Text('Xuất Excel'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          OutlinedButton.icon(
            onPressed: _isExporting ? null : () => _exportPng(_salaryKey, 'Luong_KPI'),
            icon: const Icon(Icons.image_rounded, size: 18),
            label: const Text('Xuất PNG'),
            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          FilledButton.icon(
            onPressed: () => _calculateSalary(_selPeriodId),
            icon: const Icon(Icons.calculate_rounded, size: 18),
            label: const Text('Tính lương'),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (!Responsive.isMobile(context) || _showMobileFilters) _buildFilterRow(theme),
        const SizedBox(height: 12),
        RepaintBoundary(
          key: _salaryKey,
          child: Builder(builder: (_) {
          final totalPages = (filteredTgts.length / _salaryPageSize).ceil();
          final safePage = _salaryPage.clamp(1, totalPages == 0 ? 1 : totalPages);
          final startIdx = (safePage - 1) * _salaryPageSize;
          final endIdx = (startIdx + _salaryPageSize).clamp(0, filteredTgts.length);
          final pageItems = filteredTgts.sublist(startIdx, endIdx);
          final isMobileSalary = constraints.maxWidth < 600;
          return Column(children: [
          isMobileSalary
            ? _buildSalaryMobileCards(pageItems, startIdx, filteredTgts)
            : Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 2))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: tableMinWidth - 40),
            child: DataTable(
              columnSpacing: 18,
              horizontalMargin: 16,
              headingRowHeight: 52,
              dataRowMinHeight: 44,
              dataRowMaxHeight: 58,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Color(0xFF334155)),
              dataTextStyle: const TextStyle(fontSize: 12),
              columns: [
                const DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('Tên nhân viên', textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('Chỉ tiêu KPI', textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('KPI đạt được', textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('Tỷ lệ hoàn thành', textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('Thưởng/Phạt', textAlign: TextAlign.center))),
                const DataColumn(label: Expanded(child: Text('Lương hoàn thành', textAlign: TextAlign.center))),
                // Dynamic tier columns
                for (int i = 0; i < maxTiers; i++) ...[
                  DataColumn(label: Expanded(child: Text('Bậc ${i + 1}', textAlign: TextAlign.center))),
                  DataColumn(label: Expanded(child: Text('Thưởng bậc ${i + 1}', textAlign: TextAlign.center))),
                ],
                const DataColumn(label: Expanded(child: Text('Tổng thưởng', textAlign: TextAlign.center))),
              ],
              rows: [
                // Data rows - paginated
                ...pageItems.asMap().entries.map((entry) {
                  final idx = startIdx + entry.key;
                  final t = entry.value;
                  final tgt = ((t['targetValue'] ?? 0) as num).toDouble();
                  final act = ((t['actualValue'] ?? 0) as num).toDouble();
                  final pct = ((t['completionRate'] ?? 0) as num).toDouble();
                  final completionSalary = ((t['completionSalary'] ?? 0) as num).toDouble();
                  final tierBonuses = _calcTierBonuses(t);
                  final penaltyBonus = _calcPenaltyBonus(t);

                  final salaryHT = pct >= 100 ? completionSalary : (completionSalary * pct / 100);
                  final totalTierBonus = tierBonuses.fold<double>(0, (s, b) => s + ((b['bonus'] as num?)?.toDouble() ?? 0));
                  final totalSalary = math.max(0.0, salaryHT + penaltyBonus + totalTierBonus);

                  final pctColor = pct >= 100 ? _green : pct >= 70 ? _amber : _red;

                  return DataRow(cells: [
                    DataCell(Center(child: Text('${idx + 1}', style: TextStyle(color: Colors.grey[500])))),
                    DataCell(Center(child: SizedBox(
                      width: 130,
                      child: Text(t['employeeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                    ))),
                    DataCell(Center(child: Text(t['employeeCode'] ?? '', style: TextStyle(color: Colors.grey[600])))),
                    DataCell(Center(child: Text(_cur.format(tgt)))),
                    DataCell(Center(child: Text(act > 0 ? _cur.format(act) : '-', style: TextStyle(color: act > 0 ? Colors.black87 : Colors.grey)))),
                    DataCell(Center(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: pctColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w600, color: pctColor, fontSize: 11)),
                    ))),
                    DataCell(Center(child: Text(_cur.format(penaltyBonus), style: TextStyle(fontWeight: FontWeight.w600, color: penaltyBonus < 0 ? Colors.red : penaltyBonus > 0 ? _green : Colors.grey)))),
                    DataCell(Center(child: Text(_cur.format(salaryHT), style: TextStyle(fontWeight: FontWeight.w500, color: salaryHT > 0 ? Colors.black87 : Colors.grey)))),
                    // Dynamic tier cells
                    for (int i = 0; i < maxTiers; i++) ...[
                      DataCell(Center(child: i < tierBonuses.length
                          ? Text('${(tierBonuses[i]['fromPct'] as num).toInt()}%-${tierBonuses[i]['toPct'] == -1 ? '8' : '${(tierBonuses[i]['toPct'] as num).toInt()}%'}',
                              style: TextStyle(fontSize: 11, color: Colors.grey[600]))
                          : const Text('-'))),
                      DataCell(Center(child: i < tierBonuses.length
                          ? Text(_cur.format(tierBonuses[i]['bonus']),
                              style: TextStyle(color: (tierBonuses[i]['bonus'] as num) > 0 ? _green : Colors.grey[400], fontWeight: (tierBonuses[i]['bonus'] as num) > 0 ? FontWeight.w600 : FontWeight.normal))
                          : const Text('-'))),
                    ],
                    DataCell(Center(child: Text(_cur.format(totalSalary), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                  ]);
                }),
                // Total row
                if (filteredTgts.isNotEmpty) DataRow(
                  color: WidgetStateProperty.all(Colors.grey.shade50),
                  cells: [
                    const DataCell(Center(child: Text(''))),
                    const DataCell(Center(child: Text('TỔNG CỘNG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                    const DataCell(Center(child: Text(''))),
                    const DataCell(Center(child: Text(''))),
                    const DataCell(Center(child: Text(''))),
                    const DataCell(Center(child: Text(''))),
                    DataCell(Center(child: Text(_cur.format(filteredTgts.fold<double>(0, (s, t) => s + _calcPenaltyBonus(t))), style: TextStyle(fontWeight: FontWeight.bold, color: filteredTgts.fold<double>(0, (s, t) => s + _calcPenaltyBonus(t)) < 0 ? Colors.red : _green)))),
                    DataCell(Center(child: Text(_cur.format(filteredTgts.fold<double>(0, (s, t) {
                      final pct = ((t['completionRate'] ?? 0) as num).toDouble();
                      final cs = ((t['completionSalary'] ?? 0) as num).toDouble();
                      return s + (pct >= 100 ? cs : cs * pct / 100);
                    })), style: const TextStyle(fontWeight: FontWeight.bold)))),
                    for (int i = 0; i < maxTiers; i++) ...[
                      const DataCell(Center(child: Text(''))),
                      DataCell(Center(child: Text(_cur.format(filteredTgts.fold<double>(0, (s, t) {
                        final bonuses = _calcTierBonuses(t);
                        return s + (i < bonuses.length ? ((bonuses[i]['bonus'] as num?)?.toDouble() ?? 0) : 0);
                      })), style: const TextStyle(fontWeight: FontWeight.bold, color: _green)))),
                    ],
                    DataCell(Center(child: Text(_cur.format(filteredTgts.fold<double>(0, (s, t) {
                      final pct = ((t['completionRate'] ?? 0) as num).toDouble();
                      final cs = ((t['completionSalary'] ?? 0) as num).toDouble();
                      final salaryHT = pct >= 100 ? cs : cs * pct / 100;
                      final tierBonus = _calcTierBonuses(t).fold<double>(0, (s2, b) => s2 + ((b['bonus'] as num?)?.toDouble() ?? 0));
                      final penBonus = _calcPenaltyBonus(t);
                      return s + math.max(0, salaryHT + penBonus + tierBonus);
                    })), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                  ],
                ),
              ],
            ),
          ),
          ),
          ),
        ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text('${filteredTgts.length} dòng', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    const SizedBox(width: 8),
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _salaryPageSize,
                          isDense: true,
                          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                          items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() { _salaryPageSize = v; _salaryPage = 1; });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                if (totalPages > 1) Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(icon: const Icon(Icons.first_page, size: 20), onPressed: safePage > 1 ? () => setState(() => _salaryPage = 1) : null, visualDensity: VisualDensity.compact),
                    IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: safePage > 1 ? () => setState(() => _salaryPage--) : null, visualDensity: VisualDensity.compact),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$safePage / $totalPages',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                    IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: safePage < totalPages ? () => setState(() => _salaryPage++) : null, visualDensity: VisualDensity.compact),
                    IconButton(icon: const Icon(Icons.last_page, size: 20), onPressed: safePage < totalPages ? () => setState(() => _salaryPage = totalPages) : null, visualDensity: VisualDensity.compact),
                  ],
                ),
              ],
            ),
          ),
          ]);
          }),
        ),
      ]),
    );
    });
  }

  Widget _buildSalaryMobileCards(List<Map<String, dynamic>> pageItems, int startIdx, List<Map<String, dynamic>> allItems) {
    final totalSalaryAll = allItems.fold<double>(0, (s, t) {
      final pct = ((t['completionRate'] ?? 0) as num).toDouble();
      final cs = ((t['completionSalary'] ?? 0) as num).toDouble();
      final salaryHT = pct >= 100 ? cs : cs * pct / 100;
      final tierBonus = _calcTierBonuses(t).fold<double>(0, (s2, b) => s2 + ((b['bonus'] as num?)?.toDouble() ?? 0));
      final penBonus = _calcPenaltyBonus(t);
      return s + math.max(0, salaryHT + penBonus + tierBonus);
    });
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Text('Tổng lương: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(_cur.format(totalSalaryAll), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _accent)),
        ]),
      ),
      const SizedBox(height: 8),
      ...pageItems.asMap().entries.map((entry) {
        final t = entry.value;
        final pct = ((t['completionRate'] ?? 0) as num).toDouble();
        final completionSalary = ((t['completionSalary'] ?? 0) as num).toDouble();
        final tierBonuses = _calcTierBonuses(t);
        final penaltyBonus = _calcPenaltyBonus(t);
        final salaryHT = pct >= 100 ? completionSalary : (completionSalary * pct / 100);
        final totalTierBonus = tierBonuses.fold<double>(0, (s, b) => s + ((b['bonus'] as num?)?.toDouble() ?? 0));
        final totalSalary = math.max(0.0, salaryHT + penaltyBonus + totalTierBonus);
        final pctColor = pct >= 100 ? _green : pct >= 70 ? _amber : _red;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(t['employeeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [pctColor.withValues(alpha: 0.15), pctColor.withValues(alpha: 0.05)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${pct.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w700, color: pctColor, fontSize: 12)),
                ),
              ]),
              Text(t['employeeCode'] ?? '', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
              const Divider(height: 24),
              _mobileInfoRow('Lương cơ bản', _cur.format(salaryHT), salaryHT > 0 ? Colors.black87 : Colors.grey),
              _mobileInfoRow('Thưởng/Phạt', _cur.format(penaltyBonus), penaltyBonus < 0 ? Colors.red : penaltyBonus > 0 ? _green : Colors.grey),
              _mobileInfoRow('Thưởng KPI', _cur.format(totalTierBonus), totalTierBonus > 0 ? _green : Colors.grey),
              const Divider(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_accent.withValues(alpha: 0.06), Colors.white]),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Tổng lương', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(_cur.format(totalSalary), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _accent)),
                ]),
              ),
            ]),
          ),
        );
      }),
    ]);
  }

  Widget _mobileInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: valueColor)),
      ]),
    );
  }

  // ignore: unused_element
  Future<void> _approveAllSalaries() async {
    final ids = _salaries.where((s) => s['isApproved'] != true).map((s) => s['id']?.toString() ?? '').where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    final res = await _api.approveKpiSalaries(ids);
    if (mounted && res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã duyệt tất cả');
      _loadPeriodData();
    }
  }

  // ------------------------------------------------
  //  SHARED HELPERS
  // ------------------------------------------------

  Future<void> _deleteItem(Future<Map<String, dynamic>> Function() apiCall) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Bạn có chắc muốn xóa?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) {
      await apiCall();
      _loadData();
    }
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, color.withValues(alpha: 0.04)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4),
          ],
        ),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.05)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.02)]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  Widget _card(String title, IconData icon, Color color, {required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withValues(alpha: 0.06), Colors.white]),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 15)),
          ]),
        ),
        Divider(height: 24, color: Colors.grey.shade100),
        child,
      ]),
    );
  }

  Widget _chip(String label, IconData icon, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(label)]),
        onPressed: onTap,
        backgroundColor: color.withValues(alpha: 0.08),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
        labelStyle: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _emptyState(String text, IconData icon) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 48, color: Colors.grey[300]),
      ),
      const SizedBox(height: 16),
      Text(text, style: TextStyle(color: Colors.grey[500], fontSize: 15, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Text('Bắt đầu bằng cách tạo dữ liệu mới', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
    ]));
  }

  Widget _field(TextEditingController ctrl, String label, {bool number = false, int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true),
      keyboardType: number ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      inputFormatters: number ? [ThousandSeparatorFormatter()] : null,
    );
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(d.toString())); } catch (_) { return d.toString(); }
  }

  // ------------------------------------------------
  //  TAB 5: CẤU HÌNH GOOGLE SHEET
  // ------------------------------------------------

  Widget _buildGSheetConfigTab(ThemeData theme) {
    if (_selPeriodId == null) return _emptyState('Chọn chu kỳ ở header', Icons.calendar_today);

    // Get current period data
    final period = _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => {});
    final lastSynced = period['lastSyncedAt'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // -- Header row with copy button --
        Row(children: [
          const Icon(Icons.table_chart, color: _accent, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text('Cấu hình Google Sheet', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          OutlinedButton.icon(
            onPressed: () => _showCopyGSheetConfigDialog(),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy từ chu kỳ khác', style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(foregroundColor: _accent),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Thiết lập kết nối Google Sheet. Bấm "Tạo sheet mẫu" để tạo bảng theo mã NV, sau đó đồng bộ tự động.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
        if (lastSynced != null) ...[
          const SizedBox(height: 4),
          Text('Lần đồng bộ cuối: ${_fmtDateTime(lastSynced)}', style: const TextStyle(color: _green, fontSize: 12)),
        ],
        const SizedBox(height: 20),

        // -- Section 0: Credentials status --
        if (!_credentialsConfigured) _buildCredentialsWarning(theme),
        if (!_credentialsConfigured) const SizedBox(height: 20),

        // -- Section 1: Google Sheet URL + Sheet Name --
        _buildGSheetConnectionSection(theme, period),
        const SizedBox(height: 20),

        // -- Section 2: Employee cell mappings --
        _buildEmployeeMappingSection(theme),
        const SizedBox(height: 20),

        // -- Section 3: Auto-sync schedule --
        _buildAutoSyncSection(theme, period),
      ]),
    );
  }

  String _buildGSheetUrl(String? spreadsheetId) {
    if (spreadsheetId == null || spreadsheetId.isEmpty) return '';
    return 'https://docs.google.com/spreadsheets/d/$spreadsheetId';
  }

  String _fmtDateTime(dynamic d) {
    if (d == null) return '';
    try { return DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(d.toString()).toLocal()); } catch (_) { return d.toString(); }
  }

  Widget _buildCredentialsWarning(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _red.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber_rounded, color: _red, size: 20),
          SizedBox(width: 8),
          Expanded(child: Text(
            'Chưa cấu hình Google Service Account',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _red),
          )),
        ]),
        const SizedBox(height: 8),
        Text(
          'C?n upload file credentials.json (Google Service Account key) d? kết nối Google Sheet. '
          'T?i file JSON key t? Google Cloud Console ? IAM ? Service Accounts ? Keys.',
          style: TextStyle(color: Colors.grey[700], fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        _credentialsLoading
            ? const SizedBox(height: 36, width: 36, child: CircularProgressIndicator(strokeWidth: 2))
            : FilledButton.icon(
                onPressed: _uploadCredentials,
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Upload credentials.json', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: _accent),
              ),
      ]),
    );
  }

  Widget _buildGSheetConnectionSection(ThemeData theme, Map<String, dynamic> period) {
    final sheetId = period['googleSpreadsheetId'] as String?;
    final sheetName = period['googleSheetName'] as String?;
    final hasConfig = sheetId != null && sheetId.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hasConfig ? _green.withValues(alpha: 0.3) : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.link, color: hasConfig ? _green : Colors.grey, size: 18),
          const SizedBox(width: 8),
          Text('Kết nối Google Sheet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: hasConfig ? _green : Colors.grey[700])),
          const Spacer(),
          if (hasConfig) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: _green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.check_circle, color: _green, size: 14),
              SizedBox(width: 4),
              Text('Đã kết nối', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        if (hasConfig) ...[
          _infoRow('Link', _buildGSheetUrl(sheetId)),
          const SizedBox(height: 6),
          _infoRow('Sheet', sheetName ?? 'Sheet1'),
          const SizedBox(height: 12),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => _showEditGSheetConnectionDialog(period),
            icon: Icon(hasConfig ? Icons.edit : Icons.add, size: 16),
            label: Text(hasConfig ? 'Sửa kết nối' : 'Thiết lập kết nối', style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: _accent),
          ),
          if (hasConfig) ...[
            OutlinedButton.icon(
              onPressed: () => _testGSheetConnection(_buildGSheetUrl(sheetId)),
              icon: const Icon(Icons.wifi_tethering, size: 16),
              label: const Text('Test kết nối', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: _blue),
            ),
            OutlinedButton.icon(
              onPressed: _creatingTemplate ? null : () => _createGSheetTemplate(),
              icon: _creatingTemplate
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.table_chart_outlined, size: 16),
              label: Text(_creatingTemplate ? 'Đang tạo...' : 'Tạo sheet mẫu', style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: _green),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 50, child: Text('$label:', style: TextStyle(color: Colors.grey[500], fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _buildEmployeeMappingSection(ThemeData theme) {
    if (_targets.isEmpty) return _emptyState('Chưa có nhân viên nào được giao chỉ tiêu', Icons.person_outlined);

    final configured = _targets.where((t) => t['googleCellPosition'] != null && t['googleCellPosition'].toString().isNotEmpty).toList();
    final unconfigured = _targets.where((t) => t['googleCellPosition'] == null || t['googleCellPosition'].toString().isEmpty).toList();

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
          child: Row(children: [
            Expanded(child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.people, size: 18, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              Flexible(child: Text('Ánh xạ vị trí ô (${configured.length}/${_targets.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), overflow: TextOverflow.ellipsis)),
            ])),
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                onPressed: _syncFromGoogleSheet,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Đếng b? ngay', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: _green),
              ),
              TextButton.icon(
                onPressed: () => _showBatchEditCellDialog(),
                icon: const Icon(Icons.edit_note, size: 16),
                label: const Text('Sửa tất cả', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _accent),
              ),
            ]),
          ]),
        ),
        const Divider(height: 24),
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade50,
          child: const Row(children: [
            Expanded(flex: 3, child: Text('Nhân viên', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
            Expanded(flex: 1, child: Text('Vị trí ô', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey))),
            SizedBox(width: 40),
          ]),
        ),
        const Divider(height: 24),
        // Configured employees
        ...configured.map((t) => _employeeCellRow(t, configured: true)),
        if (configured.isNotEmpty && unconfigured.isNotEmpty) Divider(height: 24, color: Colors.orange.shade100),
        // Unconfigured employees
        ...unconfigured.map((t) => _employeeCellRow(t, configured: false)),
      ]),
    );
  }

  Widget _employeeCellRow(Map<String, dynamic> t, {required bool configured}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade100))),
      child: Row(children: [
        Expanded(flex: 3, child: Row(children: [
          Icon(configured ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16, color: configured ? _green : Colors.grey[300]),
          const SizedBox(width: 8),
          Expanded(child: Text(t['employeeName'] ?? '', style: const TextStyle(fontSize: 13))),
        ])),
        Expanded(flex: 1, child: Text(
          configured ? (t['googleCellPosition'] ?? '') : '-',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: configured ? Colors.black87 : Colors.grey[400], fontFamily: 'monospace'),
        )),
        SizedBox(width: 40, child: IconButton(
          icon: const Icon(Icons.edit, size: 16, color: _accent),
          onPressed: () => _showEditSingleCellDialog(t),
          tooltip: 'Sửa vị trí ô',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        )),
      ]),
    );
  }

  Widget _buildAutoSyncSection(ThemeData theme, Map<String, dynamic> period) {
    final autoSync = period['autoSyncEnabled'] == true;
    final timeSlotsJson = period['autoSyncTimeSlots'] as String?;
    List<String> timeSlots = [];
    if (timeSlotsJson != null && timeSlotsJson.isNotEmpty) {
      try { timeSlots = List<String>.from(json.decode(timeSlotsJson)); } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: autoSync ? _blue.withValues(alpha: 0.3) : Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.schedule, color: autoSync ? _blue : Colors.grey, size: 18),
          const SizedBox(width: 8),
          Text('Tự động đồng bộ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: autoSync ? _blue : Colors.grey[700])),
          const Spacer(),
          Switch(
            value: autoSync,
            onChanged: (v) => _toggleAutoSync(v, timeSlots),
            activeThumbColor: _blue,
          ),
        ]),
        if (autoSync) ...[
          const SizedBox(height: 8),
          Text('Các mốc giờ đồng bộ tự động:', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ...timeSlots.map((slot) => Chip(
              label: Text(slot, style: const TextStyle(fontSize: 12)),
              deleteIcon: const Icon(Icons.close, size: 14),
              onDeleted: () => _removeTimeSlot(slot, timeSlots),
              backgroundColor: _blue.withValues(alpha: 0.1),
              side: BorderSide.none,
            )),
            ActionChip(
              label: const Text('+ Thêm giờ', style: TextStyle(fontSize: 12)),
              onPressed: () => _showAddTimeSlotDialog(timeSlots),
              avatar: const Icon(Icons.add, size: 14),
              backgroundColor: Colors.grey.shade100,
              side: BorderSide.none,
            ),
          ]),
          if (timeSlots.isEmpty) ...[
            const SizedBox(height: 4),
            Text('Chưa có mốc giờ nào. Nhấn "+ Thêm giờ" để thiết lập.', style: TextStyle(color: Colors.orange[700], fontSize: 11)),
          ],
        ] else ...[
          const SizedBox(height: 4),
          Text('Bật để tự động đọc dữ liệu từ Google Sheet theo lịch.', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ]),
    );
  }

  // -- GSheet Dialog: Edit connection --

  void _showEditGSheetConnectionDialog(Map<String, dynamic> period) {
    final urlCtrl = TextEditingController(text: _buildGSheetUrl(period['googleSpreadsheetId']));
    final sheetNameCtrl = TextEditingController(text: period['googleSheetName'] ?? '');
    bool testing = false;
    Map<String, dynamic>? testResult;
    List<String> availableSheets = [];
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        Future<void> onSave() async {
          final data = {
            'googleSheetUrl': urlCtrl.text.trim(),
            'googleSheetName': sheetNameCtrl.text.trim(),
            'autoSyncEnabled': period['autoSyncEnabled'] == true,
            'autoSyncTimeSlots': period['autoSyncTimeSlots'],
          };
          final res = await _api.saveKpiGSheetConfig(_selPeriodId!, data);
          if (ctx.mounted) Navigator.pop(ctx);
          if (res['isSuccess'] == true) {
            if (mounted) {
              NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã lưu kết nối Google Sheet');
              _loadData();
            }
          }
        }

        final formBody = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _field(urlCtrl, 'Link Google Sheet (URL đầy đủ)'),
          const SizedBox(height: 12),
          isMobile
            ? Column(children: [
                availableSheets.isNotEmpty
                  ? DropdownButtonFormField<String>(
                      initialValue: availableSheets.contains(sheetNameCtrl.text) ? sheetNameCtrl.text : null,
                      decoration: InputDecoration(labelText: 'Chọn Sheet', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                      items: availableSheets.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) { if (v != null) sheetNameCtrl.text = v; },
                    )
                  : _field(sheetNameCtrl, 'Tên Sheet (tab)'),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: testing ? null : () async {
                    final url = urlCtrl.text.trim();
                    if (url.isEmpty) return;
                    ss(() { testing = true; testResult = null; });
                    final res = await _api.testKpiGSheetConnection(url);
                    if (ctx.mounted) {
                      ss(() {
                        testing = false;
                        if (res['isSuccess'] == true) {
                          testResult = res['data'] as Map<String, dynamic>?;
                          final sheets = testResult?['sheetNames'];
                          if (sheets is List) {
                            availableSheets = sheets.map((e) => e.toString()).toList();
                            if (availableSheets.isNotEmpty && sheetNameCtrl.text.isEmpty) {
                              sheetNameCtrl.text = availableSheets.first;
                            }
                          }
                        } else {
                          testResult = {'connected': false, 'error': res['message'] ?? 'Lỗi kết nối'};
                        }
                      });
                    }
                  },
                  icon: testing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: Text(testing ? 'Đang test...' : 'Test kết nối', style: const TextStyle(fontSize: 12)),
                )),
              ])
            : Row(children: [
                Expanded(child: availableSheets.isNotEmpty
                  ? DropdownButtonFormField<String>(
                      initialValue: availableSheets.contains(sheetNameCtrl.text) ? sheetNameCtrl.text : null,
                      decoration: InputDecoration(labelText: 'Chọn Sheet', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                      items: availableSheets.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) { if (v != null) sheetNameCtrl.text = v; },
                    )
                  : _field(sheetNameCtrl, 'Tên Sheet (tab)'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: testing ? null : () async {
                    final url = urlCtrl.text.trim();
                    if (url.isEmpty) return;
                    ss(() { testing = true; testResult = null; });
                    final res = await _api.testKpiGSheetConnection(url);
                    if (ctx.mounted) {
                      ss(() {
                        testing = false;
                        if (res['isSuccess'] == true) {
                          testResult = res['data'] as Map<String, dynamic>?;
                          final sheets = testResult?['sheetNames'];
                          if (sheets is List) {
                            availableSheets = sheets.map((e) => e.toString()).toList();
                            if (availableSheets.isNotEmpty && sheetNameCtrl.text.isEmpty) {
                              sheetNameCtrl.text = availableSheets.first;
                            }
                          }
                        } else {
                          testResult = {'connected': false, 'error': res['message'] ?? 'Lỗi kết nối'};
                        }
                      });
                    }
                  },
                  icon: testing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 16),
                  label: Text(testing ? 'Đang test...' : 'Test', style: const TextStyle(fontSize: 12)),
                ),
              ]),
          if (testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: testResult!['connected'] == true ? _green.withValues(alpha: 0.05) : _red.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: testResult!['connected'] == true ? _green.withValues(alpha: 0.3) : _red.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                Icon(
                  testResult!['connected'] == true ? Icons.check_circle : Icons.error,
                  color: testResult!['connected'] == true ? _green : _red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      testResult!['connected'] == true
                          ? 'Kết nối thành công! Tìm thấy ${availableSheets.length} sheet.'
                          : (testResult!['notShared'] == true
                              ? 'Google Sheet chưa được chia sẻ cho service account.\nVui lòng chia sẻ quyền Viewer cho: ${testResult!['serviceAccountEmail'] ?? 'email service account'}'
                              : (testResult!['error'] ?? 'Lỗi không xác định')),
                      style: TextStyle(
                        color: testResult!['connected'] == true ? _green : _red,
                        fontSize: 12,
                      ),
                    ),
                    if (testResult!['connected'] != true && testResult!['rawError'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Chi tiết: ${testResult!['rawError']}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 10),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                )),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Nhập URL Google Sheet và nhấn "Test" để kiểm tra kết nối. '
                'Nếu chưa chia sẻ, hãy share cho service account email quyền Viewer.',
                style: TextStyle(color: Colors.blue.shade700, fontSize: 11),
              )),
            ]),
          ),
        ]);

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Thiết lập kết nối Google Sheet', style: TextStyle(fontSize: 16)),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: onSave,
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Lưu'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thiết lập kết nối Google Sheet'),
          content: SizedBox(
            width: math.min(520, MediaQuery.of(context).size.width - 32).toDouble(),
            child: SingleChildScrollView(child: formBody),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: onSave,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Lưu'),
            ),
          ],
        );
      }),
    );
  }

  // -- Test connection --

  Future<void> _testGSheetConnection(String url) async {
    if (url.isEmpty) return;
    NotificationOverlayManager().showInfo(title: 'Test kết nối', message: 'Đang test kết nối...');
    final res = await _api.testKpiGSheetConnection(url);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      if (data?['connected'] == true) {
        final sheets = data?['sheetNames'] as List? ?? [];
        NotificationOverlayManager().showSuccess(title: 'Kết nối thành công', message: 'Tìm thấy ${sheets.length} sheet.');
      } else if (data?['notShared'] == true) {
        final saEmail = data?['serviceAccountEmail'] ?? '';
        NotificationOverlayManager().showWarning(title: 'Chưa chia sẻ', message: 'Sheet chưa được chia sẻ cho service account. Chia sẻ quyền Viewer cho: $saEmail');
      } else if (data?['credentialsMissing'] == true) {
        NotificationOverlayManager().showError(title: 'Thiếu credentials', message: 'Chưa cấu hình credentials.json trên server. Liên hệ quản trị viên.');
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: data?['error'] ?? 'Không thể kết nối');
      }
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi');
    }
  }

  // -- Create GSheet template --

  Future<void> _createGSheetTemplate() async {
    if (_selPeriodId == null) return;
    setState(() => _creatingTemplate = true);
    try {
      final res = await _api.createKpiGSheetTemplate(_selPeriodId!);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        final empCount = data?['employeeCount'] ?? 0;
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Tạo sheet mẫu thành công! $empCount nhân viên. Sheet đã được lưu vào cấu hình.');
        await _loadPeriodData();
        await _loadData(showLoading: false);
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi tạo sheet mẫu');
      }
    } catch (e) {
      if (!mounted) return;
      NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _creatingTemplate = false);
    }
  }

  // -- Credentials status & upload --

  Future<void> _loadCredentialsStatus() async {
    final res = await _api.getGSheetCredentialsStatus();
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      setState(() {
        _credentialsConfigured = data?['configured'] == true;
        _serviceAccountEmail = data?['serviceAccountEmail'] as String?;
      });
    }
  }

  Future<void> _uploadCredentials() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _credentialsLoading = true);
    final res = await _api.uploadGSheetCredentials(file.bytes!.toList(), file.name);
    if (!mounted) return;
    setState(() => _credentialsLoading = false);

    if (res['isSuccess'] == true) {
      final data = res['data'] as Map<String, dynamic>?;
      if (data?['configured'] == true) {
        setState(() {
          _credentialsConfigured = true;
          _serviceAccountEmail = data?['serviceAccountEmail'] as String?;
        });
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: data?['message'] ?? 'Upload thành công!');
      } else {
        NotificationOverlayManager().showError(title: 'Lỗi', message: data?['message'] ?? res['message'] ?? 'Lỗi upload');
      }
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi upload');
    }
  }

  // -- Copy config dialog --

  void _showCopyGSheetConfigDialog() {
    final otherPeriods = _periods.where((p) => p['id']?.toString() != _selPeriodId).toList();
    if (otherPeriods.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thông báo', message: 'Không có chu kỳ khác để copy');
      return;
    }
    String? selectedSourceId;
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        Future<void> onSave() async {
          if (selectedSourceId == null) return;
          final res = await _api.copyKpiGSheetConfig(_selPeriodId!, selectedSourceId!);
          if (ctx.mounted) Navigator.pop(ctx);
          if (res['isSuccess'] == true && mounted) {
            final count = res['data']?['copiedCount'] ?? 0;
            NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã copy cấu hình ($count nhân viên)');
            _loadData();
          }
        }

        final formBody = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            decoration: InputDecoration(labelText: 'Chọn chu kỳ nguồn', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
            items: otherPeriods.map((p) => DropdownMenuItem(
              value: p['id']?.toString(),
              child: Text(p['name'] ?? '', style: const TextStyle(fontSize: 13)),
            )).toList(),
            onChanged: (v) => ss(() => selectedSourceId = v),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Thao tác này sẽ ghi đè cấu hình hiện tại (link Sheet, tên sheet, vị trí ô nhân viên, lịch đồng bộ).',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 11),
              )),
            ]),
          ),
        ]);

        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Copy cấu hình từ chu kỳ khác', style: TextStyle(fontSize: 16)),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: selectedSourceId == null ? null : onSave,
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Copy'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Copy cấu hình từ chu kỳ khác'),
          content: SizedBox(
            width: math.min(420, MediaQuery.of(context).size.width - 32).toDouble(),
            child: formBody,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: selectedSourceId == null ? null : onSave,
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Copy'),
            ),
          ],
        );
      }),
    );
  }

  // -- Batch edit cell positions --

  void _showBatchEditCellDialog() {
    final controllers = <String, TextEditingController>{};
    for (final t in _targets) {
      final empId = t['employeeId']?.toString() ?? '';
      controllers[empId] = TextEditingController(text: t['googleCellPosition'] ?? '');
    }
    final isMobile = Responsive.isMobile(context);

    Future<void> onSave(BuildContext ctx) async {
      final mappings = controllers.entries.map((e) => {
        'employeeId': e.key,
        'cellPosition': e.value.text.trim(),
      }).toList();

      final period = _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => {});
      final data = {
        'googleSheetUrl': _buildGSheetUrl(period['googleSpreadsheetId']),
        'googleSheetName': period['googleSheetName'] ?? '',
        'autoSyncEnabled': period['autoSyncEnabled'] == true,
        'autoSyncTimeSlots': period['autoSyncTimeSlots'],
        'employeeMappings': mappings,
      };

      final res = await _api.saveKpiGSheetConfig(_selPeriodId!, data);
      if (ctx.mounted) Navigator.pop(ctx);
      if (res['isSuccess'] == true && mounted) {
        NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã lưu vị trí ô');
        _loadPeriodData();
      }
    }

    Widget buildContent() {
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Nhập vị trí ô chứa doanh số/point của nhân viên trên Google Sheet (VD: B5, C10, D3).',
              style: TextStyle(color: Colors.blue.shade700, fontSize: 11),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        ..._targets.map((t) {
          final empId = t['employeeId']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: isMobile
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['employeeName'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 36,
                    child: TextField(
                      controller: controllers[empId],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: 'VD: B5',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ])
              : Row(children: [
                  Expanded(flex: 3, child: Text(t['employeeName'] ?? '', style: const TextStyle(fontSize: 13))),
                  Expanded(flex: 1, child: SizedBox(
                    height: 36,
                    child: TextField(
                      controller: controllers[empId],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                      decoration: InputDecoration(
                        hintText: 'VD: B5',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  )),
                ]),
          );
        }),
      ]);
    }

    showDialog(
      context: context,
      builder: (ctx) {
        if (isMobile) {
          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Thiết lập vị trí ô', style: TextStyle(fontSize: 16)),
                leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton(
                      onPressed: () => onSave(ctx),
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Lưu tất cả'),
                    ),
                  ),
                ],
              ),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: buildContent()),
            ),
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Thiết lập vị trí ô cho tất cả nhân viên'),
          content: SizedBox(
            width: math.min(500, MediaQuery.of(context).size.width - 32).toDouble(),
            height: 400,
            child: SingleChildScrollView(child: buildContent()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton(
              onPressed: () => onSave(ctx),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('Lưu tất cả'),
            ),
          ],
        );
      },
    );
  }

  // -- Edit single cell position --

  void _showEditSingleCellDialog(Map<String, dynamic> target) {
    final cellCtrl = TextEditingController(text: target['googleCellPosition'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Vị trí ô: ${target['employeeName'] ?? ''}', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _field(cellCtrl, 'Vị trí ô (VD: B5, C10)'),
            const SizedBox(height: 8),
            Text('Nhập vị trí ô trên Google Sheet chứa giá trị doanh số / point.',
                style: TextStyle(color: Colors.grey[500], fontSize: 11)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final empId = target['employeeId']?.toString() ?? '';
              final period = _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => {});
              final data = {
                'googleSheetUrl': _buildGSheetUrl(period['googleSpreadsheetId']),
                'googleSheetName': period['googleSheetName'] ?? '',
                'autoSyncEnabled': period['autoSyncEnabled'] == true,
                'autoSyncTimeSlots': period['autoSyncTimeSlots'],
                'employeeMappings': [{'employeeId': empId, 'cellPosition': cellCtrl.text.trim()}],
              };

              final res = await _api.saveKpiGSheetConfig(_selPeriodId!, data);
              if (ctx.mounted) Navigator.pop(ctx);
              if (res['isSuccess'] == true && mounted) {
                NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã lưu vị trí ô');
                _loadPeriodData();
              }
            },
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  // -- Auto-sync helpers --

  void _toggleAutoSync(bool enabled, List<String> currentSlots) async {
    final period = _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => {});
    final data = {
      'googleSheetUrl': _buildGSheetUrl(period['googleSpreadsheetId']),
      'googleSheetName': period['googleSheetName'] ?? '',
      'autoSyncEnabled': enabled,
      'autoSyncTimeSlots': json.encode(currentSlots),
    };
    final res = await _api.saveKpiGSheetConfig(_selPeriodId!, data);
    if (res['isSuccess'] == true && mounted) {
      _loadData();
    }
  }

  void _removeTimeSlot(String slot, List<String> currentSlots) async {
    final updated = currentSlots.where((s) => s != slot).toList();
    final period = _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => {});
    final data = {
      'googleSheetUrl': _buildGSheetUrl(period['googleSpreadsheetId']),
      'googleSheetName': period['googleSheetName'] ?? '',
      'autoSyncEnabled': period['autoSyncEnabled'] == true,
      'autoSyncTimeSlots': json.encode(updated),
    };
    final res = await _api.saveKpiGSheetConfig(_selPeriodId!, data);
    if (res['isSuccess'] == true && mounted) _loadData();
  }

  void _showAddTimeSlotDialog(List<String> currentSlots) {
    int selectedHour = 8;
    int selectedMinute = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Thêm mốc giờ đồng bộ', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              // Hour picker
              SizedBox(width: 80, child: DropdownButtonFormField<int>(
                initialValue: selectedHour,
                decoration: InputDecoration(labelText: 'Gi?', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                items: List.generate(24, (i) => DropdownMenuItem(value: i, child: Text(i.toString().padLeft(2, '0')))),
                onChanged: (v) => ss(() => selectedHour = v ?? 8),
              )),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text(':', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
              SizedBox(width: 80, child: DropdownButtonFormField<int>(
                initialValue: selectedMinute,
                decoration: InputDecoration(labelText: 'Phút', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                items: [0, 15, 30, 45].map((m) => DropdownMenuItem(value: m, child: Text(m.toString().padLeft(2, '0')))).toList(),
                onChanged: (v) => ss(() => selectedMinute = v ?? 0),
              )),
            ]),
            const SizedBox(height: 12),
            if (currentSlots.isNotEmpty) ...[
              Text('Đã thiết lập: ${currentSlots.join(", ")}', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final slot = '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}';
              if (currentSlots.contains(slot)) {
                NotificationOverlayManager().showWarning(title: 'Trùng lặp', message: 'Mốc $slot đã tồn tại');
                return;
              }
              final updated = [...currentSlots, slot]..sort();
              Navigator.pop(ctx);

              final period = _periods.firstWhere((p) => p['id']?.toString() == _selPeriodId, orElse: () => {});
              final data = {
                'googleSheetUrl': _buildGSheetUrl(period['googleSpreadsheetId']),
                'googleSheetName': period['googleSheetName'] ?? '',
                'autoSyncEnabled': period['autoSyncEnabled'] == true,
                'autoSyncTimeSlots': json.encode(updated),
              };
              final res = await _api.saveKpiGSheetConfig(_selPeriodId!, data);
              if (res['isSuccess'] == true && mounted) _loadData();
            },
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: const Text('Thêm'),
          ),
        ],
      )),
    );
  }

  // ------------------------------------------------
  //  IMPORT EXCEL / SYNC GSHEET
  // ------------------------------------------------

  Future<void> _importExcelActuals() async {
    if (_selPeriodId == null) return;

    // Chọn file Excel
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.first.bytes == null) return;

    try {
      final bytes = result.files.first.bytes!;
      final excel = excel_lib.Excel.decodeBytes(bytes);

      // Đọc sheet đầu tiên
      final sheetName = excel.tables.keys.first;
      final table = excel.tables[sheetName];
      if (table == null || table.rows.length < 2) {
        if (mounted) NotificationOverlayManager().showWarning(title: 'Thiếu dữ liệu', message: 'File không có dữ liệu (cần ít nhất 2 dòng)');
        return;
      }

      // Parse rows: Col A = Mã NV, Col C = Tổng KPI (doanh s? th?c t?)
      final List<Map<String, dynamic>> importData = [];
      for (int i = 1; i < table.rows.length; i++) {
        final row = table.rows[i];
        if (row.isEmpty) continue;
        final empCode = row.isNotEmpty ? (row[0]?.value?.toString() ?? '').trim() : '';
        if (empCode.isEmpty) continue;
        // Cột C = Tổng KPI (actual value)
        final actualStr = row.length > 2 ? (row[2]?.value?.toString() ?? '0') : '0';
        final actual = double.tryParse(actualStr.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
        importData.add({'employeeCode': empCode, 'actualValue': actual});
      }

      if (importData.isEmpty) {
        if (mounted) NotificationOverlayManager().showWarning(title: 'Không hợp lệ', message: 'Không tìm thấy dữ liệu hợp lệ trong file');
        return;
      }

      // Gửi dữ liệu lên API
      final res = await _api.importKpiExcelActuals(_selPeriodId!, data: importData);
      if (mounted) {
        if (res['isSuccess'] == true) {
          final count = res['data']?['updatedCount'] ?? 0;
          NotificationOverlayManager().showSuccess(title: 'Import thành công', message: 'Đã cập nhật doanh số cho $count nhân viên');
          _loadPeriodData();
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: ${res['message'] ?? 'Không xác định'}');
        }
      }
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi import: $e');
    }
  }

  // ignore: unused_element
  Widget _excelFormatRow(String col, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          child: Text(col, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade800)),
        ),
        const SizedBox(width: 8),
        Text(desc, style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
      ]),
    );
  }

  // ignore: unused_element
  Future<void> _downloadExcelTemplate() async {
    try {
      final bytes = await _api.downloadKpiExcelTemplate(_selPeriodId!, _targets);
      if (bytes != null) {
        await file_saver.saveFileBytes(
          bytes,
          'kpi_template_$_selPeriodId.xlsx',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
        if (mounted) NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã tải file mẫu');
      } else if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể tải file mẫu');
      }
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
    }
  }

  Future<void> _writeTargetsToGSheet() async {
    if (_selPeriodId == null) return;
    try {
      setState(() => _loading = true);
      final res = await _api.writeKpiTargetsToGSheet(_selPeriodId!);
      if (mounted) {
        if (res['isSuccess'] == true) {
          final count = res['data']?['writtenCount'] ?? 0;
          final total = res['data']?['totalRows'] ?? 0;
          final errors = res['data']?['errors'] as List? ?? [];
          final errMsg = errors.isNotEmpty ? '\n${errors.join('\n')}' : '';
          NotificationOverlayManager().showSuccess(title: 'Ghi chỉ tiêu', message: 'Đã ghi chỉ tiêu cho $count/$total nhân viên vào cột D Google Sheet$errMsg');
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: ${res['message'] ?? ''}');
        }
      }
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi ghi chỉ tiêu: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _syncFromGoogleSheet() async {
    if (_selPeriodId == null) return;
    try {
      setState(() => _loading = true);
      final res = await _api.syncKpiActualsFromGSheet(_selPeriodId!);
      if (mounted) {
        if (res['isSuccess'] == true) {
          final count = res['data']?['updatedCount'] ?? 0;
          final errors = res['data']?['errors'] as List? ?? [];
          final errMsg = errors.isNotEmpty ? '\n${errors.join('\n')}' : '';
          NotificationOverlayManager().showSuccess(title: 'Đồng bộ', message: 'Đã đồng bộ doanh số cho $count nhân viên từ Google Sheet$errMsg');
          _loadPeriodData();
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: ${res['message'] ?? ''}');
        }
      }
    } catch (e) {
      if (mounted) NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi đồng bộ: $e');
    }
    if (mounted) setState(() => _loading = false);
  }
}
