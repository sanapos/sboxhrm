import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../widgets/loading_widget.dart';
import '../utils/responsive_helper.dart';
import '../utils/file_saver.dart' as file_saver;
import 'dart:convert';
import '../widgets/notification_overlay.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  
  bool _isLoading = false;
  String _selectedReportType = 'daily';
  DateTime _selectedDate = DateTime.now();
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  
  Map<String, dynamic>? _reportData;
  int _currentPage = 1;
  final int _pageSize = 50;

  final List<Map<String, dynamic>> _reportTypes = [
    {'id': 'daily', 'name': 'Báo cáo hàng ngày', 'icon': Icons.today},
    {'id': 'monthly', 'name': 'Báo cáo hàng tháng', 'icon': Icons.calendar_month},
    {'id': 'late-early', 'name': 'Báo cáo đi muộn/về sớm', 'icon': Icons.schedule},
    {'id': 'department', 'name': 'Tổng hợp phòng ban', 'icon': Icons.business},
    {'id': 'overtime', 'name': 'Báo cáo tăng ca', 'icon': Icons.more_time},
    {'id': 'leave', 'name': 'Báo cáo nghỉ phép', 'icon': Icons.event_busy},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReport() async {
    setState(() => _isLoading = true);
    
    try {
      Map<String, dynamic> result;
      
      switch (_selectedReportType) {
        case 'daily':
          result = await _apiService.getDailyAttendanceReport(date: _selectedDate);
          break;
        case 'monthly':
          result = await _apiService.getMonthlyAttendanceReport(
            year: _selectedYear,
            month: _selectedMonth,
          );
          break;
        case 'late-early':
          result = await _apiService.getLateEarlyReport(
            startDate: _startDate,
            endDate: _endDate,
          );
          break;
        case 'department':
          result = await _apiService.getDepartmentSummaryReport(
            year: _selectedYear,
            month: _selectedMonth,
          );
          break;
        case 'overtime':
          result = await _apiService.getOvertimeReport(
            startDate: _startDate,
            endDate: _endDate,
          );
          break;
        case 'leave':
          result = await _apiService.getLeaveReport(
            startDate: _startDate,
            endDate: _endDate,
          );
          break;
        default:
          result = {'isSuccess': false, 'message': 'Unknown report type'};
      }
      
      if (result['isSuccess'] == true && mounted) {
        setState(() {
          _reportData = result['data'];
        });
      } else if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi tải báo cáo');
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _exportReport() async {
    setState(() => _isLoading = true);
    
    try {
      String? csvData;
      String fileName;
      
      switch (_selectedReportType) {
        case 'daily':
          final result = await _apiService.exportDailyReport(date: _selectedDate);
          csvData = result['data']?.toString();
          fileName = 'bao_cao_hang_ngay_${DateFormat('yyyyMMdd').format(_selectedDate)}.csv';
          break;
        case 'monthly':
          final result = await _apiService.exportMonthlyReport(year: _selectedYear, month: _selectedMonth);
          csvData = result['data']?.toString();
          fileName = 'bao_cao_thang_${_selectedYear}_$_selectedMonth.csv';
          break;
        case 'late-early':
          final result = await _apiService.exportLateEarlyReport(startDate: _startDate, endDate: _endDate);
          csvData = result['data']?.toString();
          fileName = 'bao_cao_di_muon_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.csv';
          break;
        case 'department':
          // Department summary doesn't have CSV export endpoint, generate from loaded data
          if (_reportData != null) {
            final items = (_reportData!['items'] as List?) ?? [];
            final buf = StringBuffer();
            buf.writeln('STT,Phòng ban,Số NV,Tổng chấm công,Số lần muộn,Tổng giờ làm,TB giờ/ngày,Tỷ lệ CC (%)');
            for (var i = 0; i < items.length; i++) {
              final item = items[i] as Map<String, dynamic>;
              buf.writeln('${i + 1},"${item['departmentName'] ?? ''}",${item['employeeCount'] ?? 0},${item['totalAttendance'] ?? 0},${item['totalLateCount'] ?? 0},${(item['totalWorkedHours'] ?? 0).toStringAsFixed(1)},${(item['averageWorkedHoursPerDay'] ?? 0).toStringAsFixed(1)},${item['attendanceRate'] ?? 0}');
            }
            csvData = buf.toString();
          }
          fileName = 'bao_cao_phong_ban_${_selectedYear}_$_selectedMonth.csv';
          break;
        case 'overtime':
          if (_reportData != null) {
            final items = (_reportData!['items'] as List?) ?? [];
            final buf = StringBuffer();
            buf.writeln('STT,Mã NV,Họ tên,Phòng ban,Số ngày tăng ca,Tổng phút tăng ca,Tổng giờ tăng ca');
            for (var i = 0; i < items.length; i++) {
              final item = items[i] as Map<String, dynamic>;
              buf.writeln('${i + 1},"${item['employeeCode'] ?? ''}","${item['employeeName'] ?? ''}","${item['departmentName'] ?? ''}",${item['overtimeDays'] ?? 0},${item['totalOvertimeMinutes'] ?? 0},${item['totalOvertimeHours'] ?? 0}');
            }
            csvData = buf.toString();
          }
          fileName = 'bao_cao_tang_ca_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.csv';
          break;
        case 'leave':
          if (_reportData != null) {
            final items = (_reportData!['items'] as List?) ?? [];
            final buf = StringBuffer();
            buf.writeln('STT,Mã NV,Họ tên,Phòng ban,Loại nghỉ,Ngày bắt đầu,Ngày kết thúc,Số ngày,Trạng thái');
            for (var i = 0; i < items.length; i++) {
              final item = items[i] as Map<String, dynamic>;
              buf.writeln('${i + 1},"${item['employeeCode'] ?? ''}","${item['employeeName'] ?? ''}","${item['departmentName'] ?? ''}","${item['leaveType'] ?? ''}","${item['startDate'] ?? ''}","${item['endDate'] ?? ''}",${item['totalDays'] ?? 0},"${item['status'] ?? ''}"');
            }
            csvData = buf.toString();
          }
          fileName = 'bao_cao_nghi_phep_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.csv';
          break;
        default:
          csvData = null;
          fileName = 'report.csv';
      }
      
      if (csvData != null && mounted) {
        _downloadFile(csvData, fileName);
        NotificationOverlayManager().showSuccess(title: 'Xuất báo cáo', message: 'Đã xuất báo cáo thành công');
      } else if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể xuất báo cáo');
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xuất báo cáo: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _downloadFile(String content, String fileName) {
    final bytes = utf8.encode(content);
    file_saver.saveFileBytes(bytes, fileName, 'text/csv;charset=utf-8');
  }

  void _downloadExcelFile(List<int> bytes, String fileName) {
    file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  Future<void> _exportExcel() async {
    setState(() => _isLoading = true);
    
    try {
      List<int>? excelData;
      String fileName;
      
      switch (_selectedReportType) {
        case 'daily':
          final result = await _apiService.exportDailyReportExcel(date: _selectedDate);
          excelData = (result['data'] as List?)?.cast<int>();
          fileName = 'bao_cao_hang_ngay_${DateFormat('yyyyMMdd').format(_selectedDate)}.xlsx';
          break;
        case 'monthly':
          final result = await _apiService.exportMonthlyReportExcel(year: _selectedYear, month: _selectedMonth);
          excelData = (result['data'] as List?)?.cast<int>();
          fileName = 'bao_cao_thang_${_selectedYear}_$_selectedMonth.xlsx';
          break;
        case 'late-early':
          final result = await _apiService.exportLateEarlyReportExcel(startDate: _startDate, endDate: _endDate);
          excelData = (result['data'] as List?)?.cast<int>();
          fileName = 'bao_cao_di_muon_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        case 'department':
          final result = await _apiService.exportDepartmentSummaryExcel(year: _selectedYear, month: _selectedMonth);
          excelData = (result['data'] as List?)?.cast<int>();
          fileName = 'bao_cao_phong_ban_${_selectedYear}_$_selectedMonth.xlsx';
          break;
        case 'overtime':
          final result = await _apiService.exportOvertimeReportExcel(startDate: _startDate, endDate: _endDate);
          excelData = (result['data'] as List?)?.cast<int>();
          fileName = 'bao_cao_tang_ca_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        case 'leave':
          final result = await _apiService.exportLeaveReportExcel(startDate: _startDate, endDate: _endDate);
          excelData = (result['data'] as List?)?.cast<int>();
          fileName = 'bao_cao_nghi_phep_${DateFormat('yyyyMMdd').format(_startDate)}_${DateFormat('yyyyMMdd').format(_endDate)}.xlsx';
          break;
        default:
          excelData = null;
          fileName = 'report.xlsx';
      }
      
      if (excelData != null && mounted) {
        _downloadExcelFile(excelData, fileName);
        NotificationOverlayManager().showSuccess(title: 'Xuất Excel', message: 'Đã xuất báo cáo Excel thành công');
      } else if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Không thể xuất báo cáo Excel');
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xuất báo cáo Excel: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header
          _buildHeader(),
          
          // Tabs
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Tạo báo cáo'),
              Tab(text: 'Xem kết quả'),
            ],
            labelColor: Theme.of(context).primaryColor,
            unselectedLabelColor: Colors.grey,
          ),
          
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildReportOptionsTab(),
                _buildReportResultTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.assessment, color: Theme.of(context).primaryColor, size: 24),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Báo cáo chấm công',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_reportData != null) ...[
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _exportReport,
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('CSV', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                      ),
                    ),
                    SizedBox(
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _exportExcel,
                        icon: const Icon(Icons.table_chart, size: 16),
                        label: const Text('Excel', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                      ),
                    ),
                  ],
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () {
                        _loadReport();
                        _tabController.animateTo(1);
                      },
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Tạo báo cáo', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          )
        : Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assessment, color: Theme.of(context).primaryColor, size: 28),
              const SizedBox(width: 12),
              const Text(
                'Báo cáo chấm công',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (_reportData != null) ...[
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _exportReport,
              icon: const Icon(Icons.download),
              label: const Text('Xuất CSV'),
            ),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _exportExcel,
              icon: const Icon(Icons.table_chart),
              label: const Text('Xuất Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
          ElevatedButton.icon(
            onPressed: _isLoading ? null : () {
              _loadReport();
              _tabController.animateTo(1);
            },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Tạo báo cáo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportOptionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report type selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chọn loại báo cáo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: _reportTypes.map((type) {
                      final isSelected = _selectedReportType == type['id'];
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedReportType = type['id'];
                            _reportData = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 180,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                                : Colors.grey.shade100,
                            border: Border.all(
                              color: isSelected 
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey.shade300,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                type['icon'] as IconData,
                                color: isSelected 
                                    ? Theme.of(context).primaryColor
                                    : Colors.grey,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                type['name'] as String,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected 
                                      ? Theme.of(context).primaryColor
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Date/Period selection based on report type
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Thời gian báo cáo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildDateSelector(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    switch (_selectedReportType) {
      case 'daily':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Ngày: '),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              },
            ),
          ],
        );
        
      case 'monthly':
      case 'department':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Tháng: '),
            DropdownButton<int>(
              value: _selectedMonth,
              items: List.generate(12, (i) => i + 1)
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text('Tháng $m'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedMonth = v);
              },
            ),
            const SizedBox(width: 16),
            const Text('Năm: '),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _selectedYear,
              items: List.generate(5, (i) => DateTime.now().year - i)
                  .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _selectedYear = v);
              },
            ),
          ],
        );
        
      case 'late-early':
      case 'overtime':
      case 'leave':
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Từ: '),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(DateFormat('dd/MM/yyyy').format(_startDate)),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _startDate = date);
                }
              },
            ),
            const Text('Đến: '),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text(DateFormat('dd/MM/yyyy').format(_endDate)),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _endDate = date);
                }
              },
            ),
          ],
        );
        
      default:
        return const SizedBox();
    }
  }

  Widget _buildReportResultTab() {
    if (_isLoading) {
      return const LoadingWidget(message: 'Đang tạo báo cáo...');
    }
    
    if (_reportData == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assessment_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Chọn loại báo cáo và nhấn "Tạo báo cáo"',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          _buildSummaryCards(),
          const SizedBox(height: 16),
          
          // Data table
          _buildDataTable(),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    switch (_selectedReportType) {
      case 'daily':
        return _buildDailySummary();
      case 'monthly':
        return _buildMonthlySummary();
      case 'late-early':
        return _buildLateEarlySummary();
      case 'department':
        return _buildDepartmentSummary();
      case 'overtime':
        return _buildOvertimeSummary();
      case 'leave':
        return _buildLeaveSummary();
      default:
        return const SizedBox();
    }
  }

  Widget _buildDailySummary() {
    final data = _reportData!;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard('Tổng nhân viên', '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
        _buildSummaryCard('Có mặt', '${data['present'] ?? 0}', Icons.check_circle, Colors.green),
        _buildSummaryCard('Đúng giờ', '${data['onTime'] ?? 0}', Icons.thumb_up, Colors.teal),
        _buildSummaryCard('Đi muộn', '${data['late'] ?? 0}', Icons.schedule_rounded, Colors.orange),
        _buildSummaryCard('Về sớm', '${data['earlyLeave'] ?? 0}', Icons.exit_to_app, Colors.amber),
        _buildSummaryCard('Vắng mặt', '${data['absent'] ?? 0}', Icons.person_off, Colors.red),
        _buildSummaryCard('Nghỉ phép', '${data['onLeave'] ?? 0}', Icons.beach_access, Colors.purple),
        _buildSummaryCard('Tỷ lệ CC', '${data['attendanceRate'] ?? 0}%', Icons.percent, Colors.indigo),
      ],
    );
  }

  Widget _buildMonthlySummary() {
    final data = _reportData!;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard('Tổng nhân viên', '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
        _buildSummaryCard('Ngày làm việc', '${data['workingDays'] ?? 0}', Icons.calendar_today, Colors.green),
        _buildSummaryCard('Tháng', '${data['month']}/${data['year']}', Icons.date_range, Colors.teal),
      ],
    );
  }

  Widget _buildLateEarlySummary() {
    final data = _reportData!;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard('Tổng nhân viên', '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
        _buildSummaryCard('NV vi phạm', '${data['employeesWithIssues'] ?? 0}', Icons.warning, Colors.orange),
        _buildSummaryCard('Tổng lần muộn', '${data['totalLateCount'] ?? 0}', Icons.schedule, Colors.red),
        _buildSummaryCard('Tổng phút muộn', '${data['totalLateMinutes'] ?? 0}', Icons.timer, Colors.red.shade700),
        _buildSummaryCard('Tổng lần về sớm', '${data['totalEarlyLeaveCount'] ?? 0}', Icons.exit_to_app, Colors.amber),
        _buildSummaryCard('Tổng phút về sớm', '${data['totalEarlyMinutes'] ?? 0}', Icons.timer_off, Colors.amber.shade700),
      ],
    );
  }

  Widget _buildDepartmentSummary() {
    final data = _reportData!;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard('Tổng phòng ban', '${data['totalDepartments'] ?? 0}', Icons.business, Colors.blue),
        _buildSummaryCard('Tổng nhân viên', '${data['totalEmployees'] ?? 0}', Icons.people, Colors.green),
        _buildSummaryCard('Ngày làm việc', '${data['workingDays'] ?? 0}', Icons.calendar_today, Colors.teal),
        _buildSummaryCard('Tháng', '${data['month']}/${data['year']}', Icons.date_range, Colors.purple),
      ],
    );
  }

  Widget _buildOvertimeSummary() {
    final data = _reportData!;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard('Tổng nhân viên', '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
        _buildSummaryCard('NV tăng ca', '${data['employeesWithOvertime'] ?? 0}', Icons.person, Colors.orange),
        _buildSummaryCard('Tổng phút tăng ca', '${data['totalOvertimeMinutes'] ?? 0}', Icons.timer, Colors.red),
        _buildSummaryCard('Tổng giờ tăng ca', '${(data['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}h', Icons.more_time, Colors.deepOrange),
      ],
    );
  }

  Widget _buildLeaveSummary() {
    final data = _reportData!;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildSummaryCard('Tổng nhân viên', '${data['totalEmployees'] ?? 0}', Icons.people, Colors.blue),
        _buildSummaryCard('NV nghỉ phép', '${data['employeesWithLeave'] ?? 0}', Icons.person_off, Colors.orange),
        _buildSummaryCard('Tổng đơn nghỉ', '${data['totalLeaveRequests'] ?? 0}', Icons.description, Colors.purple),
        _buildSummaryCard('Tổng ngày nghỉ', '${data['totalLeaveDays'] ?? 0}', Icons.event_busy, Colors.red),
        _buildSummaryCard('Đã duyệt', '${data['approvedCount'] ?? 0}', Icons.check_circle, Colors.green),
        _buildSummaryCard('Từ chối', '${data['rejectedCount'] ?? 0}', Icons.cancel, Colors.red.shade700),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    final items = (_reportData?['items'] as List?) ?? [];
    
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: Text('Không có dữ liệu'),
          ),
        ),
      );
    }

    final totalPages = (items.length / _pageSize).ceil();
    if (_currentPage > totalPages && totalPages > 0) _currentPage = totalPages;
    final startIdx = (_currentPage - 1) * _pageSize;
    final endIdx = (startIdx + _pageSize).clamp(0, items.length);
    final pageItems = items.sublist(startIdx, endIdx);

    return Card(
      child: Column(
        children: [
          SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: _buildTableColumns(),
                rows: _buildTableRows(pageItems, startIdx),
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                headingTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey.shade800),
              ),
            ),
          ),
          if (totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Hiển thị ${startIdx + 1}-$endIdx / ${items.length}', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.first_page, size: 20), onPressed: _currentPage > 1 ? () => setState(() => _currentPage = 1) : null),
                      IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('$_currentPage / $totalPages', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: _currentPage < totalPages ? () => setState(() => _currentPage++) : null),
                      IconButton(icon: const Icon(Icons.last_page, size: 20), onPressed: _currentPage < totalPages ? () => setState(() => _currentPage = totalPages) : null),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<DataColumn> _buildTableColumns() {
    switch (_selectedReportType) {
      case 'daily':
        return const [
          DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Họ tên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Phòng ban', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Giờ vào', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Giờ ra', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Đi muộn', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Về sớm', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Trạng thái', textAlign: TextAlign.center))),
        ];
        
      case 'monthly':
        return const [
          DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Họ tên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Phòng ban', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Ngày làm', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Ngày muộn', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Ngày nghỉ', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Ngày vắng', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Số giờ', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tỷ lệ chấm công', textAlign: TextAlign.center))),
        ];
        
      case 'late-early':
        return const [
          DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Họ tên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Phòng ban', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Số lần muộn', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng phút muộn', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Số lần về sớm', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng phút về sớm', textAlign: TextAlign.center))),
        ];
        
      case 'department':
        return const [
          DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Phòng ban', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Số nhân viên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng chấm công', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng đi muộn', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng giờ làm', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Trung bình giờ/ngày', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tỷ lệ chấm công', textAlign: TextAlign.center))),
        ];
        
      case 'overtime':
        return const [
          DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Họ tên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Phòng ban', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Số ngày tăng ca', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng phút tăng ca', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng giờ tăng ca', textAlign: TextAlign.center))),
        ];
        
      case 'leave':
        return const [
          DataColumn(label: Expanded(child: Text('STT', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Họ tên', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Phòng ban', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Loại nghỉ', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Tổng ngày nghỉ', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Đã dùng', textAlign: TextAlign.center))),
          DataColumn(label: Expanded(child: Text('Còn lại', textAlign: TextAlign.center))),
        ];
        
      default:
        return [];
    }
  }

  List<DataRow> _buildTableRows(List items, int startIdx) {
    return items.asMap().entries.map((entry) {
      final index = entry.key;
      final globalIdx = startIdx + index;
      final item = entry.value as Map<String, dynamic>;
      
      switch (_selectedReportType) {
        case 'daily':
          return DataRow(cells: [
            DataCell(Center(child: Text('${globalIdx + 1}'))),
            DataCell(Center(child: Text(item['employeeCode'] ?? ''))),
            DataCell(Center(child: Text(item['employeeName'] ?? ''))),
            DataCell(Center(child: Text(item['departmentName'] ?? ''))),
            DataCell(Center(child: Text(_formatTime(item['checkInTime'])))),
            DataCell(Center(child: Text(_formatTime(item['checkOutTime'])))),
            DataCell(Center(child: Text('${item['lateMinutes'] ?? 0} phút'))),
            DataCell(Center(child: Text('${item['earlyLeaveMinutes'] ?? 0} phút'))),
            DataCell(Center(child: _buildStatusChip(item['status'] ?? ''))),
          ]);
          
        case 'monthly':
          return DataRow(cells: [
            DataCell(Center(child: Text('${globalIdx + 1}'))),
            DataCell(Center(child: Text(item['employeeCode'] ?? ''))),
            DataCell(Center(child: Text(item['employeeName'] ?? ''))),
            DataCell(Center(child: Text(item['departmentName'] ?? ''))),
            DataCell(Center(child: Text('${item['totalDaysWorked'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalLateDays'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalLeaveDays'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalAbsentDays'] ?? 0}'))),
            DataCell(Center(child: Text('${(item['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'))),
            DataCell(Center(child: Text('${item['attendanceRate'] ?? 0}%'))),
          ]);
          
        case 'late-early':
          return DataRow(cells: [
            DataCell(Center(child: Text('${globalIdx + 1}'))),
            DataCell(Center(child: Text(item['employeeCode'] ?? ''))),
            DataCell(Center(child: Text(item['employeeName'] ?? ''))),
            DataCell(Center(child: Text(item['departmentName'] ?? ''))),
            DataCell(Center(child: Text('${item['lateCount'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalLateMinutes'] ?? 0}'))),
            DataCell(Center(child: Text('${item['earlyLeaveCount'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalEarlyMinutes'] ?? 0}'))),
          ]);
          
        case 'department':
          return DataRow(cells: [
            DataCell(Center(child: Text('${globalIdx + 1}'))),
            DataCell(Center(child: Text(item['departmentName'] ?? ''))),
            DataCell(Center(child: Text('${item['employeeCount'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalAttendance'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalLateCount'] ?? 0}'))),
            DataCell(Center(child: Text('${(item['totalWorkedHours'] ?? 0).toStringAsFixed(1)}h'))),
            DataCell(Center(child: Text('${(item['averageWorkedHoursPerDay'] ?? 0).toStringAsFixed(1)}h'))),
            DataCell(Center(child: Text('${item['attendanceRate'] ?? 0}%'))),
          ]);
          
        case 'overtime':
          return DataRow(cells: [
            DataCell(Center(child: Text('${globalIdx + 1}'))),
            DataCell(Center(child: Text(item['employeeCode'] ?? ''))),
            DataCell(Center(child: Text(item['employeeName'] ?? ''))),
            DataCell(Center(child: Text(item['departmentName'] ?? ''))),
            DataCell(Center(child: Text('${item['overtimeDays'] ?? 0}'))),
            DataCell(Center(child: Text('${item['totalOvertimeMinutes'] ?? 0}'))),
            DataCell(Center(child: Text('${(item['totalOvertimeHours'] ?? 0).toStringAsFixed(1)}h'))),
          ]);
          
        case 'leave':
          return DataRow(cells: [
            DataCell(Center(child: Text('${globalIdx + 1}'))),
            DataCell(Center(child: Text(item['employeeCode'] ?? ''))),
            DataCell(Center(child: Text(item['employeeName'] ?? ''))),
            DataCell(Center(child: Text(item['departmentName'] ?? ''))),
            DataCell(Center(child: Text(item['leaveType'] ?? ''))),
            DataCell(Center(child: Text('${item['totalDays'] ?? 0}'))),
            DataCell(Center(child: Text('${item['usedDays'] ?? 0}'))),
            DataCell(Center(child: Text('${item['remainingDays'] ?? 0}'))),
          ]);
          
        default:
          return const DataRow(cells: []);
      }
    }).toList();
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '--:--';
    try {
      final dt = DateTime.parse(isoTime);
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return '--:--';
    }
  }

  Widget _buildStatusChip(String status) {
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
    } else if (status.contains('Có mặt')) {
      color = Colors.teal;
    } else {
      color = Colors.grey;
    }
    
    return Chip(
      label: Text(
        status,
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
