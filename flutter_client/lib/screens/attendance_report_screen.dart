import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'dart:convert';
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
  final _searchCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isExporting = false;
  bool _showMobileFilters = false;
  String _reportType = 'daily';

  // Date filters
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  // Search & department filter
  String _searchText = '';
  String? _departmentFilter;
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];

  // Sorting
  String _sortColumn = 'default';
  bool _sortAscending = true;

  Map<String, dynamic>? _reportData;
  List<dynamic> _trendData = [];

  @override
  void initState() {
    super.initState();
    _loadTrends();
    _loadReport();
    _loadEmployeesAndBranches();
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrends() async {
    try {
      final result = await _apiService.getAttendanceTrends(days: 30);
      if (mounted) setState(() => _trendData = result);
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
          result =
              await _apiService.getDailyAttendanceReport(date: _selectedDate);
          break;
        case 'monthly':
          result = await _apiService.getMonthlyAttendanceReport(
              year: _selectedYear, month: _selectedMonth);
          break;
        case 'late-early':
          result = await _apiService.getLateEarlyReport(
              startDate: _startDate, endDate: _endDate);
          break;
        case 'department':
          result = await _apiService.getDepartmentSummaryReport(
              year: _selectedYear, month: _selectedMonth);
          break;
        case 'overtime':
          result = await _apiService.getOvertimeReport(
              startDate: _startDate, endDate: _endDate);
          break;
        case 'leave':
          result = await _apiService.getLeaveReport(
              startDate: _startDate, endDate: _endDate);
          break;
        default:
          result = {'isSuccess': false};
      }
      if (result['isSuccess'] == true && mounted) {
        setState(() => _reportData = result['data']);
      } else if (mounted) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: result['message'] ?? _l10n.loadError);
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _isExporting = true);
    try {
      Map<String, dynamic> result;
      String fileName;
      switch (_reportType) {
        case 'daily':
          result =
              await _apiService.exportDailyReportExcel(date: _selectedDate);
          fileName =
              'cc_hang_ngay_${DateFormat('yyyyMMdd').format(_selectedDate)}.xlsx';
          break;
        case 'monthly':
          result = await _apiService.exportMonthlyReportExcel(
              year: _selectedYear, month: _selectedMonth);
          fileName = 'cc_thang_${_selectedYear}_$_selectedMonth.xlsx';
          break;
        case 'late-early':
          result = await _apiService.exportLateEarlyReportExcel(
              startDate: _startDate, endDate: _endDate);
          fileName =
              'di_muon_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        case 'department':
          result = await _apiService.exportDepartmentSummaryExcel(
              year: _selectedYear, month: _selectedMonth);
          fileName = 'phong_ban_${_selectedYear}_$_selectedMonth.xlsx';
          break;
        case 'overtime':
          result = await _apiService.exportOvertimeReportExcel(
              startDate: _startDate, endDate: _endDate);
          fileName =
              'tang_ca_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        case 'leave':
          result = await _apiService.exportLeaveReportExcel(
              startDate: _startDate, endDate: _endDate);
          fileName =
              'nghi_phep_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        default:
          return;
      }
      if (result['isSuccess'] != true) {
        if (mounted) {
          NotificationOverlayManager().showError(
              title: 'Lỗi',
              message: result['message'] ?? 'Xuất Excel thất bại');
        }
        return;
      }
      final excelData = (result['data'] as List?)?.cast<int>();
      if (excelData != null && mounted) {
        await file_saver.saveFileBytes(excelData, fileName,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        NotificationOverlayManager()
            .showSuccess(title: 'Xuất Excel', message: _l10n.excelExported);
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Lỗi xuất: $e');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportCsv() async {
    final items = _filteredItems;
    if (items.isEmpty) {
      NotificationOverlayManager().showError(
          title: 'Không có dữ liệu', message: 'Chưa có dữ liệu để xuất');
      return;
    }
    final buf = StringBuffer();
    final cols = _csvColumns();
    buf.writeln(cols.join(','));
    for (var i = 0; i < items.length; i++) {
      final m = items[i] as Map<String, dynamic>;
      buf.writeln(_csvRow(i, m));
    }
    final bytes = utf8.encode(buf.toString());
    final suffix = _fileSuffix();
    await file_saver.saveFileBytes(
        bytes,
        'bao_cao_cham_cong_${_reportType}_$suffix.csv',
        'text/csv;charset=utf-8');
    if (mounted) {
      NotificationOverlayManager()
          .showSuccess(title: 'Xuất CSV', message: 'Đã xuất file CSV');
    }
  }

  String _fileSuffix() {
    switch (_reportType) {
      case 'daily':
        return DateFormat('yyyyMMdd').format(_selectedDate);
      case 'monthly':
      case 'department':
        return '${_selectedYear}_${_selectedMonth.toString().padLeft(2, '0')}';
      default:
        return '${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}';
    }
  }

  List<String> _csvColumns() {
    switch (_reportType) {
      case 'daily':
        return [
          'STT',
          'Mã NV',
          'Họ tên',
          'Phòng ban',
          'Giờ vào',
          'Giờ ra',
          'Đi muộn (p)',
          'Về sớm (p)',
          'Trạng thái'
        ];
      case 'monthly':
        return [
          'STT',
          'Mã NV',
          'Họ tên',
          'Phòng ban',
          'Ngày làm',
          'Ngày muộn',
          'Ngày nghỉ',
          'Ngày vắng',
          'Số giờ',
          'Tỷ lệ CC'
        ];
      case 'late-early':
        return [
          'STT',
          'Mã NV',
          'Họ tên',
          'Phòng ban',
          'Lần muộn',
          'Phút muộn',
          'Lần về sớm',
          'Phút về sớm'
        ];
      case 'department':
        return [
          'STT',
          'Phòng ban',
          'Số NV',
          'Tổng CC',
          'Đi muộn',
          'Tổng giờ',
          'TB giờ/ngày',
          'Tỷ lệ CC'
        ];
      case 'overtime':
        return [
          'STT',
          'Mã NV',
          'Họ tên',
          'Phòng ban',
          'Ngày tăng ca',
          'Phút tăng ca',
          'Giờ tăng ca'
        ];
      case 'leave':
        return [
          'STT',
          'Mã NV',
          'Họ tên',
          'Phòng ban',
          'Loại nghỉ',
          'Tổng ngày',
          'Đã dùng',
          'Còn lại'
        ];
      default:
        return [];
    }
  }

  String _csvRow(int i, Map<String, dynamic> m) {
    String q(dynamic v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
    switch (_reportType) {
      case 'daily':
        return '${i + 1},${q(m['employeeCode'])},${q(m['employeeName'])},${q(m['departmentName'])},${q(_fmtTime(m['checkInTime']))},${q(_fmtTime(m['checkOutTime']))},${m['lateMinutes'] ?? 0},${m['earlyLeaveMinutes'] ?? 0},${q(m['status'])}';
      case 'monthly':
        return '${i + 1},${q(m['employeeCode'])},${q(m['employeeName'])},${q(m['departmentName'])},${m['totalDaysWorked'] ?? 0},${m['totalLateDays'] ?? 0},${m['totalLeaveDays'] ?? 0},${m['totalAbsentDays'] ?? 0},${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)},${m['attendanceRate'] ?? 0}';
      case 'late-early':
        return '${i + 1},${q(m['employeeCode'])},${q(m['employeeName'])},${q(m['departmentName'])},${m['lateCount'] ?? 0},${m['totalLateMinutes'] ?? 0},${m['earlyLeaveCount'] ?? 0},${m['totalEarlyMinutes'] ?? 0}';
      case 'department':
        return '${i + 1},${q(m['departmentName'])},${m['employeeCount'] ?? 0},${m['totalAttendance'] ?? 0},${m['totalLateCount'] ?? 0},${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)},${(m['averageWorkedHoursPerDay'] ?? 0).toStringAsFixed(1)},${m['attendanceRate'] ?? 0}';
      case 'overtime':
        return '${i + 1},${q(m['employeeCode'])},${q(m['employeeName'])},${q(m['departmentName'])},${m['overtimeDays'] ?? 0},${m['totalOvertimeMinutes'] ?? 0},${(m['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}';
      case 'leave':
        return '${i + 1},${q(m['employeeCode'])},${q(m['employeeName'])},${q(m['departmentName'])},${q(m['leaveType'])},${m['totalDays'] ?? 0},${m['usedDays'] ?? 0},${m['remainingDays'] ?? 0}';
      default:
        return '';
    }
  }

  // ===== Filtering & sorting =====

  List<dynamic> get _filteredItems {
    final raw = (_reportData?['items'] as List?) ?? [];
    Set<String>? branchCodes;
    if (_selectedBranchId != null) {
      branchCodes = _employeesList
          .where((e) => e['branchId']?.toString() == _selectedBranchId)
          .map((e) => e['employeeCode']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();
    }
    final items = raw.where((item) {
      final m = item as Map<String, dynamic>;
      if (branchCodes != null &&
          !branchCodes.contains(m['employeeCode']?.toString())) {
        return false;
      }
      if (_departmentFilter != null &&
          (m['departmentName'] ?? '') != _departmentFilter) {
        return false;
      }
      if (_searchText.isNotEmpty) {
        final s = _searchText.toLowerCase();
        final name = (m['employeeName'] ?? '').toString().toLowerCase();
        final code = (m['employeeCode'] ?? '').toString().toLowerCase();
        final dept = (m['departmentName'] ?? '').toString().toLowerCase();
        if (!name.contains(s) && !code.contains(s) && !dept.contains(s)) {
          return false;
        }
      }
      return true;
    }).toList();

    if (_sortColumn != 'default') {
      items.sort((a, b) {
        final ma = a as Map<String, dynamic>;
        final mb = b as Map<String, dynamic>;
        final va = ma[_sortColumn];
        final vb = mb[_sortColumn];
        int cmp;
        if (va is num && vb is num) {
          cmp = va.compareTo(vb);
        } else {
          cmp = (va?.toString() ?? '').compareTo(vb?.toString() ?? '');
        }
        return _sortAscending ? cmp : -cmp;
      });
    }
    return items;
  }

  List<String> get _availableDepartments {
    final raw = (_reportData?['items'] as List?) ?? [];
    final s = <String>{};
    for (final item in raw) {
      final d = (item as Map<String, dynamic>)['departmentName'];
      if (d != null && d.toString().isNotEmpty) s.add(d.toString());
    }
    return s.toList()..sort();
  }

  // ===== Build =====

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildActionBar(),
          if (!isMobile || _showMobileFilters) _buildFilters(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      await Future.wait([_loadTrends(), _loadReport()]);
                    },
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.all(isMobile ? 12 : 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildReportTypeSelector(),
                          const SizedBox(height: 12),
                          if (_trendData.isNotEmpty) ...[
                            _buildTrendChart(),
                            const SizedBox(height: 12),
                          ],
                          if (_reportData != null) ...[
                            _buildSummaryCards(),
                            const SizedBox(height: 12),
                            _buildSearchBar(),
                            const SizedBox(height: 8),
                            _buildDataSection(),
                          ] else
                            _buildEmptyState(),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      color: Colors.white,
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _periodLabel(),
              style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isMobile) ...[
            IconButton(
              tooltip: 'Bộ lọc',
              onPressed: () =>
                  setState(() => _showMobileFilters = !_showMobileFilters),
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
              tooltip: 'Tạo báo cáo',
              onPressed: _isLoading ? null : _loadReport,
              icon: const Icon(Icons.refresh, color: Color(0xFF1E3A5F)),
            ),
            if (Provider.of<PermissionProvider>(context, listen: false)
                .canExport('AttendanceReport'))
              PopupMenuButton<String>(
                tooltip: 'Xuất',
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download, color: Color(0xFF1E3A5F)),
                onSelected: (v) {
                  if (v == 'excel') _exportExcel();
                  if (v == 'csv') _exportCsv();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'excel',
                      child: Row(children: [
                        Icon(Icons.table_chart, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Xuất Excel'),
                      ])),
                  PopupMenuItem(
                      value: 'csv',
                      child: Row(children: [
                        Icon(Icons.file_present, size: 18, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Xuất CSV'),
                      ])),
                ],
              ),
          ] else ...[
            if (Provider.of<PermissionProvider>(context, listen: false)
                .canExport('AttendanceReport')) ...[
              OutlinedButton.icon(
                onPressed: _isExporting ? null : _exportCsv,
                icon: const Icon(Icons.file_present, size: 16),
                label: const Text('CSV'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isExporting ? null : _exportExcel,
                icon: _isExporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.table_chart, size: 16),
                label: const Text('Excel'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white),
              ),
              const SizedBox(width: 8),
            ],
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _loadReport,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Tạo báo cáo'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  String _periodLabel() {
    switch (_reportType) {
      case 'daily':
        return 'Ngày ${DateFormat('dd/MM/yyyy').format(_selectedDate)}';
      case 'monthly':
      case 'department':
        return 'Tháng ${_selectedMonth.toString().padLeft(2, '0')}/$_selectedYear';
      default:
        return '${DateFormat('dd/MM/yyyy').format(_startDate)} → ${DateFormat('dd/MM/yyyy').format(_endDate)}';
    }
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDateControls(),
          const SizedBox(height: 8),
          _buildQuickPresets(),
        ],
      ),
    );
  }

  Widget _buildDateControls() {
    switch (_reportType) {
      case 'daily':
        return Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 16),
              label: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
              onPressed: () async {
                final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now());
                if (date != null) {
                  setState(() => _selectedDate = date);
                  _loadReport();
                }
              },
            ),
          ),
        ]);
      case 'monthly':
      case 'department':
        return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  initialValue: _selectedMonth,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Tháng',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                          value: i + 1, child: Text('Tháng ${i + 1}'))),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedMonth = v);
                      _loadReport();
                    }
                  },
                ),
              ),
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
                  items: List.generate(
                      5,
                      (i) => DropdownMenuItem(
                          value: DateTime.now().year - i,
                          child: Text('${DateTime.now().year - i}'))),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedYear = v);
                      _loadReport();
                    }
                  },
                ),
              ),
            ]);
      case 'late-early':
      case 'overtime':
      case 'leave':
        return Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text('Từ ${DateFormat('dd/MM').format(_startDate)}'),
            onPressed: () async {
              final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (date != null) {
                setState(() => _startDate = date);
                _loadReport();
              }
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text('Đến ${DateFormat('dd/MM').format(_endDate)}'),
            onPressed: () async {
              final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now());
              if (date != null) {
                setState(() => _endDate = date);
                _loadReport();
              }
            },
          ),
        ]);
      default:
        return const SizedBox();
    }
  }

  Widget _buildQuickPresets() {
    final presets = <_Preset>[];
    if (_reportType == 'daily') {
      presets.addAll([
        _Preset('Hôm nay', () {
          setState(() => _selectedDate = DateTime.now());
          _loadReport();
        }),
        _Preset('Hôm qua', () {
          setState(() =>
              _selectedDate = DateTime.now().subtract(const Duration(days: 1)));
          _loadReport();
        }),
      ]);
    } else if (_reportType == 'monthly' || _reportType == 'department') {
      presets.addAll([
        _Preset('Tháng này', () {
          final now = DateTime.now();
          setState(() {
            _selectedMonth = now.month;
            _selectedYear = now.year;
          });
          _loadReport();
        }),
        _Preset('Tháng trước', () {
          final now = DateTime.now();
          final prev = DateTime(now.year, now.month - 1, 1);
          setState(() {
            _selectedMonth = prev.month;
            _selectedYear = prev.year;
          });
          _loadReport();
        }),
      ]);
    } else {
      presets.addAll([
        _Preset('7 ngày', () {
          setState(() {
            _endDate = DateTime.now();
            _startDate = DateTime.now().subtract(const Duration(days: 7));
          });
          _loadReport();
        }),
        _Preset('30 ngày', () {
          setState(() {
            _endDate = DateTime.now();
            _startDate = DateTime.now().subtract(const Duration(days: 30));
          });
          _loadReport();
        }),
        _Preset('Tháng này', () {
          final now = DateTime.now();
          setState(() {
            _startDate = DateTime(now.year, now.month, 1);
            _endDate = now;
          });
          _loadReport();
        }),
      ]);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: presets
          .map((p) => ActionChip(
                label: Text(p.label, style: const TextStyle(fontSize: 12)),
                onPressed: p.onTap,
                backgroundColor: const Color(0xFFEFF4FB),
                side: BorderSide(color: Colors.blue.shade100),
              ))
          .toList(),
    );
  }

  Widget _buildReportTypeSelector() {
    final types = [
      {'id': 'daily', 'name': 'Hằng ngày', 'icon': Icons.today},
      {'id': 'monthly', 'name': 'Hằng tháng', 'icon': Icons.calendar_month},
      {'id': 'late-early', 'name': 'Muộn/Sớm', 'icon': Icons.schedule},
      {'id': 'department', 'name': 'Phòng ban', 'icon': Icons.business},
      {'id': 'overtime', 'name': 'Tăng ca', 'icon': Icons.more_time},
      {'id': 'leave', 'name': 'Nghỉ phép', 'icon': Icons.event_busy},
    ];
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: types.map((t) {
            final selected = _reportType == t['id'];
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(t['icon'] as IconData,
                      size: 16,
                      color: selected ? Colors.white : const Color(0xFF1E3A5F)),
                  const SizedBox(width: 6),
                  Text(t['name'] as String,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : const Color(0xFF1E3A5F))),
                ]),
                selected: selected,
                selectedColor: const Color(0xFF1E3A5F),
                backgroundColor: const Color(0xFFF1F5F9),
                onSelected: (_) {
                  setState(() {
                    _reportType = t['id'] as String;
                    _reportData = null;
                    _departmentFilter = null;
                    _sortColumn = 'default';
                  });
                  _loadReport();
                },
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                showCheckmark: false,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final depts = _availableDepartments;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                hintText: 'Tìm mã/họ tên/phòng ban',
                prefixIcon: Icon(Icons.search, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchText = v),
            ),
          ),
          if (depts.isNotEmpty && _reportType != 'department')
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: _departmentFilter,
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
                onChanged: (v) => setState(() => _departmentFilter = v),
              ),
            ),
          if (_branches.isNotEmpty)
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String?>(
                key: ValueKey('branch_$_selectedBranchId'),
                initialValue: _selectedBranchId,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Chi nh\u00e1nh',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('T\u1ea5t c\u1ea3')),
                  ..._branches.map((b) => DropdownMenuItem<String?>(
                      value: b['id']?.toString(),
                      child: Text(b['name']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) => setState(() => _selectedBranchId = v),
              ),
            ),
          if (_searchText.isNotEmpty ||
              _departmentFilter != null ||
              _selectedBranchId != null)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _searchText = '';
                  _departmentFilter = null;
                  _selectedBranchId = null;
                  _searchCtrl.clear();
                });
              },
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Xo\u00e0 l\u1ecdc'),
            ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
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
          Text(_l10n.trend30Days,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E3A5F))),
          const SizedBox(height: 6),
          Row(children: [
            _legendDot(Colors.green, _l10n.present),
            const SizedBox(width: 16),
            _legendDot(Colors.red, 'Vắng'),
            const SizedBox(width: 16),
            _legendDot(Colors.orange, 'Đi muộn'),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 32,
                          getTitlesWidget: (v, _) => Text('${v.toInt()}',
                              style: const TextStyle(fontSize: 10)))),
                  bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 30,
                          interval: (_trendData.length / 6)
                              .ceilToDouble()
                              .clamp(1, double.infinity),
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= 0 && idx < _trendData.length) {
                              final d = DateTime.tryParse(
                                  _trendData[idx]['date'] ?? '');
                              if (d != null) {
                                return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(DateFormat('dd/MM').format(d),
                                        style: const TextStyle(fontSize: 9)));
                              }
                            }
                            return const SizedBox();
                          })),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => spots
                          .map((s) => LineTooltipItem('${s.y.toInt()}',
                              TextStyle(color: s.bar.color, fontSize: 11)))
                          .toList()),
                ),
                lineBarsData: [
                  _lineData(
                      Colors.green,
                      _trendData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(
                              e.key.toDouble(),
                              ((e.value['present'] ??
                                      e.value['totalCheckIns'] ??
                                      0) as num)
                                  .toDouble()))
                          .toList()),
                  _lineData(
                      Colors.red,
                      _trendData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(
                              e.key.toDouble(),
                              ((e.value['absent'] ?? e.value['absences'] ?? 0)
                                      as num)
                                  .toDouble()))
                          .toList()),
                  _lineData(
                      Colors.orange,
                      _trendData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(
                              e.key.toDouble(),
                              ((e.value['late'] ?? e.value['lateArrivals'] ?? 0)
                                      as num)
                                  .toDouble()))
                          .toList()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _lineData(Color color, List<FlSpot> spots) {
    return LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData:
            BarAreaData(show: true, color: color.withValues(alpha: 0.08)));
  }

  Widget _legendDot(Color color, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 12)),
    ]);
  }

  Widget _buildSummaryCards() {
    final data = _reportData!;
    List<_CardData> cards;
    switch (_reportType) {
      case 'daily':
        cards = [
          _CardData(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}',
              Icons.people, Colors.blue),
          _CardData(_l10n.present, '${data['present'] ?? 0}',
              Icons.check_circle, Colors.green),
          _CardData(
              'Đi muộn', '${data['late'] ?? 0}', Icons.schedule, Colors.orange),
          _CardData('Về sớm', '${data['earlyLeave'] ?? 0}', Icons.exit_to_app,
              Colors.amber.shade700),
          _CardData('Vắng mặt', '${data['absent'] ?? 0}', Icons.person_off,
              Colors.red),
          _CardData('Tỷ lệ CC', '${data['attendanceRate'] ?? 0}%',
              Icons.percent, Colors.indigo),
        ];
        break;
      case 'monthly':
        cards = [
          _CardData(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}',
              Icons.people, Colors.blue),
          _CardData('Ngày làm việc', '${data['workingDays'] ?? 0}',
              Icons.calendar_today, Colors.green),
          _CardData('Tháng', '${data['month']}/${data['year']}',
              Icons.date_range, Colors.teal),
        ];
        break;
      case 'late-early':
        cards = [
          _CardData(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}',
              Icons.people, Colors.blue),
          _CardData('NV vi phạm', '${data['employeesWithIssues'] ?? 0}',
              Icons.warning, Colors.orange),
          _CardData('Lần muộn', '${data['totalLateCount'] ?? 0}',
              Icons.schedule, Colors.red),
          _CardData('Phút muộn', '${data['totalLateMinutes'] ?? 0}',
              Icons.timer, Colors.red.shade700),
          _CardData('Lần về sớm', '${data['totalEarlyLeaveCount'] ?? 0}',
              Icons.exit_to_app, Colors.amber.shade700),
        ];
        break;
      case 'department':
        cards = [
          _CardData('Phòng ban', '${data['totalDepartments'] ?? 0}',
              Icons.business, Colors.blue),
          _CardData(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}',
              Icons.people, Colors.green),
          _CardData('Ngày LV', '${data['workingDays'] ?? 0}',
              Icons.calendar_today, Colors.teal),
        ];
        break;
      case 'overtime':
        cards = [
          _CardData(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}',
              Icons.people, Colors.blue),
          _CardData('NV tăng ca', '${data['employeesWithOvertime'] ?? 0}',
              Icons.person, Colors.orange),
          _CardData('Tổng phút', '${data['totalOvertimeMinutes'] ?? 0}',
              Icons.timer, Colors.red),
          _CardData(
              'Tổng giờ',
              '${(data['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}h',
              Icons.more_time,
              Colors.deepOrange),
        ];
        break;
      case 'leave':
        cards = [
          _CardData(_l10n.totalEmployees, '${data['totalEmployees'] ?? 0}',
              Icons.people, Colors.blue),
          _CardData('NV nghỉ phép', '${data['employeesWithLeave'] ?? 0}',
              Icons.person_off, Colors.orange),
          _CardData('Tổng đơn', '${data['totalLeaveRequests'] ?? 0}',
              Icons.description, Colors.purple),
          _CardData('Tổng ngày', '${data['totalLeaveDays'] ?? 0}',
              Icons.event_busy, Colors.red),
        ];
        break;
      default:
        cards = [];
    }

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      int cols;
      if (w >= 1100) {
        cols = 6;
      } else if (w >= 800) {
        cols = 4;
      } else if (w >= 500) {
        cols = 3;
      } else {
        cols = 2;
      }
      cols = cols.clamp(1, cards.length);
      const spacing = 10.0;
      final cardW = (w - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: cards
            .map((c) => SizedBox(width: cardW, child: _summaryCard(c)))
            .toList(),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.value,
                      style: TextStyle(
                          fontSize: 16,
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

  Widget _buildDataSection() {
    final items = _filteredItems;
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7))),
        child: Center(
          child: Column(children: [
            Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text(_l10n.noData, style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );
    }

    final isMobile = Responsive.isMobile(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Chi tiết (${items.length} bản ghi)',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A5F))),
          ),
          if (isMobile)
            ...items.asMap().entries.map((e) => _mobileRow(e.key, e.value))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFF1E3A5F)),
                dataTextStyle: const TextStyle(fontSize: 12),
                showCheckboxColumn: false,
                columns: _columns(),
                rows: items
                    .asMap()
                    .entries
                    .map((e) => _row(e.key, e.value))
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _mobileRow(int idx, dynamic item) {
    final m = item as Map<String, dynamic>;
    List<Widget> lines = [];
    Widget header;

    switch (_reportType) {
      case 'daily':
        header = Row(children: [
          Expanded(
              child: Text('${m['employeeName'] ?? ''}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis)),
          _statusChip(m['status'] ?? ''),
        ]);
        lines = [
          _kv('${m['employeeCode'] ?? ''} · ${m['departmentName'] ?? ''}', ''),
          _kv('Giờ vào', _fmtTime(m['checkInTime'])),
          _kv('Giờ ra', _fmtTime(m['checkOutTime'])),
          if ((m['lateMinutes'] ?? 0) > 0)
            _kv('Đi muộn', '${m['lateMinutes']} phút',
                color: Colors.orange.shade700),
          if ((m['earlyLeaveMinutes'] ?? 0) > 0)
            _kv('Về sớm', '${m['earlyLeaveMinutes']} phút',
                color: Colors.amber.shade700),
        ];
        break;
      case 'monthly':
        header = Text('${m['employeeName'] ?? ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold));
        lines = [
          _kv('${m['employeeCode'] ?? ''} · ${m['departmentName'] ?? ''}', ''),
          _kv('Ngày làm', '${m['totalDaysWorked'] ?? 0}'),
          _kv('Ngày muộn', '${m['totalLateDays'] ?? 0}'),
          _kv('Vắng', '${m['totalAbsentDays'] ?? 0}'),
          _kv('Số giờ', '${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'),
          _kv('Tỷ lệ CC', '${m['attendanceRate'] ?? 0}%',
              color: const Color(0xFF047857)),
        ];
        break;
      case 'late-early':
        header = Text('${m['employeeName'] ?? ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold));
        lines = [
          _kv('${m['employeeCode'] ?? ''} · ${m['departmentName'] ?? ''}', ''),
          _kv('Đi muộn',
              '${m['lateCount'] ?? 0} lần / ${m['totalLateMinutes'] ?? 0} phút',
              color: Colors.red),
          _kv('Về sớm',
              '${m['earlyLeaveCount'] ?? 0} lần / ${m['totalEarlyMinutes'] ?? 0} phút',
              color: Colors.amber.shade700),
        ];
        break;
      case 'department':
        header = Text('${m['departmentName'] ?? ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold));
        lines = [
          _kv('Số NV', '${m['employeeCount'] ?? 0}'),
          _kv('Tổng CC', '${m['totalAttendance'] ?? 0}'),
          _kv('Đi muộn', '${m['totalLateCount'] ?? 0}'),
          _kv('Tổng giờ',
              '${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'),
          _kv('TB giờ/ngày',
              '${(m['averageWorkedHoursPerDay'] ?? 0).toStringAsFixed(1)}h'),
          _kv('Tỷ lệ CC', '${m['attendanceRate'] ?? 0}%',
              color: const Color(0xFF047857)),
        ];
        break;
      case 'overtime':
        header = Text('${m['employeeName'] ?? ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold));
        lines = [
          _kv('${m['employeeCode'] ?? ''} · ${m['departmentName'] ?? ''}', ''),
          _kv('Ngày tăng ca', '${m['overtimeDays'] ?? 0}'),
          _kv('Phút', '${m['totalOvertimeMinutes'] ?? 0}'),
          _kv('Giờ', '${(m['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}h',
              color: Colors.deepOrange),
        ];
        break;
      case 'leave':
        header = Text('${m['employeeName'] ?? ''}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold));
        lines = [
          _kv('${m['employeeCode'] ?? ''} · ${m['departmentName'] ?? ''}', ''),
          _kv('Loại', '${m['leaveType'] ?? ''}'),
          _kv('Tổng / Đã dùng / Còn',
              '${m['totalDays'] ?? 0} / ${m['usedDays'] ?? 0} / ${m['remainingDays'] ?? 0}'),
        ];
        break;
      default:
        header = const SizedBox();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: Text('${idx + 1}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A5F))),
            ),
            const SizedBox(width: 8),
            Expanded(child: header),
          ]),
          const Divider(height: 14),
          ...lines,
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {Color? color}) {
    if (v.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(k,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF71717A))),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
              child: Text(k,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                  overflow: TextOverflow.ellipsis)),
          Text(v,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  List<DataColumn> _columns() {
    DataColumn col(String name, {String? sortKey}) {
      return DataColumn(
        label: Expanded(child: Text(name, textAlign: TextAlign.center)),
        onSort: sortKey == null
            ? null
            : (_, asc) {
                setState(() {
                  _sortColumn = sortKey;
                  _sortAscending = asc;
                });
              },
      );
    }

    switch (_reportType) {
      case 'daily':
        return [
          col('STT'),
          col('Mã NV', sortKey: 'employeeCode'),
          col('Họ tên', sortKey: 'employeeName'),
          col('Phòng ban', sortKey: 'departmentName'),
          col('Giờ vào', sortKey: 'checkInTime'),
          col('Giờ ra', sortKey: 'checkOutTime'),
          col('Đi muộn', sortKey: 'lateMinutes'),
          col('Về sớm', sortKey: 'earlyLeaveMinutes'),
          col('Trạng thái'),
        ];
      case 'monthly':
        return [
          col('STT'),
          col('Mã NV', sortKey: 'employeeCode'),
          col('Họ tên', sortKey: 'employeeName'),
          col('Phòng ban', sortKey: 'departmentName'),
          col('Ngày làm', sortKey: 'totalDaysWorked'),
          col('Ngày muộn', sortKey: 'totalLateDays'),
          col('Ngày nghỉ', sortKey: 'totalLeaveDays'),
          col('Ngày vắng', sortKey: 'totalAbsentDays'),
          col('Số giờ', sortKey: 'totalWorkedHours'),
          col('Tỷ lệ CC', sortKey: 'attendanceRate'),
        ];
      case 'late-early':
        return [
          col('STT'),
          col('Mã NV', sortKey: 'employeeCode'),
          col('Họ tên', sortKey: 'employeeName'),
          col('Phòng ban', sortKey: 'departmentName'),
          col('Lần muộn', sortKey: 'lateCount'),
          col('Phút muộn', sortKey: 'totalLateMinutes'),
          col('Lần về sớm', sortKey: 'earlyLeaveCount'),
          col('Phút về sớm', sortKey: 'totalEarlyMinutes'),
        ];
      case 'department':
        return [
          col('STT'),
          col('Phòng ban', sortKey: 'departmentName'),
          col('Số NV', sortKey: 'employeeCount'),
          col('Tổng CC', sortKey: 'totalAttendance'),
          col('Đi muộn', sortKey: 'totalLateCount'),
          col('Tổng giờ', sortKey: 'totalWorkedHours'),
          col('TB giờ/ngày', sortKey: 'averageWorkedHoursPerDay'),
          col('Tỷ lệ CC', sortKey: 'attendanceRate'),
        ];
      case 'overtime':
        return [
          col('STT'),
          col('Mã NV', sortKey: 'employeeCode'),
          col('Họ tên', sortKey: 'employeeName'),
          col('Phòng ban', sortKey: 'departmentName'),
          col('Ngày tăng ca', sortKey: 'overtimeDays'),
          col('Phút tăng ca', sortKey: 'totalOvertimeMinutes'),
          col('Giờ tăng ca', sortKey: 'totalOvertimeHours'),
        ];
      case 'leave':
        return [
          col('STT'),
          col('Mã NV', sortKey: 'employeeCode'),
          col('Họ tên', sortKey: 'employeeName'),
          col('Phòng ban', sortKey: 'departmentName'),
          col('Loại nghỉ', sortKey: 'leaveType'),
          col('Tổng ngày', sortKey: 'totalDays'),
          col('Đã dùng', sortKey: 'usedDays'),
          col('Còn lại', sortKey: 'remainingDays'),
        ];
      default:
        return [];
    }
  }

  DataRow _row(int idx, dynamic item) {
    final m = item as Map<String, dynamic>;
    DataCell c(dynamic v) => DataCell(Center(child: Text(v?.toString() ?? '')));
    switch (_reportType) {
      case 'daily':
        return DataRow(cells: [
          c(idx + 1),
          c(m['employeeCode']),
          c(m['employeeName']),
          c(m['departmentName']),
          c(_fmtTime(m['checkInTime'])),
          c(_fmtTime(m['checkOutTime'])),
          c('${m['lateMinutes'] ?? 0}p'),
          c('${m['earlyLeaveMinutes'] ?? 0}p'),
          DataCell(Center(child: _statusChip(m['status'] ?? ''))),
        ]);
      case 'monthly':
        return DataRow(cells: [
          c(idx + 1),
          c(m['employeeCode']),
          c(m['employeeName']),
          c(m['departmentName']),
          c('${m['totalDaysWorked'] ?? 0}'),
          c('${m['totalLateDays'] ?? 0}'),
          c('${m['totalLeaveDays'] ?? 0}'),
          c('${m['totalAbsentDays'] ?? 0}'),
          c('${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'),
          c('${m['attendanceRate'] ?? 0}%'),
        ]);
      case 'late-early':
        return DataRow(cells: [
          c(idx + 1),
          c(m['employeeCode']),
          c(m['employeeName']),
          c(m['departmentName']),
          c('${m['lateCount'] ?? 0}'),
          c('${m['totalLateMinutes'] ?? 0}'),
          c('${m['earlyLeaveCount'] ?? 0}'),
          c('${m['totalEarlyMinutes'] ?? 0}'),
        ]);
      case 'department':
        return DataRow(cells: [
          c(idx + 1),
          c(m['departmentName']),
          c('${m['employeeCount'] ?? 0}'),
          c('${m['totalAttendance'] ?? 0}'),
          c('${m['totalLateCount'] ?? 0}'),
          c('${(m['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'),
          c('${(m['averageWorkedHoursPerDay'] ?? 0).toStringAsFixed(1)}h'),
          c('${m['attendanceRate'] ?? 0}%'),
        ]);
      case 'overtime':
        return DataRow(cells: [
          c(idx + 1),
          c(m['employeeCode']),
          c(m['employeeName']),
          c(m['departmentName']),
          c('${m['overtimeDays'] ?? 0}'),
          c('${m['totalOvertimeMinutes'] ?? 0}'),
          c('${(m['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}h'),
        ]);
      case 'leave':
        return DataRow(cells: [
          c(idx + 1),
          c(m['employeeCode']),
          c(m['employeeName']),
          c(m['departmentName']),
          c(m['leaveType']),
          c('${m['totalDays'] ?? 0}'),
          c('${m['usedDays'] ?? 0}'),
          c('${m['remainingDays'] ?? 0}'),
        ]);
      default:
        return const DataRow(cells: []);
    }
  }

  String _fmtTime(dynamic iso) {
    if (iso == null || iso.toString().isEmpty) return '--:--';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(iso.toString()));
    } catch (_) {
      return '--:--';
    }
  }

  Widget _statusChip(String status) {
    Color color;
    if (status.contains('Đúng giờ')) {
      color = Colors.green;
    } else if (status.contains('muộn') || status.contains('Muộn')) {
      color = Colors.orange;
    } else if (status.contains('sớm') || status.contains('Sớm')) {
      color = Colors.amber;
    } else if (status.contains('Vắng')) {
      color = Colors.red;
    } else if (status.contains('phép') || status.contains('Nghỉ')) {
      color = Colors.purple;
    } else {
      color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8)),
      child: Text(status,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E4E7))),
      child: Center(
        child: Column(children: [
          Icon(Icons.assessment_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('Chọn loại báo cáo và nhấn "Tạo báo cáo"',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
        ]),
      ),
    );
  }
}

class _CardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _CardData(this.title, this.value, this.icon, this.color);
}

class _Preset {
  final String label;
  final VoidCallback onTap;
  const _Preset(this.label, this.onTap);
}
